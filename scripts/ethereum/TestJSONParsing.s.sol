// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

contract TestJSONParsing is Script, Test {
    function run() external {
        string memory filePath = "./scripts/jsons/ethereum:tqETH:preprod:sv5:uniswapV3-lean.json";
        console.log("Reading file:", filePath);

        string memory jsonString = vm.readFile(filePath);
        console.log("File length:", bytes(jsonString).length);

        // Count operations by counting verificationType occurrences
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

        console.log("Total operations found:", count);

        // The JSON is wrapped in quotes - let's unwrap it
        console.log("\nJSON starts with quote:", bytes(jsonString)[0] == bytes1('"'));

        // Try to parse as string first to unwrap
        string memory unwrappedJson;
        try vm.parseJsonString(jsonString, "$") returns (string memory s) {
            unwrappedJson = s;
            console.log("Successfully unwrapped JSON");
            console.log("Unwrapped length:", bytes(unwrappedJson).length);
        } catch {
            console.log("Failed to unwrap, using original");
            unwrappedJson = jsonString;
        }

        // Now try to extract from unwrapped JSON
        console.log("\nTrying to extract first operation from unwrapped JSON:");
        uint256 vtValue = vm.parseJsonUint(unwrappedJson, ".merkle_proofs[0].verificationType");
        console.log("Verification type value:", vtValue);
    }
}
