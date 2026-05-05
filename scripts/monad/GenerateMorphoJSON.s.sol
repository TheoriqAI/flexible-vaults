// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";
import "../common/protocols/MorphoLibrary.sol";
import "../common/ArraysLibrary.sol";

/// @notice Script to generate Morpho market operations JSON files for tqMON subvaults
/// @dev Run with: forge script scripts/monad/GenerateMorphoJSON.s.sol --sig "generateSv0()" --via-ir --rpc-url https://rpc.monad.xyz
contract GenerateMorphoJSON is Script, Test {
    address public constant VAULT = 0x799d2847cF8Dfcb4f17ec28737f17C0E82Eb445c;
    address public curator = 0x5FFA51F64Bc40c5af3a435A95e9616cc2Df9F01B;

    // Morpho USDC supply markets
    bytes32 public constant MARKET_1 = 0x9e8441e7af65860feac831ebc117473e3033321abf528ebc8fbde1eeaaa3a626;
    bytes32 public constant MARKET_2 = 0x647f2acdadd47ed0fad3ef826e3513fd7fdf9328b0c1f24b8c762c6d79511bf6;
    bytes32 public constant MARKET_3 = 0x2761e7fe2dc3b712a7cf6d46286abc26864a65767d823c32ca554fa4ba309c6b;

    /// @notice Generate Morpho JSON for sv0 with all 3 USDC supply markets
    function generateSv0() public {
        Vault vault = Vault(payable(VAULT));
        address subvault = vault.subvaultAt(0);

        bytes32[] memory marketIds = new bytes32[](3);
        marketIds[0] = MARKET_1;
        marketIds[1] = MARKET_2;
        marketIds[2] = MARKET_3;

        generateJSON("monad:tqMON:prod:sv0:morphoOps", subvault, curator, marketIds);
    }

    /// @notice Core generation logic
    function generateJSON(
        string memory title,
        address subvault,
        address caller,
        bytes32[] memory marketIds
    ) internal {
        require(subvault != address(0), "Subvault address not set");
        require(marketIds.length > 0, "No market IDs provided");

        console.log("=== Generating Morpho Operations JSON ===");
        console.log("Subvault:", subvault);
        console.log("Curator:", caller);
        console.log("Number of markets:", marketIds.length);
        console.log("");

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        uint256 maxLeaves = marketIds.length * 50;
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](maxLeaves);
        uint256 iterator = 0;

        for (uint256 i = 0; i < marketIds.length; i++) {
            console.log("Processing market:", vm.toString(marketIds[i]));

            MorphoLibrary.Info memory info = MorphoLibrary.Info({
                marketId: marketIds[i],
                morpho: Constants.MORPHO,
                subvault: subvault,
                curator: caller
            });

            IMorpho.MarketParams memory params = IMorpho(Constants.MORPHO).idToMarketParams(marketIds[i]);
            console.log("  Loan token:", params.loanToken);
            console.log("  Collateral token:", params.collateralToken);

            iterator = ArraysLibrary.insert(
                leaves,
                MorphoLibrary.getMorphoProofs($.bitmaskVerifier, info),
                iterator
            );
        }

        assembly {
            mstore(leaves, iterator)
        }

        console.log("");
        console.log("Total operations:", iterator);

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        string[] memory descriptions = new string[](maxLeaves);
        iterator = 0;

        for (uint256 i = 0; i < marketIds.length; i++) {
            MorphoLibrary.Info memory info = MorphoLibrary.Info({
                marketId: marketIds[i],
                morpho: Constants.MORPHO,
                subvault: subvault,
                curator: caller
            });

            iterator = ArraysLibrary.insert(
                descriptions,
                MorphoLibrary.getMorphoDescriptions(info),
                iterator
            );
        }

        assembly {
            mstore(descriptions, iterator)
        }

        ProofLibrary.storeProofs(title, merkleRoot, leavesWithProofs, descriptions);

        console.log("");
        console.log("=== Generation Complete ===");
        console.log("JSON file:", string(abi.encodePacked("./scripts/jsons/", title, ".json")));
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations:", leavesWithProofs.length);
    }
}
