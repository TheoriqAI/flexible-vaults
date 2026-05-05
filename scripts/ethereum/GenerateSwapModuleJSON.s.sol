// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";
import "../common/protocols/SwapModuleLibrary.sol";
import "../common/ArraysLibrary.sol";

/// @notice Generic script to generate SwapModule (pushAssets/pullAssets) JSON files
/// @dev Reusable for any subvault + swap module combination
/// @dev Run with: forge script scripts/ethereum/GenerateSwapModuleJSON.s.sol --sig "generatePreProdWithSwapModule(uint256,address)" 4 <SWAP_MODULE_ADDR> --via-ir --rpc-url https://rpc.mevblocker.io
contract GenerateSwapModuleJSON is Script, Test {
    address public preProdCurator = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec;
    address public preProdExecutor = 0xfc5c96303F353c314e468681899C35F424246eBe;
    address public prodCurator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;

    address public constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address public constant VAULT_PREPROD = 0x2669a8B27B6f957ddb92Dc0ebdec1f112E6079E4;

    /// @notice Generate SwapModule JSON for pre-prod vault with given subvault index and swap module
    /// @param subvaultIndex The subvault index (e.g., 4)
    /// @param swapModule The swap module address for this subvault
    function generatePreProdWithSwapModule(uint256 subvaultIndex, address swapModule) public {
        Vault vault = Vault(payable(VAULT_PREPROD));
        address subvault = vault.subvaultAt(subvaultIndex);

        string memory title = string(
            abi.encodePacked("ethereum:tqETH:preprod:sv", vm.toString(subvaultIndex), ":swapModule")
        );
        generateJSON(title, subvault, swapModule, preProdCurator);
    }

    /// @notice Generate SwapModule JSON for prod vault with given subvault index and swap module
    /// @param subvaultIndex The subvault index
    /// @param swapModule The swap module address for this subvault
    function generateProdWithSwapModule(uint256 subvaultIndex, address swapModule) public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(subvaultIndex);

        string memory title = string(
            abi.encodePacked("ethereum:tqETH:prod:sv", vm.toString(subvaultIndex), ":swapModule")
        );
        generateJSON(title, subvault, swapModule, prodCurator);
    }

    /// @notice Get SwapModule config with standard asset set: WETH, wstETH, USDC, USDT, USDE, sUSDe
    /// @param subvault The subvault address
    /// @param swapModule The swap module address
    /// @param caller The caller address (curator)
    /// @return SwapModule configuration
    function getSwapModuleConfig(address subvault, address swapModule, address caller)
        internal
        pure
        returns (SwapModuleLibrary.Info memory)
    {
        address[] memory curators = new address[](1);
        curators[0] = caller;

        return SwapModuleLibrary.Info({
            subvault: subvault,
            subvaultName: "swapModule",
            swapModule: swapModule,
            curators: curators,
            assets: ArraysLibrary.makeAddressArray(
                abi.encode(
                    Constants.WETH,
                    Constants.WSTETH,
                    Constants.USDC,
                    Constants.USDT,
                    Constants.USDE,
                    Constants.SUSDE
                )
            )
        });
    }

    /// @notice Core generation logic - produces full JSON with ABIs
    function generateJSON(string memory title, address subvault, address swapModule, address caller) internal {
        require(subvault != address(0), "Subvault address not set");

        console.log("=== Generating SwapModule Operations JSON ===");
        console.log("Subvault:", subvault);
        console.log("SwapModule:", swapModule);
        console.log("Caller:", caller);
        console.log("");

        SwapModuleLibrary.Info memory info = getSwapModuleConfig(subvault, swapModule, caller);
        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Generate proofs
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](100);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            SwapModuleLibrary.getSwapModuleProofs($.bitmaskVerifier, info),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        // Generate full descriptions (with ABIs)
        string[] memory descriptions = new string[](100);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            SwapModuleLibrary.getSwapModuleDescriptions(info),
            iterator
        );

        assembly {
            mstore(descriptions, iterator)
        }

        // Store full JSON
        ProofLibrary.storeProofs(title, merkleRoot, leavesWithProofs, descriptions);

        console.log("");
        console.log("=== Generation Complete ===");
        console.log("JSON file:", string(abi.encodePacked("./scripts/jsons/", title, ".json")));
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations:", leavesWithProofs.length);
    }

    /// @notice Generate SwapModule JSON for MULTIPLE callers (entries doubled)
    /// @param subvaultIndex The subvault index
    /// @param isProd true for prod vault, false for preprod vault
    /// @param swapModule The swap module address
    /// @param callers Array of caller addresses
    function generateWithSwapModuleMultiCaller(
        uint256 subvaultIndex,
        bool isProd,
        address swapModule,
        address[] memory callers
    ) public {
        address vaultAddress = isProd ? VAULT_PROD : VAULT_PREPROD;
        string memory env = isProd ? "prod" : "preprod";

        Vault vault = Vault(payable(vaultAddress));
        address subvault = vault.subvaultAt(subvaultIndex);

        string memory title = string(
            abi.encodePacked("ethereum:tqETH:", env, ":sv", vm.toString(subvaultIndex), ":swapModule")
        );

        require(subvault != address(0), "Subvault address not set");

        console.log("=== Generating SwapModule Operations JSON (Multi-Caller) ===");
        console.log("Environment:", env);
        console.log("Subvault:", subvault);
        console.log("SwapModule:", swapModule);
        console.log("Number of callers:", callers.length);
        console.log("");

        // SwapModuleLibrary.Info already supports multiple curators
        SwapModuleLibrary.Info memory info = SwapModuleLibrary.Info({
            subvault: subvault,
            subvaultName: "swapModule",
            swapModule: swapModule,
            curators: callers,  // Pass all callers
            assets: ArraysLibrary.makeAddressArray(
                abi.encode(
                    Constants.WETH,
                    Constants.WSTETH,
                    Constants.USDC,
                    Constants.USDT,
                    Constants.USDE,
                    Constants.SUSDE
                )
            )
        });

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Generate proofs
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](200);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            SwapModuleLibrary.getSwapModuleProofs($.bitmaskVerifier, info),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        // Generate descriptions
        string[] memory descriptions = new string[](200);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            SwapModuleLibrary.getSwapModuleDescriptions(info),
            iterator
        );

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

    /// @notice Generate SwapModule ops for preprod sv4 with BOTH curator and executor as callers
    /// @param swapModule The swap module address for sv4
    function generatePreProdSv4SwapModuleMultiCaller(address swapModule) public {
        address[] memory callers = new address[](2);
        callers[0] = preProdCurator;
        callers[1] = preProdExecutor;

        generateWithSwapModuleMultiCaller(4, false, swapModule, callers);
    }

    /// @notice Generate SwapModule JSON for prod SV2 with standard assets + EURC (same as sv3)
    /// @param swapModule The swap module address for sv2
    function generateProdSv2WithSwapModule(address swapModule) public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(2);

        string memory title = "prod/tqETH/sv2-swapModule";

        require(subvault != address(0), "Subvault address not set");

        console.log("=== Generating SwapModule Operations JSON (Prod SV2) ===");
        console.log("Subvault:", subvault);
        console.log("SwapModule:", swapModule);
        console.log("");

        address[] memory curators = new address[](1);
        curators[0] = prodCurator;

        SwapModuleLibrary.Info memory info = SwapModuleLibrary.Info({
            subvault: subvault,
            subvaultName: "swapModule",
            swapModule: swapModule,
            curators: curators,
            assets: ArraysLibrary.makeAddressArray(
                abi.encode(
                    Constants.WETH,
                    Constants.WSTETH,
                    Constants.USDC,
                    Constants.USDT,
                    Constants.USDE,
                    Constants.SUSDE,
                    Constants.EURC
                )
            )
        });

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](100);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            SwapModuleLibrary.getSwapModuleProofs($.bitmaskVerifier, info),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        string[] memory descriptions = new string[](100);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            SwapModuleLibrary.getSwapModuleDescriptions(info),
            iterator
        );

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

    /// @notice Generate SwapModule JSON for prod SV3 with standard assets
    /// @param swapModule The swap module address for sv3
    function generateProdSv3WithSwapModule(address swapModule) public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(3);

        string memory title = "prod/tqETH/sv3-swapModule";

        require(subvault != address(0), "Subvault address not set");

        console.log("=== Generating SwapModule Operations JSON (Prod SV3) ===");
        console.log("Subvault:", subvault);
        console.log("SwapModule:", swapModule);
        console.log("");

        address[] memory curators = new address[](1);
        curators[0] = prodCurator;

        SwapModuleLibrary.Info memory info = SwapModuleLibrary.Info({
            subvault: subvault,
            subvaultName: "swapModule",
            swapModule: swapModule,
            curators: curators,
            assets: ArraysLibrary.makeAddressArray(
                abi.encode(
                    Constants.WETH,
                    Constants.WSTETH,
                    Constants.USDC,
                    Constants.USDT,
                    Constants.USDE,
                    Constants.SUSDE
                )
            )
        });

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](100);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            SwapModuleLibrary.getSwapModuleProofs($.bitmaskVerifier, info),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        string[] memory descriptions = new string[](100);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            SwapModuleLibrary.getSwapModuleDescriptions(info),
            iterator
        );

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

    /// @notice Generate SwapModule JSON for prod SV4 with extended asset list (includes ETH + NUSD + Sierra)
    /// @param swapModule The swap module address for sv4
    function generateProdSv4WithSwapModule(address swapModule) public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(4);

        string memory title = "prod/tqETH/sv4-swapModule";

        require(subvault != address(0), "Subvault address not set");

        console.log("=== Generating SwapModule Operations JSON (Prod SV4 Extended) ===");
        console.log("Subvault:", subvault);
        console.log("SwapModule:", swapModule);
        console.log("");

        address[] memory curators = new address[](1);
        curators[0] = prodCurator;

        SwapModuleLibrary.Info memory info = SwapModuleLibrary.Info({
            subvault: subvault,
            subvaultName: "swapModule",
            swapModule: swapModule,
            curators: curators,
            assets: ArraysLibrary.makeAddressArray(
                abi.encode(
                    Constants.ETH,
                    Constants.WETH,
                    Constants.WSTETH,
                    Constants.USDC,
                    Constants.USDT,
                    Constants.USDE,
                    Constants.SUSDE,
                    Constants.NUSD,
                    Constants.SIERRA,
                    Constants.APXUSD
                )
            )
        });

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Generate proofs
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](100);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            SwapModuleLibrary.getSwapModuleProofs($.bitmaskVerifier, info),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        // Generate descriptions
        string[] memory descriptions = new string[](100);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            SwapModuleLibrary.getSwapModuleDescriptions(info),
            iterator
        );

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
