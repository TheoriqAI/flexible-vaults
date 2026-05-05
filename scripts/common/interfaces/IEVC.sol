// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface IEVC {
    /// @notice Enables a vault as a controller for the account, allowing it to borrow on behalf of the account.
    function enableController(address account, address vault) external payable;

    /// @notice Enables a vault as collateral for the account.
    function enableCollateral(address account, address vault) external payable;

    /// @notice Disables the controller for the account.
    function disableController(address account) external payable;

    /// @notice Disables a vault as collateral for the account.
    function disableCollateral(address account, address vault) external payable;
}
