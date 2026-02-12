// SPDX-License-Identifier: MIT
pragma solidity =0.8.25;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ProofLibrary} from "../common/ProofLibrary.sol";
import {JsonLibrary} from "../common/JsonLibrary.sol";
import {ParameterLibrary} from "../common/ParameterLibrary.sol";
import {ABILibrary} from "../common/ABILibrary.sol";
import {IVerifier} from "../../src/permissions/Verifier.sol";
import {BitmaskVerifier} from "../../src/permissions/BitmaskVerifier.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vault} from "../../src/vaults/Vault.sol";
import {ILidoWithdrawalQueue} from "../common/interfaces/ILidoWithdrawalQueue.sol";
import {ISUSDe} from "../common/interfaces/ISUSDe.sol";

interface IERC20Metadata is IERC20 {
    function symbol() external view returns (string memory);
}

/**
 * @title GenerateEnterExitJSON
 * @notice Modular script to generate JSON files for vault enter/exit operations
 * @dev This script generates merkle proofs for:
 *      - Push operations (moving assets into subvault)
 *      - Pull operations (moving assets out of subvault)
 *      - Curve exchange operations (recipient must equal sender, caller must be MULTISIG)
 *      - Uniswap V3 swaps (recipient must be subvault, caller must be MULTISIG)
 *
 * IMPORTANT: This script is completely separate from other generation flows and is
 * designed to be modular and reusable for different vault configurations.
 */
