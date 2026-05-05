// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {ABILibrary} from "../ABILibrary.sol";
import {ArraysLibrary} from "../ArraysLibrary.sol";
import {JsonLibrary} from "../JsonLibrary.sol";
import {ParameterLibrary} from "../ParameterLibrary.sol";
import {ProofLibrary} from "../ProofLibrary.sol";
import {ERC20Library} from "./ERC20Library.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import "../interfaces/INttManagerWithExecutor.sol";
import "../interfaces/Imports.sol";

import "./ERC20Library.sol";

library NTTLibrary {
    using ParameterLibrary for ParameterLibrary.Parameter[];

    struct Info {
        address curator;
        address subvault;
        address targetSubvault;
        address nttRouter;
        address nttManager;
        address token;
        uint16 recipientChain;
        uint256 transceiverInstructionsLength;
        string subvaultName;
        string targetSubvaultName;
        string targetChainName;
    }

    function getNTTProofs(BitmaskVerifier bitmaskVerifier, Info memory $)
        internal
        pure
        returns (IVerifier.VerificationPayload[] memory leaves)
    {
        leaves = new IVerifier.VerificationPayload[](2);
        uint256 iterator = 0;

        // ERC20 approval: approve token to NTT router
        iterator = ArraysLibrary.insert(
            leaves,
            ERC20Library.getERC20Proofs(
                bitmaskVerifier,
                ERC20Library.Info({
                    curator: $.curator,
                    assets: ArraysLibrary.makeAddressArray(abi.encode($.token)),
                    to: ArraysLibrary.makeAddressArray(abi.encode($.nttRouter))
                })
            ),
            iterator
        );

        bytes32 recipientBytes32 = bytes32(uint256(uint160($.targetSubvault)));
        bytes32 refundBytes32 = bytes32(uint256(uint160($.subvault)));

        // NTT transfer call via NttManagerWithExecutor
        leaves[iterator++] = ProofLibrary.makeVerificationPayload(
            bitmaskVerifier,
            $.curator,
            $.nttRouter,
            0,
            // Actual calldata
            abi.encodeCall(
                INttManagerWithExecutor.transfer,
                (
                    $.nttManager,
                    $.token,
                    0, // amount - any
                    $.recipientChain,
                    recipientBytes32,
                    refundBytes32,
                    new bytes($.transceiverInstructionsLength), // transceiverInstructions placeholder
                    INttManagerWithExecutor.ExecutorArgs({
                        value: 0,
                        refundAddress: $.curator,
                        signedQuote: new bytes(165),
                        instructions: new bytes(33)
                    }),
                    INttManagerWithExecutor.FeeArgs({dbps: 0, payee: address(0)})
                )
            ),
            // Bitmask
            ProofLibrary.makeBitmask(
                true, // verify caller
                true, // verify contract (nttRouter)
                false, // don't verify value (need ETH for wormhole fee)
                true, // verify selector
                abi.encodeCall(
                    INttManagerWithExecutor.transfer,
                    (
                        address(type(uint160).max), // nttManager: locked
                        address(type(uint160).max), // token: locked
                        0, // amount: any
                        type(uint16).max, // recipientChain: locked
                        bytes32(type(uint256).max), // recipientAddress: locked
                        bytes32(type(uint256).max), // refundAddress: locked
                        new bytes($.transceiverInstructionsLength), // transceiverInstructions: any(N)
                        INttManagerWithExecutor.ExecutorArgs({
                            value: 0, // any
                            refundAddress: address(type(uint160).max), // locked to curator
                            signedQuote: new bytes(165), // any(165)
                            instructions: new bytes(33) // any(33)
                        }),
                        INttManagerWithExecutor.FeeArgs({
                            dbps: 0, // any
                            payee: address(0) // any
                        })
                    )
                )
            )
        );

        assembly {
            mstore(leaves, iterator)
        }
    }

    function getNTTDescriptions(Info memory $) internal view returns (string[] memory descriptions) {
        descriptions = new string[](2);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            ERC20Library.getERC20Descriptions(
                ERC20Library.Info({
                    curator: $.curator,
                    assets: ArraysLibrary.makeAddressArray(abi.encode($.token)),
                    to: ArraysLibrary.makeAddressArray(abi.encode($.nttRouter))
                })
            ),
            iterator
        );

        ParameterLibrary.Parameter[] memory innerParameters;
        innerParameters = innerParameters.add("nttManager", Strings.toHexString($.nttManager));
        innerParameters = innerParameters.add("amount", "any");
        innerParameters = innerParameters.add("recipientChain", Strings.toString(uint256($.recipientChain)));
        innerParameters = innerParameters.add(
            "recipientAddress", Strings.toHexString(uint256(uint160($.targetSubvault)), 32)
        );
        innerParameters = innerParameters.add(
            "refundAddress", Strings.toHexString(uint256(uint160($.subvault)), 32)
        );
        innerParameters = innerParameters.add(
            "transceiverInstructions",
            string(abi.encodePacked("any(", Strings.toString($.transceiverInstructionsLength), ")"))
        );

        descriptions[iterator++] = JsonLibrary.toJson(
            string(
                abi.encodePacked(
                    "INttManagerWithExecutor(NttManagerWithExecutor).transfer{value: any}(",
                    "NttManager,any,",
                    Strings.toString(uint256($.recipientChain)),
                    ",",
                    Strings.toHexString(uint256(uint160($.targetSubvault)), 32),
                    ",",
                    Strings.toHexString(uint256(uint160($.subvault)), 32),
                    ",any(", Strings.toString($.transceiverInstructionsLength), "),(any,",
                    Strings.toHexString($.curator),
                    ",any(165),any(33)),(any,any))"
                )
            ),
            ABILibrary.getABI(INttManagerWithExecutor.transfer.selector),
            ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.nttRouter), "any"),
            innerParameters
        );

        assembly {
            mstore(descriptions, iterator)
        }
    }
}
