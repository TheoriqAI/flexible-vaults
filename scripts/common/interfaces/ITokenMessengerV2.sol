// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/// @notice Interface for Circle CCTP V2 TokenMessenger
/// @dev Matches selector 0x8e0250ee
interface ITokenMessengerV2 {
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        uint256 maxFee,
        uint32 minFinalityThreshold
    ) external returns (uint64 nonce);
}
