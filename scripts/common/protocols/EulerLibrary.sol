// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ABILibrary} from "../ABILibrary.sol";
import {ArraysLibrary, Call} from "../ArraysLibrary.sol";
import {JsonLibrary} from "../JsonLibrary.sol";
import {ParameterLibrary} from "../ParameterLibrary.sol";
import {BitmaskVerifier, IVerifier, ProofLibrary} from "../ProofLibrary.sol";

import {IEVC} from "../interfaces/IEVC.sol";
import {IEulerVault} from "../interfaces/IEulerVault.sol";

library EulerLibrary {
    using ParameterLibrary for ParameterLibrary.Parameter[];

    struct Info {
        address subvault;
        string subvaultName;
        address curator;
        address evc; // EVC address (set to address(0) to skip EVC permissions)
        address[] supplyVaults; // EVault addresses for deposit/withdraw
        address[] borrowVaults; // EVault addresses for borrow/repay/liquidate
    }

    function _evcLength(Info memory $) internal pure returns (uint256) {
        if ($.evc == address(0)) return 0;
        // enableCollateral + disableCollateral per supply vault
        // enableController per borrow vault
        // disableController x1
        return $.supplyVaults.length * 2 + $.borrowVaults.length + 1;
    }

    function getEulerProofs(BitmaskVerifier bitmaskVerifier, Info memory $)
        internal
        view
        returns (IVerifier.VerificationPayload[] memory leaves)
    {
        uint256 length = $.supplyVaults.length * 3 + $.borrowVaults.length * 4 + _evcLength($);
        leaves = new IVerifier.VerificationPayload[](length);
        uint256 index = 0;

        for (uint256 i = 0; i < $.supplyVaults.length; i++) {
            address vault = $.supplyVaults[i];
            address asset = IERC4626(vault).asset();

            /// @dev approve underlying to EVault
            leaves[index++] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                $.curator,
                asset,
                0,
                abi.encodeCall(IERC20.approve, (vault, 0)),
                ProofLibrary.makeBitmask(
                    true, true, true, true, abi.encodeCall(IERC20.approve, (address(type(uint160).max), 0))
                )
            );
            /// @dev deposit into EVault
            leaves[index++] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                $.curator,
                vault,
                0,
                abi.encodeCall(IERC4626.deposit, (0, $.subvault)),
                ProofLibrary.makeBitmask(
                    true, true, true, true, abi.encodeCall(IERC4626.deposit, (0, address(type(uint160).max)))
                )
            );
            /// @dev withdraw from EVault
            leaves[index++] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                $.curator,
                vault,
                0,
                abi.encodeCall(IERC4626.withdraw, (0, $.subvault, $.subvault)),
                ProofLibrary.makeBitmask(
                    true,
                    true,
                    true,
                    true,
                    abi.encodeCall(IERC4626.withdraw, (0, address(type(uint160).max), address(type(uint160).max)))
                )
            );
        }

        for (uint256 i = 0; i < $.borrowVaults.length; i++) {
            address vault = $.borrowVaults[i];
            address asset = IERC4626(vault).asset();

            /// @dev approve underlying to EVault (for repay)
            leaves[index++] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                $.curator,
                asset,
                0,
                abi.encodeCall(IERC20.approve, (vault, 0)),
                ProofLibrary.makeBitmask(
                    true, true, true, true, abi.encodeCall(IERC20.approve, (address(type(uint160).max), 0))
                )
            );
            /// @dev borrow from EVault
            leaves[index++] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                $.curator,
                vault,
                0,
                abi.encodeCall(IEulerVault.borrow, (0, $.subvault)),
                ProofLibrary.makeBitmask(
                    true, true, true, true, abi.encodeCall(IEulerVault.borrow, (0, address(type(uint160).max)))
                )
            );
            /// @dev repay to EVault
            leaves[index++] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                $.curator,
                vault,
                0,
                abi.encodeCall(IEulerVault.repay, (0, $.subvault)),
                ProofLibrary.makeBitmask(
                    true, true, true, true, abi.encodeCall(IEulerVault.repay, (0, address(type(uint160).max)))
                )
            );
            /// @dev liquidate on EVault
            leaves[index++] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                $.curator,
                vault,
                0,
                abi.encodeCall(IEulerVault.liquidate, (address(0), address(0), 0, 0)),
                ProofLibrary.makeBitmask(
                    true, true, true, true, abi.encodeCall(IEulerVault.liquidate, (address(0), address(0), 0, 0))
                )
            );
        }

        /// @dev EVC permissions for borrowing
        if ($.evc != address(0)) {
            // enableCollateral + disableCollateral for each supply vault
            for (uint256 i = 0; i < $.supplyVaults.length; i++) {
                address vault = $.supplyVaults[i];
                leaves[index++] = ProofLibrary.makeVerificationPayload(
                    bitmaskVerifier,
                    $.curator,
                    $.evc,
                    0,
                    abi.encodeCall(IEVC.enableCollateral, ($.subvault, vault)),
                    ProofLibrary.makeBitmask(
                        true,
                        true,
                        true,
                        true,
                        abi.encodeCall(IEVC.enableCollateral, (address(type(uint160).max), address(type(uint160).max)))
                    )
                );
                leaves[index++] = ProofLibrary.makeVerificationPayload(
                    bitmaskVerifier,
                    $.curator,
                    $.evc,
                    0,
                    abi.encodeCall(IEVC.disableCollateral, ($.subvault, vault)),
                    ProofLibrary.makeBitmask(
                        true,
                        true,
                        true,
                        true,
                        abi.encodeCall(IEVC.disableCollateral, (address(type(uint160).max), address(type(uint160).max)))
                    )
                );
            }
            // enableController for each borrow vault
            for (uint256 i = 0; i < $.borrowVaults.length; i++) {
                address vault = $.borrowVaults[i];
                leaves[index++] = ProofLibrary.makeVerificationPayload(
                    bitmaskVerifier,
                    $.curator,
                    $.evc,
                    0,
                    abi.encodeCall(IEVC.enableController, ($.subvault, vault)),
                    ProofLibrary.makeBitmask(
                        true,
                        true,
                        true,
                        true,
                        abi.encodeCall(IEVC.enableController, (address(type(uint160).max), address(type(uint160).max)))
                    )
                );
            }
            // disableController
            leaves[index++] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                $.curator,
                $.evc,
                0,
                abi.encodeCall(IEVC.disableController, ($.subvault)),
                ProofLibrary.makeBitmask(
                    true, true, true, true, abi.encodeCall(IEVC.disableController, (address(type(uint160).max)))
                )
            );
        }
    }

    function getEulerDescriptions(Info memory $) internal view returns (string[] memory descriptions) {
        uint256 length = $.supplyVaults.length * 3 + $.borrowVaults.length * 4 + _evcLength($);
        descriptions = new string[](length);
        uint256 index = 0;
        ParameterLibrary.Parameter[] memory innerParameters;

        for (uint256 i = 0; i < $.supplyVaults.length; i++) {
            address vault = $.supplyVaults[i];
            address asset = IERC4626(vault).asset();
            string memory assetSymbol = IERC20Metadata(asset).symbol();
            string memory vaultName = IERC20Metadata(vault).symbol();

            innerParameters = ParameterLibrary.build("to", Strings.toHexString(vault)).addAny("amount");
            descriptions[index++] = JsonLibrary.toJson(
                string(abi.encodePacked("IERC20(", assetSymbol, ").approve(EulerVault(", vaultName, "), anyInt)")),
                ABILibrary.getABI(IERC20.approve.selector),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(asset), "0"),
                innerParameters
            );

            innerParameters =
                ParameterLibrary.build("assets", "any").add("receiver", Strings.toHexString($.subvault));
            descriptions[index++] = JsonLibrary.toJson(
                string(abi.encodePacked("EulerVault(", vaultName, ").deposit(anyInt, ", $.subvaultName, ")")),
                ABILibrary.getABI(IERC4626.deposit.selector),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(vault), "0"),
                innerParameters
            );

            innerParameters = ParameterLibrary.build("assets", "any").add("receiver", Strings.toHexString($.subvault))
                .add("owner", Strings.toHexString($.subvault));
            descriptions[index++] = JsonLibrary.toJson(
                string(
                    abi.encodePacked(
                        "EulerVault(", vaultName, ").withdraw(anyInt, ", $.subvaultName, ", ", $.subvaultName, ")"
                    )
                ),
                ABILibrary.getABI(IERC4626.withdraw.selector),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(vault), "0"),
                innerParameters
            );
        }

        for (uint256 i = 0; i < $.borrowVaults.length; i++) {
            address vault = $.borrowVaults[i];
            address asset = IERC4626(vault).asset();
            string memory assetSymbol = IERC20Metadata(asset).symbol();
            string memory vaultName = IERC20Metadata(vault).symbol();

            innerParameters = ParameterLibrary.build("to", Strings.toHexString(vault)).addAny("amount");
            descriptions[index++] = JsonLibrary.toJson(
                string(abi.encodePacked("IERC20(", assetSymbol, ").approve(EulerVault(", vaultName, "), anyInt)")),
                ABILibrary.getABI(IERC20.approve.selector),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(asset), "0"),
                innerParameters
            );

            innerParameters =
                ParameterLibrary.build("amount", "any").add("receiver", Strings.toHexString($.subvault));
            descriptions[index++] = JsonLibrary.toJson(
                string(abi.encodePacked("EulerVault(", vaultName, ").borrow(anyInt, ", $.subvaultName, ")")),
                ABILibrary.getABI(IEulerVault.borrow.selector),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(vault), "0"),
                innerParameters
            );

            innerParameters =
                ParameterLibrary.build("amount", "any").add("receiver", Strings.toHexString($.subvault));
            descriptions[index++] = JsonLibrary.toJson(
                string(abi.encodePacked("EulerVault(", vaultName, ").repay(anyInt, ", $.subvaultName, ")")),
                ABILibrary.getABI(IEulerVault.repay.selector),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(vault), "0"),
                innerParameters
            );

            innerParameters = ParameterLibrary.build("violator", "any").addAny("collateral").addAny("repayAssets")
                .addAny("minYieldBalance");
            descriptions[index++] = JsonLibrary.toJson(
                string(abi.encodePacked("EulerVault(", vaultName, ").liquidate(any, any, anyInt, anyInt)")),
                ABILibrary.getABI(IEulerVault.liquidate.selector),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(vault), "0"),
                innerParameters
            );
        }

        if ($.evc != address(0)) {
            for (uint256 i = 0; i < $.supplyVaults.length; i++) {
                string memory vaultName = IERC20Metadata($.supplyVaults[i]).symbol();

                innerParameters = ParameterLibrary.build("account", Strings.toHexString($.subvault)).add(
                    "vault", Strings.toHexString($.supplyVaults[i])
                );
                descriptions[index++] = JsonLibrary.toJson(
                    string(abi.encodePacked("EVC.enableCollateral(", $.subvaultName, ", ", vaultName, ")")),
                    ABILibrary.getABI(IEVC.enableCollateral.selector),
                    ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.evc), "0"),
                    innerParameters
                );
                descriptions[index++] = JsonLibrary.toJson(
                    string(abi.encodePacked("EVC.disableCollateral(", $.subvaultName, ", ", vaultName, ")")),
                    ABILibrary.getABI(IEVC.disableCollateral.selector),
                    ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.evc), "0"),
                    innerParameters
                );
            }
            for (uint256 i = 0; i < $.borrowVaults.length; i++) {
                string memory vaultName = IERC20Metadata($.borrowVaults[i]).symbol();

                innerParameters = ParameterLibrary.build("account", Strings.toHexString($.subvault)).add(
                    "vault", Strings.toHexString($.borrowVaults[i])
                );
                descriptions[index++] = JsonLibrary.toJson(
                    string(abi.encodePacked("EVC.enableController(", $.subvaultName, ", ", vaultName, ")")),
                    ABILibrary.getABI(IEVC.enableController.selector),
                    ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.evc), "0"),
                    innerParameters
                );
            }
            innerParameters = ParameterLibrary.build("account", Strings.toHexString($.subvault));
            descriptions[index++] = JsonLibrary.toJson(
                string(abi.encodePacked("EVC.disableController(", $.subvaultName, ")")),
                ABILibrary.getABI(IEVC.disableController.selector),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.evc), "0"),
                innerParameters
            );
        }
    }

    function getEulerDescriptionsLean(Info memory $) internal view returns (string[] memory descriptions) {
        uint256 length = $.supplyVaults.length * 3 + $.borrowVaults.length * 4 + _evcLength($);
        descriptions = new string[](length);
        uint256 index = 0;
        ParameterLibrary.Parameter[] memory innerParameters;

        for (uint256 i = 0; i < $.supplyVaults.length; i++) {
            address vault = $.supplyVaults[i];
            address asset = IERC4626(vault).asset();
            string memory assetSymbol = IERC20Metadata(asset).symbol();
            string memory vaultName = IERC20Metadata(vault).symbol();

            innerParameters = ParameterLibrary.build("to", Strings.toHexString(vault)).addAny("amount");
            descriptions[index++] = JsonLibrary.toJsonLean(
                string(abi.encodePacked("IERC20(", assetSymbol, ").approve(EulerVault(", vaultName, "), anyInt)")),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(asset), "0"),
                innerParameters
            );

            innerParameters =
                ParameterLibrary.build("assets", "any").add("receiver", Strings.toHexString($.subvault));
            descriptions[index++] = JsonLibrary.toJsonLean(
                string(abi.encodePacked("EulerVault(", vaultName, ").deposit(anyInt, ", $.subvaultName, ")")),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(vault), "0"),
                innerParameters
            );

            innerParameters = ParameterLibrary.build("assets", "any").add("receiver", Strings.toHexString($.subvault))
                .add("owner", Strings.toHexString($.subvault));
            descriptions[index++] = JsonLibrary.toJsonLean(
                string(
                    abi.encodePacked(
                        "EulerVault(", vaultName, ").withdraw(anyInt, ", $.subvaultName, ", ", $.subvaultName, ")"
                    )
                ),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(vault), "0"),
                innerParameters
            );
        }

        for (uint256 i = 0; i < $.borrowVaults.length; i++) {
            address vault = $.borrowVaults[i];
            address asset = IERC4626(vault).asset();
            string memory assetSymbol = IERC20Metadata(asset).symbol();
            string memory vaultName = IERC20Metadata(vault).symbol();

            innerParameters = ParameterLibrary.build("to", Strings.toHexString(vault)).addAny("amount");
            descriptions[index++] = JsonLibrary.toJsonLean(
                string(abi.encodePacked("IERC20(", assetSymbol, ").approve(EulerVault(", vaultName, "), anyInt)")),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(asset), "0"),
                innerParameters
            );

            innerParameters =
                ParameterLibrary.build("amount", "any").add("receiver", Strings.toHexString($.subvault));
            descriptions[index++] = JsonLibrary.toJsonLean(
                string(abi.encodePacked("EulerVault(", vaultName, ").borrow(anyInt, ", $.subvaultName, ")")),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(vault), "0"),
                innerParameters
            );

            innerParameters =
                ParameterLibrary.build("amount", "any").add("receiver", Strings.toHexString($.subvault));
            descriptions[index++] = JsonLibrary.toJsonLean(
                string(abi.encodePacked("EulerVault(", vaultName, ").repay(anyInt, ", $.subvaultName, ")")),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(vault), "0"),
                innerParameters
            );

            innerParameters = ParameterLibrary.build("violator", "any").addAny("collateral").addAny("repayAssets")
                .addAny("minYieldBalance");
            descriptions[index++] = JsonLibrary.toJsonLean(
                string(abi.encodePacked("EulerVault(", vaultName, ").liquidate(any, any, anyInt, anyInt)")),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString(vault), "0"),
                innerParameters
            );
        }

        if ($.evc != address(0)) {
            for (uint256 i = 0; i < $.supplyVaults.length; i++) {
                string memory vaultName = IERC20Metadata($.supplyVaults[i]).symbol();

                innerParameters = ParameterLibrary.build("account", Strings.toHexString($.subvault)).add(
                    "vault", Strings.toHexString($.supplyVaults[i])
                );
                descriptions[index++] = JsonLibrary.toJsonLean(
                    string(abi.encodePacked("EVC.enableCollateral(", $.subvaultName, ", ", vaultName, ")")),
                    ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.evc), "0"),
                    innerParameters
                );
                descriptions[index++] = JsonLibrary.toJsonLean(
                    string(abi.encodePacked("EVC.disableCollateral(", $.subvaultName, ", ", vaultName, ")")),
                    ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.evc), "0"),
                    innerParameters
                );
            }
            for (uint256 i = 0; i < $.borrowVaults.length; i++) {
                string memory vaultName = IERC20Metadata($.borrowVaults[i]).symbol();

                innerParameters = ParameterLibrary.build("account", Strings.toHexString($.subvault)).add(
                    "vault", Strings.toHexString($.borrowVaults[i])
                );
                descriptions[index++] = JsonLibrary.toJsonLean(
                    string(abi.encodePacked("EVC.enableController(", $.subvaultName, ", ", vaultName, ")")),
                    ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.evc), "0"),
                    innerParameters
                );
            }
            innerParameters = ParameterLibrary.build("account", Strings.toHexString($.subvault));
            descriptions[index++] = JsonLibrary.toJsonLean(
                string(abi.encodePacked("EVC.disableController(", $.subvaultName, ")")),
                ParameterLibrary.build(Strings.toHexString($.curator), Strings.toHexString($.evc), "0"),
                innerParameters
            );
        }
    }

    function getEulerCalls(Info memory $) internal view returns (Call[][] memory calls) {
        uint256 index = 0;
        calls = new Call[][]($.supplyVaults.length * 3 + $.borrowVaults.length * 4 + _evcLength($));

        for (uint256 j = 0; j < $.supplyVaults.length; j++) {
            address vault = $.supplyVaults[j];
            address asset = IERC4626(vault).asset();

            /// @dev approve underlying to EVault
            {
                Call[] memory tmp = new Call[](16);
                uint256 i = 0;
                tmp[i++] = Call($.curator, asset, 0, abi.encodeCall(IERC20.approve, (vault, 0)), true);
                tmp[i++] = Call($.curator, asset, 0, abi.encodeCall(IERC20.approve, (vault, 1 ether)), true);
                tmp[i++] = Call(address(0xdead), asset, 0, abi.encodeCall(IERC20.approve, (vault, 1 ether)), false);
                tmp[i++] = Call($.curator, address(0xdead), 0, abi.encodeCall(IERC20.approve, (vault, 1 ether)), false);
                tmp[i++] = Call($.curator, asset, 0, abi.encodeCall(IERC20.approve, (address(0xdead), 1 ether)), false);
                tmp[i++] = Call($.curator, asset, 1 wei, abi.encodeCall(IERC20.approve, (vault, 1 ether)), false);
                tmp[i++] = Call($.curator, asset, 0, abi.encode(IERC20.approve.selector, vault, 1 ether), false);
                assembly {
                    mstore(tmp, i)
                }
                calls[index++] = tmp;
            }
            /// @dev deposit into EVault
            {
                Call[] memory tmp = new Call[](16);
                uint256 i = 0;
                tmp[i++] = Call($.curator, vault, 0, abi.encodeCall(IERC4626.deposit, (0, $.subvault)), true);
                tmp[i++] = Call($.curator, vault, 0, abi.encodeCall(IERC4626.deposit, (1 ether, $.subvault)), true);
                tmp[i++] =
                    Call(address(0xdead), vault, 0, abi.encodeCall(IERC4626.deposit, (1 ether, $.subvault)), false);
                tmp[i++] =
                    Call($.curator, address(0xdead), 0, abi.encodeCall(IERC4626.deposit, (1 ether, $.subvault)), false);
                tmp[i++] =
                    Call($.curator, vault, 0, abi.encodeCall(IERC4626.deposit, (1 ether, address(0xdead))), false);
                tmp[i++] =
                    Call($.curator, vault, 1 wei, abi.encodeCall(IERC4626.deposit, (1 ether, $.subvault)), false);
                tmp[i++] =
                    Call($.curator, vault, 0, abi.encode(IERC4626.deposit.selector, 1 ether, $.subvault), false);
                assembly {
                    mstore(tmp, i)
                }
                calls[index++] = tmp;
            }
            /// @dev withdraw from EVault
            {
                Call[] memory tmp = new Call[](16);
                uint256 i = 0;
                tmp[i++] =
                    Call($.curator, vault, 0, abi.encodeCall(IERC4626.withdraw, (0, $.subvault, $.subvault)), true);
                tmp[i++] = Call(
                    $.curator, vault, 0, abi.encodeCall(IERC4626.withdraw, (1 ether, $.subvault, $.subvault)), true
                );
                tmp[i++] = Call(
                    address(0xdead), vault, 0, abi.encodeCall(IERC4626.withdraw, (1 ether, $.subvault, $.subvault)), false
                );
                tmp[i++] = Call(
                    $.curator, address(0xdead), 0, abi.encodeCall(IERC4626.withdraw, (1 ether, $.subvault, $.subvault)), false
                );
                tmp[i++] = Call(
                    $.curator, vault, 0, abi.encodeCall(IERC4626.withdraw, (1 ether, address(0xdead), $.subvault)), false
                );
                tmp[i++] = Call(
                    $.curator, vault, 0, abi.encodeCall(IERC4626.withdraw, (1 ether, $.subvault, address(0xdead))), false
                );
                tmp[i++] = Call(
                    $.curator, vault, 1 wei, abi.encodeCall(IERC4626.withdraw, (1 ether, $.subvault, $.subvault)), false
                );
                tmp[i++] = Call(
                    $.curator, vault, 0, abi.encode(IERC4626.withdraw.selector, 1 ether, $.subvault, $.subvault), false
                );
                assembly {
                    mstore(tmp, i)
                }
                calls[index++] = tmp;
            }
        }

        for (uint256 j = 0; j < $.borrowVaults.length; j++) {
            address vault = $.borrowVaults[j];
            address asset = IERC4626(vault).asset();

            /// @dev approve underlying to EVault (for repay)
            {
                Call[] memory tmp = new Call[](16);
                uint256 i = 0;
                tmp[i++] = Call($.curator, asset, 0, abi.encodeCall(IERC20.approve, (vault, 0)), true);
                tmp[i++] = Call($.curator, asset, 0, abi.encodeCall(IERC20.approve, (vault, 1 ether)), true);
                tmp[i++] = Call(address(0xdead), asset, 0, abi.encodeCall(IERC20.approve, (vault, 1 ether)), false);
                tmp[i++] = Call($.curator, address(0xdead), 0, abi.encodeCall(IERC20.approve, (vault, 1 ether)), false);
                tmp[i++] = Call($.curator, asset, 0, abi.encodeCall(IERC20.approve, (address(0xdead), 1 ether)), false);
                tmp[i++] = Call($.curator, asset, 1 wei, abi.encodeCall(IERC20.approve, (vault, 1 ether)), false);
                tmp[i++] = Call($.curator, asset, 0, abi.encode(IERC20.approve.selector, vault, 1 ether), false);
                assembly {
                    mstore(tmp, i)
                }
                calls[index++] = tmp;
            }
            /// @dev borrow from EVault
            {
                Call[] memory tmp = new Call[](16);
                uint256 i = 0;
                tmp[i++] = Call($.curator, vault, 0, abi.encodeCall(IEulerVault.borrow, (0, $.subvault)), true);
                tmp[i++] = Call($.curator, vault, 0, abi.encodeCall(IEulerVault.borrow, (1 ether, $.subvault)), true);
                tmp[i++] =
                    Call(address(0xdead), vault, 0, abi.encodeCall(IEulerVault.borrow, (1 ether, $.subvault)), false);
                tmp[i++] =
                    Call($.curator, address(0xdead), 0, abi.encodeCall(IEulerVault.borrow, (1 ether, $.subvault)), false);
                tmp[i++] =
                    Call($.curator, vault, 0, abi.encodeCall(IEulerVault.borrow, (1 ether, address(0xdead))), false);
                tmp[i++] =
                    Call($.curator, vault, 1 wei, abi.encodeCall(IEulerVault.borrow, (1 ether, $.subvault)), false);
                tmp[i++] =
                    Call($.curator, vault, 0, abi.encode(IEulerVault.borrow.selector, 1 ether, $.subvault), false);
                assembly {
                    mstore(tmp, i)
                }
                calls[index++] = tmp;
            }
            /// @dev repay to EVault
            {
                Call[] memory tmp = new Call[](16);
                uint256 i = 0;
                tmp[i++] = Call($.curator, vault, 0, abi.encodeCall(IEulerVault.repay, (0, $.subvault)), true);
                tmp[i++] = Call($.curator, vault, 0, abi.encodeCall(IEulerVault.repay, (1 ether, $.subvault)), true);
                tmp[i++] =
                    Call(address(0xdead), vault, 0, abi.encodeCall(IEulerVault.repay, (1 ether, $.subvault)), false);
                tmp[i++] =
                    Call($.curator, address(0xdead), 0, abi.encodeCall(IEulerVault.repay, (1 ether, $.subvault)), false);
                tmp[i++] =
                    Call($.curator, vault, 0, abi.encodeCall(IEulerVault.repay, (1 ether, address(0xdead))), false);
                tmp[i++] =
                    Call($.curator, vault, 1 wei, abi.encodeCall(IEulerVault.repay, (1 ether, $.subvault)), false);
                tmp[i++] =
                    Call($.curator, vault, 0, abi.encode(IEulerVault.repay.selector, 1 ether, $.subvault), false);
                assembly {
                    mstore(tmp, i)
                }
                calls[index++] = tmp;
            }
            /// @dev liquidate on EVault
            {
                Call[] memory tmp = new Call[](16);
                uint256 i = 0;
                tmp[i++] = Call(
                    $.curator, vault, 0, abi.encodeCall(IEulerVault.liquidate, (address(0x1), address(0x2), 1 ether, 0)), true
                );
                tmp[i++] = Call(
                    $.curator, vault, 0, abi.encodeCall(IEulerVault.liquidate, (address(0x3), address(0x4), 0, 0)), true
                );
                tmp[i++] = Call(
                    address(0xdead), vault, 0, abi.encodeCall(IEulerVault.liquidate, (address(0x1), address(0x2), 1 ether, 0)), false
                );
                tmp[i++] = Call(
                    $.curator, address(0xdead), 0, abi.encodeCall(IEulerVault.liquidate, (address(0x1), address(0x2), 1 ether, 0)), false
                );
                tmp[i++] = Call(
                    $.curator, vault, 1 wei, abi.encodeCall(IEulerVault.liquidate, (address(0x1), address(0x2), 1 ether, 0)), false
                );
                tmp[i++] = Call(
                    $.curator, vault, 0, abi.encode(IEulerVault.liquidate.selector, address(0x1), address(0x2), 1 ether, 0), false
                );
                assembly {
                    mstore(tmp, i)
                }
                calls[index++] = tmp;
            }
        }

        /// @dev EVC calls
        if ($.evc != address(0)) {
            for (uint256 j = 0; j < $.supplyVaults.length; j++) {
                address vault = $.supplyVaults[j];
                // enableCollateral
                {
                    Call[] memory tmp = new Call[](16);
                    uint256 i = 0;
                    tmp[i++] = Call($.curator, $.evc, 0, abi.encodeCall(IEVC.enableCollateral, ($.subvault, vault)), true);
                    tmp[i++] = Call(address(0xdead), $.evc, 0, abi.encodeCall(IEVC.enableCollateral, ($.subvault, vault)), false);
                    tmp[i++] = Call($.curator, address(0xdead), 0, abi.encodeCall(IEVC.enableCollateral, ($.subvault, vault)), false);
                    tmp[i++] = Call($.curator, $.evc, 0, abi.encodeCall(IEVC.enableCollateral, (address(0xdead), vault)), false);
                    tmp[i++] = Call($.curator, $.evc, 0, abi.encodeCall(IEVC.enableCollateral, ($.subvault, address(0xdead))), false);
                    tmp[i++] = Call($.curator, $.evc, 1 wei, abi.encodeCall(IEVC.enableCollateral, ($.subvault, vault)), false);
                    assembly {
                        mstore(tmp, i)
                    }
                    calls[index++] = tmp;
                }
                // disableCollateral
                {
                    Call[] memory tmp = new Call[](16);
                    uint256 i = 0;
                    tmp[i++] = Call($.curator, $.evc, 0, abi.encodeCall(IEVC.disableCollateral, ($.subvault, vault)), true);
                    tmp[i++] = Call(address(0xdead), $.evc, 0, abi.encodeCall(IEVC.disableCollateral, ($.subvault, vault)), false);
                    tmp[i++] = Call($.curator, address(0xdead), 0, abi.encodeCall(IEVC.disableCollateral, ($.subvault, vault)), false);
                    tmp[i++] = Call($.curator, $.evc, 0, abi.encodeCall(IEVC.disableCollateral, (address(0xdead), vault)), false);
                    tmp[i++] = Call($.curator, $.evc, 0, abi.encodeCall(IEVC.disableCollateral, ($.subvault, address(0xdead))), false);
                    tmp[i++] = Call($.curator, $.evc, 1 wei, abi.encodeCall(IEVC.disableCollateral, ($.subvault, vault)), false);
                    assembly {
                        mstore(tmp, i)
                    }
                    calls[index++] = tmp;
                }
            }
            for (uint256 j = 0; j < $.borrowVaults.length; j++) {
                address vault = $.borrowVaults[j];
                // enableController
                {
                    Call[] memory tmp = new Call[](16);
                    uint256 i = 0;
                    tmp[i++] = Call($.curator, $.evc, 0, abi.encodeCall(IEVC.enableController, ($.subvault, vault)), true);
                    tmp[i++] = Call(address(0xdead), $.evc, 0, abi.encodeCall(IEVC.enableController, ($.subvault, vault)), false);
                    tmp[i++] = Call($.curator, address(0xdead), 0, abi.encodeCall(IEVC.enableController, ($.subvault, vault)), false);
                    tmp[i++] = Call($.curator, $.evc, 0, abi.encodeCall(IEVC.enableController, (address(0xdead), vault)), false);
                    tmp[i++] = Call($.curator, $.evc, 0, abi.encodeCall(IEVC.enableController, ($.subvault, address(0xdead))), false);
                    tmp[i++] = Call($.curator, $.evc, 1 wei, abi.encodeCall(IEVC.enableController, ($.subvault, vault)), false);
                    assembly {
                        mstore(tmp, i)
                    }
                    calls[index++] = tmp;
                }
            }
            // disableController
            {
                Call[] memory tmp = new Call[](16);
                uint256 i = 0;
                tmp[i++] = Call($.curator, $.evc, 0, abi.encodeCall(IEVC.disableController, ($.subvault)), true);
                tmp[i++] = Call(address(0xdead), $.evc, 0, abi.encodeCall(IEVC.disableController, ($.subvault)), false);
                tmp[i++] = Call($.curator, address(0xdead), 0, abi.encodeCall(IEVC.disableController, ($.subvault)), false);
                tmp[i++] = Call($.curator, $.evc, 0, abi.encodeCall(IEVC.disableController, (address(0xdead))), false);
                tmp[i++] = Call($.curator, $.evc, 1 wei, abi.encodeCall(IEVC.disableController, ($.subvault)), false);
                assembly {
                    mstore(tmp, i)
                }
                calls[index++] = tmp;
            }
        }
    }
}
