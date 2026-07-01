// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";
import "../common/JsonLibrary.sol";
import "../common/ParameterLibrary.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @notice Generates Nest nOPAL DEPOSIT ops for SV4 (approve USDC + deposit via NestVaultPredicateProxy).
/// @dev Nest = Veda BoringVault + Predicate. The deposit calldata embeds a time-bound Predicate
///      signature fetched from api.nest.credit at runtime (POST .../mint/build-tx). The bot/curator
///      submits exactly that API calldata through the subvault.
///
///      LENGTH-PINNED LEAF: the deposit leaf is built for the API's stable 644-byte calldata
///      (selector 0xa46ea103 + 5 head words + 15 tail words). It LOCKS
///      selector + _depositAsset(USDC) + _recipient(subvault) + _vault + the PredicateMessage offset,
///      and WILDCARDS _depositAmount + the entire PredicateMessage tail (taskId, expireByTime,
///      signerAddresses, signatures) — the predicate proxy + PredicateManager verify the signature
///      on-chain, so our leaf only pins who/where/asset/recipient/vault. If Nest ever changes the
///      predicate message shape (extra signer, different taskId length) the 644-byte length changes
///      and THIS LEAF MUST BE REGENERATED. The bot should assert the API calldata is 644 bytes.
///
///      Redeem/claim (AtomicQueue requestRedeem + claim) is NOT included yet — see follow-up.
///
/// Run: forge script scripts/ethereum/GenerateNestJSON.s.sol --sig "generateProdSv4()" \
///        --rpc-url http://localhost:8545 --via-ir
contract GenerateNestJSON is Script, Test {
    using ParameterLibrary for ParameterLibrary.Parameter[];

    address public constant prodCurator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;
    address public constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;

    // deposit(address _depositAsset, uint256 _depositAmount, address _recipient, address _vault,
    //         (string taskId, uint256 expireByTime, address[] signerAddresses, bytes[] signatures))
    bytes4 constant DEPOSIT_SELECTOR = 0xa46ea103;

    // ABI for the deposit description (not in ABILibrary's fixed table).
    string constant APPROVE_ABI =
        '{"inputs":[{"internalType":"address","name":"spender","type":"address"},{"internalType":"uint256","name":"amount","type":"uint256"}],"name":"approve","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"nonpayable","type":"function"}';

    string constant REQUEST_REDEEM_ABI =
        '{"inputs":[{"internalType":"uint256","name":"shares","type":"uint256"},{"internalType":"address","name":"controller","type":"address"},{"internalType":"address","name":"owner","type":"address"}],"name":"requestRedeem","outputs":[{"internalType":"uint256","name":"requestId","type":"uint256"}],"stateMutability":"nonpayable","type":"function"}';
    string constant REDEEM_ABI =
        '{"inputs":[{"internalType":"uint256","name":"shares","type":"uint256"},{"internalType":"address","name":"receiver","type":"address"},{"internalType":"address","name":"owner","type":"address"}],"name":"redeem","outputs":[{"internalType":"uint256","name":"assets","type":"uint256"}],"stateMutability":"nonpayable","type":"function"}';
    string constant UPDATE_REDEEM_ABI =
        '{"inputs":[{"internalType":"uint256","name":"shares","type":"uint256"},{"internalType":"address","name":"controller","type":"address"},{"internalType":"address","name":"owner","type":"address"}],"name":"updateRedeem","outputs":[],"stateMutability":"nonpayable","type":"function"}';

    string constant NEST_DEPOSIT_ABI =
        '{"inputs":[{"internalType":"address","name":"_depositAsset","type":"address"},{"internalType":"uint256","name":"_depositAmount","type":"uint256"},{"internalType":"address","name":"_recipient","type":"address"},{"internalType":"address","name":"_vault","type":"address"},{"components":[{"internalType":"string","name":"taskId","type":"string"},{"internalType":"uint256","name":"expireByTime","type":"uint256"},{"internalType":"address[]","name":"signerAddresses","type":"address[]"},{"internalType":"bytes[]","name":"signatures","type":"bytes[]"}],"internalType":"struct PredicateMessage","name":"_predicateMessage","type":"tuple"}],"name":"deposit","outputs":[{"internalType":"uint256","name":"_shares","type":"uint256"}],"stateMutability":"nonpayable","type":"function"}';

    function generateProdSv4() public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(4);
        require(subvault != address(0), "subvault not found");
        _generate("prod/tqETH/sv4-nest", prodCurator, subvault);
    }

    function _generate(string memory title, address curator, address subvault) internal {
        BitmaskVerifier bitmaskVerifier = Constants.protocolDeployment().bitmaskVerifier;

        // 2 deposit (USDC, predicate) + 4 redeem per asset (USDC vault, USDT vault) = 10 ops.
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](10);
        string[] memory descriptions = new string[](10);

        // ---- 1. approve USDC -> NestVaultPredicateProxy (spender locked, amount any) ----
        leaves[0] = ProofLibrary.makeVerificationPayload(
            bitmaskVerifier,
            curator,
            Constants.USDC,
            0,
            abi.encodeCall(IERC20.approve, (Constants.NEST_PREDICATE_PROXY, 0)),
            ProofLibrary.makeBitmask(
                true, true, true, true, abi.encodeCall(IERC20.approve, (address(type(uint160).max), 0))
            )
        );
        {
            ParameterLibrary.Parameter[] memory inner = new ParameterLibrary.Parameter[](0);
            inner = inner.add("to", Strings.toHexString(Constants.NEST_PREDICATE_PROXY)).addAny("amount");
            descriptions[0] = JsonLibrary.toJson(
                "IERC20(USDC).approve(NestVaultPredicateProxy, anyAmount)",
                APPROVE_ABI,
                ParameterLibrary.build(Strings.toHexString(curator), Strings.toHexString(Constants.USDC), "0"),
                inner
            );
        }

        // ---- 2. NestVaultPredicateProxy.deposit(USDC, anyAmount, subvault, NEST_OPAL_VAULT, <predicate wildcard>) ----
        // 644-byte calldata = 4 (selector) + 5 head words (160) + 15 tail words (480).
        // LOCK: selector + asset + recipient + vault + predicate-offset.  WILDCARD: amount + tail.
        bytes memory depositData = abi.encodePacked(
            DEPOSIT_SELECTOR,
            bytes32(uint256(uint160(Constants.USDC))), // _depositAsset (LOCK)
            bytes32(uint256(0)), // _depositAmount (wildcard)
            bytes32(uint256(uint160(subvault))), // _recipient (LOCK)
            bytes32(uint256(uint160(Constants.NEST_OPAL_VAULT))), // _vault (LOCK)
            bytes32(uint256(0xa0)), // offset to PredicateMessage (LOCK)
            new bytes(480) // PredicateMessage tail (wildcard)
        );
        bytes memory maskData = abi.encodePacked(
            bytes4(0), // selector (makeBitmask forces to 0xffffffff)
            bytes32(type(uint256).max), // _depositAsset LOCK
            bytes32(uint256(0)), // _depositAmount wildcard
            bytes32(type(uint256).max), // _recipient LOCK
            bytes32(type(uint256).max), // _vault LOCK
            bytes32(type(uint256).max), // offset LOCK
            new bytes(480) // tail wildcard
        );
        leaves[1] = ProofLibrary.makeVerificationPayload(
            bitmaskVerifier,
            curator,
            Constants.NEST_PREDICATE_PROXY,
            0,
            depositData,
            ProofLibrary.makeBitmask(true, true, true, true, maskData)
        );
        {
            ParameterLibrary.Parameter[] memory inner = new ParameterLibrary.Parameter[](0);
            inner = inner.add("_depositAsset", Strings.toHexString(Constants.USDC)).addAny("_depositAmount").add(
                "_recipient", Strings.toHexString(subvault)
            ).add("_vault", Strings.toHexString(Constants.NEST_OPAL_VAULT)).addAny("_predicateMessage");
            descriptions[1] = JsonLibrary.toJson(
                "NestVaultPredicateProxy.deposit(USDC, anyAmount, subvault4, nOPAL, anyPredicateMessage)",
                NEST_DEPOSIT_ABI,
                ParameterLibrary.build(
                    Strings.toHexString(curator), Strings.toHexString(Constants.NEST_PREDICATE_PROXY), "0"
                ),
                inner
            );
        }

        // ---- redeem legs (no predicate): approve + requestRedeem + redeem(claim) + updateRedeem, per asset ----
        uint256 idx = 2;
        idx = _addRedeemLeg(bitmaskVerifier, curator, subvault, Constants.NEST_OPAL_VAULT, "USDC", leaves, descriptions, idx);
        idx = _addRedeemLeg(bitmaskVerifier, curator, subvault, Constants.NEST_OPAL_VAULT_USDT, "USDT", leaves, descriptions, idx);
        require(idx == 10, "nest: leaf count mismatch");

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        ProofLibrary.storeProofs(title, merkleRoot, leavesWithProofs, descriptions);

        console.log("=== Nest nOPAL deposit+redeem JSON ===");
        console.log("subvault:", subvault);
        console.log("predicateProxy:", Constants.NEST_PREDICATE_PROXY);
        console.log("ops:", leavesWithProofs.length);
        console.log("merkle root:", vm.toString(merkleRoot));
    }

    /// @dev Adds one asset's redeem leg (no predicate): approve(nOPAL->vault) + requestRedeem + redeem + updateRedeem.
    function _addRedeemLeg(
        BitmaskVerifier bmv,
        address curator,
        address subvault,
        address vault,
        string memory vaultName,
        IVerifier.VerificationPayload[] memory leaves,
        string[] memory descriptions,
        uint256 idx
    ) internal view returns (uint256) {
        // a. nOPAL.approve(vault, anyAmount) — spender locked to the NestVault
        leaves[idx] = ProofLibrary.makeVerificationPayload(
            bmv,
            curator,
            Constants.NOPAL,
            0,
            abi.encodeCall(IERC20.approve, (vault, 0)),
            ProofLibrary.makeBitmask(
                true, true, true, true, abi.encodeCall(IERC20.approve, (address(type(uint160).max), 0))
            )
        );
        {
            ParameterLibrary.Parameter[] memory inner = new ParameterLibrary.Parameter[](0);
            inner = inner.add("to", Strings.toHexString(vault)).addAny("amount");
            descriptions[idx] = JsonLibrary.toJson(
                string.concat("IERC20(nOPAL).approve(NestVault[", vaultName, "], anyAmount)"),
                APPROVE_ABI,
                ParameterLibrary.build(Strings.toHexString(curator), Strings.toHexString(Constants.NOPAL), "0"),
                inner
            );
        }
        idx++;

        // b/c/d. requestRedeem / redeem(claim) / updateRedeem — all (uint256 shares, address, address),
        //        shares wildcarded, both addresses locked to the subvault, target locked to the vault.
        idx = _addRedeemFn(
            bmv, curator, subvault, vault, vaultName, "requestRedeem(uint256,address,address)", REQUEST_REDEEM_ABI, "requestRedeem", leaves, descriptions, idx
        );
        idx = _addRedeemFn(
            bmv, curator, subvault, vault, vaultName, "redeem(uint256,address,address)", REDEEM_ABI, "redeem", leaves, descriptions, idx
        );
        idx = _addRedeemFn(
            bmv, curator, subvault, vault, vaultName, "updateRedeem(uint256,address,address)", UPDATE_REDEEM_ABI, "updateRedeem", leaves, descriptions, idx
        );
        return idx;
    }

    /// @dev One (uint256 shares, address, address) NestVault op: shares wildcard, both addresses locked to subvault.
    function _addRedeemFn(
        BitmaskVerifier bmv,
        address curator,
        address subvault,
        address vault,
        string memory vaultName,
        string memory sig,
        string memory abiStr,
        string memory fnName,
        IVerifier.VerificationPayload[] memory leaves,
        string[] memory descriptions,
        uint256 idx
    ) internal view returns (uint256) {
        leaves[idx] = ProofLibrary.makeVerificationPayload(
            bmv,
            curator,
            vault,
            0,
            abi.encodeWithSignature(sig, uint256(0), subvault, subvault),
            ProofLibrary.makeBitmask(
                true,
                true,
                true,
                true,
                abi.encodeWithSignature(sig, uint256(0), address(type(uint160).max), address(type(uint160).max))
            )
        );
        {
            ParameterLibrary.Parameter[] memory inner = new ParameterLibrary.Parameter[](0);
            inner = inner.addAny("shares").add("controller", Strings.toHexString(subvault)).add(
                "owner", Strings.toHexString(subvault)
            );
            descriptions[idx] = JsonLibrary.toJson(
                string.concat("NestVault[", vaultName, "].", fnName, "(anyShares, subvault4, subvault4)"),
                abiStr,
                ParameterLibrary.build(Strings.toHexString(curator), Strings.toHexString(vault), "0"),
                inner
            );
        }
        return idx + 1;
    }
}
