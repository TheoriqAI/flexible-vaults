// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {ICowswapSettlement} from "../common/interfaces/ICowswapSettlement.sol";

import {AcceptanceLibrary} from "../common/AcceptanceLibrary.sol";

import {ArraysLibrary} from "../common/ArraysLibrary.sol";
import {Permissions} from "../common/Permissions.sol";
import {ProofLibrary} from "../common/ProofLibrary.sol";

import {CoreVaultLibrary} from "../common/protocols/CoreVaultLibrary.sol";

import {AaveLibrary} from "../common/protocols/AaveLibrary.sol";
import {KyberSwapLibrary} from "../common/protocols/KyberSwapLibrary.sol";
import {StakeWiseLibrary} from "../common/protocols/StakeWiseLibrary.sol";
import {SwapModuleLibrary} from "../common/protocols/SwapModuleLibrary.sol";
import {WethLibrary} from "../common/protocols/WethLibrary.sol";

import {BitmaskVerifier, Call, IVerifier, ProtocolDeployment, SubvaultCalls} from "../common/interfaces/Imports.sol";
import "./Constants.sol";

library tqETHLibrary {
    function getSubvault0Info(address subvault, address[] memory curators, address swapModule)
        internal
        pure
        returns (SwapModuleLibrary.Info memory)
    {
        return SwapModuleLibrary.Info({
            subvault: subvault,
            subvaultName: "subvault0",
            swapModule: swapModule,
            curators: curators,
            assets: ArraysLibrary.makeAddressArray(
                abi.encode(
                    Constants.ETH,
                    Constants.WETH,
                    Constants.WSTETH,
                    Constants.USDC,
                    Constants.USDT,
                    Constants.USDE
                )
            )
        });
    }

    function getKyberSwapInfo(address curator) internal pure returns (KyberSwapLibrary.Info memory) {
        return KyberSwapLibrary.Info({
            kyberRouter: Constants.KYBERSWAP_ROUTER,
            curator: curator,
            assets: ArraysLibrary.makeAddressArray(
                abi.encode(
                    Constants.ETH,
                    Constants.WETH,
                    Constants.WSTETH,
                    Constants.USDC,
                    Constants.USDT,
                    Constants.USDE
                )
            )
        });
    }

    function getSubvault0Proofs(address subvault, address swapModule, address[] memory curators)
        internal
        pure
        returns (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leaves)
    {
        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // SwapModule: 3 ops per asset per curator = 3 * 6 * 2 = 36
        // KyberSwap: (2 + assets.length) per curator = 7 * 2 = 14
        // Total: ~50 (with some margin)
        leaves = new IVerifier.VerificationPayload[](100);
        uint256 iterator = 0;

        // SwapModule proofs
        iterator = ArraysLibrary.insert(
            leaves,
            SwapModuleLibrary.getSwapModuleProofs($.bitmaskVerifier, getSubvault0Info(subvault, curators, swapModule)),
            iterator
        );

        // KyberSwap proofs for each curator
        for (uint256 i = 0; i < curators.length; i++) {
            iterator = ArraysLibrary.insert(
                leaves,
                KyberSwapLibrary.getKyberSwapProofs($.bitmaskVerifier, getKyberSwapInfo(curators[i])),
                iterator
            );
        }

        assembly {
            mstore(leaves, iterator)
        }
        return ProofLibrary.generateMerkleProofs(leaves);
    }

    function getSubvault0Descriptions(address subvault, address swapModule, address[] memory curators)
        internal
        view
        returns (string[] memory descriptions)
    {
        descriptions = new string[](100);
        uint256 iterator = 0;

        // SwapModule descriptions
        iterator = ArraysLibrary.insert(
            descriptions,
            SwapModuleLibrary.getSwapModuleDescriptions(getSubvault0Info(subvault, curators, swapModule)),
            iterator
        );

        // KyberSwap descriptions for each curator
        for (uint256 i = 0; i < curators.length; i++) {
            iterator = ArraysLibrary.insert(
                descriptions,
                KyberSwapLibrary.getKyberSwapDescriptions(getKyberSwapInfo(curators[i])),
                iterator
            );
        }

        assembly {
            mstore(descriptions, iterator)
        }
    }

    function getSubvault0SubvaultCalls(
        address subvault,
        address swapModule,
        address[] memory curators,
        IVerifier.VerificationPayload[] memory leaves
    ) internal pure returns (SubvaultCalls memory calls) {
        calls.payloads = leaves;
        calls.calls = new Call[][](leaves.length);

        uint256 iterator = 0;

        // SwapModule calls
        iterator = ArraysLibrary.insert(
            calls.calls,
            SwapModuleLibrary.getSwapModuleCalls(getSubvault0Info(subvault, curators, swapModule)),
            iterator
        );

        // KyberSwap calls for each curator
        for (uint256 i = 0; i < curators.length; i++) {
            iterator = ArraysLibrary.insert(
                calls.calls,
                KyberSwapLibrary.getKyberSwapCalls(getKyberSwapInfo(curators[i])),
                iterator
            );
        }
    }

    function getSubvault1CoreVaultInfo(address subvault, address[] memory curators)
        internal
        pure
        returns (CoreVaultLibrary.Info[] memory data)
    {
        address[] memory depositQueues = ArraysLibrary.makeAddressArray(
            abi.encode(
                Constants.STRETH_DEPOSIT_QUEUE_ETH,
                Constants.STRETH_DEPOSIT_QUEUE_WETH,
                Constants.STRETH_DEPOSIT_QUEUE_WSTETH
            )
        );
        address[] memory redeemQueues = ArraysLibrary.makeAddressArray(abi.encode(Constants.STRETH_REDEEM_QUEUE_WSTETH));
        data = new CoreVaultLibrary.Info[](curators.length);
        for (uint256 i = 0; i < data.length; i++) {
            data[i] = CoreVaultLibrary.Info({
                subvault: subvault,
                subvaultName: "subvault1",
                curator: curators[i],
                vault: Constants.STRETH,
                depositQueues: depositQueues,
                redeemQueues: redeemQueues
            });
        }
    }

    function getSubvault1Proofs(address subvault, address[] memory curators)
        internal
        view
        returns (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leaves)
    {
        leaves = new IVerifier.VerificationPayload[](50);
        ProtocolDeployment memory $ = Constants.protocolDeployment();
        uint256 iterator = 0;
        CoreVaultLibrary.Info[] memory data = getSubvault1CoreVaultInfo(subvault, curators);
        for (uint256 i = 0; i < data.length; i++) {
            iterator =
                ArraysLibrary.insert(leaves, CoreVaultLibrary.getCoreVaultProofs($.bitmaskVerifier, data[i]), iterator);
        }
        assembly {
            mstore(leaves, iterator)
        }

        return ProofLibrary.generateMerkleProofs(leaves);
    }

    function getSubvault1Descriptions(address subvault, address[] memory curators)
        internal
        view
        returns (string[] memory descriptions)
    {
        descriptions = new string[](50);
        uint256 iterator = 0;
        CoreVaultLibrary.Info[] memory data = getSubvault1CoreVaultInfo(subvault, curators);
        for (uint256 i = 0; i < data.length; i++) {
            iterator = ArraysLibrary.insert(descriptions, CoreVaultLibrary.getCoreVaultDescriptions(data[i]), iterator);
        }
        assembly {
            mstore(descriptions, iterator)
        }
    }

    function getSubvault1SubvaultCalls(
        address subvault,
        address[] memory curators,
        IVerifier.VerificationPayload[] memory leaves
    ) internal view returns (SubvaultCalls memory calls) {
        calls.payloads = leaves;
        calls.calls = new Call[][](leaves.length);
        uint256 iterator = 0;
        CoreVaultLibrary.Info[] memory data = getSubvault1CoreVaultInfo(subvault, curators);
        for (uint256 i = 0; i < data.length; i++) {
            iterator = ArraysLibrary.insert(calls.calls, CoreVaultLibrary.getCoreVaultCalls(data[i]), iterator);
        }
    }

    function getSubvault2Info(address subvault, address[] memory curators)
        internal
        pure
        returns (StakeWiseLibrary.Info[] memory data)
    {
        data = new StakeWiseLibrary.Info[](curators.length);
        for (uint256 i = 0; i < data.length; i++) {
            data[i] = StakeWiseLibrary.Info({
                curator: curators[i],
                subvault: subvault,
                subvaultName: "subvault2",
                vault: 0xe6d8d8aC54461b1C5eD15740EEe322043F696C08,
                vaultName: "Chorus One - MEV Max"
            });
        }
    }

    function getSubvault2Proofs(address subvault, address[] memory curators)
        internal
        pure
        returns (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leaves)
    {
        ProtocolDeployment memory $ = Constants.protocolDeployment();
        leaves = new IVerifier.VerificationPayload[](50);
        uint256 iterator = 0;
        StakeWiseLibrary.Info[] memory data = getSubvault2Info(subvault, curators);
        for (uint256 i = 0; i < data.length; i++) {
            iterator =
                ArraysLibrary.insert(leaves, StakeWiseLibrary.getStakeWiseProofs($.bitmaskVerifier, data[i]), iterator);
        }
        assembly {
            mstore(leaves, iterator)
        }

        return ProofLibrary.generateMerkleProofs(leaves);
    }

    function getSubvault2Descriptions(address subvault, address[] memory curators)
        internal
        pure
        returns (string[] memory descriptions)
    {
        descriptions = new string[](50);
        uint256 iterator = 0;
        StakeWiseLibrary.Info[] memory data = getSubvault2Info(subvault, curators);
        for (uint256 i = 0; i < data.length; i++) {
            iterator = ArraysLibrary.insert(descriptions, StakeWiseLibrary.getStakeWiseDescriptions(data[i]), iterator);
        }
        assembly {
            mstore(descriptions, iterator)
        }
    }

    function getSubvault2SubvaultCalls(
        address subvault,
        address[] memory curators,
        IVerifier.VerificationPayload[] memory leaves
    ) internal pure returns (SubvaultCalls memory calls) {
        calls.payloads = leaves;
        calls.calls = new Call[][](leaves.length);
        uint256 iterator = 0;
        StakeWiseLibrary.Info[] memory data = getSubvault2Info(subvault, curators);
        for (uint256 i = 0; i < data.length; i++) {
            iterator = ArraysLibrary.insert(calls.calls, StakeWiseLibrary.getStakeWiseCalls(data[i]), iterator);
        }
    }

    // ============================================
    // Aave Operations Helper Functions
    // ============================================

    /// @notice Helper to get Aave info for a subvault with specified assets for collateral and loans
    /// @param subvault The subvault address
    /// @param subvaultName The name of the subvault (e.g., "subvault3")
    /// @param curator The curator address that can execute these operations
    /// @param collateralAssets Array of assets that can be supplied as collateral (e.g., [WETH, wstETH])
    /// @param loanAssets Array of assets that can be borrowed (e.g., [USDC, USDT, USDE])
    /// @param categoryId Aave eMode category ID (0 for no eMode, 1 for ETH correlated, etc.)
    /// @return AaveLibrary.Info struct configured for these parameters
    function getAaveInfo(
        address subvault,
        string memory subvaultName,
        address curator,
        address[] memory collateralAssets,
        address[] memory loanAssets,
        uint8 categoryId
    ) internal pure returns (AaveLibrary.Info memory) {
        return AaveLibrary.Info({
            subvault: subvault,
            subvaultName: subvaultName,
            curator: curator,
            aaveInstance: Constants.AAVE_CORE,
            aaveInstanceName: "Core",
            collaterals: collateralAssets,
            loans: loanAssets,
            categoryId: categoryId
        });
    }

    /// @notice Helper to get Aave info for tqETH Aave operations subvault
    /// @dev Configured for WETH, wstETH, USDE as collateral; WETH, wstETH, USDC, USDT, USDE as loans
    /// @param subvault The subvault address
    /// @param curator The curator address
    /// @return AaveLibrary.Info struct
    function getAaveOperationsInfo(address subvault, address curator) internal pure returns (AaveLibrary.Info memory) {
        // WETH, wstETH, USDE can be used as collateral (supply/withdraw)
        address[] memory collaterals = new address[](3);
        collaterals[0] = Constants.WETH;
        collaterals[1] = Constants.WSTETH;
        collaterals[2] = Constants.USDE;

        // WETH, wstETH, USDC, USDT, USDE can be borrowed (borrow/repay)
        address[] memory loans = new address[](5);
        loans[0] = Constants.WETH;
        loans[1] = Constants.WSTETH;
        loans[2] = Constants.USDC;
        loans[3] = Constants.USDT;
        loans[4] = Constants.USDE;

        return AaveLibrary.Info({
            subvault: subvault,
            subvaultName: "aaveOps",
            curator: curator,
            aaveInstance: Constants.AAVE_CORE,
            aaveInstanceName: "Core",
            collaterals: collaterals,
            loans: loans,
            categoryId: 0 // No eMode - mixed asset types
        });
    }

    /// @notice Get proofs for Aave operations including push/pull liquidity to main vault
    /// @param subvault The subvault address
    /// @param vault The main vault address
    /// @param curator The curator address
    /// @return merkleRoot The merkle root for all operations
    /// @return leaves The verification payloads with proofs
    function getAaveOperationsProofs(address subvault, address vault, address curator)
        internal
        view
        returns (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leaves)
    {
        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Allocate enough space for Aave operations + deposit/redeem operations
        // Aave: (2 collaterals + 3 loans) * 3 operations each + 1 setUserEMode = 16
        // CoreVault: estimate ~10 for deposit/redeem queues
        leaves = new IVerifier.VerificationPayload[](30);
        uint256 iterator = 0;

        // Add Aave operations (supply, withdraw, borrow, repay for all assets + setUserEMode)
        AaveLibrary.Info memory aaveInfo = getAaveOperationsInfo(subvault, curator);
        iterator = ArraysLibrary.insert(
            leaves,
            AaveLibrary.getAaveProofs($.bitmaskVerifier, aaveInfo),
            iterator
        );

        // Note: Deposit/redeem operations are NOT included here
        // If you need them, add them separately with the correct deposit/redeem queues for your vault

        // Trim array to actual size
        assembly {
            mstore(leaves, iterator)
        }

        return ProofLibrary.generateMerkleProofs(leaves);
    }

    /// @notice Get descriptions for Aave operations
    /// @param subvault The subvault address
    /// @param vault The main vault address
    /// @param curator The curator address
    /// @return descriptions Array of human-readable descriptions
    function getAaveOperationsDescriptions(address subvault, address vault, address curator)
        internal
        view
        returns (string[] memory descriptions)
    {
        descriptions = new string[](30);
        uint256 iterator = 0;

        // Add Aave descriptions
        AaveLibrary.Info memory aaveInfo = getAaveOperationsInfo(subvault, curator);
        iterator = ArraysLibrary.insert(
            descriptions,
            AaveLibrary.getAaveDescriptions(aaveInfo),
            iterator
        );

        // Note: Deposit/redeem descriptions are NOT included here
        // If you need them, add them separately with the correct deposit/redeem queues for your vault

        // Trim array to actual size
        assembly {
            mstore(descriptions, iterator)
        }
    }

    /// @notice Get lean descriptions for Aave operations (without ABIs)
    /// @param subvault The subvault address
    /// @param vault The main vault address
    /// @param curator The curator address
    /// @return descriptions Array of human-readable descriptions without ABI data
    function getAaveOperationsDescriptionsLean(address subvault, address vault, address curator)
        internal
        view
        returns (string[] memory descriptions)
    {
        descriptions = new string[](30);
        uint256 iterator = 0;

        // Add Aave lean descriptions
        AaveLibrary.Info memory aaveInfo = getAaveOperationsInfo(subvault, curator);
        iterator = ArraysLibrary.insert(
            descriptions,
            AaveLibrary.getAaveDescriptionsLean(aaveInfo),
            iterator
        );

        // Note: Deposit/redeem descriptions are NOT included here
        // If you need them, add them separately with the correct deposit/redeem queues for your vault

        // Trim array to actual size
        assembly {
            mstore(descriptions, iterator)
        }
    }

    /// @notice Get test calls for Aave operations
    /// @param subvault The subvault address
    /// @param vault The main vault address
    /// @param curator The curator address
    /// @param leaves The verification payloads
    /// @return calls SubvaultCalls struct with test cases
    function getAaveOperationsSubvaultCalls(
        address subvault,
        address vault,
        address curator,
        IVerifier.VerificationPayload[] memory leaves
    ) internal view returns (SubvaultCalls memory calls) {
        calls.payloads = leaves;
        calls.calls = new Call[][](leaves.length);
        uint256 iterator = 0;

        // Add Aave test calls
        AaveLibrary.Info memory aaveInfo = getAaveOperationsInfo(subvault, curator);
        iterator = ArraysLibrary.insert(
            calls.calls,
            AaveLibrary.getAaveCalls(aaveInfo),
            iterator
        );

        // Add deposit/redeem test calls
        CoreVaultLibrary.Info memory coreVaultInfo = CoreVaultLibrary.Info({
            subvault: subvault,
            subvaultName: "aaveOps",
            curator: curator,
            vault: vault,
            depositQueues: getDepositQueues(),
            redeemQueues: getRedeemQueues()
        });
        iterator = ArraysLibrary.insert(
            calls.calls,
            CoreVaultLibrary.getCoreVaultCalls(coreVaultInfo),
            iterator
        );
    }

    /// @notice Get deposit queues for tqETH vault
    /// @return Array of deposit queue addresses
    function getDepositQueues() internal pure returns (address[] memory) {
        address[] memory queues = new address[](3);
        queues[0] = Constants.STRETH_DEPOSIT_QUEUE_ETH;
        queues[1] = Constants.STRETH_DEPOSIT_QUEUE_WETH;
        queues[2] = Constants.STRETH_DEPOSIT_QUEUE_WSTETH;
        return queues;
    }

    /// @notice Get redeem queues for tqETH vault
    /// @return Array of redeem queue addresses
    function getRedeemQueues() internal pure returns (address[] memory) {
        address[] memory queues = new address[](1);
        queues[0] = Constants.STRETH_REDEEM_QUEUE_WSTETH;
        return queues;
    }
}
