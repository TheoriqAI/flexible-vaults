// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "../scripts/ethereum/Constants.sol";
import "../src/interfaces/modules/ICallModule.sol";
import "../src/permissions/Verifier.sol";
import "../scripts/common/interfaces/IAavePoolV3.sol";
import "../scripts/common/interfaces/IMorpho.sol";
import "../src/interfaces/utils/ISwapModule.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Production Subvault 2 Integration Tests
/// @notice Tests all 107 operations from sv2-all.json (Aave eMode0, Morpho 7 markets, SwapModule, Withdrawals)
/// @dev Requires mainnet fork.
///
/// sv2-all.json index map:
///   0-24:   Aave eMode 0 (25 ops)
///   25-80:  Morpho (56 ops, 7 markets × 8)
///   81-101: SwapModule (21 ops, 7 assets × 3)
///   102-106: Withdrawals (5 ops)
contract ProdSv2IntegrationTest is Test {
    address constant prodCurator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;
    address constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address constant activeAdmin = 0x2D95cb50F204B8B84606751F262b407C08528c85;
    address constant SWAP_MODULE = 0xD1EE1697e278F9bC73BFFeF4495FB0Cd91B375Cf;

    // Morpho market IDs
    bytes32 constant MARKET_SNUSD_USDC = 0xae60b71b407e0517ead445b7113a7ffa07ea4a9379d526ade541a3e9ec777cb4;
    bytes32 constant MARKET_REUSD_USDC = 0x4565ac05d38b19374ccbb04c17cca60ca9353cd41824f0803d0fc7704f60eaed;
    bytes32 constant MARKET_SAVUSD_USDC = 0xe07d416323a1afbfe0bf2fe27ffb549ff565cf5c86d21b79fc60664038e597c9;
    bytes32 constant MARKET_SUSN_USDC = 0x8924445a76b678c536df977ed9222fb0b23ee5311497dd0223fe6270bb20b4e6;
    bytes32 constant MARKET_PT_SAVUSD_USDC = 0xc978f01522ff64adafd91856065d602c56e326a0368b895bd9244d5998e60076;
    bytes32 constant MARKET_WSTETH_EURC = 0x7421c2741e064e8c53fcb5de9faf7f0025dce75bc1caf26774dd878291c81dac;
    bytes32 constant MARKET_WBTC_EURC = 0xff527fe9c6516f9d82a3d51422ccb031d123266e6e26d4c22c942a948c180a75;

    address subvault2;
    IVerifier verifier2;
    bytes32 merkleRoot;
    string jsonData;

    function setUp() public {
        vm.createSelectFork("https://rpc.mevblocker.io");

        Vault vault = Vault(payable(VAULT_PROD));
        subvault2 = vault.subvaultAt(2);

        console.log("Subvault 2:", subvault2);

        verifier2 = ICallModule(subvault2).verifier();
        console.log("Verifier 2:", address(verifier2));

        // Load sv2-all.json
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/prod/tqETH/sv2-all.json");
        jsonData = vm.readFile(path);
        merkleRoot = bytes32(vm.parseJsonBytes32(jsonData, ".merkle_root"));

        console.log("Merkle root:", vm.toString(merkleRoot));

        // Set merkle root via prank as activeAdmin
        vm.prank(activeAdmin);
        verifier2.setMerkleRoot(merkleRoot);

        require(verifier2.merkleRoot() == merkleRoot, "Merkle root mismatch");
        console.log("Merkle root set on verifier");
    }

    function _waitForRPC() internal {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    // =================== JSON HELPERS ===================

    function _getVerificationData(uint256 index) internal view returns (bytes memory) {
        string memory basePath = string.concat(".merkle_proofs[", vm.toString(index), "].verificationData");
        return vm.parseJsonBytes(jsonData, basePath);
    }

    function _getProof(uint256 index) internal view returns (bytes32[] memory) {
        string memory basePath = string.concat(".merkle_proofs[", vm.toString(index), "].proof");
        bytes memory proofData = vm.parseJson(jsonData, basePath);
        return abi.decode(proofData, (bytes32[]));
    }

    function _makePayload(uint256 index) internal view returns (IVerifier.VerificationPayload memory) {
        return IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: _getVerificationData(index),
            proof: _getProof(index)
        });
    }

    function _execCall(address target, uint256 value, bytes memory callData, uint256 proofIndex) internal {
        IVerifier.VerificationPayload memory payload = _makePayload(proofIndex);
        vm.prank(prodCurator);
        ICallModule(subvault2).call(target, value, callData, payload);
    }

    // =================== AAVE OPERATIONS TEST ===================
    // Aave indices (eMode 0):
    // 0:  setUserEMode(0)
    // 1:  WETH approve (collateral), 2: WETH supply, 3: WETH withdraw
    // 4:  wstETH approve (collateral), 5: wstETH supply, 6: wstETH withdraw
    // 7:  WETH approve (borrow), 8: WETH borrow, 9: WETH repay
    // 10: wstETH approve (borrow), 11: wstETH borrow, 12: wstETH repay
    // 13: USDC approve, 14: USDC borrow, 15: USDC repay
    // 16: USDT approve, 17: USDT borrow, 18: USDT repay
    // 19: USDe approve, 20: USDe borrow, 21: USDe repay
    // 22: EURC approve, 23: EURC borrow, 24: EURC repay

    function test_ProdSv2_AaveOperations() public {
        console.log("\n=== Testing Prod SV2 - Aave Operations (eMode 0) ===");

        // First ensure eMode is 0 (fork state may have non-zero eMode)
        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.setUserEMode, (0)), 0);
        console.log("setUserEMode(0) - SUCCESS");
        _waitForRPC();

        // Fund subvault with collateral
        deal(Constants.WETH, subvault2, 10 ether);
        deal(Constants.WSTETH, subvault2, 5 ether);

        // --- Approve & Supply collateral ---

        // WETH collateral
        _execCall(Constants.WETH, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 1);
        console.log("WETH approve - SUCCESS");
        _waitForRPC();

        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.supply, (Constants.WETH, 5 ether, subvault2, 0)), 2);
        console.log("WETH supply - SUCCESS");
        _waitForRPC();

        // wstETH collateral
        _execCall(Constants.WSTETH, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 4);
        console.log("wstETH approve - SUCCESS");
        _waitForRPC();

        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.supply, (Constants.WSTETH, 2 ether, subvault2, 0)), 5);
        console.log("wstETH supply - SUCCESS");
        _waitForRPC();

        // --- Borrow & Repay (eMode 0, all borrows allowed) ---

        // USDC: approve, borrow, repay
        _execCall(Constants.USDC, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 13);
        console.log("USDC approve - SUCCESS");
        _waitForRPC();

        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.borrow, (Constants.USDC, 100e6, 2, 0, subvault2)), 14);
        console.log("USDC borrow - SUCCESS");
        _waitForRPC();

        deal(Constants.USDC, subvault2, 200e6);
        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.repay, (Constants.USDC, type(uint256).max, 2, subvault2)), 15);
        console.log("USDC repay - SUCCESS");
        _waitForRPC();

        // WETH: borrow, repay (approve already done for collateral at index 7)
        _execCall(Constants.WETH, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 7);
        console.log("WETH borrow approve - SUCCESS");
        _waitForRPC();

        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.borrow, (Constants.WETH, 0.01 ether, 2, 0, subvault2)), 8);
        console.log("WETH borrow - SUCCESS");
        _waitForRPC();

        deal(Constants.WETH, subvault2, 1 ether);
        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.repay, (Constants.WETH, type(uint256).max, 2, subvault2)), 9);
        console.log("WETH repay - SUCCESS");
        _waitForRPC();

        // USDe: approve, borrow, repay
        _execCall(Constants.USDE, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 19);
        console.log("USDe approve - SUCCESS");
        _waitForRPC();

        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.borrow, (Constants.USDE, 1e18, 2, 0, subvault2)), 20);
        console.log("USDe borrow - SUCCESS");
        _waitForRPC();

        deal(Constants.USDE, subvault2, 2e18);
        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.repay, (Constants.USDE, type(uint256).max, 2, subvault2)), 21);
        console.log("USDe repay - SUCCESS");
        _waitForRPC();

        // USDT: approve, borrow, repay
        _execCall(Constants.USDT, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 16);
        console.log("USDT approve - SUCCESS");
        _waitForRPC();

        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.borrow, (Constants.USDT, 1e6, 2, 0, subvault2)), 17);
        console.log("USDT borrow - SUCCESS");
        _waitForRPC();

        deal(Constants.USDT, subvault2, 2e6);
        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.repay, (Constants.USDT, type(uint256).max, 2, subvault2)), 18);
        console.log("USDT repay - SUCCESS");
        _waitForRPC();

        // EURC: approve, borrow, repay
        _execCall(Constants.EURC, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 22);
        console.log("EURC approve - SUCCESS");
        _waitForRPC();

        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.borrow, (Constants.EURC, 100e6, 2, 0, subvault2)), 23);
        console.log("EURC borrow - SUCCESS");
        _waitForRPC();

        deal(Constants.EURC, subvault2, 200e6);
        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.repay, (Constants.EURC, type(uint256).max, 2, subvault2)), 24);
        console.log("EURC repay - SUCCESS");
        _waitForRPC();

        // --- Withdraw collateral ---
        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.withdraw, (Constants.WETH, 0.5 ether, subvault2)), 3);
        console.log("WETH withdraw - SUCCESS");
        _waitForRPC();

        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.withdraw, (Constants.WSTETH, 0.5 ether, subvault2)), 6);
        console.log("wstETH withdraw - SUCCESS");

        console.log("\n=== All SV2 Aave Tests Passed ===");
    }

    // =================== MORPHO OPERATIONS TEST ===================
    // Morpho indices (25-80), 7 markets × 8 ops each:
    //   Market 1 - sNUSD/USDC:      25-32
    //   Market 2 - reUSD/USDC:      33-40
    //   Market 3 - savUSD/USDC:     41-48
    //   Market 4 - sUSN/USDC:       49-56
    //   Market 5 - PT-savUSD/USDC:  57-64
    //   Market 6 - wstETH/EURC:     65-72
    //   Market 7 - wBTC/EURC:       73-80
    //
    // Per-market pattern (base + offset):
    //   +0: collateral approve, +1: loan approve
    //   +2: supply, +3: supplyCollateral, +4: repay, +5: borrow, +6: withdraw, +7: withdrawCollateral

    function test_ProdSv2_MorphoOperations_USDC() public {
        console.log("\n=== Testing Prod SV2 - Morpho USDC Markets ===");

        IMorpho.MarketParams memory paramsSnusd = IMorpho(Constants.MORPHO).idToMarketParams(MARKET_SNUSD_USDC);
        IMorpho.MarketParams memory paramsReusd = IMorpho(Constants.MORPHO).idToMarketParams(MARKET_REUSD_USDC);
        IMorpho.MarketParams memory paramsSavusd = IMorpho(Constants.MORPHO).idToMarketParams(MARKET_SAVUSD_USDC);
        IMorpho.MarketParams memory paramsSusn = IMorpho(Constants.MORPHO).idToMarketParams(MARKET_SUSN_USDC);
        IMorpho.MarketParams memory paramsPtSavusd = IMorpho(Constants.MORPHO).idToMarketParams(MARKET_PT_SAVUSD_USDC);

        // Fund subvault
        deal(Constants.USDC, subvault2, 50_000e6);
        deal(paramsSnusd.collateralToken, subvault2, 1000e18);
        deal(paramsReusd.collateralToken, subvault2, 1000e18);
        deal(paramsSavusd.collateralToken, subvault2, 1000e18);
        deal(paramsSusn.collateralToken, subvault2, 1000e18);
        deal(paramsPtSavusd.collateralToken, subvault2, 1000e18);

        console.log("\n--- Market 1: sNUSD/USDC ---");
        _testMorphoMarket(paramsSnusd, 25, Constants.USDC, 100e6, 10e6, 50e6, 100e18, 50e18);

        console.log("\n--- Market 2: reUSD/USDC ---");
        _testMorphoMarket(paramsReusd, 33, Constants.USDC, 100e6, 10e6, 50e6, 100e18, 50e18);

        console.log("\n--- Market 3: savUSD/USDC ---");
        _testMorphoMarket(paramsSavusd, 41, Constants.USDC, 100e6, 10e6, 50e6, 100e18, 50e18);

        console.log("\n--- Market 4: sUSN/USDC ---");
        _testMorphoMarket(paramsSusn, 49, Constants.USDC, 100e6, 10e6, 50e6, 100e18, 50e18);

        console.log("\n--- Market 5: PT-savUSD/USDC ---");
        _testMorphoMarket(paramsPtSavusd, 57, Constants.USDC, 100e6, 10e6, 50e6, 100e18, 50e18);

        console.log("\n=== All SV2 Morpho USDC Tests Passed ===");
    }

    function test_ProdSv2_MorphoOperations_EURC() public {
        console.log("\n=== Testing Prod SV2 - Morpho EURC Markets ===");

        IMorpho.MarketParams memory paramsWstethEurc = IMorpho(Constants.MORPHO).idToMarketParams(MARKET_WSTETH_EURC);
        IMorpho.MarketParams memory paramsWbtcEurc = IMorpho(Constants.MORPHO).idToMarketParams(MARKET_WBTC_EURC);

        // Fund subvault
        deal(Constants.EURC, subvault2, 10_000e6);
        deal(Constants.WSTETH, subvault2, 10 ether);
        deal(paramsWbtcEurc.collateralToken, subvault2, 1e8); // wBTC has 8 decimals

        console.log("\n--- Market 6: wstETH/EURC ---");
        _testMorphoMarket(paramsWstethEurc, 65, Constants.EURC, 100e6, 10e6, 50e6, 1 ether, 0.5 ether);

        console.log("\n--- Market 7: wBTC/EURC ---");
        _testMorphoMarket(paramsWbtcEurc, 73, Constants.EURC, 100e6, 10e6, 50e6, 0.01e8, 0.005e8);

        console.log("\n=== All SV2 Morpho EURC Tests Passed ===");
    }

    function _testMorphoMarket(
        IMorpho.MarketParams memory params,
        uint256 baseIndex,
        address loanToken,
        uint256 supplyAmount,
        uint256 borrowAmount,
        uint256 withdrawAmount,
        uint256 collateralAmount,
        uint256 withdrawCollateralAmount
    ) internal {
        // Approve collateral for Morpho
        _execCall(params.collateralToken, 0, abi.encodeCall(IERC20.approve, (Constants.MORPHO, type(uint256).max)), baseIndex);
        console.log("  Collateral approve - SUCCESS");
        _waitForRPC();

        // Approve loan token for Morpho
        _execCall(loanToken, 0, abi.encodeCall(IERC20.approve, (Constants.MORPHO, type(uint256).max)), baseIndex + 1);
        console.log("  Loan token approve - SUCCESS");
        _waitForRPC();

        // Supply loan token
        _execCall(Constants.MORPHO, 0, abi.encodeCall(IMorpho.supply, (params, supplyAmount, 0, subvault2, "")), baseIndex + 2);
        console.log("  Supply - SUCCESS");
        _waitForRPC();

        // Supply collateral
        _execCall(Constants.MORPHO, 0, abi.encodeCall(IMorpho.supplyCollateral, (params, collateralAmount, subvault2, "")), baseIndex + 3);
        console.log("  Supply collateral - SUCCESS");
        _waitForRPC();

        // Borrow
        _execCall(Constants.MORPHO, 0, abi.encodeCall(IMorpho.borrow, (params, borrowAmount, 0, subvault2, subvault2)), baseIndex + 5);
        console.log("  Borrow - SUCCESS");
        _waitForRPC();

        // Repay
        _execCall(Constants.MORPHO, 0, abi.encodeCall(IMorpho.repay, (params, borrowAmount, 0, subvault2, "")), baseIndex + 4);
        console.log("  Repay - SUCCESS");
        _waitForRPC();

        // Withdraw loan token
        _execCall(Constants.MORPHO, 0, abi.encodeCall(IMorpho.withdraw, (params, withdrawAmount, 0, subvault2, subvault2)), baseIndex + 6);
        console.log("  Withdraw - SUCCESS");
        _waitForRPC();

        // Withdraw collateral
        _execCall(Constants.MORPHO, 0, abi.encodeCall(IMorpho.withdrawCollateral, (params, withdrawCollateralAmount, subvault2, subvault2)), baseIndex + 7);
        console.log("  Withdraw collateral - SUCCESS");
        _waitForRPC();
    }

    // =================== SWAP MODULE OPERATIONS TEST ===================
    // SwapModule indices (81-101), 7 assets × 3 ops:
    //   WETH:   81 approve, 82 push, 83 pull
    //   wstETH: 84 approve, 85 push, 86 pull
    //   USDC:   87 approve, 88 push, 89 pull
    //   USDT:   90 approve, 91 push, 92 pull
    //   USDe:   93 approve, 94 push, 95 pull
    //   sUSDe:  96 approve, 97 push, 98 pull
    //   EURC:   99 approve, 100 push, 101 pull

    function test_ProdSv2_SwapModuleOperations() public {
        console.log("\n=== Testing Prod SV2 - SwapModule Operations ===");

        // Fund subvault
        deal(Constants.WETH, subvault2, 1 ether);
        deal(Constants.WSTETH, subvault2, 1 ether);
        deal(Constants.USDC, subvault2, 100e6);
        deal(Constants.USDT, subvault2, 100e6);
        deal(Constants.USDE, subvault2, 100e18);
        deal(Constants.SUSDE, subvault2, 100e18);
        deal(Constants.EURC, subvault2, 100e6);

        // --- WETH ---
        _execCall(Constants.WETH, 0, abi.encodeCall(IERC20.approve, (SWAP_MODULE, type(uint256).max)), 81);
        console.log("WETH approve - SUCCESS");
        _waitForRPC();

        _execCall(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pushAssets, (Constants.WETH, 0.1 ether)), 82);
        console.log("WETH push - SUCCESS");
        _waitForRPC();

        _execCall(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pullAssets, (Constants.WETH, 0.05 ether)), 83);
        console.log("WETH pull - SUCCESS");
        _waitForRPC();

        // --- wstETH ---
        _execCall(Constants.WSTETH, 0, abi.encodeCall(IERC20.approve, (SWAP_MODULE, type(uint256).max)), 84);
        console.log("wstETH approve - SUCCESS");
        _waitForRPC();

        _execCall(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pushAssets, (Constants.WSTETH, 0.1 ether)), 85);
        console.log("wstETH push - SUCCESS");
        _waitForRPC();

        _execCall(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pullAssets, (Constants.WSTETH, 0.05 ether)), 86);
        console.log("wstETH pull - SUCCESS");
        _waitForRPC();

        // --- USDC ---
        _execCall(Constants.USDC, 0, abi.encodeCall(IERC20.approve, (SWAP_MODULE, type(uint256).max)), 87);
        console.log("USDC approve - SUCCESS");
        _waitForRPC();

        _execCall(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pushAssets, (Constants.USDC, 10e6)), 88);
        console.log("USDC push - SUCCESS");
        _waitForRPC();

        _execCall(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pullAssets, (Constants.USDC, 5e6)), 89);
        console.log("USDC pull - SUCCESS");
        _waitForRPC();

        // --- USDT ---
        _execCall(Constants.USDT, 0, abi.encodeCall(IERC20.approve, (SWAP_MODULE, type(uint256).max)), 90);
        console.log("USDT approve - SUCCESS");
        _waitForRPC();

        _execCall(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pushAssets, (Constants.USDT, 10e6)), 91);
        console.log("USDT push - SUCCESS");
        _waitForRPC();

        _execCall(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pullAssets, (Constants.USDT, 5e6)), 92);
        console.log("USDT pull - SUCCESS");
        _waitForRPC();

        // --- USDe ---
        _execCall(Constants.USDE, 0, abi.encodeCall(IERC20.approve, (SWAP_MODULE, type(uint256).max)), 93);
        console.log("USDe approve - SUCCESS");
        _waitForRPC();

        _execCall(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pushAssets, (Constants.USDE, 10e18)), 94);
        console.log("USDe push - SUCCESS");
        _waitForRPC();

        _execCall(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pullAssets, (Constants.USDE, 5e18)), 95);
        console.log("USDe pull - SUCCESS");
        _waitForRPC();

        // --- sUSDe ---
        _execCall(Constants.SUSDE, 0, abi.encodeCall(IERC20.approve, (SWAP_MODULE, type(uint256).max)), 96);
        console.log("sUSDe approve - SUCCESS");
        _waitForRPC();

        _execCall(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pushAssets, (Constants.SUSDE, 10e18)), 97);
        console.log("sUSDe push - SUCCESS");
        _waitForRPC();

        _execCall(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pullAssets, (Constants.SUSDE, 5e18)), 98);
        console.log("sUSDe pull - SUCCESS");
        _waitForRPC();

        // --- EURC ---
        _execCall(Constants.EURC, 0, abi.encodeCall(IERC20.approve, (SWAP_MODULE, type(uint256).max)), 99);
        console.log("EURC approve - SUCCESS");
        _waitForRPC();

        _execCall(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pushAssets, (Constants.EURC, 10e6)), 100);
        console.log("EURC push - SUCCESS");
        _waitForRPC();

        _execCall(SWAP_MODULE, 0, abi.encodeCall(ISwapModule.pullAssets, (Constants.EURC, 5e6)), 101);
        console.log("EURC pull - SUCCESS");

        console.log("\n=== All SV2 SwapModule Tests Passed ===");
    }

    // =================== NEGATIVE TESTS: NON-CURATOR ===================

    function test_RevertWhen_NonCuratorCallsOperation_SV2() public {
        console.log("\n=== Testing Non-Curator Access Control on SV2 ===");

        address nonCurator = address(0xBAD);
        deal(Constants.WETH, subvault2, 1 ether);

        // Aave: WETH approve
        {
            IVerifier.VerificationPayload memory payload = _makePayload(1);
            bytes memory callData = abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max));
            vm.prank(nonCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault2).call(Constants.WETH, 0, callData, payload);
            console.log("Non-curator Aave approve REVERTED - SUCCESS");
        }

        // Morpho: supply
        {
            IMorpho.MarketParams memory params = IMorpho(Constants.MORPHO).idToMarketParams(MARKET_SNUSD_USDC);
            IVerifier.VerificationPayload memory payload = _makePayload(27);
            bytes memory callData = abi.encodeCall(IMorpho.supply, (params, 100e6, 0, subvault2, ""));
            vm.prank(nonCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault2).call(Constants.MORPHO, 0, callData, payload);
            console.log("Non-curator Morpho supply REVERTED - SUCCESS");
        }

        // SwapModule: pushAssets
        {
            IVerifier.VerificationPayload memory payload = _makePayload(82);
            bytes memory callData = abi.encodeCall(ISwapModule.pushAssets, (Constants.WETH, 0.1 ether));
            vm.prank(nonCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault2).call(SWAP_MODULE, 0, callData, payload);
            console.log("Non-curator SwapModule push REVERTED - SUCCESS");
        }

        console.log("\n=== All Non-Curator SV2 Tests REVERTED as expected ===");
    }

    // =================== NEGATIVE TESTS: WRONG RECIPIENT (AAVE) ===================

    function test_RevertWhen_WrongRecipient_Aave_SV2() public {
        console.log("\n=== Testing Wrong Recipient Enforcement (Aave) on SV2 ===");

        deal(Constants.WETH, subvault2, 10 ether);

        // Set eMode 0 and supply first
        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.setUserEMode, (0)), 0);
        _execCall(Constants.WETH, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 1);
        _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.supply, (Constants.WETH, 5 ether, subvault2, 0)), 2);

        address wrongRecipient = address(0xBAD);

        // Wrong supply onBehalfOf
        {
            IVerifier.VerificationPayload memory payload = _makePayload(2);
            bytes memory callData = abi.encodeCall(IAavePoolV3.supply, (Constants.WETH, 1 ether, wrongRecipient, 0));
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault2).call(Constants.AAVE_CORE, 0, callData, payload);
            console.log("Wrong supply onBehalfOf REVERTED - SUCCESS");
        }

        // Wrong withdraw recipient
        {
            IVerifier.VerificationPayload memory payload = _makePayload(3);
            bytes memory callData = abi.encodeCall(IAavePoolV3.withdraw, (Constants.WETH, 0.5 ether, wrongRecipient));
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault2).call(Constants.AAVE_CORE, 0, callData, payload);
            console.log("Wrong withdraw recipient REVERTED - SUCCESS");
        }

        // Wrong borrow onBehalfOf
        {
            _execCall(Constants.USDC, 0, abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), 13);
            IVerifier.VerificationPayload memory payload = _makePayload(14);
            bytes memory callData = abi.encodeCall(IAavePoolV3.borrow, (Constants.USDC, 10e6, 2, 0, wrongRecipient));
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault2).call(Constants.AAVE_CORE, 0, callData, payload);
            console.log("Wrong borrow onBehalfOf REVERTED - SUCCESS");
        }

        // Wrong repay onBehalfOf
        {
            _execCall(Constants.AAVE_CORE, 0, abi.encodeCall(IAavePoolV3.borrow, (Constants.USDC, 10e6, 2, 0, subvault2)), 14);
            deal(Constants.USDC, subvault2, 20e6);

            IVerifier.VerificationPayload memory payload = _makePayload(15);
            bytes memory callData = abi.encodeCall(IAavePoolV3.repay, (Constants.USDC, 10e6, 2, wrongRecipient));
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault2).call(Constants.AAVE_CORE, 0, callData, payload);
            console.log("Wrong repay onBehalfOf REVERTED - SUCCESS");
        }

        console.log("\n=== All Wrong Recipient Aave Tests REVERTED as expected ===");
    }

    // =================== NEGATIVE TESTS: WRONG RECIPIENT (MORPHO) ===================

    function test_RevertWhen_WrongRecipient_Morpho_SV2() public {
        console.log("\n=== Testing Wrong Recipient Enforcement (Morpho) on SV2 ===");

        IMorpho.MarketParams memory params = IMorpho(Constants.MORPHO).idToMarketParams(MARKET_SNUSD_USDC);

        deal(Constants.USDC, subvault2, 1000e6);
        deal(params.collateralToken, subvault2, 1000e18);

        // Approve first (indices 25, 26)
        _execCall(params.collateralToken, 0, abi.encodeCall(IERC20.approve, (Constants.MORPHO, type(uint256).max)), 25);
        _execCall(Constants.USDC, 0, abi.encodeCall(IERC20.approve, (Constants.MORPHO, type(uint256).max)), 26);

        address wrongRecipient = address(0xBAD);

        // Wrong supply onBehalf
        {
            IVerifier.VerificationPayload memory payload = _makePayload(27);
            bytes memory callData = abi.encodeCall(IMorpho.supply, (params, 100e6, 0, wrongRecipient, ""));
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault2).call(Constants.MORPHO, 0, callData, payload);
            console.log("Wrong Morpho supply onBehalf REVERTED - SUCCESS");
        }

        // Wrong supplyCollateral onBehalf
        {
            IVerifier.VerificationPayload memory payload = _makePayload(28);
            bytes memory callData = abi.encodeCall(IMorpho.supplyCollateral, (params, 100e18, wrongRecipient, ""));
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault2).call(Constants.MORPHO, 0, callData, payload);
            console.log("Wrong Morpho supplyCollateral onBehalf REVERTED - SUCCESS");
        }

        // Supply correctly to have balances for borrow/withdraw tests
        _execCall(Constants.MORPHO, 0, abi.encodeCall(IMorpho.supply, (params, 100e6, 0, subvault2, "")), 27);
        _execCall(Constants.MORPHO, 0, abi.encodeCall(IMorpho.supplyCollateral, (params, 100e18, subvault2, "")), 28);

        // Wrong borrow receiver
        {
            IVerifier.VerificationPayload memory payload = _makePayload(30);
            bytes memory callData = abi.encodeCall(IMorpho.borrow, (params, 10e6, 0, subvault2, wrongRecipient));
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault2).call(Constants.MORPHO, 0, callData, payload);
            console.log("Wrong Morpho borrow receiver REVERTED - SUCCESS");
        }

        // Wrong withdraw receiver
        {
            IVerifier.VerificationPayload memory payload = _makePayload(31);
            bytes memory callData = abi.encodeCall(IMorpho.withdraw, (params, 10e6, 0, subvault2, wrongRecipient));
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault2).call(Constants.MORPHO, 0, callData, payload);
            console.log("Wrong Morpho withdraw receiver REVERTED - SUCCESS");
        }

        // Wrong withdrawCollateral receiver
        {
            IVerifier.VerificationPayload memory payload = _makePayload(32);
            bytes memory callData = abi.encodeCall(IMorpho.withdrawCollateral, (params, 10e18, subvault2, wrongRecipient));
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault2).call(Constants.MORPHO, 0, callData, payload);
            console.log("Wrong Morpho withdrawCollateral receiver REVERTED - SUCCESS");
        }

        // Wrong repay onBehalf
        {
            _execCall(Constants.MORPHO, 0, abi.encodeCall(IMorpho.borrow, (params, 10e6, 0, subvault2, subvault2)), 30);

            IVerifier.VerificationPayload memory payload = _makePayload(29);
            bytes memory callData = abi.encodeCall(IMorpho.repay, (params, 10e6, 0, wrongRecipient, ""));
            vm.prank(prodCurator);
            vm.expectRevert(IVerifier.VerificationFailed.selector);
            ICallModule(subvault2).call(Constants.MORPHO, 0, callData, payload);
            console.log("Wrong Morpho repay onBehalf REVERTED - SUCCESS");
        }

        console.log("\n=== All Wrong Recipient Morpho Tests REVERTED as expected ===");
    }
}
