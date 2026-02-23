// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";
import "../common/protocols/PendleLibrary.sol";
import "../common/ArraysLibrary.sol";

/// @notice Script to generate Pendle PT operations JSON files for tqETH subvaults
/// @dev Run with: forge script scripts/ethereum/GeneratePendleJSON.s.sol --sig "generateProdCurator()" --via-ir
contract GeneratePendleJSON is Script, Test {
    // Addresses from tqETH.s.sol
    address public preProdCurator = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec;
    address public prodCurator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;

    // Vault addresses
    address public constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address public constant VAULT_PREPROD = 0x2669a8B27B6f957ddb92Dc0ebdec1f112E6079E4;

    /// @notice Generate JSON for prod vault, curator (default subvault 0)
    function generateProdCurator() external {
        generateProdCuratorWithIndex(0);
    }

    /// @notice Generate JSON for prod vault, curator with specific subvault index
    /// @param subvaultIndex The index of the subvault (0, 1, 2, etc.)
    function generateProdCuratorWithIndex(uint256 subvaultIndex) public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(subvaultIndex);

        string memory title = string(
            abi.encodePacked("ethereum:tqETH:prod:sv", vm.toString(subvaultIndex), ":pendlePT")
        );
        generateJSON(title, subvault, "prod", prodCurator);
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
            abi.encodePacked("ethereum:tqETH:preprod:sv", vm.toString(subvaultIndex), ":pendlePT")
        );
        generateJSON(title, subvault, "preprod", preProdCurator);
    }

    /// @notice Generate JSON for a specific caller
    /// @param title The title/filename for the JSON file
    /// @param subvault The subvault address
    /// @param environment "prod" or "preprod"
    /// @param caller The caller address (curator or agent)
    function generateJSON(string memory title, address subvault, string memory environment, address caller)
        internal
    {
        require(subvault != address(0), "Subvault address not set");

        console.log("=== Generating Pendle PT Operations JSON ===");
        console.log("Environment:", environment);
        console.log("Subvault:", subvault);
        console.log("Curator:", caller);
        console.log("");

        // Get Pendle configuration
        PendleLibrary.Info memory pendleInfo = getPendlePTConfig(subvault, caller);

        // Generate proofs and descriptions
        ProtocolDeployment memory $ = Constants.protocolDeployment();

        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](50);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            PendleLibrary.getPendleProofs($.bitmaskVerifier, pendleInfo),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        // Generate descriptions
        string[] memory descriptions = new string[](50);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            PendleLibrary.getPendleDescriptions(pendleInfo),
            iterator
        );

        assembly {
            mstore(descriptions, iterator)
        }

        // Store to JSON file
        ProofLibrary.storeProofs(title, merkleRoot, leavesWithProofs, descriptions);

        // Also generate lean version without ABIs
        string[] memory descriptionsLean = new string[](50);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptionsLean,
            PendleLibrary.getPendleDescriptionsLean(pendleInfo),
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
        console.log("");
        console.log("Next steps:");
        console.log("1. Review the generated JSON file");
        console.log("2. Set merkle root on-chain: verifier.setMerkleRoot(", vm.toString(merkleRoot), ")");
        console.log("3. Ensure curator has CALLER_ROLE on the subvault");
    }

    /// @notice Get Pendle PT configuration with both PT-jrUSDe-27MAR2025 and PT-sNUSD-04MAR2026
    /// @param subvault The subvault address
    /// @param caller The caller address
    /// @return Pendle configuration
    function getPendlePTConfig(address subvault, address caller)
        internal
        pure
        returns (PendleLibrary.Info memory)
    {
        PendleLibrary.PTStrategy[] memory strategies = new PendleLibrary.PTStrategy[](3);

        // Strategy 1: PT-jrUSDe-27MAR2025
        // Input tokens: USDe and sUSDe
        address[] memory inputTokens1 = new address[](2);
        inputTokens1[0] = Constants.USDE;
        inputTokens1[1] = Constants.SUSDE;

        strategies[0] = PendleLibrary.PTStrategy({
            ptToken: Constants.PT_JRUSDE_27MAR2025,
            market: Constants.PENDLE_MARKET_PT_JRUSDE_27MAR2025,
            inputTokens: inputTokens1,
            mintSyToken: Constants.JRUSDE  // jrUSDe is the SY token for this PT
        });

        // Strategy 2: PT-sNUSD-04MAR2026
        // Input tokens: NUSD, sNUSD, USDe, USDC
        address[] memory inputTokens2 = new address[](4);
        inputTokens2[0] = Constants.NUSD;
        inputTokens2[1] = Constants.SNUSD;
        inputTokens2[2] = Constants.USDE;
        inputTokens2[3] = Constants.USDC;

        strategies[1] = PendleLibrary.PTStrategy({
            ptToken: Constants.PT_SNUSD_04MAR2026,
            market: Constants.PENDLE_MARKET_PT_SNUSD_04MAR2026,
            inputTokens: inputTokens2,
            mintSyToken: Constants.SNUSD  // sNUSD is the SY token for this PT
        });

        // Strategy 3: PT-sUSDe-5FEB2026
        // Input tokens: USDe and sUSDe
        address[] memory inputTokens3 = new address[](2);
        inputTokens3[0] = Constants.USDE;
        inputTokens3[1] = Constants.SUSDE;

        strategies[2] = PendleLibrary.PTStrategy({
            ptToken: Constants.PT_SUSDE_5FEB2026,
            market: Constants.PENDLE_MARKET_PT_SUSDE_5FEB2026,
            inputTokens: inputTokens3,
            mintSyToken: Constants.SUSDE  // sUSDe is the SY token for this PT
        });

        return PendleLibrary.Info({
            subvault: subvault,
            subvaultName: "pendlePT",
            curator: caller,
            pendleRouter: Constants.PENDLE_ROUTER,
            pendleRouterName: "PendleRouterV3",
            strategies: strategies
        });
    }

    /// @notice Generate custom JSON with specific PT strategies
    /// @param title The title/filename for the JSON file
    /// @param subvault The subvault address
    /// @param subvaultName The subvault name
    /// @param caller The caller address
    /// @param strategies Array of PT strategies to include
    function generateCustomJSON(
        string memory title,
        address subvault,
        string memory subvaultName,
        address caller,
        PendleLibrary.PTStrategy[] memory strategies
    ) public {
        require(subvault != address(0), "Subvault address not set");

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Create Pendle info
        PendleLibrary.Info memory pendleInfo = PendleLibrary.Info({
            subvault: subvault,
            subvaultName: subvaultName,
            curator: caller,
            pendleRouter: Constants.PENDLE_ROUTER,
            pendleRouterName: "PendleRouterV3",
            strategies: strategies
        });

        // Generate proofs
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](100);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            PendleLibrary.getPendleProofs($.bitmaskVerifier, pendleInfo),
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
            PendleLibrary.getPendleDescriptions(pendleInfo),
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

    /// @notice Generate Pendle PT JSON with custom strategies
    /// @param subvaultIndex The subvault index
    /// @param isProd true for prod vault, false for preprod vault
    /// @param strategies Array of PT strategies
    function generateWithCustomStrategies(
        uint256 subvaultIndex,
        bool isProd,
        PendleLibrary.PTStrategy[] memory strategies
    ) public {
        address vaultAddress = isProd ? VAULT_PROD : VAULT_PREPROD;
        string memory env = isProd ? "prod" : "preprod";

        Vault vault = Vault(payable(vaultAddress));
        address subvault = vault.subvaultAt(subvaultIndex);

        string memory title = string(
            abi.encodePacked("ethereum:tqETH:", env, ":sv", vm.toString(subvaultIndex), ":pendlePT")
        );

        string memory subvaultName = string(abi.encodePacked("subvault", vm.toString(subvaultIndex)));

        console.log("=== Generating Pendle PT Operations JSON ===");
        console.log("Environment:", env);
        console.log("Subvault index:", subvaultIndex);
        console.log("Subvault address:", subvault);
        console.log("Number of PT strategies:", strategies.length);
        console.log("");

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Select appropriate curator based on environment
        address curator = isProd ? prodCurator : preProdCurator;

        // Create Pendle info
        PendleLibrary.Info memory pendleInfo = PendleLibrary.Info({
            subvault: subvault,
            subvaultName: subvaultName,
            curator: curator,
            pendleRouter: Constants.PENDLE_ROUTER,
            pendleRouterName: "PendleRouterV3",
            strategies: strategies
        });

        // Generate proofs
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](100);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            PendleLibrary.getPendleProofs($.bitmaskVerifier, pendleInfo),
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
            PendleLibrary.getPendleDescriptions(pendleInfo),
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
            PendleLibrary.getPendleDescriptionsLean(pendleInfo),
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


    /// @notice Generate Pendle PT JSON from a config file
    /// @param configPath Path to config file (relative to scripts/configs/)
    function generateFromConfig(string memory configPath) public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/configs/", configPath, ".json");
        string memory json = vm.readFile(path);

        uint256 subvaultIndex = vm.parseJsonUint(json, ".subvaultIndex");
        bool isProd = vm.parseJsonBool(json, ".isProd");

        // Parse strategies - count them first
        uint256 numStrategies = 0;
        for (uint256 i = 0; i < 20; i++) {
            string memory basePath = string.concat(".strategies[", vm.toString(i), "].ptToken");
            try vm.parseJsonAddress(json, basePath) {
                numStrategies++;
            } catch {
                break;
            }
        }

        PendleLibrary.PTStrategy[] memory strategies = new PendleLibrary.PTStrategy[](numStrategies);

        for (uint256 i = 0; i < numStrategies; i++) {
            string memory basePath = string.concat(".strategies[", vm.toString(i), "]");

            address ptToken = vm.parseJsonAddress(json, string.concat(basePath, ".ptToken"));
            address market = vm.parseJsonAddress(json, string.concat(basePath, ".market"));
            address mintSyToken = vm.parseJsonAddress(json, string.concat(basePath, ".mintSyToken"));

            // Parse inputTokens array
            bytes memory inputTokensData = vm.parseJson(json, string.concat(basePath, ".inputTokens"));
            address[] memory inputTokens = abi.decode(inputTokensData, (address[]));

            strategies[i] = PendleLibrary.PTStrategy({
                ptToken: ptToken,
                market: market,
                inputTokens: inputTokens,
                mintSyToken: mintSyToken
            });
        }

        generateWithCustomStrategies(subvaultIndex, isProd, strategies);
    }

    /// @notice Example: Add a different PT strategy
    function generateMultiPTExample() external {
        address subvault = address(0); // TODO: Replace with actual subvault address

        PendleLibrary.PTStrategy[] memory strategies = new PendleLibrary.PTStrategy[](2);

        // Strategy 1: PT-jrUSDe
        address[] memory inputTokens1 = new address[](2);
        inputTokens1[0] = Constants.USDE;
        inputTokens1[1] = Constants.SUSDE;

        strategies[0] = PendleLibrary.PTStrategy({
            ptToken: Constants.PT_JRUSDE_27MAR2025,
            market: Constants.PENDLE_MARKET_PT_JRUSDE_27MAR2025,
            inputTokens: inputTokens1,
            mintSyToken: Constants.JRUSDE
        });

        // Strategy 2: Another PT (example - replace with actual addresses)
        address[] memory inputTokens2 = new address[](1);
        inputTokens2[0] = Constants.WETH;

        strategies[1] = PendleLibrary.PTStrategy({
            ptToken: address(0), // TODO: Add actual PT token
            market: address(0),  // TODO: Add actual market
            inputTokens: inputTokens2,
            mintSyToken: Constants.WETH
        });

        generateCustomJSON(
            "ethereum:tqETH:multiPT",
            subvault,
            "multiPT",
            prodCurator,
            strategies
        );
    }
}
