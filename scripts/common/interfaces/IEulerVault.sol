// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface IEulerVault {
    /// @notice Borrows `amount` of underlying assets, sending them to `receiver`.
    /// @param amount The amount of assets to borrow.
    /// @param receiver The address that will receive the borrowed assets.
    /// @return The amount of assets borrowed.
    function borrow(uint256 amount, address receiver) external returns (uint256);

    /// @notice Repays `amount` of the debt owed by `receiver`.
    /// @param amount The amount of assets to repay.
    /// @param receiver The address whose debt is being repaid.
    /// @return The amount of assets repaid.
    function repay(uint256 amount, address receiver) external returns (uint256);

    /// @notice Liquidates a violator's position, repaying their debt and receiving collateral shares.
    /// @param violator The address of the account to liquidate.
    /// @param collateral The EVault address holding the collateral to seize.
    /// @param repayAssets The amount of underlying debt to repay.
    /// @param minYieldBalance The minimum collateral balance to receive (slippage protection).
    function liquidate(address violator, address collateral, uint256 repayAssets, uint256 minYieldBalance) external;
}
