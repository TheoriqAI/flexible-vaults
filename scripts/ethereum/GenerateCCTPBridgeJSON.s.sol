// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";
import "../common/protocols/CCTPLibrary.sol";
import "../common/ArraysLibrary.sol";

/// @notice Script to generate CCTP V2 bridge operations JSON files
/// @dev Run with: forge script scripts/ethereum/GenerateCCTPBridgeJSON.s.sol --sig "generateProdSv4USDCToMonad(address)" --via-ir --rpc-url http://108.53.61.201:8550 0x0C7cb4e1241F4B7Fd65DE59FDE5a6dBFf190fB20
contract GenerateCCTPBridgeJSON is Script, Test {
    address public prodCurator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;
    address public preProdCurator = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec;

    address public constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address public constant VAULT_PREPROD = 0x2669a8B27B6f957ddb92Dc0ebdec1f112E6079E4;

    /// @notice Generate CCTP bridge JSON for preProd SV5 USDC to Monad
    function generatePreProdSv5USDCToMonad(address targetSubvault) public {
        Vault vault = Vault(payable(VAULT_PREPROD));
        address subvault = vault.subvaultAt(5);
        require(subvault != address(0), "Subvault address not set");
        require(targetSubvault != address(0), "Target subvault not set");

        _generateCCTPBridge("preProd/tqETH/sv5-cctpBridge-USDC-monad", preProdCurator, subvault, targetSubvault);
    }

    /// @notice Generate CCTP bridge JSON for prod SV4 USDC to Monad
    function generateProdSv4USDCToMonad(address targetSubvault) public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(4);
        require(subvault != address(0), "Subvault address not set");
        require(targetSubvault != address(0), "Target subvault not set");

        _generateCCTPBridge("prod/tqETH/sv4-cctpBridge-USDC-monad", prodCurator, subvault, targetSubvault);
    }

    function _generateCCTPBridge(
        string memory title,
        address curator,
        address subvault,
        address targetSubvault
    ) internal {
        console.log("=== Generating CCTP Bridge Operations JSON ===");
        console.log("Source subvault:", subvault);
        console.log("TokenMessengerV2:", Constants.CCTP_TOKEN_MESSENGER_V2);
        console.log("MessageTransmitterV2:", Constants.CCTP_MESSAGE_TRANSMITTER_V2);
        console.log("Token: USDC");
        console.log("Destination domain (Monad):", uint256(Constants.CCTP_MONAD_DOMAIN));
        console.log("Target subvault:", targetSubvault);
        console.log("");

        CCTPLibrary.Info memory info = CCTPLibrary.Info({
            curator: curator,
            subvault: subvault,
            tokenMessenger: Constants.CCTP_TOKEN_MESSENGER_V2,
            messageTransmitter: Constants.CCTP_MESSAGE_TRANSMITTER_V2,
            burnToken: Constants.USDC,
            destinationDomain: Constants.CCTP_MONAD_DOMAIN,
            mintRecipient: bytes32(uint256(uint160(targetSubvault))),
            messageLength: 320, // V2 message: 124-byte header + 196-byte BurnMessage
            attestationLength: 130, // 2 attesters x 65 bytes
            targetChainName: "monad"
        });

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](10);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            CCTPLibrary.getCCTPProofs($.bitmaskVerifier, info),
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
            CCTPLibrary.getCCTPDescriptions(info),
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
