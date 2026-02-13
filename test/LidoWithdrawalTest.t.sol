// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vault} from "../src/vaults/Vault.sol";
import {IVerifier} from "../src/permissions/Verifier.sol";
import {ICallModule} from "../src/interfaces/modules/ICallModule.sol";

interface ILidoWithdrawalQueue {
    function requestWithdrawalsWstETH(uint256[] calldata _amounts, address _owner)
        external
        returns (uint256[] memory requestIds);
    function claimWithdrawal(uint256 _requestId) external;
    function claimWithdrawals(uint256[] calldata _requestIds, uint256[] calldata _hints) external;
    function getWithdrawalStatus(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses);
    function getLastFinalizedRequestId() external view returns (uint256);
    function getLastRequestId() external view returns (uint256);

    struct WithdrawalRequestStatus {
        uint256 amountOfStETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }
}

contract LidoWithdrawalTest is Test {
    // Prod addresses
    address constant PROD_VAULT = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant LIDO_WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;
    address constant PROD_CURATOR = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;
    address constant ACTIVE_ADMIN = 0x2D95cb50F204B8B84606751F262b407C08528c85;

    Vault vault;
    address subvault3;
    IVerifier verifier;
    bytes32 merkleRoot;
    string json;

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork("https://ethereum.publicnode.com");

        vault = Vault(payable(PROD_VAULT));
        subvault3 = vault.subvaultAt(3);
        verifier = ICallModule(subvault3).verifier();

        console.log("Prod Vault:", PROD_VAULT);
        console.log("Subvault 3:", subvault3);
        console.log("Verifier:", address(verifier));

        // Load the JSON file (merged all.json - withdrawal proofs are at indices 62-66)
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/ethereum:tqETH:prod:sv3:all.json");
        json = vm.readFile(path);

        merkleRoot = vm.parseJsonBytes32(json, ".merkle_root");
        console.log("Merkle root from JSON:");
        console.logBytes32(merkleRoot);

        // Set merkle root on verifier using active admin
        vm.prank(ACTIVE_ADMIN);
        verifier.setMerkleRoot(merkleRoot);

        console.log("Merkle root set successfully");
    }

    function test_ApproveWstETH() public {
        console.log("\n=== Test: Approve wstETH for Lido Withdrawal Queue ===");

        // Get the first proof (approve wstETH)
        bytes memory verificationData = vm.parseJsonBytes(json, ".merkle_proofs[62].verificationData");
        bytes32[] memory proof = vm.parseJsonBytes32Array(json, ".merkle_proofs[62].proof");

        console.log("Proof length:", proof.length);

        // Build the verification payload
        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            proof: proof,
            verificationData: verificationData
        });

        // Build the actual call: approve(LIDO_WITHDRAWAL_QUEUE, 1 ether)
        bytes memory callData = abi.encodeWithSelector(
            IERC20.approve.selector,
            LIDO_WITHDRAWAL_QUEUE,
            1 ether
        );

        // Execute through CallModule as prod curator
        vm.prank(PROD_CURATOR);
        ICallModule(subvault3).call(WSTETH, 0, callData, payload);

        console.log("Approve wstETH: PASSED");
    }

    function test_RequestWithdrawalsWstETH() public {
        console.log("\n=== Test: Request Withdrawals wstETH ===");

        // First, give subvault some wstETH
        deal(WSTETH, subvault3, 5 ether);
        console.log("Subvault wstETH balance:", IERC20(WSTETH).balanceOf(subvault3));

        // First approve
        {
            bytes memory approveVerificationData = vm.parseJsonBytes(json, ".merkle_proofs[62].verificationData");
            bytes32[] memory approveProof = vm.parseJsonBytes32Array(json, ".merkle_proofs[62].proof");

            IVerifier.VerificationPayload memory approvePayload = IVerifier.VerificationPayload({
                verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
                proof: approveProof,
                verificationData: approveVerificationData
            });

            bytes memory approveCallData = abi.encodeWithSelector(
                IERC20.approve.selector,
                LIDO_WITHDRAWAL_QUEUE,
                type(uint256).max
            );

            vm.prank(PROD_CURATOR);
            ICallModule(subvault3).call(WSTETH, 0, approveCallData, approvePayload);
            console.log("Approve: PASSED");
        }

        // Now request withdrawals
        {
            bytes memory verificationData = vm.parseJsonBytes(json, ".merkle_proofs[63].verificationData");
            bytes32[] memory proof = vm.parseJsonBytes32Array(json, ".merkle_proofs[63].proof");

            IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
                verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
                proof: proof,
                verificationData: verificationData
            });

            // Build actual call with 1-element array (bitmask requires consistent array size)
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 1 ether;

            bytes memory callData = abi.encodeWithSelector(
                ILidoWithdrawalQueue.requestWithdrawalsWstETH.selector,
                amounts,
                subvault3 // owner must be subvault
            );

            vm.prank(PROD_CURATOR);
            ICallModule(subvault3).call(LIDO_WITHDRAWAL_QUEUE, 0, callData, payload);

            console.log("RequestWithdrawalsWstETH: PASSED");
        }
    }

    function test_RequestWithdrawalsWstETH_WrongOwner() public {
        console.log("\n=== Test: Request Withdrawals with WRONG owner (should fail) ===");

        // Give subvault some wstETH
        deal(WSTETH, subvault3, 5 ether);

        // First approve
        {
            bytes memory approveVerificationData = vm.parseJsonBytes(json, ".merkle_proofs[62].verificationData");
            bytes32[] memory approveProof = vm.parseJsonBytes32Array(json, ".merkle_proofs[62].proof");

            IVerifier.VerificationPayload memory approvePayload = IVerifier.VerificationPayload({
                verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
                proof: approveProof,
                verificationData: approveVerificationData
            });

            bytes memory approveCallData = abi.encodeWithSelector(
                IERC20.approve.selector,
                LIDO_WITHDRAWAL_QUEUE,
                type(uint256).max
            );

            vm.prank(PROD_CURATOR);
            ICallModule(subvault3).call(WSTETH, 0, approveCallData, approvePayload);
        }

        // Try request withdrawals with WRONG owner
        {
            bytes memory verificationData = vm.parseJsonBytes(json, ".merkle_proofs[63].verificationData");
            bytes32[] memory proof = vm.parseJsonBytes32Array(json, ".merkle_proofs[63].proof");

            IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
                verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
                proof: proof,
                verificationData: verificationData
            });

            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 1 ether;

            bytes memory callData = abi.encodeWithSelector(
                ILidoWithdrawalQueue.requestWithdrawalsWstETH.selector,
                amounts,
                address(0xdead) // WRONG owner - should fail verification
            );

            vm.prank(PROD_CURATOR);
            vm.expectRevert(); // Should revert because owner doesn't match
            ICallModule(subvault3).call(LIDO_WITHDRAWAL_QUEUE, 0, callData, payload);

            console.log("RequestWithdrawalsWstETH with wrong owner: CORRECTLY REJECTED");
        }
    }

    function test_ClaimWithdrawal_VerificationOnly() public {
        console.log("\n=== Test: Claim Withdrawal (verification via CallModule) ===");

        // Get the third proof (claimWithdrawal)
        bytes memory verificationData = vm.parseJsonBytes(json, ".merkle_proofs[64].verificationData");
        bytes32[] memory proof = vm.parseJsonBytes32Array(json, ".merkle_proofs[64].proof");

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            proof: proof,
            verificationData: verificationData
        });

        // Build actual call with a request ID
        uint256 requestId = 12345;

        bytes memory callData = abi.encodeWithSelector(
            ILidoWithdrawalQueue.claimWithdrawal.selector,
            requestId
        );

        // The actual claim will revert because request 12345 doesn't exist on Lido.
        // We verify that the revert is NOT VerificationFailed (meaning verification passed)
        vm.prank(PROD_CURATOR);
        try ICallModule(subvault3).call(LIDO_WITHDRAWAL_QUEUE, 0, callData, payload) {
            // If it succeeds, that's unexpected but fine
            console.log("ClaimWithdrawal: Unexpectedly succeeded");
        } catch (bytes memory reason) {
            // Check it's NOT VerificationFailed
            bytes4 verificationFailedSelector = IVerifier.VerificationFailed.selector;
            bytes4 actualSelector;
            if (reason.length >= 4) {
                assembly {
                    actualSelector := mload(add(reason, 32))
                }
            }
            assertTrue(actualSelector != verificationFailedSelector, "Should NOT revert with VerificationFailed");
            console.log("ClaimWithdrawal verification: PASSED (reverted from Lido, not verification)");
        }
    }

    function test_ClaimWithdrawal_AnyRequestId() public {
        console.log("\n=== Test: Claim Withdrawal accepts any request ID ===");

        // Get the third proof (claimWithdrawal)
        bytes memory verificationData = vm.parseJsonBytes(json, ".merkle_proofs[64].verificationData");
        bytes32[] memory proof = vm.parseJsonBytes32Array(json, ".merkle_proofs[64].proof");

        // Test multiple request IDs to ensure "any" works
        // All should pass verification but revert from Lido (request doesn't exist)
        uint256[] memory testIds = new uint256[](3);
        testIds[0] = 0;
        testIds[1] = 999999;
        testIds[2] = 42;

        bytes4 verificationFailedSelector = IVerifier.VerificationFailed.selector;

        for (uint256 i = 0; i < testIds.length; i++) {
            bytes memory callData = abi.encodeWithSelector(
                ILidoWithdrawalQueue.claimWithdrawal.selector,
                testIds[i]
            );

            IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
                verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
                proof: proof,
                verificationData: verificationData
            });

            // Should revert from Lido (not VerificationFailed)
            vm.prank(PROD_CURATOR);
            try ICallModule(subvault3).call(LIDO_WITHDRAWAL_QUEUE, 0, callData, payload) {
                // Unexpected success
            } catch (bytes memory reason) {
                bytes4 actualSelector;
                if (reason.length >= 4) {
                    assembly {
                        actualSelector := mload(add(reason, 32))
                    }
                }
                assertTrue(
                    actualSelector != verificationFailedSelector,
                    string.concat("RequestId ", vm.toString(testIds[i]), " should NOT revert with VerificationFailed")
                );
            }
        }

        console.log("ClaimWithdrawal verification with multiple request IDs: ALL PASSED");
    }
}
