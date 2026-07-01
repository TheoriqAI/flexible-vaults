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
    address public preProdExecutor = 0xfc5c96303F353c314e468681899C35F424246eBe;
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

    // SV2 Morpho market IDs
    bytes32 public constant SV2_MARKET_SNUSD_USDC = 0xae60b71b407e0517ead445b7113a7ffa07ea4a9379d526ade541a3e9ec777cb4;
    bytes32 public constant SV2_MARKET_REUSD_USDC = 0x4565ac05d38b19374ccbb04c17cca60ca9353cd41824f0803d0fc7704f60eaed;
    bytes32 public constant SV2_MARKET_SAVUSD_USDC = 0xe07d416323a1afbfe0bf2fe27ffb549ff565cf5c86d21b79fc60664038e597c9;
    bytes32 public constant MARKET_SUSN_USDC = 0x8924445a76b678c536df977ed9222fb0b23ee5311497dd0223fe6270bb20b4e6;
    bytes32 public constant MARKET_PT_SAVUSD_USDC = 0xc978f01522ff64adafd91856065d602c56e326a0368b895bd9244d5998e60076;
    bytes32 public constant MARKET_PT_SNUSD_4JUN2026_USDC = 0xb62aac664f81d19f21a158aa0373967ef60fd1ac8de4a9091bd225c007973ca6;
    bytes32 public constant MARKET_PT_REUSD_25JUN2026_USDC = 0x9bc98c2f20ac58287ef2c860eea53a2fdc27c17a7817ff1206c0b7840cc7cd79;

    // SV4 Morpho additions (all verified on-chain: collateral/loan/LLTV confirmed).
    bytes32 public constant MARKET_PT_REUSD_10DEC2026_USDC = 0x1e9d614631a7df0ec07fb05b2c8cb2491575fd1a63a33bf187a6afb295a4fc64; // PT-reUSD-10DEC / USDC, 91.5%
    bytes32 public constant MARKET_USD3_USDC = 0xe3df58f9d3011b7481ff36b939fa5f8da642f34ea5792d25d3958dbf1efa26d7; // USD3 / USDC, 91.5%
    bytes32 public constant MARKET_AA_FALCONX_USDC = 0xe83d72fa5b00dcd46d9e0e860d95aa540d5ec106da5833108a9f826f21f36f52; // AA_FalconXUSDC / USDC, 77%
    bytes32 public constant MARKET_CBBTC_USDC = 0x64d65c9a2d91c36d56fbc42d69e979335320169b3df63bf92789e2c8883fcc64; // cbBTC / USDC, 86%
    bytes32 public constant MARKET_XAUT_USDT = 0xb7843fe78e7e7fd3106a1b939645367967d1f986c2e45edb8932ad1896450877; // XAUt / USDT, 77%
    bytes32 public constant MARKET_WSTETH_USDC = 0x7e585a933ffe8443c371b4f8cfeb4430f5f6a14c2f32a898c26662c67a1cb8b8; // wstETH / USDC, 86%
    bytes32 public constant MARKET_WBTC_USDC = 0x3a85e619751152991742810df6ec69ce473daef99e28a64ab2340d7b7ccfee49; // WBTC / USDC, 86%
    bytes32 public constant MARKET_WETH_USDC = 0x94b823e6bd8ea533b4e33fbc307faea0b307301bc48763acc4d4aa4def7636cd; // WETH / USDC, 86%
    bytes32 public constant MARKET_WETH_USDT = 0x3758a9e2abbd67b5621f23ec482608f2f98b3c792874661ce49df7843aadcfd2; // WETH / USDT, 86%
    bytes32 public constant MARKET_WBTC_USDT = 0xa921ef34e2fc7a27ccc50ae7e4b154e16c9799d3387076c421423ef52ac4df99; // WBTC / USDT, 86%
    bytes32 public constant MARKET_WSTETH_USDT = 0xe7e9694b754c4d4f7e21faf7223f6fa71abaeb10296a4c43a54a7977149687d2; // wstETH / USDT, 86%

    /// @notice Generate Morpho ops for PROD subvault 2 (all sv4 USDC markets + EURC markets)
    function generateProdSv2Morpho() public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(2);
        bytes32[] memory marketIds = new bytes32[](7);
        marketIds[0] = SV2_MARKET_SNUSD_USDC;
        marketIds[1] = SV2_MARKET_REUSD_USDC;
        marketIds[2] = SV2_MARKET_SAVUSD_USDC;
        marketIds[3] = MARKET_SUSN_USDC;
        marketIds[4] = MARKET_PT_SAVUSD_USDC;
        marketIds[5] = SV3_MARKET_WSTETH_EURC;
        marketIds[6] = SV3_MARKET_WBTC_EURC;
        generateJSON("prod/tqETH/sv2-morphoOps", subvault, prodCurator, marketIds);
    }

    /// @notice Generate Morpho ops for PROD subvault 4 (14 markets, 112 ops)
    /// Live stables: sNUSD/USDC, reUSD/USDC, savUSD/USDC
    /// PT: PT-reUSD-10DEC2026/USDC
    /// ERC4626: USD3/USDC, AA_FalconXUSDC/USDC
    /// Blue-chips: cbBTC/USDC, XAUt/USDT, wstETH/USDC, WBTC/USDC, WETH/USDC, WETH/USDT, WBTC/USDT, wstETH/USDT
    /// Removed (were expired PTs + sUSN): sUSN/USDC, PT-savUSD-14MAY2026, PT-sNUSD-4JUN2026, PT-reUSD-25JUN2026
    function generateProdSv4Morpho() public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(4);
        bytes32[] memory marketIds = new bytes32[](14);
        marketIds[0] = SV2_MARKET_SNUSD_USDC;
        marketIds[1] = SV2_MARKET_REUSD_USDC;
        marketIds[2] = SV2_MARKET_SAVUSD_USDC;
        marketIds[3] = MARKET_PT_REUSD_10DEC2026_USDC;
        marketIds[4] = MARKET_USD3_USDC;
        marketIds[5] = MARKET_AA_FALCONX_USDC;
        marketIds[6] = MARKET_CBBTC_USDC;
        marketIds[7] = MARKET_XAUT_USDT;
        marketIds[8] = MARKET_WSTETH_USDC;
        marketIds[9] = MARKET_WBTC_USDC;
        marketIds[10] = MARKET_WETH_USDC;
        marketIds[11] = MARKET_WETH_USDT;
        marketIds[12] = MARKET_WBTC_USDT;
        marketIds[13] = MARKET_WSTETH_USDT;
        generateJSON("prod/tqETH/sv4-morphoOps", subvault, prodCurator, marketIds);
    }

    // SV3 Morpho market IDs (EURC loan token)
    bytes32 public constant SV3_MARKET_WSTETH_EURC = 0x7421c2741e064e8c53fcb5de9faf7f0025dce75bc1caf26774dd878291c81dac;
    bytes32 public constant SV3_MARKET_WBTC_EURC = 0xff527fe9c6516f9d82a3d51422ccb031d123266e6e26d4c22c942a948c180a75;

    // SV3 Morpho market IDs (WETH loan token)
    bytes32 public constant SV3_MARKET_SAVETH_WETH = 0xd98cd88ae5b336086b39fb1d62ba6171282e946105b010143f0e89f8fe7cff36;

    /// @notice Generate Morpho ops for PROD subvault 3 (savETH/WETH market)
    function generateProdSv3Morpho() public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(3);
        bytes32[] memory marketIds = new bytes32[](1);
        marketIds[0] = SV3_MARKET_SAVETH_WETH;
        generateJSON("prod/tqETH/sv3-morphoOps", subvault, prodCurator, marketIds);
    }

    /// @notice Generate Morpho JSON for MULTIPLE callers (entries doubled)
    /// @param subvaultIndex The subvault index
    /// @param isProd true for prod vault, false for preprod vault
    /// @param marketIds Array of Morpho market IDs
    /// @param callers Array of caller addresses
    function generateWithMarketsMultiCaller(
        uint256 subvaultIndex,
        bool isProd,
        bytes32[] memory marketIds,
        address[] memory callers
    ) public {
        address vaultAddress = isProd ? VAULT_PROD : VAULT_PREPROD;
        string memory env = isProd ? "prod" : "preprod";

        Vault vault = Vault(payable(vaultAddress));
        address subvault = vault.subvaultAt(subvaultIndex);

        string memory title = string(
            abi.encodePacked("ethereum:tqETH:", env, ":sv", vm.toString(subvaultIndex), ":morphoOps")
        );

        require(subvault != address(0), "Subvault address not set");
        require(marketIds.length > 0, "No market IDs provided");

        console.log("=== Generating Morpho Operations JSON (Multi-Caller) ===");
        console.log("Environment:", env);
        console.log("Subvault:", subvault);
        console.log("Number of markets:", marketIds.length);
        console.log("Number of callers:", callers.length);
        console.log("");

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        uint256 maxLeaves = marketIds.length * callers.length * 50;
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](maxLeaves);
        uint256 iterator = 0;

        // Generate proofs for ALL callers and ALL markets
        for (uint256 c = 0; c < callers.length; c++) {
            console.log("Generating for caller:", callers[c]);
            for (uint256 i = 0; i < marketIds.length; i++) {
                MorphoLibrary.Info memory info = MorphoLibrary.Info({
                    marketId: marketIds[i],
                    morpho: Constants.MORPHO,
                    subvault: subvault,
                    curator: callers[c]
                });

                iterator = ArraysLibrary.insert(
                    leaves,
                    MorphoLibrary.getMorphoProofs($.bitmaskVerifier, info),
                    iterator
                );
            }
        }

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        // Generate descriptions for ALL callers and ALL markets
        string[] memory descriptions = new string[](maxLeaves);
        iterator = 0;

        for (uint256 c = 0; c < callers.length; c++) {
            for (uint256 i = 0; i < marketIds.length; i++) {
                MorphoLibrary.Info memory info = MorphoLibrary.Info({
                    marketId: marketIds[i],
                    morpho: Constants.MORPHO,
                    subvault: subvault,
                    curator: callers[c]
                });

                iterator = ArraysLibrary.insert(
                    descriptions,
                    MorphoLibrary.getMorphoDescriptions(info),
                    iterator
                );
            }
        }

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

    /// @notice Generate Morpho ops for preprod sv4 with BOTH curator and executor as callers
    function generatePreProdSv4MorphoMultiCaller() public {
        bytes32[] memory marketIds = new bytes32[](3);
        marketIds[0] = MARKET_1;
        marketIds[1] = MARKET_2;
        marketIds[2] = MARKET_3;

        address[] memory callers = new address[](2);
        callers[0] = preProdCurator;
        callers[1] = preProdExecutor;

        generateWithMarketsMultiCaller(4, false, marketIds, callers);
    }
}
