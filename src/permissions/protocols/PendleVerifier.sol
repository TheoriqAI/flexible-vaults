// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../../interfaces/external/pendle/IPendleMarket.sol";
import "../../interfaces/external/pendle/IPendleRouter.sol";

import "./OwnedCustomVerifier.sol";

/// @title PendleVerifier
/// @notice Custom verifier for Pendle Router operations with ABI-level decoding.
/// @dev Unlike BitmaskVerifier, this supports dynamic arrays (limit order fills, flash fills)
///      and optionally checks minPtOut/minTokenOut against the market TWAP oracle.
contract PendleVerifier is OwnedCustomVerifier {
    // ──────────────────────────────────────────────────────────────────────────
    // Roles
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Role for addresses allowed to initiate calls (curators)
    bytes32 public constant CALLER_ROLE = keccak256("permissions.protocols.PendleVerifier.CALLER_ROLE");

    /// @notice Role for allowed Pendle market addresses
    bytes32 public constant MARKET_ROLE = keccak256("permissions.protocols.PendleVerifier.MARKET_ROLE");

    /// @notice Role for allowed input/output token addresses
    bytes32 public constant TOKEN_ROLE = keccak256("permissions.protocols.PendleVerifier.TOKEN_ROLE");

    /// @notice Role for allowed Pendle swap aggregator addresses
    bytes32 public constant PENDLE_SWAP_ROLE = keccak256("permissions.protocols.PendleVerifier.PENDLE_SWAP_ROLE");

    /// @notice Role for allowed limit order router addresses
    bytes32 public constant LIMIT_ROUTER_ROLE = keccak256("permissions.protocols.PendleVerifier.LIMIT_ROUTER_ROLE");

    /// @notice Role for addresses allowed to update TWAP configuration
    bytes32 public constant TWAP_ADMIN_ROLE = keccak256("permissions.protocols.PendleVerifier.TWAP_ADMIN_ROLE");

    // ──────────────────────────────────────────────────────────────────────────
    // Errors
    // ──────────────────────────────────────────────────────────────────────────

    error InvalidMaxSlippageBps();
    error Unauthorized();

    // ──────────────────────────────────────────────────────────────────────────
    // Events
    // ──────────────────────────────────────────────────────────────────────────

    event TwapConfigUpdated(uint32 twapDuration, uint256 maxSlippageBps);

    // ──────────────────────────────────────────────────────────────────────────
    // Function selectors (derived from IPendleRouter interface)
    // ──────────────────────────────────────────────────────────────────────────

    bytes4 private constant SWAP_EXACT_TOKEN_FOR_PT = IPendleRouter.swapExactTokenForPt.selector;
    bytes4 private constant SWAP_EXACT_PT_FOR_TOKEN = IPendleRouter.swapExactPtForToken.selector;
    bytes4 private constant EXIT_POST_EXP_TO_TOKEN = IPendleRouter.exitPostExpToToken.selector;

    // ──────────────────────────────────────────────────────────────────────────
    // Immutables
    // ──────────────────────────────────────────────────────────────────────────

    address public immutable pendleRouter;

    // ──────────────────────────────────────────────────────────────────────────
    // TWAP configuration (mutable by TWAP_ADMIN_ROLE)
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice TWAP observation window in seconds (0 = disabled)
    uint32 public twapDuration;

    /// @notice Maximum allowed slippage in basis points (e.g. 200 = 2%)
    uint256 public maxSlippageBps;

    // ──────────────────────────────────────────────────────────────────────────
    // Constructor
    // ──────────────────────────────────────────────────────────────────────────

    constructor(address pendleRouter_, string memory name_, uint256 version_)
        OwnedCustomVerifier(name_, version_)
    {
        pendleRouter = pendleRouter_;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Admin
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Update TWAP oracle configuration
    /// @param twapDuration_ Observation window in seconds (0 to disable TWAP checks)
    /// @param maxSlippageBps_ Maximum slippage in basis points
    function setTwapConfig(uint32 twapDuration_, uint256 maxSlippageBps_) external {
        if (!hasRole(TWAP_ADMIN_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized();
        }
        if (maxSlippageBps_ > 10000) revert InvalidMaxSlippageBps();
        twapDuration = twapDuration_;
        maxSlippageBps = maxSlippageBps_;
        emit TwapConfigUpdated(twapDuration_, maxSlippageBps_);
    }

    // ──────────────────────────────────────────────────────────────────────────
    // ICustomVerifier
    // ──────────────────────────────────────────────────────────────────────────

    /// @inheritdoc ICustomVerifier
    function verifyCall(
        address who,
        address where,
        uint256 value,
        bytes calldata callData,
        bytes calldata /* verificationData */
    ) external view override returns (bool) {
        if (value != 0 || callData.length < 4 || where != pendleRouter || !hasRole(CALLER_ROLE, who)) {
            return false;
        }

        bytes4 selector = bytes4(callData[:4]);

        if (selector == SWAP_EXACT_TOKEN_FOR_PT) {
            return _verifySwapExactTokenForPt(who, callData);
        } else if (selector == SWAP_EXACT_PT_FOR_TOKEN) {
            return _verifySwapExactPtForToken(who, callData);
        } else if (selector == EXIT_POST_EXP_TO_TOKEN) {
            return _verifyExitPostExpToToken(who, callData);
        }

        return false;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Internal: per-function verification
    // ──────────────────────────────────────────────────────────────────────────

    function _verifySwapExactTokenForPt(address who, bytes calldata callData) internal view returns (bool) {
        (
            address receiver,
            address market,
            uint256 minPtOut,
            IPendleRouter.ApproxParams memory _approx,
            IPendleRouter.TokenInput memory input,
            IPendleRouter.LimitOrderData memory limit
        ) = abi.decode(
            callData[4:],
            (address, address, uint256, IPendleRouter.ApproxParams, IPendleRouter.TokenInput, IPendleRouter.LimitOrderData)
        );

        // Receiver must be the calling subvault
        if (receiver != who) return false;

        // Market must be whitelisted
        if (!hasRole(MARKET_ROLE, market)) return false;

        // Tokens must be whitelisted
        if (!hasRole(TOKEN_ROLE, input.tokenIn)) return false;
        if (!hasRole(TOKEN_ROLE, input.tokenMintSy)) return false;

        // PendleSwap aggregator: must be whitelisted if used
        if (input.pendleSwap != address(0) && !hasRole(PENDLE_SWAP_ROLE, input.pendleSwap)) return false;

        // Limit router: must be whitelisted if used
        if (limit.limitRouter != address(0) && !hasRole(LIMIT_ROUTER_ROLE, limit.limitRouter)) return false;

        // TWAP check: only when input is the direct SY-mintable token (no intermediate swap)
        if (twapDuration > 0 && input.tokenIn == input.tokenMintSy) {
            uint256 expectedPtOut = _getExpectedPtOut(market, input.netTokenIn);
            if (expectedPtOut > 0) {
                uint256 minAcceptable = expectedPtOut * (10000 - maxSlippageBps) / 10000;
                if (minPtOut < minAcceptable) return false;
            }
        }

        return true;
    }

    function _verifySwapExactPtForToken(address who, bytes calldata callData) internal view returns (bool) {
        (
            address receiver,
            address market,
            uint256 _exactPtIn,
            IPendleRouter.TokenOutput memory output,
            IPendleRouter.LimitOrderData memory limit
        ) = abi.decode(
            callData[4:],
            (address, address, uint256, IPendleRouter.TokenOutput, IPendleRouter.LimitOrderData)
        );

        // Receiver must be the calling subvault
        if (receiver != who) return false;

        // Market must be whitelisted
        if (!hasRole(MARKET_ROLE, market)) return false;

        // Tokens must be whitelisted
        if (!hasRole(TOKEN_ROLE, output.tokenOut)) return false;
        if (!hasRole(TOKEN_ROLE, output.tokenRedeemSy)) return false;

        // PendleSwap aggregator: must be whitelisted if used
        if (output.pendleSwap != address(0) && !hasRole(PENDLE_SWAP_ROLE, output.pendleSwap)) return false;

        // Limit router: must be whitelisted if used
        if (limit.limitRouter != address(0) && !hasRole(LIMIT_ROUTER_ROLE, limit.limitRouter)) return false;

        return true;
    }

    function _verifyExitPostExpToToken(address who, bytes calldata callData) internal view returns (bool) {
        (
            address receiver,
            address market,
            uint256 _netPtIn,
            uint256 _minTokenOut,
            IPendleRouter.TokenOutput memory output
        ) = abi.decode(callData[4:], (address, address, uint256, uint256, IPendleRouter.TokenOutput));

        // Receiver must be the calling subvault
        if (receiver != who) return false;

        // Market must be whitelisted
        if (!hasRole(MARKET_ROLE, market)) return false;

        // Tokens must be whitelisted
        if (!hasRole(TOKEN_ROLE, output.tokenOut)) return false;
        if (!hasRole(TOKEN_ROLE, output.tokenRedeemSy)) return false;

        // PendleSwap aggregator: must be whitelisted if used
        if (output.pendleSwap != address(0) && !hasRole(PENDLE_SWAP_ROLE, output.pendleSwap)) return false;

        return true;
    }

    // ──────────────────────────────────────────────────────────────────────────
    // Internal: TWAP oracle
    // ──────────────────────────────────────────────────────────────────────────

    /// @notice Compute expected PT output from TWAP implied rate
    /// @dev Uses the market's observe() oracle to get TWAP ln(impliedRate).
    ///      PT price relative to underlying ≈ e^(-lnImpliedRate * timeToExpiry / 365 days).
    ///      Returns 0 if the oracle call fails (e.g. insufficient cardinality) to avoid
    ///      blocking operations when the oracle is not yet initialized.
    /// @param market The Pendle market address
    /// @param netTokenIn Amount of input token (in underlying terms)
    /// @return expectedPtOut Expected PT output based on TWAP, or 0 if oracle unavailable
    function _getExpectedPtOut(address market, uint256 netTokenIn) internal view returns (uint256) {
        uint32 duration = twapDuration;
        if (duration == 0) return 0;

        // Query the market oracle for TWAP
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = duration;
        secondsAgos[1] = 0;

        uint216[] memory cumulatives;
        try IPendleMarket(market).observe(secondsAgos) returns (uint216[] memory result) {
            cumulatives = result;
        } catch {
            // Oracle not initialized or insufficient cardinality — skip TWAP check
            return 0;
        }

        uint256 lnImpliedRateTwap = (uint256(cumulatives[1]) - uint256(cumulatives[0])) / duration;

        uint256 timeToExpiry;
        try IPendleMarket(market).expiry() returns (uint256 exp) {
            if (exp <= block.timestamp) return 0; // Expired — no TWAP check needed
            timeToExpiry = exp - block.timestamp;
        } catch {
            return 0;
        }

        // PT price = e^(-lnImpliedRate * timeToExpiry / YEAR)
        // expectedPtOut = netTokenIn / ptPrice = netTokenIn * e^(lnImpliedRate * timeToExpiry / YEAR)
        //
        // We approximate using a second-order Taylor expansion:
        // e^x ≈ 1 + x + x^2/2
        //
        // lnImpliedRate is in 1e18 fixed-point (Pendle convention).
        // x = lnImpliedRate * timeToExpiry / 365 days, also in 1e18.

        uint256 YEAR = 365 days;
        uint256 WAD = 1e18;

        // x = lnImpliedRateTwap * timeToExpiry / YEAR (in 1e18)
        uint256 x = lnImpliedRateTwap * timeToExpiry / YEAR;

        // e^x ≈ 1 + x + x²/2 (in 1e18 fixed-point)
        uint256 expX = WAD + x + (x * x) / (2 * WAD);

        // expectedPtOut = netTokenIn * e^x / WAD
        // (because PT is cheaper than underlying, you get MORE PT per token)
        return netTokenIn * expX / WAD;
    }
}
