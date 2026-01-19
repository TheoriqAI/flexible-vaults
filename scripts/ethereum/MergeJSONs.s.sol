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

        // Extract description - preserve the full JSON object if it exists
        string memory description;

        // First check if description is a nested object (has .description.description)
        // If so, extract the entire description object as raw JSON to preserve abi, parameters, etc.
        try vm.parseJsonString(jsonString, string(abi.encodePacked(basePath, ".description.description"))) returns (string memory) {
            // It's a nested object - extract the whole thing as raw JSON
            description = _extractRawJsonObject(jsonString, basePath, ".description");
        } catch {
            // It's a simple string - just get the string value
            description = string(abi.encodePacked('"', vm.parseJsonString(jsonString, string(abi.encodePacked(basePath, ".description"))), '"'));
        }

        // Store (proofs will be regenerated, so we leave them empty)
        allLeaves[targetIndex] = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType(vt),
            verificationData: verificationData,
            proof: new bytes32[](0)
        });

        allDescriptions[targetIndex] = description;
    }

    /// @notice Extract a raw JSON object from a JSON string at a given path
    /// @dev This manually parses the JSON to extract the object with all nested content
    function _extractRawJsonObject(
        string memory jsonString,
        string memory basePath,
        string memory fieldPath
    ) private view returns (string memory) {
        // Build the full path to search for
        string memory searchKey = string(abi.encodePacked('"description":'));
        bytes memory jsonBytes = bytes(jsonString);
        bytes memory searchBytes = bytes(searchKey);

        // Find the index position in the original JSON
        // We need to find the nth occurrence based on basePath index
        uint256 proofIndex = _parseIndexFromPath(basePath);

        // Find the nth "description" key that's part of a merkle_proof entry
        uint256 occurrenceCount = 0;
        uint256 startPos = 0;

        for (uint256 i = 0; i < jsonBytes.length - searchBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < searchBytes.length && found; j++) {
                if (jsonBytes[i + j] != searchBytes[j]) {
                    found = false;
                }
            }
            if (found) {
                // Check if this is inside a merkle_proofs entry by looking for "verificationType" before it
                if (_isInMerkleProof(jsonBytes, i)) {
                    if (occurrenceCount == proofIndex) {
                        startPos = i + searchBytes.length;
                        break;
                    }
                    occurrenceCount++;
                }
            }
        }

        // Skip whitespace
        while (startPos < jsonBytes.length && (jsonBytes[startPos] == ' ' || jsonBytes[startPos] == '\n' || jsonBytes[startPos] == '\t')) {
            startPos++;
        }

        // Now extract the JSON object (handle nested braces)
        if (jsonBytes[startPos] == '{') {
            uint256 braceCount = 1;
            uint256 endPos = startPos + 1;

            while (endPos < jsonBytes.length && braceCount > 0) {
                if (jsonBytes[endPos] == '{') braceCount++;
                else if (jsonBytes[endPos] == '}') braceCount--;
                endPos++;
            }

            // Extract the substring
            bytes memory result = new bytes(endPos - startPos);
            for (uint256 i = 0; i < endPos - startPos; i++) {
                result[i] = jsonBytes[startPos + i];
            }
            return string(result);
        }

        // Fallback: if it's a simple string, wrap it
        revert("Expected JSON object for description");
    }

    function _parseIndexFromPath(string memory path) private pure returns (uint256) {
        // Parse index from ".merkle_proofs[X]"
        bytes memory pathBytes = bytes(path);
        uint256 start = 0;
        uint256 end = 0;

        for (uint256 i = 0; i < pathBytes.length; i++) {
            if (pathBytes[i] == '[') start = i + 1;
            if (pathBytes[i] == ']') end = i;
        }

        uint256 result = 0;
        for (uint256 i = start; i < end; i++) {
            result = result * 10 + (uint8(pathBytes[i]) - 48);
        }
        return result;
    }

    function _isInMerkleProof(bytes memory json, uint256 pos) private pure returns (bool) {
        // Look backwards for "verificationType" to confirm we're in a merkle_proof entry
        bytes memory marker = bytes("verificationType");

        // Search backwards up to 500 chars
        uint256 searchStart = pos > 500 ? pos - 500 : 0;

        for (uint256 i = pos; i > searchStart; i--) {
            if (json[i] == '{') {
                // Found opening brace, check if verificationType follows
                for (uint256 j = i; j < pos && j < i + 100; j++) {
                    bool found = true;
                    for (uint256 k = 0; k < marker.length && found && j + k < pos; k++) {
                        if (json[j + k] != marker[k]) found = false;
                    }
                    if (found) return true;
                }
            }
        }
        return false;
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
