// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";
import "../common/protocols/NTTLibrary.sol";
import "../common/protocols/CCIPLibrary.sol";
import "../common/protocols/CCTPLibrary.sol";
import "../common/ArraysLibrary.sol";

/// @notice Script to generate bridge operations JSON files for Monad SV0 → Ethereum
/// @dev Run with: forge script scripts/monad/GenerateBridgeJSON.s.sol --sig "generateSv0()" --via-ir --rpc-url https://rpc.monad.xyz
contract GenerateBridgeJSON is Script, Test {
    address public constant VAULT = 0x799d2847cF8Dfcb4f17ec28737f17C0E82Eb445c;
    address public curator = 0x5FFA51F64Bc40c5af3a435A95e9616cc2Df9F01B;

    /// @notice Generate all bridge JSONs for SV0 (NTT WETH, CCIP wstETH, CCTP USDC)
    function generateSv0() public {
        Vault vault = Vault(payable(VAULT));
        address subvault = vault.subvaultAt(0);
        require(subvault != address(0), "Subvault address not set");

        generateNTT(subvault);
        generateCCIP(subvault);
        generateCCTP(subvault);
    }

    /// @notice NTT bridge: WETH → Ethereum SV3
    function generateNTT(address subvault) internal {
        console.log("=== Generating NTT Bridge (WETH -> Ethereum SV3) ===");
        console.log("Source subvault:", subvault);
        console.log("Target:", Constants.ETHEREUM_TQETH_SV3);

        NTTLibrary.Info memory info = NTTLibrary.Info({
            curator: curator,
            subvault: subvault,
            targetSubvault: Constants.ETHEREUM_TQETH_SV3,
            nttRouter: Constants.NTT_ROUTER,
            nttManager: Constants.NTT_WETH_MANAGER,
            token: Constants.WETH,
            recipientChain: Constants.WORMHOLE_ETHEREUM_CHAIN_ID,
            transceiverInstructionsLength: 38, // 2 transceivers: Wormhole (1-byte) + Axelar (32-byte)
            subvaultName: "monad-sv0",
            targetSubvaultName: "eth-sv3",
            targetChainName: "ethereum"
        });

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](10);
        uint256 iterator = 0;
        iterator = ArraysLibrary.insert(leaves, NTTLibrary.getNTTProofs($.bitmaskVerifier, info), iterator);
        assembly { mstore(leaves, iterator) }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        string[] memory descriptions = new string[](10);
        iterator = 0;
        iterator = ArraysLibrary.insert(descriptions, NTTLibrary.getNTTDescriptions(info), iterator);
        assembly { mstore(descriptions, iterator) }

        ProofLibrary.storeProofs("monad:tqMON:prod:sv0:nttBridge", merkleRoot, leavesWithProofs, descriptions);
        console.log("NTT bridge JSON generated, ops:", leavesWithProofs.length, "root:", vm.toString(merkleRoot));
    }

    /// @notice CCIP bridge: wstETH → Ethereum SV3
    function generateCCIP(address subvault) internal {
        console.log("\n=== Generating CCIP Bridge (wstETH -> Ethereum SV3) ===");
        console.log("Source subvault:", subvault);
        console.log("Target:", Constants.ETHEREUM_TQETH_SV3);

        CCIPLibrary.Info memory info = CCIPLibrary.Info({
            curator: curator,
            subvault: subvault,
            asset: Constants.WSTETH,
            ccipRouter: Constants.CCIP_MONAD_ROUTER,
            targetChainSelector: Constants.CCIP_ETHEREUM_CHAIN_SELECTOR,
            targetChainReceiver: Constants.ETHEREUM_TQETH_SV3,
            targetChainName: "ethereum"
        });

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](10);
        uint256 iterator = 0;
        iterator = ArraysLibrary.insert(leaves, CCIPLibrary.getCCIPProofs($.bitmaskVerifier, info), iterator);
        assembly { mstore(leaves, iterator) }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        string[] memory descriptions = new string[](10);
        iterator = 0;
        iterator = ArraysLibrary.insert(descriptions, CCIPLibrary.getCCIPDescriptions(info), iterator);
        assembly { mstore(descriptions, iterator) }

        ProofLibrary.storeProofs("monad:tqMON:prod:sv0:ccipBridge", merkleRoot, leavesWithProofs, descriptions);
        console.log("CCIP bridge JSON generated, ops:", leavesWithProofs.length, "root:", vm.toString(merkleRoot));
    }

    /// @notice CCTP bridge: USDC → Ethereum SV4
    function generateCCTP(address subvault) internal {
        console.log("\n=== Generating CCTP Bridge (USDC -> Ethereum SV4) ===");
        console.log("Source subvault:", subvault);
        console.log("Target:", Constants.ETHEREUM_TQETH_SV4);

        CCTPLibrary.Info memory info = CCTPLibrary.Info({
            curator: curator,
            subvault: subvault,
            tokenMessenger: Constants.CCTP_TOKEN_MESSENGER_V2,
            messageTransmitter: address(0), // not needed (receiveMessage removed)
            burnToken: Constants.USDC,
            destinationDomain: Constants.CCTP_ETHEREUM_DOMAIN,
            mintRecipient: bytes32(uint256(uint160(Constants.ETHEREUM_TQETH_SV4))),
            messageLength: 0, // not needed (receiveMessage removed)
            attestationLength: 0, // not needed (receiveMessage removed)
            targetChainName: "ethereum"
        });

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](10);
        uint256 iterator = 0;
        iterator = ArraysLibrary.insert(leaves, CCTPLibrary.getCCTPProofs($.bitmaskVerifier, info), iterator);
        assembly { mstore(leaves, iterator) }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        string[] memory descriptions = new string[](10);
        iterator = 0;
        iterator = ArraysLibrary.insert(descriptions, CCTPLibrary.getCCTPDescriptions(info), iterator);
        assembly { mstore(descriptions, iterator) }

        ProofLibrary.storeProofs("monad:tqMON:prod:sv0:cctpBridge", merkleRoot, leavesWithProofs, descriptions);
        console.log("CCTP bridge JSON generated, ops:", leavesWithProofs.length, "root:", vm.toString(merkleRoot));
    }
}
