// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "@openzeppelin/contracts/utils/Strings.sol";

import {ABILibrary} from "../ABILibrary.sol";
import {JsonLibrary} from "../JsonLibrary.sol";
import {ParameterLibrary} from "../ParameterLibrary.sol";
import "../ProofLibrary.sol";
import "../interfaces/IKyberSwapRouter.sol";
import "../interfaces/Imports.sol";

library KyberSwapLibrary {
    using ParameterLibrary for ParameterLibrary.Parameter[];

    struct Info {
        address kyberRouter;
        address curator;
        address[] assets;
    }

    function getKyberSwapProofs(BitmaskVerifier bitmaskVerifier, Info memory $)
        internal
        pure
        returns (IVerifier.VerificationPayload[] memory leaves)
    {
        // Operations per curator:
        // 1. approve each asset to kyberRouter
        // 2. swap function (MERKLE_COMPACT - variable length calldata)
        // 3. swapGeneric function (MERKLE_COMPACT - variable length calldata)
        // Total: assets.length + 2

        uint256 length = $.assets.length + 2;
        leaves = new IVerifier.VerificationPayload[](length);
        uint256 index = 0;

        // Proof for swap function - use MERKLE_COMPACT for variable-length calldata
        // MERKLE_COMPACT only checks (who, where, selector) - ignores calldata content/length
        leaves[index++] = _makeMerkleCompactPayload($.curator, $.kyberRouter, IKyberSwapRouter.swap.selector);

        // Proof for swapGeneric function - use MERKLE_COMPACT for variable-length calldata
        leaves[index++] = _makeMerkleCompactPayload($.curator, $.kyberRouter, IKyberSwapRouter.swapGeneric.selector);

        // Approvals for each asset - use BitmaskVerifier (fixed-length calldata)
        for (uint256 i = 0; i < $.assets.length; i++) {
            address asset = $.assets[i];
            if (asset == TransferLibrary.ETH) continue; // Skip ETH, no approval needed

            leaves[index++] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                $.curator,
                asset,
                0,
                abi.encodeCall(IERC20.approve, ($.kyberRouter, 0)),
                ProofLibrary.makeBitmask(
                    true, true, true, true, abi.encodeCall(IERC20.approve, (address(type(uint160).max), 0))
                )
            );
        }

        assembly {
            mstore(leaves, index)
        }
    }

    /// @dev Creates a MERKLE_COMPACT verification payload for selector-only verification
    /// This is used for functions with variable-length calldata (like swap functions)
    function _makeMerkleCompactPayload(address who, address where, bytes4 selector)
        internal
        pure
        returns (IVerifier.VerificationPayload memory payload)
    {
        // MERKLE_COMPACT verificationData is the hash of (who, where, selector)
        bytes32 compactHash = keccak256(abi.encode(who, where, selector));
        payload.verificationType = IVerifier.VerificationType.MERKLE_COMPACT;
        payload.verificationData = abi.encodePacked(compactHash);
        // proof will be populated by generateMerkleProofs
    }

    function getKyberSwapDescriptions(Info memory $) internal view returns (string[] memory descriptions) {
        uint256 length = $.assets.length + 2;
        descriptions = new string[](length);
        uint256 index = 0;
        ParameterLibrary.Parameter[] memory innerParameters;

        // swap description
        innerParameters = ParameterLibrary.build("execution", "any");
        descriptions[index++] = JsonLibrary.toJson(
            string(abi.encodePacked("KyberSwapRouter.swap(anyExecution)")),
            ABILibrary.getABI(IKyberSwapRouter.swap.selector),
            ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.kyberRouter), "any"),
            innerParameters
        );

        // swapGeneric description
        innerParameters = ParameterLibrary.build("execution", "any");
        descriptions[index++] = JsonLibrary.toJson(
            string(abi.encodePacked("KyberSwapRouter.swapGeneric(anyExecution)")),
            ABILibrary.getABI(IKyberSwapRouter.swapGeneric.selector),
            ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.kyberRouter), "any"),
            innerParameters
        );

        // Approval descriptions
        for (uint256 i = 0; i < $.assets.length; i++) {
            if ($.assets[i] == TransferLibrary.ETH) continue;

            string memory asset = IERC20Metadata($.assets[i]).symbol();
            innerParameters = ParameterLibrary.build("to", Strings.toHexString($.kyberRouter)).addAny("amount");
            descriptions[index++] = JsonLibrary.toJson(
                string(abi.encodePacked("IERC20(", asset, ").approve(KyberSwapRouter, anyInt)")),
                ABILibrary.getABI(IERC20.approve.selector),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.assets[i]), "0"),
                innerParameters
            );
        }

        assembly {
            mstore(descriptions, index)
        }
    }

    function getKyberSwapCalls(Info memory $) internal pure returns (Call[][] memory calls) {
        uint256 index = 0;
        calls = new Call[][]($.assets.length + 2);

        // swap test calls - MERKLE_COMPACT accepts any calldata length
        {
            Call[] memory tmp = new Call[](8);
            uint256 i = 0;
            // MERKLE_COMPACT only checks selector - any calldata length works
            tmp[i++] = Call($.curator, $.kyberRouter, 0, _encodeSwap(), true);
            tmp[i++] = Call($.curator, $.kyberRouter, 1 ether, _encodeSwap(), true); // with ETH value
            // Test with different calldata (just selector) - should still work
            tmp[i++] = Call($.curator, $.kyberRouter, 0, abi.encodeWithSelector(IKyberSwapRouter.swap.selector), true);
            tmp[i++] = Call(address(0xdead), $.kyberRouter, 0, _encodeSwap(), false); // wrong caller
            tmp[i++] = Call($.curator, address(0xdead), 0, _encodeSwap(), false); // wrong target
            assembly {
                mstore(tmp, i)
            }
            calls[index++] = tmp;
        }

        // swapGeneric test calls - MERKLE_COMPACT accepts any calldata length
        {
            Call[] memory tmp = new Call[](8);
            uint256 i = 0;
            tmp[i++] = Call($.curator, $.kyberRouter, 0, _encodeSwapGeneric(), true);
            tmp[i++] = Call($.curator, $.kyberRouter, 1 ether, _encodeSwapGeneric(), true);
            // Test with different calldata (just selector) - should still work
            tmp[i++] = Call($.curator, $.kyberRouter, 0, abi.encodeWithSelector(IKyberSwapRouter.swapGeneric.selector), true);
            tmp[i++] = Call(address(0xdead), $.kyberRouter, 0, _encodeSwapGeneric(), false);
            tmp[i++] = Call($.curator, address(0xdead), 0, _encodeSwapGeneric(), false);
            assembly {
                mstore(tmp, i)
            }
            calls[index++] = tmp;
        }

        // Approval test calls
        for (uint256 j = 0; j < $.assets.length; j++) {
            if ($.assets[j] == TransferLibrary.ETH) continue;

            address asset = $.assets[j];
            Call[] memory tmp = new Call[](8);
            uint256 i = 0;
            tmp[i++] = Call($.curator, asset, 0, abi.encodeCall(IERC20.approve, ($.kyberRouter, 0)), true);
            tmp[i++] = Call($.curator, asset, 0, abi.encodeCall(IERC20.approve, ($.kyberRouter, 1 ether)), true);
            tmp[i++] = Call(address(0xdead), asset, 0, abi.encodeCall(IERC20.approve, ($.kyberRouter, 1 ether)), false);
            tmp[i++] = Call($.curator, address(0xdead), 0, abi.encodeCall(IERC20.approve, ($.kyberRouter, 1 ether)), false);
            tmp[i++] = Call($.curator, asset, 0, abi.encodeCall(IERC20.approve, (address(0xdead), 1 ether)), false);
            tmp[i++] = Call($.curator, asset, 1 wei, abi.encodeCall(IERC20.approve, ($.kyberRouter, 1 ether)), false);
            assembly {
                mstore(tmp, i)
            }
            calls[index++] = tmp;
        }

        assembly {
            mstore(calls, index)
        }
    }

    function _encodeSwap() internal pure returns (bytes memory) {
        IKyberSwapRouter.SwapDescriptionV2 memory desc = IKyberSwapRouter.SwapDescriptionV2({
            srcToken: address(0),
            dstToken: address(0),
            srcReceivers: new address[](0),
            srcAmounts: new uint256[](0),
            feeReceivers: new address[](0),
            feeAmounts: new uint256[](0),
            dstReceiver: address(0),
            amount: 0,
            minReturnAmount: 0,
            flags: 0,
            permit: ""
        });
        IKyberSwapRouter.SwapExecutionParams memory execution = IKyberSwapRouter.SwapExecutionParams({
            callTarget: address(0),
            approveTarget: address(0),
            targetData: "",
            desc: desc,
            clientData: ""
        });
        return abi.encodeCall(IKyberSwapRouter.swap, (execution));
    }

    function _encodeSwapGeneric() internal pure returns (bytes memory) {
        IKyberSwapRouter.SwapDescriptionV2 memory desc = IKyberSwapRouter.SwapDescriptionV2({
            srcToken: address(0),
            dstToken: address(0),
            srcReceivers: new address[](0),
            srcAmounts: new uint256[](0),
            feeReceivers: new address[](0),
            feeAmounts: new uint256[](0),
            dstReceiver: address(0),
            amount: 0,
            minReturnAmount: 0,
            flags: 0,
            permit: ""
        });
        IKyberSwapRouter.SwapExecutionParams memory execution = IKyberSwapRouter.SwapExecutionParams({
            callTarget: address(0),
            approveTarget: address(0),
            targetData: "",
            desc: desc,
            clientData: ""
        });
        return abi.encodeCall(IKyberSwapRouter.swapGeneric, (execution));
    }
}
