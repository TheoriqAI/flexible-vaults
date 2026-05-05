// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface ISUSDe {
    /// @notice Start cooldown period for withdrawing shares
    /// @param shares Amount of shares to cooldown
    /// @return assets Amount of underlying assets
    function cooldownShares(uint256 shares) external returns (uint256 assets);

    /// @notice Unstake after cooldown period has elapsed
    /// @param receiver Address to receive the unstaked USDe
    function unstake(address receiver) external;
}
