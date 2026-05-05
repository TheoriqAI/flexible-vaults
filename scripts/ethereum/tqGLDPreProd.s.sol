// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../common/interfaces/ICowswapSettlement.sol";
import {IWETH as WETHInterface} from "../common/interfaces/IWETH.sol";

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

import "../../src/vaults/Subvault.sol";
import "../../src/vaults/VaultConfigurator.sol";

import "../common/AcceptanceLibrary.sol";
import "../common/Permissions.sol";
import "../common/ProofLibrary.sol";
import "forge-std/Script.sol";

import "./Constants.sol";
import "./tqGLDLibrary.sol";

interface IAggregatorV3 {
    function latestAnswer() external view returns (int256);
}

/// @dev Helper to atomically submit + accept oracle reports in a single transaction.
///      Needed because forge broadcast simulates each tx independently, so acceptReport
///      can't see submitReports' state when they are separate transactions.
contract OracleInitHelper {
    function submitAndAccept(IOracle oracle, IOracle.Report[] calldata reports) external {
        oracle.submitReports(reports);
        uint32 ts = uint32(block.timestamp);
        for (uint256 i = 0; i < reports.length; i++) {
            oracle.acceptReport(reports[i].asset, uint256(reports[i].priceD18), ts);
        }
    }
}

contract Deploy is Script {
    // Actors (same as tqETH preProd)
    address public proxyAdmin = 0xC1211878475Cd017fecb922Ae63cc3815FA45652;
    address public lazyVaultAdmin = 0xE8bEc6Fb52f01e487415D3Ed3797ab92cBfdF498;
    address public activeVaultAdmin = 0x7885B30F0DC0d8e1aAf0Ed6580caC22d5D09ff4f;
    address public oracleUpdater = 0x3F1C3Eb0bC499c1A091B635dEE73fF55E19cdCE9;

    address public curator1 = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec;
    address public curator2 = 0xfc5c96303F353c314e468681899C35F424246eBe;

    address public pauser1 = 0xFeCeb0255a4B7Cd05995A7d617c0D52c994099CF;
    address public pauser2 = 0x8b7C1b52e2d606a526abD73f326c943c75e45Bd3;

    function run() external {
        uint256 deployerPk = uint256(bytes32(vm.envBytes("HOT_DEPLOYER")));
        address deployer = vm.addr(deployerPk);

        uint256 gasStart = gasleft();

        vm.startBroadcast(deployerPk);

        Vault.RoleHolder[] memory holders = new Vault.RoleHolder[](43);
        TimelockController timelockController;

        {
            address[] memory proposers = ArraysLibrary.makeAddressArray(abi.encode(lazyVaultAdmin, deployer));
            address[] memory executors = ArraysLibrary.makeAddressArray(abi.encode(pauser1, pauser2));
            timelockController = new TimelockController(0, proposers, executors, lazyVaultAdmin);
        }
        {
            uint256 i = 0;

            // activeVaultAdmin roles:
            holders[i++] = Vault.RoleHolder(Permissions.ACCEPT_REPORT_ROLE, activeVaultAdmin);
            holders[i++] = Vault.RoleHolder(Permissions.SET_MERKLE_ROOT_ROLE, activeVaultAdmin);
            holders[i++] = Vault.RoleHolder(Permissions.ALLOW_CALL_ROLE, activeVaultAdmin);
            holders[i++] = Vault.RoleHolder(Permissions.DISALLOW_CALL_ROLE, activeVaultAdmin);
            holders[i++] = Vault.RoleHolder(Permissions.SET_VAULT_LIMIT_ROLE, activeVaultAdmin);
            holders[i++] = Vault.RoleHolder(Permissions.SET_SUBVAULT_LIMIT_ROLE, activeVaultAdmin);
            holders[i++] = Vault.RoleHolder(Permissions.ALLOW_SUBVAULT_ASSETS_ROLE, activeVaultAdmin);
            holders[i++] = Vault.RoleHolder(Permissions.MODIFY_VAULT_BALANCE_ROLE, activeVaultAdmin);
            holders[i++] = Vault.RoleHolder(Permissions.MODIFY_SUBVAULT_BALANCE_ROLE, activeVaultAdmin);

            // emergency pauser roles:
            holders[i++] = Vault.RoleHolder(Permissions.SET_FLAGS_ROLE, address(timelockController));
            holders[i++] = Vault.RoleHolder(Permissions.SET_MERKLE_ROOT_ROLE, address(timelockController));
            holders[i++] = Vault.RoleHolder(Permissions.SET_QUEUE_STATUS_ROLE, address(timelockController));

            // oracle updater roles:
            holders[i++] = Vault.RoleHolder(Permissions.SUBMIT_REPORTS_ROLE, oracleUpdater);

            // curator roles:
            address[] memory curators = getCurators();

            for (uint256 j = 0; j < curators.length; j++) {
                holders[i++] = Vault.RoleHolder(Permissions.CALLER_ROLE, curators[j]);
                holders[i++] = Vault.RoleHolder(Permissions.PULL_LIQUIDITY_ROLE, curators[j]);
                holders[i++] = Vault.RoleHolder(Permissions.PUSH_LIQUIDITY_ROLE, curators[j]);
            }

            // deployer roles:
            holders[i++] = Vault.RoleHolder(Permissions.DEFAULT_ADMIN_ROLE, deployer); // temporary, for granting oracle roles to helper
            holders[i++] = Vault.RoleHolder(Permissions.CREATE_QUEUE_ROLE, deployer);
            holders[i++] = Vault.RoleHolder(Permissions.CREATE_SUBVAULT_ROLE, deployer);
            holders[i++] = Vault.RoleHolder(Permissions.SET_VAULT_LIMIT_ROLE, deployer);
            holders[i++] = Vault.RoleHolder(Permissions.ALLOW_SUBVAULT_ASSETS_ROLE, deployer);
            holders[i++] = Vault.RoleHolder(Permissions.SET_SUBVAULT_LIMIT_ROLE, deployer);
            holders[i++] = Vault.RoleHolder(Permissions.SET_MERKLE_ROOT_ROLE, deployer);
            holders[i++] = Vault.RoleHolder(Permissions.SUBMIT_REPORTS_ROLE, deployer);
            holders[i++] = Vault.RoleHolder(Permissions.ACCEPT_REPORT_ROLE, deployer);
            assembly {
                mstore(holders, i)
            }
        }

        address[] memory assets_ = new address[](7);
        assets_[0] = Constants.ETH;
        assets_[1] = Constants.WETH;
        assets_[2] = Constants.XAUT;
        assets_[3] = Constants.PAXG;
        assets_[4] = Constants.USDC;
        assets_[5] = Constants.USDT;
        assets_[6] = Constants.USDE;

        address[] memory oracleAssets_ = new address[](4);
        oracleAssets_[0] = Constants.XAUT;
        oracleAssets_[1] = Constants.PAXG;
        oracleAssets_[2] = Constants.USDC;
        oracleAssets_[3] = Constants.USDT;

        ProtocolDeployment memory $ = Constants.protocolDeployment();
        VaultConfigurator.InitParams memory initParams = VaultConfigurator.InitParams({
            version: 0,
            proxyAdmin: proxyAdmin,
            vaultAdmin: lazyVaultAdmin,
            shareManagerVersion: 0,
            shareManagerParams: abi.encode(bytes32(0), "Theoriq AlphaVault GLD PreProd", "pp-tqGLD"),
            feeManagerVersion: 0,
            feeManagerParams: abi.encode(deployer, lazyVaultAdmin, uint24(0), uint24(0), uint24(1e5), uint24(1e4)),
            riskManagerVersion: 0,
            riskManagerParams: abi.encode(type(int256).max),
            oracleVersion: 0,
            oracleParams: abi.encode(
                IOracle.SecurityParams({
                    maxAbsoluteDeviation: 0.5 ether,
                    suspiciousAbsoluteDeviation: 0.1 ether,
                    maxRelativeDeviationD18: 0.5 ether,
                    suspiciousRelativeDeviationD18: 0.1 ether,
                    timeout: 5 minutes,
                    depositInterval: 5 minutes,
                    redeemInterval: 5 minutes
                }),
                oracleAssets_
            ),
            defaultDepositHook: address($.redirectingDepositHook),
            defaultRedeemHook: address($.basicRedeemHook),
            queueLimit: 5,
            roleHolders: holders
        });

        Vault vault;
        {
            (,,,, address vault_) = $.vaultConfigurator.create(initParams);
            vault = Vault(payable(vault_));
        }

        // queues setup: deposit for USDC, USDT, PAXG, XAUT; redeem for XAUT only
        vault.createQueue(0, true, proxyAdmin, Constants.USDC, new bytes(0));
        vault.createQueue(0, true, proxyAdmin, Constants.USDT, new bytes(0));
        vault.createQueue(0, true, proxyAdmin, Constants.PAXG, new bytes(0));
        vault.createQueue(0, true, proxyAdmin, Constants.XAUT, new bytes(0));
        vault.createQueue(2, false, proxyAdmin, Constants.XAUT, new bytes(0));

        // fee manager setup
        vault.feeManager().setBaseAsset(address(vault), Constants.XAUT);
        Ownable(address(vault.feeManager())).transferOwnership(lazyVaultAdmin);

        // subvault setup
        address[] memory verifiers = new address[](5);
        address[] memory swapModules = new address[](5);
        SubvaultCalls[] memory calls = new SubvaultCalls[](5);

        // Subvault 0: swap module proofs with merkle root
        {
            IRiskManager riskManager = vault.riskManager();
            verifiers[0] = $.verifierFactory.create(0, proxyAdmin, abi.encode(vault, bytes32(0)));
            address subvault = vault.createSubvault(0, proxyAdmin, verifiers[0]);

            swapModules[0] = _createSwapModule($, subvault);

            bytes32 merkleRoot;
            (merkleRoot, calls[0]) = _createSubvault0Verifier(subvault, swapModules[0]);
            IVerifier(verifiers[0]).setMerkleRoot(merkleRoot);
            riskManager.allowSubvaultAssets(vault.subvaultAt(0), assets_);
            riskManager.setSubvaultLimit(vault.subvaultAt(0), type(int256).max / 2);
        }

        // Subvault 1: swap module, zero merkle root (to be added later)
        {
            IRiskManager riskManager = vault.riskManager();
            verifiers[1] = $.verifierFactory.create(0, proxyAdmin, abi.encode(vault, bytes32(0)));
            address subvault = vault.createSubvault(0, proxyAdmin, verifiers[1]);

            swapModules[1] = _createSwapModule($, subvault);

            // merkle root to be set later
            riskManager.allowSubvaultAssets(vault.subvaultAt(1), assets_);
            riskManager.setSubvaultLimit(vault.subvaultAt(1), type(int256).max / 2);
        }

        // Subvault 2: swap module, zero merkle root (to be added later)
        {
            IRiskManager riskManager = vault.riskManager();
            verifiers[2] = $.verifierFactory.create(0, proxyAdmin, abi.encode(vault, bytes32(0)));
            address subvault = vault.createSubvault(0, proxyAdmin, verifiers[2]);

            swapModules[2] = _createSwapModule($, subvault);

            // merkle root to be set later
            riskManager.allowSubvaultAssets(vault.subvaultAt(2), assets_);
            riskManager.setSubvaultLimit(vault.subvaultAt(2), type(int256).max / 2);
        }

        // Subvault 3: swap module, zero merkle root (to be added later)
        {
            IRiskManager riskManager = vault.riskManager();
            verifiers[3] = $.verifierFactory.create(0, proxyAdmin, abi.encode(vault, bytes32(0)));
            address subvault = vault.createSubvault(0, proxyAdmin, verifiers[3]);

            swapModules[3] = _createSwapModule($, subvault);

            // merkle root to be set later
            riskManager.allowSubvaultAssets(vault.subvaultAt(3), assets_);
            riskManager.setSubvaultLimit(vault.subvaultAt(3), type(int256).max / 2);
        }

        // Subvault 4: swap module with nUSD + extra router, zero merkle root (to be added later)
        {
            IRiskManager riskManager = vault.riskManager();
            verifiers[4] = $.verifierFactory.create(0, proxyAdmin, abi.encode(vault, bytes32(0)));
            address subvault = vault.createSubvault(0, proxyAdmin, verifiers[4]);

            swapModules[4] = _createSwapModuleWithNUSD($, subvault);

            // merkle root to be set later
            riskManager.allowSubvaultAssets(vault.subvaultAt(4), assets_);
            riskManager.setSubvaultLimit(vault.subvaultAt(4), type(int256).max / 2);
        }

        // oracle reports - fetch gold price from Chainlink for initial seeding
        {
            uint256 xauUsd = uint256(IAggregatorV3(0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6).latestAnswer()); // XAU/USD, 8 dec

            IOracle.Report[] memory reports = new IOracle.Report[](4);

            // XAUT (6 dec): 1e30 (base asset, 1 oz gold)
            reports[0].asset = Constants.XAUT;
            reports[0].priceD18 = uint224(1e30);

            // PAXG (18 dec): 1 ether (1 oz gold, same as XAUT)
            reports[1].asset = Constants.PAXG;
            reports[1].priceD18 = uint224(1 ether);

            // USDC (6 dec): 1e30 / goldPriceUsd = 1e38 / xauUsd
            reports[2].asset = Constants.USDC;
            reports[2].priceD18 = uint224(1e38 / xauUsd);

            // USDT (6 dec): same as USDC
            reports[3].asset = Constants.USDT;
            reports[3].priceD18 = uint224(1e38 / xauUsd);

            console2.log("Chainlink XAU/USD (8 dec): %d", xauUsd);
            for (uint256 i = 0; i < reports.length; i++) {
                console2.log("Report %d priceD18: %d", i, uint256(reports[i].priceD18));
            }

            IOracle oracle = vault.oracle();

            // Use helper to atomically submit + accept in one tx (workaround for forge broadcast simulation)
            OracleInitHelper helper = new OracleInitHelper();
            vault.grantRole(Permissions.SUBMIT_REPORTS_ROLE, address(helper));
            vault.grantRole(Permissions.ACCEPT_REPORT_ROLE, address(helper));
            helper.submitAndAccept(oracle, reports);
            vault.revokeRole(Permissions.SUBMIT_REPORTS_ROLE, address(helper));
            vault.revokeRole(Permissions.ACCEPT_REPORT_ROLE, address(helper));
        }

        // emergency pause setup
        timelockController.schedule(
            address(vault.shareManager()),
            0,
            abi.encodeCall(
                IShareManager.setFlags,
                (
                    IShareManager.Flags({
                        hasMintPause: true,
                        hasBurnPause: true,
                        hasTransferPause: true,
                        hasWhitelist: true,
                        hasTransferWhitelist: true,
                        globalLockup: type(uint32).max
                    })
                )
            ),
            bytes32(0),
            bytes32(0),
            0
        );

        for (uint256 i = 0; i < vault.subvaults(); i++) {
            timelockController.schedule(
                address(Subvault(payable(vault.subvaultAt(i))).verifier()),
                0,
                abi.encodeCall(IVerifier.setMerkleRoot, (bytes32(0))),
                bytes32(0),
                bytes32(0),
                0
            );
        }

        for (uint256 i = 0; i < vault.getAssetCount(); i++) {
            address asset = vault.assetAt(i);
            for (uint256 j = 0; j < vault.getQueueCount(asset); j++) {
                address queue = vault.queueAt(asset, j);

                timelockController.schedule(
                    address(vault),
                    0,
                    abi.encodeCall(IShareModule.setQueueStatus, (queue, true)),
                    bytes32(0),
                    bytes32(0),
                    0
                );
            }
        }

        timelockController.renounceRole(timelockController.PROPOSER_ROLE(), deployer);
        timelockController.renounceRole(timelockController.CANCELLER_ROLE(), deployer);

        vault.renounceRole(Permissions.DEFAULT_ADMIN_ROLE, deployer);
        vault.renounceRole(Permissions.CREATE_QUEUE_ROLE, deployer);
        vault.renounceRole(Permissions.CREATE_SUBVAULT_ROLE, deployer);
        vault.renounceRole(Permissions.SET_VAULT_LIMIT_ROLE, deployer);
        vault.renounceRole(Permissions.ALLOW_SUBVAULT_ASSETS_ROLE, deployer);
        vault.renounceRole(Permissions.SET_SUBVAULT_LIMIT_ROLE, deployer);
        vault.renounceRole(Permissions.SUBMIT_REPORTS_ROLE, deployer);
        vault.renounceRole(Permissions.ACCEPT_REPORT_ROLE, deployer);
        vault.renounceRole(Permissions.SET_MERKLE_ROOT_ROLE, deployer);

        console2.log("Vault %s", address(vault));
        console2.log("TimelockController %s", address(timelockController));

        console2.log("DepositQueue (USDC) %s", address(vault.queueAt(Constants.USDC, 0)));
        console2.log("DepositQueue (USDT) %s", address(vault.queueAt(Constants.USDT, 0)));
        console2.log("DepositQueue (PAXG) %s", address(vault.queueAt(Constants.PAXG, 0)));
        console2.log("DepositQueue (XAUT) %s", address(vault.queueAt(Constants.XAUT, 0)));
        console2.log("RedeemQueue (XAUT) %s", address(vault.queueAt(Constants.XAUT, 1)));

        console2.log("Oracle %s", address(vault.oracle()));
        console2.log("ShareManager %s", address(vault.shareManager()));
        console2.log("FeeManager %s", address(vault.feeManager()));
        console2.log("RiskManager %s", address(vault.riskManager()));

        for (uint256 i = 0; i < 5; i++) {
            console2.log("Subvault %d: %s", i, vault.subvaultAt(i));
            console2.log("  Verifier %d: %s", i, verifiers[i]);
            console2.log("  SwapModule %d: %s", i, swapModules[i]);
        }

        uint256 gasUsed = gasStart - gasleft();
        console2.log("Estimated gas used: %d", gasUsed);

        vm.stopBroadcast();

        // revert("ok");
    }

    function getCurators() public view returns (address[] memory) {
        return ArraysLibrary.makeAddressArray(abi.encode(curator1, curator2));
    }

    function _createSwapModule(ProtocolDeployment memory $, address subvault) internal returns (address swapModule) {
        swapModule = $.swapModuleFactory.create(
            0,
            proxyAdmin,
            abi.encode(
                lazyVaultAdmin,
                subvault,
                Constants.TQ_GLD_SWAP_ORACLE,
                0.995e8,
                ArraysLibrary.makeAddressArray(
                    abi.encode(
                        curator1,
                        curator2,
                        Constants.ETH,
                        Constants.WETH,
                        Constants.XAUT,
                        Constants.PAXG,
                        Constants.USDC,
                        Constants.USDT,
                        Constants.USDE,
                        Constants.ETH,
                        Constants.WETH,
                        Constants.XAUT,
                        Constants.PAXG,
                        Constants.USDC,
                        Constants.USDT,
                        Constants.USDE,
                        Constants.WETH,
                        Constants.KYBERSWAP_ROUTER
                    )
                ),
                ArraysLibrary.makeBytes32Array(
                    abi.encode(
                        Permissions.SWAP_MODULE_CALLER_ROLE,
                        Permissions.SWAP_MODULE_CALLER_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                        Permissions.SWAP_MODULE_ROUTER_ROLE,
                        Permissions.SWAP_MODULE_ROUTER_ROLE
                    )
                )
            )
        );
    }

    function _createSwapModuleWithNUSD(ProtocolDeployment memory $, address subvault)
        internal
        returns (address swapModule)
    {
        swapModule = $.swapModuleFactory.create(
            0,
            proxyAdmin,
            abi.encode(
                lazyVaultAdmin,
                subvault,
                Constants.TQ_GLD_SWAP_ORACLE,
                0.995e8,
                ArraysLibrary.makeAddressArray(
                    abi.encode(
                        curator1,
                        curator2,
                        Constants.ETH,
                        Constants.WETH,
                        Constants.XAUT,
                        Constants.PAXG,
                        Constants.USDC,
                        Constants.USDT,
                        Constants.USDE,
                        Constants.NUSD,
                        Constants.ETH,
                        Constants.WETH,
                        Constants.XAUT,
                        Constants.PAXG,
                        Constants.USDC,
                        Constants.USDT,
                        Constants.USDE,
                        Constants.NUSD,
                        Constants.WETH,
                        Constants.KYBERSWAP_ROUTER,
                        Constants.NUSD_ROUTER
                    )
                ),
                ArraysLibrary.makeBytes32Array(
                    abi.encode(
                        Permissions.SWAP_MODULE_CALLER_ROLE,
                        Permissions.SWAP_MODULE_CALLER_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                        Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                        Permissions.SWAP_MODULE_ROUTER_ROLE,
                        Permissions.SWAP_MODULE_ROUTER_ROLE,
                        Permissions.SWAP_MODULE_ROUTER_ROLE
                    )
                )
            )
        );
    }

    function _createSubvault0Verifier(address subvault, address swapModule)
        internal
        returns (bytes32 merkleRoot, SubvaultCalls memory calls)
    {
        address[] memory curators = getCurators();
        string[] memory descriptions = tqGLDLibrary.getSubvault0Descriptions(subvault, swapModule, curators);
        IVerifier.VerificationPayload[] memory leaves;
        (merkleRoot, leaves) = tqGLDLibrary.getSubvault0Proofs(subvault, swapModule, curators);
        ProofLibrary.storeProofs("ethereum:tqGLDPreProd:subvault0", merkleRoot, leaves, descriptions);
        calls = tqGLDLibrary.getSubvault0SubvaultCalls(subvault, swapModule, curators, leaves);
    }

    function _getExpectedHolders(address timelockController)
        internal
        view
        returns (Vault.RoleHolder[] memory holders)
    {
        holders = new Vault.RoleHolder[](50);
        uint256 i = 0;

        // lazyVaultAdmin roles:
        holders[i++] = Vault.RoleHolder(Permissions.DEFAULT_ADMIN_ROLE, lazyVaultAdmin);

        // activeVaultAdmin roles:
        holders[i++] = Vault.RoleHolder(Permissions.ACCEPT_REPORT_ROLE, activeVaultAdmin);
        holders[i++] = Vault.RoleHolder(Permissions.SET_MERKLE_ROOT_ROLE, activeVaultAdmin);
        holders[i++] = Vault.RoleHolder(Permissions.ALLOW_CALL_ROLE, activeVaultAdmin);
        holders[i++] = Vault.RoleHolder(Permissions.DISALLOW_CALL_ROLE, activeVaultAdmin);
        holders[i++] = Vault.RoleHolder(Permissions.SET_VAULT_LIMIT_ROLE, activeVaultAdmin);
        holders[i++] = Vault.RoleHolder(Permissions.SET_SUBVAULT_LIMIT_ROLE, activeVaultAdmin);
        holders[i++] = Vault.RoleHolder(Permissions.ALLOW_SUBVAULT_ASSETS_ROLE, activeVaultAdmin);
        holders[i++] = Vault.RoleHolder(Permissions.MODIFY_VAULT_BALANCE_ROLE, activeVaultAdmin);
        holders[i++] = Vault.RoleHolder(Permissions.MODIFY_SUBVAULT_BALANCE_ROLE, activeVaultAdmin);

        // emergency pauser roles:
        holders[i++] = Vault.RoleHolder(Permissions.SET_FLAGS_ROLE, address(timelockController));
        holders[i++] = Vault.RoleHolder(Permissions.SET_MERKLE_ROOT_ROLE, address(timelockController));
        holders[i++] = Vault.RoleHolder(Permissions.SET_QUEUE_STATUS_ROLE, address(timelockController));

        // oracle updater roles:
        holders[i++] = Vault.RoleHolder(Permissions.SUBMIT_REPORTS_ROLE, oracleUpdater);

        // curator roles:
        address[] memory curators = getCurators();

        for (uint256 j = 0; j < curators.length; j++) {
            holders[i++] = Vault.RoleHolder(Permissions.CALLER_ROLE, curators[j]);
            holders[i++] = Vault.RoleHolder(Permissions.PULL_LIQUIDITY_ROLE, curators[j]);
            holders[i++] = Vault.RoleHolder(Permissions.PUSH_LIQUIDITY_ROLE, curators[j]);
        }

        assembly {
            mstore(holders, i)
        }
    }
}
