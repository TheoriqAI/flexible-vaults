// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";
import "../common/JsonLibrary.sol";
import "../common/ParameterLibrary.sol";
import "../common/interfaces/IPendleRouter.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/// @notice Generates Pendle LP ops (add/remove single-token + claim rewards) for a subvault.
/// @dev Parameterized: `_generate(subvaultIndex, isProd, markets, tokens, suffix)` — reuse for any subvault
///      by passing a different index + market/token list (thin wrappers below). `subvault` is always the
///      on-chain `subvaultAt(index)` lookup, never a literal.
///
///      FULL LOCKS (unlike the PT-swap library which masks with template values): every locked address
///      uses `type(uint160).max` in the mask, so receiver/market/tokenIn/tokenOut/tokenMintSy/tokenRedeemSy
///      AND the no-aggregator path (pendleSwap=0, extRouter=0, limitRouter=0) are truly pinned. This forces
///      the direct Pendle-router SY mint/redeem path (no external aggregator). swapType (an enum) can't be
///      0xff-masked, but with pendleSwap+extRouter locked to 0 an external route can't execute anyway.
///      For a non-SY input later, add a SEPARATE scoped leaf pinning pendleSwap+extRouter to whitelisted
///      routers and wildcarding only extCalldata.
///
///      Claim = redeemDueInterestAndRewardsV2(SYs=[], YTs=[], markets=[all LP markets], tokenOut=0, swaps=[]).
///      Fully pinned (fixed length, no wildcards) — rewards credit msg.sender (the subvault); markets with
///      no rewards return 0. Selector 0x0741a803.
///
/// Run: forge script scripts/ethereum/GeneratePendleLpJSON.s.sol --sig "generateProdSv4Lp()" \
///        --rpc-url http://localhost:8545 --via-ir --gas-limit 9000000000000000000
contract GeneratePendleLpJSON is Script, Test {
    using ParameterLibrary for ParameterLibrary.Parameter[];

    address public constant prodCurator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;
    address public constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;

    bytes4 constant REDEEM_REWARDS_SELECTOR = 0x0741a803; // redeemDueInterestAndRewardsV2(...)

    /// @notice LP ops for PROD subvault 4 — all 8 live PT markets.
    function generateProdSv4Lp() public {
        address[] memory markets = new address[](8);
        address[] memory tokens = new address[](8);
        markets[0] = Constants.PENDLE_MARKET_PT_USDG_23SEP2026;     tokens[0] = Constants.USDG;
        markets[1] = Constants.PENDLE_MARKET_PT_NOPAL_16SEP2026;    tokens[1] = Constants.NOPAL;
        markets[2] = Constants.PENDLE_MARKET_PT_REUSDE_09DEC2026;   tokens[2] = Constants.REUSDE;
        markets[3] = Constants.PENDLE_MARKET_PT_USD3_16DEC2026;     tokens[3] = Constants.USD3;
        markets[4] = Constants.PENDLE_MARKET_PT_SUSD3_16DEC2026;    tokens[4] = Constants.SUSD3;
        markets[5] = Constants.PENDLE_MARKET_PT_REUSD_10DEC2026;    tokens[5] = Constants.REUSD;
        markets[6] = Constants.PENDLE_MARKET_PT_SIERRA_01JUL2026;   tokens[6] = Constants.SIERRA;
        markets[7] = Constants.PENDLE_MARKET_PT_SIERRA_06AUG2026;   tokens[7] = Constants.SIERRA;
        _generate(4, true, markets, tokens, "prod/tqETH/sv4-pendleLp");
    }

    function _generate(
        uint256 subvaultIndex,
        bool, /* isProd */
        address[] memory markets,
        address[] memory tokens,
        string memory title
    ) internal {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(subvaultIndex);
        require(subvault != address(0), "subvault not found");
        address curator = prodCurator;
        address router = Constants.PENDLE_ROUTER;
        BitmaskVerifier bmv = Constants.protocolDeployment().bitmaskVerifier;

        uint256 n = markets.length;
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](4 * n + 1);
        string[] memory descriptions = new string[](4 * n + 1);
        uint256 idx = 0;

        for (uint256 i = 0; i < n; i++) {
            // a. approve(token -> router) for adding liquidity
            (leaves[idx], descriptions[idx]) = _approve(bmv, curator, tokens[i], router, "tokenIn");
            idx++;
            // b. addLiquiditySingleToken
            (leaves[idx], descriptions[idx]) = _addLiq(bmv, curator, router, subvault, markets[i], tokens[i]);
            idx++;
            // c. approve(market/LP -> router) for removing liquidity (the market IS the LP ERC20)
            (leaves[idx], descriptions[idx]) = _approve(bmv, curator, markets[i], router, "LP");
            idx++;
            // d. removeLiquiditySingleToken
            (leaves[idx], descriptions[idx]) = _removeLiq(bmv, curator, router, subvault, markets[i], tokens[i]);
            idx++;
        }

        // claim: redeemDueInterestAndRewardsV2 pinning all markets, empty SYs/YTs/swaps, tokenOut=0
        (leaves[idx], descriptions[idx]) = _claim(bmv, curator, router, markets);
        idx++;
        require(idx == 4 * n + 1, "leaf count mismatch");

        (bytes32 root, IVerifier.VerificationPayload[] memory withProofs) =
            ProofLibrary.generateMerkleProofs(leaves);
        ProofLibrary.storeProofs(title, root, withProofs, descriptions);

        console.log("=== Pendle LP JSON ===");
        console.log("subvault:", subvault);
        console.log("markets:", n);
        console.log("ops:", withProofs.length);
        console.log("merkle root:", vm.toString(root));
    }

    // ---- leaf builders (full 0xff locks via type(uint160).max masks) ----

    function _approve(BitmaskVerifier bmv, address curator, address token, address router, string memory tag)
        internal
        view
        returns (IVerifier.VerificationPayload memory leaf, string memory desc)
    {
        leaf = ProofLibrary.makeVerificationPayload(
            bmv,
            curator,
            token,
            0,
            abi.encodeCall(IERC20.approve, (router, 0)),
            ProofLibrary.makeBitmask(
                true, true, true, true, abi.encodeCall(IERC20.approve, (address(type(uint160).max), 0))
            )
        );
        ParameterLibrary.Parameter[] memory inner = new ParameterLibrary.Parameter[](0);
        inner = inner.add("to", Strings.toHexString(router)).addAny("amount");
        desc = JsonLibrary.toJsonLean(
            string.concat("IERC20(", tag, "=", Strings.toHexString(token), ").approve(PendleRouter, anyAmount)"),
            ParameterLibrary.build(Strings.toHexString(curator), Strings.toHexString(token), "0"),
            inner
        );
    }

    function _addLiq(
        BitmaskVerifier bmv,
        address curator,
        address router,
        address subvault,
        address market,
        address token
    ) internal view returns (IVerifier.VerificationPayload memory leaf, string memory desc) {
        IPendleRouter.ApproxParams memory ap; // all zero = wildcard
        IPendleRouter.SwapData memory swap =
            IPendleRouter.SwapData({swapType: IPendleRouter.SwapType.NONE, extRouter: address(0), extCalldata: "", needScale: false});
        IPendleRouter.TokenInput memory input = IPendleRouter.TokenInput({
            tokenIn: token,
            netTokenIn: 0,
            tokenMintSy: token,
            pendleSwap: address(0),
            swapData: swap
        });
        IPendleRouter.LimitOrderData memory limit = IPendleRouter.LimitOrderData({
            limitRouter: address(0),
            epsSkipMarket: 0,
            normalFills: new IPendleRouter.FillOrderParams[](0),
            flashFills: new IPendleRouter.FillOrderParams[](0),
            optData: ""
        });
        bytes memory data =
            abi.encodeCall(IPendleRouter.addLiquiditySingleToken, (subvault, market, 0, ap, input, limit));

        address max = address(type(uint160).max);
        IPendleRouter.SwapData memory swapMask =
            IPendleRouter.SwapData({swapType: IPendleRouter.SwapType.NONE, extRouter: max, extCalldata: "", needScale: false});
        IPendleRouter.TokenInput memory inputMask = IPendleRouter.TokenInput({
            tokenIn: max,
            netTokenIn: 0,
            tokenMintSy: max,
            pendleSwap: max,
            swapData: swapMask
        });
        IPendleRouter.LimitOrderData memory limitMask = IPendleRouter.LimitOrderData({
            limitRouter: max,
            epsSkipMarket: 0,
            normalFills: new IPendleRouter.FillOrderParams[](0),
            flashFills: new IPendleRouter.FillOrderParams[](0),
            optData: ""
        });
        bytes memory bitmask = ProofLibrary.makeBitmask(
            true,
            true,
            true,
            true,
            abi.encodeCall(IPendleRouter.addLiquiditySingleToken, (max, max, 0, ap, inputMask, limitMask))
        );
        leaf = ProofLibrary.makeVerificationPayload(bmv, curator, router, 0, data, bitmask);

        ParameterLibrary.Parameter[] memory inner = new ParameterLibrary.Parameter[](0);
        inner = inner.add("receiver", Strings.toHexString(subvault)).add("market", Strings.toHexString(market)).add(
            "tokenIn", Strings.toHexString(token)
        ).addAny("amounts");
        desc = JsonLibrary.toJsonLean(
            string.concat("PendleRouter.addLiquiditySingleToken(subvault, ", Strings.toHexString(market), ", anyAmt, [tokenIn=", Strings.toHexString(token), "], directMint)"),
            ParameterLibrary.build(Strings.toHexString(curator), Strings.toHexString(router), "0"),
            inner
        );
    }

    function _removeLiq(
        BitmaskVerifier bmv,
        address curator,
        address router,
        address subvault,
        address market,
        address token
    ) internal view returns (IVerifier.VerificationPayload memory leaf, string memory desc) {
        IPendleRouter.SwapData memory swap =
            IPendleRouter.SwapData({swapType: IPendleRouter.SwapType.NONE, extRouter: address(0), extCalldata: "", needScale: false});
        IPendleRouter.TokenOutput memory output = IPendleRouter.TokenOutput({
            tokenOut: token,
            minTokenOut: 0,
            tokenRedeemSy: token,
            pendleSwap: address(0),
            swapData: swap
        });
        IPendleRouter.LimitOrderData memory limit = IPendleRouter.LimitOrderData({
            limitRouter: address(0),
            epsSkipMarket: 0,
            normalFills: new IPendleRouter.FillOrderParams[](0),
            flashFills: new IPendleRouter.FillOrderParams[](0),
            optData: ""
        });
        bytes memory data =
            abi.encodeCall(IPendleRouter.removeLiquiditySingleToken, (subvault, market, 0, output, limit));

        address max = address(type(uint160).max);
        IPendleRouter.SwapData memory swapMask =
            IPendleRouter.SwapData({swapType: IPendleRouter.SwapType.NONE, extRouter: max, extCalldata: "", needScale: false});
        IPendleRouter.TokenOutput memory outputMask = IPendleRouter.TokenOutput({
            tokenOut: max,
            minTokenOut: 0,
            tokenRedeemSy: max,
            pendleSwap: max,
            swapData: swapMask
        });
        IPendleRouter.LimitOrderData memory limitMask = IPendleRouter.LimitOrderData({
            limitRouter: max,
            epsSkipMarket: 0,
            normalFills: new IPendleRouter.FillOrderParams[](0),
            flashFills: new IPendleRouter.FillOrderParams[](0),
            optData: ""
        });
        bytes memory bitmask = ProofLibrary.makeBitmask(
            true,
            true,
            true,
            true,
            abi.encodeCall(IPendleRouter.removeLiquiditySingleToken, (max, max, 0, outputMask, limitMask))
        );
        leaf = ProofLibrary.makeVerificationPayload(bmv, curator, router, 0, data, bitmask);

        ParameterLibrary.Parameter[] memory inner = new ParameterLibrary.Parameter[](0);
        inner = inner.add("receiver", Strings.toHexString(subvault)).add("market", Strings.toHexString(market)).add(
            "tokenOut", Strings.toHexString(token)
        ).addAny("amounts");
        desc = JsonLibrary.toJsonLean(
            string.concat("PendleRouter.removeLiquiditySingleToken(subvault, ", Strings.toHexString(market), ", anyLp, [tokenOut=", Strings.toHexString(token), "], directRedeem)"),
            ParameterLibrary.build(Strings.toHexString(curator), Strings.toHexString(router), "0"),
            inner
        );
    }

    function _claim(BitmaskVerifier bmv, address curator, address router, address[] memory markets)
        internal
        view
        returns (IVerifier.VerificationPayload memory leaf, string memory desc)
    {
        // redeemDueInterestAndRewardsV2(SYs=[], YTs=[], markets, tokenOut=0, swaps=[])
        // Empty SYs/YTs/swaps encode identically to empty address[] regardless of element type.
        bytes memory data = abi.encodePacked(
            REDEEM_REWARDS_SELECTOR,
            abi.encode(new address[](0), new address[](0), markets, address(0), new address[](0))
        );
        // Full pin: every byte locked (no wildcards) — deterministic redeem-only claim.
        bytes memory maskData = new bytes(data.length - 4); // makeBitmask handles the 4 selector bytes
        for (uint256 i = 0; i < maskData.length; i++) {
            maskData[i] = 0xff;
        }
        // makeBitmask expects callData incl. selector slot; prepend 4 bytes (forced to 0xff by selector=true)
        bytes memory maskCallData = bytes.concat(bytes4(0), maskData);
        bytes memory bitmask = ProofLibrary.makeBitmask(true, true, true, true, maskCallData);
        leaf = ProofLibrary.makeVerificationPayload(bmv, curator, router, 0, data, bitmask);

        ParameterLibrary.Parameter[] memory inner = new ParameterLibrary.Parameter[](0);
        inner = inner.add("SYs", "[]").add("YTs", "[]").addAny("markets").add("tokenOut", "0x0").add("swaps", "[]");
        desc = JsonLibrary.toJsonLean(
            "PendleRouter.redeemDueInterestAndRewardsV2([], [], allLpMarkets, 0x0, []) (rewards->subvault)",
            ParameterLibrary.build(Strings.toHexString(curator), Strings.toHexString(router), "0"),
            inner
        );
    }
}
