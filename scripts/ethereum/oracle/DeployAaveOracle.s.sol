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

    // PermissionedChainlinkOracle feeds deployed 2026-07-01 (see CLAUDE.md §A)
    address public constant REUSDE = 0xdDC0f880ff6e4e22E4B74632fBb43Ce4DF6cCC5a;
    address public constant REUSDE_ORACLE = 0x5b430Dfb2DfD72b906C6BfF0b326640090F6AEB4;

    address public constant REUSD = 0x5086bf358635B81D8C47C66d1C8b9E567Db70c72;
    address public constant REUSD_ORACLE = 0x7De0912436f4081eA6F5F69c0b6a34b64cCf1a38;

    address public constant USD3 = 0x056B269Eb1f75477a8666ae8C7fE01b64dD55eCc;
    address public constant USD3_ORACLE = 0xd05C96aad89AC7F15ACd06A88CD28EC90f06537E;

    address public constant SUSD3 = 0xf689555121e529Ff0463e191F9Bd9d1E496164a7;
    address public constant SUSD3_ORACLE = 0x2E55fA1aA757FdeDfa6A2F34B1BDbedFFcac46bA;

    address public constant SNUSD = 0x08EFCC2F3e61185D0EA7F8830B3FEc9Bfa2EE313;
    address public constant SNUSD_ORACLE = 0xd3C3F2471e1A9408915ee2Dfca6815c1A14f1fF0;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_KEY");
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
        console.log("  asset[2] (reUSDe):", REUSDE, "->", REUSDE_ORACLE);
        console.log("  asset[3] (reUSD):", REUSD, "->", REUSD_ORACLE);
        console.log("  asset[4] (USD3):", USD3, "->", USD3_ORACLE);
        console.log("  asset[5] (sUSD3):", SUSD3, "->", SUSD3_ORACLE);
        console.log("  asset[6] (sNUSD):", SNUSD, "->", SNUSD_ORACLE);
        console.log("");

        // Build arrays for assets and sources (NUSD must remain index 0)
        address[] memory assets = new address[](7);
        assets[0] = NUSD;
        assets[1] = SIERRA;
        assets[2] = REUSDE;
        assets[3] = REUSD;
        assets[4] = USD3;
        assets[5] = SUSD3;
        assets[6] = SNUSD;

        address[] memory sources = new address[](7);
        sources[0] = NUSD_ORACLE;
        sources[1] = SIERRA_ORACLE;
        sources[2] = REUSDE_ORACLE;
        sources[3] = REUSD_ORACLE;
        sources[4] = USD3_ORACLE;
        sources[5] = SUSD3_ORACLE;
        sources[6] = SNUSD_ORACLE;

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
