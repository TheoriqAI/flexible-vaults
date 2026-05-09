// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice Minimal Pendle Market interface for oracle reads
/// @dev https://github.com/pendle-finance/pendle-core-v2-public
interface IPendleMarket {
    /// @notice Returns cumulative ln(impliedRate) values at the given seconds ago timestamps
    /// @param secondsAgos Array of seconds ago from current block timestamp
    /// @return lnImpliedRateCumulative Cumulative ln(impliedRate) values
    function observe(uint32[] memory secondsAgos)
        external
        view
        returns (uint216[] memory lnImpliedRateCumulative);

    /// @notice Returns the market expiry timestamp
    function expiry() external view returns (uint256);
}
