// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";
import "../common/protocols/NTTLibrary.sol";
import "../common/ArraysLibrary.sol";

/// @notice Script to generate NTT (Wormhole) bridge operations JSON files
/// @dev Run with: forge script scripts/ethereum/GenerateNTTBridgeJSON.s.sol --sig "generateProdSv3WETHToMonad(address)" --via-ir --rpc-url https://rpc.mevblocker.io 0x0C7cb4e1241F4B7Fd65DE59FDE5a6dBFf190fB20
contract GenerateNTTBridgeJSON is Script, Test {
    address public prodCurator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;
    address public preProdCurator = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec;

    address public constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address public constant VAULT_PREPROD = 0x2669a8B27B6f957ddb92Dc0ebdec1f112E6079E4;

    /// @notice Generate NTT bridge JSON for preProd SV5 WETH to Monad
    function generatePreProdSv5WETHToMonad(address targetSubvault) public {
        Vault vault = Vault(payable(VAULT_PREPROD));
        address subvault = vault.subvaultAt(5);
        require(subvault != address(0), "Subvault address not set");
        require(targetSubvault != address(0), "Target subvault not set");

        _generateNTTBridge(
            "preProd/tqETH/sv5-nttBridge-WETH-monad",
            preProdCurator,
            subvault,
            targetSubvault,
            "sv5",
            "monad-sv0"
        );
    }

    /// @notice Generate NTT bridge JSON for prod SV3 WETH to Monad
    function generateProdSv3WETHToMonad(address targetSubvault) public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(3);
        require(subvault != address(0), "Subvault address not set");
        require(targetSubvault != address(0), "Target subvault not set");

        _generateNTTBridge(
            "prod/tqETH/sv3-nttBridge-WETH-monad",
            prodCurator,
            subvault,
            targetSubvault,
            "sv3",
            "monad-sv0"
        );
    }

    function _generateNTTBridge(
        string memory title,
        address curator,
        address subvault,
        address targetSubvault,
        string memory subvaultName,
        string memory targetSubvaultName
    ) internal {
        console.log("=== Generating NTT Bridge Operations JSON ===");
        console.log("Source subvault:", subvault);
        console.log("NTT Router:", Constants.NTT_ROUTER);
        console.log("NTT Manager:", Constants.NTT_WETH_MANAGER);
        console.log("Token: WETH");
        console.log("Wormhole Monad chain ID:", uint256(Constants.WORMHOLE_MONAD_CHAIN_ID));
        console.log("Target subvault:", targetSubvault);
        console.log("");

        NTTLibrary.Info memory info = NTTLibrary.Info({
            curator: curator,
            subvault: subvault,
            targetSubvault: targetSubvault,
            nttRouter: Constants.NTT_ROUTER,
            nttManager: Constants.NTT_WETH_MANAGER,
            token: Constants.WETH,
            recipientChain: Constants.WORMHOLE_MONAD_CHAIN_ID,
            transceiverInstructionsLength: 38, // 2 transceivers: Wormhole (1-byte) + Axelar (32-byte)
            subvaultName: subvaultName,
            targetSubvaultName: targetSubvaultName,
            targetChainName: "monad"
        });

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](10);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            NTTLibrary.getNTTProofs($.bitmaskVerifier, info),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        string[] memory descriptions = new string[](10);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            NTTLibrary.getNTTDescriptions(info),
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

        _verifyTargetSubvault(targetSubvault);
    }

    function _verifyTargetSubvault(address targetSubvault) internal {
        string memory rpcUrl = vm.envOr("MONAD_RPC_URL", string("https://rpc.monad.xyz"));
        uint256 currentFork = vm.activeFork();
        uint256 monadFork = vm.createFork(rpcUrl);
        vm.selectFork(monadFork);

        Vault dstVault = Vault(payable(Constants.MONAD_VAULT));
        bool found = false;
        for (uint256 i = 0; i < 20; i++) {
            try dstVault.subvaultAt(i) returns (address sv) {
                if (sv == targetSubvault) {
                    console.log("VERIFIED: target is subvault at index", i, "on monad");
                    found = true;
                    break;
                }
            } catch {
                break;
            }
        }
        require(found, "Target address is NOT a subvault of the Monad vault");
        vm.selectFork(currentFork);
    }
}
