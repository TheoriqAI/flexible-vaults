// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface IKyberSwapRouter {
    struct SwapDescriptionV2 {
        address srcToken;
        address dstToken;
        address[] srcReceivers;
        uint256[] srcAmounts;
        address[] feeReceivers;
        uint256[] feeAmounts;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
        bytes permit;
    }

    struct SwapExecutionParams {
        address callTarget;
        address approveTarget;
        bytes targetData;
        SwapDescriptionV2 desc;
        bytes clientData;
    }

    function swap(SwapExecutionParams calldata execution)
        external
        payable
        returns (uint256 returnAmount, uint256 gasUsed);

    function swapGeneric(SwapExecutionParams calldata execution)
        external
        payable
        returns (uint256 returnAmount, uint256 gasUsed);

    function swapSimpleMode(
        address caller,
        SwapDescriptionV2 calldata desc,
        bytes calldata executorData,
        bytes calldata clientData
    ) external returns (uint256 returnAmount, uint256 gasUsed);
}
