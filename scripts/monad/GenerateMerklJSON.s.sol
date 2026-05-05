// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";
import "../common/JsonLibrary.sol";
import "../common/ParameterLibrary.sol";

/// @notice Script to generate Merkl toggleOperator JSON for Monad SV0
/// @dev Run with: forge script scripts/monad/GenerateMerklJSON.s.sol --sig "generateSv0()" --via-ir --rpc-url https://rpc.monad.xyz
contract GenerateMerklJSON is Script, Test {
    address public constant VAULT = 0x799d2847cF8Dfcb4f17ec28737f17C0E82Eb445c;
    address public curator = 0x5FFA51F64Bc40c5af3a435A95e9616cc2Df9F01B;

    // toggleOperator(address user, address operator)
    string constant TOGGLE_OPERATOR_ABI =
        '{"inputs":[{"internalType":"address","name":"user","type":"address"},{"internalType":"address","name":"operator","type":"address"}],"name":"toggleOperator","outputs":[],"stateMutability":"nonpayable","type":"function"}';

    /// @notice Generate Merkl toggleOperator JSON for SV0
    function generateSv0() public {
        Vault vault = Vault(payable(VAULT));
        address subvault = vault.subvaultAt(0);
        require(subvault != address(0), "Subvault address not set");

        console.log("=== Generating Merkl toggleOperator ===");
        console.log("Subvault:", subvault);
        console.log("Curator:", curator);
        console.log("Merkl Distributor:", Constants.MERKL_DISTRIBUTOR);

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // toggleOperator(address user, address operator) — both params locked
        bytes memory data = abi.encodeWithSelector(0xbdac7ca3, subvault, curator);

        // Bitmask: selector locked, both address params locked
        bytes memory calldataBitmask = abi.encodePacked(
            bytes4(0), // placeholder — makeBitmask sets selector to 0xFFFFFFFF
            bytes32(type(uint256).max), // user locked
            bytes32(type(uint256).max)  // operator locked
        );

        bytes memory bitmask = ProofLibrary.makeBitmask(
            true,  // who (caller = curator)
            true,  // where (target = merkl distributor)
            true,  // value (= 0)
            true,  // selector locked
            calldataBitmask
        );

        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](1);
        leaves[0] = ProofLibrary.makeVerificationPayload(
            $.bitmaskVerifier,
            curator,
            Constants.MERKL_DISTRIBUTOR,
            0,
            data,
            bitmask
        );

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        // Build proper description JSON matching ABILibrary pattern
        ParameterLibrary.Parameter[] memory innerParams = ParameterLibrary.build("user", Strings.toHexString(subvault));
        innerParams = ParameterLibrary.add(innerParams, "operator", Strings.toHexString(curator));

        string[] memory descriptions = new string[](1);
        descriptions[0] = JsonLibrary.toJson(
            string(
                abi.encodePacked(
                    "IMerklDistributor(",
                    Strings.toHexString(Constants.MERKL_DISTRIBUTOR),
                    ").toggleOperator(subvault, curator)"
                )
            ),
            TOGGLE_OPERATOR_ABI,
            ParameterLibrary.build(
                Strings.toHexString(curator),
                Strings.toHexString(Constants.MERKL_DISTRIBUTOR),
                "0"
            ),
            innerParams
        );

        ProofLibrary.storeProofs("monad:tqMON:prod:sv0:merklClaim", merkleRoot, leavesWithProofs, descriptions);

        console.log("Merkl JSON generated, ops:", leavesWithProofs.length, "root:", vm.toString(merkleRoot));
    }
}
