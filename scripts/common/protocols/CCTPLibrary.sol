// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {ABILibrary} from "../ABILibrary.sol";
import {ArraysLibrary} from "../ArraysLibrary.sol";
import {JsonLibrary} from "../JsonLibrary.sol";
import {ParameterLibrary} from "../ParameterLibrary.sol";
import {ProofLibrary} from "../ProofLibrary.sol";
import {ERC20Library} from "./ERC20Library.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import "../interfaces/ITokenMessengerV2.sol";
import "../interfaces/IMessageTransmitterV2.sol";
import "../interfaces/Imports.sol";

import "./ERC20Library.sol";

library CCTPLibrary {
    using ParameterLibrary for ParameterLibrary.Parameter[];

    struct Info {
        address curator;
        address subvault;
        address tokenMessenger;
        address messageTransmitter;
        address burnToken; // USDC
        uint32 destinationDomain;
        bytes32 mintRecipient; // abi-encoded address on destination chain
        uint256 messageLength; // expected CCTP message size for receiveMessage bitmask
        uint256 attestationLength; // expected attestation size for receiveMessage bitmask
        string targetChainName;
    }

    function getCCTPProofs(BitmaskVerifier bitmaskVerifier, Info memory $)
        internal
        pure
        returns (IVerifier.VerificationPayload[] memory leaves)
    {
        leaves = new IVerifier.VerificationPayload[](2);
        uint256 iterator = 0;

        // 1. ERC20 approval: approve burnToken to TokenMessenger
        iterator = ArraysLibrary.insert(
            leaves,
            ERC20Library.getERC20Proofs(
                bitmaskVerifier,
                ERC20Library.Info({
                    curator: $.curator,
                    assets: ArraysLibrary.makeAddressArray(abi.encode($.burnToken)),
                    to: ArraysLibrary.makeAddressArray(abi.encode($.tokenMessenger))
                })
            ),
            iterator
        );

        // 2. depositForBurn: send USDC to destination chain
        // Note: receiveMessage removed — relayers claim with destinationCaller = bytes32(0)
        leaves[iterator++] = ProofLibrary.makeVerificationPayload(
            bitmaskVerifier,
            $.curator,
            $.tokenMessenger,
            0,
            // Actual calldata
            abi.encodeCall(
                ITokenMessengerV2.depositForBurn,
                (
                    0, // amount: any
                    $.destinationDomain,
                    $.mintRecipient,
                    $.burnToken,
                    bytes32(0), // destinationCaller: any (open relay)
                    0, // maxFee: any
                    0 // minFinalityThreshold: any
                )
            ),
            // Bitmask
            ProofLibrary.makeBitmask(
                true, // verify caller
                true, // verify contract (tokenMessenger)
                true, // verify value = 0 (no ETH needed)
                true, // verify selector
                abi.encodeCall(
                    ITokenMessengerV2.depositForBurn,
                    (
                        0, // amount: any
                        type(uint32).max, // destinationDomain: locked
                        bytes32(type(uint256).max), // mintRecipient: locked
                        address(type(uint160).max), // burnToken: locked
                        bytes32(0), // destinationCaller: any (open relay)
                        0, // maxFee: any
                        0 // minFinalityThreshold: any
                    )
                )
            )
        );

        assembly {
            mstore(leaves, iterator)
        }
    }

    function getCCTPDescriptions(Info memory $) internal view returns (string[] memory descriptions) {
        descriptions = new string[](2);
        uint256 iterator = 0;

        // ERC20 approve description
        iterator = ArraysLibrary.insert(
            descriptions,
            ERC20Library.getERC20Descriptions(
                ERC20Library.Info({
                    curator: $.curator,
                    assets: ArraysLibrary.makeAddressArray(abi.encode($.burnToken)),
                    to: ArraysLibrary.makeAddressArray(abi.encode($.tokenMessenger))
                })
            ),
            iterator
        );

        // depositForBurn description
        ParameterLibrary.Parameter[] memory depositParams;
        depositParams = depositParams.add("amount", "any");
        depositParams = depositParams.add("destinationDomain", Strings.toString(uint256($.destinationDomain)));
        depositParams = depositParams.add("mintRecipient", Strings.toHexString(uint256($.mintRecipient), 32));
        depositParams = depositParams.add("burnToken", Strings.toHexString($.burnToken));
        depositParams = depositParams.add("destinationCaller", "any");
        depositParams = depositParams.add("maxFee", "any");
        depositParams = depositParams.add("minFinalityThreshold", "any");

        descriptions[iterator++] = JsonLibrary.toJson(
            string(
                abi.encodePacked(
                    "ITokenMessengerV2(TokenMessengerV2).depositForBurn(any,",
                    Strings.toString(uint256($.destinationDomain)),
                    ",",
                    Strings.toHexString(uint256($.mintRecipient), 32),
                    ",",
                    Strings.toHexString($.burnToken),
                    ",any,any,any)"
                )
            ),
            ABILibrary.getABI(ITokenMessengerV2.depositForBurn.selector),
            ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.tokenMessenger), "0"),
            depositParams
        );

        assembly {
            mstore(descriptions, iterator)
        }
    }
}
