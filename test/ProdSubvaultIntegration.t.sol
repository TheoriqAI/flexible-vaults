// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "../scripts/ethereum/Constants.sol";
import "../src/interfaces/modules/ICallModule.sol";
import "../src/permissions/Verifier.sol";
import "../scripts/common/interfaces/IAavePoolV3.sol";
import "../scripts/common/interfaces/ILidoWithdrawalQueue.sol";
import "../scripts/common/interfaces/ISUSDe.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title Production Subvault 3 Integration Tests
/// @notice Tests actual execution of Aave/Spark operations on prod subvault 3
/// @dev Requires mainnet fork. SV4 tests are in ProdSv4EMode38Integration.t.sol
contract ProdSubvaultIntegrationTest is Test {
    // Addresses
    address constant prodCurator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;
    address constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address constant activeAdmin = 0x2D95cb50F204B8B84606751F262b407C08528c85;
    address constant LIDO_WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    address subvault3;

    IVerifier verifier3;
    bytes32 merkleRootSv3;

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork("https://rpc.mevblocker.io");

        // Get subvault address
        Vault vault = Vault(payable(VAULT_PROD));
        subvault3 = vault.subvaultAt(3);

        console.log("Subvault 3:", subvault3);

        // Get verifier
        verifier3 = ICallModule(subvault3).verifier();
        console.log("Verifier 3:", address(verifier3));

        // Parse merkle root from JSON
        string memory root = vm.projectRoot();
        string memory pathSv3 = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory jsonSv3 = vm.readFile(pathSv3);
        merkleRootSv3 = bytes32(vm.parseJsonBytes32(jsonSv3, ".merkle_root"));

        console.log("Merkle root SV3:", vm.toString(merkleRootSv3));
        console.log("Active admin:", activeAdmin);

        // Set merkle root on verifier
        vm.prank(activeAdmin);
        verifier3.setMerkleRoot(merkleRootSv3);

        console.log("Merkle root set on verifier");

        // Verify it was set correctly
        bytes32 actualRoot3 = verifier3.merkleRoot();
        console.log("Verifier 3 merkle root after set:", vm.toString(actualRoot3));
        require(actualRoot3 == merkleRootSv3, "SV3 merkle root mismatch");
    }

    /// @notice Helper to add delay between operations to prevent RPC rate limiting
    function _waitForRPC() internal {
        // Roll forward a block and warp time to help with RPC caching
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    /// @notice Test Aave operations on prod subvault 3 (eMode 1)
    function test_ProdSv3_AaveOperations() public {
        console.log("\n=== Testing Prod Subvault 3 - Aave Operations ===");

        // Give subvault some WETH to work with
        vm.deal(subvault3, 10 ether);
        vm.prank(subvault3);
        (bool success,) = Constants.WETH.call{value: 5 ether}("");
        require(success, "WETH wrap failed");

        uint256 wethBalance = IERC20(Constants.WETH).balanceOf(subvault3);
        console.log("Subvault WETH balance:", wethBalance);

        // Load proof data from JSON
        // For this test, we'll use index 0 for setEMode, then test supply/borrow/repay/withdraw
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory json = vm.readFile(path);

        // Parse the JSON to get proofs
        // We'll manually construct the verification payloads for this test
        // In production, these would come from the JSON file

        // IMPORTANT: Do USD-based operations BEFORE setting eMode 1 (ETH correlated)
        // because eMode 1 restricts borrowing to ETH-correlated assets only

        // Test 1: Approve WETH for Aave
        console.log("\n--- Test 1: Approve WETH ---");
        _testApprove(subvault3, Constants.WETH, Constants.AAVE_CORE, json);
        _waitForRPC();

        // Test 2: Supply 2 WETH (need enough collateral for USDC borrow)
        console.log("\n--- Test 2: Supply WETH ---");
        _testSupply(subvault3, Constants.AAVE_CORE, Constants.WETH, 2 ether, json);
        _waitForRPC();

        // Test 3: Borrow 100 USDC (2 = variable rate) - BEFORE setting eMode
        console.log("\n--- Test 3: Borrow USDC (before eMode) ---");
        _testBorrow(subvault3, Constants.AAVE_CORE, Constants.USDC, 100e6, 2, json);
        _waitForRPC();

        // Test 4: Approve USDC for repayment
        console.log("\n--- Test 4: Approve USDC ---");
        _testApprove(subvault3, Constants.USDC, Constants.AAVE_CORE, json);
        _waitForRPC();

        // Test 5: Repay all USDC (use max uint to repay all including interest)
        console.log("\n--- Test 5: Repay USDC ---");
        // Deal a tiny bit extra USDC to cover any interest accrued
        deal(Constants.USDC, subvault3, 101e6);
        _testRepay(subvault3, Constants.AAVE_CORE, Constants.USDC, type(uint256).max, 2, json);
        _waitForRPC();

        // Test 6: Now set eMode to 1 (ETH correlated) - after USD debt is cleared
        console.log("\n--- Test 6: Set eMode ---");
        _testSetEMode(subvault3, Constants.AAVE_CORE, 1, json, 0);
        _waitForRPC();

        // Test 7: Withdraw 0.5 WETH
        console.log("\n--- Test 7: Withdraw WETH ---");
        _testWithdraw(subvault3, Constants.AAVE_CORE, Constants.WETH, 0.5 ether, json);

        console.log("\n=== All Prod SV3 Tests Passed ===");
    }

    /// @notice Test Aave and Spark operations on prod subvault 3 when eMode 1 is already set
    /// @dev This test works with the real production state where eMode 1 is active
    ///      Only borrows/repays ETH-correlated assets (WETH, wstETH) allowed in eMode 1
    function test_ProdSv3_AaveAndSparkOperations_eMode1() public {
        console.log("\n=== Testing Prod Subvault 3 - Aave & Spark Operations (eMode 1 already set) ===");

        // Give subvault some WETH and wstETH to work with
        vm.deal(subvault3, 10 ether);
        vm.prank(subvault3);
        (bool success,) = Constants.WETH.call{value: 5 ether}("");
        require(success, "WETH wrap failed");
        deal(Constants.WSTETH, subvault3, 2 ether);

        uint256 wethBalance = IERC20(Constants.WETH).balanceOf(subvault3);
        uint256 wstethBalance = IERC20(Constants.WSTETH).balanceOf(subvault3);
        console.log("Subvault WETH balance:", wethBalance);
        console.log("Subvault wstETH balance:", wstethBalance);

        // Check current eMode on Aave (should be 1 on real vault)
        uint256 aaveEMode = IAavePoolV3(Constants.AAVE_CORE).getUserEMode(subvault3);
        console.log("Aave eMode:", aaveEMode);

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory json = vm.readFile(path);

        // =================== AAVE OPERATIONS ===================
        console.log("\n========== AAVE OPERATIONS ==========");

        // Test 1: Approve WETH for Aave
        console.log("\n--- Aave Test 1: Approve WETH ---");
        _testApprove(subvault3, Constants.WETH, Constants.AAVE_CORE, json);
        _waitForRPC();

        // Test 2: Supply 2 WETH as collateral
        console.log("\n--- Aave Test 2: Supply WETH ---");
        _testSupply(subvault3, Constants.AAVE_CORE, Constants.WETH, 2 ether, json);
        _waitForRPC();

        // Test 3: Borrow 0.1 WETH (ETH-correlated, allowed in eMode 1)
        console.log("\n--- Aave Test 3: Borrow WETH (eMode 1) ---");
        _testBorrow(subvault3, Constants.AAVE_CORE, Constants.WETH, 0.1 ether, 2, json);
        _waitForRPC();

        // Test 4: Repay WETH
        console.log("\n--- Aave Test 4: Repay WETH ---");
        _testRepay(subvault3, Constants.AAVE_CORE, Constants.WETH, 0.1 ether, 2, json);
        _waitForRPC();

        // Test 5: Withdraw 0.5 WETH
        console.log("\n--- Aave Test 5: Withdraw WETH ---");
        _testWithdraw(subvault3, Constants.AAVE_CORE, Constants.WETH, 0.5 ether, json);
        _waitForRPC();

        // Test 6: Approve wstETH for Aave
        console.log("\n--- Aave Test 6: Approve wstETH ---");
        _testApprove(subvault3, Constants.WSTETH, Constants.AAVE_CORE, json);
        _waitForRPC();

        // Test 7: Supply 1 wstETH on Aave
        console.log("\n--- Aave Test 7: Supply wstETH ---");
        _testSupply(subvault3, Constants.AAVE_CORE, Constants.WSTETH, 1 ether, json);
        _waitForRPC();

        // Test 8: Withdraw 0.5 wstETH from Aave
        console.log("\n--- Aave Test 8: Withdraw wstETH ---");
        _testWithdraw(subvault3, Constants.AAVE_CORE, Constants.WSTETH, 0.5 ether, json);
        _waitForRPC();

        // =================== SPARK OPERATIONS ===================
        console.log("\n========== SPARK OPERATIONS ==========");

        // Approve wstETH for Spark
        console.log("\n--- Spark Test 1: Approve wstETH ---");
        _testApproveSpark(subvault3, Constants.WSTETH, Constants.SPARK, json);
        _waitForRPC();

        // Test 7: Supply 1 wstETH as collateral on Spark
        console.log("\n--- Spark Test 2: Supply wstETH ---");
        _testSupplySpark(subvault3, Constants.SPARK, Constants.WSTETH, 1 ether, json);
        _waitForRPC();

        // Test 8: Approve WETH for Spark borrow
        console.log("\n--- Spark Test 3: Approve WETH ---");
        _testApproveSparkBorrow(subvault3, Constants.WETH, Constants.SPARK, json);
        _waitForRPC();

        // Test 9: Borrow 0.1 WETH on Spark (ETH-correlated, allowed in eMode 1)
        console.log("\n--- Spark Test 4: Borrow WETH (eMode 1) ---");
        _testBorrowSpark(subvault3, Constants.SPARK, Constants.WETH, 0.1 ether, 2, json);
        _waitForRPC();

        // Test 10: Repay WETH on Spark
        console.log("\n--- Spark Test 5: Repay WETH ---");
        _testRepaySpark(subvault3, Constants.SPARK, Constants.WETH, 0.1 ether, 2, json);
        _waitForRPC();

        // Test 11: Withdraw 0.5 wstETH from Spark
        console.log("\n--- Spark Test 6: Withdraw wstETH ---");
        _testWithdrawSpark(subvault3, Constants.SPARK, Constants.WSTETH, 0.5 ether, json);

        console.log("\n=== All Prod SV3 Aave & Spark eMode1 Tests Passed ===");
    }

    // NOTE: SV4 tests moved to ProdSv4EMode38Integration.t.sol

    /// @notice Test that non-curator cannot execute operations
    function test_RevertWhen_NonCuratorCallsOperation() public {
        console.log("\n=== Testing Non-Curator Access Control ===");

        // Give subvault assets
        vm.deal(subvault3, 10 ether);
        vm.prank(subvault3);
        (bool success,) = Constants.WETH.call{value: 5 ether}("");
        require(success, "WETH wrap failed");

        // Load JSON
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory json = vm.readFile(path);

        // Get proof for approve operation
        uint256 proofIndex = _findProofForApprove(json, Constants.WETH, Constants.AAVE_CORE);
        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        bytes memory callData = abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max));

        // Try to call as random address (not curator)
        address attacker = address(0xBAD);
        vm.prank(attacker);
        vm.expectRevert(); // Should revert because caller is not curator
        ICallModule(subvault3).call(Constants.WETH, 0, callData, payload);

        console.log("Non-curator call REVERTED as expected - SUCCESS");
    }

    /// @notice Test that wrong recipient/onBehalfOf causes failure
    function test_RevertWhen_WrongRecipient() public {
        console.log("\n=== Testing Wrong Recipient Enforcement ===");

        // Give subvault assets
        vm.deal(subvault3, 10 ether);
        vm.prank(subvault3);
        (bool success,) = Constants.WETH.call{value: 5 ether}("");
        require(success, "WETH wrap failed");

        // First approve WETH (this should succeed)
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory json = vm.readFile(path);

        _testApprove(subvault3, Constants.WETH, Constants.AAVE_CORE, json);

        // Now try to supply with WRONG recipient (not subvault3)
        uint256 proofIndex = _findProofForSupply(json, Constants.WETH);
        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        // Use wrong recipient address (should be subvault3, but we use attacker)
        address wrongRecipient = address(0xBAD);
        bytes memory callData = abi.encodeCall(
            IAavePoolV3.supply,
            (Constants.WETH, 1 ether, wrongRecipient, 0) // ← WRONG recipient!
        );

        vm.prank(prodCurator);
        vm.expectRevert(); // Should revert because hash won't match
        ICallModule(subvault3).call(Constants.AAVE_CORE, 0, callData, payload);

        console.log("Wrong recipient call REVERTED as expected - SUCCESS");
    }

    /// @notice Test that wrong 'to' address in withdraw causes failure
    function test_RevertWhen_WrongWithdrawRecipient() public {
        console.log("\n=== Testing Wrong Withdraw Recipient Enforcement ===");

        // Give subvault assets and supply first
        vm.deal(subvault3, 10 ether);
        vm.prank(subvault3);
        (bool success,) = Constants.WETH.call{value: 5 ether}("");
        require(success, "WETH wrap failed");

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory json = vm.readFile(path);

        // Approve and supply WETH first
        _testApprove(subvault3, Constants.WETH, Constants.AAVE_CORE, json);
        _testSupply(subvault3, Constants.AAVE_CORE, Constants.WETH, 1 ether, json);

        // Now try to withdraw to WRONG address
        uint256 proofIndex = _findProofForWithdraw(json, Constants.WETH);
        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        // Use wrong 'to' address
        address wrongRecipient = address(0xBAD);
        bytes memory callData = abi.encodeCall(
            IAavePoolV3.withdraw,
            (Constants.WETH, 0.5 ether, wrongRecipient) // ← WRONG 'to' address!
        );

        vm.prank(prodCurator);
        vm.expectRevert(); // Should revert because hash won't match
        ICallModule(subvault3).call(Constants.AAVE_CORE, 0, callData, payload);

        console.log("Wrong withdraw recipient REVERTED as expected - SUCCESS");
    }

    /// @notice Test that wrong onBehalfOf in borrow causes failure
    function test_RevertWhen_WrongBorrowOnBehalfOf() public {
        console.log("\n=== Testing Wrong Borrow OnBehalfOf Enforcement ===");

        // Give subvault assets and supply collateral first
        vm.deal(subvault3, 10 ether);
        vm.prank(subvault3);
        (bool success,) = Constants.WETH.call{value: 5 ether}("");
        require(success, "WETH wrap failed");

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory json = vm.readFile(path);

        // Set eMode, approve and supply WETH first
        _testSetEMode(subvault3, Constants.AAVE_CORE, 1, json, 0);
        _testApprove(subvault3, Constants.WETH, Constants.AAVE_CORE, json);
        _testSupply(subvault3, Constants.AAVE_CORE, Constants.WETH, 2 ether, json);

        // Now try to borrow with WRONG onBehalfOf
        uint256 proofIndex = _findProofForBorrow(json, Constants.USDC);
        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        // Use wrong onBehalfOf address
        address wrongOnBehalfOf = address(0xBAD);
        bytes memory callData = abi.encodeCall(
            IAavePoolV3.borrow,
            (Constants.USDC, 100e6, 2, 0, wrongOnBehalfOf) // ← WRONG onBehalfOf!
        );

        vm.prank(prodCurator);
        vm.expectRevert(); // Should revert because hash won't match
        ICallModule(subvault3).call(Constants.AAVE_CORE, 0, callData, payload);

        console.log("Wrong borrow onBehalfOf REVERTED as expected - SUCCESS");
    }

    /// @notice Test that wrong onBehalfOf in repay causes failure
    function test_RevertWhen_WrongRepayOnBehalfOf() public {
        console.log("\n=== Testing Wrong Repay OnBehalfOf Enforcement ===");

        // Give subvault assets, supply and borrow first
        vm.deal(subvault3, 10 ether);
        vm.prank(subvault3);
        (bool success,) = Constants.WETH.call{value: 5 ether}("");
        require(success, "WETH wrap failed");

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory json = vm.readFile(path);

        // Set eMode, approve, supply and borrow
        _testSetEMode(subvault3, Constants.AAVE_CORE, 1, json, 0);
        _testApprove(subvault3, Constants.WETH, Constants.AAVE_CORE, json);
        _testSupply(subvault3, Constants.AAVE_CORE, Constants.WETH, 2 ether, json);
        _testBorrow(subvault3, Constants.AAVE_CORE, Constants.USDC, 100e6, 2, json);

        // Approve USDC for repayment
        _testApprove(subvault3, Constants.USDC, Constants.AAVE_CORE, json);

        // Now try to repay with WRONG onBehalfOf
        uint256 proofIndex = _findProofForRepay(json, Constants.USDC);
        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        // Use wrong onBehalfOf address
        address wrongOnBehalfOf = address(0xBAD);
        bytes memory callData = abi.encodeCall(
            IAavePoolV3.repay,
            (Constants.USDC, 50e6, 2, wrongOnBehalfOf) // ← WRONG onBehalfOf!
        );

        vm.prank(prodCurator);
        vm.expectRevert(); // Should revert because hash won't match
        ICallModule(subvault3).call(Constants.AAVE_CORE, 0, callData, payload);

        console.log("Wrong repay onBehalfOf REVERTED as expected - SUCCESS");
    }

    // Helper functions to execute operations

    function _testSetEMode(
        address subvault,
        address pool,
        uint8 categoryId,
        string memory json,
        uint256 proofIndex
    ) internal {
        // Get proof from JSON
        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        bytes memory callData = abi.encodeCall(IAavePoolV3.setUserEMode, (categoryId));

        vm.prank(prodCurator);
        ICallModule(subvault).call(pool, 0, callData, payload);

        console.log("Set eMode to", categoryId, "- SUCCESS");
    }

    function _testApprove(address subvault, address token, address spender, string memory json) internal {
        // Find approve proof in JSON
        uint256 proofIndex = _findProofForApprove(json, token, spender);

        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        bytes memory callData = abi.encodeCall(IERC20.approve, (spender, type(uint256).max));

        vm.prank(prodCurator);
        ICallModule(subvault).call(token, 0, callData, payload);

        console.log("Approved token for spender - SUCCESS");
    }

    function _testSupply(
        address subvault,
        address pool,
        address asset,
        uint256 amount,
        string memory json
    ) internal {
        uint256 proofIndex = _findProofForSupply(json, asset);

        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        bytes memory callData = abi.encodeCall(IAavePoolV3.supply, (asset, amount, subvault, 0));

        vm.prank(prodCurator);
        ICallModule(subvault).call(pool, 0, callData, payload);

        console.log("Supplied asset - SUCCESS");
    }

    function _testBorrow(
        address subvault,
        address pool,
        address asset,
        uint256 amount,
        uint256 rateMode,
        string memory json
    ) internal {
        uint256 proofIndex = _findProofForBorrow(json, asset);

        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        bytes memory callData = abi.encodeCall(IAavePoolV3.borrow, (asset, amount, rateMode, 0, subvault));

        vm.prank(prodCurator);
        ICallModule(subvault).call(pool, 0, callData, payload);

        console.log("Borrowed asset - SUCCESS");
    }

    function _testRepay(
        address subvault,
        address pool,
        address asset,
        uint256 amount,
        uint256 rateMode,
        string memory json
    ) internal {
        uint256 proofIndex = _findProofForRepay(json, asset);

        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        bytes memory callData = abi.encodeCall(IAavePoolV3.repay, (asset, amount, rateMode, subvault));

        vm.prank(prodCurator);
        ICallModule(subvault).call(pool, 0, callData, payload);

        console.log("Repaid asset - SUCCESS");
    }

    function _testWithdraw(
        address subvault,
        address pool,
        address asset,
        uint256 amount,
        string memory json
    ) internal {
        uint256 proofIndex = _findProofForWithdraw(json, asset);

        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        bytes memory callData = abi.encodeCall(IAavePoolV3.withdraw, (asset, amount, subvault));

        vm.prank(prodCurator);
        ICallModule(subvault).call(pool, 0, callData, payload);

        console.log("Withdrew asset - SUCCESS");
    }

    // Helper functions to parse JSON

    function _getVerificationData(string memory json, uint256 index) internal view returns (bytes memory) {
        string memory basePath = string.concat(".merkle_proofs[", vm.toString(index), "].verificationData");
        return vm.parseJsonBytes(json, basePath);
    }

    function _getProof(string memory json, uint256 index) internal view returns (bytes32[] memory) {
        string memory basePath = string.concat(".merkle_proofs[", vm.toString(index), "].proof");
        bytes memory proofData = vm.parseJson(json, basePath);
        return abi.decode(proofData, (bytes32[]));
    }

    function _findProofForApprove(string memory json, address token, address spender)
        internal
        view
        returns (uint256)
    {
        // Indices from JSON (ethereum:tqETH:prod:sv3:all.json):
        // 0: setUserEMode
        // 1: WETH approve, 2: WETH supply, 3: WETH withdraw
        // 4: wstETH approve, 5: wstETH supply, 6: wstETH withdraw
        // 7: WETH approve (borrow), 8: WETH borrow, 9: WETH repay
        // 10: wstETH approve (borrow), 11: wstETH borrow, 12: wstETH repay
        // 13: USDC approve, 14: USDC borrow, 15: USDC repay
        // 16: USDT approve, 17: USDT borrow, 18: USDT repay
        // 19: USDe approve, 20: USDe borrow, 21: USDe repay

        // Use first approve for supply operations
        if (token == Constants.WETH) return 1;
        if (token == Constants.WSTETH) return 4;
        if (token == Constants.USDC) return 13;
        if (token == Constants.USDT) return 16;
        if (token == Constants.USDE) return 19;

        revert("Proof not found for approve");
    }

    function _findProofForSupply(string memory json, address asset) internal view returns (uint256) {
        // 2: WETH supply, 5: wstETH supply
        if (asset == Constants.WETH) return 2;
        if (asset == Constants.WSTETH) return 5;

        revert("Proof not found for supply");
    }

    function _findProofForWithdraw(string memory json, address asset) internal view returns (uint256) {
        // 3: WETH withdraw, 6: wstETH withdraw
        if (asset == Constants.WETH) return 3;
        if (asset == Constants.WSTETH) return 6;

        revert("Proof not found for withdraw");
    }

    function _findProofForBorrow(string memory json, address asset) internal view returns (uint256) {
        // 8: WETH borrow, 11: wstETH borrow
        // 14: USDC borrow, 17: USDT borrow, 20: USDe borrow
        if (asset == Constants.WETH) return 8;
        if (asset == Constants.WSTETH) return 11;
        if (asset == Constants.USDC) return 14;
        if (asset == Constants.USDT) return 17;
        if (asset == Constants.USDE) return 20;

        revert("Proof not found for borrow");
    }

    function _findProofForRepay(string memory json, address asset) internal view returns (uint256) {
        // 9: WETH repay, 12: wstETH repay
        // 15: USDC repay, 18: USDT repay, 21: USDe repay
        if (asset == Constants.WETH) return 9;
        if (asset == Constants.WSTETH) return 12;
        if (asset == Constants.USDC) return 15;
        if (asset == Constants.USDT) return 18;
        if (asset == Constants.USDE) return 21;

        revert("Proof not found for repay");
    }

    // =================== SPARK HELPER FUNCTIONS ===================
    // Spark proof indices (from ethereum:tqETH:prod:sv3:all.json):
    // Aave now has 25 ops (added EURC borrow), so Spark starts at 25
    // 25: setUserEMode (Spark)
    // 26: WETH approve (supply), 27: WETH supply, 28: WETH withdraw
    // 29: wstETH approve (supply), 30: wstETH supply, 31: wstETH withdraw
    // 32: WETH approve (borrow), 33: WETH borrow, 34: WETH repay
    // 35: wstETH approve (borrow), 36: wstETH borrow, 37: wstETH repay
    // 38: USDC approve, 39: USDC borrow, 40: USDC repay
    // 41: USDT approve, 42: USDT borrow, 43: USDT repay
    // 44: USDe approve, 45: USDe borrow, 46: USDe repay

    function _testApproveSpark(address subvault, address token, address spender, string memory json) internal {
        uint256 proofIndex = _findProofForApproveSpark(token);

        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        bytes memory callData = abi.encodeCall(IERC20.approve, (spender, type(uint256).max));

        vm.prank(prodCurator);
        ICallModule(subvault).call(token, 0, callData, payload);

        console.log("Approved token for Spark - SUCCESS");
    }

    function _testApproveSparkBorrow(address subvault, address token, address spender, string memory json) internal {
        uint256 proofIndex = _findProofForApproveSparkBorrow(token);

        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        bytes memory callData = abi.encodeCall(IERC20.approve, (spender, type(uint256).max));

        vm.prank(prodCurator);
        ICallModule(subvault).call(token, 0, callData, payload);

        console.log("Approved token for Spark borrow - SUCCESS");
    }

    function _testSupplySpark(
        address subvault,
        address pool,
        address asset,
        uint256 amount,
        string memory json
    ) internal {
        uint256 proofIndex = _findProofForSupplySpark(asset);

        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        bytes memory callData = abi.encodeCall(IAavePoolV3.supply, (asset, amount, subvault, 0));

        vm.prank(prodCurator);
        ICallModule(subvault).call(pool, 0, callData, payload);

        console.log("Supplied asset to Spark - SUCCESS");
    }

    function _testBorrowSpark(
        address subvault,
        address pool,
        address asset,
        uint256 amount,
        uint256 rateMode,
        string memory json
    ) internal {
        uint256 proofIndex = _findProofForBorrowSpark(asset);

        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        bytes memory callData = abi.encodeCall(IAavePoolV3.borrow, (asset, amount, rateMode, 0, subvault));

        vm.prank(prodCurator);
        ICallModule(subvault).call(pool, 0, callData, payload);

        console.log("Borrowed asset from Spark - SUCCESS");
    }

    function _testRepaySpark(
        address subvault,
        address pool,
        address asset,
        uint256 amount,
        uint256 rateMode,
        string memory json
    ) internal {
        uint256 proofIndex = _findProofForRepaySpark(asset);

        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        bytes memory callData = abi.encodeCall(IAavePoolV3.repay, (asset, amount, rateMode, subvault));

        vm.prank(prodCurator);
        ICallModule(subvault).call(pool, 0, callData, payload);

        console.log("Repaid asset to Spark - SUCCESS");
    }

    function _testWithdrawSpark(
        address subvault,
        address pool,
        address asset,
        uint256 amount,
        string memory json
    ) internal {
        uint256 proofIndex = _findProofForWithdrawSpark(asset);

        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        bytes memory callData = abi.encodeCall(IAavePoolV3.withdraw, (asset, amount, subvault));

        vm.prank(prodCurator);
        ICallModule(subvault).call(pool, 0, callData, payload);

        console.log("Withdrew asset from Spark - SUCCESS");
    }

    // Spark proof index finders
    function _findProofForApproveSpark(address token) internal pure returns (uint256) {
        if (token == Constants.WETH) return 26;
        if (token == Constants.WSTETH) return 29;
        if (token == Constants.USDC) return 38;
        if (token == Constants.USDT) return 41;
        if (token == Constants.USDE) return 44;
        revert("Spark: Proof not found for approve");
    }

    function _findProofForApproveSparkBorrow(address token) internal pure returns (uint256) {
        if (token == Constants.WETH) return 32;
        if (token == Constants.WSTETH) return 35;
        revert("Spark: Proof not found for approve borrow");
    }

    function _findProofForSupplySpark(address asset) internal pure returns (uint256) {
        if (asset == Constants.WETH) return 27;
        if (asset == Constants.WSTETH) return 30;
        revert("Spark: Proof not found for supply");
    }

    function _findProofForWithdrawSpark(address asset) internal pure returns (uint256) {
        if (asset == Constants.WETH) return 28;
        if (asset == Constants.WSTETH) return 31;
        revert("Spark: Proof not found for withdraw");
    }

    function _findProofForBorrowSpark(address asset) internal pure returns (uint256) {
        if (asset == Constants.WETH) return 33;
        if (asset == Constants.WSTETH) return 36;
        if (asset == Constants.USDC) return 39;
        if (asset == Constants.USDT) return 42;
        if (asset == Constants.USDE) return 45;
        revert("Spark: Proof not found for borrow");
    }

    function _findProofForRepaySpark(address asset) internal pure returns (uint256) {
        if (asset == Constants.WETH) return 34;
        if (asset == Constants.WSTETH) return 37;
        if (asset == Constants.USDC) return 40;
        if (asset == Constants.USDT) return 43;
        if (asset == Constants.USDE) return 46;
        revert("Spark: Proof not found for repay");
    }
}
