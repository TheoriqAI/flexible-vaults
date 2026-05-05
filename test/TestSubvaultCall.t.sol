// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {IVerifier} from "../src/interfaces/permissions/IVerifier.sol";
import {ICallModule} from "../src/interfaces/modules/ICallModule.sol";

contract TestSubvaultCall is Test {
    address constant SUBVAULT = 0x9A47b63143FfA375405ddcf0952Fd2C1570915d8;
    address constant POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant CURATOR = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec;

    function testCallWithProofs() external {
        vm.createSelectFork("https://rpc.mevblocker.io");

        bytes32[] memory proofs = new bytes32[](4);
        proofs[0] = 0xcefc0580ae4db6b08de25e19df25245e4efb5a15066a0b6c6e6d3cd77061e87f;
        proofs[1] = 0x9b3aa4761e87b1eddd59e7da32ce7b75a21844047f274ad8a6e072e627e366fd;
        proofs[2] = 0x9f4451f5535fb6e7f0e1aeb4087b4be904066e4cb3fb43141198d2606f313c30;
        proofs[3] = 0x46f2f58ce7dd4f3dee6a9f3dd8c5f3691ab3b7f9ecd5f14a88c3349e8f252a05;

        bytes memory verificationData = hex"0000000000000000000000000000000263fb29c3d6b0c5837883519ef05ea20a008fe4b9d1ca3f73c3a3efdf75ea0a1a943665274afeb7de8819e8fdd6e3fa33000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000001c400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000a0b86991c6218b36c1d19d4a2e9eb0ce3606eb48000000000000000000000000c02aaa39b223fe8d0a0e5c4f27ead9083c756cc20000000000000000000000000000000000000000000000000000000000000bb80000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000009a47b63143ffa375405ddcf0952fd2c1570915d8000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proofs
        });

        bytes memory mintData = abi.encodeWithSignature(
            "mint((address,address,uint24,int24,int24,uint256,uint256,uint256,uint256,address,uint256))",
            address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48), // USDC
            address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // WETH
            uint24(3000),
            int24(195960),
            int24(196560),
            uint256(500000),
            uint256(161455002255954),
            uint256(495000),
            uint256(159920752233194),
            SUBVAULT,
            uint256(1768278601) // current time + 30 minutes
        );

        console.log("=== Test: Calling subvault.call() with struct ===");
        console.log("Proof array length:", payload.proof.length);
        for (uint256 i = 0; i < payload.proof.length; i++) {
            console.log("Proof", i);
            console.logBytes32(payload.proof[i]);
        }

        // Encode the call using abi.encodeCall to see what Solidity produces
        bytes memory encoded = abi.encodeCall(
            ICallModule.call,
            (POSITION_MANAGER, 0, mintData, payload)
        );

        console.log("\n=== Encoded calldata from abi.encodeCall ===");
        console.logBytes(encoded);

        // Now make the actual call
        console.log("\n=== Making actual call from curator ===");
        vm.prank(CURATOR);
        try ICallModule(SUBVAULT).call(POSITION_MANAGER, 0, mintData, payload) returns (bytes memory response) {
            console.log("SUCCESS!");
            console.logBytes(response);
        } catch Error(string memory reason) {
            console.log("FAILED with reason:", reason);
        } catch (bytes memory lowLevelData) {
            console.log("FAILED with low-level error:");
            console.logBytes(lowLevelData);
        }
    }
}
