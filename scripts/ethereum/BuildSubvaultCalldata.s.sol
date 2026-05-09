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

/**
 * @title BuildSubvaultCalldata
 * @notice Build complete encoded calldata for subvault.call() function
 */
contract BuildSubvaultCalldata is Script {
    // Addresses
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC_WETH_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640; // 0.3% fee
    address constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant ETH_USD_CHAINLINK = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;

    address constant SUBVAULT = 0x9A47b63143FfA375405ddcf0952Fd2C1570915d8;

    // Verification data and proofs from JSON file (index 0 = USDC approval)
    bytes constant USDC_VERIFICATION_DATA = hex"0000000000000000000000000000000263fb29c3d6b0c5837883519ef05ea20ad399575cc1703c84da2300f1976db62c6ce77b06a6c7871f003bd58074f43426000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    bytes32[4] USDC_PROOFS = [
        bytes32(0xa2ed854b213d3b48bff10ba4603124ef6ee14d5e68bfbbde051a920cd2a363b4),
        bytes32(0x72f66c25d311547ca43de7e34137886f32d5f74684e75b9c9e2f189227357612),
        bytes32(0xe9430d004fd824d83f4f59a0b3aa7512cc654890ca42eea5da490a41a5d04568),
        bytes32(0x46f2f58ce7dd4f3dee6a9f3dd8c5f3691ab3b7f9ecd5f14a88c3349e8f252a05)
    ];

    // Verification data and proofs from JSON file (index 1 = WETH approval)
    bytes constant WETH_VERIFICATION_DATA = hex"0000000000000000000000000000000263fb29c3d6b0c5837883519ef05ea20ad399575cc1703c84da2300f1976db62c6ce77b06a6c7871f003bd58074f43426000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    bytes32[4] WETH_PROOFS = [
        bytes32(0xa2ed854b213d3b48bff10ba4603124ef6ee14d5e68bfbbde051a920cd2a363b4),
        bytes32(0x72f66c25d311547ca43de7e34137886f32d5f74684e75b9c9e2f189227357612),
        bytes32(0xe9430d004fd824d83f4f59a0b3aa7512cc654890ca42eea5da490a41a5d04568),
        bytes32(0x46f2f58ce7dd4f3dee6a9f3dd8c5f3691ab3b7f9ecd5f14a88c3349e8f252a05)
    ];

    // Verification data and proofs from JSON file (index 2 = Mint)
    bytes constant MINT_VERIFICATION_DATA = hex"0000000000000000000000000000000263fb29c3d6b0c5837883519ef05ea20a008fe4b9d1ca3f73c3a3efdf75ea0a1a943665274afeb7de8819e8fdd6e3fa33000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001c400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000bb80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009a47b63143ffa375405ddcf0952fd2c1570915d8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    bytes32[4] MINT_PROOFS = [
        bytes32(0xcefc0580ae4db6b08de25e19df25245e4efb5a15066a0b6c6e6d3cd77061e87f),
        bytes32(0x9b3aa4761e87b1eddd59e7da32ce7b75a21844047f274ad8a6e072e627e366fd),
        bytes32(0x9f4451f5535fb6e7f0e1aeb4087b4be904066e4cb3fb43141198d2606f313c30),
        bytes32(0x46f2f58ce7dd4f3dee6a9f3dd8c5f3691ab3b7f9ecd5f14a88c3349e8f252a05)
    ];

    /**
     * @notice Build all three transactions as encoded subvault.call() data
     * @param percentRange Percentage range for ticks (e.g., 5 for ±5%)
     */
    function buildAllTransactions(uint256 percentRange) external view {
        console.log("=== Building Complete Subvault Call Transactions ===");
        console.log("Target: %s (Subvault)", SUBVAULT);
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

        console.log("Calculated Parameters:");
        console.log("ETH Price: $%s", ethUsdPrice / 1e8);
        console.log("USDC Amount: %s", usdcAmount);
        console.log("WETH Amount: %s", wethAmount);
        console.log("Tick Lower: %s", vm.toString(tickLower));
        console.log("Tick Upper: %s", vm.toString(tickUpper));
        console.log("");

        // Build Transaction 1: USDC Approval
        bytes memory usdcApprovalCalldata = abi.encodeCall(IERC20.approve, (POSITION_MANAGER, usdcAmount));
        bytes32[] memory usdcProofs = new bytes32[](4);
        for (uint256 i = 0; i < 4; i++) {
            usdcProofs[i] = USDC_PROOFS[i];
        }

        // Encode struct fields directly inline - Solidity will handle the tuple encoding
        bytes memory tx1 = abi.encodeWithSelector(
            0xa6df3a8d, // call(address,uint256,bytes,(uint8,bytes,bytes32[]))
            USDC,                      // where: target contract
            0,                         // value: ETH to send
            usdcApprovalCalldata,      // data: calldata
            uint8(3),                  // payload.verificationType (BITMASK_VERIFIER)
            USDC_VERIFICATION_DATA,    // payload.verificationData
            usdcProofs                 // payload.proof
        );

        console.log("=== Transaction 1: USDC Approval ===");
        console.log("Target: %s (Subvault)", SUBVAULT);
        console.log("Value: 0");
        console.log("Data (encoded subvault.call):");
        console.logBytes(tx1);
        console.log("");

        // Build Transaction 2: WETH Approval
        bytes memory wethApprovalCalldata = abi.encodeCall(IERC20.approve, (POSITION_MANAGER, wethAmount));
        bytes32[] memory wethProofs = new bytes32[](4);
        for (uint256 i = 0; i < 4; i++) {
            wethProofs[i] = WETH_PROOFS[i];
        }

        bytes memory tx2 = abi.encodeWithSelector(
            0xa6df3a8d, // call(address,uint256,bytes,(uint8,bytes,bytes32[]))
            WETH,                      // where: target contract
            0,                         // value: ETH to send
            wethApprovalCalldata,      // data: calldata
            uint8(3),                  // payload.verificationType (BITMASK_VERIFIER)
            WETH_VERIFICATION_DATA,    // payload.verificationData
            wethProofs                 // payload.proof
        );

        console.log("=== Transaction 2: WETH Approval ===");
        console.log("Target: %s (Subvault)", SUBVAULT);
        console.log("Value: 0");
        console.log("Data (encoded subvault.call):");
        console.logBytes(tx2);
        console.log("");

        // Build Transaction 3: Mint Position
        bytes memory mintCalldata = abi.encodeWithSignature(
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

        bytes32[] memory mintProofs = new bytes32[](4);
        for (uint256 i = 0; i < 4; i++) {
            mintProofs[i] = MINT_PROOFS[i];
        }

        bytes memory tx3 = abi.encodeWithSelector(
            0xa6df3a8d, // call(address,uint256,bytes,(uint8,bytes,bytes32[]))
            POSITION_MANAGER,          // where: target contract
            0,                         // value: ETH to send
            mintCalldata,              // data: calldata
            uint8(3),                  // payload.verificationType (BITMASK_VERIFIER)
            MINT_VERIFICATION_DATA,    // payload.verificationData
            mintProofs                 // payload.proof
        );

        console.log("=== Transaction 3: Mint LP Position ===");
        console.log("Target: %s (Subvault)", SUBVAULT);
        console.log("Value: 0");
        console.log("Data (encoded subvault.call):");
        console.logBytes(tx3);
        console.log("");

        console.log("=== Summary ===");
        console.log("All three transactions are encoded for subvault.call()");
        console.log("Simply paste each data blob into Safe UI with:");
        console.log("- Target: %s", SUBVAULT);
        console.log("- Value: 0");
        console.log("- Custom data checkbox: CHECKED");
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
     * @notice Run with 5% range
     */
    function run() external view {
        this.buildAllTransactions(5);
    }
}
