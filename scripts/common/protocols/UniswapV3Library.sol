// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "@openzeppelin/contracts/utils/Strings.sol";

import {ABILibrary} from "../ABILibrary.sol";
import {JsonLibrary} from "../JsonLibrary.sol";
import "../ParameterLibrary.sol";
import "../ProofLibrary.sol";
import "../interfaces/Imports.sol";

/// @notice Library for generating Uniswap V3 LP operation proofs
/// @dev Generates Merkle tree leaves for Uniswap V3 NonfungiblePositionManager operations
library UniswapV3Library {
    using ParameterLibrary for ParameterLibrary.Parameter[];

    /// @notice Configuration for a single LP pool
    struct LPPool {
        address token0;           // First token in the pair
        address token1;           // Second token in the pair
        uint24 fee;              // Pool fee tier (500, 3000, or 10000)
    }

    /// @notice Complete Uniswap V3 configuration
    struct Info {
        address subvault;
        string subvaultName;
        address caller;          // curator or agent
        address positionManager; // NonfungiblePositionManager address
        string positionManagerName;
        LPPool[] pools;
    }

    /// @notice Generate all Uniswap V3 LP operation proofs for the given configuration
    /// @param bitmaskVerifier The bitmask verifier contract address
    /// @param $ The Uniswap V3 configuration
    /// @return leaves Array of verification payloads for all operations
    function getUniswapV3Proofs(BitmaskVerifier bitmaskVerifier, Info memory $)
        internal
        pure
        returns (IVerifier.VerificationPayload[] memory leaves)
    {
        // Each pool has:
        // - 2 token approvals (token0 and token1)
        // - 1 mint (add liquidity)
        // - 1 increaseLiquidity
        // - 1 decreaseLiquidity
        // - 1 collect
        // - 1 burn (remove position)
        uint256 opsPerPool = 7;
        uint256 length = $.pools.length * opsPerPool;
        leaves = new IVerifier.VerificationPayload[](length);
        uint256 index = 0;

        for (uint256 i = 0; i < $.pools.length; i++) {
            LPPool memory pool = $.pools[i];

            // 1. Approve token0 to position manager
            leaves[index++] = _makeApprovalProof(
                bitmaskVerifier,
                $.caller,
                pool.token0,
                $.positionManager
            );

            // 2. Approve token1 to position manager
            leaves[index++] = _makeApprovalProof(
                bitmaskVerifier,
                $.caller,
                pool.token1,
                $.positionManager
            );

            // 3. Mint new position (add liquidity)
            leaves[index++] = _makeMintProof(
                bitmaskVerifier,
                $.caller,
                $.positionManager,
                $.subvault,
                pool.token0,
                pool.token1,
                pool.fee
            );

            // 4. Increase liquidity on existing position
            leaves[index++] = _makeIncreaseLiquidityProof(
                bitmaskVerifier,
                $.caller,
                $.positionManager,
                $.subvault
            );

            // 5. Decrease liquidity from position
            leaves[index++] = _makeDecreaseLiquidityProof(
                bitmaskVerifier,
                $.caller,
                $.positionManager
            );

            // 6. Collect fees/tokens from position
            leaves[index++] = _makeCollectProof(
                bitmaskVerifier,
                $.caller,
                $.positionManager,
                $.subvault
            );

            // 7. Burn position (after liquidity is 0)
            leaves[index++] = _makeBurnProof(
                bitmaskVerifier,
                $.caller,
                $.positionManager
            );
        }

        return leaves;
    }

    /// @notice Generate human-readable descriptions for all operations
    /// @param $ The Uniswap V3 configuration
    /// @return descriptions Array of descriptions matching the proofs
    function getUniswapV3Descriptions(Info memory $)
        internal
        view
        returns (string[] memory descriptions)
    {
        uint256 opsPerPool = 7;
        uint256 length = $.pools.length * opsPerPool;
        descriptions = new string[](length);
        uint256 index = 0;

        for (uint256 i = 0; i < $.pools.length; i++) {
            LPPool memory pool = $.pools[i];
            string memory token0Symbol = _tokenSymbol(pool.token0);
            string memory token1Symbol = _tokenSymbol(pool.token1);

            // Token0 approval
            ParameterLibrary.Parameter[] memory innerParamsApprove0 =
                ParameterLibrary.build("to", Strings.toHexString($.positionManager)).addAny("amount");

            descriptions[index++] = JsonLibrary.toJson(
                string(abi.encodePacked("IERC20(", token0Symbol, ").approve(", $.positionManagerName, ", anyInt)")),
                ABILibrary.getABI(IERC20.approve.selector),
                ParameterLibrary.build(Strings.toHexString($.caller), Strings.toHexString(pool.token0), "0"),
                innerParamsApprove0
            );

            // Token1 approval
            ParameterLibrary.Parameter[] memory innerParamsApprove1 =
                ParameterLibrary.build("to", Strings.toHexString($.positionManager)).addAny("amount");

            descriptions[index++] = JsonLibrary.toJson(
                string(abi.encodePacked("IERC20(", token1Symbol, ").approve(", $.positionManagerName, ", anyInt)")),
                ABILibrary.getABI(IERC20.approve.selector),
                ParameterLibrary.build(Strings.toHexString($.caller), Strings.toHexString(pool.token1), "0"),
                innerParamsApprove1
            );

            // Mint
            descriptions[index++] = JsonLibrary.toJson(
                string(abi.encodePacked(
                    $.positionManagerName,
                    ".mint(",
                    token0Symbol,
                    ", ",
                    token1Symbol,
                    ", fee=",
                    Strings.toString(uint256(pool.fee)),
                    ", recipient=",
                    $.subvaultName,
                    ")"
                )),
                "mint((address,address,uint24,int24,int24,uint256,uint256,uint256,uint256,address,uint256))",
                ParameterLibrary.build(Strings.toHexString($.caller), Strings.toHexString($.positionManager), "0"),
                ParameterLibrary.build("token0", Strings.toHexString(pool.token0))
                    .add("token1", Strings.toHexString(pool.token1))
                    .add("fee", Strings.toString(uint256(pool.fee)))
                    .addAny("tickLower")
                    .addAny("tickUpper")
                    .addAny("amount0Desired")
                    .addAny("amount1Desired")
                    .addAny("amount0Min")
                    .addAny("amount1Min")
                    .add("recipient", Strings.toHexString($.subvault))
                    .addAny("deadline")
            );

            // Increase liquidity
            descriptions[index++] = JsonLibrary.toJson(
                string(abi.encodePacked(
                    $.positionManagerName,
                    ".increaseLiquidity(tokenId=any, amount0=any, amount1=any, recipient=",
                    $.subvaultName,
                    ")"
                )),
                "increaseLiquidity((uint256,uint256,uint256,uint256,uint256,uint256))",
                ParameterLibrary.build(Strings.toHexString($.caller), Strings.toHexString($.positionManager), "0"),
                ParameterLibrary.buildAny("tokenId")
                    .addAny("amount0Desired")
                    .addAny("amount1Desired")
                    .addAny("amount0Min")
                    .addAny("amount1Min")
                    .addAny("deadline")
            );

            // Decrease liquidity
            descriptions[index++] = JsonLibrary.toJson(
                string(abi.encodePacked($.positionManagerName, ".decreaseLiquidity(tokenId=any, liquidity=any)")),
                "decreaseLiquidity((uint256,uint128,uint256,uint256,uint256))",
                ParameterLibrary.build(Strings.toHexString($.caller), Strings.toHexString($.positionManager), "0"),
                ParameterLibrary.buildAny("tokenId")
                    .addAny("liquidity")
                    .addAny("amount0Min")
                    .addAny("amount1Min")
                    .addAny("deadline")
            );

            // Collect
            descriptions[index++] = JsonLibrary.toJson(
                string(abi.encodePacked(
                    $.positionManagerName,
                    ".collect(tokenId=any, recipient=",
                    $.subvaultName,
                    ")"
                )),
                "collect((uint256,address,uint128,uint128))",
                ParameterLibrary.build(Strings.toHexString($.caller), Strings.toHexString($.positionManager), "0"),
                ParameterLibrary.buildAny("tokenId")
                    .add("recipient", Strings.toHexString($.subvault))
                    .addAny("amount0Max")
                    .addAny("amount1Max")
            );

            // Burn
            descriptions[index++] = JsonLibrary.toJson(
                string(abi.encodePacked($.positionManagerName, ".burn(tokenId=any)")),
                "burn(uint256)",
                ParameterLibrary.build(Strings.toHexString($.caller), Strings.toHexString($.positionManager), "0"),
                ParameterLibrary.buildAny("tokenId")
            );
        }

        return descriptions;
    }

    /// @notice Generate lean descriptions (without ABIs)
    function getUniswapV3DescriptionsLean(Info memory $)
        internal
        pure
        returns (string[] memory descriptions)
    {
        uint256 opsPerPool = 7;
        uint256 length = $.pools.length * opsPerPool;
        descriptions = new string[](length);
        uint256 index = 0;

        for (uint256 i = 0; i < $.pools.length; i++) {
            LPPool memory pool = $.pools[i];
            string memory token0Symbol = _tokenSymbol(pool.token0);
            string memory token1Symbol = _tokenSymbol(pool.token1);

            descriptions[index++] = string(abi.encodePacked(
                "IERC20(", token0Symbol, ").approve(", $.positionManagerName, ", anyInt)"
            ));

            descriptions[index++] = string(abi.encodePacked(
                "IERC20(", token1Symbol, ").approve(", $.positionManagerName, ", anyInt)"
            ));

            descriptions[index++] = string(abi.encodePacked(
                $.positionManagerName,
                ".mint(",
                token0Symbol,
                ", ",
                token1Symbol,
                ", fee=",
                Strings.toString(uint256(pool.fee)),
                ", recipient=",
                $.subvaultName,
                ")"
            ));

            descriptions[index++] = string(abi.encodePacked(
                $.positionManagerName,
                ".increaseLiquidity(tokenId=any, amount0=any, amount1=any)"
            ));

            descriptions[index++] = string(abi.encodePacked(
                $.positionManagerName,
                ".decreaseLiquidity(tokenId=any, liquidity=any)"
            ));

            descriptions[index++] = string(abi.encodePacked(
                $.positionManagerName,
                ".collect(tokenId=any, recipient=",
                $.subvaultName,
                ")"
            ));

            descriptions[index++] = string(abi.encodePacked(
                $.positionManagerName,
                ".burn(tokenId=any)"
            ));
        }

        return descriptions;
    }

    // ========== INTERNAL PROOF GENERATION FUNCTIONS ==========

    function _makeApprovalProof(
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

    function _makeMintProof(
        BitmaskVerifier bitmaskVerifier,
        address caller,
        address positionManager,
        address subvault,
        address token0,
        address token1,
        uint24 fee
    ) private pure returns (IVerifier.VerificationPayload memory) {
        // MintParams struct
        bytes memory mintCalldata = abi.encodeWithSignature(
            "mint((address,address,uint24,int24,int24,uint256,uint256,uint256,uint256,address,uint256))",
            token0,
            token1,
            fee,
            int24(0),    // tickLower - any
            int24(0),    // tickUpper - any
            uint256(0),  // amount0Desired - any
            uint256(0),  // amount1Desired - any
            uint256(0),  // amount0Min - any
            uint256(0),  // amount1Min - any
            subvault,    // recipient - FIXED
            uint256(0)   // deadline - any
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
                mintCalldata // Use same calldata for bitmask (recipient is fixed)
            )
        );
    }

    function _makeIncreaseLiquidityProof(
        BitmaskVerifier bitmaskVerifier,
        address caller,
        address positionManager,
        address /* subvault */
    ) private pure returns (IVerifier.VerificationPayload memory) {
        // IncreaseLiquidityParams struct
        bytes memory increaseCalldata = abi.encodeWithSignature(
            "increaseLiquidity((uint256,uint256,uint256,uint256,uint256,uint256))",
            uint256(0),  // tokenId - any
            uint256(0),  // amount0Desired - any
            uint256(0),  // amount1Desired - any
            uint256(0),  // amount0Min - any
            uint256(0),  // amount1Min - any
            uint256(0)   // deadline - any
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
                increaseCalldata
            )
        );
    }

    function _makeDecreaseLiquidityProof(
        BitmaskVerifier bitmaskVerifier,
        address caller,
        address positionManager
    ) private pure returns (IVerifier.VerificationPayload memory) {
        // DecreaseLiquidityParams struct
        bytes memory decreaseCalldata = abi.encodeWithSignature(
            "decreaseLiquidity((uint256,uint128,uint256,uint256,uint256))",
            uint256(0),  // tokenId - any
            uint128(0),  // liquidity - any
            uint256(0),  // amount0Min - any
            uint256(0),  // amount1Min - any
            uint256(0)   // deadline - any
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
                decreaseCalldata
            )
        );
    }

    function _makeCollectProof(
        BitmaskVerifier bitmaskVerifier,
        address caller,
        address positionManager,
        address subvault
    ) private pure returns (IVerifier.VerificationPayload memory) {
        // CollectParams struct
        bytes memory collectCalldata = abi.encodeWithSignature(
            "collect((uint256,address,uint128,uint128))",
            uint256(0),  // tokenId - any
            subvault,    // recipient - FIXED
            uint128(type(uint128).max),  // amount0Max - any
            uint128(type(uint128).max)   // amount1Max - any
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
                collectCalldata // recipient is fixed
            )
        );
    }

    function _makeBurnProof(
        BitmaskVerifier bitmaskVerifier,
        address caller,
        address positionManager
    ) private pure returns (IVerifier.VerificationPayload memory) {
        return ProofLibrary.makeVerificationPayload(
            bitmaskVerifier,
            caller,
            positionManager,
            0,
            abi.encodeWithSignature("burn(uint256)", uint256(0)),
            ProofLibrary.makeBitmask(
                true, // who: locked to caller
                true, // where: locked to position manager
                true,  // value: locked to 0
                true, // selector: locked
                abi.encodeWithSignature("burn(uint256)", uint256(0))
            )
        );
    }

    // ========== HELPER FUNCTIONS ==========

    function _tokenSymbol(address token) private pure returns (string memory) {
        // Common token symbols
        if (token == 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2) return "WETH";
        if (token == 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48) return "USDC";
        if (token == 0xdAC17F958D2ee523a2206206994597C13D831ec7) return "USDT";
        if (token == 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3) return "USDe";
        if (token == 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497) return "sUSDe";
        if (token == 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0) return "wstETH";
        if (token == 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599) return "WBTC";
        if (token == 0x6B175474E89094C44Da98b954EedeAC495271d0F) return "DAI";

        return Strings.toHexString(token);
    }
}