contract GenerateEnterExitJSON is Script {
    using ParameterLibrary for ParameterLibrary.Parameter[];

    // Constants
    address constant MULTISIG = 0x78B1fDE522103116891C71977AB8f8344b327C77; // Default multisig
    address constant CURVE_ROUTER = 0xF0d4c12A5768D806021F80a262B4d39d26C58b8D; // Curve Exchange Router
    address constant UNI_V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564; // Uniswap V3 SwapRouter
    address constant LIDO_WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1; // Lido Withdrawal Queue
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0; // wstETH token
    address constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497; // sUSDe token

    struct Config {
        address subvault;
        string subvaultName;
        address multisig;
        address bitmaskVerifier;
        // Arrays of assets for push/pull operations
        address[] pushAssets; // Assets to move INTO subvault
        address[] pullAssets; // Assets to move OUT OF subvault
        // Optional Curve swaps
        CurveSwap[] curveSwaps;
        // Optional Uniswap V3 swaps
        UniV3Swap[] uniV3Swaps;
        // Optional Lido wstETH withdrawal queue
        bool enableLidoWithdrawal;
        // Optional sUSDe withdrawal (cooldown + unstake)
        bool enableSusdeWithdrawal;
    }

    struct CurveSwap {
        address pool;
        address assetIn;
        address assetOut;
        // Note: recipient will be enforced as sender (subvault)
        // Note: caller will be enforced as MULTISIG only
    }

    struct UniV3Swap {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        // Note: recipient will be enforced as subvault
        // Note: caller will be enforced as MULTISIG only
    }

    /**
     * @notice Generate enter/exit JSON for a vault configuration
     * @param config The vault configuration with assets and swaps
     * @param outputTitle Title for the output JSON file
     * @param generateLean Whether to generate a lean version without ABIs
     */
    function generateEnterExitJSON(
        Config memory config,
        string memory outputTitle,
        bool generateLean
    ) public {
        console.log("=== Generate Enter/Exit JSON ===");
        console.log("Subvault: %s", config.subvault);
        console.log("Output: %s", outputTitle);
        console.log("");

        // Count total operations
        uint256 totalOps = 0;
        totalOps += config.pushAssets.length; // Push operations (transfer to subvault)
        totalOps += config.pullAssets.length; // Pull operations (transfer from subvault)
        totalOps += config.curveSwaps.length * 2; // Curve: approve + exchange
        totalOps += config.uniV3Swaps.length * 2; // UniV3: approve + swap
        if (config.enableLidoWithdrawal) {
            totalOps += 3; // wstETH approve + requestWithdrawalsWstETH + claimWithdrawal
        }
        if (config.enableSusdeWithdrawal) {
            totalOps += 2; // cooldownShares + unstake
        }

        console.log("Total operations:");
        console.log("  Push assets: %d", config.pushAssets.length);
        console.log("  Pull assets: %d", config.pullAssets.length);
        console.log("  Curve swaps: %d", config.curveSwaps.length);
        console.log("  UniV3 swaps: %d", config.uniV3Swaps.length);
        if (config.enableLidoWithdrawal) {
            console.log("  Lido withdrawal: 3 (approve + request + claim)");
        }
        if (config.enableSusdeWithdrawal) {
            console.log("  sUSDe withdrawal: 2 (cooldownShares + unstake)");
        }
        console.log("  Total: %d", totalOps);
        console.log("");

        // Create arrays for proofs and descriptions
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](totalOps);
        string[] memory descriptions = new string[](totalOps);
        uint256 index = 0;

        BitmaskVerifier bitmaskVerifier = BitmaskVerifier(config.bitmaskVerifier);

        // Generate push operations (transfer assets INTO subvault)
        console.log("Generating push operations...");
        for (uint256 i = 0; i < config.pushAssets.length; i++) {
            address asset = config.pushAssets[i];

            // Transfer from multisig to subvault
            leaves[index] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                config.multisig,
                asset,
                0,
                abi.encodeCall(IERC20.transfer, (config.subvault, 0)),
                ProofLibrary.makeBitmask(
                    false, // who: fixed (multisig only)
                    false, // where: fixed (asset address)
                    true, // value: any
                    false, // selector: fixed
                    abi.encodeCall(IERC20.transfer, (address(type(uint160).max), 0))
                )
            );

            // Simple description for now
            descriptions[index] = string.concat(
                "IERC20(",
                _getAssetSymbol(asset),
                ").transfer(",
                config.subvaultName,
                ", anyInt)"
            );

            index++;
        }

        // Generate pull operations (transfer assets OUT OF subvault)
        console.log("Generating pull operations...");
        for (uint256 i = 0; i < config.pullAssets.length; i++) {
            address asset = config.pullAssets[i];

            // Transfer from subvault to multisig
            leaves[index] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                config.multisig,
                asset,
                0,
                abi.encodeCall(IERC20.transferFrom, (config.subvault, config.multisig, 0)),
                ProofLibrary.makeBitmask(
                    false, // who: fixed (multisig only)
                    false, // where: fixed (asset address)
                    true, // value: any
                    false, // selector: fixed
                    abi.encodeCall(
                        IERC20.transferFrom,
                        (address(type(uint160).max), address(type(uint160).max), 0)
                    )
                )
            );

            descriptions[index] = string.concat(
                "IERC20(",
                _getAssetSymbol(asset),
                ").transferFrom(",
                config.subvaultName,
                ", MULTISIG, anyInt)"
            );

            index++;
        }

        // Generate Curve swap operations
        console.log("Generating Curve swap operations...");
        for (uint256 i = 0; i < config.curveSwaps.length; i++) {
            CurveSwap memory swap = config.curveSwaps[i];

            // 1. Approve Curve router
            leaves[index] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                config.multisig,
                swap.assetIn,
                0,
                abi.encodeCall(IERC20.approve, (CURVE_ROUTER, 0)),
                ProofLibrary.makeBitmask(
                    false, // who: fixed (multisig only)
                    false, // where: fixed (assetIn)
                    true, // value: any
                    false, // selector: fixed
                    abi.encodeCall(IERC20.approve, (address(type(uint160).max), 0))
                )
            );

            // Build description with ABI for approve (using helper to avoid stack too deep)
            descriptions[index] = _buildCurveApproveDescription(swap.assetIn, config.multisig);

            index++;

            // 2. Exchange on Curve (recipient MUST be subvault)
            // exchange(pool, from, to, amount, expected, receiver)
            // Lock down: specific pool, specific tokens, specific receiver
            leaves[index] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                config.multisig,
                CURVE_ROUTER,
                0,
                abi.encodeWithSignature(
                    "exchange(address,address,address,uint256,uint256,address)",
                    swap.pool,
                    swap.assetIn,
                    swap.assetOut,
                    uint256(0),
                    uint256(0),
                    config.subvault
                ),
                ProofLibrary.makeBitmask(
                    false, // who: fixed (multisig only)
                    false, // where: fixed (CURVE_ROUTER)
                    true, // value: any
                    false, // selector: fixed
                    abi.encodeWithSignature(
                        "exchange(address,address,address,uint256,uint256,address)",
                        swap.pool, // pool: FIXED (only this specific pool)
                        swap.assetIn, // from: FIXED (only this specific token in)
                        swap.assetOut, // to: FIXED (only this specific token out)
                        uint256(0), // amount: any
                        uint256(0), // expected: any
                        config.subvault // receiver: FIXED (only subvault)
                    )
                )
            );

            // Build description with ABI for exchange (using helper to avoid stack too deep)
            descriptions[index] = _buildCurveExchangeDescription(
                swap.pool,
                swap.assetIn,
                swap.assetOut,
                config.subvault,
                config.subvaultName,
                config.multisig
            );

            index++;
        }

        // Generate Uniswap V3 swap operations
        console.log("Generating Uniswap V3 swap operations...");
        for (uint256 i = 0; i < config.uniV3Swaps.length; i++) {
            UniV3Swap memory swap = config.uniV3Swaps[i];

            // 1. Approve Uniswap V3 router
            leaves[index] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                config.multisig,
                swap.tokenIn,
                0,
                abi.encodeCall(IERC20.approve, (UNI_V3_ROUTER, 0)),
                ProofLibrary.makeBitmask(
                    false, // who: fixed (multisig only)
                    false, // where: fixed (tokenIn)
                    true, // value: any
                    false, // selector: fixed
                    abi.encodeCall(IERC20.approve, (address(type(uint160).max), 0))
                )
            );

            descriptions[index] = string.concat(
                "IERC20(",
                _getAssetSymbol(swap.tokenIn),
                ").approve(UniswapV3Router, anyInt)"
            );

            index++;

            // 2. Exact input single swap (recipient MUST be subvault)
            // exactInputSingle(ExactInputSingleParams)
            // struct ExactInputSingleParams {
            //     address tokenIn;
            //     address tokenOut;
            //     uint24 fee;
            //     address recipient;
            //     uint256 deadline;
            //     uint256 amountIn;
            //     uint256 amountOutMinimum;
            //     uint160 sqrtPriceLimitX96;
            // }
            bytes memory swapCalldata = abi.encodeWithSignature(
                "exactInputSingle((address,address,uint24,address,uint256,uint256,uint256,uint160))",
                swap.tokenIn,
                swap.tokenOut,
                swap.fee,
                config.subvault,
                uint256(0), // deadline
                uint256(0), // amountIn
                uint256(0), // amountOutMinimum
                uint160(0) // sqrtPriceLimitX96
            );

            leaves[index] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                config.multisig,
                UNI_V3_ROUTER,
                0,
                swapCalldata,
                ProofLibrary.makeBitmask(
                    false, // who: fixed (multisig only)
                    false, // where: fixed (UNI_V3_ROUTER)
                    true, // value: any
                    false, // selector: fixed
                    swapCalldata // Full bitmask with flexible amounts but fixed recipient
                )
            );

            descriptions[index] = string.concat(
                "UniswapV3Router.exactInputSingle(tokenIn=",
                _getAssetSymbol(swap.tokenIn),
                ", tokenOut=",
                _getAssetSymbol(swap.tokenOut),
                ", fee=",
                vm.toString(uint256(swap.fee)),
                ", recipient=",
                config.subvaultName,
                ", amountIn=any, amountOutMin=any)"
            );

            index++;
        }

        // Generate Lido wstETH withdrawal queue operations
        if (config.enableLidoWithdrawal) {
            console.log("Generating Lido withdrawal queue operations...");

            // 1. Approve wstETH to withdrawal queue
            leaves[index] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                config.subvault, // Called FROM subvault
                WSTETH,
                0,
                abi.encodeCall(IERC20.approve, (LIDO_WITHDRAWAL_QUEUE, 0)),
                ProofLibrary.makeBitmask(
                    false, // who: fixed (subvault only)
                    false, // where: fixed (wstETH)
                    true, // value: any
                    false, // selector: fixed
                    abi.encodeCall(IERC20.approve, (address(type(uint160).max), 0))
                )
            );

            {
                ParameterLibrary.Parameter[] memory innerParams = new ParameterLibrary.Parameter[](0);
                innerParams = innerParams.add("to", Strings.toHexString(LIDO_WITHDRAWAL_QUEUE)).addAny("amount");
                descriptions[index] = JsonLibrary.toJson(
                    "IERC20(wstETH).approve(LidoWithdrawalQueue, anyAmount)",
                    ABILibrary.getABI(IERC20.approve.selector),
                    ParameterLibrary.build(Strings.toHexString(config.subvault), Strings.toHexString(WSTETH), "0"),
                    innerParams
                );
            }
            index++;

            // 2. requestWithdrawalsWstETH(uint256[] amounts, address _owner) - owner locked to subvault
            // Signature: requestWithdrawalsWstETH(uint256[],address) returns (uint256[])
            // Using array of length 1 - bitmask length must match actual calldata length
            uint256[] memory singleAmount = new uint256[](1);
            bytes memory requestCalldata = abi.encodeWithSignature(
                "requestWithdrawalsWstETH(uint256[],address)",
                singleAmount,
                config.subvault
            );

            leaves[index] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                config.subvault, // Called FROM subvault
                LIDO_WITHDRAWAL_QUEUE,
                0,
                requestCalldata,
                ProofLibrary.makeBitmask(
                    false, // who: fixed (subvault only)
                    false, // where: fixed (withdrawal queue)
                    true, // value: any
                    false, // selector: fixed
                    abi.encodeWithSignature(
                        "requestWithdrawalsWstETH(uint256[],address)",
                        singleAmount, // amounts: any (1 element array)
                        config.subvault // _owner: FIXED to subvault
                    )
                )
            );

            {
                ParameterLibrary.Parameter[] memory innerParams = new ParameterLibrary.Parameter[](0);
                innerParams = innerParams.addAny("_amounts").add("_owner", Strings.toHexString(config.subvault));
                descriptions[index] = JsonLibrary.toJson(
                    string.concat("LidoWithdrawalQueue.requestWithdrawalsWstETH(anyAmounts[], ", config.subvaultName, ")"),
                    ABILibrary.getABI(ILidoWithdrawalQueue.requestWithdrawalsWstETH.selector),
                    ParameterLibrary.build(Strings.toHexString(config.subvault), Strings.toHexString(LIDO_WITHDRAWAL_QUEUE), "0"),
                    innerParams
                );
            }
            index++;

            // 3. claimWithdrawal(uint256 _requestId)
            bytes memory claimCalldata = abi.encodeWithSignature(
                "claimWithdrawal(uint256)",
                uint256(0)
            );

            leaves[index] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                config.subvault, // Called FROM subvault
                LIDO_WITHDRAWAL_QUEUE,
                0,
                claimCalldata,
                ProofLibrary.makeBitmask(
                    false, // who: fixed (subvault only)
                    false, // where: fixed (withdrawal queue)
                    true, // value: any
                    false, // selector: fixed
                    abi.encodeWithSignature(
                        "claimWithdrawal(uint256)",
                        uint256(0) // _requestId: any
                    )
                )
            );

            {
                ParameterLibrary.Parameter[] memory innerParams = new ParameterLibrary.Parameter[](0);
                innerParams = innerParams.addAny("_requestId");
                descriptions[index] = JsonLibrary.toJson(
                    "LidoWithdrawalQueue.claimWithdrawal(anyRequestId)",
                    ABILibrary.getABI(ILidoWithdrawalQueue.claimWithdrawal.selector),
                    ParameterLibrary.build(Strings.toHexString(config.subvault), Strings.toHexString(LIDO_WITHDRAWAL_QUEUE), "0"),
                    innerParams
                );
            }
            index++;
        }

        // Generate sUSDe withdrawal operations
        if (config.enableSusdeWithdrawal) {
            console.log("Generating sUSDe withdrawal operations...");

            // 1. cooldownShares(uint256 shares)
            bytes memory cooldownCalldata = abi.encodeWithSignature(
                "cooldownShares(uint256)",
                uint256(0)
            );

            leaves[index] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                config.subvault, // Called FROM subvault
                SUSDE,
                0,
                cooldownCalldata,
                ProofLibrary.makeBitmask(
                    false, // who: fixed (subvault only)
                    false, // where: fixed (sUSDe)
                    true, // value: any
                    false, // selector: fixed
                    abi.encodeWithSignature(
                        "cooldownShares(uint256)",
                        uint256(0) // shares: any
                    )
                )
            );

            {
                ParameterLibrary.Parameter[] memory innerParams = new ParameterLibrary.Parameter[](0);
                innerParams = innerParams.addAny("shares");
                descriptions[index] = JsonLibrary.toJson(
                    "sUSDe.cooldownShares(anyShares)",
                    ABILibrary.getABI(ISUSDe.cooldownShares.selector),
                    ParameterLibrary.build(Strings.toHexString(config.subvault), Strings.toHexString(SUSDE), "0"),
                    innerParams
                );
            }
            index++;

            // 2. unstake(address receiver) - receiver locked to subvault
            bytes memory unstakeCalldata = abi.encodeWithSignature(
                "unstake(address)",
                config.subvault
            );

            leaves[index] = ProofLibrary.makeVerificationPayload(
                bitmaskVerifier,
                config.subvault, // Called FROM subvault
                SUSDE,
                0,
                unstakeCalldata,
                ProofLibrary.makeBitmask(
                    false, // who: fixed (subvault only)
                    false, // where: fixed (sUSDe)
                    true, // value: any
                    false, // selector: fixed
                    abi.encodeWithSignature(
                        "unstake(address)",
                        config.subvault // receiver: FIXED to subvault
                    )
                )
            );

            {
                ParameterLibrary.Parameter[] memory innerParams = new ParameterLibrary.Parameter[](0);
                innerParams = innerParams.add("receiver", Strings.toHexString(config.subvault));
                descriptions[index] = JsonLibrary.toJson(
                    string.concat("sUSDe.unstake(", config.subvaultName, ")"),
                    ABILibrary.getABI(ISUSDe.unstake.selector),
                    ParameterLibrary.build(Strings.toHexString(config.subvault), Strings.toHexString(SUSDE), "0"),
                    innerParams
                );
            }
            index++;
        }

        console.log("Generating merkle proofs...");

        // Generate merkle root and proofs
        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        console.log("");
        console.log("Merkle root: ");
        console.logBytes32(merkleRoot);
        console.log("");

        // Store proofs
        ProofLibrary.storeProofs(outputTitle, merkleRoot, leavesWithProofs, descriptions);
        console.log("Saved: scripts/jsons/%s.json", outputTitle);

        if (generateLean) {
            string memory leanTitle = string.concat(outputTitle, "-lean");
            ProofLibrary.storeProofs(leanTitle, merkleRoot, leavesWithProofs, descriptions);
            console.log("Saved: scripts/jsons/%s.json", leanTitle);
        }

        console.log("");
        console.log("=== Generation Complete ===");
    }

    // Helper functions

    function _getAssetSymbol(address asset) internal view returns (string memory) {
        try IERC20Metadata(asset).symbol() returns (string memory symbol) {
            return symbol;
        } catch {
            return vm.toString(asset);
        }
    }

    /// @notice Build Curve approve description with ABI
    function _buildCurveApproveDescription(
        address assetIn,
        address caller
    ) internal view returns (string memory) {
        ParameterLibrary.Parameter[] memory innerParams =
            ParameterLibrary.build("to", Strings.toHexString(CURVE_ROUTER)).addAny("amount");

        return JsonLibrary.toJson(
            string.concat("IERC20(", _getAssetSymbol(assetIn), ").approve(CurveRouter, anyInt)"),
            ABILibrary.getABI(IERC20.approve.selector),
            ParameterLibrary.build(Strings.toHexString(caller), Strings.toHexString(assetIn), "0"),
            innerParams
        );
    }

    /// @notice Build Curve exchange description with ABI
    function _buildCurveExchangeDescription(
        address pool,
        address assetIn,
        address assetOut,
        address subvault,
        string memory subvaultName,
        address caller
    ) internal view returns (string memory) {
        ParameterLibrary.Parameter[] memory innerParams =
            ParameterLibrary.build("pool", Strings.toHexString(pool))
                .add("from", Strings.toHexString(assetIn))
                .add("to", Strings.toHexString(assetOut))
                .addAny("amount")
                .addAny("expected")
                .add("receiver", Strings.toHexString(subvault));

        return JsonLibrary.toJson(
            string.concat(
                "CurveRouter.exchange(pool=",
                vm.toString(pool),
                ", from=",
                _getAssetSymbol(assetIn),
                ", to=",
                _getAssetSymbol(assetOut),
                ", amount=any, expected=any, receiver=",
                subvaultName,
                ")"
            ),
            ABILibrary.getABI(bytes4(keccak256("exchange(address,address,address,uint256,uint256,address)"))),
            ParameterLibrary.build(Strings.toHexString(caller), Strings.toHexString(CURVE_ROUTER), "0"),
            innerParams
        );
    }

    /**
     * @notice Example: Generate enter/exit for tqETH subvault
     */
    function generateTqETHEnterExit() public {
        Config memory config;
        config.subvault = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec; // tqETH subvault
        config.subvaultName = "tqETH";
        config.multisig = MULTISIG;
        config.bitmaskVerifier = 0x0000000263Fb29C3D6B0C5837883519eF05ea20A; // From Constants.sol line 164

        // Push assets (into vault)
        config.pushAssets = new address[](2);
        config.pushAssets[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        config.pushAssets[1] = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3; // USDe

        // Pull assets (out of vault)
        config.pullAssets = new address[](2);
        config.pullAssets[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        config.pullAssets[1] = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3; // USDe

        // No swaps for this example
        config.curveSwaps = new CurveSwap[](0);
        config.uniV3Swaps = new UniV3Swap[](0);

        generateEnterExitJSON(config, "ethereum:tqETH:enter-exit", true);
    }

    /**
     * @notice Generate Curve swap JSON for preprod subvault
     * @param subvaultIndex The subvault index (0, 1, 2, etc.)
     * @param curveSwaps Array of Curve swaps to include
     * @param outputSuffix Suffix for the output filename (e.g., "curveNUSD")
     */
    function generatePreProdCurveSwaps(
        uint256 subvaultIndex,
        CurveSwap[] memory curveSwaps,
        string memory outputSuffix
    ) public {
        address preprodVault = 0x2669a8B27B6f957ddb92Dc0ebdec1f112E6079E4;
        Vault vault = Vault(payable(preprodVault));
        address subvault = vault.subvaultAt(subvaultIndex);

        Config memory config;
        config.subvault = subvault;
        config.subvaultName = string.concat("subvault", vm.toString(subvaultIndex));
        config.multisig = MULTISIG;
        config.bitmaskVerifier = 0x0000000263Fb29C3D6B0C5837883519eF05ea20A;

        // No push/pull assets
        config.pushAssets = new address[](0);
        config.pullAssets = new address[](0);

        // Set Curve swaps
        config.curveSwaps = curveSwaps;

        // No Uniswap V3 swaps
        config.uniV3Swaps = new UniV3Swap[](0);

        string memory outputTitle = string.concat(
            "ethereum:tqETH:preprod:sv",
            vm.toString(subvaultIndex),
            ":",
            outputSuffix
        );
        generateEnterExitJSON(config, outputTitle, true);
    }

    /**
     * @notice Generate Curve swap JSON for prod subvault
     * @param subvaultIndex The subvault index (0, 1, 2, etc.)
     * @param curveSwaps Array of Curve swaps to include
     * @param outputSuffix Suffix for the output filename (e.g., "curveNUSD")
     */
    function generateProdCurveSwaps(
        uint256 subvaultIndex,
        CurveSwap[] memory curveSwaps,
        string memory outputSuffix
    ) public {
        address prodVault = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
        Vault vault = Vault(payable(prodVault));
        address subvault = vault.subvaultAt(subvaultIndex);

        Config memory config;
        config.subvault = subvault;
        config.subvaultName = string.concat("subvault", vm.toString(subvaultIndex));
        config.multisig = MULTISIG;
        config.bitmaskVerifier = 0x0000000263Fb29C3D6B0C5837883519eF05ea20A;

        // No push/pull assets
        config.pushAssets = new address[](0);
        config.pullAssets = new address[](0);

        // Set Curve swaps
        config.curveSwaps = curveSwaps;

        // No Uniswap V3 swaps
        config.uniV3Swaps = new UniV3Swap[](0);

        string memory outputTitle = string.concat(
            "ethereum:tqETH:prod:sv",
            vm.toString(subvaultIndex),
            ":",
            outputSuffix
        );
        generateEnterExitJSON(config, outputTitle, true);
    }

    /**
     * @notice Generate Curve swaps from a JSON config file (preprod)
     * @param configPath Path to the JSON config file (e.g., "preprod-sv4-curve-nusd")
     */
    function generatePreProdCurveSwapsFromConfig(string memory configPath) public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/configs/", configPath, ".json");
        string memory json = vm.readFile(path);

        uint256 subvaultIndex = vm.parseJsonUint(json, ".subvaultIndex");
        string memory outputSuffix = vm.parseJsonString(json, ".outputSuffix");

        // Parse curve swaps array
        bytes memory swapsData = vm.parseJson(json, ".curveSwaps");
        CurveSwap[] memory swaps = abi.decode(swapsData, (CurveSwap[]));

        generatePreProdCurveSwaps(subvaultIndex, swaps, outputSuffix);
    }

    /**
     * @notice Generate Curve swaps from a JSON config file (prod)
     * @param configPath Path to the JSON config file (e.g., "prod-sv4-curve-nusd")
     */
    function generateProdCurveSwapsFromConfig(string memory configPath) public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/configs/", configPath, ".json");
        string memory json = vm.readFile(path);

        uint256 subvaultIndex = vm.parseJsonUint(json, ".subvaultIndex");
        string memory outputSuffix = vm.parseJsonString(json, ".outputSuffix");

        // Parse curve swaps array
        bytes memory swapsData = vm.parseJson(json, ".curveSwaps");
        CurveSwap[] memory swaps = abi.decode(swapsData, (CurveSwap[]));

        generateProdCurveSwaps(subvaultIndex, swaps, outputSuffix);
    }

    /**
     * @notice Generate enter/exit operations from a JSON config file (preprod)
     * @param configPath Path to the JSON config file (e.g., "preprod-sv4-enterExit")
     */
    function generatePreProdEnterExitFromConfig(string memory configPath) public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/configs/", configPath, ".json");
        string memory json = vm.readFile(path);

        uint256 subvaultIndex = vm.parseJsonUint(json, ".subvaultIndex");
        string memory outputSuffix = vm.parseJsonString(json, ".outputSuffix");

        // Parse push and pull assets
        bytes memory pushData = vm.parseJson(json, ".pushAssets");
        bytes memory pullData = vm.parseJson(json, ".pullAssets");
        address[] memory pushAssets = abi.decode(pushData, (address[]));
        address[] memory pullAssets = abi.decode(pullData, (address[]));

        // Get subvault address
        address preprodVault = 0x2669a8B27B6f957ddb92Dc0ebdec1f112E6079E4;
        Vault vault = Vault(payable(preprodVault));
        address subvault = vault.subvaultAt(subvaultIndex);

        Config memory config;
        config.subvault = subvault;
        config.subvaultName = string.concat("subvault", vm.toString(subvaultIndex));
        config.multisig = MULTISIG;
        config.bitmaskVerifier = 0x0000000263Fb29C3D6B0C5837883519eF05ea20A;
        config.pushAssets = pushAssets;
        config.pullAssets = pullAssets;
        config.curveSwaps = new CurveSwap[](0);
        config.uniV3Swaps = new UniV3Swap[](0);

        string memory outputTitle = string.concat(
            "ethereum:tqETH:preprod:sv",
            vm.toString(subvaultIndex),
            ":",
            outputSuffix
        );
        generateEnterExitJSON(config, outputTitle, true);
    }

    /**
     * @notice Generate Lido wstETH withdrawal queue JSON for preprod subvault
     * @param subvaultIndex The subvault index (0, 1, 2, etc.)
     */
    function generatePreProdLidoWithdrawal(uint256 subvaultIndex) public {
        address preprodVault = 0x2669a8B27B6f957ddb92Dc0ebdec1f112E6079E4;
        Vault vault = Vault(payable(preprodVault));
        address subvault = vault.subvaultAt(subvaultIndex);

        Config memory config;
        config.subvault = subvault;
        config.subvaultName = string.concat("subvault", vm.toString(subvaultIndex));
        config.multisig = MULTISIG;
        config.bitmaskVerifier = 0x0000000263Fb29C3D6B0C5837883519eF05ea20A;
        config.pushAssets = new address[](0);
        config.pullAssets = new address[](0);
        config.curveSwaps = new CurveSwap[](0);
        config.uniV3Swaps = new UniV3Swap[](0);
        config.enableLidoWithdrawal = true;

        string memory outputTitle = string.concat(
            "ethereum:tqETH:preprod:sv",
            vm.toString(subvaultIndex),
            ":lidoWithdrawal"
        );
        generateEnterExitJSON(config, outputTitle, true);
    }

    /**
     * @notice Generate Lido wstETH withdrawal queue JSON for prod subvault
     * @param subvaultIndex The subvault index (0, 1, 2, etc.)
     */
    function generateProdLidoWithdrawal(uint256 subvaultIndex) public {
        address prodVault = 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d;
        Vault vault = Vault(payable(prodVault));
        address subvault = vault.subvaultAt(subvaultIndex);

        Config memory config;
        config.subvault = subvault;
        config.subvaultName = string.concat("subvault", vm.toString(subvaultIndex));
        config.multisig = MULTISIG;
        config.bitmaskVerifier = 0x0000000263Fb29C3D6B0C5837883519eF05ea20A;
        config.pushAssets = new address[](0);
        config.pullAssets = new address[](0);
        config.curveSwaps = new CurveSwap[](0);
        config.uniV3Swaps = new UniV3Swap[](0);
        config.enableLidoWithdrawal = true;

        string memory outputTitle = string.concat(
            "ethereum:tqETH:prod:sv",
            vm.toString(subvaultIndex),
            ":lidoWithdrawal"
        );
        generateEnterExitJSON(config, outputTitle, true);
    }

    /**
     * @notice Generate from generic config file that supports all features
     * @param configPath Path to the JSON config file
     * @param isProd Whether to use prod vault
     * @dev Config file format:
     * {
     *   "subvaultIndex": 4,
     *   "outputSuffix": "lidoWithdrawal",
     *   "enableLidoWithdrawal": true,
     *   "curveSwaps": [],
     *   "pushAssets": [],
     *   "pullAssets": []
     * }
     */
    function generateFromConfig(string memory configPath, bool isProd) public {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/scripts/configs/", configPath, ".json");
        string memory json = vm.readFile(path);

        uint256 subvaultIndex = vm.parseJsonUint(json, ".subvaultIndex");
        string memory outputSuffix = vm.parseJsonString(json, ".outputSuffix");

        // Get subvault address
        address vaultAddr = isProd
            ? 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d
            : 0x2669a8B27B6f957ddb92Dc0ebdec1f112E6079E4;
        Vault vault = Vault(payable(vaultAddr));
        address subvault = vault.subvaultAt(subvaultIndex);

        Config memory config;
        config.subvault = subvault;
        config.subvaultName = string.concat("subvault", vm.toString(subvaultIndex));
        config.multisig = MULTISIG;
        config.bitmaskVerifier = 0x0000000263Fb29C3D6B0C5837883519eF05ea20A;

        // Try to parse optional fields
        try vm.parseJsonBool(json, ".enableLidoWithdrawal") returns (bool enabled) {
            config.enableLidoWithdrawal = enabled;
        } catch {
            config.enableLidoWithdrawal = false;
        }

        try vm.parseJsonBool(json, ".enableSusdeWithdrawal") returns (bool enabled) {
            config.enableSusdeWithdrawal = enabled;
        } catch {
            config.enableSusdeWithdrawal = false;
        }

        // Parse optional arrays
        try vm.parseJson(json, ".curveSwaps") returns (bytes memory swapsData) {
            config.curveSwaps = abi.decode(swapsData, (CurveSwap[]));
        } catch {
            config.curveSwaps = new CurveSwap[](0);
        }

        try vm.parseJson(json, ".pushAssets") returns (bytes memory pushData) {
            config.pushAssets = abi.decode(pushData, (address[]));
        } catch {
            config.pushAssets = new address[](0);
        }

        try vm.parseJson(json, ".pullAssets") returns (bytes memory pullData) {
            config.pullAssets = abi.decode(pullData, (address[]));
        } catch {
            config.pullAssets = new address[](0);
        }

        config.uniV3Swaps = new UniV3Swap[](0);

        string memory env = isProd ? "prod" : "preprod";
        string memory outputTitle = string.concat(
            "ethereum:tqETH:",
            env,
            ":sv",
            vm.toString(subvaultIndex),
            ":",
            outputSuffix
        );
        generateEnterExitJSON(config, outputTitle, true);
    }
}
