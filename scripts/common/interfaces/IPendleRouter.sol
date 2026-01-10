// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice Pendle Router V3 interface
/// @dev https://github.com/pendle-finance/pendle-core-v2-public
interface IPendleRouter {
    enum SwapType {
        NONE,
        KYBERSWAP,
        ONE_INCH,
        // ETH_WETH not used in Aggregator
        ETH_WETH
    }

    struct SwapData {
        SwapType swapType;
        address extRouter;
        bytes extCalldata;
        bool needScale;
    }

    struct TokenInput {
        // Token/Sy data
        address tokenIn;
        uint256 netTokenIn;
        address tokenMintSy;
        // aggregator data
        address pendleSwap;
        SwapData swapData;
    }

    struct TokenOutput {
        // Token/Sy data
        address tokenOut;
        uint256 minTokenOut;
        address tokenRedeemSy;
        // aggregator data
        address pendleSwap;
        SwapData swapData;
    }

    struct Order {
        uint256 salt;
        uint256 expiry;
        uint256 nonce;
        uint8 orderType;
        address token;
        address YT;
        address maker;
        address receiver;
        uint256 makingAmount;
        uint256 lnImpliedRate;
        uint256 failSafeRate;
        bytes permit;
    }

    struct FillOrderParams {
        Order order;
        bytes signature;
        uint256 makingAmount;
    }

    struct LimitOrderData {
        address limitRouter;
        uint256 epsSkipMarket; // unused in this version
        FillOrderParams[] normalFills;
        FillOrderParams[] flashFills;
        bytes optData;
    }

    struct ApproxParams {
        uint256 guessMin;
        uint256 guessMax;
        uint256 guessOffchain; // pass 0 to skip this variable
        uint256 maxIteration; // pass 256 to use default value
        uint256 eps; // pass 1e14 to use default value of 1e-4
    }

    /// @notice Swap exact token for PT
    /// @param receiver The address that will receive the PT tokens
    /// @param market The Pendle market address
    /// @param minPtOut Minimum amount of PT to receive
    /// @param guessPtOut Approximation parameters for the swap
    /// @param input Token input parameters
    /// @param limit Limit order data (usually empty for simple swaps)
    function swapExactTokenForPt(
        address receiver,
        address market,
        uint256 minPtOut,
        ApproxParams calldata guessPtOut,
        TokenInput calldata input,
        LimitOrderData calldata limit
    ) external payable returns (uint256 netPtOut, uint256 netSyFee, uint256 netSyInterm);

    /// @notice Swap exact PT for token
    /// @param receiver The address that will receive the output tokens
    /// @param market The Pendle market address
    /// @param exactPtIn Exact amount of PT to swap
    /// @param output Token output parameters
    /// @param limit Limit order data (usually empty for simple swaps)
    function swapExactPtForToken(
        address receiver,
        address market,
        uint256 exactPtIn,
        TokenOutput calldata output,
        LimitOrderData calldata limit
    ) external returns (uint256 netTokenOut, uint256 netSyFee, uint256 netSyInterm);

    /// @notice Redeem PT after expiry for underlying token
    /// @param receiver The address that will receive the redeemed tokens
    /// @param market The Pendle market address
    /// @param netPtIn Amount of PT to redeem
    /// @param minTokenOut Minimum amount of output token to receive
    /// @param output Token output parameters
    function exitPostExpToToken(
        address receiver,
        address market,
        uint256 netPtIn,
        uint256 minTokenOut,
        TokenOutput calldata output
    ) external returns (uint256 netTokenOut, uint256 netSyInterm);
}
