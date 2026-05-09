// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/// @notice Interface for the Wormhole NTT Manager With Executor
/// @dev Matches selector 0x924105c3
interface INttManagerWithExecutor {
    struct ExecutorArgs {
        uint256 value;
        address refundAddress;
        bytes signedQuote;
        bytes instructions;
    }

    struct FeeArgs {
        uint16 dbps;
        address payee;
    }

    function transfer(
        address nttManager,
        address token,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipientAddress,
        bytes32 refundAddress,
        bytes calldata encodedInstructions,
        ExecutorArgs calldata executorArgs,
        FeeArgs calldata feeArgs
    ) external payable returns (uint64 msgId);
}
