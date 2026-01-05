// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./tqETHLibrary.sol";
import "../common/ProofLibrary.sol";
import "../common/protocols/AaveLibrary.sol";
import "../common/protocols/CoreVaultLibrary.sol";
import "../common/ArraysLibrary.sol";

/// @notice Cross-chain Aave operations JSON generator
/// @dev Supports any chain by configuring Aave pool address and asset addresses
contract GenerateAaveOpsJSONCrossChain is Script, Test {

    /// @notice Configuration for a specific chain
    struct ChainConfig {
        uint256 chainId;
        string chainName;
        address aavePool;
        address[] collateralAssets;
        address[] loanAssets;
        uint8 eModeCategory;
    }

    /// @notice Generate JSON for Ethereum mainnet
    function generateEthereum() external {
        ChainConfig memory config = ChainConfig({
            chainId: 1,
            chainName: "ethereum",
            aavePool: 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2,  // Aave V3 Core
            collateralAssets: new address[](3),
            loanAssets: new address[](3),
            eModeCategory: 0
        });

        // Collaterals: WETH, wstETH, USDE
        config.collateralAssets[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;  // WETH
        config.collateralAssets[1] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;  // wstETH
        config.collateralAssets[2] = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;  // USDE

        // Loans: USDC, USDT, USDE
        config.loanAssets[0] = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;  // USDC
        config.loanAssets[1] = 0xdAC17F958D2ee523a2206206994597C13D831ec7;  // USDT
        config.loanAssets[2] = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;  // USDE

        address subvault = address(0); // TODO: Set your subvault address
        address curator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;
        address vault = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;  // tqETH

        generateForChain(config, subvault, vault, curator);
    }

    /// @notice Generate JSON for Arbitrum
    function generateArbitrum() external {
        ChainConfig memory config = ChainConfig({
            chainId: 42161,
            chainName: "arbitrum",
            aavePool: 0x794a61358D6845594F94dc1DB02A252b5b4814aD,  // Aave V3 Arbitrum
            collateralAssets: new address[](3),
            loanAssets: new address[](3),
            eModeCategory: 0
        });

        // Arbitrum asset addresses (example - replace with actual)
        config.collateralAssets[0] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;  // WETH
        config.collateralAssets[1] = 0x5979D7b546E38E414F7E9822514be443A4800529;  // wstETH
        config.collateralAssets[2] = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;  // USDe

        config.loanAssets[0] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;  // USDC
        config.loanAssets[1] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;  // USDT
        config.loanAssets[2] = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;  // USDe

        address subvault = address(0); // TODO: Set your subvault address
        address curator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;
        address vault = address(0); // TODO: Set your vault address

        generateForChain(config, subvault, vault, curator);
    }

    /// @notice Generate JSON for Base
    function generateBase() external {
        ChainConfig memory config = ChainConfig({
            chainId: 8453,
            chainName: "base",
            aavePool: 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5,  // Aave V3 Base
            collateralAssets: new address[](2),
            loanAssets: new address[](2),
            eModeCategory: 1  // ETH correlated
        });

        // Base asset addresses (example - replace with actual)
        config.collateralAssets[0] = 0x4200000000000000000000000000000000000006;  // WETH
        config.collateralAssets[1] = 0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452;  // wstETH

        config.loanAssets[0] = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;  // USDC
        config.loanAssets[1] = 0x50c5725949A6F0c72E6C4a641F24049A917DB0Cb;  // DAI

        address subvault = address(0); // TODO: Set your subvault address
        address curator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;
        address vault = address(0); // TODO: Set your vault address

        generateForChain(config, subvault, vault, curator);
    }

    /// @notice Generate JSON for any chain with custom configuration
    /// @param config Chain configuration
    /// @param subvault Subvault address
    /// @param vault Vault address
    /// @param curator Curator address
    function generateForChain(
        ChainConfig memory config,
        address subvault,
        address vault,
        address curator
    ) public {
        require(subvault != address(0), "Subvault address not set");
        require(vault != address(0), "Vault address not set");

        // Build title with chain ID: chainName:vaultSymbol:aaveOps
        string memory title = string(
            abi.encodePacked(
                config.chainName,
                ":",
                vm.toString(config.chainId),
                ":aaveOps"
            )
        );

        console.log("Generating Aave operations JSON for:");
        console.log("Chain:", config.chainName, "(", config.chainId, ")");
        console.log("Aave Pool:", config.aavePool);
        console.log("Curator:", curator);
        console.log("Subvault:", subvault);

        // Generate proofs and descriptions
        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leaves) =
            generateAaveProofs(config, subvault, vault, curator);

        string[] memory descriptions = generateAaveDescriptions(config, subvault, vault, curator);

        // Store to JSON file
        ProofLibrary.storeProofs(title, merkleRoot, leaves, descriptions);

        console.log("\n=== Generation Complete ===");
        console.log("JSON file:", string(abi.encodePacked("./scripts/jsons/", title, ".json")));
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Operations count:", leaves.length);
        console.log("\nNext steps:");
        console.log("1. Set merkle root on-chain: verifier.setMerkleRoot(", vm.toString(merkleRoot), ")");
        console.log("2. Grant roles: vault.grantRole(CALLER_ROLE,", vm.toString(curator), ")");
    }

    /// @notice Generate Aave proofs for a custom chain configuration
    function generateAaveProofs(
        ChainConfig memory config,
        address subvault,
        address vault,
        address curator
    ) internal view returns (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leaves) {
        ProtocolDeployment memory $ = getProtocolDeployment(config.chainId);

        leaves = new IVerifier.VerificationPayload[](50);
        uint256 iterator = 0;

        // Create Aave info
        AaveLibrary.Info memory aaveInfo = AaveLibrary.Info({
            subvault: subvault,
            subvaultName: "aaveOps",
            curator: curator,
            aaveInstance: config.aavePool,
            aaveInstanceName: "AaveV3",
            collaterals: config.collateralAssets,
            loans: config.loanAssets,
            categoryId: config.eModeCategory
        });

        // Add Aave operations
        iterator = ArraysLibrary.insert(
            leaves,
            AaveLibrary.getAaveProofs($.bitmaskVerifier, aaveInfo),
            iterator
        );

        // Add vault operations (if vault exists on this chain)
        if (vault != address(0)) {
            CoreVaultLibrary.Info memory coreVaultInfo = CoreVaultLibrary.Info({
                subvault: subvault,
                subvaultName: "aaveOps",
                curator: curator,
                vault: vault,
                depositQueues: new address[](0),  // Configure per chain
                redeemQueues: new address[](0)    // Configure per chain
            });

            // Only add if there are queues
            if (coreVaultInfo.depositQueues.length > 0 || coreVaultInfo.redeemQueues.length > 0) {
                iterator = ArraysLibrary.insert(
                    leaves,
                    CoreVaultLibrary.getCoreVaultProofs($.bitmaskVerifier, coreVaultInfo),
                    iterator
                );
            }
        }

        // Trim array
        assembly {
            mstore(leaves, iterator)
        }

        return ProofLibrary.generateMerkleProofs(leaves);
    }

    /// @notice Generate descriptions for a custom chain configuration
    function generateAaveDescriptions(
        ChainConfig memory config,
        address subvault,
        address vault,
        address curator
    ) internal view returns (string[] memory descriptions) {
        descriptions = new string[](50);
        uint256 iterator = 0;

        // Create Aave info
        AaveLibrary.Info memory aaveInfo = AaveLibrary.Info({
            subvault: subvault,
            subvaultName: "aaveOps",
            curator: curator,
            aaveInstance: config.aavePool,
            aaveInstanceName: "AaveV3",
            collaterals: config.collateralAssets,
            loans: config.loanAssets,
            categoryId: config.eModeCategory
        });

        // Add Aave descriptions
        iterator = ArraysLibrary.insert(
            descriptions,
            AaveLibrary.getAaveDescriptions(aaveInfo),
            iterator
        );

        // Add vault descriptions (if applicable)
        if (vault != address(0)) {
            CoreVaultLibrary.Info memory coreVaultInfo = CoreVaultLibrary.Info({
                subvault: subvault,
                subvaultName: "aaveOps",
                curator: curator,
                vault: vault,
                depositQueues: new address[](0),
                redeemQueues: new address[](0)
            });

            if (coreVaultInfo.depositQueues.length > 0 || coreVaultInfo.redeemQueues.length > 0) {
                iterator = ArraysLibrary.insert(
                    descriptions,
                    CoreVaultLibrary.getCoreVaultDescriptions(coreVaultInfo),
                    iterator
                );
            }
        }

        // Trim array
        assembly {
            mstore(descriptions, iterator)
        }
    }

    /// @notice Get protocol deployment for a specific chain
    function getProtocolDeployment(uint256 chainId) internal view returns (ProtocolDeployment memory) {
        if (chainId == 1) {
            // Ethereum mainnet
            return Constants.protocolDeployment();
        } else if (chainId == 42161) {
            // Arbitrum - TODO: Deploy protocol contracts on Arbitrum
            revert("Protocol not deployed on Arbitrum yet");
        } else if (chainId == 8453) {
            // Base - TODO: Deploy protocol contracts on Base
            revert("Protocol not deployed on Base yet");
        } else {
            revert("Unsupported chain");
        }
    }

    /// @notice Helper to quickly add/remove assets from arrays
    /// @dev Use this as a template for custom configurations
    function exampleCustomAssets() external pure {
        // Example: Different asset configuration
        address[] memory collaterals = new address[](4);
        collaterals[0] = address(0x1111);  // Asset 1
        collaterals[1] = address(0x2222);  // Asset 2
        collaterals[2] = address(0x3333);  // Asset 3
        collaterals[3] = address(0x4444);  // Asset 4

        address[] memory loans = new address[](2);
        loans[0] = address(0x5555);  // Asset 5
        loans[1] = address(0x6666);  // Asset 6

        // Then use these in ChainConfig
    }
}
