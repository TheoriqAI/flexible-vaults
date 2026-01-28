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
    address public preProdCurator = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec;
    address public prodCurator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;
    address public agent1 = 0xfcBEe74406415c0Cbe556317B1aeF8D9950D515D;

    // Vault addresses
    address public constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address public constant VAULT_PREPROD = 0x2669a8B27B6f957ddb92Dc0ebdec1f112E6079E4;

    /// @notice Generate JSON for prod vault, curator
    function generateProdCurator() external {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(0); // Change index as needed: 0, 1, 2, etc.

        generateJSON("ethereum:tqETH:prod:aaveOps", subvault, prodCurator);
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
        generateJSON(title, subvault, preProdCurator);
    }

    /// @notice Generate JSON for prod vault, curator with specific subvault index
    /// @param subvaultIndex The index of the subvault (0, 1, 2, etc.)
    function generateProdCuratorWithIndex(uint256 subvaultIndex) public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(subvaultIndex);

        string memory title = string(
            abi.encodePacked("ethereum:tqETH:prod:sv", vm.toString(subvaultIndex), ":aaveOps")
        );
        generateJSON(title, subvault, prodCurator);
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

        // Also generate lean version without ABIs
        string[] memory descriptionsLean =
            tqETHLibrary.getAaveOperationsDescriptionsLean(subvault, Constants.TQETH, caller);

        string memory leanTitle = string(abi.encodePacked(title, "-lean"));
        ProofLibrary.storeProofs(leanTitle, merkleRoot, leaves, descriptionsLean);

        console.log("");
        console.log("=== Generation Complete ===");
        console.log("JSON file:", string(abi.encodePacked("./scripts/jsons/", title, ".json")));
        console.log("Lean JSON file:", string(abi.encodePacked("./scripts/jsons/", leanTitle, ".json")));
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

        // Also generate lean version without ABIs
        string[] memory descriptionsLean = new string[](30);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptionsLean,
            AaveLibrary.getAaveDescriptionsLean(aaveInfo),
            iterator
        );

        iterator = ArraysLibrary.insert(
            descriptionsLean,
            CoreVaultLibrary.getCoreVaultDescriptionsLean(coreVaultInfo),
            iterator
        );

        assembly {
            mstore(descriptionsLean, iterator)
        }

        string memory leanTitle = string(abi.encodePacked(title, "-lean"));
        ProofLibrary.storeProofs(leanTitle, merkleRoot, leavesWithProofs, descriptionsLean);

        console.log("");
        console.log("=== Generation Complete ===");
        console.log("JSON file:", string(abi.encodePacked("./scripts/jsons/", title, ".json")));
        console.log("Lean JSON file:", string(abi.encodePacked("./scripts/jsons/", leanTitle, ".json")));
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations:", leavesWithProofs.length);
    }

    /// @notice Generate Aave JSON with custom collateral and borrow tokens
    /// @param subvaultIndex The subvault index (0, 1, 2, etc.)
    /// @param isProd true for prod vault, false for preprod vault
    /// @param pool Aave pool address (use Constants.AAVE_CORE or Constants.SPARK)
    /// @param collaterals Array of collateral asset addresses
    /// @param borrows Array of borrow asset addresses
    /// @param outputSuffix Suffix for output filename (e.g., "aaveOps")
    /// @param categoryId Aave eMode category ID (e.g., 0 for none, 32 for specific eMode)
    function generateWithCustomAssets(
        uint256 subvaultIndex,
        bool isProd,
        address pool,
        address[] memory collaterals,
        address[] memory borrows,
        string memory outputSuffix,
        uint8 categoryId
    ) public {
        address vaultAddress = isProd ? VAULT_PROD : VAULT_PREPROD;
        string memory env = isProd ? "prod" : "preprod";

        Vault vault = Vault(payable(vaultAddress));
        address subvault = vault.subvaultAt(subvaultIndex);

        string memory title = string(
            abi.encodePacked("ethereum:tqETH:", env, ":sv", vm.toString(subvaultIndex), ":", outputSuffix)
        );

        console.log("=== Generating Aave Operations JSON ===");
        console.log("Environment:", env);
        console.log("Subvault index:", subvaultIndex);
        console.log("Subvault address:", subvault);
        console.log("Pool:", pool);
        console.log("Collaterals:", collaterals.length);
        console.log("Borrows:", borrows.length);
        console.log("");

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Determine pool name for subvault naming
        string memory poolName = pool == Constants.AAVE_CORE ? "aave" : "spark";
        string memory subvaultName = string(
            abi.encodePacked("subvault", vm.toString(subvaultIndex), "_", poolName)
        );

        // Create Aave info with custom assets
        address curator = isProd ? prodCurator : preProdCurator;
        AaveLibrary.Info memory aaveInfo = AaveLibrary.Info({
            subvault: subvault,
            subvaultName: subvaultName,
            curator: curator,
            aaveInstance: pool,
            aaveInstanceName: poolName,
            collaterals: collaterals,
            loans: borrows,
            categoryId: categoryId
        });

        // Generate proofs
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](100);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            AaveLibrary.getAaveProofs($.bitmaskVerifier, aaveInfo),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        // Generate descriptions (full version with ABIs)
        string[] memory descriptions = new string[](100);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            AaveLibrary.getAaveDescriptions(aaveInfo),
            iterator
        );

        assembly {
            mstore(descriptions, iterator)
        }

        // Store full version
        ProofLibrary.storeProofs(title, merkleRoot, leavesWithProofs, descriptions);

        // Generate descriptions (lean version)
        string[] memory descriptionsLean = new string[](100);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptionsLean,
            AaveLibrary.getAaveDescriptionsLean(aaveInfo),
            iterator
        );

        assembly {
            mstore(descriptionsLean, iterator)
        }

        // Store lean version
        string memory leanTitle = string(abi.encodePacked(title, "-lean"));
        ProofLibrary.storeProofs(leanTitle, merkleRoot, leavesWithProofs, descriptionsLean);

        console.log("");
        console.log("=== Generation Complete ===");
        console.log("JSON file:", string(abi.encodePacked("./scripts/jsons/", title, ".json")));
        console.log("Lean JSON file:", string(abi.encodePacked("./scripts/jsons/", leanTitle, ".json")));
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations:", leavesWithProofs.length);
    }

    /// @notice Helper: Generate Aave ops for preprod subvault 4 with PT tokens
    /// @param categoryId eMode category ID
    function generatePreProdSv4Aave(uint8 categoryId) public {
        // Collaterals: wstETH, PT-USDE, PT-sUSDe
        address[] memory collaterals = new address[](3);
        collaterals[0] = Constants.WSTETH; // 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
        collaterals[1] = 0x1F84a51296691320478c98b8d77f2Bbd17D34350; // PT-USDE (checksummed)
        collaterals[2] = 0xE8483517077afa11A9B07f849cee2552f040d7b2; // PT-sUSDe (checksummed)

        // Borrows: USDC, USDT, USDE
        address[] memory borrows = new address[](3);
        borrows[0] = Constants.USDC; // 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
        borrows[1] = Constants.USDT; // 0xdAC17F958D2ee523a2206206994597C13D831ec7
        borrows[2] = Constants.USDE; // 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3

        string memory suffix = string(abi.encodePacked("aaveOps-emode", vm.toString(uint256(categoryId))));
        generateWithCustomAssets(
            4, // subvault 4
            false, // preprod
            Constants.AAVE_CORE, // Aave pool (not Spark)
            collaterals,
            borrows,
            suffix,
            categoryId
        );
    }

    /// @notice Generate ALL sv4 ops (Aave with both eMode 0 and 32)
    function generatePreProdSv4All() public {
        generatePreProdSv4Aave(32);
    }

    /// @notice Helper: Generate Spark ops for preprod subvault 3
    /// @param categoryId eMode category ID for Spark
    function generatePreProdSv3Spark(uint8 categoryId) public {
        // Collaterals: WETH, wstETH
        address[] memory collaterals = new address[](2);
        collaterals[0] = Constants.WETH;
        collaterals[1] = Constants.WSTETH;

        // Borrows: WETH, wstETH, USDC, USDT, USDE
        address[] memory borrows = new address[](5);
        borrows[0] = Constants.WETH;
        borrows[1] = Constants.WSTETH;
        borrows[2] = Constants.USDC;
        borrows[3] = Constants.USDT;
        borrows[4] = Constants.USDE;

        string memory suffix = string(abi.encodePacked("sparkOps-emode", vm.toString(uint256(categoryId))));
        generateWithCustomAssets(
            3, // subvault 3
            false, // preprod
            Constants.SPARK, // Spark pool
            collaterals,
            borrows,
            suffix,
            categoryId
        );
    }

    /// @notice Helper: Generate Aave Core ops for preprod subvault 3
    /// @param categoryId eMode category ID for Aave
    function generatePreProdSv3Aave(uint8 categoryId) public {
        // Collaterals: WETH, wstETH
        address[] memory collaterals = new address[](2);
        collaterals[0] = Constants.WETH;
        collaterals[1] = Constants.WSTETH;

        // Borrows: WETH, wstETH, USDC, USDT, USDE
        address[] memory borrows = new address[](5);
        borrows[0] = Constants.WETH;
        borrows[1] = Constants.WSTETH;
        borrows[2] = Constants.USDC;
        borrows[3] = Constants.USDT;
        borrows[4] = Constants.USDE;

        string memory suffix = string(abi.encodePacked("aaveOps-emode", vm.toString(uint256(categoryId))));
        generateWithCustomAssets(
            3, // subvault 3
            false, // preprod
            Constants.AAVE_CORE, // Aave Core pool
            collaterals,
            borrows,
            suffix,
            categoryId
        );
    }

    /// @notice Generate ALL sv3 ops (Aave + Spark with eMode 0, 1, and 32)
    function generatePreProdSv3All() public {
        generatePreProdSv3Aave(32);
        generatePreProdSv3Spark(32);
    }

    /// @notice Helper: Generate Aave Core ops for PROD subvault 3
    /// @param categoryId eMode category ID for Aave
    function generateProdSv3Aave(uint8 categoryId) public {
        // Collaterals: WETH, wstETH (same as preprod)
        address[] memory collaterals = new address[](2);
        collaterals[0] = Constants.WETH;
        collaterals[1] = Constants.WSTETH;

        // Borrows: WETH, wstETH, USDC, USDT, USDE (same as preprod)
        address[] memory borrows = new address[](5);
        borrows[0] = Constants.WETH;
        borrows[1] = Constants.WSTETH;
        borrows[2] = Constants.USDC;
        borrows[3] = Constants.USDT;
        borrows[4] = Constants.USDE;

        string memory suffix = string(abi.encodePacked("aaveOps-emode", vm.toString(uint256(categoryId))));
        generateWithCustomAssets(
            3, // subvault 3
            true, // PROD
            Constants.AAVE_CORE, // Aave Core pool
            collaterals,
            borrows,
            suffix,
            categoryId
        );
    }

    /// @notice Helper: Generate Spark ops for PROD subvault 3
    /// @param categoryId eMode category ID for Spark
    function generateProdSv3Spark(uint8 categoryId) public {
        // Collaterals: WETH, wstETH (same as preprod)
        address[] memory collaterals = new address[](2);
        collaterals[0] = Constants.WETH;
        collaterals[1] = Constants.WSTETH;

        // Borrows: WETH, wstETH, USDC, USDT, USDE (same as preprod)
        address[] memory borrows = new address[](5);
        borrows[0] = Constants.WETH;
        borrows[1] = Constants.WSTETH;
        borrows[2] = Constants.USDC;
        borrows[3] = Constants.USDT;
        borrows[4] = Constants.USDE;

        string memory suffix = string(abi.encodePacked("sparkOps-emode", vm.toString(uint256(categoryId))));
        generateWithCustomAssets(
            3, // subvault 3
            true, // PROD
            Constants.SPARK, // Spark pool
            collaterals,
            borrows,
            suffix,
            categoryId
        );
    }

    /// @notice Generate ALL prod sv3 ops with eMode 1 (Aave + Spark)
    function generateProdSv3AllEMode1() public {
        generateProdSv3Aave(1);
        generateProdSv3Spark(1);
    }

    /// @notice Helper: Generate Aave ops for PROD subvault 4 with PT tokens
    /// @param categoryId eMode category ID
    function generateProdSv4Aave(uint8 categoryId) public {
        // Collaterals: wstETH, PT-sUSDe
        address[] memory collaterals = new address[](2);
        collaterals[0] = Constants.WSTETH; // 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
        collaterals[1] = 0xE8483517077afa11A9B07f849cee2552f040d7b2; // PT-sUSDe-05FEB2026 (checksummed)

        // Borrows: USDe only
        address[] memory borrows = new address[](1);
        borrows[0] = Constants.USDE; // 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3

        string memory suffix = string(abi.encodePacked("aaveOps-emode", vm.toString(uint256(categoryId))));
        generateWithCustomAssets(
            4, // subvault 4
            true, // PROD
            Constants.AAVE_CORE, // Aave pool (not Spark)
            collaterals,
            borrows,
            suffix,
            categoryId
        );
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
            prodCurator, // Example uses prod curator
            collaterals,
            loans,
            0 // No eMode - category 0
        );
    }
}
