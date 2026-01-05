// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "./tqETHLibrary.sol";
import "../common/ProofLibrary.sol";

/// @notice Script to generate Aave operations JSON files for tqETH subvaults
/// @dev Run with: forge script scripts/ethereum/GenerateAaveOpsJSON.s.sol --sig "generateProdCurator()"
contract GenerateAaveOpsJSON is Script, Test {
    // Addresses from tqETH.s.sol
    address public curator = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec;
    address public agent1 = 0xfcBEe74406415c0Cbe556317B1aeF8D9950D515D;

    // Vault addresses
    address public constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address public constant VAULT_PREPROD = 0x2669a8B27B6f957ddb92Dc0ebdec1f112E6079E4;

    /// @notice Generate JSON for prod vault, curator
    function generateProdCurator() external {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(0); // Change index as needed: 0, 1, 2, etc.

        generateJSON("ethereum:tqETH:prod:aaveOps", subvault, curator);
    }

    /// @notice Generate JSON for pre-prod vault, curator (default subvault 0)
    function generatePreProdCurator() external {
        generatePreProdCuratorWithIndex(0);
    }

    /// @notice Generate JSON for pre-prod vault, curator with specific subvault index
    /// @param subvaultIndex The index of the subvault (0, 1, 2, etc.)
    function generatePreProdCuratorWithIndex(uint256 subvaultIndex) public {
        Vault vault = Vault(payable(VAULT_PREPROD));
        address subvault = vault.subvaultAt(subvaultIndex);

        string memory title = string(
            abi.encodePacked("ethereum:tqETH:preprod:sv", vm.toString(subvaultIndex), ":aaveOps")
        );
        generateJSON(title, subvault, curator);
    }

    /// @notice Generate JSON for prod vault, curator with specific subvault index
    /// @param subvaultIndex The index of the subvault (0, 1, 2, etc.)
    function generateProdCuratorWithIndex(uint256 subvaultIndex) public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(subvaultIndex);

        string memory title = string(
            abi.encodePacked("ethereum:tqETH:prod:sv", vm.toString(subvaultIndex), ":aaveOps")
        );
        generateJSON(title, subvault, curator);
    }

    /// @notice Generate JSON for prod vault, agent1
    function generateProdAgent1() external {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(0); // Change index as needed

        generateJSON("ethereum:tqETH:prod:aaveOps:agent1", subvault, agent1);
    }

    /// @notice Generate JSON for pre-prod vault, agent1
    function generatePreProdAgent1() external {
        Vault vault = Vault(payable(VAULT_PREPROD));
        address subvault = vault.subvaultAt(0); // Change index as needed

        generateJSON("ethereum:tqETH:preprod:aaveOps:agent1", subvault, agent1);
    }

    /// @notice (LEGACY) Use generateProdCurator() instead
    function generateForCurator() external {
        this.generateProdCurator();
    }

    /// @notice (LEGACY) Use generateProdAgent1() instead
    function generateForAgent1() external {
        this.generateProdAgent1();
    }

    /// @notice Generate JSON for a specific caller
    /// @param title The title/filename for the JSON file
    /// @param subvault The subvault address
    /// @param caller The caller address (curator or agent)
    function generateJSON(string memory title, address subvault, address caller) internal {
        require(subvault != address(0), "Subvault address not set");

        // Generate proofs and descriptions
        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leaves) =
            tqETHLibrary.getAaveOperationsProofs(subvault, Constants.TQETH, caller);

        string[] memory descriptions =
            tqETHLibrary.getAaveOperationsDescriptions(subvault, Constants.TQETH, caller);

        // Store to JSON file
        ProofLibrary.storeProofs(title, merkleRoot, leaves, descriptions);

        console.log("Generated JSON file:", string(abi.encodePacked("./scripts/jsons/", title, ".json")));
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations:", leaves.length);
    }

    /// @notice Generate JSON with custom assets configuration
    /// @param title The title/filename for the JSON file
    /// @param subvault The subvault address
    /// @param subvaultName The subvault name (e.g., "subvault3")
    /// @param caller The caller address
    /// @param collaterals Array of collateral asset addresses
    /// @param loans Array of loan asset addresses
    /// @param categoryId Aave eMode category ID
    function generateCustomJSON(
        string memory title,
        address subvault,
        string memory subvaultName,
        address caller,
        address[] memory collaterals,
        address[] memory loans,
        uint8 categoryId
    ) public {
        require(subvault != address(0), "Subvault address not set");

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Create custom Aave info
        AaveLibrary.Info memory aaveInfo = tqETHLibrary.getAaveInfo(
            subvault,
            subvaultName,
            caller,
            collaterals,
            loans,
            categoryId
        );

        // Generate proofs
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](30);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            AaveLibrary.getAaveProofs($.bitmaskVerifier, aaveInfo),
            iterator
        );

        // Add deposit/redeem operations
        CoreVaultLibrary.Info memory coreVaultInfo = CoreVaultLibrary.Info({
            subvault: subvault,
            subvaultName: subvaultName,
            curator: caller,
            vault: Constants.TQETH,
            depositQueues: tqETHLibrary.getDepositQueues(),
            redeemQueues: tqETHLibrary.getRedeemQueues()
        });
        iterator = ArraysLibrary.insert(
            leaves,
            CoreVaultLibrary.getCoreVaultProofs($.bitmaskVerifier, coreVaultInfo),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        // Generate descriptions
        string[] memory descriptions = new string[](30);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            AaveLibrary.getAaveDescriptions(aaveInfo),
            iterator
        );

        iterator = ArraysLibrary.insert(
            descriptions,
            CoreVaultLibrary.getCoreVaultDescriptions(coreVaultInfo),
            iterator
        );

        assembly {
            mstore(descriptions, iterator)
        }

        // Store to JSON file
        ProofLibrary.storeProofs(title, merkleRoot, leavesWithProofs, descriptions);

        console.log("Generated custom JSON file:", string(abi.encodePacked("./scripts/jsons/", title, ".json")));
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations:", leavesWithProofs.length);
    }

    /// @notice Example: Generate JSON with all 5 assets you mentioned
    function generateAllAssetsExample() external {
        address subvault = address(0); // TODO: Replace with actual subvault address

        // Collaterals: WETH, wstETH, USDC, USDT, USDE
        address[] memory collaterals = new address[](5);
        collaterals[0] = Constants.WETH;
        collaterals[1] = Constants.WSTETH;
        collaterals[2] = Constants.USDC;
        collaterals[3] = Constants.USDT;
        collaterals[4] = Constants.USDE;

        // Loans: WETH, wstETH, USDC, USDT, USDE (all assets for max flexibility)
        address[] memory loans = new address[](5);
        loans[0] = Constants.WETH;
        loans[1] = Constants.WSTETH;
        loans[2] = Constants.USDC;
        loans[3] = Constants.USDT;
        loans[4] = Constants.USDE;

        generateCustomJSON(
            "ethereum:tqETH:aaveOpsAll",
            subvault,
            "aaveOpsAll",
            curator,
            collaterals,
            loans,
            0 // No eMode - category 0
        );
    }
}
