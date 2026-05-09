// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IVerifier} from "../../src/interfaces/permissions/IVerifier.sol";
import {ICallModule} from "../../src/interfaces/modules/ICallModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title FixedEncode
 * @notice Use abi.encodeCall with the actual interface to get proper encoding
 */
contract FixedEncode is Script {
    address constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant SUBVAULT = 0x9A47b63143FfA375405ddcf0952Fd2C1570915d8;

    // Updated parameters - current tick 195874
    uint256 constant USDC_AMOUNT = 500000;
    uint256 constant WETH_AMOUNT = 160762424336601;
    int24 constant TICK_LOWER = 195360;  // 5% below current
    int24 constant TICK_UPPER = 196380;  // 5% above current
    uint256 constant AMOUNT_0_MIN = 1;  // Accept any non-zero USDC
    uint256 constant AMOUNT_1_MIN = 0;  // Accept 0 WETH (since we're at edge)
    uint256 constant DEADLINE = 1768278815;

    function encodeUsdcApproval() internal view {
        // USDC Approval verification data and proofs
        bytes memory verificationData = hex"0000000000000000000000000000000263fb29c3d6b0c5837883519ef05ea20ad399575cc1703c84da2300f1976db62c6ce77b06a6c7871f003bd58074f43426000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        bytes32[] memory proofs = new bytes32[](4);
        proofs[0] = 0xa2ed854b213d3b48bff10ba4603124ef6ee14d5e68bfbbde051a920cd2a363b4;
        proofs[1] = 0x72f66c25d311547ca43de7e34137886f32d5f74684e75b9c9e2f189227357612;
        proofs[2] = 0xe9430d004fd824d83f4f59a0b3aa7512cc654890ca42eea5da490a41a5d04568;
        proofs[3] = 0x46f2f58ce7dd4f3dee6a9f3dd8c5f3691ab3b7f9ecd5f14a88c3349e8f252a05;

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proofs
        });

        bytes memory approvalCalldata = abi.encodeCall(IERC20.approve, (POSITION_MANAGER, USDC_AMOUNT));

        bytes memory encoded = abi.encodeCall(
            ICallModule.call,
            (USDC, 0, approvalCalldata, payload)
        );

        console.log("=== Transaction 1: USDC Approval ===");
        console.log("Target: %s (Subvault)", SUBVAULT);
        console.log("Value: 0");
        console.logBytes(encoded);
        console.log("");
    }

    function encodeWethApproval() internal view {
        // WETH Approval verification data and proofs (same as USDC since they use the same bitmask pattern)
        bytes memory verificationData = hex"0000000000000000000000000000000263fb29c3d6b0c5837883519ef05ea20ad399575cc1703c84da2300f1976db62c6ce77b06a6c7871f003bd58074f43426000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        bytes32[] memory proofs = new bytes32[](4);
        proofs[0] = 0xa2ed854b213d3b48bff10ba4603124ef6ee14d5e68bfbbde051a920cd2a363b4;
        proofs[1] = 0x72f66c25d311547ca43de7e34137886f32d5f74684e75b9c9e2f189227357612;
        proofs[2] = 0xe9430d004fd824d83f4f59a0b3aa7512cc654890ca42eea5da490a41a5d04568;
        proofs[3] = 0x46f2f58ce7dd4f3dee6a9f3dd8c5f3691ab3b7f9ecd5f14a88c3349e8f252a05;

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proofs
        });

        bytes memory approvalCalldata = abi.encodeCall(IERC20.approve, (POSITION_MANAGER, WETH_AMOUNT));

        bytes memory encoded = abi.encodeCall(
            ICallModule.call,
            (WETH, 0, approvalCalldata, payload)
        );

        console.log("=== Transaction 2: WETH Approval ===");
        console.log("Target: %s (Subvault)", SUBVAULT);
        console.log("Value: 0");
        console.logBytes(encoded);
        console.log("");
    }

    function encodeMintTransaction() internal view {
        // Mint parameters with updated ticks and amounts
        bytes memory mintCalldata = abi.encodeWithSignature(
            "mint((address,address,uint24,int24,int24,uint256,uint256,uint256,uint256,address,uint256))",
            USDC, WETH, uint24(3000), TICK_LOWER, TICK_UPPER,
            USDC_AMOUNT, WETH_AMOUNT,
            AMOUNT_0_MIN, AMOUNT_1_MIN,
            SUBVAULT, DEADLINE
        );

        // Verification data
        bytes memory verificationData = hex"0000000000000000000000000000000263fb29c3d6b0c5837883519ef05ea20a008fe4b9d1ca3f73c3a3efdf75ea0a1a943665274afeb7de8819e8fdd6e3fa33000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001c400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000bb80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009a47b63143ffa375405ddcf0952fd2c1570915d8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        // Proofs
        bytes32[] memory proofs = new bytes32[](4);
        proofs[0] = 0xcefc0580ae4db6b08de25e19df25245e4efb5a15066a0b6c6e6d3cd77061e87f;
        proofs[1] = 0x9b3aa4761e87b1eddd59e7da32ce7b75a21844047f274ad8a6e072e627e366fd;
        proofs[2] = 0x9f4451f5535fb6e7f0e1aeb4087b4be904066e4cb3fb43141198d2606f313c30;
        proofs[3] = 0x46f2f58ce7dd4f3dee6a9f3dd8c5f3691ab3b7f9ecd5f14a88c3349e8f252a05;

        // Create payload struct
        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proofs
        });

        // Use abi.encodeCall with the actual interface function
        bytes memory encoded = abi.encodeCall(
            ICallModule.call,
            (POSITION_MANAGER, 0, mintCalldata, payload)
        );

        console.log("=== Transaction 3: Mint LP Position ===");
        console.log("Target: %s (Subvault)", SUBVAULT);
        console.log("Value: 0");
        console.logBytes(encoded);
        console.log("");
    }

    function run() external view {
        encodeUsdcApproval();
        encodeWethApproval();
        encodeMintTransaction();
    }
}
