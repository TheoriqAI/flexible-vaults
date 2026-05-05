// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface ILidoWithdrawalQueue {
    /// @notice Request withdrawal of wstETH
    /// @param _amounts Array of wstETH amounts to withdraw
    /// @param _owner Address that will own the withdrawal NFTs
    /// @return requestIds Array of request IDs
    function requestWithdrawalsWstETH(uint256[] calldata _amounts, address _owner)
        external
        returns (uint256[] memory requestIds);

    /// @notice Claim a finalized withdrawal request
    /// @param _requestId The ID of the withdrawal request to claim
    function claimWithdrawal(uint256 _requestId) external;
}
