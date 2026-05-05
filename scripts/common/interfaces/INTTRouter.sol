// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

/// @notice Interface for the Wormhole NTT Router
/// @dev Matches selector 0x924105c3
interface INTTRouter {
    struct RelayInstructions {
        uint256 deliveryPayment;
        address relayer;
        bytes relayerData;
        bytes extraData;
    }

    struct TargetChainInfo {
        uint16 chainId;
        address target;
    }

    function transfer(
        address nttManager,
        address token,
        uint256 amount,
        uint16 recipientChain,
        bytes32 recipient,
        bytes32 refundAddress,
        bytes calldata transceiverInstructions,
        RelayInstructions calldata relayInstructions,
        TargetChainInfo calldata targetChainInfo
    ) external payable;
}
