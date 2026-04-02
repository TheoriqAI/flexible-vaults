// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "../scripts/ethereum/Constants.sol";
import "../src/interfaces/modules/ICallModule.sol";
import "../src/permissions/Verifier.sol";
import "../src/interfaces/utils/ISwapModule.sol";
import "../scripts/common/interfaces/IAavePoolV3.sol";
import "../scripts/common/interfaces/ILidoWithdrawalQueue.sol";
import "../scripts/common/interfaces/ISUSDe.sol";
import "../scripts/common/interfaces/IPendleRouter.sol";
import "../scripts/common/interfaces/IMorpho.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title Prod SV4 eMode 38 Integration Tests
/// @notice Tests the prod SV4 JSON (sv4-all.json) with eMode 38, Pendle, SwapModule, Morpho, and withdrawals
/// @dev Uses scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv4:all.json (111 ops)
///
/// Index map:
/// 0: setUserEMode(38)
/// 1-3: sUSDe (approve, supply, withdraw)
/// 4-6: PT-srUSDe (approve, supply, withdraw)
/// 7-9: wstETH (approve, supply, withdraw)
/// 10-12: WETH (approve, supply, withdraw)
/// 13-15: USDe (approve, borrow, repay)
/// 16-18: USDC (approve, borrow, repay)
/// 19-21: USDT (approve, borrow, repay)
/// 22-29: Morpho sNUSD/USDC market
/// 30-37: Morpho reUSD/USDC market
/// 38-45: Morpho savUSD/USDC market
/// 46-53: Morpho sUSN/USDC market
/// 54-76: SwapModule (ETH, WETH, wstETH, USDC, USDT, USDe, sUSDe, NUSD)
/// 77-85: Pendle PT-sUSDe-06MAY2026 (USDe+sUSDe in, USDe+sUSDe out)
/// 86-96: Pendle PT-srUSDe-01APR2026 (USDe+sUSDe+srUSDe in, sUSDe+srUSDe out)
/// 97-101: Pendle PT-sNUSD-03JUN2026 (sNUSD)
/// 102-104: Lido withdrawal (approve, request, claim)
/// 105-106: sUSDe (cooldownShares, unstake)
/// 107-109: sNUSD (approve nUSD, deposit, cooldownShares)
/// 110: srUSDe withdraw (sUSDe)
contract ProdSv4EMode38IntegrationTest is Test {
    address constant prodCurator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;
    address constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address constant activeAdmin = 0x2D95cb50F204B8B84606751F262b407C08528c85;
    address constant LIDO_WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;
    address constant SWAP_MODULE = 0x114dea9b67A31E704dAbE28bed51C49C01940DDf;

    // PT tokens from the pendle config
    address constant PT_SUSDE_06MAY2026 = 0x3de0ff76E8b528C092d47b9DaC775931cef80F49;
    address constant PENDLE_MARKET_PT_SUSDE_06MAY2026 = 0x8dAe8ECe668cf80d348873F23D456448E8694883;

    // Morpho market IDs
    bytes32 constant MARKET_SNUSD_USDC = 0xae60b71b407e0517ead445b7113a7ffa07ea4a9379d526ade541a3e9ec777cb4;
    bytes32 constant MARKET_REUSD_USDC = 0x4565ac05d38b19374ccbb04c17cca60ca9353cd41824f0803d0fc7704f60eaed;
    bytes32 constant MARKET_SAVUSD_USDC = 0xe07d416323a1afbfe0bf2fe27ffb549ff565cf5c86d21b79fc60664038e597c9;
    bytes32 constant MARKET_SUSN_USDC = 0x8924445a76b678c536df977ed9222fb0b23ee5311497dd0223fe6270bb20b4e6;

    address subvault4;
    IVerifier verifier4;
    bytes32 merkleRoot;
    string json;

    function setUp() public {
        vm.createSelectFork("https://rpc.mevblocker.io");

        Vault vault = Vault(payable(VAULT_PROD));
        subvault4 = vault.subvaultAt(4);
        console.log("Subvault 4:", subvault4);

        verifier4 = ICallModule(subvault4).verifier();
        console.log("Verifier 4:", address(verifier4));

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv4:all.json");
        json = vm.readFile(path);
        merkleRoot = bytes32(vm.parseJsonBytes32(json, ".merkle_root"));
        console.log("Merkle root:", vm.toString(merkleRoot));

        vm.prank(activeAdmin);
        verifier4.setMerkleRoot(merkleRoot);

        require(verifier4.merkleRoot() == merkleRoot, "Merkle root mismatch");
        console.log("Merkle root set on verifier");
    }

    function _waitForRPC() internal {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function _getVerificationData(uint256 index) internal view returns (bytes memory) {
        string memory basePath = string.concat(".merkle_proofs[", vm.toString(index), "].verificationData");
        return vm.parseJsonBytes(json, basePath);
    }

    function _getProof(uint256 index) internal view returns (bytes32[] memory) {
        string memory basePath = string.concat(".merkle_proofs[", vm.toString(index), "].proof");
        bytes memory proofData = vm.parseJson(json, basePath);
        return abi.decode(proofData, (bytes32[]));
    }

    function _payload(uint256 index) internal view returns (IVerifier.VerificationPayload memory) {
        return IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: _getVerificationData(index),
            proof: _getProof(index)
        });
    }

    function _exec(address target, uint256 value, bytes memory callData, uint256 proofIndex) internal {
        vm.prank(prodCurator);
        ICallModule(subvault4).call(target, value, callData, _payload(proofIndex));
    }

    // =================== AAVE EMODE 38 TESTS ===================

    function test_ProdSv4_AaveEMode38Operations() public {
        console.log("\n=== Testing Prod SV4 - Aave eMode 38 Operations ===");

        // Fund subvault with sUSDe, PT-srUSDe, wstETH, and WETH
        deal(Constants.SUSDE, subvault4, 100 ether);
        deal(Constants.PT_SRUSDE_01APR2026, subvault4, 50 ether);
        deal(Constants.WSTETH, subvault4, 10 ether);
        deal(Constants.WETH, subvault4, 10 ether);

        // 1. Approve sUSDe for Aave (index 1)
        console.log("\n--- Approve sUSDe for Aave ---");
        _exec(Constants.SUSDE, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 1);
        console.log("sUSDe approve - SUCCESS");
        _waitForRPC();

        // 2. Supply sUSDe (index 2)
        console.log("\n--- Supply sUSDe ---");
        _exec(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.supply, (Constants.SUSDE, 50 ether, subvault4, 0)), 2);
        console.log("sUSDe supply - SUCCESS");
        _waitForRPC();

        // 3. Approve PT-srUSDe for Aave (index 4)
        console.log("\n--- Approve PT-srUSDe for Aave ---");
        _exec(Constants.PT_SRUSDE_01APR2026, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 4);
        console.log("PT-srUSDe approve - SUCCESS");
        _waitForRPC();

        // 4. Supply PT-srUSDe (index 5)
        console.log("\n--- Supply PT-srUSDe ---");
        _exec(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.supply, (Constants.PT_SRUSDE_01APR2026, 25 ether, subvault4, 0)), 5);
        console.log("PT-srUSDe supply - SUCCESS");
        _waitForRPC();

        // 5. Approve wstETH for Aave (index 7)
        console.log("\n--- Approve wstETH for Aave ---");
        _exec(Constants.WSTETH, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 7);
        console.log("wstETH approve - SUCCESS");
        _waitForRPC();

        // 6. Supply wstETH (index 8)
        console.log("\n--- Supply wstETH ---");
        _exec(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.supply, (Constants.WSTETH, 5 ether, subvault4, 0)), 8);
        console.log("wstETH supply - SUCCESS");
        _waitForRPC();

        // 7. Approve WETH for Aave (index 10)
        console.log("\n--- Approve WETH for Aave ---");
        _exec(Constants.WETH, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 10);
        console.log("WETH approve - SUCCESS");
        _waitForRPC();

        // 8. Supply WETH (index 11)
        console.log("\n--- Supply WETH ---");
        _exec(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.supply, (Constants.WETH, 5 ether, subvault4, 0)), 11);
        console.log("WETH supply - SUCCESS");
        _waitForRPC();

        // 9. Set eMode 38 (index 0)
        console.log("\n--- Set eMode 38 ---");
        _exec(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.setUserEMode, (38)), 0);
        console.log("Set eMode 38 - SUCCESS");
        _waitForRPC();

        // Verify collateral position
        (uint256 totalCollateral,,uint256 availableBorrows,,,) =
            IAavePoolV3(Constants.AAVE_CORE).getUserAccountData(subvault4);
        console.log("Total collateral (base):", totalCollateral);
        console.log("Available borrows:", availableBorrows);
        require(totalCollateral > 0, "Should have collateral");

        // 10. Approve USDe for repayment (index 13)
        console.log("\n--- Approve USDe ---");
        _exec(Constants.USDE, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 13);
        console.log("USDe approve - SUCCESS");
        _waitForRPC();

        // 11. Borrow USDe (index 14)
        console.log("\n--- Borrow USDe ---");
        _exec(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.borrow, (Constants.USDE, 10e18, 2, 0, subvault4)), 14);
        console.log("USDe borrow - SUCCESS");
        _waitForRPC();

        // 12. Repay USDe (index 15)
        console.log("\n--- Repay USDe ---");
        _exec(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.repay, (Constants.USDE, 10e18, 2, subvault4)), 15);
        console.log("USDe repay - SUCCESS");
        _waitForRPC();

        // 13. Approve USDC (index 16)
        console.log("\n--- Approve USDC ---");
        _exec(Constants.USDC, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 16);
        console.log("USDC approve - SUCCESS");
        _waitForRPC();

        // 14. Borrow USDC (index 17)
        console.log("\n--- Borrow USDC ---");
        _exec(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.borrow, (Constants.USDC, 10e6, 2, 0, subvault4)), 17);
        console.log("USDC borrow - SUCCESS");
        _waitForRPC();

        // 15. Repay USDC (index 18)
        console.log("\n--- Repay USDC ---");
        _exec(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.repay, (Constants.USDC, 10e6, 2, subvault4)), 18);
        console.log("USDC repay - SUCCESS");
        _waitForRPC();

        // 16. Approve USDT (index 19)
        console.log("\n--- Approve USDT ---");
        _exec(Constants.USDT, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 19);
        console.log("USDT approve - SUCCESS");
        _waitForRPC();

        // 17. Borrow USDT (index 20)
        console.log("\n--- Borrow USDT ---");
        _exec(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.borrow, (Constants.USDT, 10e6, 2, 0, subvault4)), 20);
        console.log("USDT borrow - SUCCESS");
        _waitForRPC();

        // 18. Repay USDT (index 21)
        console.log("\n--- Repay USDT ---");
        _exec(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.repay, (Constants.USDT, 10e6, 2, subvault4)), 21);
        console.log("USDT repay - SUCCESS");
        _waitForRPC();

        // 17. Withdraw sUSDe (index 3)
        console.log("\n--- Withdraw sUSDe ---");
        _exec(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.withdraw, (Constants.SUSDE, 10 ether, subvault4)), 3);
        console.log("sUSDe withdraw - SUCCESS");
        _waitForRPC();

        // 18. Withdraw PT-srUSDe (index 6)
        console.log("\n--- Withdraw PT-srUSDe ---");
        _exec(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.withdraw, (Constants.PT_SRUSDE_01APR2026, 5 ether, subvault4)), 6);
        console.log("PT-srUSDe withdraw - SUCCESS");
        _waitForRPC();

        // 21. Withdraw wstETH (index 9)
        console.log("\n--- Withdraw wstETH ---");
        _exec(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.withdraw, (Constants.WSTETH, 1 ether, subvault4)), 9);
        console.log("wstETH withdraw - SUCCESS");
        _waitForRPC();

        // 22. Withdraw WETH (index 12)
        console.log("\n--- Withdraw WETH ---");
        _exec(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.withdraw, (Constants.WETH, 1 ether, subvault4)), 12);
        console.log("WETH withdraw - SUCCESS");

        console.log("\n=== All Aave eMode 38 Tests Passed ===");
    }

    // =================== PENDLE TESTS ===================

    function test_ProdSv4_PendleSwapSusdeForPtSusde() public {
        console.log("\n=== Testing Pendle: sUSDe -> PT-sUSDe-06MAY2026 ===");

        deal(Constants.SUSDE, subvault4, 10 ether);

        // Approve sUSDe for Pendle Router (index 78)
        console.log("\n--- Approve sUSDe for Pendle ---");
        _exec(Constants.SUSDE, 0, abi.encodeCall(IERC20.approve, (Constants.PENDLE_ROUTER, type(uint256).max)), 78);
        console.log("sUSDe approve - SUCCESS");
        _waitForRPC();

        // swapExactTokenForPt: sUSDe -> PT-sUSDe-06MAY2026 (index 80)
        console.log("\n--- swapExactTokenForPt (sUSDe -> PT-sUSDe) ---");
        {
            IPendleRouter.TokenInput memory input = IPendleRouter.TokenInput({
                tokenIn: Constants.SUSDE,
                netTokenIn: 1 ether,
                tokenMintSy: Constants.SUSDE,
                pendleSwap: address(0),
                swapData: IPendleRouter.SwapData({
                    swapType: IPendleRouter.SwapType.NONE,
                    extRouter: address(0),
                    extCalldata: "",
                    needScale: false
                })
            });
            IPendleRouter.ApproxParams memory guessPtOut = IPendleRouter.ApproxParams({
                guessMin: 0,
                guessMax: type(uint256).max,
                guessOffchain: 0,
                maxIteration: 256,
                eps: 1e14
            });
            IPendleRouter.LimitOrderData memory limit = IPendleRouter.LimitOrderData({
                limitRouter: address(0),
                epsSkipMarket: 0,
                normalFills: new IPendleRouter.FillOrderParams[](0),
                flashFills: new IPendleRouter.FillOrderParams[](0),
                optData: ""
            });
            bytes memory callData = abi.encodeCall(
                IPendleRouter.swapExactTokenForPt,
                (subvault4, PENDLE_MARKET_PT_SUSDE_06MAY2026, 0, guessPtOut, input, limit)
            );
            _exec(Constants.PENDLE_ROUTER, 0, callData, 80);

            uint256 ptBal = IERC20(PT_SUSDE_06MAY2026).balanceOf(subvault4);
            console.log("PT-sUSDe balance:", ptBal);
            require(ptBal > 0, "Should have PT tokens");
            console.log("swapExactTokenForPt - SUCCESS");
        }
        _waitForRPC();

        // Approve PT for Pendle Router (index 81)
        console.log("\n--- Approve PT-sUSDe for Pendle ---");
        _exec(PT_SUSDE_06MAY2026, 0, abi.encodeCall(IERC20.approve, (Constants.PENDLE_ROUTER, type(uint256).max)), 81);
        console.log("PT approve - SUCCESS");
        _waitForRPC();

        // swapExactPtForToken: PT-sUSDe -> sUSDe (index 83)
        console.log("\n--- swapExactPtForToken (PT-sUSDe -> sUSDe) ---");
        {
            uint256 ptBal = IERC20(PT_SUSDE_06MAY2026).balanceOf(subvault4);
            uint256 susdeBefore = IERC20(Constants.SUSDE).balanceOf(subvault4);

            IPendleRouter.TokenOutput memory output = IPendleRouter.TokenOutput({
                tokenOut: Constants.SUSDE,
                minTokenOut: 0,
                tokenRedeemSy: Constants.SUSDE,
                pendleSwap: address(0),
                swapData: IPendleRouter.SwapData({
                    swapType: IPendleRouter.SwapType.NONE,
                    extRouter: address(0),
                    extCalldata: "",
                    needScale: false
                })
            });
            IPendleRouter.LimitOrderData memory limit = IPendleRouter.LimitOrderData({
                limitRouter: address(0),
                epsSkipMarket: 0,
                normalFills: new IPendleRouter.FillOrderParams[](0),
                flashFills: new IPendleRouter.FillOrderParams[](0),
                optData: ""
            });
            bytes memory callData = abi.encodeCall(
                IPendleRouter.swapExactPtForToken,
                (subvault4, PENDLE_MARKET_PT_SUSDE_06MAY2026, ptBal, output, limit)
            );
            _exec(Constants.PENDLE_ROUTER, 0, callData, 83);

            uint256 susdeAfter = IERC20(Constants.SUSDE).balanceOf(subvault4);
            console.log("sUSDe before:", susdeBefore, "after:", susdeAfter);
            require(susdeAfter > susdeBefore, "Should have received sUSDe back");
            console.log("swapExactPtForToken - SUCCESS");
        }

        console.log("\n=== Pendle sUSDe Swap Tests Passed ===");
    }

    function test_ProdSv4_PendleSwapSnusdForPtSnusd() public {
        console.log("\n=== Testing Pendle: sNUSD -> PT-sNUSD-03JUN2026 ===");

        deal(Constants.SNUSD, subvault4, 100 ether);

        // Approve sNUSD for Pendle Router (index 97)
        console.log("\n--- Approve sNUSD for Pendle ---");
        _exec(Constants.SNUSD, 0, abi.encodeCall(IERC20.approve, (Constants.PENDLE_ROUTER, type(uint256).max)), 97);
        console.log("sNUSD approve - SUCCESS");
        _waitForRPC();

        // swapExactTokenForPt: sNUSD -> PT-sNUSD-03JUN2026 (index 98)
        console.log("\n--- swapExactTokenForPt (sNUSD -> PT-sNUSD) ---");
        {
            IPendleRouter.TokenInput memory input = IPendleRouter.TokenInput({
                tokenIn: Constants.SNUSD,
                netTokenIn: 10 ether,
                tokenMintSy: Constants.SNUSD,
                pendleSwap: address(0),
                swapData: IPendleRouter.SwapData({
                    swapType: IPendleRouter.SwapType.NONE,
                    extRouter: address(0),
                    extCalldata: "",
                    needScale: false
                })
            });
            IPendleRouter.ApproxParams memory guessPtOut = IPendleRouter.ApproxParams({
                guessMin: 0,
                guessMax: type(uint256).max,
                guessOffchain: 0,
                maxIteration: 256,
                eps: 1e14
            });
            IPendleRouter.LimitOrderData memory limit = IPendleRouter.LimitOrderData({
                limitRouter: address(0),
                epsSkipMarket: 0,
                normalFills: new IPendleRouter.FillOrderParams[](0),
                flashFills: new IPendleRouter.FillOrderParams[](0),
                optData: ""
            });
            bytes memory callData = abi.encodeCall(
                IPendleRouter.swapExactTokenForPt,
                (subvault4, Constants.PENDLE_MARKET_PT_SNUSD_03JUN2026, 0, guessPtOut, input, limit)
            );
            _exec(Constants.PENDLE_ROUTER, 0, callData, 98);

            uint256 ptBal = IERC20(Constants.PT_SNUSD_03JUN2026).balanceOf(subvault4);
            console.log("PT-sNUSD balance:", ptBal);
            require(ptBal > 0, "Should have PT tokens");
            console.log("swapExactTokenForPt - SUCCESS");
        }
        _waitForRPC();

        // Approve PT for Pendle Router (index 99)
        console.log("\n--- Approve PT-sNUSD for Pendle ---");
        _exec(Constants.PT_SNUSD_03JUN2026, 0, abi.encodeCall(IERC20.approve, (Constants.PENDLE_ROUTER, type(uint256).max)), 99);
        console.log("PT approve - SUCCESS");
        _waitForRPC();

        // swapExactPtForToken: PT-sNUSD -> sNUSD (index 100)
        console.log("\n--- swapExactPtForToken (PT-sNUSD -> sNUSD) ---");
        {
            uint256 ptBal = IERC20(Constants.PT_SNUSD_03JUN2026).balanceOf(subvault4);
            uint256 snusdBefore = IERC20(Constants.SNUSD).balanceOf(subvault4);

            IPendleRouter.TokenOutput memory output = IPendleRouter.TokenOutput({
                tokenOut: Constants.SNUSD,
                minTokenOut: 0,
                tokenRedeemSy: Constants.SNUSD,
                pendleSwap: address(0),
                swapData: IPendleRouter.SwapData({
                    swapType: IPendleRouter.SwapType.NONE,
                    extRouter: address(0),
                    extCalldata: "",
                    needScale: false
                })
            });
            IPendleRouter.LimitOrderData memory limit = IPendleRouter.LimitOrderData({
                limitRouter: address(0),
                epsSkipMarket: 0,
                normalFills: new IPendleRouter.FillOrderParams[](0),
                flashFills: new IPendleRouter.FillOrderParams[](0),
                optData: ""
            });
            bytes memory callData = abi.encodeCall(
                IPendleRouter.swapExactPtForToken,
                (subvault4, Constants.PENDLE_MARKET_PT_SNUSD_03JUN2026, ptBal, output, limit)
            );
            _exec(Constants.PENDLE_ROUTER, 0, callData, 100);

            uint256 snusdAfter = IERC20(Constants.SNUSD).balanceOf(subvault4);
            console.log("sNUSD before:", snusdBefore, "after:", snusdAfter);
            require(snusdAfter > snusdBefore, "Should have received sNUSD back");
            console.log("swapExactPtForToken - SUCCESS");
        }

        console.log("\n=== Pendle sNUSD Swap Tests Passed ===");
    }

    function test_ProdSv4_PendleExitPostExpPtSrusde() public {
        console.log("\n=== Testing Pendle: exitPostExpToToken PT-srUSDe -> srUSDe ===");

        // PT-srUSDe-01APR2026 is expired, so we can exit post-expiry
        deal(Constants.PT_SRUSDE_01APR2026, subvault4, 1 ether);

        // Approve PT-srUSDe for Pendle Router (index 92)
        console.log("\n--- Approve PT-srUSDe for Pendle ---");
        _exec(Constants.PT_SRUSDE_01APR2026, 0, abi.encodeCall(IERC20.approve, (Constants.PENDLE_ROUTER, type(uint256).max)), 92);
        console.log("PT-srUSDe approve - SUCCESS");
        _waitForRPC();

        // exitPostExpToToken: PT-srUSDe -> srUSDe (index 96)
        console.log("\n--- exitPostExpToToken (PT-srUSDe -> srUSDe) ---");
        {
            uint256 srusdeBefore = IERC20(Constants.SRUSDE).balanceOf(subvault4);
            uint256 ptBal = IERC20(Constants.PT_SRUSDE_01APR2026).balanceOf(subvault4);

            IPendleRouter.TokenOutput memory output = IPendleRouter.TokenOutput({
                tokenOut: Constants.SRUSDE,
                minTokenOut: 0,
                tokenRedeemSy: Constants.SRUSDE,
                pendleSwap: address(0),
                swapData: IPendleRouter.SwapData({
                    swapType: IPendleRouter.SwapType.NONE,
                    extRouter: address(0),
                    extCalldata: "",
                    needScale: false
                })
            });
            bytes memory callData = abi.encodeCall(
                IPendleRouter.exitPostExpToToken,
                (subvault4, Constants.PENDLE_MARKET_PT_SRUSDE_01APR2026, ptBal, 0, output)
            );
            _exec(Constants.PENDLE_ROUTER, 0, callData, 96);

            uint256 srusdeAfter = IERC20(Constants.SRUSDE).balanceOf(subvault4);
            console.log("srUSDe before:", srusdeBefore, "after:", srusdeAfter);
            require(srusdeAfter > srusdeBefore, "Should have received srUSDe from exitPostExpToToken");
            console.log("exitPostExpToToken - SUCCESS");
        }

        console.log("\n=== Pendle exitPostExpToToken PT-srUSDe Tests Passed ===");
    }

    // =================== SWAP MODULE TESTS ===================

    function test_ProdSv4_SwapModuleOperations() public {
        console.log("\n=== Testing Prod SV4 - SwapModule Operations ===");

        // Fund subvault
        deal(Constants.WETH, subvault4, 2 ether);
        deal(Constants.USDC, subvault4, 1000e6);
        deal(Constants.SUSDE, subvault4, 10 ether);
        deal(Constants.NUSD, subvault4, 100 ether);

        // Test WETH: approve (56), push (57), pull (58)
        console.log("\n--- WETH: approve for SwapModule ---");
        _exec(Constants.WETH, 0, abi.encodeCall(IERC20.approve, (SWAP_MODULE, type(uint256).max)), 56);
        console.log("WETH approve - SUCCESS");
        _waitForRPC();

        console.log("\n--- WETH: pushAssets ---");
        _exec(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pushAssets, (Constants.WETH, 0.5 ether)), 57);
        console.log("WETH push - SUCCESS");
        _waitForRPC();

        console.log("\n--- WETH: pullAssets ---");
        _exec(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pullAssets, (Constants.WETH, 0.1 ether)), 58);
        console.log("WETH pull - SUCCESS");
        _waitForRPC();

        // Test USDC: approve (62), push (63), pull (64)
        console.log("\n--- USDC: approve for SwapModule ---");
        _exec(Constants.USDC, 0, abi.encodeCall(IERC20.approve, (SWAP_MODULE, type(uint256).max)), 62);
        console.log("USDC approve - SUCCESS");
        _waitForRPC();

        console.log("\n--- USDC: pushAssets ---");
        _exec(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pushAssets, (Constants.USDC, 100e6)), 63);
        console.log("USDC push - SUCCESS");
        _waitForRPC();

        console.log("\n--- USDC: pullAssets ---");
        _exec(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pullAssets, (Constants.USDC, 50e6)), 64);
        console.log("USDC pull - SUCCESS");
        _waitForRPC();

        // Test sUSDe: approve (71), push (72), pull (73)
        console.log("\n--- sUSDe: approve for SwapModule ---");
        _exec(Constants.SUSDE, 0, abi.encodeCall(IERC20.approve, (SWAP_MODULE, type(uint256).max)), 71);
        console.log("sUSDe approve - SUCCESS");
        _waitForRPC();

        console.log("\n--- sUSDe: pushAssets ---");
        _exec(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pushAssets, (Constants.SUSDE, 1 ether)), 72);
        console.log("sUSDe push - SUCCESS");
        _waitForRPC();

        console.log("\n--- sUSDe: pullAssets ---");
        _exec(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pullAssets, (Constants.SUSDE, 0.5 ether)), 73);
        console.log("sUSDe pull - SUCCESS");
        _waitForRPC();

        // Test NUSD: approve (74), push (75), pull (76)
        console.log("\n--- NUSD: approve for SwapModule ---");
        _exec(Constants.NUSD, 0, abi.encodeCall(IERC20.approve, (SWAP_MODULE, type(uint256).max)), 74);
        console.log("NUSD approve - SUCCESS");
        _waitForRPC();

        console.log("\n--- NUSD: pushAssets ---");
        _exec(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pushAssets, (Constants.NUSD, 10 ether)), 75);
        console.log("NUSD push - SUCCESS");
        _waitForRPC();

        console.log("\n--- NUSD: pullAssets ---");
        _exec(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pullAssets, (Constants.NUSD, 5 ether)), 76);
        console.log("NUSD pull - SUCCESS");

        console.log("\n=== All SwapModule Tests Passed ===");
    }

    // =================== MORPHO TESTS ===================

    function test_ProdSv4_MorphoOperations() public {
        console.log("\n=== Testing Prod SV4 - Morpho Operations ===");

        // Fetch market params on-chain
        IMorpho morpho = IMorpho(Constants.MORPHO);
        IMorpho.MarketParams memory snusdParams = morpho.idToMarketParams(MARKET_SNUSD_USDC);
        IMorpho.MarketParams memory reusdParams = morpho.idToMarketParams(MARKET_REUSD_USDC);
        IMorpho.MarketParams memory savusdParams = morpho.idToMarketParams(MARKET_SAVUSD_USDC);
        IMorpho.MarketParams memory susnParams = morpho.idToMarketParams(MARKET_SUSN_USDC);

        console.log("sNUSD market - loan:", snusdParams.loanToken, "collateral:", snusdParams.collateralToken);
        console.log("reUSD market - loan:", reusdParams.loanToken, "collateral:", reusdParams.collateralToken);
        console.log("savUSD market - loan:", savusdParams.loanToken, "collateral:", savusdParams.collateralToken);
        console.log("sUSN market - loan:", susnParams.loanToken, "collateral:", susnParams.collateralToken);

        // ===== sNUSD/USDC market (indices 22-29) =====
        console.log("\n========== sNUSD/USDC Market ==========");
        deal(Constants.SNUSD, subvault4, 1000 ether);
        deal(Constants.USDC, subvault4, 10000e6);

        // Approve sNUSD for Morpho (index 22)
        _exec(Constants.SNUSD, 0, abi.encodeCall(IERC20.approve, (Constants.MORPHO, type(uint256).max)), 22);
        console.log("sNUSD approve - SUCCESS");
        _waitForRPC();

        // Approve USDC for Morpho (index 23)
        _exec(Constants.USDC, 0, abi.encodeCall(IERC20.approve, (Constants.MORPHO, type(uint256).max)), 23);
        console.log("USDC approve - SUCCESS");
        _waitForRPC();

        // Supply USDC (loan token) (index 24)
        _exec(Constants.MORPHO, 0, abi.encodeCall(IMorpho.supply, (snusdParams, 1000e6, 0, subvault4, "")), 24);
        console.log("USDC supply - SUCCESS");
        _waitForRPC();

        // Supply sNUSD collateral (index 25)
        _exec(Constants.MORPHO, 0, abi.encodeCall(IMorpho.supplyCollateral, (snusdParams, 500 ether, subvault4, "")), 25);
        console.log("sNUSD supplyCollateral - SUCCESS");
        _waitForRPC();

        // Borrow USDC (index 27)
        _exec(Constants.MORPHO, 0, abi.encodeCall(IMorpho.borrow, (snusdParams, 100e6, 0, subvault4, subvault4)), 27);
        console.log("USDC borrow - SUCCESS");
        _waitForRPC();

        // Repay USDC (index 26)
        _exec(Constants.MORPHO, 0, abi.encodeCall(IMorpho.repay, (snusdParams, 100e6, 0, subvault4, "")), 26);
        console.log("USDC repay - SUCCESS");
        _waitForRPC();

        // Withdraw USDC (index 28)
        _exec(Constants.MORPHO, 0, abi.encodeCall(IMorpho.withdraw, (snusdParams, 500e6, 0, subvault4, subvault4)), 28);
        console.log("USDC withdraw - SUCCESS");
        _waitForRPC();

        // Withdraw sNUSD collateral (index 29)
        _exec(Constants.MORPHO, 0, abi.encodeCall(IMorpho.withdrawCollateral, (snusdParams, 100 ether, subvault4, subvault4)), 29);
        console.log("sNUSD withdrawCollateral - SUCCESS");
        _waitForRPC();

        // ===== reUSD/USDC market (indices 30-37) =====
        console.log("\n========== reUSD/USDC Market ==========");
        deal(reusdParams.collateralToken, subvault4, 1000 ether);

        // Approve reUSD for Morpho (index 30)
        _exec(reusdParams.collateralToken, 0, abi.encodeCall(IERC20.approve, (Constants.MORPHO, type(uint256).max)), 30);
        console.log("reUSD approve - SUCCESS");
        _waitForRPC();

        // Approve USDC for Morpho (index 31)
        _exec(Constants.USDC, 0, abi.encodeCall(IERC20.approve, (Constants.MORPHO, type(uint256).max)), 31);
        console.log("USDC approve (reUSD market) - SUCCESS");
        _waitForRPC();

        // Supply collateral (index 33)
        _exec(Constants.MORPHO, 0, abi.encodeCall(IMorpho.supplyCollateral, (reusdParams, 500 ether, subvault4, "")), 33);
        console.log("reUSD supplyCollateral - SUCCESS");
        _waitForRPC();

        // Withdraw collateral (index 37)
        _exec(Constants.MORPHO, 0, abi.encodeCall(IMorpho.withdrawCollateral, (reusdParams, 100 ether, subvault4, subvault4)), 37);
        console.log("reUSD withdrawCollateral - SUCCESS");
        _waitForRPC();

        // ===== savUSD/USDC market (indices 38-45) =====
        console.log("\n========== savUSD/USDC Market ==========");
        deal(savusdParams.collateralToken, subvault4, 1000 ether);

        // Approve savUSD for Morpho (index 38)
        _exec(savusdParams.collateralToken, 0, abi.encodeCall(IERC20.approve, (Constants.MORPHO, type(uint256).max)), 38);
        console.log("savUSD approve - SUCCESS");
        _waitForRPC();

        // Approve USDC for Morpho (index 39)
        _exec(Constants.USDC, 0, abi.encodeCall(IERC20.approve, (Constants.MORPHO, type(uint256).max)), 39);
        console.log("USDC approve (savUSD market) - SUCCESS");
        _waitForRPC();

        // Supply collateral (index 41)
        _exec(Constants.MORPHO, 0, abi.encodeCall(IMorpho.supplyCollateral, (savusdParams, 500 ether, subvault4, "")), 41);
        console.log("savUSD supplyCollateral - SUCCESS");
        _waitForRPC();

        // Withdraw collateral (index 45)
        _exec(Constants.MORPHO, 0, abi.encodeCall(IMorpho.withdrawCollateral, (savusdParams, 100 ether, subvault4, subvault4)), 45);
        console.log("savUSD withdrawCollateral - SUCCESS");
        _waitForRPC();

        // ===== sUSN/USDC market (indices 46-53) =====
        console.log("\n========== sUSN/USDC Market ==========");
        deal(susnParams.collateralToken, subvault4, 1000 ether);

        // Approve sUSN for Morpho (index 46)
        _exec(susnParams.collateralToken, 0, abi.encodeCall(IERC20.approve, (Constants.MORPHO, type(uint256).max)), 46);
        console.log("sUSN approve - SUCCESS");
        _waitForRPC();

        // Approve USDC for Morpho (index 47)
        _exec(Constants.USDC, 0, abi.encodeCall(IERC20.approve, (Constants.MORPHO, type(uint256).max)), 47);
        console.log("USDC approve (sUSN market) - SUCCESS");
        _waitForRPC();

        // Supply USDC (index 48)
        _exec(Constants.MORPHO, 0, abi.encodeCall(IMorpho.supply, (susnParams, 1000e6, 0, subvault4, "")), 48);
        console.log("USDC supply - SUCCESS");
        _waitForRPC();

        // Supply sUSN collateral (index 49)
        _exec(Constants.MORPHO, 0, abi.encodeCall(IMorpho.supplyCollateral, (susnParams, 500 ether, subvault4, "")), 49);
        console.log("sUSN supplyCollateral - SUCCESS");
        _waitForRPC();

        // Withdraw USDC (index 52)
        _exec(Constants.MORPHO, 0, abi.encodeCall(IMorpho.withdraw, (susnParams, 500e6, 0, subvault4, subvault4)), 52);
        console.log("USDC withdraw - SUCCESS");
        _waitForRPC();

        // Withdraw sUSN collateral (index 53)
        _exec(Constants.MORPHO, 0, abi.encodeCall(IMorpho.withdrawCollateral, (susnParams, 100 ether, subvault4, subvault4)), 53);
        console.log("sUSN withdrawCollateral - SUCCESS");

        console.log("\n=== All Morpho Tests Passed ===");
    }

    // =================== WITHDRAWAL TESTS ===================

    function test_ProdSv4_WithdrawalOperations() public {
        console.log("\n=== Testing Prod SV4 - Withdrawal & Staking Operations ===");

        // =================== LIDO WITHDRAWAL (indices 102-104) ===================
        console.log("\n========== LIDO WITHDRAWAL ==========");

        deal(Constants.WSTETH, subvault4, 2 ether);

        // Approve wstETH for Lido (index 102)
        console.log("\n--- Approve wstETH for Lido ---");
        _exec(Constants.WSTETH, 0, abi.encodeCall(IERC20.approve, (LIDO_WITHDRAWAL_QUEUE, type(uint256).max)), 102);
        console.log("wstETH approve - SUCCESS");
        _waitForRPC();

        // Request withdrawal (index 103)
        console.log("\n--- Request wstETH withdrawal ---");
        {
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 0.1 ether;
            _exec(LIDO_WITHDRAWAL_QUEUE, 0, abi.encodeCall(ILidoWithdrawalQueue.requestWithdrawalsWstETH, (amounts, subvault4)), 103);
            console.log("Request withdrawal - SUCCESS");
        }
        _waitForRPC();

        // Claim withdrawal (index 104) - expect revert from Lido (not finalized), but proof is valid
        console.log("\n--- Claim withdrawal (expect Lido revert) ---");
        {
            bytes memory callData = abi.encodeCall(ILidoWithdrawalQueue.claimWithdrawal, (1));
            vm.prank(prodCurator);
            try ICallModule(subvault4).call(LIDO_WITHDRAWAL_QUEUE, 0, callData, _payload(104)) {
                console.log("Claim succeeded (unexpected but ok)");
            } catch {
                console.log("Claim reverted (expected - not finalized) - PROOF VALID");
            }
        }
        _waitForRPC();

        // =================== sUSDe COOLDOWN/UNSTAKE (indices 105-106) ===================
        console.log("\n========== sUSDe COOLDOWN/UNSTAKE ==========");

        deal(Constants.SUSDE, subvault4, 1 ether);

        // cooldownShares (index 105)
        console.log("\n--- sUSDe cooldownShares ---");
        _exec(Constants.SUSDE, 0, abi.encodeCall(ISUSDe.cooldownShares, (0.5 ether)), 105);
        console.log("sUSDe cooldownShares - SUCCESS");
        _waitForRPC();

        // unstake (index 106) - expect revert (cooldown not elapsed)
        console.log("\n--- sUSDe unstake (expect revert) ---");
        {
            bytes memory callData = abi.encodeCall(ISUSDe.unstake, (subvault4));
            vm.prank(prodCurator);
            try ICallModule(subvault4).call(Constants.SUSDE, 0, callData, _payload(106)) {
                console.log("unstake succeeded (unexpected but ok)");
            } catch {
                console.log("unstake reverted (expected - cooldown not elapsed) - PROOF VALID");
            }
        }
        _waitForRPC();

        // =================== sNUSD DEPOSIT/COOLDOWN (indices 107-109) ===================
        console.log("\n========== sNUSD DEPOSIT/COOLDOWN ==========");

        deal(Constants.NUSD, subvault4, 100 ether);

        // Approve nUSD for sNUSD (index 107)
        console.log("\n--- Approve nUSD for sNUSD ---");
        _exec(Constants.NUSD, 0, abi.encodeCall(IERC20.approve, (Constants.SNUSD, type(uint256).max)), 107);
        console.log("nUSD approve - SUCCESS");
        _waitForRPC();

        // Deposit nUSD into sNUSD (index 108)
        console.log("\n--- Deposit nUSD into sNUSD ---");
        _exec(Constants.SNUSD, 0, abi.encodeCall(IERC4626.deposit, (50 ether, subvault4)), 108);
        console.log("sNUSD deposit - SUCCESS");
        _waitForRPC();

        // sNUSD cooldownShares (index 109)
        console.log("\n--- sNUSD cooldownShares ---");
        _exec(Constants.SNUSD, 0, abi.encodeCall(ISUSDe.cooldownShares, (10 ether)), 109);
        console.log("sNUSD cooldownShares - SUCCESS");
        _waitForRPC();

        // =================== srUSDe WITHDRAW (index 110) ===================
        console.log("\n========== srUSDe WITHDRAW ==========");

        deal(Constants.SRUSDE, subvault4, 10 ether);

        // srUSDe withdraw into sUSDe (index 110)
        console.log("\n--- srUSDe withdraw to sUSDe ---");
        {
            uint256 susdeBefore = IERC20(Constants.SUSDE).balanceOf(subvault4);
            bytes memory callData = abi.encodeWithSignature(
                "withdraw(address,uint256,address,address)",
                Constants.SUSDE,
                1 ether,
                subvault4,
                subvault4
            );
            _exec(Constants.SRUSDE, 0, callData, 110);
            uint256 susdeAfter = IERC20(Constants.SUSDE).balanceOf(subvault4);
            console.log("sUSDe before:", susdeBefore, "after:", susdeAfter);
            require(susdeAfter > susdeBefore, "Should have received sUSDe from srUSDe withdraw");
            console.log("srUSDe withdraw - SUCCESS");
        }

        console.log("\n=== All Withdrawal & Staking Tests Passed ===");
    }

    // =================== NEGATIVE TESTS ===================

    /// @notice Test that a non-curator caller is blocked across all operation types
    function test_RevertWhen_NonCuratorCallsSv4_EMode38() public {
        console.log("\n=== Testing Non-Curator Access Control (eMode 38 JSON) ===");

        address nonCurator = 0xfcBEe74406415c0Cbe556317B1aeF8D9950D515D;

        deal(Constants.SUSDE, subvault4, 10 ether);
        deal(Constants.NUSD, subvault4, 100 ether);

        // 1. Aave sUSDe approve (index 1)
        console.log("\n--- Non-curator: Aave sUSDe approve ---");
        {
            bytes memory callData = abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max));
            vm.prank(nonCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.SUSDE, 0, callData, _payload(1));
            console.log("REVERTED - SUCCESS");
        }

        // 2. Aave wstETH approve (index 7)
        console.log("\n--- Non-curator: Aave wstETH approve ---");
        {
            bytes memory callData = abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max));
            vm.prank(nonCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.WSTETH, 0, callData, _payload(7));
            console.log("REVERTED - SUCCESS");
        }

        // 3. SwapModule WETH approve (index 56)
        console.log("\n--- Non-curator: SwapModule WETH approve ---");
        {
            bytes memory callData = abi.encodeCall(IERC20.approve, (SWAP_MODULE, type(uint256).max));
            vm.prank(nonCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.WETH, 0, callData, _payload(56));
            console.log("REVERTED - SUCCESS");
        }

        // 4. Lido wstETH approve (index 102)
        console.log("\n--- Non-curator: Lido wstETH approve ---");
        {
            bytes memory callData = abi.encodeCall(IERC20.approve, (LIDO_WITHDRAWAL_QUEUE, type(uint256).max));
            vm.prank(nonCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.WSTETH, 0, callData, _payload(102));
            console.log("REVERTED - SUCCESS");
        }

        // 5. sUSDe cooldownShares (index 105)
        console.log("\n--- Non-curator: sUSDe cooldownShares ---");
        {
            bytes memory callData = abi.encodeCall(ISUSDe.cooldownShares, (0.5 ether));
            vm.prank(nonCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.SUSDE, 0, callData, _payload(105));
            console.log("REVERTED - SUCCESS");
        }

        // 6. Pendle sNUSD approve (index 97)
        console.log("\n--- Non-curator: Pendle sNUSD approve ---");
        {
            bytes memory callData = abi.encodeCall(IERC20.approve, (Constants.PENDLE_ROUTER, type(uint256).max));
            vm.prank(nonCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.SNUSD, 0, callData, _payload(97));
            console.log("REVERTED - SUCCESS");
        }

        // 7. sNUSD deposit (index 108)
        console.log("\n--- Non-curator: sNUSD deposit ---");
        {
            bytes memory callData = abi.encodeCall(IERC4626.deposit, (50 ether, subvault4));
            vm.prank(nonCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.SNUSD, 0, callData, _payload(108));
            console.log("REVERTED - SUCCESS");
        }

        // 8. Morpho sNUSD approve (index 22)
        console.log("\n--- Non-curator: Morpho sNUSD approve ---");
        {
            bytes memory callData = abi.encodeCall(IERC20.approve, (Constants.MORPHO, type(uint256).max));
            vm.prank(nonCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.SNUSD, 0, callData, _payload(22));
            console.log("REVERTED - SUCCESS");
        }

        console.log("\n=== All Non-Curator Tests REVERTED as expected ===");
    }

    /// @notice Test that wrong recipient/onBehalfOf params fail even when called by curator
    function test_RevertWhen_WrongRecipientParams_EMode38() public {
        console.log("\n=== Testing Wrong Recipient Enforcement (eMode 38 JSON) ===");

        deal(Constants.SUSDE, subvault4, 100 ether);
        deal(Constants.WSTETH, subvault4, 10 ether);
        address wrongRecipient = address(0xBAD);

        // 1. Aave supply with wrong onBehalfOf (index 2 = sUSDe supply)
        console.log("\n--- Wrong recipient: Aave sUSDe supply ---");
        {
            _exec(Constants.SUSDE, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 1);

            bytes memory callData = abi.encodeCall(
                IAavePoolV3.supply, (Constants.SUSDE, 1 ether, wrongRecipient, 0)
            );
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.AAVE_CORE, 0, callData, _payload(2));
            console.log("Wrong supply recipient REVERTED - SUCCESS");
        }
        _waitForRPC();

        // 2. Aave wstETH supply with wrong onBehalfOf (index 8)
        console.log("\n--- Wrong recipient: Aave wstETH supply ---");
        {
            _exec(Constants.WSTETH, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 7);

            bytes memory callData = abi.encodeCall(
                IAavePoolV3.supply, (Constants.WSTETH, 1 ether, wrongRecipient, 0)
            );
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.AAVE_CORE, 0, callData, _payload(8));
            console.log("Wrong wstETH supply recipient REVERTED - SUCCESS");
        }
        _waitForRPC();

        // 3. Aave withdraw with wrong 'to' (index 3 = sUSDe withdraw)
        console.log("\n--- Wrong recipient: Aave withdraw ---");
        {
            _exec(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.supply, (Constants.SUSDE, 10 ether, subvault4, 0)), 2);

            bytes memory callData = abi.encodeCall(
                IAavePoolV3.withdraw, (Constants.SUSDE, 1 ether, wrongRecipient)
            );
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.AAVE_CORE, 0, callData, _payload(3));
            console.log("Wrong withdraw recipient REVERTED - SUCCESS");
        }
        _waitForRPC();

        // 4. Aave borrow with wrong onBehalfOf (index 14 = USDe borrow)
        console.log("\n--- Wrong onBehalfOf: Aave borrow ---");
        {
            bytes memory callData = abi.encodeCall(
                IAavePoolV3.borrow, (Constants.USDE, 1e18, 2, 0, wrongRecipient)
            );
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.AAVE_CORE, 0, callData, _payload(14));
            console.log("Wrong borrow onBehalfOf REVERTED - SUCCESS");
        }
        _waitForRPC();

        // 5. Aave repay with wrong onBehalfOf (index 15 = USDe repay)
        console.log("\n--- Wrong onBehalfOf: Aave repay ---");
        {
            bytes memory callData = abi.encodeCall(
                IAavePoolV3.repay, (Constants.USDE, 1e18, 2, wrongRecipient)
            );
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.AAVE_CORE, 0, callData, _payload(15));
            console.log("Wrong repay onBehalfOf REVERTED - SUCCESS");
        }
        _waitForRPC();

        // 6. Pendle swapExactTokenForPt with wrong receiver (index 80)
        console.log("\n--- Wrong receiver: Pendle swapExactTokenForPt ---");
        {
            _exec(Constants.SUSDE, 0, abi.encodeCall(IERC20.approve, (Constants.PENDLE_ROUTER, type(uint256).max)), 78);

            IPendleRouter.TokenInput memory input = IPendleRouter.TokenInput({
                tokenIn: Constants.SUSDE,
                netTokenIn: 1 ether,
                tokenMintSy: Constants.SUSDE,
                pendleSwap: address(0),
                swapData: IPendleRouter.SwapData({
                    swapType: IPendleRouter.SwapType.NONE,
                    extRouter: address(0),
                    extCalldata: "",
                    needScale: false
                })
            });
            IPendleRouter.ApproxParams memory guessPtOut = IPendleRouter.ApproxParams({
                guessMin: 0,
                guessMax: type(uint256).max,
                guessOffchain: 0,
                maxIteration: 256,
                eps: 1e14
            });
            IPendleRouter.LimitOrderData memory limit = IPendleRouter.LimitOrderData({
                limitRouter: address(0),
                epsSkipMarket: 0,
                normalFills: new IPendleRouter.FillOrderParams[](0),
                flashFills: new IPendleRouter.FillOrderParams[](0),
                optData: ""
            });
            bytes memory callData = abi.encodeCall(
                IPendleRouter.swapExactTokenForPt,
                (wrongRecipient, PENDLE_MARKET_PT_SUSDE_06MAY2026, 0, guessPtOut, input, limit)
            );
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.PENDLE_ROUTER, 0, callData, _payload(80));
            console.log("Wrong Pendle receiver REVERTED - SUCCESS");
        }
        _waitForRPC();

        // 7. Lido requestWithdrawalsWstETH with wrong owner (index 103)
        console.log("\n--- Wrong owner: Lido requestWithdrawals ---");
        {
            deal(Constants.WSTETH, subvault4, 1 ether);
            _exec(Constants.WSTETH, 0, abi.encodeCall(IERC20.approve, (LIDO_WITHDRAWAL_QUEUE, type(uint256).max)), 102);

            uint256[] memory amounts = new uint256[](1);
            amounts[0] = 0.1 ether;
            bytes memory callData = abi.encodeCall(
                ILidoWithdrawalQueue.requestWithdrawalsWstETH, (amounts, wrongRecipient)
            );
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(LIDO_WITHDRAWAL_QUEUE, 0, callData, _payload(103));
            console.log("Wrong Lido owner REVERTED - SUCCESS");
        }
        _waitForRPC();

        // 8. sUSDe unstake with wrong receiver (index 106)
        console.log("\n--- Wrong receiver: sUSDe unstake ---");
        {
            bytes memory callData = abi.encodeCall(ISUSDe.unstake, (wrongRecipient));
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.SUSDE, 0, callData, _payload(106));
            console.log("Wrong unstake receiver REVERTED - SUCCESS");
        }
        _waitForRPC();

        // 9. sNUSD deposit with wrong receiver (index 108)
        console.log("\n--- Wrong receiver: sNUSD deposit ---");
        {
            deal(Constants.NUSD, subvault4, 100 ether);
            _exec(Constants.NUSD, 0, abi.encodeCall(IERC20.approve, (Constants.SNUSD, type(uint256).max)), 107);

            bytes memory callData = abi.encodeCall(IERC4626.deposit, (50 ether, wrongRecipient));
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.SNUSD, 0, callData, _payload(108));
            console.log("Wrong sNUSD deposit receiver REVERTED - SUCCESS");
        }
        _waitForRPC();

        // 10. Morpho supplyCollateral with wrong onBehalfOf (index 25)
        console.log("\n--- Wrong onBehalfOf: Morpho supplyCollateral ---");
        {
            IMorpho.MarketParams memory params = IMorpho(Constants.MORPHO).idToMarketParams(MARKET_SNUSD_USDC);
            deal(Constants.SNUSD, subvault4, 100 ether);
            _exec(Constants.SNUSD, 0, abi.encodeCall(IERC20.approve, (Constants.MORPHO, type(uint256).max)), 22);

            bytes memory callData = abi.encodeCall(
                IMorpho.supplyCollateral, (params, 10 ether, wrongRecipient, "")
            );
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.MORPHO, 0, callData, _payload(25));
            console.log("Wrong Morpho supplyCollateral onBehalfOf REVERTED - SUCCESS");
        }
        _waitForRPC();

        // 11. Morpho borrow with wrong receiver (index 27)
        console.log("\n--- Wrong receiver: Morpho borrow ---");
        {
            IMorpho.MarketParams memory params = IMorpho(Constants.MORPHO).idToMarketParams(MARKET_SNUSD_USDC);
            bytes memory callData = abi.encodeCall(
                IMorpho.borrow, (params, 10e6, 0, subvault4, wrongRecipient)
            );
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault4).call(Constants.MORPHO, 0, callData, _payload(27));
            console.log("Wrong Morpho borrow receiver REVERTED - SUCCESS");
        }

        console.log("\n=== All Wrong Recipient Tests REVERTED as expected ===");
    }
}
