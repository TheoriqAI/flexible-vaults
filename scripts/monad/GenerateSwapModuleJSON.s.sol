// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";
import "../common/protocols/SwapModuleLibrary.sol";
import "../common/ArraysLibrary.sol";

/// @notice Script to generate SwapModule (pushAssets/pullAssets) JSON files for tqMON subvaults
/// @dev Run with: forge script scripts/monad/GenerateSwapModuleJSON.s.sol --sig "generateSv0()" --via-ir --rpc-url https://rpc.monad.xyz
contract GenerateSwapModuleJSON is Script, Test {
    address public constant VAULT = 0x799d2847cF8Dfcb4f17ec28737f17C0E82Eb445c;
    address public curator = 0x5FFA51F64Bc40c5af3a435A95e9616cc2Df9F01B;

    address public constant SWAP_MODULE_0 = 0x34C39003f5D5Dbb022926642b0fD28A2fd9ec544;
    address public constant SWAP_MODULE_1 = 0x4192b2021afd7F7a0acA354Ee8f9264aa946BF74;

    /// @notice Generate SwapModule JSON for sv0 with MON, WMON, WETH, USDC, AUSD
    function generateSv0() public {
        Vault vault = Vault(payable(VAULT));
        address subvault = vault.subvaultAt(0);
        generateJSON("monad:tqMON:prod:sv0:swapModule", subvault, SWAP_MODULE_0, curator);
    }

    /// @notice Generate SwapModule JSON for sv0 prod with WMON, MON, USDC, WETH (no AUSD)
    function generateSv0Prod() public {
        Vault vault = Vault(payable(VAULT));
        address subvault = vault.subvaultAt(0);
        generateJSONProd("monad:tqMON:prod:sv0:swapModule", subvault, SWAP_MODULE_0, curator);
    }

    /// @notice Generate SwapModule JSON for sv1 with MON, WMON, WETH, USDC, AUSD
    function generateSv1() public {
        Vault vault = Vault(payable(VAULT));
        address subvault = vault.subvaultAt(1);
        generateJSON("monad:tqMON:prod:sv1:swapModule", subvault, SWAP_MODULE_1, curator);
    }

    /// @notice Generate SwapModule JSON for any subvault with custom swap module
    /// @param subvaultIndex The subvault index
    /// @param swapModule The swap module address
    function generateWithSwapModule(uint256 subvaultIndex, address swapModule) public {
        Vault vault = Vault(payable(VAULT));
        address subvault = vault.subvaultAt(subvaultIndex);

        string memory title = string(
            abi.encodePacked("monad:tqMON:prod:sv", vm.toString(subvaultIndex), ":swapModule")
        );
        generateJSON(title, subvault, swapModule, curator);
    }

    /// @notice Core generation logic (prod: WMON, MON, USDC, WETH)
    function generateJSONProd(string memory title, address subvault, address swapModule, address caller) internal {
        require(subvault != address(0), "Subvault address not set");

        console.log("=== Generating SwapModule Operations JSON (Prod) ===");
        console.log("Subvault:", subvault);
        console.log("SwapModule:", swapModule);
        console.log("Caller:", caller);
        console.log("");

        address[] memory curators = new address[](1);
        curators[0] = caller;

        SwapModuleLibrary.Info memory info = SwapModuleLibrary.Info({
            subvault: subvault,
            subvaultName: "swapModule",
            swapModule: swapModule,
            curators: curators,
            assets: ArraysLibrary.makeAddressArray(
                abi.encode(Constants.WMON, Constants.MON, Constants.USDC, Constants.WETH)
            )
        });

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](100);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            SwapModuleLibrary.getSwapModuleProofs($.bitmaskVerifier, info),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        string[] memory descriptions = new string[](100);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            SwapModuleLibrary.getSwapModuleDescriptions(info),
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
    }

    /// @notice Core generation logic
    function generateJSON(string memory title, address subvault, address swapModule, address caller) internal {
        require(subvault != address(0), "Subvault address not set");

        console.log("=== Generating SwapModule Operations JSON ===");
        console.log("Subvault:", subvault);
        console.log("SwapModule:", swapModule);
        console.log("Caller:", caller);
        console.log("");

        address[] memory curators = new address[](1);
        curators[0] = caller;

        SwapModuleLibrary.Info memory info = SwapModuleLibrary.Info({
            subvault: subvault,
            subvaultName: "swapModule",
            swapModule: swapModule,
            curators: curators,
            assets: ArraysLibrary.makeAddressArray(
                abi.encode(Constants.MON, Constants.WMON, Constants.WETH, Constants.USDC, Constants.AUSD)
            )
        });

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Generate proofs
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](100);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            SwapModuleLibrary.getSwapModuleProofs($.bitmaskVerifier, info),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        // Generate descriptions
        string[] memory descriptions = new string[](100);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            SwapModuleLibrary.getSwapModuleDescriptions(info),
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
    }
}
