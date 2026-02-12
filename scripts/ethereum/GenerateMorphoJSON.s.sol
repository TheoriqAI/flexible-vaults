// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";
import "../common/protocols/MorphoLibrary.sol";
import "../common/ArraysLibrary.sol";

/// @notice Script to generate Morpho market operations JSON files for tqETH subvaults
/// @dev Run with: forge script scripts/ethereum/GenerateMorphoJSON.s.sol --sig "generateProd(uint256)" <SUBVAULT_INDEX> --via-ir --rpc-url https://rpc.mevblocker.io
contract GenerateMorphoJSON is Script, Test {
    // Curators
    address public preProdCurator = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec;
    address public prodCurator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;

    // Vault addresses
    address public constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address public constant VAULT_PREPROD = 0x2669a8B27B6f957ddb92Dc0ebdec1f112E6079E4;

    // Default Morpho market IDs
    bytes32 public constant MARKET_1 = 0xb8fc70e82bc5bb53e773626fcc6a23f7eefa036918d7ef216ecfb1950a94a85e;
    bytes32 public constant MARKET_2 = 0xb323495f7e4148be5643a4ea4a8221eef163e4bccfdedc2a6f4696baacbc86cc;
    bytes32 public constant MARKET_3 = 0xe7e9694b754c4d4f7e21faf7223f6fa71abaeb10296a4c43a54a7977149687d2;

    /// @notice Generate JSON for prod vault with default markets
    /// @param subvaultIndex The subvault index
    function generateProd(uint256 subvaultIndex) external {
        bytes32[] memory marketIds = new bytes32[](3);
        marketIds[0] = MARKET_1;
        marketIds[1] = MARKET_2;
        marketIds[2] = MARKET_3;
        generateProdWithMarkets(subvaultIndex, marketIds);
    }

    /// @notice Generate JSON for prod vault with custom markets
    /// @param subvaultIndex The subvault index
    /// @param marketIds Array of Morpho market IDs
    function generateProdWithMarkets(uint256 subvaultIndex, bytes32[] memory marketIds) public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(subvaultIndex);

        string memory title = string(
            abi.encodePacked("ethereum:tqETH:prod:sv", vm.toString(subvaultIndex), ":morphoOps")
        );
        generateJSON(title, subvault, prodCurator, marketIds);
    }

    /// @notice Generate JSON for pre-prod vault with default markets
    /// @param subvaultIndex The subvault index
    function generatePreProd(uint256 subvaultIndex) external {
        bytes32[] memory marketIds = new bytes32[](3);
        marketIds[0] = MARKET_1;
        marketIds[1] = MARKET_2;
        marketIds[2] = MARKET_3;
        generatePreProdWithMarkets(subvaultIndex, marketIds);
    }

    /// @notice Generate JSON for pre-prod vault with custom markets
    /// @param subvaultIndex The subvault index
    /// @param marketIds Array of Morpho market IDs
    function generatePreProdWithMarkets(uint256 subvaultIndex, bytes32[] memory marketIds) public {
        Vault vault = Vault(payable(VAULT_PREPROD));
        address subvault = vault.subvaultAt(subvaultIndex);

        string memory title = string(
            abi.encodePacked("ethereum:tqETH:preprod:sv", vm.toString(subvaultIndex), ":morphoOps")
        );
        generateJSON(title, subvault, preProdCurator, marketIds);
    }

    /// @notice Generate JSON for a single market (convenience function)
    /// @param subvaultIndex The subvault index
    /// @param isProd Whether to use prod vault
    /// @param marketId Single Morpho market ID
    function generateSingleMarket(uint256 subvaultIndex, bool isProd, bytes32 marketId) external {
        bytes32[] memory marketIds = new bytes32[](1);
        marketIds[0] = marketId;

        if (isProd) {
            generateProdWithMarkets(subvaultIndex, marketIds);
        } else {
            generatePreProdWithMarkets(subvaultIndex, marketIds);
        }
    }

    /// @notice Core generation logic
    /// @param title The title/filename for the JSON file
    /// @param subvault The subvault address
    /// @param curator The curator address
    /// @param marketIds Array of Morpho market IDs
    function generateJSON(
        string memory title,
        address subvault,
        address curator,
        bytes32[] memory marketIds
    ) internal {
        require(subvault != address(0), "Subvault address not set");
        require(marketIds.length > 0, "No market IDs provided");

        console.log("=== Generating Morpho Operations JSON ===");
        console.log("Subvault:", subvault);
        console.log("Curator:", curator);
        console.log("Number of markets:", marketIds.length);
        console.log("");

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Calculate max size: 8 operations per market (2 approves + 6 operations)
        uint256 maxLeaves = marketIds.length * 50; // MorphoLibrary allocates 50 per market
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](maxLeaves);
        uint256 iterator = 0;

        // Generate proofs for each market
        for (uint256 i = 0; i < marketIds.length; i++) {
            console.log("Processing market:", vm.toString(marketIds[i]));

            MorphoLibrary.Info memory info = MorphoLibrary.Info({
                marketId: marketIds[i],
                morpho: Constants.MORPHO,
                subvault: subvault,
                curator: curator
            });

            // Log market params
            IMorpho.MarketParams memory params = IMorpho(Constants.MORPHO).idToMarketParams(marketIds[i]);
            console.log("  Loan token:", params.loanToken);
            console.log("  Collateral token:", params.collateralToken);

            iterator = ArraysLibrary.insert(
                leaves,
                MorphoLibrary.getMorphoProofs($.bitmaskVerifier, info),
                iterator
            );
        }

        assembly {
            mstore(leaves, iterator)
        }

        console.log("");
        console.log("Total operations:", iterator);

        // Generate merkle tree
        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        // Generate descriptions for each market
        string[] memory descriptions = new string[](maxLeaves);
        iterator = 0;

        for (uint256 i = 0; i < marketIds.length; i++) {
            MorphoLibrary.Info memory info = MorphoLibrary.Info({
                marketId: marketIds[i],
                morpho: Constants.MORPHO,
                subvault: subvault,
                curator: curator
            });

            iterator = ArraysLibrary.insert(
                descriptions,
                MorphoLibrary.getMorphoDescriptions(info),
                iterator
            );
        }

        assembly {
            mstore(descriptions, iterator)
        }

        // Store to JSON file
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
        console.log("3. Ensure curator has CALLER_ROLE on the subvault");
    }

    /// @notice Generate JSON from a config file (for more complex setups)
    /// @param configPath Path to config JSON file
    /// @dev Config file format:
    /// {
    ///   "subvaultIndex": 0,
    ///   "isProd": true,
    ///   "marketIds": ["0xb8fc70e...", "0xb323495..."]
    /// }
    function generateFromConfig(string memory configPath) external {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/", configPath);
        string memory json = vm.readFile(path);

        uint256 subvaultIndex = vm.parseJsonUint(json, ".subvaultIndex");
        bool isProd = vm.parseJsonBool(json, ".isProd");

        // Parse market IDs array
        bytes memory marketIdsData = vm.parseJson(json, ".marketIds");
        bytes32[] memory marketIds = abi.decode(marketIdsData, (bytes32[]));

        console.log("Loaded config:");
        console.log("  Subvault index:", subvaultIndex);
        console.log("  isProd:", isProd);
        console.log("  Market count:", marketIds.length);

        if (isProd) {
            generateProdWithMarkets(subvaultIndex, marketIds);
        } else {
            generatePreProdWithMarkets(subvaultIndex, marketIds);
        }
    }
}
