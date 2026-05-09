// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "@openzeppelin/contracts/utils/Strings.sol";

import {ABILibrary} from "../ABILibrary.sol";
import {JsonLibrary} from "../JsonLibrary.sol";
import "../ParameterLibrary.sol";
import "../ProofLibrary.sol";
import "../interfaces/IPendleRouter.sol";
import "../interfaces/Imports.sol";

/// @notice Library for generating Pendle PT operation proofs
/// @dev Generates Merkle tree leaves for Pendle Router operations with security restrictions
library PendleLibrary {
    using ParameterLibrary for ParameterLibrary.Parameter[];

    /// @notice Configuration for a single PT strategy
    struct PTStrategy {
        address ptToken;          // PT token address
        address market;           // Pendle market address
        address[] inputTokens;    // Array of allowed input tokens for entry (tokenIn=tokenMintSy)
        address[] outputTokens;   // Array of allowed output tokens for exit (tokenOut=tokenRedeemSy)
    }

    /// @notice Complete Pendle configuration
    struct Info {
        address subvault;
        string subvaultName;
        address curator;
        address pendleRouter;
        string pendleRouterName;
        PTStrategy[] strategies;
    }

    /// @notice Generate all Pendle operation proofs for the given configuration
    /// @param bitmaskVerifier The bitmask verifier contract address
    /// @param $ The Pendle configuration
    /// @return leaves Array of verification payloads for all operations
    function getPendleProofs(BitmaskVerifier bitmaskVerifier, Info memory $)
        internal
        pure
        returns (IVerifier.VerificationPayload[] memory leaves)
    {
        // Calculate total number of operations
        uint256 totalInputTokens = 0;
        uint256 totalOutputTokens = 0;
        for (uint256 i = 0; i < $.strategies.length; i++) {
            totalInputTokens += $.strategies[i].inputTokens.length;
            totalOutputTokens += $.strategies[i].outputTokens.length;
        }

        // Each strategy has:
        // - N approvals (one per input token)
        // - N swapExactTokenForPt (one per input token)
        // - 1 PT approval
        // - M swapExactPtForToken (one per output token)
        // - M exitPostExpToToken (one per output token)
        uint256 length = totalInputTokens * 2 + $.strategies.length + totalOutputTokens * 2;
        leaves = new IVerifier.VerificationPayload[](length);
        uint256 index = 0;

        for (uint256 i = 0; i < $.strategies.length; i++) {
            PTStrategy memory strategy = $.strategies[i];

            // 1. Generate approval proofs for each input token
            for (uint256 j = 0; j < strategy.inputTokens.length; j++) {
                leaves[index++] = _makeApprovalProof(
                    bitmaskVerifier,
                    $.curator,
                    strategy.inputTokens[j],
                    $.pendleRouter
                );
            }

            // 2. Generate swapExactTokenForPt proofs (one per input token, each using itself as mintSy)
            for (uint256 j = 0; j < strategy.inputTokens.length; j++) {
                leaves[index++] = _makeSwapTokenForPtProof(
                    bitmaskVerifier,
                    $.curator,
                    $.pendleRouter,
                    $.subvault,
                    strategy.market,
                    strategy.inputTokens[j]  // Use this specific token as both tokenIn and tokenMintSy
                );
            }

            // 3. Generate PT token approval proof (for selling PT back)
            leaves[index++] = _makeApprovalProof(
                bitmaskVerifier,
                $.curator,
                strategy.ptToken,
                $.pendleRouter
            );

            // 4. Generate swapExactPtForToken proofs (one per output token)
            for (uint256 j = 0; j < strategy.outputTokens.length; j++) {
                leaves[index++] = _makeSwapPtForTokenProof(
                    bitmaskVerifier,
                    $.curator,
                    $.pendleRouter,
                    $.subvault,
                    strategy.market,
                    strategy.outputTokens[j]  // Use this specific token as both tokenOut and tokenRedeemSy
                );
            }

            // 5. Generate exitPostExpToToken proofs (one per output token)
            for (uint256 j = 0; j < strategy.outputTokens.length; j++) {
                leaves[index++] = _makeExitPostExpProof(
                    bitmaskVerifier,
                    $.curator,
                    $.pendleRouter,
                    $.subvault,
                    strategy.market,
                    strategy.outputTokens[j]  // Use this specific token as both tokenOut and tokenRedeemSy
                );
            }
        }

        return leaves;
    }

    /// @notice Generate human-readable descriptions for all operations
    /// @param $ The Pendle configuration
    /// @return descriptions Array of descriptions matching the proofs
    function getPendleDescriptions(Info memory $)
        internal
        view
        returns (string[] memory descriptions)
    {
        uint256 totalInputTokens = 0;
        uint256 totalOutputTokens = 0;
        for (uint256 i = 0; i < $.strategies.length; i++) {
            totalInputTokens += $.strategies[i].inputTokens.length;
            totalOutputTokens += $.strategies[i].outputTokens.length;
        }

        // Count: (approvals + swaps for each input) + PT approval + (swaps + exits for each output)
        uint256 length = totalInputTokens * 2 + $.strategies.length + totalOutputTokens * 2;
        descriptions = new string[](length);
        uint256 index = 0;

        for (uint256 i = 0; i < $.strategies.length; i++) {
            PTStrategy memory strategy = $.strategies[i];

            // Approval descriptions for input tokens
            for (uint256 j = 0; j < strategy.inputTokens.length; j++) {
                string memory tokenSymbol = _tokenSymbol(strategy.inputTokens[j]);

                ParameterLibrary.Parameter[] memory innerParameters =
                    ParameterLibrary.build("to", Strings.toHexString($.pendleRouter)).addAny("amount");

                descriptions[index++] = JsonLibrary.toJson(
                    string(abi.encodePacked("IERC20(", tokenSymbol, ").approve(PendleRouter(", $.pendleRouterName, "), anyInt)")),
                    ABILibrary.getABI(IERC20.approve.selector),
                    ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(strategy.inputTokens[j]), "0"),
                    innerParameters
                );
            }

            // Swap token for PT - one description per input token
            for (uint256 j = 0; j < strategy.inputTokens.length; j++) {
                string memory tokenSymbol = _tokenSymbol(strategy.inputTokens[j]);

                ParameterLibrary.Parameter[] memory innerParameters =
                    ParameterLibrary.build("receiver", Strings.toHexString($.subvault))
                        .add("market", Strings.toHexString(strategy.market))
                        .addAny("minPtOut")
                        .addAny("guessPtOut")
                        .addAny("input")
                        .add("limit", "empty");

                descriptions[index++] = JsonLibrary.toJson(
                    string(
                        abi.encodePacked(
                            "PendleRouter(",
                            $.pendleRouterName,
                            ").swapExactTokenForPt(receiver=",
                            $.subvaultName,
                            ", market=",
                            Strings.toHexString(strategy.market),
                            ", tokenIn=",
                            tokenSymbol,
                            ", tokenMintSy=",
                            tokenSymbol,
                            ", minPtOut=any, NO_EXT_SWAP)"
                        )
                    ),
                    ABILibrary.getABI(IPendleRouter.swapExactTokenForPt.selector),
                    ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.pendleRouter), "0"),
                    innerParameters
                );
            }

            // PT token approval
            {
                string memory tokenSymbol = _tokenSymbol(strategy.ptToken);

                ParameterLibrary.Parameter[] memory innerParameters =
                    ParameterLibrary.build("to", Strings.toHexString($.pendleRouter)).addAny("amount");

                descriptions[index++] = JsonLibrary.toJson(
                    string(abi.encodePacked("IERC20(PT-", tokenSymbol, ").approve(PendleRouter(", $.pendleRouterName, "), anyInt)")),
                    ABILibrary.getABI(IERC20.approve.selector),
                    ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(strategy.ptToken), "0"),
                    innerParameters
                );
            }

            // Swap PT for token - one description per output token
            for (uint256 j = 0; j < strategy.outputTokens.length; j++) {
                string memory tokenSymbol = _tokenSymbol(strategy.outputTokens[j]);

                ParameterLibrary.Parameter[] memory innerParameters =
                    ParameterLibrary.build("receiver", Strings.toHexString($.subvault))
                        .add("market", Strings.toHexString(strategy.market))
                        .addAny("exactPtIn")
                        .addAny("output")
                        .add("limit", "empty");

                descriptions[index++] = JsonLibrary.toJson(
                    string(
                        abi.encodePacked(
                            "PendleRouter(",
                            $.pendleRouterName,
                            ").swapExactPtForToken(receiver=",
                            $.subvaultName,
                            ", market=",
                            Strings.toHexString(strategy.market),
                            ", tokenOut=",
                            tokenSymbol,
                            ", tokenRedeemSy=",
                            tokenSymbol,
                            ", exactPtIn=any, minTokenOut=any, NO_EXT_SWAP)"
                        )
                    ),
                    ABILibrary.getABI(IPendleRouter.swapExactPtForToken.selector),
                    ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.pendleRouter), "0"),
                    innerParameters
                );
            }

            // Exit post expiry - one description per output token
            for (uint256 j = 0; j < strategy.outputTokens.length; j++) {
                string memory tokenSymbol = _tokenSymbol(strategy.outputTokens[j]);

                ParameterLibrary.Parameter[] memory innerParameters =
                    ParameterLibrary.build("receiver", Strings.toHexString($.subvault))
                        .add("market", Strings.toHexString(strategy.market))
                        .addAny("netPtIn")
                        .addAny("minTokenOut")
                        .addAny("output");

                descriptions[index++] = JsonLibrary.toJson(
                    string(
                        abi.encodePacked(
                            "PendleRouter(",
                            $.pendleRouterName,
                            ").exitPostExpToToken(receiver=",
                            $.subvaultName,
                            ", market=",
                            Strings.toHexString(strategy.market),
                            ", tokenOut=",
                            tokenSymbol,
                            ", tokenRedeemSy=",
                            tokenSymbol,
                            ", netPtIn=any, minTokenOut=any, NO_SWAP)"
                        )
                    ),
                    ABILibrary.getABI(IPendleRouter.exitPostExpToToken.selector),
                    ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.pendleRouter), "0"),
                    innerParameters
                );
            }
        }

        return descriptions;
    }

    /// @notice Generate lean descriptions (without ABI) for all Pendle operations
    function getPendleDescriptionsLean(Info memory $)
        internal
        view
        returns (string[] memory descriptions)
    {
        // Calculate total number of operations
        uint256 totalInputTokens = 0;
        uint256 totalOutputTokens = 0;
        for (uint256 i = 0; i < $.strategies.length; i++) {
            totalInputTokens += $.strategies[i].inputTokens.length;
            totalOutputTokens += $.strategies[i].outputTokens.length;
        }

        // Count: (approvals + swaps for each input) + PT approval + (swaps + exits for each output)
        uint256 length = totalInputTokens * 2 + $.strategies.length + totalOutputTokens * 2;
        descriptions = new string[](length);
        uint256 index = 0;

        for (uint256 i = 0; i < $.strategies.length; i++) {
            PTStrategy memory strategy = $.strategies[i];

            // Approval descriptions for input tokens
            for (uint256 j = 0; j < strategy.inputTokens.length; j++) {
                string memory tokenSymbol = _tokenSymbol(strategy.inputTokens[j]);

                ParameterLibrary.Parameter[] memory innerParameters =
                    ParameterLibrary.build("to", Strings.toHexString($.pendleRouter)).addAny("amount");

                descriptions[index++] = JsonLibrary.toJsonLean(
                    string(abi.encodePacked("IERC20(", tokenSymbol, ").approve(PendleRouter(", $.pendleRouterName, "), anyInt)")),
                    ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(strategy.inputTokens[j]), "0"),
                    innerParameters
                );
            }

            // Swap token for PT - one description per input token
            for (uint256 j = 0; j < strategy.inputTokens.length; j++) {
                string memory tokenSymbol = _tokenSymbol(strategy.inputTokens[j]);

                ParameterLibrary.Parameter[] memory innerParameters =
                    ParameterLibrary.build("receiver", Strings.toHexString($.subvault))
                        .add("market", Strings.toHexString(strategy.market))
                        .addAny("minPtOut")
                        .addAny("guessPtOut")
                        .addAny("input")
                        .add("limit", "empty");

                descriptions[index++] = JsonLibrary.toJsonLean(
                    string(
                        abi.encodePacked(
                            "PendleRouter(",
                            $.pendleRouterName,
                            ").swapExactTokenForPt(receiver=",
                            $.subvaultName,
                            ", market=",
                            Strings.toHexString(strategy.market),
                            ", tokenIn=",
                            tokenSymbol,
                            ", tokenMintSy=",
                            tokenSymbol,
                            ", minPtOut=any, NO_EXT_SWAP)"
                        )
                    ),
                    ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.pendleRouter), "0"),
                    innerParameters
                );
            }

            // PT token approval
            {
                string memory tokenSymbol = _tokenSymbol(strategy.ptToken);

                ParameterLibrary.Parameter[] memory innerParameters =
                    ParameterLibrary.build("to", Strings.toHexString($.pendleRouter)).addAny("amount");

                descriptions[index++] = JsonLibrary.toJsonLean(
                    string(abi.encodePacked("IERC20(PT-", tokenSymbol, ").approve(PendleRouter(", $.pendleRouterName, "), anyInt)")),
                    ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(strategy.ptToken), "0"),
                    innerParameters
                );
            }

            // Swap PT for token - one description per output token
            for (uint256 j = 0; j < strategy.outputTokens.length; j++) {
                string memory tokenSymbol = _tokenSymbol(strategy.outputTokens[j]);

                ParameterLibrary.Parameter[] memory innerParameters =
                    ParameterLibrary.build("receiver", Strings.toHexString($.subvault))
                        .add("market", Strings.toHexString(strategy.market))
                        .addAny("exactPtIn")
                        .addAny("output")
                        .add("limit", "empty");

                descriptions[index++] = JsonLibrary.toJsonLean(
                    string(
                        abi.encodePacked(
                            "PendleRouter(",
                            $.pendleRouterName,
                            ").swapExactPtForToken(receiver=",
                            $.subvaultName,
                            ", market=",
                            Strings.toHexString(strategy.market),
                            ", tokenOut=",
                            tokenSymbol,
                            ", tokenRedeemSy=",
                            tokenSymbol,
                            ", exactPtIn=any, minTokenOut=any, NO_EXT_SWAP)"
                        )
                    ),
                    ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.pendleRouter), "0"),
                    innerParameters
                );
            }

            // Exit post-expiry - one description per output token
            for (uint256 j = 0; j < strategy.outputTokens.length; j++) {
                string memory tokenSymbol = _tokenSymbol(strategy.outputTokens[j]);

                ParameterLibrary.Parameter[] memory innerParameters =
                    ParameterLibrary.build("receiver", Strings.toHexString($.subvault))
                        .add("market", Strings.toHexString(strategy.market))
                        .addAny("netPtIn")
                        .addAny("minTokenOut")
                        .addAny("output");

                descriptions[index++] = JsonLibrary.toJsonLean(
                    string(
                        abi.encodePacked(
                            "PendleRouter(",
                            $.pendleRouterName,
                            ").exitPostExpToToken(receiver=",
                            $.subvaultName,
                            ", market=",
                            Strings.toHexString(strategy.market),
                            ", tokenOut=",
                            tokenSymbol,
                            ", tokenRedeemSy=",
                            tokenSymbol,
                            ", netPtIn=any, minTokenOut=any, NO_SWAP)"
                        )
                    ),
                    ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.pendleRouter), "0"),
                    innerParameters
                );
            }
        }

        return descriptions;
    }

    /// @notice Create an ERC20 approval proof
    function _makeApprovalProof(
        BitmaskVerifier bitmaskVerifier,
        address curator,
        address token,
        address spender
    ) private pure returns (IVerifier.VerificationPayload memory) {
        return ProofLibrary.makeVerificationPayload(
            bitmaskVerifier,
            curator,
            token,
            0,
            abi.encodeCall(IERC20.approve, (spender, 0)),
            ProofLibrary.makeBitmask(
                true, true, true, true, abi.encodeCall(IERC20.approve, (address(type(uint160).max), 0))
            )
        );
    }

    /// @notice Create swapExactTokenForPt proof with security restrictions
    /// @dev Locks: receiver=subvault, tokenIn=inputToken, tokenMintSy=inputToken, NO external router
    ///      Allows: any amounts, minPtOut, approxParams
    function _makeSwapTokenForPtProof(
        BitmaskVerifier bitmaskVerifier,
        address curator,
        address pendleRouter,
        address subvault,
        address market,
        address inputToken
    ) private pure returns (IVerifier.VerificationPayload memory) {
        // Create template with locked parameters
        IPendleRouter.ApproxParams memory approxParams = IPendleRouter.ApproxParams({
            guessMin: 0,
            guessMax: 0,
            guessOffchain: 0,
            maxIteration: 0,
            eps: 0
        });

        IPendleRouter.SwapData memory swapData = IPendleRouter.SwapData({
            swapType: IPendleRouter.SwapType.NONE,  // LOCKED: No external swaps
            extRouter: address(0),                   // LOCKED: No external router
            extCalldata: "",
            needScale: false
        });

        // Lock both tokenIn and tokenMintSy to the same inputToken (no swaps)
        IPendleRouter.TokenInput memory tokenInput = IPendleRouter.TokenInput({
            tokenIn: inputToken,           // LOCKED: Must use this specific input token
            netTokenIn: 0,                 // ALLOW ANY: Amount
            tokenMintSy: inputToken,       // LOCKED: Same as tokenIn (no conversion needed)
            pendleSwap: address(0),        // LOCKED: No Pendle swap aggregator
            swapData: swapData             // LOCKED: No external swaps
        });

        IPendleRouter.LimitOrderData memory limitOrderData = IPendleRouter.LimitOrderData({
            limitRouter: address(0),       // LOCKED: No limit orders
            epsSkipMarket: 0,
            normalFills: new IPendleRouter.FillOrderParams[](0),
            flashFills: new IPendleRouter.FillOrderParams[](0),
            optData: ""
        });

        bytes memory callData = abi.encodeCall(
            IPendleRouter.swapExactTokenForPt,
            (subvault, market, 0, approxParams, tokenInput, limitOrderData)
        );

        // Create bitmask
        // For bitmask: 0 = allow any, non-zero = must match template exactly
        // Lock: receiver (subvault), market, mintSyToken, pendleSwap, extRouter
        // Allow: minPtOut, amounts, approxParams

        IPendleRouter.SwapData memory swapDataMask = IPendleRouter.SwapData({
            swapType: swapData.swapType,           // Use same as template (locks it)
            extRouter: swapData.extRouter,          // Use same as template (locks to 0x0)
            extCalldata: "",                        // Empty = allow any
            needScale: swapData.needScale          // Use same as template
        });

        IPendleRouter.TokenInput memory tokenInputMask = IPendleRouter.TokenInput({
            tokenIn: tokenInput.tokenIn,            // LOCK: Must match template (same as tokenMintSy)
            netTokenIn: 0,                          // 0 = ALLOW any amount
            tokenMintSy: tokenInput.tokenMintSy,    // LOCK: Must match template (same as tokenIn)
            pendleSwap: tokenInput.pendleSwap,      // Same as template = LOCK (to 0x0)
            swapData: swapDataMask
        });

        IPendleRouter.LimitOrderData memory limitOrderDataMask = IPendleRouter.LimitOrderData({
            limitRouter: limitOrderData.limitRouter, // Same as template = LOCK (to 0x0)
            epsSkipMarket: 0,                        // 0 = ALLOW
            normalFills: new IPendleRouter.FillOrderParams[](0),
            flashFills: new IPendleRouter.FillOrderParams[](0),
            optData: ""
        });

        bytes memory bitmask = ProofLibrary.makeBitmask(
            true,  // Lock curator
            true,  // Lock pendleRouter
            true,  // Lock value (0)
            true,  // Lock function selector
            abi.encodeCall(
                IPendleRouter.swapExactTokenForPt,
                (
                    subvault,           // Same as template = LOCK receiver
                    market,             // Same as template = LOCK market
                    0,                  // 0 = ALLOW minPtOut
                    approxParams,       // Same as template (all zeros) = LOCK
                    tokenInputMask,
                    limitOrderDataMask
                )
            )
        );

        return ProofLibrary.makeVerificationPayload(
            bitmaskVerifier,
            curator,
            pendleRouter,
            0,
            callData,
            bitmask
        );
    }

    /// @notice Create swapExactPtForToken proof with security restrictions
    /// @dev Locks: receiver=subvault, tokenOut=outputToken, tokenRedeemSy=outputToken, NO external router
    ///      Allows: any amounts, exactPtIn, minTokenOut
    function _makeSwapPtForTokenProof(
        BitmaskVerifier bitmaskVerifier,
        address curator,
        address pendleRouter,
        address subvault,
        address market,
        address outputToken
    ) private pure returns (IVerifier.VerificationPayload memory) {
        IPendleRouter.SwapData memory swapData = IPendleRouter.SwapData({
            swapType: IPendleRouter.SwapType.NONE,  // LOCKED: No external swaps
            extRouter: address(0),                   // LOCKED: No external router
            extCalldata: "",
            needScale: false
        });

        IPendleRouter.TokenOutput memory tokenOutput = IPendleRouter.TokenOutput({
            tokenOut: outputToken,       // LOCKED: Must use this specific output token
            minTokenOut: 0,              // ALLOW ANY
            tokenRedeemSy: outputToken,  // LOCKED: Same as tokenOut (no conversion needed)
            pendleSwap: address(0),      // LOCKED: No Pendle swap aggregator
            swapData: swapData           // LOCKED: No external swaps
        });

        IPendleRouter.LimitOrderData memory limitOrderData = IPendleRouter.LimitOrderData({
            limitRouter: address(0),     // LOCKED: No limit orders
            epsSkipMarket: 0,
            normalFills: new IPendleRouter.FillOrderParams[](0),
            flashFills: new IPendleRouter.FillOrderParams[](0),
            optData: ""
        });

        bytes memory callData = abi.encodeCall(
            IPendleRouter.swapExactPtForToken,
            (subvault, market, 0, tokenOutput, limitOrderData)
        );

        // Create mask - lock both tokenOut and tokenRedeemSy to outputToken
        IPendleRouter.SwapData memory swapDataMask = IPendleRouter.SwapData({
            swapType: swapData.swapType,           // Use same as template (locks it)
            extRouter: swapData.extRouter,          // Use same as template (locks to 0x0)
            extCalldata: "",                        // Empty = allow any
            needScale: swapData.needScale          // Use same as template
        });

        IPendleRouter.TokenOutput memory tokenOutputMask = IPendleRouter.TokenOutput({
            tokenOut: tokenOutput.tokenOut,         // LOCK: Must match template (same as tokenRedeemSy)
            minTokenOut: 0,                         // 0 = ALLOW any amount
            tokenRedeemSy: tokenOutput.tokenRedeemSy,  // LOCK: Must match template (same as tokenOut)
            pendleSwap: tokenOutput.pendleSwap,     // Same as template = LOCK (to 0x0)
            swapData: swapDataMask
        });

        IPendleRouter.LimitOrderData memory limitOrderDataMask = IPendleRouter.LimitOrderData({
            limitRouter: limitOrderData.limitRouter, // Same as template = LOCK (to 0x0)
            epsSkipMarket: 0,                        // 0 = ALLOW
            normalFills: new IPendleRouter.FillOrderParams[](0),
            flashFills: new IPendleRouter.FillOrderParams[](0),
            optData: ""
        });

        bytes memory bitmask = ProofLibrary.makeBitmask(
            true,  // Lock curator
            true,  // Lock pendleRouter
            true,  // Lock value (0)
            true,  // Lock function selector
            abi.encodeCall(
                IPendleRouter.swapExactPtForToken,
                (
                    subvault,            // Same as template = LOCK receiver
                    market,              // Same as template = LOCK market
                    0,                   // 0 = ALLOW exactPtIn
                    tokenOutputMask,
                    limitOrderDataMask
                )
            )
        );

        return ProofLibrary.makeVerificationPayload(
            bitmaskVerifier,
            curator,
            pendleRouter,
            0,
            callData,
            bitmask
        );
    }

    /// @notice Create exitPostExpToToken proof (redeem expired PT)
    /// @dev Locks: receiver=subvault, tokenOut=outputToken, tokenRedeemSy=outputToken, NO external router
    ///      Allows: any amounts, netPtIn, minTokenOut
    function _makeExitPostExpProof(
        BitmaskVerifier bitmaskVerifier,
        address curator,
        address pendleRouter,
        address subvault,
        address market,
        address outputToken
    ) private pure returns (IVerifier.VerificationPayload memory) {
        IPendleRouter.SwapData memory swapData = IPendleRouter.SwapData({
            swapType: IPendleRouter.SwapType.NONE,  // LOCKED: No external swaps
            extRouter: address(0),                   // LOCKED: No external router
            extCalldata: "",
            needScale: false
        });

        IPendleRouter.TokenOutput memory tokenOutput = IPendleRouter.TokenOutput({
            tokenOut: outputToken,       // LOCKED: Must use this specific output token
            minTokenOut: 0,              // ALLOW ANY
            tokenRedeemSy: outputToken,  // LOCKED: Same as tokenOut (no conversion needed)
            pendleSwap: address(0),      // LOCKED: No Pendle swap aggregator
            swapData: swapData           // LOCKED: No external swaps
        });

        bytes memory callData = abi.encodeCall(
            IPendleRouter.exitPostExpToToken,
            (subvault, market, 0, 0, tokenOutput)
        );

        // Create mask - lock both tokenOut and tokenRedeemSy to outputToken
        IPendleRouter.SwapData memory swapDataMask = IPendleRouter.SwapData({
            swapType: swapData.swapType,           // Use same as template (locks it)
            extRouter: swapData.extRouter,          // Use same as template (locks to 0x0)
            extCalldata: "",                        // Empty = allow any
            needScale: swapData.needScale          // Use same as template
        });

        IPendleRouter.TokenOutput memory tokenOutputMask = IPendleRouter.TokenOutput({
            tokenOut: tokenOutput.tokenOut,         // LOCK: Must match template (same as tokenRedeemSy)
            minTokenOut: 0,                         // 0 = ALLOW any amount
            tokenRedeemSy: tokenOutput.tokenRedeemSy,  // LOCK: Must match template (same as tokenOut)
            pendleSwap: tokenOutput.pendleSwap,     // Same as template = LOCK (to 0x0)
            swapData: swapDataMask
        });

        bytes memory bitmask = ProofLibrary.makeBitmask(
            true,  // Lock curator
            true,  // Lock pendleRouter
            true,  // Lock value (0)
            true,  // Lock function selector
            abi.encodeCall(
                IPendleRouter.exitPostExpToToken,
                (
                    subvault,            // Same as template = LOCK receiver
                    market,              // Same as template = LOCK market
                    0,                   // 0 = ALLOW netPtIn
                    0,                   // 0 = ALLOW minTokenOut
                    tokenOutputMask
                )
            )
        );

        return ProofLibrary.makeVerificationPayload(
            bitmaskVerifier,
            curator,
            pendleRouter,
            0,
            callData,
            bitmask
        );
    }

    /// @notice Get token symbol for descriptions
    function _tokenSymbol(address token) private pure returns (string memory) {
        if (token == 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3) return "USDe";
        if (token == 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497) return "sUSDe";
        if (token == 0x4F6673346aB4813F1665327aB39087008Cc7d76F) return "jrUSDe";
        if (token == 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) return "WETH";
        if (token == 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0) return "wstETH";
        if (token == 0x08EFCC2F3e61185D0EA7F8830B3FEc9Bfa2EE313) return "sNUSD";
        if (token == 0x3d7d6fdf07EE548B939A80edbc9B2256d0cdc003) return "sRUSDe";
        if (token == 0x6bf7788EAA948d9fFBA7E9bb386E2D3c9810e0fc) return "Sierra";
        return Strings.toHexString(token);
    }
}
