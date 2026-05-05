// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/// @notice Interface for Circle CCTP V2 MessageTransmitter
/// @dev Used for receiving/claiming bridged USDC
interface IMessageTransmitterV2 {
    function receiveMessage(bytes calldata message, bytes calldata attestation) external returns (bool success);
}
