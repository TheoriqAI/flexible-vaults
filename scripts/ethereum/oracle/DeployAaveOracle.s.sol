// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {AaveOracle, IPoolAddressesProvider} from "src/external/aave/AaveOracle.sol";

/// @notice Deploy script for AaveOracle
/// @dev Run with: forge script scripts/ethereum/oracle/DeployAaveOracle.s.sol:DeployAaveOracle --rpc-url https://rpc.mevblocker.io --broadcast --via-ir
contract DeployAaveOracle is Script {
    // Constructor parameters
    address public constant ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    address public constant FALLBACK_ORACLE = 0x54586bE62E3c3580375aE3723C145253060Ca0C2;
    address public constant BASE_CURRENCY = address(0); // USD
    uint256 public constant BASE_CURRENCY_UNIT = 100000000; // 8 decimals (1e8)

    // Assets and oracles to set (NUSD must remain index 0)
    address public constant NUSD = 0xE556ABa6fe6036275Ec1f87eda296BE72C811BCE;
    address public constant NUSD_ORACLE = 0x5e7281f74e74D76347f0b8f4a36Fd3cb29c19d95;

    address public constant SIERRA = 0x6bf7788EAA948d9fFBA7E9bb386E2D3c9810e0fc;
    address public constant SIERRA_ORACLE = 0x9269127F104C040AB526575573c23F3e67401aD9;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("HOT_DEPLOYER");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== Deploying AaveOracle ===");
        console.log("Deployer:", deployer);
        console.log("");
        console.log("Constructor parameters:");
        console.log("  addressesProvider:", ADDRESSES_PROVIDER);
        console.log("  fallbackOracle:", FALLBACK_ORACLE);
        console.log("  baseCurrency:", BASE_CURRENCY);
        console.log("  baseCurrencyUnit:", BASE_CURRENCY_UNIT);
        console.log("  asset[0] (NUSD):", NUSD, "->", NUSD_ORACLE);
        console.log("  asset[1] (SIERRA):", SIERRA, "->", SIERRA_ORACLE);
        console.log("");

        // Build arrays for assets and sources
        address[] memory assets = new address[](2);
        assets[0] = NUSD;
        assets[1] = SIERRA;

        address[] memory sources = new address[](2);
        sources[0] = NUSD_ORACLE;
        sources[1] = SIERRA_ORACLE;

        vm.startBroadcast(deployerPrivateKey);

        AaveOracle aaveOracle = new AaveOracle(
            IPoolAddressesProvider(ADDRESSES_PROVIDER),
            assets,
            sources,
            FALLBACK_ORACLE,
            BASE_CURRENCY,
            BASE_CURRENCY_UNIT
        );

        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("AaveOracle deployed at:", address(aaveOracle));
        console.log("");
        console.log("Verify with:");
        console.log("forge verify-contract", address(aaveOracle), "lib/aave-v3-core/contracts/misc/AaveOracle.sol:AaveOracle --chain mainnet --watch");
    }
}
