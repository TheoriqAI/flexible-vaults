// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {ArraysLibrary} from "../common/ArraysLibrary.sol";
import {Permissions} from "../common/Permissions.sol";
import {ProofLibrary} from "../common/ProofLibrary.sol";

import {SwapModuleLibrary} from "../common/protocols/SwapModuleLibrary.sol";

import {BitmaskVerifier, Call, IVerifier, ProtocolDeployment, SubvaultCalls} from "../common/interfaces/Imports.sol";
import "./Constants.sol";

library tqGLDLibrary {
    function getGLDAssets() internal pure returns (address[] memory) {
        return ArraysLibrary.makeAddressArray(
            abi.encode(
                Constants.ETH,
                Constants.WETH,
                Constants.XAUT,
                Constants.PAXG,
                Constants.USDC,
                Constants.USDT,
                Constants.USDE
            )
        );
    }

    function getSubvault0Info(address subvault, address[] memory curators, address swapModule)
        internal
        pure
        returns (SwapModuleLibrary.Info memory)
    {
        return SwapModuleLibrary.Info({
            subvault: subvault,
            subvaultName: "subvault0",
            swapModule: swapModule,
            curators: curators,
            assets: getGLDAssets()
        });
    }

    function getSubvault0Proofs(address subvault, address swapModule, address[] memory curators)
        internal
        pure
        returns (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leaves)
    {
        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // SwapModule proofs only:
        // ETH = 2 ops (pushAssets, pullAssets), non-ETH = 3 ops (approve, pushAssets, pullAssets)
        // Per curator: 2 + 6*3 = 20, for 2 curators = 40
        leaves = new IVerifier.VerificationPayload[](100);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            SwapModuleLibrary.getSwapModuleProofs($.bitmaskVerifier, getSubvault0Info(subvault, curators, swapModule)),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }
        return ProofLibrary.generateMerkleProofs(leaves);
    }

    function getSubvault0Descriptions(address subvault, address swapModule, address[] memory curators)
        internal
        view
        returns (string[] memory descriptions)
    {
        descriptions = new string[](100);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            SwapModuleLibrary.getSwapModuleDescriptions(getSubvault0Info(subvault, curators, swapModule)),
            iterator
        );

        assembly {
            mstore(descriptions, iterator)
        }
    }

    function getSubvault0SubvaultCalls(
        address subvault,
        address swapModule,
        address[] memory curators,
        IVerifier.VerificationPayload[] memory leaves
    ) internal pure returns (SubvaultCalls memory calls) {
        calls.payloads = leaves;
        calls.calls = new Call[][](leaves.length);

        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            calls.calls,
            SwapModuleLibrary.getSwapModuleCalls(getSubvault0Info(subvault, curators, swapModule)),
            iterator
        );
    }
}
