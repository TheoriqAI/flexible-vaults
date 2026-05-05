// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";
import "../common/protocols/OFTLibrary.sol";
import "../common/ArraysLibrary.sol";

/// @notice Script to generate OFT bridge operations JSON files
/// @dev Run with: forge script scripts/ethereum/GenerateOFTJSON.s.sol --sig "generateProdSv3WETHToMonad()" --via-ir --rpc-url https://rpc.mevblocker.io
contract GenerateOFTJSON is Script, Test {
    address public prodCurator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;

    address public constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;

    /// @notice Generate OFT bridge JSON for prod SV3 WETH to Monad
    function generateProdSv3WETHToMonad() public {
        generateOFTBridge(
            3, // subvault index
            Constants.ETHEREUM_WETH_OFT_ADAPTER,
            Constants.LAYER_ZERO_MONAD_EID,
            0x0C7cb4e1241F4B7Fd65DE59FDE5a6dBFf190fB20, // target subvault on Monad
            Constants.MONAD_VAULT,
            "monad",
            "monad-sv"
        );
    }

    /// @notice Generic OFT bridge JSON generator with target subvault verification
    /// @param subvaultIndex Source subvault index on Ethereum prod vault
    /// @param oftAdapter OFT adapter address on Ethereum
    /// @param dstEid LayerZero destination endpoint ID
    /// @param targetSubvault Target subvault on destination chain
    /// @param dstVault Vault address on destination chain (for verification)
    /// @param targetChainName Human-readable chain name
    /// @param targetSubvaultName Human-readable subvault name
    function generateOFTBridge(
        uint256 subvaultIndex,
        address oftAdapter,
        uint32 dstEid,
        address targetSubvault,
        address dstVault,
        string memory targetChainName,
        string memory targetSubvaultName
    ) public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(subvaultIndex);
        require(subvault != address(0), "Subvault address not set");

        string memory title = string(
            abi.encodePacked(
                "prod/tqETH/sv",
                vm.toString(subvaultIndex),
                "-lzBridge-WETH-",
                targetChainName
            )
        );

        console.log("=== Generating OFT Bridge Operations JSON ===");
        console.log("Source subvault:", subvault);
        console.log("OFT adapter:", oftAdapter);
        console.log("Destination EID:", uint256(dstEid));
        console.log("Target subvault:", targetSubvault);
        console.log("Target (bytes32):", vm.toString(bytes32(uint256(uint160(targetSubvault)))));
        console.log("Refund address (source subvault):", subvault);
        console.log("");

        OFTLibrary.Info memory info = OFTLibrary.Info({
            curator: prodCurator,
            subvault: subvault,
            targetSubvault: targetSubvault,
            approveRequired: true, // WETH needs approval to OFT adapter
            sourceOFT: oftAdapter,
            dstEid: dstEid,
            subvaultName: string(abi.encodePacked("sv", vm.toString(subvaultIndex))),
            targetSubvaultName: targetSubvaultName,
            targetChainName: targetChainName
        });

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Generate proofs
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](10);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            OFTLibrary.getOFTProofs($.bitmaskVerifier, info),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        // Generate descriptions
        string[] memory descriptions = new string[](10);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            OFTLibrary.getOFTDescriptions(info),
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

        // Verify target is a subvault on destination chain (done last to avoid fork state issues)
        _verifyTargetSubvault(dstVault, targetSubvault, targetChainName);
    }

    /// @notice Verify the target address is a subvault of the destination vault
    /// @dev Uses vm.createFork with <CHAIN>_RPC_URL env var, falls back to public RPC.
    function _verifyTargetSubvault(
        address dstVault,
        address targetSubvault,
        string memory chainName
    ) internal {
        // Build env var name: e.g. "MONAD_RPC_URL"
        string memory envKey = string(abi.encodePacked(_toUpperCase(chainName), "_RPC_URL"));
        string memory rpcUrl = vm.envOr(envKey, _defaultRpc(chainName));

        if (bytes(rpcUrl).length == 0) {
            console.log("WARNING: No RPC available for %s, skipping target subvault verification", chainName);
            console.log("Please verify manually that", targetSubvault);
            console.log("is a subvault of vault", dstVault);
            console.log("");
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

    /// @notice Default public RPC URLs for known chains
    function _defaultRpc(string memory chainName) internal pure returns (string memory) {
        if (keccak256(bytes(chainName)) == keccak256("monad")) return "https://rpc.monad.xyz";
        return "";
    }

    /// @notice Convert string to uppercase (for env var names)
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
