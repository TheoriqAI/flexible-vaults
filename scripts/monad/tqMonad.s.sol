// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../../test/Imports.sol";
import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "../common/ArraysLibrary.sol";
import "../common/Permissions.sol";
import "./Constants.sol";


contract TqMonadDeploy is Script, Test {
    // Actors (same as Plasma)
    address public immutable proxyAdmin = 0xE5e8dA2b0f47fA3De49dc29F5a659926f012b6cf;
    address public immutable lazyVaultAdmin = 0x08E31c49f8863c4b4ae1521AE3c1034f6cDAAcC3;
    address public immutable activeVaultAdmin = 0x4A4191203b6b930b6a70a51244B14389D9A0ac21;
    address public immutable oracleUpdater = 0x5Ba9B6fb45be77C5F075b81EA674121dCD3bAF9C;
    address public immutable curator = 0x5FFA51F64Bc40c5af3a435A95e9616cc2Df9F01B;

    uint256 public constant DEFAULT_MULTIPLIER = 0.995e8;

    function run() external {
        uint256 deployerPk = uint256(bytes32(vm.envBytes("HOT_DEPLOYER")));
        address deployer = vm.addr(deployerPk);

        vm.startBroadcast(deployerPk);

        TimelockController timelockController = new TimelockController(
            0,
            ArraysLibrary.makeAddressArray(abi.encode(deployer, lazyVaultAdmin)),
            ArraysLibrary.makeAddressArray(abi.encode(curator, activeVaultAdmin)),
            lazyVaultAdmin
        );

        Vault.RoleHolder[] memory holders = new Vault.RoleHolder[](50);
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

            // timelock roles:
            holders[i++] = Vault.RoleHolder(Permissions.SET_FLAGS_ROLE, address(timelockController));
            holders[i++] = Vault.RoleHolder(Permissions.SET_MERKLE_ROOT_ROLE, address(timelockController));
            holders[i++] = Vault.RoleHolder(Permissions.SET_QUEUE_STATUS_ROLE, address(timelockController));

            // oracle updater roles:
            holders[i++] = Vault.RoleHolder(Permissions.SUBMIT_REPORTS_ROLE, oracleUpdater);

            // curator roles:
            holders[i++] = Vault.RoleHolder(Permissions.CALLER_ROLE, curator);
            holders[i++] = Vault.RoleHolder(Permissions.PULL_LIQUIDITY_ROLE, curator);
            holders[i++] = Vault.RoleHolder(Permissions.PUSH_LIQUIDITY_ROLE, curator);

            // deployer roles:
            holders[i++] = Vault.RoleHolder(Permissions.CREATE_SUBVAULT_ROLE, deployer);
            holders[i++] = Vault.RoleHolder(Permissions.SET_VAULT_LIMIT_ROLE, deployer);
            holders[i++] = Vault.RoleHolder(Permissions.ALLOW_SUBVAULT_ASSETS_ROLE, deployer);
            holders[i++] = Vault.RoleHolder(Permissions.SET_SUBVAULT_LIMIT_ROLE, deployer);
            holders[i++] = Vault.RoleHolder(Permissions.SUBMIT_REPORTS_ROLE, deployer);
            holders[i++] = Vault.RoleHolder(Permissions.ACCEPT_REPORT_ROLE, deployer);

            assembly {
                mstore(holders, i)
            }
        }

        // Oracle assets: MON and WMON
        address[] memory oracleAssets = ArraysLibrary.makeAddressArray(abi.encode(Constants.MON, Constants.WMON, Constants.WETH));

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        VaultConfigurator.InitParams memory initParams;
        {
            IOracle.SecurityParams memory securityParams = IOracle.SecurityParams({
                maxAbsoluteDeviation: 0.005 ether,
                suspiciousAbsoluteDeviation: 0.001 ether,
                maxRelativeDeviationD18: 0.005 ether,
                suspiciousRelativeDeviationD18: 0.001 ether,
                timeout: 20 hours,
                depositInterval: 1 hours,
                redeemInterval: 2 days
            });

            initParams = VaultConfigurator.InitParams({
                version: 0,
                proxyAdmin: proxyAdmin,
                vaultAdmin: lazyVaultAdmin,
                shareManagerVersion: 0,
                shareManagerParams: abi.encode(bytes32(0), "Theoriq AlphaVault MON", "tqMON"),
                feeManagerVersion: 0,
                feeManagerParams: abi.encode(lazyVaultAdmin, lazyVaultAdmin, 0, 0, 0, 0),
                riskManagerVersion: 0,
                riskManagerParams: abi.encode(type(int256).max / 2),
                oracleVersion: 0,
                oracleParams: abi.encode(securityParams, oracleAssets),
                defaultDepositHook: address(0),
                defaultRedeemHook: address(0),
                queueLimit: 0,
                roleHolders: holders
            });
        }

        Vault vault;
        {
            (,,,, address vault_) = $.vaultConfigurator.create(initParams);
            vault = Vault(payable(vault_));
        }

        // Risk manager allowed assets: MON, WMON, WETH
        address[] memory riskManagerAssets = ArraysLibrary.makeAddressArray(
            abi.encode(Constants.MON, Constants.WMON, Constants.WETH)
        );

        // Subvault 0
        {
            IRiskManager riskManager = vault.riskManager();
            address verifier0 = $.verifierFactory.create(0, proxyAdmin, abi.encode(vault, bytes32(0)));
            address subvault0 = vault.createSubvault(0, proxyAdmin, verifier0);
            _deploySwapModule($, subvault0);
            riskManager.allowSubvaultAssets(vault.subvaultAt(0), riskManagerAssets);
            riskManager.setSubvaultLimit(vault.subvaultAt(0), type(int256).max / 2);
        }

        // Subvault 1
        {
            IRiskManager riskManager = vault.riskManager();
            address verifier1 = $.verifierFactory.create(0, proxyAdmin, abi.encode(vault, bytes32(0)));
            address subvault1 = vault.createSubvault(0, proxyAdmin, verifier1);
            _deploySwapModule($, subvault1);
            riskManager.allowSubvaultAssets(vault.subvaultAt(1), riskManagerAssets);
            riskManager.setSubvaultLimit(vault.subvaultAt(1), type(int256).max / 2);
        }

        // Oracle: submit initial price reports
        {
            IOracle oracle = vault.oracle();

            IOracle.Report[] memory reports = new IOracle.Report[](3);
            reports[0].asset = Constants.MON;
            reports[0].priceD18 = 1 ether;
            reports[1].asset = Constants.WMON;
            reports[1].priceD18 = 1 ether;
            reports[2].asset = Constants.WETH;
            reports[2].priceD18 = 1 ether;
            oracle.submitReports(reports);
        }

        // Emergency pause setup
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

        // Renounce deployer roles
        timelockController.renounceRole(timelockController.PROPOSER_ROLE(), deployer);
        timelockController.renounceRole(timelockController.CANCELLER_ROLE(), deployer);

        vault.renounceRole(Permissions.CREATE_SUBVAULT_ROLE, deployer);
        vault.renounceRole(Permissions.SET_VAULT_LIMIT_ROLE, deployer);
        vault.renounceRole(Permissions.ALLOW_SUBVAULT_ASSETS_ROLE, deployer);
        vault.renounceRole(Permissions.SET_SUBVAULT_LIMIT_ROLE, deployer);
        vault.renounceRole(Permissions.SUBMIT_REPORTS_ROLE, deployer);
        vault.renounceRole(Permissions.ACCEPT_REPORT_ROLE, deployer);

        console2.log("Vault: %s", address(vault));
        console2.log("Subvault 0: %s", vault.subvaultAt(0));
        console2.log("Subvault 1: %s", vault.subvaultAt(1));
        console2.log("Verifier 0: %s", address(Subvault(payable(vault.subvaultAt(0))).verifier()));
        console2.log("Verifier 1: %s", address(Subvault(payable(vault.subvaultAt(1))).verifier()));
        console2.log("Oracle: %s", address(vault.oracle()));
        console2.log("RiskManager: %s", address(vault.riskManager()));
        console2.log("ShareManager: %s", address(vault.shareManager()));
        console2.log("FeeManager: %s", address(vault.feeManager()));
        console2.log("TimelockController: %s", address(timelockController));

        vm.stopBroadcast();
    }

    function _deploySwapModule(ProtocolDeployment memory $, address subvault) internal returns (address) {
        // Tokens: MON, WMON, USDC, WETH as tokenIn and tokenOut
        // Routers: KyberSwap + WMON
        address[] memory actors = ArraysLibrary.makeAddressArray(
            abi.encode(
                // CALLER
                curator,
                // TOKEN_IN: MON, WMON, USDC, WETH
                Constants.MON,
                Constants.WMON,
                Constants.USDC,
                Constants.WETH,
                // TOKEN_OUT: MON, WMON, USDC, WETH
                Constants.MON,
                Constants.WMON,
                Constants.USDC,
                Constants.WETH,
                // ROUTER: KyberSwap, WMON
                Constants.KYBERSWAP_ROUTER,
                Constants.WMON
            )
        );
        bytes32[] memory permissions = ArraysLibrary.makeBytes32Array(
            abi.encode(
                Permissions.SWAP_MODULE_CALLER_ROLE,
                // TOKEN_IN x4
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                Permissions.SWAP_MODULE_TOKEN_IN_ROLE,
                // TOKEN_OUT x4
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                Permissions.SWAP_MODULE_TOKEN_OUT_ROLE,
                // ROUTER x2
                Permissions.SWAP_MODULE_ROUTER_ROLE,
                Permissions.SWAP_MODULE_ROUTER_ROLE
            )
        );
        return $.swapModuleFactory.create(
            0,
            proxyAdmin,
            abi.encode(lazyVaultAdmin, subvault, Constants.AAVE_V3_ORACLE, DEFAULT_MULTIPLIER, actors, permissions)
        );
    }
}
