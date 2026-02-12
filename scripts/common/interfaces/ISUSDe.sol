// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface ISUSDe {
    function cooldownShares(uint256 shares) external returns (uint256 assets);

    function unstake(address receiver) external;
}
