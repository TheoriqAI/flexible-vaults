// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";
import "../common/protocols/EulerLibrary.sol";
import "../common/ArraysLibrary.sol";

/// @notice Script to generate Euler EVault operations JSON files for tqMON subvaults
/// @dev Run with: forge script scripts/monad/GenerateEulerJSON.s.sol --sig "generateSv0()" --via-ir --rpc-url https://rpc.monad.xyz
contract GenerateEulerJSON is Script, Test {
    address public constant VAULT = 0x799d2847cF8Dfcb4f17ec28737f17C0E82Eb445c;
    address public curator = 0x5FFA51F64Bc40c5af3a435A95e9616cc2Df9F01B;

    /// @notice Generate Euler JSON for sv0 — supply only (no borrowing)
    function generateSv0() public {
        Vault vault = Vault(payable(VAULT));
        address subvault = vault.subvaultAt(0);

        address[] memory borrowVaults = new address[](0);

        generateJSON("monad:tqMON:prod:sv0:eulerOps", subvault, curator, address(0), _supplyVaults(), borrowVaults);
    }

    /// @notice Generate Euler JSON for sv0 with borrowing enabled (WETH, USDC, AUSD)
    function generateSv0WithBorrow() public {
        Vault vault = Vault(payable(VAULT));
        address subvault = vault.subvaultAt(0);

        address[] memory borrowVaults = new address[](3);
        borrowVaults[0] = Constants.EULER_WETH_EVAULT;
        borrowVaults[1] = Constants.EULER_USDC_EVAULT;
        borrowVaults[2] = Constants.EULER_AUSD_EVAULT;

        generateJSON("monad:tqMON:prod:sv0:eulerOps", subvault, curator, Constants.EULER_EVC, _supplyVaults(), borrowVaults);
    }

    function _supplyVaults() internal pure returns (address[] memory supplyVaults) {
        supplyVaults = new address[](5);
        supplyVaults[0] = Constants.EULER_WETH_EVAULT;
        supplyVaults[1] = Constants.EULER_AUSD_EVAULT;
        supplyVaults[2] = Constants.EULER_WMON_EVAULT;
        supplyVaults[3] = Constants.EULER_USDC_EVAULT;
        supplyVaults[4] = Constants.EULER_WSTETH_EVAULT;
    }

    /// @notice Generate Euler JSON for sv0 prod — supply USDC/WETH_V2/wstETH_V2, borrow WETH_V2/USDC
    function generateSv0Prod() public {
        Vault vault = Vault(payable(VAULT));
        address subvault = vault.subvaultAt(0);

        address[] memory supplyVaults = new address[](3);
        supplyVaults[0] = Constants.EULER_USDC_EVAULT;
        supplyVaults[1] = Constants.EULER_WETH_EVAULT_V2;
        supplyVaults[2] = Constants.EULER_WSTETH_EVAULT_V2;

        address[] memory borrowVaults = new address[](2);
        borrowVaults[0] = Constants.EULER_WETH_EVAULT_V2;
        borrowVaults[1] = Constants.EULER_USDC_EVAULT;

        generateJSON("monad:tqMON:prod:sv0:eulerOps", subvault, curator, Constants.EULER_EVC, supplyVaults, borrowVaults);
    }

    /// @notice Generate Euler JSON for any subvault with custom supply/borrow vaults
    /// @param subvaultIndex The subvault index
    /// @param evc The EVC address (address(0) to skip EVC permissions)
    /// @param supplyVaults Array of EVault addresses for deposit/withdraw
    /// @param borrowVaults Array of EVault addresses for borrow/repay/liquidate
    function generate(uint256 subvaultIndex, address evc, address[] memory supplyVaults, address[] memory borrowVaults)
        public
    {
        Vault vault = Vault(payable(VAULT));
        address subvault = vault.subvaultAt(subvaultIndex);

        string memory title = string(
            abi.encodePacked("monad:tqMON:prod:sv", vm.toString(subvaultIndex), ":eulerOps")
        );
        generateJSON(title, subvault, curator, evc, supplyVaults, borrowVaults);
    }

    /// @notice Core generation logic
    function generateJSON(
        string memory title,
        address subvault,
        address caller,
        address evc,
        address[] memory supplyVaults,
        address[] memory borrowVaults
    ) internal {
        require(subvault != address(0), "Subvault address not set");
        require(supplyVaults.length + borrowVaults.length > 0, "No EVaults provided");

        console.log("=== Generating Euler Operations JSON ===");
        console.log("Subvault:", subvault);
        console.log("Curator:", caller);
        console.log("Supply vaults:", supplyVaults.length);
        console.log("Borrow vaults:", borrowVaults.length);
        console.log("");

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        EulerLibrary.Info memory info = EulerLibrary.Info({
            subvault: subvault,
            subvaultName: "subvault",
            curator: caller,
            evc: evc,
            supplyVaults: supplyVaults,
            borrowVaults: borrowVaults
        });

        // Generate proofs
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](100);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            EulerLibrary.getEulerProofs($.bitmaskVerifier, info),
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
            EulerLibrary.getEulerDescriptions(info),
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
        console.log("");
        console.log("Next steps:");
        console.log("1. Review the generated JSON file");
        console.log("2. Set merkle root on-chain: verifier.setMerkleRoot(", vm.toString(merkleRoot), ")");
    }
}
