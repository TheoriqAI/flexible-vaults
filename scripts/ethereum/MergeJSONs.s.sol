// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";

/// @notice Script to merge multiple JSON files with merkle proofs into a single combined JSON
/// @dev This reads existing JSON files, extracts all operations, regenerates a single merkle tree
contract MergeJSONs is Script, Test {
    
    /// @notice Merge preprod subvault 5 UniswapV3 and V4 JSONs
    function mergePreProdSv5UniswapV3AndV4() external {
        string[] memory files = new string[](2);
        files[0] = "ethereum:tqETH:preprod:sv5:uniswapV3-lean";
        files[1] = "ethereum:tqETH:preprod:sv5:uniswapV4-lean";
        
        string memory outputTitle = "ethereum:tqETH:preprod:sv5:uniswapV3+V4-lean";
        
        merge(files, outputTitle);
    }
    
    /// @notice General-purpose function to merge any set of JSON files
    /// @param inputTitles Array of JSON file titles (without .json extension)
    /// @param outputTitle Title for the merged output file
    function merge(string[] memory inputTitles, string memory outputTitle) public {
        console.log("=== Merging JSON Files ===");
        console.log("Number of files to merge:", inputTitles.length);
        console.log("");
        
        // Collect all operations
        IVerifier.VerificationPayload[] memory allLeaves = new IVerifier.VerificationPayload[](500);
        string[] memory allDescriptions = new string[](500);
        uint256 totalOps = 0;
        
        // Process each file
        for (uint256 i = 0; i < inputTitles.length; i++) {
            (uint256 opsAdded) = _processFile(inputTitles[i], allLeaves, allDescriptions, totalOps, i + 1);
            totalOps += opsAdded;
        }
        
        // Resize arrays to actual size
        assembly {
            mstore(allLeaves, totalOps)
            mstore(allDescriptions, totalOps)
        }
        
        console.log("Total operations collected:", totalOps);
        console.log("");
        console.log("Generating new merkle tree with ALL operations...");
        
        // Generate NEW merkle tree with all combined operations
        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(allLeaves);
        
        // Store the merged file
        ProofLibrary.storeProofs(outputTitle, merkleRoot, leavesWithProofs, allDescriptions);
        
        console.log("");
        console.log("=== Merge Complete ===");
        console.log("Output file:", string(abi.encodePacked("./scripts/jsons/", outputTitle, ".json")));
        console.log("NEW Merkle root:", vm.toString(merkleRoot));
        console.log("Total operations:", totalOps);
        console.log("");
        console.log("IMPORTANT: This is a NEW merkle root that includes ALL operations from all files.");
        console.log("You must set this NEW merkle root on-chain: verifier.setMerkleRoot(", vm.toString(merkleRoot), ")");
        console.log("All proofs have been regenerated for the combined merkle tree.");
    }
    
    function _processFile(
        string memory fileTitle,
        IVerifier.VerificationPayload[] memory allLeaves,
        string[] memory allDescriptions,
        uint256 startIndex,
        uint256 fileNum
    ) private returns (uint256 opsAdded) {
        string memory filePath = string(abi.encodePacked("./scripts/jsons/", fileTitle, ".json"));
        console.log("Reading file", fileNum, ":", filePath);
        
        // Read the JSON file
        string memory jsonString = vm.readFile(filePath);
        
        // Parse to get count first
        uint256 opsCount = _countOpsInFile(jsonString);
        console.log("  Operations in this file:", opsCount);
        
        // Extract each operation
        for (uint256 j = 0; j < opsCount; j++) {
            _extractOp(jsonString, j, allLeaves, allDescriptions, startIndex + j);
        }
        
        console.log("");
        return opsCount;
    }
    
    function _countOpsInFile(string memory jsonString) private pure returns (uint256) {
        // Count operations by counting "verificationType" occurrences
        bytes memory jsonBytes = bytes(jsonString);
        uint256 count = 0;
        bytes memory needle = bytes("verificationType");

        for (uint256 i = 0; i <= jsonBytes.length - needle.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < needle.length && found; j++) {
                if (jsonBytes[i + j] != needle[j]) {
                    found = false;
                }
            }
            if (found) {
                count++;
            }
        }

        return count;
    }
    
    function _extractOp(
        string memory jsonString,
        uint256 index,
        IVerifier.VerificationPayload[] memory allLeaves,
        string[] memory allDescriptions,
        uint256 targetIndex
    ) private view {
        string memory basePath = string(abi.encodePacked(".merkle_proofs[", vm.toString(index), "]"));
        
        // Extract verificationType
        bytes memory vtData = vm.parseJson(jsonString, string(abi.encodePacked(basePath, ".verificationType")));
        uint8 vt = abi.decode(vtData, (uint8));
        
        // Extract verificationData (as hex string)
        bytes memory vdData = vm.parseJson(jsonString, string(abi.encodePacked(basePath, ".verificationData")));
        bytes memory verificationData = abi.decode(vdData, (bytes));
        
        // Extract description
        // Always try nested format first (Aave/Pendle have .description.description)
        bytes memory nestedDescData;
        string memory description;
        bool foundNested = false;

        // Try to parse nested format
        try vm.parseJsonString(jsonString, string(abi.encodePacked(basePath, ".description.description"))) returns (string memory nested) {
            description = nested;
            foundNested = true;
        } catch {
            // Not nested, try simple format
        }

        // If nested format didn't work, try simple string format
        if (!foundNested) {
            description = vm.parseJsonString(jsonString, string(abi.encodePacked(basePath, ".description")));
        }
        
        // Store (proofs will be regenerated, so we leave them empty)
        allLeaves[targetIndex] = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType(vt),
            verificationData: verificationData,
            proof: new bytes32[](0)
        });
        
        allDescriptions[targetIndex] = description;
    }

    /// @notice Helper function to try decoding bytes as string
    /// @return success Whether decoding succeeded
    /// @return result The decoded string if successful
    function _tryDecodeString(bytes memory data) private pure returns (bool success, string memory result) {
        // If data length is too short, it can't be a valid string
        if (data.length < 32) {
            return (false, "");
        }

        // Try to decode as string - if the first word is a reasonable offset (0x20)
        // and the string length is reasonable, it's likely a string
        uint256 offset;
        assembly {
            offset := mload(add(data, 32))
        }

        // Simple heuristic: if offset is 0x20 (32), it's likely a simple ABI-encoded string
        if (offset == 32) {
            return (true, abi.decode(data, (string)));
        }

        // Otherwise, it's likely a nested object
        return (false, "");
    }
}
