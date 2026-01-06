// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "./tqETHLibrary.sol";
import "../common/ProofLibrary.sol";

/// @notice Script to generate SwapModule operations JSON files for tqETH subvault0
/// @dev Run with: forge script scripts/ethereum/GenerateSwapModuleJSON.s.sol --sig "generatePreProd()" --rpc-url <RPC>
contract GenerateSwapModuleJSON is Script, Test {
    // Curators
    address public curator = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec;
    address public agent1 = 0xfcBEe74406415c0Cbe556317B1aeF8D9950D515D;

    // Vault addresses
    address public constant VAULT_PROD = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
    address public constant VAULT_PREPROD = 0x2669a8B27B6f957ddb92Dc0ebdec1f112E6079E4;

    // SwapModule addresses
    address public constant SWAP_MODULE_PREPROD = 0x17aeAbfD3cB214A8757bF07D2E248d526c8C4809;
    address public constant SWAP_MODULE_PROD = 0x17aeAbfD3cB214A8757bF07D2E248d526c8C4809; // TODO: Update with prod address

    /// @notice Generate JSON for preprod subvault0 (swap module operations)
    function generatePreProd() public {
        Vault vault = Vault(payable(VAULT_PREPROD));
        address subvault = vault.subvaultAt(0);
        address[] memory curators = _getCurators();

        string[] memory descriptions = tqETHLibrary.getSubvault0Descriptions(subvault, SWAP_MODULE_PREPROD, curators);
        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leaves) =
            tqETHLibrary.getSubvault0Proofs(subvault, SWAP_MODULE_PREPROD, curators);

        ProofLibrary.storeProofs("ethereum:tqETHPreProd:subvault0", merkleRoot, leaves, descriptions);

        console.log("Generated: ./scripts/jsons/ethereum:tqETHPreProd:subvault0.json");
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations:", leaves.length);
    }

    /// @notice Generate JSON for prod subvault0 (swap module operations)
    function generateProd() public {
        Vault vault = Vault(payable(VAULT_PROD));
        address subvault = vault.subvaultAt(0);
        address[] memory curators = _getCurators();

        string[] memory descriptions = tqETHLibrary.getSubvault0Descriptions(subvault, SWAP_MODULE_PROD, curators);
        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leaves) =
            tqETHLibrary.getSubvault0Proofs(subvault, SWAP_MODULE_PROD, curators);

        ProofLibrary.storeProofs("ethereum:tqETH:subvault0", merkleRoot, leaves, descriptions);

        console.log("Generated: ./scripts/jsons/ethereum:tqETH:subvault0.json");
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations:", leaves.length);
    }

    function _getCurators() internal view returns (address[] memory) {
        address[] memory curators = new address[](2);
        curators[0] = curator;
        curators[1] = agent1;
        return curators;
    }
}
