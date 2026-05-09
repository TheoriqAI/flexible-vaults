// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "@openzeppelin/contracts/utils/Strings.sol";

import {ABILibrary} from "../ABILibrary.sol";
import {JsonLibrary} from "../JsonLibrary.sol";
import "../ParameterLibrary.sol";
import "../ProofLibrary.sol";
import "../interfaces/Imports.sol";

/// @notice Library for generating Uniswap V4 LP operation proofs
/// @dev Generates Merkle tree leaves for Uniswap V4 PositionManager operations
library UniswapV4Library {
    using ParameterLibrary for ParameterLibrary.Parameter[];

    /// @notice Configuration for a single LP pool
    struct LPPool {
        address currency0;        // First currency in the pair
        address currency1;        // Second currency in the pair
        uint24 fee;              // Fee tier (e.g., 3000 = 0.3%)
    }

    /// @notice Configuration for generating operations
    struct Info {
        address subvault;
        string subvaultName;
        address caller;
        address positionManager;
        string positionManagerName;
        LPPool[] pools;
    }

    /**
     * @notice Generate all Uniswap V4 LP operation proofs for the given configuration
     * @param bitmaskVerifier The bitmask verifier contract address
     * @param info Configuration containing subvault, caller, position manager, and pools
     * @return leaves Array of verification payloads for all operations
     */
    function getUniswapV4Proofs(BitmaskVerifier bitmaskVerifier, Info memory info)
        internal
        pure
        returns (IVerifier.VerificationPayload[] memory leaves)
    {
        uint256 totalOps = info.pools.length * 7; // 7 operations per pool: 2 approvals + mint + increase + decrease + collect + burn
        leaves = new IVerifier.VerificationPayload[](totalOps);

        uint256 index = 0;
        for (uint256 i = 0; i < info.pools.length; i++) {
            LPPool memory pool = info.pools[i];

            // Operation 1: Currency0 Approval
            leaves[index++] = _generateApproval(
                bitmaskVerifier,
                info.caller,
                pool.currency0,
                info.positionManager
            );

            // Operation 2: Currency1 Approval
            leaves[index++] = _generateApproval(
                bitmaskVerifier,
                info.caller,
                pool.currency1,
                info.positionManager
            );

            // Operation 3: Mint Position
            leaves[index++] = _generateMint(
                bitmaskVerifier,
                info.caller,
                info.positionManager,
                pool.currency0,
                pool.currency1,
                pool.fee,
                info.subvault
            );

            // Operation 4: Increase Liquidity
            leaves[index++] = _generateIncreaseLiquidity(
                bitmaskVerifier,
                info.caller,
                info.positionManager
            );

            // Operation 5: Decrease Liquidity
            leaves[index++] = _generateDecreaseLiquidity(
                bitmaskVerifier,
                info.caller,
                info.positionManager
            );

            // Operation 6: Collect Fees
            leaves[index++] = _generateCollect(
                bitmaskVerifier,
                info.caller,
                info.positionManager,
                info.subvault
            );

            // Operation 7: Burn Position
            leaves[index++] = _generateBurn(
                bitmaskVerifier,
                info.caller,
                info.positionManager
            );
        }

        return leaves;
    }

    function _generateApproval(
        BitmaskVerifier bitmaskVerifier,
        address caller,
        address token,
        address spender
    ) private pure returns (IVerifier.VerificationPayload memory) {
        return ProofLibrary.makeVerificationPayload(
            bitmaskVerifier,
            caller,
            token,
            0,
            abi.encodeCall(IERC20.approve, (spender, 0)),
            ProofLibrary.makeBitmask(
                true, // who: locked to caller
                true, // where: locked to token
                true,  // value: locked to 0
                true, // selector: locked
                abi.encodeCall(IERC20.approve, (address(type(uint160).max), 0))
            )
        );
    }

    function _generateMint(
        BitmaskVerifier bitmaskVerifier,
        address caller,
        address positionManager,
        address currency0,
        address currency1,
        uint24 fee,
        address recipient
    ) private pure returns (IVerifier.VerificationPayload memory) {
        // V4 mint signature: mint((address,address,uint24,int24,address),int24,int24,uint256,uint256,uint256,address,bytes)
        // PoolKey: (currency0, currency1, fee, tickSpacing, hooks)
        // Mint params: tickLower, tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData
        bytes memory mintCalldata = abi.encodeWithSignature(
            "mint((address,address,uint24,int24,address),int24,int24,uint256,uint256,uint256,address,bytes)",
            currency0,       // PoolKey.currency0 - FIXED
            currency1,       // PoolKey.currency1 - FIXED
            fee,             // PoolKey.fee - FIXED
            int24(0),        // PoolKey.tickSpacing - any
            address(0),      // PoolKey.hooks - any
            int24(0),        // tickLower - any
            int24(0),        // tickUpper - any
            uint256(0),      // liquidity - any
            uint256(0),      // amount0Max - any
            uint256(0),      // amount1Max - any
            recipient,       // recipient - FIXED
            bytes("")        // hookData - any
        );

        return ProofLibrary.makeVerificationPayload(
            bitmaskVerifier,
            caller,
            positionManager,
            0,
            mintCalldata,
            ProofLibrary.makeBitmask(
                true, // who: locked to caller
                true, // where: locked to position manager
                true,  // value: locked to 0
                true, // selector: locked
                mintCalldata // Use same calldata for bitmask (currency0, currency1, fee, recipient are fixed)
            )
        );
    }

    function _generateIncreaseLiquidity(
        BitmaskVerifier bitmaskVerifier,
        address caller,
        address positionManager
    ) private pure returns (IVerifier.VerificationPayload memory) {
        // V4 increaseLiquidity signature: increaseLiquidity(uint256,uint256,uint256,uint256,bytes)
        bytes memory increaseCalldata = abi.encodeWithSignature(
            "increaseLiquidity(uint256,uint256,uint256,uint256,bytes)",
            uint256(0),  // tokenId - any
            uint256(0),  // liquidity - any
            uint256(0),  // amount0Max - any
            uint256(0),  // amount1Max - any
            bytes("")    // hookData - any
        );

        return ProofLibrary.makeVerificationPayload(
            bitmaskVerifier,
            caller,
            positionManager,
            0,
            increaseCalldata,
            ProofLibrary.makeBitmask(
                true, // who: locked to caller
                true, // where: locked to position manager
                true,  // value: locked to 0
                true, // selector: locked
                abi.encodeWithSignature(
                    "increaseLiquidity(uint256,uint256,uint256,uint256,bytes)",
                    type(uint256).max,
                    type(uint256).max,
                    type(uint256).max,
                    type(uint256).max,
                    bytes("")
                )
            )
        );
    }

    function _generateDecreaseLiquidity(
        BitmaskVerifier bitmaskVerifier,
        address caller,
        address positionManager
    ) private pure returns (IVerifier.VerificationPayload memory) {
        // V4 decreaseLiquidity signature: decreaseLiquidity(uint256,uint256,uint256,uint256,bytes)
        bytes memory decreaseCalldata = abi.encodeWithSignature(
            "decreaseLiquidity(uint256,uint256,uint256,uint256,bytes)",
            uint256(0),  // tokenId - any
            uint256(0),  // liquidity - any
            uint256(0),  // amount0Min - any
            uint256(0),  // amount1Min - any
            bytes("")    // hookData - any
        );

        return ProofLibrary.makeVerificationPayload(
            bitmaskVerifier,
            caller,
            positionManager,
            0,
            decreaseCalldata,
            ProofLibrary.makeBitmask(
                true, // who: locked to caller
                true, // where: locked to position manager
                true,  // value: locked to 0
                true, // selector: locked
                abi.encodeWithSignature(
                    "decreaseLiquidity(uint256,uint256,uint256,uint256,bytes)",
                    type(uint256).max,
                    type(uint256).max,
                    type(uint256).max,
                    type(uint256).max,
                    bytes("")
                )
            )
        );
    }

    function _generateCollect(
        BitmaskVerifier bitmaskVerifier,
        address caller,
        address positionManager,
        address recipient
    ) private pure returns (IVerifier.VerificationPayload memory) {
        // V4 collect signature: collect(uint256,address,uint128,uint128,bytes)
        bytes memory collectCalldata = abi.encodeWithSignature(
            "collect(uint256,address,uint128,uint128,bytes)",
            uint256(0),  // tokenId - any
            recipient,   // recipient - FIXED
            uint128(0),  // amount0Max - any
            uint128(0),  // amount1Max - any
            bytes("")    // hookData - any
        );

        return ProofLibrary.makeVerificationPayload(
            bitmaskVerifier,
            caller,
            positionManager,
            0,
            collectCalldata,
            ProofLibrary.makeBitmask(
                true, // who: locked to caller
                true, // where: locked to position manager
                true,  // value: locked to 0
                true, // selector: locked
                collectCalldata // Use same calldata for bitmask (recipient is fixed)
            )
        );
    }

    function _generateBurn(
        BitmaskVerifier bitmaskVerifier,
        address caller,
        address positionManager
    ) private pure returns (IVerifier.VerificationPayload memory) {
        // V4 burn signature: burn(uint256,bytes)
        bytes memory burnCalldata = abi.encodeWithSignature(
            "burn(uint256,bytes)",
            uint256(0),  // tokenId - any
            bytes("")    // hookData - any
        );

        return ProofLibrary.makeVerificationPayload(
            bitmaskVerifier,
            caller,
            positionManager,
            0,
            burnCalldata,
            ProofLibrary.makeBitmask(
                true, // who: locked to caller
                true, // where: locked to position manager
                true,  // value: locked to 0
                true, // selector: locked
                abi.encodeWithSignature(
                    "burn(uint256,bytes)",
                    type(uint256).max,
                    bytes("")
                )
            )
        );
    }

    /// @notice Generate lean descriptions (without ABIs) for Uniswap V4 operations
    function getUniswapV4DescriptionsLean(Info memory info)
        internal
        pure
        returns (string[] memory descriptions)
    {
        uint256 opsPerPool = 7;
        uint256 length = info.pools.length * opsPerPool;
        descriptions = new string[](length);
        uint256 index = 0;

        for (uint256 i = 0; i < info.pools.length; i++) {
            LPPool memory pool = info.pools[i];
            string memory currency0Symbol = _tokenSymbol(pool.currency0);
            string memory currency1Symbol = _tokenSymbol(pool.currency1);

            descriptions[index++] = string(abi.encodePacked(
                "IERC20(", currency0Symbol, ").approve(", info.positionManagerName, ", anyInt)"
            ));

            descriptions[index++] = string(abi.encodePacked(
                "IERC20(", currency1Symbol, ").approve(", info.positionManagerName, ", anyInt)"
            ));

            descriptions[index++] = string(abi.encodePacked(
                info.positionManagerName,
                ".mint(",
                currency0Symbol,
                ", ",
                currency1Symbol,
                ", fee=",
                Strings.toString(uint256(pool.fee)),
                ", recipient=",
                info.subvaultName,
                ")"
            ));

            descriptions[index++] = string(abi.encodePacked(
                info.positionManagerName,
                ".increaseLiquidity(tokenId=any, liquidity=any)"
            ));

            descriptions[index++] = string(abi.encodePacked(
                info.positionManagerName,
                ".decreaseLiquidity(tokenId=any, liquidity=any)"
            ));

            descriptions[index++] = string(abi.encodePacked(
                info.positionManagerName,
                ".collect(tokenId=any, recipient=",
                info.subvaultName,
                ")"
            ));

            descriptions[index++] = string(abi.encodePacked(
                info.positionManagerName,
                ".burn(tokenId=any)"
            ));
        }

        return descriptions;
    }

    /// @notice Get token symbol for known tokens
    function _tokenSymbol(address token) private pure returns (string memory) {
        if (token == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) return "USDC";
        if (token == 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) return "WETH";
        if (token == 0xdAC17F958D2ee523a2206206994597C13D831ec7) return "USDT";
        if (token == 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0) return "wstETH";
        if (token == 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84) return "stETH";
        return Strings.toHexString(token);
    }
}
