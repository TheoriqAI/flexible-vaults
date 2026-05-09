// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";
import "../common/protocols/CCIPLibrary.sol";
import "../common/ArraysLibrary.sol";

/// @notice Script to generate CCIP bridge operations JSON files
/// @dev Run with: forge script scripts/ethereum/GenerateCCIPBridgeJSON.s.sol --sig "generateProdSv3WstETHToMonad()" --via-ir --rpc-url https://rpc.mevblocker.io
contract GenerateCCIPBridgeJSON is Script, Test {
    address public prodCurator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;
    address public preProdCurator = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec;

    address public constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address public constant VAULT_PREPROD = 0x2669a8B27B6f957ddb92Dc0ebdec1f112E6079E4;

    /// @notice Generate CCIP bridge JSON for preProd SV5 wstETH to Monad
    function generatePreProdSv5WstETHToMonad() public {
        Vault vault = Vault(payable(VAULT_PREPROD));
        address subvault = vault.subvaultAt(5);
        require(subvault != address(0), "Subvault address not set");

        _generateCCIPBridge(
            "preProd/tqETH/sv5-ccipBridge-wstETH-monad",
            preProdCurator,
            subvault,
            Constants.WSTETH,
            Constants.CCIP_ETHEREUM_ROUTER,
            Constants.CCIP_MONAD_CHAIN_SELECTOR,
            0x0C7cb4e1241F4B7Fd65DE59FDE5a6dBFf190fB20,
            Constants.MONAD_VAULT,
            "monad"
        );
    }

    /// @notice Generate CCIP bridge JSON for prod SV3 wstETH to Monad
    function generateProdSv3WstETHToMonad() public {
        generateCCIPBridge(
            3, // subvault index
            Constants.WSTETH,
            Constants.CCIP_ETHEREUM_ROUTER,
            Constants.CCIP_MONAD_CHAIN_SELECTOR,
            0x0C7cb4e1241F4B7Fd65DE59FDE5a6dBFf190fB20, // target subvault on Monad
            Constants.MONAD_VAULT,
            "monad"
        );
    }

    /// @notice Generic CCIP bridge JSON generator for prod vault
    function generateCCIPBridge(
        uint256 subvaultIndex,
        address asset,
        address ccipRouter,
        uint64 targetChainSelector,
        address targetSubvault,
        address dstVault,
        string memory targetChainName
    ) public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(subvaultIndex);
        require(subvault != address(0), "Subvault address not set");

        string memory assetSymbol = IERC20Metadata(asset).symbol();
        string memory title = string(
            abi.encodePacked(
                "prod/tqETH/sv", vm.toString(subvaultIndex),
                "-ccipBridge-", assetSymbol, "-", targetChainName
            )
        );

        _generateCCIPBridge(title, prodCurator, subvault, asset, ccipRouter, targetChainSelector, targetSubvault, dstVault, targetChainName);
    }

    function _generateCCIPBridge(
        string memory title,
        address curator,
        address subvault,
        address asset,
        address ccipRouter,
        uint64 targetChainSelector,
        address targetSubvault,
        address dstVault,
        string memory targetChainName
    ) internal {
        console.log("=== Generating CCIP Bridge Operations JSON ===");
        console.log("Source subvault:", subvault);
        console.log("Asset:", IERC20Metadata(asset).symbol());
        console.log("CCIP Router:", ccipRouter);
        console.log("Target chain selector:", uint256(targetChainSelector));
        console.log("Target subvault:", targetSubvault);
        console.log("");

        CCIPLibrary.Info memory info = CCIPLibrary.Info({
            curator: curator,
            subvault: subvault,
            asset: asset,
            ccipRouter: ccipRouter,
            targetChainSelector: targetChainSelector,
            targetChainReceiver: targetSubvault,
            targetChainName: targetChainName
        });

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](10);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            CCIPLibrary.getCCIPProofs($.bitmaskVerifier, info),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        string[] memory descriptions = new string[](10);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            CCIPLibrary.getCCIPDescriptions(info),
            iterator
        );

        assembly {
            mstore(descriptions, iterator)
        }

        ProofLibrary.storeProofs(title, merkleRoot, leavesWithProofs, descriptions);

        console.log("");
        console.log("=== Generation Complete ===");
        console.log("JSON file:", string(abi.encodePacked("./scripts/jsons/", title, ".json")));
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations:", leavesWithProofs.length);

        _verifyTargetSubvault(dstVault, targetSubvault, targetChainName);
    }

    /// @notice Verify the target address is a subvault of the destination vault
    /// @dev Uses vm.createFork with <CHAIN>_RPC_URL env var, falls back to public RPC.
    function _verifyTargetSubvault(
        address dstVault,
        address targetSubvault,
        string memory chainName
    ) internal {
        string memory rpcUrl = vm.envOr(
            string(abi.encodePacked(_toUpperCase(chainName), "_RPC_URL")),
            _defaultRpc(chainName)
        );

        if (bytes(rpcUrl).length == 0) {
            console.log("WARNING: No RPC for %s, skipping subvault verification", chainName);
            return;
        }

        uint256 currentFork = vm.activeFork();
        uint256 dstFork = vm.createFork(rpcUrl);
        vm.selectFork(dstFork);

        Vault dstVaultContract = Vault(payable(dstVault));
        bool found = false;
        for (uint256 i = 0; i < 20; i++) {
            try dstVaultContract.subvaultAt(i) returns (address sv) {
                if (sv == targetSubvault) {
                    console.log("VERIFIED: target is subvault at index", i, "on", chainName);
                    found = true;
                    break;
                }
            } catch {
                break;
            }
        }
        require(found, "Target address is NOT a subvault of the destination vault");

        vm.selectFork(currentFork);
    }

    function _defaultRpc(string memory chainName) internal pure returns (string memory) {
        if (keccak256(bytes(chainName)) == keccak256("monad")) return "https://rpc.monad.xyz";
        return "";
    }

    function _toUpperCase(string memory str) internal pure returns (string memory) {
        bytes memory bStr = bytes(str);
        bytes memory bUpper = new bytes(bStr.length);
        for (uint256 i = 0; i < bStr.length; i++) {
            if (bStr[i] >= 0x61 && bStr[i] <= 0x7A) {
                bUpper[i] = bytes1(uint8(bStr[i]) - 32);
            } else {
                bUpper[i] = bStr[i];
            }
        }
        return string(bUpper);
    }
}
