// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "../scripts/ethereum/Constants.sol";
import "../src/interfaces/modules/ICallModule.sol";
import "../src/permissions/Verifier.sol";
import "../scripts/common/interfaces/IAavePoolV3.sol";
import "../scripts/common/interfaces/IMorpho.sol";
import "../scripts/common/interfaces/ILidoWithdrawalQueue.sol";
import "../scripts/common/interfaces/ISUSDe.sol";
import "../scripts/common/interfaces/INttManagerWithExecutor.sol";
import "../scripts/common/interfaces/ICCIPRouterClient.sol";
import "../scripts/common/libraries/CCIPClient.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title Production Subvault 3 Integration Tests
/// @notice Tests actual execution of Aave/Spark operations on prod subvault 3
/// @dev Requires mainnet fork. SV4 tests are in ProdSv4Emode44Integration.t.sol
contract ProdSubvaultIntegrationTest is Test {
    // Addresses
    address constant prodCurator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;
    address constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address constant activeAdmin = 0x2D95cb50F204B8B84606751F262b407C08528c85;
    address constant LIDO_WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    // Morpho savETH/WETH market
    bytes32 constant MARKET_SAVETH_WETH = 0xd98cd88ae5b336086b39fb1d62ba6171282e946105b010143f0e89f8fe7cff36;
    address constant SAVETH = 0xDA06eE2dACF9245Aa80072a4407deBDea0D7e341;

    address subvault3;

    IVerifier verifier3;
    bytes32 merkleRootSv3;

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork("http://108.53.61.201:8550");

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
    /// @dev eMode 1 is active on the fork, so only ETH-correlated borrows (WETH, wstETH) work
    function test_ProdSv3_AaveOperations() public {
        console.log("\n=== Testing Prod Subvault 3 - Aave Operations (eMode 1) ===");

        // Give subvault some WETH to work with
        vm.deal(subvault3, 10 ether);
        vm.prank(subvault3);
        (bool success,) = Constants.WETH.call{value: 5 ether}("");
        require(success, "WETH wrap failed");

        uint256 wethBalance = IERC20(Constants.WETH).balanceOf(subvault3);
        console.log("Subvault WETH balance:", wethBalance);

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory json = vm.readFile(path);

        // eMode 1 is already active on fork — only ETH-correlated borrows allowed

        // Test 1: Set eMode to 1 (confirm it works)
        console.log("\n--- Test 1: Set eMode 1 ---");
        _testSetEMode(subvault3, Constants.AAVE_CORE, 1, json, 0);
        _waitForRPC();

        // Test 2: Approve WETH for Aave
        console.log("\n--- Test 2: Approve WETH ---");
        _testApprove(subvault3, Constants.WETH, Constants.AAVE_CORE, json);
        _waitForRPC();

        // Test 3: Supply 2 WETH
        console.log("\n--- Test 3: Supply WETH ---");
        _testSupply(subvault3, Constants.AAVE_CORE, Constants.WETH, 2 ether, json);
        _waitForRPC();

        // Test 4: Borrow 0.1 WETH (ETH-correlated, allowed in eMode 1)
        console.log("\n--- Test 4: Borrow WETH (eMode 1) ---");
        _testBorrow(subvault3, Constants.AAVE_CORE, Constants.WETH, 0.1 ether, 2, json);
        _waitForRPC();

        // Test 5: Repay WETH
        console.log("\n--- Test 5: Repay WETH ---");
        _testRepay(subvault3, Constants.AAVE_CORE, Constants.WETH, 0.1 ether, 2, json);
        _waitForRPC();

        // Test 6: Withdraw 0.5 WETH
        console.log("\n--- Test 6: Withdraw WETH ---");
        _testWithdraw(subvault3, Constants.AAVE_CORE, Constants.WETH, 0.5 ether, json);

        console.log("\n=== All Prod SV3 Aave Tests Passed ===");
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

    /// @notice Test Morpho savETH/WETH market operations on prod subvault 3
    /// @dev Morpho indices in sv3: 44-51
    ///   44: savETH approve (collateral), 45: WETH approve (loan)
    ///   46: supply, 47: supplyCollateral, 48: repay, 49: borrow, 50: withdraw, 51: withdrawCollateral
    function test_ProdSv3_MorphoOperations() public {
        console.log("\n=== Testing Prod Subvault 3 - Morpho savETH/WETH Market ===");

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory json = vm.readFile(path);

        // Fund subvault with WETH (loan token) and savETH (collateral token)
        deal(Constants.WETH, subvault3, 10 ether);
        deal(SAVETH, subvault3, 10 ether);

        IMorpho.MarketParams memory params = IMorpho(Constants.MORPHO).idToMarketParams(MARKET_SAVETH_WETH);
        console.log("Market loan token:", params.loanToken);
        console.log("Market collateral token:", params.collateralToken);

        // 1. Approve savETH (collateral) for Morpho - index 44
        console.log("\n--- Morpho Test 1: Approve savETH (collateral) ---");
        _execMorphoCall(SAVETH, 0, abi.encodeCall(IERC20.approve, (Constants.MORPHO, type(uint256).max)), json, 44);
        console.log("savETH approve - SUCCESS");
        _waitForRPC();

        // 2. Approve WETH (loan) for Morpho - index 45
        console.log("\n--- Morpho Test 2: Approve WETH (loan) ---");
        _execMorphoCall(Constants.WETH, 0, abi.encodeCall(IERC20.approve, (Constants.MORPHO, type(uint256).max)), json, 45);
        console.log("WETH approve - SUCCESS");
        _waitForRPC();

        // 3. Supply WETH (loan token) - index 46
        console.log("\n--- Morpho Test 3: Supply WETH ---");
        _execMorphoCall(Constants.MORPHO, 0, abi.encodeCall(IMorpho.supply, (params, 1 ether, 0, subvault3, "")), json, 46);
        console.log("Supply WETH - SUCCESS");
        _waitForRPC();

        // 4. Supply savETH as collateral - index 47
        console.log("\n--- Morpho Test 4: Supply savETH collateral ---");
        _execMorphoCall(Constants.MORPHO, 0, abi.encodeCall(IMorpho.supplyCollateral, (params, 2 ether, subvault3, "")), json, 47);
        console.log("Supply savETH collateral - SUCCESS");
        _waitForRPC();

        // 5. Borrow WETH - index 49
        console.log("\n--- Morpho Test 5: Borrow WETH ---");
        _execMorphoCall(Constants.MORPHO, 0, abi.encodeCall(IMorpho.borrow, (params, 0.1 ether, 0, subvault3, subvault3)), json, 49);
        console.log("Borrow WETH - SUCCESS");
        _waitForRPC();

        // 6. Repay WETH - index 48
        console.log("\n--- Morpho Test 6: Repay WETH ---");
        _execMorphoCall(Constants.MORPHO, 0, abi.encodeCall(IMorpho.repay, (params, 0.1 ether, 0, subvault3, "")), json, 48);
        console.log("Repay WETH - SUCCESS");
        _waitForRPC();

        // 7. Withdraw WETH (loan) - index 50
        console.log("\n--- Morpho Test 7: Withdraw WETH ---");
        _execMorphoCall(Constants.MORPHO, 0, abi.encodeCall(IMorpho.withdraw, (params, 0.5 ether, 0, subvault3, subvault3)), json, 50);
        console.log("Withdraw WETH - SUCCESS");
        _waitForRPC();

        // 8. Withdraw savETH collateral - index 51
        console.log("\n--- Morpho Test 8: Withdraw savETH collateral ---");
        _execMorphoCall(Constants.MORPHO, 0, abi.encodeCall(IMorpho.withdrawCollateral, (params, 1 ether, subvault3, subvault3)), json, 51);
        console.log("Withdraw savETH collateral - SUCCESS");

        console.log("\n=== All Prod SV3 Morpho Tests Passed ===");
    }

    /// @notice Test CCIP bridge wstETH approval and ccipSend on prod subvault 3
    /// @dev CCIP indices in sv3: 70 (wstETH approve), 71 (ccipSend)
    function test_ProdSv3_CCIPBridgeOperations() public {
        console.log("\n=== Testing Prod Subvault 3 - CCIP Bridge wstETH to Monad ===");

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory json = vm.readFile(path);

        // Fund subvault with wstETH
        deal(Constants.WSTETH, subvault3, 10 ether);

        // 1. Approve wstETH for CCIP Router - index 70
        console.log("\n--- CCIP Test 1: Approve wstETH for CCIP Router ---");
        {
            bytes memory verificationData = _getVerificationData(json, 70);
            bytes32[] memory proof = _getProof(json, 70);

            IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
                verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
                verificationData: verificationData,
                proof: proof
            });

            bytes memory callData = abi.encodeCall(IERC20.approve, (Constants.CCIP_ETHEREUM_ROUTER, type(uint256).max));

            vm.prank(prodCurator);
            ICallModule(subvault3).call(Constants.WSTETH, 0, callData, payload);
            console.log("wstETH approve for CCIP Router - SUCCESS");
        }
        _waitForRPC();

        // 2. CCIP send wstETH to Monad - index 71
        console.log("\n--- CCIP Test 2: ccipSend wstETH to Monad ---");
        {
            bytes memory verificationData = _getVerificationData(json, 71);
            bytes32[] memory proof = _getProof(json, 71);

            IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
                verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
                verificationData: verificationData,
                proof: proof
            });

            address targetSubvault = 0x0C7cb4e1241F4B7Fd65DE59FDE5a6dBFf190fB20;

            CCIPClient.EVMTokenAmount[] memory tokenAmounts = new CCIPClient.EVMTokenAmount[](1);
            tokenAmounts[0] = CCIPClient.EVMTokenAmount({token: Constants.WSTETH, amount: 1 ether});

            bytes memory callData = abi.encodeCall(
                ICCIPRouterClient.ccipSend,
                (
                    Constants.CCIP_MONAD_CHAIN_SELECTOR,
                    CCIPClient.EVM2AnyMessage({
                        receiver: abi.encode(targetSubvault),
                        data: new bytes(0),
                        tokenAmounts: tokenAmounts,
                        feeToken: address(0), // pay in ETH
                        extraArgs: CCIPClient._argsToBytes(
                            CCIPClient.EVMExtraArgsV2({gasLimit: 0, allowOutOfOrderExecution: true})
                        )
                    })
                )
            );

            // Get fee estimate from CCIP router
            uint256 ccipFee = 0.001 ether; // generous fee buffer
            vm.deal(subvault3, ccipFee);
            vm.prank(prodCurator);
            try ICallModule(subvault3).call(Constants.CCIP_ETHEREUM_ROUTER, ccipFee, callData, payload) {
                console.log("CCIP ccipSend wstETH to Monad - SUCCESS");
            } catch (bytes memory reason) {
                console.log("CCIP ccipSend reverted, reason length:", reason.length);
                console.logBytes(reason);
                revert("CCIP ccipSend should not revert");
            }
        }

        console.log("\n=== All Prod SV3 CCIP Bridge Tests Passed ===");
    }

    /// @notice Test NTT bridge WETH approval and transfer call on prod subvault 3
    /// @dev NTT indices in sv3: 72 (WETH approve), 73 (transfer)
    function test_ProdSv3_NTTBridgeOperations() public {
        console.log("\n=== Testing Prod Subvault 3 - NTT Bridge WETH to Monad ===");

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory json = vm.readFile(path);

        // Fund subvault with WETH
        deal(Constants.WETH, subvault3, 10 ether);

        // 1. Approve WETH for NTT Router - index 72
        console.log("\n--- NTT Test 1: Approve WETH for NTT Router ---");
        {
            bytes memory verificationData = _getVerificationData(json, 72);
            bytes32[] memory proof = _getProof(json, 72);

            IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
                verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
                verificationData: verificationData,
                proof: proof
            });

            bytes memory callData = abi.encodeCall(IERC20.approve, (Constants.NTT_ROUTER, type(uint256).max));

            vm.prank(prodCurator);
            ICallModule(subvault3).call(Constants.WETH, 0, callData, payload);
            console.log("WETH approve for NTT Router - SUCCESS");
        }
        _waitForRPC();

        // 2. NTT transfer call - index 73
        // Fetch a fresh signed quote from the Wormhole executor API, then build transfer calldata
        console.log("\n--- NTT Test 2: NTT Transfer ---");
        {
            bytes memory verificationData = _getVerificationData(json, 73);
            bytes32[] memory proof = _getProof(json, 73);

            IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
                verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
                verificationData: verificationData,
                proof: proof
            });

            address targetSubvault = 0x0C7cb4e1241F4B7Fd65DE59FDE5a6dBFf190fB20;

            // Fetch fresh quote from Wormhole executor API (avoids expired-quote reverts)
            (uint256 estimatedCost, bytes memory signedQuote) = _fetchFreshNTTQuote();

            bytes memory callData = abi.encodeCall(
                INttManagerWithExecutor.transfer,
                (
                    Constants.NTT_WETH_MANAGER,
                    Constants.WETH,
                    1 ether,
                    Constants.WORMHOLE_MONAD_CHAIN_ID,
                    bytes32(uint256(uint160(targetSubvault))),
                    bytes32(uint256(uint160(subvault3))), // refundAddress = source subvault
                    // 38-byte transceiverInstructions: 2 transceivers (Wormhole 1-byte + Axelar 32-byte)
                    hex"020001010120000000000000000000000000000000000000000000000000000000000000ffff",
                    INttManagerWithExecutor.ExecutorArgs({
                        value: estimatedCost,
                        refundAddress: prodCurator,
                        signedQuote: signedQuote,
                        // Relay instructions: 1 GasInstruction, gasLimit=1000000, msgValue=0
                        instructions: hex"01000000000000000000000000000f424000000000000000000000000000000000"
                    }),
                    INttManagerWithExecutor.FeeArgs({dbps: 0, payee: address(0)})
                )
            );

            vm.deal(subvault3, 1 ether); // ETH for wormhole fee
            vm.prank(prodCurator);
            ICallModule(subvault3).call(Constants.NTT_ROUTER, 0.1 ether, callData, payload);
            console.log("NTT transfer call - SUCCESS");
        }

        console.log("\n=== All Prod SV3 NTT Bridge Tests Passed ===");
    }

    /// @notice Test that CCIP bridge with wrong receiver is rejected by bitmask
    function test_RevertWhen_CCIPWrongReceiver() public {
        console.log("\n=== Testing CCIP Wrong Receiver Enforcement ===");

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory json = vm.readFile(path);

        deal(Constants.WSTETH, subvault3, 10 ether);

        bytes memory verificationData = _getVerificationData(json, 71);
        bytes32[] memory proof = _getProof(json, 71);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        address wrongReceiver = address(0xdead);

        CCIPClient.EVMTokenAmount[] memory tokenAmounts = new CCIPClient.EVMTokenAmount[](1);
        tokenAmounts[0] = CCIPClient.EVMTokenAmount({token: Constants.WSTETH, amount: 1 ether});

        bytes memory callData = abi.encodeCall(
            ICCIPRouterClient.ccipSend,
            (
                Constants.CCIP_MONAD_CHAIN_SELECTOR,
                CCIPClient.EVM2AnyMessage({
                    receiver: abi.encode(wrongReceiver), // ← WRONG receiver
                    data: new bytes(0),
                    tokenAmounts: tokenAmounts,
                    feeToken: address(0),
                    extraArgs: CCIPClient._argsToBytes(
                        CCIPClient.EVMExtraArgsV2({gasLimit: 0, allowOutOfOrderExecution: true})
                    )
                })
            )
        );

        vm.prank(prodCurator);
        vm.expectRevert();
        ICallModule(subvault3).call(Constants.CCIP_ETHEREUM_ROUTER, 0.001 ether, callData, payload);

        console.log("Wrong CCIP receiver REVERTED as expected - SUCCESS");
    }

    /// @notice Test that CCIP bridge with wrong chain selector is rejected by bitmask
    function test_RevertWhen_CCIPWrongChainSelector() public {
        console.log("\n=== Testing CCIP Wrong Chain Selector Enforcement ===");

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory json = vm.readFile(path);

        deal(Constants.WSTETH, subvault3, 10 ether);

        bytes memory verificationData = _getVerificationData(json, 71);
        bytes32[] memory proof = _getProof(json, 71);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        address targetSubvault = 0x0C7cb4e1241F4B7Fd65DE59FDE5a6dBFf190fB20;

        CCIPClient.EVMTokenAmount[] memory tokenAmounts = new CCIPClient.EVMTokenAmount[](1);
        tokenAmounts[0] = CCIPClient.EVMTokenAmount({token: Constants.WSTETH, amount: 1 ether});

        bytes memory callData = abi.encodeCall(
            ICCIPRouterClient.ccipSend,
            (
                uint64(999999999), // ← WRONG chain selector
                CCIPClient.EVM2AnyMessage({
                    receiver: abi.encode(targetSubvault),
                    data: new bytes(0),
                    tokenAmounts: tokenAmounts,
                    feeToken: address(0),
                    extraArgs: CCIPClient._argsToBytes(
                        CCIPClient.EVMExtraArgsV2({gasLimit: 0, allowOutOfOrderExecution: true})
                    )
                })
            )
        );

        vm.prank(prodCurator);
        vm.expectRevert();
        ICallModule(subvault3).call(Constants.CCIP_ETHEREUM_ROUTER, 0.001 ether, callData, payload);

        console.log("Wrong CCIP chain selector REVERTED as expected - SUCCESS");
    }

    /// @notice Test that NTT transfer with wrong dstEid is rejected by bitmask
    function test_RevertWhen_NTTWrongDstEid() public {
        console.log("\n=== Testing NTT Wrong dstEid Enforcement ===");

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory json = vm.readFile(path);

        deal(Constants.WETH, subvault3, 10 ether);

        bytes memory verificationData = _getVerificationData(json, 73);
        bytes32[] memory proof = _getProof(json, 73);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        address targetSubvault = 0x0C7cb4e1241F4B7Fd65DE59FDE5a6dBFf190fB20;

        bytes memory callData = abi.encodeCall(
            INttManagerWithExecutor.transfer,
            (
                Constants.NTT_WETH_MANAGER,
                Constants.WETH,
                1 ether,
                uint16(9999), // ← WRONG chain ID
                bytes32(uint256(uint160(targetSubvault))),
                bytes32(uint256(uint160(subvault3))),
                new bytes(38),
                INttManagerWithExecutor.ExecutorArgs({
                    value: 0,
                    refundAddress: prodCurator,
                    signedQuote: new bytes(165),
                    instructions: new bytes(33)
                }),
                INttManagerWithExecutor.FeeArgs({dbps: 0, payee: address(0)})
            )
        );

        vm.prank(prodCurator);
        vm.expectRevert();
        ICallModule(subvault3).call(Constants.NTT_ROUTER, 0, callData, payload);

        console.log("Wrong NTT dstEid REVERTED as expected - SUCCESS");
    }

    /// @notice Test that NTT transfer with wrong recipient is rejected by bitmask
    function test_RevertWhen_NTTWrongRecipient() public {
        console.log("\n=== Testing NTT Wrong Recipient Enforcement ===");

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory json = vm.readFile(path);

        deal(Constants.WETH, subvault3, 10 ether);

        bytes memory verificationData = _getVerificationData(json, 73);
        bytes32[] memory proof = _getProof(json, 73);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        // Use WRONG recipient (0xdead instead of the real target subvault)
        bytes memory callData = abi.encodeCall(
            INttManagerWithExecutor.transfer,
            (
                Constants.NTT_WETH_MANAGER,
                Constants.WETH,
                1 ether,
                Constants.WORMHOLE_MONAD_CHAIN_ID,
                bytes32(uint256(uint160(address(0xdead)))), // ← WRONG recipient
                bytes32(uint256(uint160(subvault3))),       // refundAddress = source subvault (correct)
                new bytes(38),
                INttManagerWithExecutor.ExecutorArgs({
                    value: 0,
                    refundAddress: prodCurator,
                    signedQuote: new bytes(165),
                    instructions: new bytes(33)
                }),
                INttManagerWithExecutor.FeeArgs({dbps: 0, payee: address(0)})
            )
        );

        vm.prank(prodCurator);
        vm.expectRevert(); // Should revert because bitmask won't match
        ICallModule(subvault3).call(Constants.NTT_ROUTER, 0, callData, payload);

        console.log("Wrong NTT recipient REVERTED as expected - SUCCESS");
    }

    /// @notice Test that NTT transfer with wrong refund address is rejected by bitmask
    function test_RevertWhen_NTTWrongRefundAddress() public {
        console.log("\n=== Testing NTT Wrong Refund Address Enforcement ===");

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv3:all.json");
        string memory json = vm.readFile(path);

        deal(Constants.WETH, subvault3, 10 ether);

        bytes memory verificationData = _getVerificationData(json, 73);
        bytes32[] memory proof = _getProof(json, 73);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        address targetSubvault = 0x0C7cb4e1241F4B7Fd65DE59FDE5a6dBFf190fB20;

        // Correct recipient, but WRONG refund address
        bytes memory callData = abi.encodeCall(
            INttManagerWithExecutor.transfer,
            (
                Constants.NTT_WETH_MANAGER,
                Constants.WETH,
                1 ether,
                Constants.WORMHOLE_MONAD_CHAIN_ID,
                bytes32(uint256(uint160(targetSubvault))),      // correct recipient
                bytes32(uint256(uint160(address(0xdead)))),     // ← WRONG refund address
                new bytes(38),
                INttManagerWithExecutor.ExecutorArgs({
                    value: 0,
                    refundAddress: prodCurator,
                    signedQuote: new bytes(165),
                    instructions: new bytes(33)
                }),
                INttManagerWithExecutor.FeeArgs({dbps: 0, payee: address(0)})
            )
        );

        vm.prank(prodCurator);
        vm.expectRevert(); // Should revert because bitmask locks refundAddress to source subvault
        ICallModule(subvault3).call(Constants.NTT_ROUTER, 0, callData, payload);

        console.log("Wrong NTT refund address REVERTED as expected - SUCCESS");
    }

    /// @notice Fetches a fresh signed quote from the Wormhole NTT executor API
    /// @dev API endpoint: POST https://executor.labsapis.com/v0/quote
    ///      Body: {"srcChain":2,"dstChain":48,"relayInstructions":"0x01..."}
    ///      - srcChain=2 (Ethereum), dstChain=48 (Monad)
    ///      - relayInstructions: 1 GasInstruction, gasLimit=1000000, msgValue=0
    ///      Response: {"signedQuote":"0x4551...","estimatedCost":"..."}
    ///      Requires ffi=true in foundry.toml + curl and jq on PATH
    function _fetchFreshNTTQuote() internal returns (uint256 estimatedCost, bytes memory signedQuote) {
        string[] memory cmd = new string[](3);
        cmd[0] = "bash";
        cmd[1] = "-c";
        cmd[2] = string.concat(
            'RESP=$(curl -s -X POST "https://executor.labsapis.com/v0/quote" ',
            '-H "Content-Type: application/json" ',
            "-d '{\"srcChain\":2,\"dstChain\":48,\"relayInstructions\":\"0x01000000000000000000000000000f424000000000000000000000000000000000\"}'); ",
            'COST=$(echo "$RESP" | jq -r .estimatedCost); ',
            'QUOTE=$(echo "$RESP" | jq -r .signedQuote); ',
            'cast abi-encode "f(uint256,bytes)" "$COST" "$QUOTE"'
        );
        bytes memory result = vm.ffi(cmd);
        (estimatedCost, signedQuote) = abi.decode(result, (uint256, bytes));
        console.log("Fetched fresh NTT quote, estimatedCost:", estimatedCost);
    }

    /// @notice Helper to execute a call with Morpho proof verification
    function _execMorphoCall(address target, uint256 value, bytes memory callData, string memory json, uint256 proofIndex) internal {
        bytes memory verificationData = _getVerificationData(json, proofIndex);
        bytes32[] memory proof = _getProof(json, proofIndex);

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });

        vm.prank(prodCurator);
        ICallModule(subvault3).call(target, value, callData, payload);
    }

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

        // Set eMode, approve, supply and borrow WETH (ETH-correlated, works in eMode 1)
        _testSetEMode(subvault3, Constants.AAVE_CORE, 1, json, 0);
        _testApprove(subvault3, Constants.WETH, Constants.AAVE_CORE, json);
        _testSupply(subvault3, Constants.AAVE_CORE, Constants.WETH, 2 ether, json);
        _testBorrow(subvault3, Constants.AAVE_CORE, Constants.WETH, 0.1 ether, 2, json);

        // Now try to repay with WRONG onBehalfOf
        uint256 proofIndex = _findProofForRepay(json, Constants.WETH);
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
            (Constants.WETH, 0.1 ether, 2, wrongOnBehalfOf) // ← WRONG onBehalfOf!
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
    // Aave has 22 ops, so Spark starts at 22
    // 22: setUserEMode (Spark)
    // 23: WETH approve (supply), 24: WETH supply, 25: WETH withdraw
    // 26: wstETH approve (supply), 27: wstETH supply, 28: wstETH withdraw
    // 29: WETH approve (borrow), 30: WETH borrow, 31: WETH repay
    // 32: wstETH approve (borrow), 33: wstETH borrow, 34: wstETH repay
    // 35: USDC approve, 36: USDC borrow, 37: USDC repay
    // 38: USDT approve, 39: USDT borrow, 40: USDT repay
    // 41: USDe approve, 42: USDe borrow, 43: USDe repay

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
        if (token == Constants.WETH) return 23;
        if (token == Constants.WSTETH) return 26;
        if (token == Constants.USDC) return 35;
        if (token == Constants.USDT) return 38;
        if (token == Constants.USDE) return 41;
        revert("Spark: Proof not found for approve");
    }

    function _findProofForApproveSparkBorrow(address token) internal pure returns (uint256) {
        if (token == Constants.WETH) return 29;
        if (token == Constants.WSTETH) return 32;
        revert("Spark: Proof not found for approve borrow");
    }

    function _findProofForSupplySpark(address asset) internal pure returns (uint256) {
        if (asset == Constants.WETH) return 24;
        if (asset == Constants.WSTETH) return 27;
        revert("Spark: Proof not found for supply");
    }

    function _findProofForWithdrawSpark(address asset) internal pure returns (uint256) {
        if (asset == Constants.WETH) return 25;
        if (asset == Constants.WSTETH) return 28;
        revert("Spark: Proof not found for withdraw");
    }

    function _findProofForBorrowSpark(address asset) internal pure returns (uint256) {
        if (asset == Constants.WETH) return 30;
        if (asset == Constants.WSTETH) return 33;
        if (asset == Constants.USDC) return 36;
        if (asset == Constants.USDT) return 39;
        if (asset == Constants.USDE) return 42;
        revert("Spark: Proof not found for borrow");
    }

    function _findProofForRepaySpark(address asset) internal pure returns (uint256) {
        if (asset == Constants.WETH) return 31;
        if (asset == Constants.WSTETH) return 34;
        if (asset == Constants.USDC) return 37;
        if (asset == Constants.USDT) return 40;
        if (asset == Constants.USDE) return 43;
        revert("Spark: Proof not found for repay");
    }
}
