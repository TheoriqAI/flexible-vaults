// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "../scripts/ethereum/Constants.sol";
import "../src/interfaces/modules/ICallModule.sol";
import "../src/permissions/Verifier.sol";
import "../src/permissions/BitmaskVerifier.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/// @title Simple Approve WETH Test
/// @notice Minimal test to verify merkle proof works for approve WETH on subvault 3
contract SimpleApproveTest is Test {
    // Prod addresses
    address constant prodCurator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;
    address constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address constant activeAdmin = 0x2D95cb50F204B8B84606751F262b407C08528c85;

    address subvault3;
    IVerifier verifier3;

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork("https://rpc.mevblocker.io");

        // Get subvault3 address
        Vault vault = Vault(payable(VAULT_PROD));
        subvault3 = vault.subvaultAt(3);
        console.log("Subvault 3 address:", subvault3);

        // Get verifier
        verifier3 = ICallModule(subvault3).verifier();
        console.log("Verifier 3 address:", address(verifier3));

        // Log current merkle root
        bytes32 currentRoot = verifier3.merkleRoot();
        console.log("Current merkle root:", vm.toString(currentRoot));

        // Set merkle root from NEW merged JSON (ethereum:tqETH:prod:sv3:all-new.json)
        // This uses the FIXED merge script that matches Solidity leaf hash computation
        bytes32 merkleRoot = 0x2bbe0a10fb022bb12e196d177ac653a11f4e31d7e994bc9a5d8ba03f39b1fc8c;
        console.log("Setting merkle root:", vm.toString(merkleRoot));

        vm.prank(activeAdmin);
        verifier3.setMerkleRoot(merkleRoot);

        // Verify it was set
        bytes32 actualRoot = verifier3.merkleRoot();
        console.log("Merkle root after set:", vm.toString(actualRoot));
        require(actualRoot == merkleRoot, "Merkle root not set correctly");
    }

    /// @notice Debug test to understand what's happening
    function test_DebugVerification() public {
        console.log("\n=== Debug Verification ===");

        // From aaveOps-emode1.json index 1: IERC20(WETH).approve(AaveInstance(aave), anyInt)
        bytes memory verificationData = hex"0000000000000000000000000000000263fb29c3d6b0c5837883519ef05ea20a5f4492a50723b904a5cf8fcea9507d75086352c54d98052060f46eafeda61a2e000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a4ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000ffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        // Proof from NEW merged JSON (all-new.json) - 6 elements
        bytes32[] memory proof = new bytes32[](6);
        proof[0] = 0x1672df4f1f05e2ecfedf7060b6aca2e47ccae6b1adab525cae2ac3be865ca5e0;
        proof[1] = 0x922d2e28be9cc6ed2516c70e8e5ec16896db94d26a5bd418a988480e15bf7993;
        proof[2] = 0x09dd2b7abe080e9746fd9de8c4c3dc45bedb327fe350d3fb7058f6493fd67f77;
        proof[3] = 0x92785fb66797252cf2b9b3424441c38775ba452e057e775dfec956949732492a;
        proof[4] = 0x1872a695d83283ea017b1764edd67e38702c08ad7c4f0c418c81d4f8235e5311;
        proof[5] = 0x70fa5bdae5d8a55c3c645bd63025bd0eae2571df9b1a2cf2d532fb02c9b5b4da;

        // Build calldata
        bytes memory callData = abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max));
        console.log("callData length:", callData.length);
        console.logBytes(callData);

        // Step 1: Compute merkle leaf (same as Verifier does)
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(
            IVerifier.VerificationType.CUSTOM_VERIFIER,
            keccak256(verificationData)
        ))));
        console.log("Computed leaf:", vm.toString(leaf));

        // Step 2: Verify merkle proof
        bytes32 root = verifier3.merkleRoot();
        bool merkleValid = MerkleProof.verify(proof, root, leaf);
        console.log("Merkle proof valid:", merkleValid);

        // Step 3: Check BitmaskVerifier manually
        // verificationData[0x20:] is what gets passed to BitmaskVerifier
        // First 32 bytes is verifier address, rest goes to verifyCall

        // Extract expected hash and bitmask from verificationData
        bytes memory bitmaskVerifierData = new bytes(verificationData.length - 32);
        for (uint i = 32; i < verificationData.length; i++) {
            bitmaskVerifierData[i - 32] = verificationData[i];
        }
        console.log("BitmaskVerifier data length:", bitmaskVerifierData.length);

        // The first 32 bytes of bitmaskVerifierData is expectedHash
        bytes32 expectedHash;
        assembly {
            expectedHash := mload(add(bitmaskVerifierData, 32))
        }
        console.log("Expected hash from verificationData:", vm.toString(expectedHash));

        // Call BitmaskVerifier directly
        BitmaskVerifier bitmaskVerifier = BitmaskVerifier(0x0000000263Fb29C3D6B0C5837883519eF05ea20A);

        // We need to extract the bitmask
        // Format: expectedHash (32) | offset (32) | length (32) | bitmask data
        uint256 bitmaskOffset;
        uint256 bitmaskLength;
        assembly {
            bitmaskOffset := mload(add(bitmaskVerifierData, 64))  // offset at position 32
            bitmaskLength := mload(add(bitmaskVerifierData, 96))  // length at offset position
        }
        console.log("Bitmask offset:", bitmaskOffset);
        console.log("Bitmask length:", bitmaskLength);
        console.log("Expected bitmask length (data.length + 96):", callData.length + 96);

        // Now let's try the actual call
        console.log("\n--- Now testing actual call ---");

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        // Check getVerificationResult
        bool result = verifier3.getVerificationResult(
            prodCurator,
            Constants.WETH,
            0,
            callData,
            payload
        );
        console.log("getVerificationResult:", result);
    }

    /// @notice Test approve WETH for Aave on subvault 3
    function test_ApproveWETH() public {
        console.log("\n=== Testing Approve WETH ===");

        // From aaveOps-emode1.json index 1: IERC20(WETH).approve(AaveInstance(aave), anyInt)
        bytes memory verificationData = hex"0000000000000000000000000000000263fb29c3d6b0c5837883519ef05ea20a5f4492a50723b904a5cf8fcea9507d75086352c54d98052060f46eafeda61a2e000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a4ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000ffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

        // Proof from NEW merged JSON (all-new.json) - 6 elements
        bytes32[] memory proof = new bytes32[](6);
        proof[0] = 0x1672df4f1f05e2ecfedf7060b6aca2e47ccae6b1adab525cae2ac3be865ca5e0;
        proof[1] = 0x922d2e28be9cc6ed2516c70e8e5ec16896db94d26a5bd418a988480e15bf7993;
        proof[2] = 0x09dd2b7abe080e9746fd9de8c4c3dc45bedb327fe350d3fb7058f6493fd67f77;
        proof[3] = 0x92785fb66797252cf2b9b3424441c38775ba452e057e775dfec956949732492a;
        proof[4] = 0x1872a695d83283ea017b1764edd67e38702c08ad7c4f0c418c81d4f8235e5311;
        proof[5] = 0x70fa5bdae5d8a55c3c645bd63025bd0eae2571df9b1a2cf2d532fb02c9b5b4da;

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        // Build the calldata for approve(spender, amount)
        // spender = AAVE_CORE, amount = max
        bytes memory callData = abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max));

        console.log("Calling approve on WETH...");
        console.log("Target (WETH):", Constants.WETH);
        console.log("Spender (AAVE_CORE):", Constants.AAVE_CORE);
        console.log("Caller (prodCurator):", prodCurator);

        vm.prank(prodCurator);
        ICallModule(subvault3).call(Constants.WETH, 0, callData, payload);

        // Check the allowance was set
        uint256 allowance = IERC20(Constants.WETH).allowance(subvault3, Constants.AAVE_CORE);
        console.log("Allowance after approve:", allowance);
        assertEq(allowance, type(uint256).max, "Allowance not set correctly");

        console.log("=== SUCCESS ===");
    }
}
