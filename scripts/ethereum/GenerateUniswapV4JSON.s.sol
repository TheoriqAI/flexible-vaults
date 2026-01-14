// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";
import "../common/protocols/UniswapV4Library.sol";
import "../common/ArraysLibrary.sol";

/// @notice Script to generate Uniswap V4 LP operations JSON files for tqETH subvaults
/// @dev Run with: forge script scripts/ethereum/GenerateUniswapV4JSON.s.sol --sig "generatePreProdCurator()" --via-ir
contract GenerateUniswapV4JSON is Script, Test {
    // Addresses from tqETH.s.sol
    address public curator = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec;

    // Vault addresses
    address public constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address public constant VAULT_PREPROD = 0x2669a8B27B6f957ddb92Dc0ebdec1f112E6079E4;

    // Uniswap V4 PositionManager (placeholder - update with actual address when available)
    address public constant UNISWAP_V4_POSITION_MANAGER = 0x1B1C77B606d13b09C84d1c7394B96b147bC03147;

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
            abi.encodePacked("ethereum:tqETH:prod:sv", vm.toString(subvaultIndex), ":uniswapV4")
        );
        generateJSON(title, subvault, "prod", curator);
    }

    /// @notice Generate JSON for pre-prod vault, curator (default subvault 5)
    function generatePreProdCurator() external {
        generatePreProdCuratorWithIndex(5);
    }

    /// @notice Generate JSON for pre-prod vault, curator with specific subvault index
    /// @param subvaultIndex The index of the subvault (0, 1, 2, etc.)
    function generatePreProdCuratorWithIndex(uint256 subvaultIndex) public {
        Vault vault = Vault(payable(VAULT_PREPROD));
        address subvault = vault.subvaultAt(subvaultIndex);

        string memory title = string(
            abi.encodePacked("ethereum:tqETH:preprod:sv", vm.toString(subvaultIndex), ":uniswapV4")
        );
        generateJSON(title, subvault, "preprod", curator);
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

        console.log("=== Generating Uniswap V4 LP Operations JSON ===");
        console.log("Environment:", environment);
        console.log("Subvault:", subvault);
        console.log("Caller:", caller);
        console.log("");

        // Get Uniswap V4 configuration
        UniswapV4Library.Info memory uniV4Info = getUniswapV4Config(subvault, caller);

        // Generate proofs and descriptions
        ProtocolDeployment memory $ = Constants.protocolDeployment();

        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](50);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            UniswapV4Library.getUniswapV4Proofs($.bitmaskVerifier, uniV4Info),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        // Generate descriptions (lean version for now)
        string[] memory descriptions = new string[](50);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            UniswapV4Library.getUniswapV4DescriptionsLean(uniV4Info),
            iterator
        );

        assembly {
            mstore(descriptions, iterator)
        }

        // Store to JSON file (lean version)
        string memory leanTitle = string(abi.encodePacked(title, "-lean"));
        ProofLibrary.storeProofs(leanTitle, merkleRoot, leavesWithProofs, descriptions);

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
        console.log("3. Ensure caller has CALLER_ROLE on the subvault");
    }

    /// @notice Get Uniswap V4 configuration with USDC/WETH and USDC/USDT pools
    /// @param subvault The subvault address
    /// @param caller The caller address
    /// @return Uniswap V4 configuration
    function getUniswapV4Config(address subvault, address caller)
        internal
        pure
        returns (UniswapV4Library.Info memory)
    {
        // Define pool pairs with fee tiers
        UniswapV4Library.LPPool[] memory pools = new UniswapV4Library.LPPool[](2);

        // Pool 1: USDC/WETH 0.3% fee (most liquid)
        // USDC (0xA0b8...) < WETH (0xC02a...) so USDC is currency0
        pools[0] = UniswapV4Library.LPPool({
            currency0: Constants.USDC,
            currency1: Constants.WETH,
            fee: 3000
        });

        // Pool 2: USDC/USDT 0.01% fee (stablecoin pair)
        // USDC (0xA0b8...) < USDT (0xdAC1...) so USDC is currency0
        pools[1] = UniswapV4Library.LPPool({
            currency0: Constants.USDC,
            currency1: Constants.USDT,
            fee: 100
        });

        return UniswapV4Library.Info({
            subvault: subvault,
            subvaultName: "uniswapV4",
            caller: caller,
            positionManager: UNISWAP_V4_POSITION_MANAGER,
            positionManagerName: "UniswapV4PositionManager",
            pools: pools
        });
    }

    /// @notice Generate custom JSON with specific LP pools
    /// @param title The title/filename for the JSON file
    /// @param subvault The subvault address
    /// @param subvaultName The subvault name
    /// @param caller The caller address
    /// @param pools Array of LP pools to include
    function generateCustomJSON(
        string memory title,
        address subvault,
        string memory subvaultName,
        address caller,
        UniswapV4Library.LPPool[] memory pools
    ) public {
        require(subvault != address(0), "Subvault address not set");

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Create Uniswap V4 info
        UniswapV4Library.Info memory uniV4Info = UniswapV4Library.Info({
            subvault: subvault,
            subvaultName: subvaultName,
            caller: caller,
            positionManager: UNISWAP_V4_POSITION_MANAGER,
            positionManagerName: "UniswapV4PositionManager",
            pools: pools
        });

        // Generate proofs
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](100);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            UniswapV4Library.getUniswapV4Proofs($.bitmaskVerifier, uniV4Info),
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
            UniswapV4Library.getUniswapV4DescriptionsLean(uniV4Info),
            iterator
        );

        assembly {
            mstore(descriptions, iterator)
        }

        // Store to JSON file (lean version)
        string memory leanTitle = string(abi.encodePacked(title, "-lean"));
        ProofLibrary.storeProofs(leanTitle, merkleRoot, leavesWithProofs, descriptions);

        console.log("Generated custom JSON file:", string(abi.encodePacked("./scripts/jsons/", title, ".json")));
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations:", leavesWithProofs.length);
    }
}
