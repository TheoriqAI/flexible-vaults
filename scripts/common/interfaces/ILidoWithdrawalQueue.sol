// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface ILidoWithdrawalQueue {
    function requestWithdrawalsWstETH(uint256[] calldata _amounts, address _owner)
        external
        returns (uint256[] memory requestIds);

    function claimWithdrawal(uint256 _requestId) external;
}
