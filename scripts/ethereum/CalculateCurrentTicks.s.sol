// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

interface IUniswapV3Pool {
    function slot0() external view returns (
        uint160 sqrtPriceX96,
        int24 tick,
        uint16 observationIndex,
        uint16 observationCardinality,
        uint16 observationCardinalityNext,
        uint8 feeProtocol,
        bool unlocked
    );
}

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

/**
 * @title CalculateCurrentTicks
 * @notice Calculate optimal tick ranges for LP position based on current price
 */
contract CalculateCurrentTicks is Script {
    address constant USDC_WETH_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640; // 0.3% fee
    address constant ETH_USD_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    int24 constant TICK_SPACING = 60; // for 0.3% fee tier

    function getEthUsdPrice() internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(ETH_USD_FEED);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint8 decimals = priceFeed.decimals();

        console.log("ETH/USD Price from Chainlink: $%s", uint256(price) / 10**decimals);
        return uint256(price);
    }

    function getCurrentTick() internal view returns (int24) {
        IUniswapV3Pool pool = IUniswapV3Pool(USDC_WETH_POOL);
        (, int24 tick,,,,,) = pool.slot0();
        return tick;
    }

    function calculateOptimalRange(uint256 percentRange) internal view {
        console.log("=== Calculating Optimal LP Position ===");
        console.log("");

        // 1. Get current ETH price from Chainlink
        uint256 ethUsdPrice = getEthUsdPrice();
        console.log("");

        // 2. Get current tick from Uniswap V3 pool
        int24 currentTick = getCurrentTick();
        console.log("Current tick from pool: %s", vm.toString(currentTick));
        console.log("");

        // 3. Calculate tick range based on percentage
        // Each tick represents ~0.01% price change
        // For X% range: ticks = X * 100
        int24 tickRange = int24(int256(percentRange * 100));
        int24 tickLower = currentTick - tickRange;
        int24 tickUpper = currentTick + tickRange;

        // Round to tick spacing multiples (60 for 0.3% fee)
        tickLower = (tickLower / TICK_SPACING) * TICK_SPACING;
        tickUpper = (tickUpper / TICK_SPACING) * TICK_SPACING;

        console.log("=== Calculated Tick Range (+-%s%%) ===", percentRange);
        console.log("Tick Lower: %s", vm.toString(tickLower));
        console.log("Tick Upper: %s", vm.toString(tickUpper));
        console.log("Tick Spacing: %s", vm.toString(TICK_SPACING));
        console.log("");

        // 4. Calculate token amounts
        uint256 usdcAmount = 5e5; // 0.5 USDC
        uint256 wethAmount = (5e7 * 1e18) / ethUsdPrice; // $0.50 worth of ETH

        console.log("=== Token Amounts ===");
        console.log("USDC (token0): %s (0.5 USDC)", usdcAmount);
        console.log("WETH (token1): %s wei", wethAmount);
        console.log("WETH in ETH: %s", wethAmount / 1e18);
        console.log("");

        // 5. Calculate min amounts with 1% slippage
        uint256 amount0Min = usdcAmount * 99 / 100;
        uint256 amount1Min = wethAmount * 99 / 100;

        console.log("=== Slippage Protection (1%% slippage) ===");
        console.log("amount0Min: %s", amount0Min);
        console.log("amount1Min: %s", amount1Min);
        console.log("");

        // 6. Calculate deadline (current time + 30 minutes)
        uint256 deadline = block.timestamp + 1800;
        console.log("=== Deadline ===");
        console.log("Current timestamp: %s", block.timestamp);
        console.log("Deadline (now + 30 min): %s", deadline);
        console.log("");

        // 7. Calculate price range in USD terms
        // Price = 1.0001^tick
        // For USDC/WETH pool, price is in USDC per WETH
        console.log("=== Price Range (approximate) ===");
        console.log("Current ETH price: $%s", uint256(ethUsdPrice) / 1e8);

        // Approximate price range
        // Each tick is ~0.01%, so X ticks = X * 0.01%
        uint256 lowerPriceUsd = (uint256(ethUsdPrice) * (10000 - percentRange * 100)) / 10000 / 1e8;
        uint256 upperPriceUsd = (uint256(ethUsdPrice) * (10000 + percentRange * 100)) / 10000 / 1e8;

        console.log("Lower price (~%s%% below): $%s", percentRange, lowerPriceUsd);
        console.log("Upper price (~%s%% above): $%s", percentRange, upperPriceUsd);
        console.log("");

        console.log("=== Summary for Safe Transaction ===");
        console.log("Use these parameters for mint:");
        console.log("  token0: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48 (USDC)");
        console.log("  token1: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 (WETH)");
        console.log("  fee: 3000");
        console.log("  tickLower: %s", vm.toString(tickLower));
        console.log("  tickUpper: %s", vm.toString(tickUpper));
        console.log("  amount0Desired: %s", usdcAmount);
        console.log("  amount1Desired: %s", wethAmount);
        console.log("  amount0Min: %s", amount0Min);
        console.log("  amount1Min: %s", amount1Min);
        console.log("  recipient: 0x9A47b63143FfA375405ddcf0952Fd2C1570915d8");
        console.log("  deadline: %s", deadline);
    }

    function run() external view {
        // Calculate with 5% range
        calculateOptimalRange(5);
    }
}
