// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IVerifier} from "../../src/permissions/Verifier.sol";
import {ICallModule} from "../../src/interfaces/modules/ICallModule.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IMorpho {
    struct MarketParams {
        address loanToken;
        address collateralToken;
        address oracle;
        address irm;
        uint256 lltv;
    }

    function withdraw(
        MarketParams calldata marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256, uint256);

    function supply(
        MarketParams calldata marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes calldata data
    ) external returns (uint256, uint256);
}

interface IAavePool {
    function repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf)
        external
        returns (uint256);
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
        external;
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
        external;
}

/**
 * @title EncodeSv0Rebalance
 * @notice Encode calldata for SV0 rebalance:
 *         1. Approve XAUT for Aave
 *         2. Supply 17628 XAUT to Aave
 *         3. Morpho withdraw 1500 USDC from PT-sNUSD market
 *         4. Approve USDC for Aave
 *         5. Aave repay 300 USDC
 *         6. Aave borrow 1200 USDe
 *         7. Approve USDC for Morpho
 *         8. Supply 1200 USDC to Morpho PT-reUSD market
 *
 * Run: source .env && forge script scripts/ethereum/EncodeSv0Rebalance.s.sol --via-ir --rpc-url alchemy -vvv
 */
contract EncodeSv0Rebalance is Script {
    address constant SV0 = 0x7585770a2d08A276AF5F5980F54eCa8C25e33987;
    address constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address constant AAVE_CORE = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address constant XAUT = 0x68749665FF8D2d112Fa859AA293F07A622782F38;

    // Morpho market 1 params (USDC / PT-sNUSD-5MAR2026)
    address constant M1_COLLATERAL = 0x54Bf2659B5CdFd86b75920e93C0844c0364F5166;
    address constant M1_ORACLE = 0xe8465B52E106d98157d82b46cA566CB9d09482A9;
    address constant M1_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint256 constant M1_LLTV = 770000000000000000;

    // Morpho market 3 params (USDC / PT-reUSD-25JUN2026)
    address constant M3_COLLATERAL = 0x3EAA0F0f0A5d3D595ae4e4b0D27f439d01c3E7b2;
    address constant M3_ORACLE = 0x12d66602C691Aa93E90415aB22FB0760695AC768;
    address constant M3_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;
    uint256 constant M3_LLTV = 915000000000000000;

    function _getPayload(string memory json, uint256 index)
        internal
        pure
        returns (IVerifier.VerificationPayload memory)
    {
        bytes memory verificationData =
            vm.parseJsonBytes(json, string.concat(".merkle_proofs[", vm.toString(index), "].verificationData"));
        bytes memory proofRaw =
            vm.parseJson(json, string.concat(".merkle_proofs[", vm.toString(index), "].proof"));
        bytes32[] memory proof = abi.decode(proofRaw, (bytes32[]));

        return IVerifier.VerificationPayload({
            verificationType: IVerifier.VerificationType.CUSTOM_VERIFIER,
            verificationData: verificationData,
            proof: proof
        });
    }

    function _encode(address where, bytes memory data, IVerifier.VerificationPayload memory payload)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeCall(ICallModule.call, (where, 0, data, payload));
    }

    function run() external view {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/preProd/tqGold/sv0-all.json");
        string memory json = vm.readFile(path);

        console.log("============================================");
        console.log("  SV0 Rebalance - Encoded Calldata for Safe");
        console.log("============================================");
        console.log("");
        console.log("Subvault (target for all txs): %s", SV0);
        console.log("Caller: curator1 (0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec)");
        console.log("Value: 0 for all transactions");
        console.log("");

        // === TX 1: Approve XAUT for Aave (index 31) ===
        {
            console.log("--------------------------------------------");
            console.log("TX 1: Approve XAUT for Aave");
            console.log("--------------------------------------------");

            bytes memory innerCalldata = abi.encodeCall(IERC20.approve, (AAVE_CORE, 17628));
            bytes memory encoded = _encode(XAUT, innerCalldata, _getPayload(json, 31));

            console.log("Calldata:");
            console.logBytes(encoded);
            console.log("");
        }

        // === TX 2: Supply 17628 XAUT to Aave (index 32) ===
        {
            console.log("--------------------------------------------");
            console.log("TX 2: Supply 17628 XAUT to Aave");
            console.log("--------------------------------------------");

            bytes memory innerCalldata = abi.encodeCall(IAavePool.supply, (XAUT, 17628, SV0, 0));
            bytes memory encoded = _encode(AAVE_CORE, innerCalldata, _getPayload(json, 32));

            console.log("Calldata:");
            console.logBytes(encoded);
            console.log("");
        }

        // === TX 3: Morpho withdraw 1500 USDC from PT-sNUSD market (index 84) ===
        {
            console.log("--------------------------------------------");
            console.log("TX 3: Morpho Withdraw 1500 USDC (PT-sNUSD market)");
            console.log("--------------------------------------------");

            IMorpho.MarketParams memory marketParams = IMorpho.MarketParams({
                loanToken: USDC,
                collateralToken: M1_COLLATERAL,
                oracle: M1_ORACLE,
                irm: M1_IRM,
                lltv: M1_LLTV
            });

            bytes memory innerCalldata = abi.encodeCall(IMorpho.withdraw, (marketParams, 1500e6, 0, SV0, SV0));
            bytes memory encoded = _encode(MORPHO, innerCalldata, _getPayload(json, 84));

            console.log("Calldata:");
            console.logBytes(encoded);
            console.log("");
        }

        // === TX 4: Approve USDC for Aave (index 35) ===
        {
            console.log("--------------------------------------------");
            console.log("TX 4: Approve USDC for Aave (300 USDC)");
            console.log("--------------------------------------------");

            bytes memory innerCalldata = abi.encodeCall(IERC20.approve, (AAVE_CORE, 300e6));
            bytes memory encoded = _encode(USDC, innerCalldata, _getPayload(json, 35));

            console.log("Calldata:");
            console.logBytes(encoded);
            console.log("");
        }

        // === TX 5: Aave repay 300 USDC (index 37) ===
        {
            console.log("--------------------------------------------");
            console.log("TX 5: Aave Repay 300 USDC (variable rate)");
            console.log("--------------------------------------------");

            bytes memory innerCalldata = abi.encodeCall(IAavePool.repay, (USDC, 300e6, 2, SV0));
            bytes memory encoded = _encode(AAVE_CORE, innerCalldata, _getPayload(json, 37));

            console.log("Calldata:");
            console.logBytes(encoded);
            console.log("");
        }

        // === TX 6: Aave borrow 1200 USDe (index 42) ===
        {
            console.log("--------------------------------------------");
            console.log("TX 6: Aave Borrow 1200 USDe (variable rate)");
            console.log("--------------------------------------------");

            bytes memory innerCalldata = abi.encodeCall(IAavePool.borrow, (USDE, 1200e18, 2, 0, SV0));
            bytes memory encoded = _encode(AAVE_CORE, innerCalldata, _getPayload(json, 42));

            console.log("Calldata:");
            console.logBytes(encoded);
            console.log("");
        }

        // === TX 7: Approve USDC for Morpho (index 79) ===
        {
            console.log("--------------------------------------------");
            console.log("TX 7: Approve USDC for Morpho (1200 USDC)");
            console.log("--------------------------------------------");

            bytes memory innerCalldata = abi.encodeCall(IERC20.approve, (MORPHO, 1200e6));
            bytes memory encoded = _encode(USDC, innerCalldata, _getPayload(json, 79));

            console.log("Calldata:");
            console.logBytes(encoded);
            console.log("");
        }

        // === TX 8: Supply 1200 USDC to Morpho PT-reUSD market (index 94) ===
        {
            console.log("--------------------------------------------");
            console.log("TX 8: Morpho Supply 1200 USDC (PT-reUSD market)");
            console.log("--------------------------------------------");

            IMorpho.MarketParams memory marketParams = IMorpho.MarketParams({
                loanToken: USDC,
                collateralToken: M3_COLLATERAL,
                oracle: M3_ORACLE,
                irm: M3_IRM,
                lltv: M3_LLTV
            });

            bytes memory innerCalldata = abi.encodeCall(IMorpho.supply, (marketParams, 1200e6, 0, SV0, ""));
            bytes memory encoded = _encode(MORPHO, innerCalldata, _getPayload(json, 94));

            console.log("Calldata:");
            console.logBytes(encoded);
            console.log("");
        }

        console.log("============================================");
        console.log("  Safe UI Instructions");
        console.log("============================================");
        console.log("For each TX above:");
        console.log("  - Target (to): %s", SV0);
        console.log("  - Value: 0");
        console.log("  - Toggle 'Custom data' ON");
        console.log("  - Paste the calldata hex blob");
        console.log("  - Execute as curator1");
        console.log("");
        console.log("Order: TX1 -> TX2 -> TX3 -> TX4 -> TX5 -> TX6 -> TX7 -> TX8");
    }

    /**
     * @notice Encode SV3: approve USDe for SM3 + push 1700 USDe into SwapModule
     * Run: source .env && forge script scripts/ethereum/EncodeSv0Rebalance.s.sol \
     *      --sig "runSv3Push()" --via-ir --rpc-url alchemy -vvv
     */
    function runSv3Push() external view {
        address sv3 = 0x003a456aA12Faa30C146e8c5c0053f385e2584A5;
        address sm3 = 0xA1d2AF0f8D1f910f6cA7836db5d724A82DF10d79;
        address usde = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/jsons/preProd/tqGold/sv3-all.json");
        string memory json = vm.readFile(path);

        console.log("============================================");
        console.log("  SV3 Push USDe into SwapModule");
        console.log("============================================");
        console.log("");
        console.log("Subvault (target for all txs): %s", sv3);
        console.log("Caller: curator1 (0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec)");
        console.log("Value: 0 for all transactions");
        console.log("");

        // TX 1: setUserEMode(38) (index 24)
        {
            console.log("--------------------------------------------");
            console.log("TX 1: Aave setUserEMode(38)");
            console.log("--------------------------------------------");

            bytes memory innerCalldata = abi.encodeWithSignature("setUserEMode(uint8)", uint8(38));
            bytes memory encoded =
                abi.encodeCall(ICallModule.call, (0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2, 0, innerCalldata, _getPayload(json, 24)));

            console.log("Calldata:");
            console.logBytes(encoded);
            console.log("");
        }

        // TX 2: Approve USDe for SM3 (index 6)
        {
            console.log("--------------------------------------------");
            console.log("TX 2: Approve USDe for SwapModule SM3");
            console.log("--------------------------------------------");

            bytes memory innerCalldata = abi.encodeCall(IERC20.approve, (sm3, 1700e18));
            bytes memory encoded = abi.encodeCall(ICallModule.call, (usde, 0, innerCalldata, _getPayload(json, 6)));

            console.log("Calldata:");
            console.logBytes(encoded);
            console.log("");
        }

        // TX 3: pushAssets USDe into SM3 (index 7)
        {
            console.log("--------------------------------------------");
            console.log("TX 3: pushAssets 1700 USDe into SwapModule");
            console.log("--------------------------------------------");

            bytes memory innerCalldata = abi.encodeWithSignature("pushAssets(address,uint256)", usde, 1700e18);
            bytes memory encoded = abi.encodeCall(ICallModule.call, (sm3, 0, innerCalldata, _getPayload(json, 7)));

            console.log("Calldata:");
            console.logBytes(encoded);
            console.log("");
        }

        console.log("============================================");
        console.log("  Safe UI Instructions");
        console.log("============================================");
        console.log("For each TX above:");
        console.log("  - Target (to): %s", sv3);
        console.log("  - Value: 0");
        console.log("  - Toggle 'Custom data' ON");
        console.log("  - Paste the calldata hex blob");
        console.log("  - Execute as curator1");
        console.log("");
        console.log("Order: TX1 -> TX2 -> TX3");
    }
}
