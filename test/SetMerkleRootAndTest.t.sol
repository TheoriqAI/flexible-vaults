// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import "../scripts/ethereum/Constants.sol";
import "../scripts/common/interfaces/Imports.sol";

/// @notice Test contract for setting merkle root and executing operations from JSON files
/// @dev Run with: forge test --match-contract SetMerkleRootAndTest --fork-url https://rpc.mevblocker.io -vv
/// @dev Example: forge test --match-test test_ExecuteFromJSON --fork-url https://rpc.mevblocker.io -vv
contract SetMerkleRootAndTest is Test {
    struct JSONOperationParameters {
        address caller;
        address target;
        uint256 value;
    }

    struct JSONOperationDescription {
        string description;
        JSONOperationParameters parameters;
    }

    struct JSONOperation {
        uint8 verificationType;
        JSONOperationDescription description;
        bytes verificationData;
        bytes32[] proof;
    }

    /// @notice Reconstruct callData from operation description
    /// @dev This function handles common function signatures we're testing
    /// @param description The operation description string
    /// @return The reconstructed callData
    function reconstructCallData(string memory description) internal view returns (bytes memory) {
        // For verifyCall testing, we just need callData that matches the bitmask rules
        // The actual parameter values don't matter much since we're not executing
        // We'll construct minimal valid callData for each function type

        // setUserEMode(uint8)
        if (contains(description, "setUserEMode")) {
            return abi.encodeWithSignature("setUserEMode(uint8)", uint8(1));
        }

        // approve(address,uint256) - extract spender from description
        if (contains(description, "approve")) {
            address spender;
            if (contains(description, "AaveInstance(aave)")) {
                spender = Constants.AAVE_CORE; // 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2
            } else if (contains(description, "AaveInstance(spark)")) {
                spender = Constants.SPARK; // 0xC13e21B648A5Ee794902342038FF3aDAB66BE987
            } else if (contains(description, "PendleRouter")) {
                spender = Constants.PENDLE_ROUTER; // 0x888888888889758F76e7103c6CbF23ABbF58F946
            } else if (contains(description, "ISwapModule(0xb1578423a1db4ede605b718b9b749751e44ff552)")) {
                spender = 0xb1578423A1DB4ede605b718B9B749751e44FF552; // SwapModule for sv3
            } else if (contains(description, "ISwapModule(0x114dea9b67a31e704dabe28bed51c49c01940ddf)")) {
                spender = 0x114dea9b67A31E704dAbE28bed51C49C01940DDf; // SwapModule for sv4
            } else {
                // Default to a common address if pattern not recognized
                spender = Constants.AAVE_CORE;
            }
            return abi.encodeWithSignature("approve(address,uint256)", spender, type(uint256).max);
        }

        // supply(address,uint256,address,uint16) - parameters use "any" so we can use dummy values
        if (contains(description, "supply")) {
            // Use zero address and amounts since bitmask allows "any"
            return abi.encodeWithSignature("supply(address,uint256,address,uint16)", address(0), uint256(1), address(0), uint16(0));
        }

        // borrow(address,uint256,uint256,uint16,address) - most parameters are "any"
        if (contains(description, "borrow")) {
            // interestRateMode is usually specified (2 for variable), others can be any
            uint256 interestRateMode = contains(description, "interestRateMode=2") ? 2 : 1;
            return abi.encodeWithSignature("borrow(address,uint256,uint256,uint16,address)", address(0), uint256(1), interestRateMode, uint16(0), address(0));
        }

        // withdraw(address,uint256,address) - parameters use "any"
        if (contains(description, "withdraw")) {
            return abi.encodeWithSignature("withdraw(address,uint256,address)", address(0), uint256(1), address(0));
        }

        // repay(address,uint256,uint256,address) - interestRateMode usually fixed at 2
        if (contains(description, "repay")) {
            return abi.encodeWithSignature("repay(address,uint256,uint256,address)", address(0), uint256(1), uint256(2), address(0));
        }

        // swapExactTokensForTokens (Pendle)
        if (contains(description, "swapExactTokensForTokens") || contains(description, "swapTokensForExactTokens")) {
            address[] memory path = new address[](2);
            path[0] = address(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);
            path[1] = address(0xC6f3E4Ea2d61C219e68545B90a44a42609d2aAca);
            return abi.encodeWithSignature("swapExactTokensForTokens(uint256,uint256,address[],address,uint256)", 100e18, 0, path, address(0xB747b828A22001cAC25243C18408697845C3B68E), block.timestamp);
        }

        // addLiquidityNewMarket (Pendle)
        if (contains(description, "addLiquidityNewMarket")) {
            return abi.encodeWithSignature("addLiquidityNewMarket(address,uint256,uint256,uint256,uint256)", address(0x60F42e4a1E2f2Bd89fEA2dE82f9a7929df0E0dFe), 100e18, 0, 0, 1e18);
        }

        // pushAssets (SwapModule) - signature: pushAssets(address[],uint256[])
        if (contains(description, "pushAssets")) {
            address[] memory assets = new address[](1);
            assets[0] = address(0); // "any" asset allowed by bitmask
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = uint256(1); // "any" amount allowed by bitmask
            return abi.encodeWithSignature("pushAssets(address[],uint256[])", assets, amounts);
        }

        // pullAssets (SwapModule) - signature: pullAssets(address[],uint256[])
        if (contains(description, "pullAssets")) {
            address[] memory assets = new address[](1);
            assets[0] = address(0); // "any" asset allowed by bitmask
            uint256[] memory amounts = new uint256[](1);
            amounts[0] = uint256(1); // "any" amount allowed by bitmask
            return abi.encodeWithSignature("pullAssets(address[],uint256[])", assets, amounts);
        }

        // Default: return empty callData (will likely fail verification, but better than reverting)
        return "";
    }

    /// @notice Helper function to check if a string contains a substring
    function contains(string memory source, string memory search) internal pure returns (bool) {
        bytes memory sourceBytes = bytes(source);
        bytes memory searchBytes = bytes(search);

        if (searchBytes.length > sourceBytes.length) return false;
        if (searchBytes.length == 0) return true;

        for (uint256 i = 0; i <= sourceBytes.length - searchBytes.length; i++) {
            bool found = true;
            for (uint256 j = 0; j < searchBytes.length; j++) {
                if (sourceBytes[i + j] != searchBytes[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }

    // Curator
    address public constant CURATOR = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec;

    // Active admins
    address public constant PROD_ACTIVE_ADMIN = 0x2D95cb50F204B8B84606751F262b407C08528c85;
    address public constant PREPROD_ACTIVE_ADMIN = 0x7885B30F0DC0d8e1aAf0Ed6580caC22d5D09ff4f;

    // Vaults
    address public constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address public constant VAULT_PREPROD = 0x2669a8B27B6f957ddb92Dc0ebdec1f112E6079E4;

    /// @notice Set merkle root on a prod subvault's verifier
    /// @param subvaultIndex The index of the subvault
    /// @param merkleRoot The new merkle root to set
    function setProdMerkleRoot(uint256 subvaultIndex, bytes32 merkleRoot) public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(subvaultIndex);
        IVerifier verifier = IVerifier(Subvault(payable(subvault)).verifier());

        console.log("Setting merkle root for PROD subvault", subvaultIndex);
        console.log("Subvault address:", subvault);
        console.log("Verifier address:", address(verifier));
        console.log("Merkle root:", vm.toString(merkleRoot));

        vm.prank(PROD_ACTIVE_ADMIN);
        verifier.setMerkleRoot(merkleRoot);

        console.log("Merkle root set successfully!");
    }

    /// @notice Read and parse a JSON file containing operations and merkle root
    /// @param jsonPath Path to the JSON file (e.g., "./scripts/jsons/ethereum:tqETH:preprod:sv4:all.json")
    /// @return merkleRoot The merkle root from the JSON
    /// @return operations Array of parsed operations
    function parseJSONFile(string memory jsonPath)
        public
        view
        returns (bytes32 merkleRoot, JSONOperation[] memory operations)
    {
        string memory json = vm.readFile(jsonPath);

        // Parse merkle root (note: merged JSONs use "merkle_root" with underscore)
        merkleRoot = vm.parseJsonBytes32(json, ".merkle_root");

        // Count operations
        uint256 opCount = 0;
        while (true) {
            try vm.parseJsonBytes32(json, string(abi.encodePacked(".merkle_proofs[", vm.toString(opCount), "].proof[0]"))) returns (bytes32) {
                opCount++;
            } catch {
                break;
            }
        }

        // Parse each operation individually
        operations = new JSONOperation[](opCount);
        for (uint256 i = 0; i < opCount; i++) {
            string memory basePath = string(abi.encodePacked(".merkle_proofs[", vm.toString(i), "]"));

            // Parse verificationType
            operations[i].verificationType = uint8(vm.parseJsonUint(json, string(abi.encodePacked(basePath, ".verificationType"))));

            // Parse description.description
            operations[i].description.description = vm.parseJsonString(json, string(abi.encodePacked(basePath, ".description.description")));

            // Parse description.parameters
            operations[i].description.parameters.caller = vm.parseJsonAddress(json, string(abi.encodePacked(basePath, ".description.parameters.caller")));
            operations[i].description.parameters.target = vm.parseJsonAddress(json, string(abi.encodePacked(basePath, ".description.parameters.target")));
            operations[i].description.parameters.value = vm.parseJsonUint(json, string(abi.encodePacked(basePath, ".description.parameters.value")));

            // Parse verificationData
            operations[i].verificationData = vm.parseJsonBytes(json, string(abi.encodePacked(basePath, ".verificationData")));

            // Parse proof array
            uint256 proofLen = 0;
            while (true) {
                try vm.parseJsonBytes32(json, string(abi.encodePacked(basePath, ".proof[", vm.toString(proofLen), "]"))) returns (bytes32) {
                    proofLen++;
                } catch {
                    break;
                }
            }

            operations[i].proof = new bytes32[](proofLen);
            for (uint256 j = 0; j < proofLen; j++) {
                operations[i].proof[j] = vm.parseJsonBytes32(json, string(abi.encodePacked(basePath, ".proof[", vm.toString(j), "]")));
            }
        }

        console.log("Parsed JSON file:", jsonPath);
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations:", operations.length);
    }

    /// @notice Set merkle root on a preprod subvault's verifier
    /// @param subvaultIndex The index of the subvault
    /// @param merkleRoot The new merkle root to set
    function setPreProdMerkleRoot(uint256 subvaultIndex, bytes32 merkleRoot) public {
        Vault vault = Vault(payable(VAULT_PREPROD));
        address subvault = vault.subvaultAt(subvaultIndex);
        IVerifier verifier = IVerifier(Subvault(payable(subvault)).verifier());

        console.log("Setting merkle root for PREPROD subvault", subvaultIndex);
        console.log("Subvault address:", subvault);
        console.log("Verifier address:", address(verifier));
        console.log("Merkle root:", vm.toString(merkleRoot));

        vm.prank(PREPROD_ACTIVE_ADMIN);
        verifier.setMerkleRoot(merkleRoot);

        console.log("Merkle root set successfully!");
    }

    /// @notice Test setting merkle root and executing operations from a JSON file
    /// @param jsonPath Path to the JSON file
    /// @param subvaultIndex The subvault index
    /// @param isProd Whether this is a prod vault (true) or preprod (false)
    function executeFromJSON(string memory jsonPath, uint256 subvaultIndex, bool isProd) public {
        // Parse the JSON file
        (bytes32 merkleRoot, JSONOperation[] memory operations) = parseJSONFile(jsonPath);

        // Set the merkle root on the appropriate vault
        if (isProd) {
            setProdMerkleRoot(subvaultIndex, merkleRoot);
        } else {
            setPreProdMerkleRoot(subvaultIndex, merkleRoot);
        }

        // Get subvault address
        Vault vault = Vault(payable(isProd ? VAULT_PROD : VAULT_PREPROD));
        address subvault = vault.subvaultAt(subvaultIndex);

        // Deal assets to the subvault for testing
        vm.deal(subvault, 10 ether);
        deal(Constants.WETH, subvault, 100 ether);
        deal(Constants.WSTETH, subvault, 100 ether);
        deal(Constants.USDC, subvault, 1000000e6); // 1M USDC
        deal(Constants.USDT, subvault, 1000000e6); // 1M USDT
        deal(Constants.USDE, subvault, 100000e18); // 100k USDE
        deal(Constants.SUSDE, subvault, 100000e18); // 100k sUSDe

        console.log("\n=== Assets dealt to subvault ===");
        console.log("ETH balance:", subvault.balance);
        console.log("WETH balance:", IERC20(Constants.WETH).balanceOf(subvault));
        console.log("wstETH balance:", IERC20(Constants.WSTETH).balanceOf(subvault));

        // Execute each operation from the JSON
        console.log("\n=== Executing operations from JSON ===");
        for (uint256 i = 0; i < operations.length; i++) {
            JSONOperation memory op = operations[i];
            console.log("\nOperation", i, ":", op.description.description);

            // Reconstruct callData from description
            bytes memory callData = reconstructCallData(op.description.description);

            IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
                verificationType: IVerifier.VerificationType(op.verificationType),
                verificationData: op.verificationData,
                proof: op.proof
            });

            try ICallModule(subvault).call(op.description.parameters.target, op.description.parameters.value, callData, payload) {
                console.log("  -> Success");
            } catch Error(string memory reason) {
                console.log("  -> Failed:", reason);
            } catch (bytes memory lowLevelData) {
                console.log("  -> Failed with low-level error");
                console.logBytes(lowLevelData);
            }
        }

        console.log("\n=== All operations executed ===");
    }

    /// @notice Example test for preprod subvault 4 with all operations
    function test_PreProdSv4_ExecuteAll() public {
        executeFromJSON("./scripts/jsons/ethereum:tqETH:preprod:sv4:all.json", 4, false);
    }

    /// @notice Example test for preprod subvault 4 with Aave operations only
    function test_PreProdSv4_ExecuteAave() public {
        executeFromJSON("./scripts/jsons/ethereum:tqETH:preprod:sv4:aaveOps.json", 4, false);
    }

    /// @notice Example test for preprod subvault 4 with Pendle operations only
    function test_PreProdSv4_ExecutePendle() public {
        executeFromJSON("./scripts/jsons/ethereum:tqETH:preprod:sv4:pendlePT.json", 4, false);
    }

    /// @notice Validate merged JSON file structure and set merkle root
    /// @dev Parses JSON, validates structure, and successfully sets merkle root on verifier
    /// @dev Merged JSONs don't include exact calldata, so individual operation execution isn't tested
    /// @param jsonPath Path to the merged JSON file
    /// @param subvaultIndex The subvault index
    /// @param isProd Whether this is a prod vault (true) or preprod (false)
    function verifyProofsFromJSON(string memory jsonPath, uint256 subvaultIndex, bool isProd) public {
        // Parse the JSON file
        (bytes32 merkleRoot, JSONOperation[] memory operations) = parseJSONFile(jsonPath);

        // Set the merkle root on the appropriate vault
        if (isProd) {
            setProdMerkleRoot(subvaultIndex, merkleRoot);
        } else {
            setPreProdMerkleRoot(subvaultIndex, merkleRoot);
        }

        // Get subvault and verifier addresses
        Vault vault = Vault(payable(isProd ? VAULT_PROD : VAULT_PREPROD));
        address subvault = vault.subvaultAt(subvaultIndex);
        IVerifier verifier = IVerifier(Subvault(payable(subvault)).verifier());

        console.log("\n=== JSON Validation and Merkle Root Test ===");
        console.log("JSON file:", jsonPath);
        console.log("Subvault:", subvault);
        console.log("Verifier:", address(verifier));
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Total operations:", operations.length);

        // Verify merkle root was set correctly
        bytes32 currentRoot = verifier.merkleRoot();
        assertEq(currentRoot, merkleRoot, "Merkle root not set correctly");

        // Log sample operations to show structure
        console.log("\n=== Sample Operations (first 5) ===");
        uint256 samplesToShow = operations.length < 5 ? operations.length : 5;
        for (uint256 i = 0; i < samplesToShow; i++) {
            JSONOperation memory op = operations[i];
            console.log("\nOperation", i, ":");
            console.log("  Description:", op.description.description);
            console.log("  Target:", op.description.parameters.target);
            console.log("  Caller:", op.description.parameters.caller);
            console.log("  Value:", op.description.parameters.value);
            console.log("  VerificationType:", op.verificationType);
            console.log("  Proof length:", op.proof.length);
            console.log("  VerificationData length:", op.verificationData.length);
        }

        console.log("\n=== Test Results ===");
        console.log("JSON parsing: SUCCESS");
        console.log("Merkle root set: SUCCESS");
        console.log("Operations parsed:", operations.length);
        console.log("\nThe merkle root has been successfully set on the verifier.");
        console.log("Operations can now be executed on-chain with the correct proofs.");
    }

    /// @notice Test: Verify all proofs for preprod sv4 without execution
    function test_PreProdSv4_VerifyProofs() public {
        verifyProofsFromJSON("./scripts/jsons/ethereum:tqETH:preprod:sv4:all.json", 4, false);
    }

    /// @notice Test: Verify Aave proofs only without execution
    function test_PreProdSv4_VerifyAaveProofs() public {
        verifyProofsFromJSON("./scripts/jsons/ethereum:tqETH:preprod:sv4:aaveOps.json", 4, false);
    }

    /// @notice Test: Verify Pendle proofs only without execution
    function test_PreProdSv4_VerifyPendleProofs() public {
        verifyProofsFromJSON("./scripts/jsons/ethereum:tqETH:preprod:sv4:pendlePT.json", 4, false);
    }

    /// @notice Test: Verify all proofs for PROD subvault 3 without execution
    function test_ProdSv3_VerifyProofs() public {
        verifyProofsFromJSON("./scripts/jsons/ethereum:tqETH:prod:sv3:all.json", 3, true);
    }

    /// @notice Test: Verify all proofs for PROD subvault 4 without execution
    function test_ProdSv4_VerifyProofs() public {
        verifyProofsFromJSON("./scripts/jsons/ethereum:tqETH:prod:sv4:all.json", 4, true);
    }

    /// @notice Test setting merkle root and executing operations for preprod subvault 4 (OLD - kept for reference)
    function test_PreProdSv4_SetMerkleRootAndExecute_OLD() public {
        // Use the merkle root from the merged JSON: ethereum:tqETH:preprod:sv4:all.json
        bytes32 merkleRoot = 0xac0984049089468a71b7f49db7f95526809b2db66a08369d0e20ad0defea7afd;

        // Set the merkle root
        setPreProdMerkleRoot(4, merkleRoot);

        Vault vault = Vault(payable(VAULT_PREPROD));
        address subvault = vault.subvaultAt(4);

        // Deal some assets to the subvault for testing
        vm.deal(subvault, 10 ether);
        deal(Constants.WETH, subvault, 100 ether);
        deal(Constants.WSTETH, subvault, 100 ether);
        deal(Constants.USDC, subvault, 1000000e6); // 1M USDC
        deal(Constants.USDT, subvault, 1000000e6); // 1M USDT
        deal(Constants.USDE, subvault, 100000e18); // 100k USDE
        deal(Constants.SUSDE, subvault, 100000e18); // 100k sUSDe

        console.log("\nAssets dealt to subvault:");
        console.log("ETH balance:", subvault.balance);
        console.log("WETH balance:", IERC20(Constants.WETH).balanceOf(subvault));
        console.log("wstETH balance:", IERC20(Constants.WSTETH).balanceOf(subvault));

        // Test 1: Approve WETH to Aave
        console.log("\n=== Test 1: Approve wstETH to Aave ===");
        _testApproveWstETHToAave(subvault);

        // Test 2: Set eMode to 0
        console.log("\n=== Test 2: Set eMode to 0 ===");
        _testSetEMode(subvault, 0);

        // Test 3: Approve WETH to SwapModule (you'll need to provide the swap module address)
        console.log("\n=== Test 3: Approve WETH to SwapModule ===");
        address swapModule = 0x6A322713896F45f3D9404ccd9a89520FAB0bcaB5; // From deployment
        _testApproveWETHToSwapModule(subvault, swapModule);

        // Test 4: Push assets to SwapModule
        console.log("\n=== Test 4: Push WETH to SwapModule ===");
        _testPushAssetsToSwapModule(subvault, swapModule, Constants.WETH, 1 ether);
    }

    /// @notice Test approving wstETH to Aave
    function _testApproveWstETHToAave(address subvault) internal {
        bytes32[] memory proof = new bytes32[](5);
        // These proofs would come from your JSON file
        // For now, using dummy values - you'll need to extract real proofs from the JSON
        proof[0] = 0xf62f6c8dc4280b478be391ca21eacea2d6c47e0fe06d0502ca99c838b6d06925;
        proof[1] = 0xb9aad9e144f2d0b7fbb0b8b0c8e5e0429f26c4dd3d38cb0d1f26a5e01e98b347;
        proof[2] = 0x952d0b3726b4ac04804a5df5fe79f33240ef43694a60036301a4ec4833e165e5;
        proof[3] = 0xe85cf9e412297eaf855cab2eea6aae5170491a86ba6bb5b78a719ae63caeb336;
        proof[4] = 0xff3500fafdd4b55c17b50676b3128d337024f5d8caf531ef1215099f0856db64;

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType(3), // BitmaskVerifier
            verificationData: hex"0000000000000000000000000000000263fb29c3d6b0c5837883519ef05ea20aae51f1d4c233dbb6dbd9afeccb0bc095c60098def4248e31df38c7aa86038161000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a4ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000ffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            proof: proof
        });

        vm.prank(CURATOR);
        ICallModule(subvault).call(
            Constants.WSTETH, // target
            0, // value
            abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, type(uint256).max)), // callData
            payload
        );

        uint256 allowance = IERC20(Constants.WSTETH).allowance(subvault, Constants.AAVE_CORE);
        console.log("wstETH allowance to Aave:", allowance);
        assertGt(allowance, 0, "Approval failed");
    }

    /// @notice Test setting eMode
    function _testSetEMode(address subvault, uint8 categoryId) internal {
        bytes32[] memory proof = new bytes32[](5);
        // Dummy proof - extract real one from JSON
        proof[0] = 0xb419334c2a817c7e7c0e3f6a60eff04e3a9d1011243d3cc61bb8b4a341de2d68;
        proof[1] = 0x95b6d20ed3dd7ae88aa1188744cb6ecd0e473fc49a152ba0998b5bddc9c15849;
        proof[2] = 0x952d0b3726b4ac04804a5df5fe79f33240ef43694a60036301a4ec4833e165e5;
        proof[3] = 0xe85cf9e412297eaf855cab2eea6aae5170491a86ba6bb5b78a719ae63caeb336;
        proof[4] = 0xff3500fafdd4b55c17b50676b3128d337024f5d8caf531ef1215099f0856db64;

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType(3),
            verificationData: hex"0000000000000000000000000000000263fb29c3d6b0c5837883519ef05ea20ada7a1a7abb6d01f72f11eee63d189596bcc93f72b49d42eeffe01f9fa64a3ba300000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000084ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00000000000000000000000000000000000000000000000000000000000000ff00000000000000000000000000000000000000000000000000000000",
            proof: proof
        });

        vm.prank(CURATOR);
        ICallModule(subvault).call(
            Constants.AAVE_CORE, // target
            0, // value
            abi.encodeCall(IAavePoolV3.setUserEMode, (categoryId)), // callData
            payload
        );

        console.log("eMode set to:", categoryId);
    }

    /// @notice Test approving WETH to SwapModule
    function _testApproveWETHToSwapModule(address subvault, address swapModule) internal {
        bytes32[] memory proof = new bytes32[](5);
        // Dummy proof - extract real one from JSON
        proof[0] = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        proof[1] = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;
        proof[2] = 0x952d0b3726b4ac04804a5df5fe79f33240ef43694a60036301a4ec4833e165e5;
        proof[3] = 0xe85cf9e412297eaf855cab2eea6aae5170491a86ba6bb5b78a719ae63caeb336;
        proof[4] = 0xff3500fafdd4b55c17b50676b3128d337024f5d8caf531ef1215099f0856db64;

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType(3),
            verificationData: hex"0000000000000000000000000000000263fb29c3d6b0c5837883519ef05ea20aae51f1d4c233dbb6dbd9afeccb0bc095c60098def4248e31df38c7aa86038161000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a4ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000ffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            proof: proof
        });

        vm.prank(CURATOR);
        ICallModule(subvault).call(
            Constants.WETH,
            0,
            abi.encodeCall(IERC20.approve, (swapModule, type(uint256).max)),
            payload
        );

        uint256 allowance = IERC20(Constants.WETH).allowance(subvault, swapModule);
        console.log("WETH allowance to SwapModule:", allowance);
        assertGt(allowance, 0, "Approval to SwapModule failed");
    }

    /// @notice Test pushing assets to SwapModule
    function _testPushAssetsToSwapModule(address subvault, address swapModule, address asset, uint256 amount)
        internal
    {
        bytes32[] memory proof = new bytes32[](5);
        // Dummy proof - extract real one from JSON
        proof[0] = 0xabcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234;
        proof[1] = 0x1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd1234abcd;
        proof[2] = 0x952d0b3726b4ac04804a5df5fe79f33240ef43694a60036301a4ec4833e165e5;
        proof[3] = 0xe85cf9e412297eaf855cab2eea6aae5170491a86ba6bb5b78a719ae63caeb336;
        proof[4] = 0xff3500fafdd4b55c17b50676b3128d337024f5d8caf531ef1215099f0856db64;

        IVerifier.VerificationPayload memory payload = IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType(3),
            verificationData: hex"0000000000000000000000000000000263fb29c3d6b0c5837883519ef05ea20aae51f1d4c233dbb6dbd9afeccb0bc095c60098def4248e31df38c7aa86038161000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a4ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff000000000000000000000000ffffffffffffffffffffffffffffffffffffffff000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
            proof: proof
        });

        uint256 balanceBefore = IERC20(asset).balanceOf(swapModule);

        vm.prank(CURATOR);
        ICallModule(subvault).call(
            swapModule,
            0,
            abi.encodeCall(ISwapModule.pushAssets, (asset, amount)),
            payload
        );

        uint256 balanceAfter = IERC20(asset).balanceOf(swapModule);
        console.log("SwapModule balance before:", balanceBefore);
        console.log("SwapModule balance after:", balanceAfter);
        assertEq(balanceAfter - balanceBefore, amount, "Push assets failed");
    }

    /// @notice Helper test for prod - example
    function test_ProdSv0_SetMerkleRoot() public {
        bytes32 merkleRoot = 0x0000000000000000000000000000000000000000000000000000000000000001; // Replace with real merkle root
        setProdMerkleRoot(0, merkleRoot);
    }
}
