// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

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
    function tickSpacing() external view returns (int24);
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

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }
}

/**
 * @title BuildUniswapV3Mint
 * @notice Helper script to calculate parameters and build calldata for Uniswap V3 LP minting
 */
contract BuildUniswapV3Mint is Script {
    // Addresses
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC_WETH_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640; // 0.3% fee
    address constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant ETH_USD_CHAINLINK = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    address constant SUBVAULT = 0x9A47b63143FfA375405ddcf0952Fd2C1570915d8;

    /**
     * @notice Calculate all parameters for minting a position with $0.50 of each token
     * @param percentRange Percentage range for ticks (e.g., 5 for ±5%)
     */
    function calculateMintParams(uint256 percentRange) external view {
        console.log("=== Calculating Uniswap V3 Mint Parameters ===");
        console.log("");

        // 1. Get ETH/USD price from Chainlink
        uint256 ethUsdPrice = getEthUsdPrice();
        console.log("ETH/USD Price from Chainlink: $%s", ethUsdPrice / 1e8);
        console.log("");

        // 2. Get current tick from pool
        IUniswapV3Pool pool = IUniswapV3Pool(USDC_WETH_POOL);
        (, int24 currentTick, , , , , ) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();

        console.log("Current tick: %s", vm.toString(currentTick));
        console.log("Tick spacing: %s", vm.toString(tickSpacing));
        console.log("");

        // 3. Calculate tick range (±5% = ±500 basis points ≈ ±500 ticks)
        int24 tickRange = int24(int256(percentRange * 100));
        int24 tickLower = currentTick - tickRange;
        int24 tickUpper = currentTick + tickRange;

        // Round to tick spacing multiples
        tickLower = (tickLower / tickSpacing) * tickSpacing;
        tickUpper = (tickUpper / tickSpacing) * tickSpacing;

        console.log("Tick range: +-%s%%", percentRange);
        console.log("Tick offset: +-%s ticks", vm.toString(tickRange));
        console.log("tickLower: %s", vm.toString(tickLower));
        console.log("tickUpper: %s", vm.toString(tickUpper));
        console.log("");

        // 4. Calculate token amounts for $0.50 each
        // $0.50 USDC = 0.5 * 1e6 (USDC has 6 decimals)
        uint256 usdcAmount = 5e5; // $0.50 USDC

        // $0.50 ETH = 0.5 / ethUsdPrice * 1e18
        uint256 wethAmount = (5e7 * 1e18) / ethUsdPrice; // 0.5 * 1e8 / price * 1e18

        console.log("Token amounts (5%% range, balanced):");
        console.log("USDC (token0): %s (= $0.50)", usdcAmount);
        console.log("WETH (token1): %s (= $0.50)", wethAmount);
        console.log("");

        // 5. Set slippage (1%)
        uint256 amount0Min = usdcAmount * 99 / 100;
        uint256 amount1Min = wethAmount * 99 / 100;

        console.log("Slippage protection (1%%):");
        console.log("amount0Min: %s", amount0Min);
        console.log("amount1Min: %s", amount1Min);
        console.log("");

        // 6. Print the MintParams
        console.log("=== MintParams ===");
        console.log("token0: %s (USDC)", USDC);
        console.log("token1: %s (WETH)", WETH);
        console.log("fee: 3000");
        console.log("tickLower: %s", vm.toString(tickLower));
        console.log("tickUpper: %s", vm.toString(tickUpper));
        console.log("amount0Desired: %s", usdcAmount);
        console.log("amount1Desired: %s", wethAmount);
        console.log("amount0Min: %s", amount0Min);
        console.log("amount1Min: %s", amount1Min);
        console.log("recipient: %s (subvault)", SUBVAULT);
        console.log("deadline: <block.timestamp + 1800>");
        console.log("");
    }

    /**
     * @notice Build complete transaction calldata including approvals and mint
     * @param percentRange Percentage range for ticks (e.g., 5 for ±5%)
     */
    function buildCompleteTx(uint256 percentRange) external view returns (
        bytes memory usdcApprovalCalldata,
        bytes memory wethApprovalCalldata,
        bytes memory mintCalldata
    ) {
        console.log("=== Building Complete Transaction Calldata ===");
        console.log("");

        // Get ETH price and calculate amounts
        uint256 ethUsdPrice = getEthUsdPrice();
        uint256 usdcAmount = 5e5; // $0.50
        uint256 wethAmount = (5e7 * 1e18) / ethUsdPrice;

        // Get tick parameters
        IUniswapV3Pool pool = IUniswapV3Pool(USDC_WETH_POOL);
        (, int24 currentTick, , , , , ) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();

        int24 tickRange = int24(int256(percentRange * 100));
        int24 tickLower = ((currentTick - tickRange) / tickSpacing) * tickSpacing;
        int24 tickUpper = ((currentTick + tickRange) / tickSpacing) * tickSpacing;

        uint256 amount0Min = usdcAmount * 99 / 100;
        uint256 amount1Min = wethAmount * 99 / 100;
        uint256 deadline = block.timestamp + 1800; // 30 minutes

        // Build calldata
        usdcApprovalCalldata = abi.encodeCall(IERC20.approve, (POSITION_MANAGER, usdcAmount));
        wethApprovalCalldata = abi.encodeCall(IERC20.approve, (POSITION_MANAGER, wethAmount));

        mintCalldata = abi.encodeWithSignature(
            "mint((address,address,uint24,int24,int24,uint256,uint256,uint256,uint256,address,uint256))",
            USDC,           // token0
            WETH,           // token1
            uint24(3000),   // fee
            tickLower,      // tickLower
            tickUpper,      // tickUpper
            usdcAmount,     // amount0Desired
            wethAmount,     // amount1Desired
            amount0Min,     // amount0Min
            amount1Min,     // amount1Min
            SUBVAULT,       // recipient
            deadline        // deadline
        );

        console.log("1. USDC Approval Calldata:");
        console.log("   Target: %s", USDC);
        console.logBytes(usdcApprovalCalldata);
        console.log("");

        console.log("2. WETH Approval Calldata:");
        console.log("   Target: %s", WETH);
        console.logBytes(wethApprovalCalldata);
        console.log("");

        console.log("3. Mint Calldata:");
        console.log("   Target: %s", POSITION_MANAGER);
        console.logBytes(mintCalldata);
        console.log("");

        return (usdcApprovalCalldata, wethApprovalCalldata, mintCalldata);
    }

    /**
     * @notice Build subvault.call() encoded data with verification
     * @dev This builds the complete calldata for executing through the subvault with merkle proof verification
     */
    function buildSubvaultCallWithProof(uint256 percentRange) external view {
        console.log("=== Building Subvault Call with Merkle Proof ===");
        console.log("Subvault: %s", SUBVAULT);
        console.log("");

        // Get all parameters
        uint256 ethUsdPrice = getEthUsdPrice();
        uint256 usdcAmount = 5e5;
        uint256 wethAmount = (5e7 * 1e18) / ethUsdPrice;

        IUniswapV3Pool pool = IUniswapV3Pool(USDC_WETH_POOL);
        (, int24 currentTick, , , , , ) = pool.slot0();
        int24 tickSpacing = pool.tickSpacing();

        int24 tickRange = int24(int256(percentRange * 100));
        int24 tickLower = ((currentTick - tickRange) / tickSpacing) * tickSpacing;
        int24 tickUpper = ((currentTick + tickRange) / tickSpacing) * tickSpacing;

        uint256 amount0Min = usdcAmount * 99 / 100;
        uint256 amount1Min = wethAmount * 99 / 100;
        uint256 deadline = block.timestamp + 1800;

        console.log("Step 1: USDC Approval");
        console.log("---------------------------------------");
        console.log("To execute: subvault.call(verificationData, proofs, target, value, calldata)");
        console.log("");
        console.log("target: %s", USDC);
        console.log("value: 0");
        console.log("calldata:");
        bytes memory usdcApproval = abi.encodeCall(IERC20.approve, (POSITION_MANAGER, usdcAmount));
        console.logBytes(usdcApproval);
        console.log("");
        console.log("verificationData: <from JSON file - index 0>");
        console.log("proofs: <from JSON file - index 0>");
        console.log("");

        console.log("Step 2: WETH Approval");
        console.log("---------------------------------------");
        console.log("target: %s", WETH);
        console.log("value: 0");
        console.log("calldata:");
        bytes memory wethApproval = abi.encodeCall(IERC20.approve, (POSITION_MANAGER, wethAmount));
        console.logBytes(wethApproval);
        console.log("");
        console.log("verificationData: <from JSON file - index 1>");
        console.log("proofs: <from JSON file - index 1>");
        console.log("");

        console.log("Step 3: Mint Position");
        console.log("---------------------------------------");
        console.log("target: %s", POSITION_MANAGER);
        console.log("value: 0");
        console.log("calldata:");
        bytes memory mintCall = abi.encodeWithSignature(
            "mint((address,address,uint24,int24,int24,uint256,uint256,uint256,uint256,address,uint256))",
            USDC, WETH, uint24(3000), tickLower, tickUpper,
            usdcAmount, wethAmount, amount0Min, amount1Min,
            SUBVAULT, deadline
        );
        console.logBytes(mintCall);
        console.log("");
        console.log("verificationData: <from JSON file - index 2>");
        console.log("proofs: <from JSON file - index 2>");
        console.log("");

        console.log("=== Summary ===");
        console.log("You need to:");
        console.log("1. Load the JSON file: ethereum:tqETH:preprod:sv5:uniswapV3-lean.json");
        console.log("2. For USDC approval: use merkle_proofs[0]");
        console.log("3. For WETH approval: use merkle_proofs[1]");
        console.log("4. For mint: use merkle_proofs[2]");
        console.log("");
        console.log("Parameters calculated:");
        console.log("  ETH Price: $%s", ethUsdPrice / 1e8);
        console.log("  USDC Amount: %s ($0.50)", usdcAmount);
        console.log("  WETH Amount: %s ($0.50)", wethAmount);
        console.log("  Current Tick: %s", vm.toString(currentTick));
        console.log("  Tick Lower: %s", vm.toString(tickLower));
        console.log("  Tick Upper: %s", vm.toString(tickUpper));
        console.log("  Slippage: 1%%");
        console.log("  Deadline: %s", deadline);
    }

    /**
     * @notice Get ETH/USD price from Chainlink
     */
    function getEthUsdPrice() internal view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(ETH_USD_CHAINLINK);
        (, int256 answer, , , ) = priceFeed.latestRoundData();
        return uint256(answer); // Returns price with 8 decimals
    }

    /**
     * @notice Run all calculations with 5% range
     */
    function run() external view {
        this.calculateMintParams(5);
        console.log("");
        console.log("======================");
        console.log("");
        this.buildSubvaultCallWithProof(5);
    }
}
