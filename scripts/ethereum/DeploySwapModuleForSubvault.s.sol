// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ArraysLibrary.sol";
import "../common/Permissions.sol";
import "../common/interfaces/Imports.sol";

/// @notice Script to deploy a SwapModule for a specific subvault
/// @dev Run with: forge script scripts/ethereum/DeploySwapModuleForSubvault.s.sol --sig "run()" --rpc-url <RPC> --broadcast
/// @dev For preprod: forge script scripts/ethereum/DeploySwapModuleForSubvault.s.sol --sig "runPreProd()" --rpc-url <RPC> --broadcast
contract DeploySwapModuleForSubvault is Script, Test {
    // Production Configuration
    address public constant SUBVAULT = 0xB747b828A22001cAC25243C18408697845C3B68E;
    address public constant PROXY_ADMIN = 0x55d9ecEB5733F72A48C544e20D49859eC92Fba5F;
    address public constant LAZY_VAULT_ADMIN = 0x8907D6089fC71AA6a9a7bb9EC5b1170e92489ebf;
    address public constant CURATOR = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;

    // PreProd Configuration
    address public constant PREPROD_SUBVAULT = 0xf37D9264099Fc67448e56e60BC33095F2b2a95d3;
    address public constant PREPROD_PROXY_ADMIN = 0xC1211878475Cd017fecb922Ae63cc3815FA45652;
    address public constant PREPROD_LAZY_VAULT_ADMIN = 0xE8bEc6Fb52f01e487415D3Ed3797ab92cBfdF498;
    address public constant PREPROD_CURATOR1 = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec;
    address public constant PREPROD_CURATOR2 = 0x7096aa3293DEc845235b42c199358D02f497bA58;

    function run() external {
        uint256 deployerPk = uint256(bytes32(vm.envBytes("HOT_DEPLOYER")));

        vm.startBroadcast(deployerPk);

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Build the token arrays with interleaved tokenIn and tokenOut
        // Pattern: curator, tokenIn1-6, tokenOut1-6, router1, router2
        address[] memory addresses = ArraysLibrary.makeAddressArray(
            abi.encode(
                CURATOR,              // SWAP_MODULE_CALLER_ROLE
                Constants.WETH,       // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.WSTETH,     // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.USDC,       // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.USDT,       // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.USDE,       // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.SUSDE,      // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.WETH,       // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.WSTETH,     // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.USDC,       // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.USDT,       // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.USDE,       // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.SUSDE,      // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.COWSWAP_SETTLEMENT, // SWAP_MODULE_ROUTER_ROLE
                Constants.KYBERSWAP_ROUTER    // SWAP_MODULE_ROUTER_ROLE
            )
        );

        // Build the role array corresponding to the addresses
        bytes32[] memory roles = ArraysLibrary.makeBytes32Array(
            abi.encode(
                Permissions.SWAP_MODULE_CALLER_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_ROUTER_ROLE,
                Permissions.SWAP_MODULE_ROUTER_ROLE
            )
        );

        // Deploy SwapModule
        address swapModule = $.swapModuleFactory.create(
            0,
            PROXY_ADMIN,
            abi.encode(
                LAZY_VAULT_ADMIN,           // admin
                SUBVAULT,                   // subvault
                Constants.AAVE_V3_ORACLE,   // oracle
                0.995e8,                    // slippage tolerance (99.5%)
                addresses,                  // addresses array
                roles                       // roles array
            )
        );

        vm.stopBroadcast();

        console.log("");
        console.log("=== SwapModule Deployment Complete ===");
        console.log("SwapModule address:", swapModule);
        console.log("Subvault:", SUBVAULT);
        console.log("Curator:", CURATOR);
        console.log("");
        console.log("Tokens configured:");
        console.log("  TokenIn: WETH, wstETH, USDC, USDT, USDE, SUSDE");
        console.log("  TokenOut: WETH, wstETH, USDC, USDT, USDE, SUSDE");
        console.log("  Routers: CowswapSettlement, KyberSwapRouter");
        console.log("");
        console.log("Next steps:");
        console.log("1. Grant necessary roles on the subvault if needed");
        console.log("2. Configure merkle root for swap operations");
    }

    function runPreProd() external {
        uint256 deployerPk = uint256(bytes32(vm.envBytes("HOT_DEPLOYER")));

        vm.startBroadcast(deployerPk);

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Build the token arrays with interleaved tokenIn and tokenOut
        // Pattern: curator1, curator2, tokenIn1-6, tokenOut1-6, router1, router2
        address[] memory addresses = ArraysLibrary.makeAddressArray(
            abi.encode(
                PREPROD_CURATOR1,     // SWAP_MODULE_CALLER_ROLE
                PREPROD_CURATOR2,     // SWAP_MODULE_CALLER_ROLE
                Constants.WETH,       // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.WSTETH,     // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.USDC,       // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.USDT,       // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.USDE,       // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.SUSDE,      // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.WETH,       // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.WSTETH,     // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.USDC,       // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.USDT,       // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.USDE,       // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.SUSDE,      // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.COWSWAP_SETTLEMENT, // SWAP_MODULE_ROUTER_ROLE
                Constants.KYBERSWAP_ROUTER    // SWAP_MODULE_ROUTER_ROLE
            )
        );

        // Build the role array corresponding to the addresses
        bytes32[] memory roles = ArraysLibrary.makeBytes32Array(
            abi.encode(
                Permissions.SWAP_MODULE_CALLER_ROLE,
                Permissions.SWAP_MODULE_CALLER_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_ROUTER_ROLE,
                Permissions.SWAP_MODULE_ROUTER_ROLE
            )
        );

        // Deploy SwapModule
        address swapModule = $.swapModuleFactory.create(
            0,
            PREPROD_PROXY_ADMIN,
            abi.encode(
                PREPROD_LAZY_VAULT_ADMIN,   // admin
                PREPROD_SUBVAULT,           // subvault
                Constants.AAVE_V3_ORACLE,   // oracle
                0.995e8,                    // slippage tolerance (99.5%)
                addresses,                  // addresses array
                roles                       // roles array
            )
        );

        vm.stopBroadcast();

        console.log("");
        console.log("=== PreProd SwapModule Deployment Complete ===");
        console.log("SwapModule address:", swapModule);
        console.log("Subvault:", PREPROD_SUBVAULT);
        console.log("Curator1:", PREPROD_CURATOR1);
        console.log("Curator2:", PREPROD_CURATOR2);
        console.log("");
        console.log("Tokens configured:");
        console.log("  TokenIn: WETH, wstETH, USDC, USDT, USDE, SUSDE");
        console.log("  TokenOut: WETH, wstETH, USDC, USDT, USDE, SUSDE");
        console.log("  Routers: CowswapSettlement, KyberSwapRouter");
        console.log("");
        console.log("Next steps:");
        console.log("1. Grant necessary roles on the subvault if needed");
        console.log("2. Configure merkle root for swap operations");
    }

    /// @notice Deploy SwapModule for prod with custom subvault address
    /// @param customSubvault The subvault address to deploy for
    function runProdCustomSubvault(address customSubvault) external {
        uint256 deployerPk = uint256(bytes32(vm.envBytes("HOT_DEPLOYER")));

        vm.startBroadcast(deployerPk);

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Build the token arrays with interleaved tokenIn and tokenOut
        // Pattern: curator, tokenIn1-7, tokenOut1-7, router1-3
        address[] memory addresses = ArraysLibrary.makeAddressArray(
            abi.encode(
                CURATOR,              // SWAP_MODULE_CALLER_ROLE
                Constants.ETH,        // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.WETH,       // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.WSTETH,     // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.USDC,       // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.USDT,       // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.USDE,       // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.SUSDE,      // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.ETH,        // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.WETH,       // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.WSTETH,     // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.USDC,       // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.USDT,       // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.USDE,       // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.SUSDE,      // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.COWSWAP_SETTLEMENT, // SWAP_MODULE_ROUTER_ROLE
                Constants.KYBERSWAP_ROUTER,   // SWAP_MODULE_ROUTER_ROLE
                Constants.WETH                // SWAP_MODULE_ROUTER_ROLE
            )
        );

        // Build the role array corresponding to the addresses
        bytes32[] memory roles = ArraysLibrary.makeBytes32Array(
            abi.encode(
                Permissions.SWAP_MODULE_CALLER_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_ROUTER_ROLE,
                Permissions.SWAP_MODULE_ROUTER_ROLE,
                Permissions.SWAP_MODULE_ROUTER_ROLE
            )
        );

        // Deploy SwapModule
        address swapModule = $.swapModuleFactory.create(
            0,
            PROXY_ADMIN,
            abi.encode(
                LAZY_VAULT_ADMIN,           // admin
                customSubvault,             // subvault (custom parameter)
                Constants.AAVE_V3_ORACLE,   // oracle
                0.995e8,                    // slippage tolerance (99.5%)
                addresses,                  // addresses array
                roles                       // roles array
            )
        );

        vm.stopBroadcast();

        console.log("");
        console.log("=== Prod SwapModule Deployment Complete (Custom Subvault) ===");
        console.log("SwapModule address:", swapModule);
        console.log("Subvault:", customSubvault);
        console.log("Curator:", CURATOR);
        console.log("");
        console.log("Tokens configured:");
        console.log("  TokenIn: WETH, wstETH, USDC, USDT, USDE, SUSDE");
        console.log("  TokenOut: WETH, wstETH, USDC, USDT, USDE, SUSDE");
        console.log("  Routers: CowswapSettlement, KyberSwapRouter");
        console.log("");
        console.log("Next steps:");
        console.log("1. Grant necessary roles on the subvault if needed");
        console.log("2. Configure merkle root for swap operations");
    }

    /// @notice Deploy SwapModule for preprod with custom subvault address
    /// @param customSubvault The subvault address to deploy for
    function runPreProdCustomSubvault(address customSubvault) external {
        uint256 deployerPk = uint256(bytes32(vm.envBytes("HOT_DEPLOYER")));

        vm.startBroadcast(deployerPk);

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Build the token arrays with interleaved tokenIn and tokenOut
        // Pattern: curator1, curator2, tokenIn1-6, tokenOut1-6, router1, router2
        address[] memory addresses = ArraysLibrary.makeAddressArray(
            abi.encode(
                PREPROD_CURATOR1,     // SWAP_MODULE_CALLER_ROLE
                PREPROD_CURATOR2,     // SWAP_MODULE_CALLER_ROLE
                Constants.WETH,       // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.WSTETH,     // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.USDC,       // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.USDT,       // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.USDE,       // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.SUSDE,      // SWAP_MODULE_TOKEN_IN_ROLE
                Constants.WETH,       // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.WSTETH,     // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.USDC,       // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.USDT,       // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.USDE,       // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.SUSDE,      // SWAP_MODULE_TOKEN_OUT_ROLE
                Constants.COWSWAP_SETTLEMENT, // SWAP_MODULE_ROUTER_ROLE
                Constants.KYBERSWAP_ROUTER    // SWAP_MODULE_ROUTER_ROLE
            )
        );

        // Build the role array corresponding to the addresses
        bytes32[] memory roles = ArraysLibrary.makeBytes32Array(
            abi.encode(
                Permissions.SWAP_MODULE_CALLER_ROLE,
                Permissions.SWAP_MODULE_CALLER_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_ROUTER_ROLE,
                Permissions.SWAP_MODULE_ROUTER_ROLE
            )
        );

        // Deploy SwapModule
        address swapModule = $.swapModuleFactory.create(
            0,
            PREPROD_PROXY_ADMIN,
            abi.encode(
                PREPROD_LAZY_VAULT_ADMIN,   // admin
                customSubvault,             // subvault (custom parameter)
                Constants.AAVE_V3_ORACLE,   // oracle
                0.995e8,                    // slippage tolerance (99.5%)
                addresses,                  // addresses array
                roles                       // roles array
            )
        );

        vm.stopBroadcast();

        console.log("");
        console.log("=== PreProd SwapModule Deployment Complete (Custom Subvault) ===");
        console.log("SwapModule address:", swapModule);
        console.log("Subvault:", customSubvault);
        console.log("Curator1:", PREPROD_CURATOR1);
        console.log("Curator2:", PREPROD_CURATOR2);
        console.log("");
        console.log("Tokens configured:");
        console.log("  TokenIn: WETH, wstETH, USDC, USDT, USDE, SUSDE");
        console.log("  TokenOut: WETH, wstETH, USDC, USDT, USDE, SUSDE");
        console.log("  Routers: CowswapSettlement, KyberSwapRouter");
        console.log("");
        console.log("Next steps:");
        console.log("1. Grant necessary roles on the subvault if needed");
        console.log("2. Configure merkle root for swap operations");
    }
}
