// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import "./Constants.sol";
import "../common/ProofLibrary.sol";
import "../common/ArraysLibrary.sol";
import "../common/protocols/SwapModuleLibrary.sol";
import {AaveLibrary} from "../common/protocols/AaveLibrary.sol";
import {MorphoLibrary} from "../common/protocols/MorphoLibrary.sol";
import {PendleLibrary} from "../common/protocols/PendleLibrary.sol";
import {BitmaskVerifier, Call, IVerifier, ProtocolDeployment, SubvaultCalls} from "../common/interfaces/Imports.sol";

/// @notice Script to generate merkle proof JSON files for tqGLD PreProd subvaults
/// @dev Run with: forge script scripts/ethereum/GenerateTqGLDJSON.s.sol --sig "generateSv0All()" --via-ir --rpc-url https://rpc.mevblocker.io
contract GenerateTqGLDJSON is Script, Test {
    // Curators (same as tqETH preProd)
    address public curator1 = 0x55666095cD083a92E368c0CBAA18d8a10D3b65Ec;
    address public curator2 = 0xfc5c96303F353c314e468681899C35F424246eBe;

    // tqGLD PreProd subvault addresses
    address public constant SV0 = 0x7585770a2d08A276AF5F5980F54eCa8C25e33987;
    address public constant SV1 = 0x72a169759F9e65522f82C959c9e0572D84a56Fa0;
    address public constant SV2 = 0x5af218A143956BB19258877e2bb517C837F514C8;
    address public constant SV3 = 0x003a456aA12Faa30C146e8c5c0053f385e2584A5;
    address public constant SV4 = 0xf249968da6Fab901A54cf8fF967C891CC185dB1A;

    // tqGLD PreProd swap module addresses (verified on-chain via verifier() calls)
    address public constant SM0 = 0xd4173FF670B1ad429d3A85af00cdD5C450F96c6C;
    address public constant SM1 = 0x19c3C9B4e3bf1b583fC84E63a0b4FcBD5630903B;
    address public constant SM2 = 0x957f2895523655E5101Cf25F5189357C3C3c1076;
    address public constant SM3 = 0xA1d2AF0f8D1f910f6cA7836db5d724A82DF10d79;
    address public constant SM4 = 0x41fE0266e0B941855c000E8A51bF42CEd42e77f6;

    function getCurators() internal view returns (address[] memory) {
        return ArraysLibrary.makeAddressArray(abi.encode(curator1, curator2));
    }

    // ==================== SV0: SwapModule ====================

    /// @notice Generate SwapModule JSON for SV0 (XAUT, PAXG, USDC, USDT, USDe)
    function generateSv0SwapModule() public {
        string memory title = "preProd/tqGold/sv0-swapModule";

        address[] memory assets = new address[](5);
        assets[0] = Constants.XAUT;
        assets[1] = Constants.PAXG;
        assets[2] = Constants.USDC;
        assets[3] = Constants.USDT;
        assets[4] = Constants.USDE;

        SwapModuleLibrary.Info memory info = SwapModuleLibrary.Info({
            subvault: SV0,
            subvaultName: "subvault0",
            swapModule: SM0,
            curators: getCurators(),
            assets: assets
        });

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Generate proofs
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](100);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            SwapModuleLibrary.getSwapModuleProofs($.bitmaskVerifier, info),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        // Generate descriptions
        string[] memory descriptions = new string[](100);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            SwapModuleLibrary.getSwapModuleDescriptions(info),
            iterator
        );

        assembly {
            mstore(descriptions, iterator)
        }

        ProofLibrary.storeProofs(title, merkleRoot, leavesWithProofs, descriptions);

        console.log("=== SV0 SwapModule Generation Complete ===");
        console.log("JSON file:", string(abi.encodePacked("./scripts/jsons/", title, ".json")));
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations:", leavesWithProofs.length);
    }

    // ==================== SV0: Aave (XAUT collateral, USDC/USDT/USDe borrows, eMode 0) ====================

    /// @notice Generate Aave JSON for SV0 (XAUT collateral, USDC/USDT/USDe borrows, eMode 0)
    function generateSv0Aave() public {
        string memory title = "preProd/tqGold/sv0-aave-emode0";

        address[] memory collaterals = new address[](1);
        collaterals[0] = Constants.XAUT;

        address[] memory loans = new address[](3);
        loans[0] = Constants.USDC;
        loans[1] = Constants.USDT;
        loans[2] = Constants.USDE;

        address[] memory collateralToggles = new address[](1);
        collateralToggles[0] = Constants.XAUT;

        _generateAaveJSON(title, SV0, "subvault0", Constants.AAVE_CORE, "aave", collaterals, loans, collateralToggles, 0);
    }

    // ==================== SV0: Spark (USDC/USDT/USDe supply) ====================

    /// @notice Generate Spark JSON for SV0 (USDC + USDT + USDe collateral, no borrows)
    function generateSv0Spark() public {
        string memory title = "preProd/tqGold/sv0-spark";

        address[] memory collaterals = new address[](3);
        collaterals[0] = Constants.USDC;
        collaterals[1] = Constants.USDT;
        collaterals[2] = Constants.USDE;

        address[] memory loans = new address[](0);

        _generateAaveJSON(title, SV0, "subvault0", Constants.SPARK, "spark", collaterals, loans, new address[](0), 0);
    }

    // ==================== SV0: Morpho (USDC supply to multiple markets) ====================

    // Morpho market 1: USDC loan, PT-sNUSD collateral
    bytes32 public constant MORPHO_USDC_PT_SNUSD_MARKET =
        0x2a9a5c436719badcfadbad3ad8e8179a160ded758603eaa03a883f922a1790d3;

    // Morpho market 2: USDC loan, reUSD collateral
    bytes32 public constant MORPHO_USDC_REUSD_MARKET =
        0x4565ac05d38b19374ccbb04c17cca60ca9353cd41824f0803d0fc7704f60eaed;

    // Morpho market 3: USDC loan, PT-reUSD-25JUN2026 collateral
    bytes32 public constant MORPHO_USDC_PT_REUSD_MARKET =
        0x9bc98c2f20ac58287ef2c860eea53a2fdc27c17a7817ff1206c0b7840cc7cd79;

    /// @notice Generate Morpho JSON for SV0 (supply USDC to PT-sNUSD + reUSD markets, deduplicated approvals)
    function generateSv0Morpho() public {
        string memory title = "preProd/tqGold/sv0-morpho";

        bytes32[] memory marketIds = new bytes32[](3);
        marketIds[0] = MORPHO_USDC_PT_SNUSD_MARKET;
        marketIds[1] = MORPHO_USDC_REUSD_MARKET;
        marketIds[2] = MORPHO_USDC_PT_REUSD_MARKET;

        address[] memory curators = getCurators();
        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Collect all leaves from all markets × curators
        uint256 maxLeaves = curators.length * marketIds.length * 50;
        IVerifier.VerificationPayload[] memory allLeaves = new IVerifier.VerificationPayload[](maxLeaves);
        string[] memory allDescriptions = new string[](maxLeaves);
        uint256 iterator = 0;
        uint256 descIterator = 0;

        for (uint256 i = 0; i < curators.length; i++) {
            for (uint256 j = 0; j < marketIds.length; j++) {
                MorphoLibrary.Info memory info = MorphoLibrary.Info({
                    marketId: marketIds[j],
                    morpho: Constants.MORPHO,
                    subvault: SV0,
                    curator: curators[i]
                });

                IVerifier.VerificationPayload[] memory marketLeaves = MorphoLibrary.getMorphoProofs($.bitmaskVerifier, info);
                string[] memory marketDescs = MorphoLibrary.getMorphoDescriptions(info);

                for (uint256 k = 0; k < marketLeaves.length; k++) {
                    // Deduplicate: check if this verificationData already exists
                    bytes32 leafHash = keccak256(marketLeaves[k].verificationData);
                    bool isDuplicate = false;
                    for (uint256 m = 0; m < iterator; m++) {
                        if (keccak256(allLeaves[m].verificationData) == leafHash) {
                            isDuplicate = true;
                            break;
                        }
                    }
                    if (!isDuplicate) {
                        allLeaves[iterator] = marketLeaves[k];
                        allDescriptions[descIterator] = marketDescs[k];
                        iterator++;
                        descIterator++;
                    }
                }
            }
        }

        assembly {
            mstore(allLeaves, iterator)
            mstore(allDescriptions, descIterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(allLeaves);

        ProofLibrary.storeProofs(title, merkleRoot, leavesWithProofs, allDescriptions);

        console.log("");
        console.log("=== SV0 Morpho Generation Complete ===");
        console.log("JSON file:", string(abi.encodePacked("./scripts/jsons/", title, ".json")));
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations (deduplicated):", leavesWithProofs.length);
    }

    // ==================== SV0: All ====================

    /// @notice Generate all SV0 JSONs (SwapModule + Aave + Spark + Morpho)
    function generateSv0All() public {
        generateSv0SwapModule();
        generateSv0Aave();
        generateSv0Spark();
        generateSv0Morpho();
    }

    // ==================== SV3: SwapModule ====================

    /// @notice Generate SwapModule JSON for SV3 (USDC, USDT, USDe, sUSDe)
    function generateSv3SwapModule() public {
        string memory title = "preProd/tqGold/sv3-swapModule";

        address[] memory assets = new address[](4);
        assets[0] = Constants.USDC;
        assets[1] = Constants.USDT;
        assets[2] = Constants.USDE;
        assets[3] = Constants.SUSDE;

        SwapModuleLibrary.Info memory info = SwapModuleLibrary.Info({
            subvault: SV3,
            subvaultName: "subvault3",
            swapModule: SM3,
            curators: getCurators(),
            assets: assets
        });

        ProtocolDeployment memory $ = Constants.protocolDeployment();

        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](100);
        uint256 iterator = 0;

        iterator = ArraysLibrary.insert(
            leaves,
            SwapModuleLibrary.getSwapModuleProofs($.bitmaskVerifier, info),
            iterator
        );

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        string[] memory descriptions = new string[](100);
        iterator = 0;

        iterator = ArraysLibrary.insert(
            descriptions,
            SwapModuleLibrary.getSwapModuleDescriptions(info),
            iterator
        );

        assembly {
            mstore(descriptions, iterator)
        }

        ProofLibrary.storeProofs(title, merkleRoot, leavesWithProofs, descriptions);

        console.log("=== SV3 SwapModule Generation Complete ===");
        console.log("JSON file:", string(abi.encodePacked("./scripts/jsons/", title, ".json")));
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations:", leavesWithProofs.length);
    }

    // ==================== SV3: Aave (sUSDe + PT-srUSDe-01APR2026 collateral, USDC/USDT/USDe borrows, eMode 38) ====================

    /// @notice Generate Aave JSON for SV3 (eMode 38, sUSDe + PT-srUSDe supply, USDC/USDT/USDe borrows)
    function generateSv3Aave() public {
        string memory title = "preProd/tqGold/sv3-aave-emode38";

        address[] memory collaterals = new address[](2);
        collaterals[0] = Constants.SUSDE;
        collaterals[1] = Constants.PT_SRUSDE_01APR2026;

        address[] memory loans = new address[](3);
        loans[0] = Constants.USDC;
        loans[1] = Constants.USDT;
        loans[2] = Constants.USDE;

        _generateAaveJSON(title, SV3, "subvault3", Constants.AAVE_CORE, "aave", collaterals, loans, new address[](0), 38);
    }

    // ==================== SV3: Pendle (sUSDe -> PT-srUSDe-01APR2026) ====================

    /// @notice Generate Pendle JSON for SV3 (1 strategy: PT-srUSDe-01APR2026, input/output: sUSDe)
    function generateSv3Pendle() public {
        string memory title = "preProd/tqGold/sv3-pendle";

        address[] memory curators = getCurators();
        ProtocolDeployment memory $ = Constants.protocolDeployment();

        PendleLibrary.PTStrategy[] memory strategies = new PendleLibrary.PTStrategy[](1);

        address[] memory inputTokens = new address[](1);
        inputTokens[0] = Constants.SUSDE;

        address[] memory outputTokens = new address[](1);
        outputTokens[0] = Constants.SUSDE;

        strategies[0] = PendleLibrary.PTStrategy({
            ptToken: Constants.PT_SRUSDE_01APR2026,
            market: Constants.PENDLE_MARKET_PT_SRUSDE_01APR2026,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        });

        // Generate proofs for ALL curators
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](200);
        uint256 iterator = 0;

        for (uint256 i = 0; i < curators.length; i++) {
            PendleLibrary.Info memory pendleInfo = PendleLibrary.Info({
                subvault: SV3,
                subvaultName: "subvault3",
                curator: curators[i],
                pendleRouter: Constants.PENDLE_ROUTER,
                pendleRouterName: "PendleRouterV3",
                strategies: strategies
            });

            iterator = ArraysLibrary.insert(
                leaves,
                PendleLibrary.getPendleProofs($.bitmaskVerifier, pendleInfo),
                iterator
            );
        }

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        // Generate descriptions for ALL curators
        string[] memory descriptions = new string[](200);
        iterator = 0;

        for (uint256 i = 0; i < curators.length; i++) {
            PendleLibrary.Info memory pendleInfo = PendleLibrary.Info({
                subvault: SV3,
                subvaultName: "subvault3",
                curator: curators[i],
                pendleRouter: Constants.PENDLE_ROUTER,
                pendleRouterName: "PendleRouterV3",
                strategies: strategies
            });

            iterator = ArraysLibrary.insert(
                descriptions,
                PendleLibrary.getPendleDescriptions(pendleInfo),
                iterator
            );
        }

        assembly {
            mstore(descriptions, iterator)
        }

        ProofLibrary.storeProofs(title, merkleRoot, leavesWithProofs, descriptions);

        console.log("");
        console.log("=== SV3 Pendle Generation Complete ===");
        console.log("JSON file:", string(abi.encodePacked("./scripts/jsons/", title, ".json")));
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations:", leavesWithProofs.length);
    }

    // ==================== SV3: sUSDe Withdrawal (cooldownShares + unstake) ====================

    /// @notice Generate sUSDe withdrawal JSON for SV3 (cooldownShares + unstake, multi-curator)
    function generateSv3SusdeWithdrawal() public {
        string memory title = "preProd/tqGold/sv3-susdeWithdrawal";

        address[] memory curators = getCurators();
        ProtocolDeployment memory $ = Constants.protocolDeployment();

        uint256 opsPerCurator = 2; // cooldownShares + unstake
        uint256 totalOps = curators.length * opsPerCurator;

        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](totalOps);
        string[] memory descriptions = new string[](totalOps);
        uint256 index = 0;

        for (uint256 i = 0; i < curators.length; i++) {
            // 1. cooldownShares(uint256 shares)
            leaves[index] = ProofLibrary.makeVerificationPayload(
                $.bitmaskVerifier,
                curators[i],
                Constants.SUSDE,
                0,
                abi.encodeWithSignature("cooldownShares(uint256)", uint256(0)),
                ProofLibrary.makeBitmask(
                    true, // who: locked to curator
                    true, // where: locked to sUSDe
                    true, // value: locked to 0
                    true, // selector: locked
                    abi.encodeWithSignature("cooldownShares(uint256)", uint256(0))
                )
            );
            descriptions[index] = string(abi.encodePacked(
                '"sUSDe.cooldownShares(anyShares) [caller: ', vm.toString(curators[i]), ']"'
            ));
            index++;

            // 2. unstake(address receiver) - receiver locked to SV3
            leaves[index] = ProofLibrary.makeVerificationPayload(
                $.bitmaskVerifier,
                curators[i],
                Constants.SUSDE,
                0,
                abi.encodeWithSignature("unstake(address)", SV3),
                ProofLibrary.makeBitmask(
                    true, // who: locked to curator
                    true, // where: locked to sUSDe
                    true, // value: locked to 0
                    true, // selector: locked
                    abi.encodeWithSignature("unstake(address)", SV3) // receiver: FIXED to SV3
                )
            );
            descriptions[index] = string(abi.encodePacked(
                '"sUSDe.unstake(subvault3) [caller: ', vm.toString(curators[i]), ']"'
            ));
            index++;
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        ProofLibrary.storeProofs(title, merkleRoot, leavesWithProofs, descriptions);

        console.log("");
        console.log("=== SV3 sUSDe Withdrawal Generation Complete ===");
        console.log("JSON file:", string(abi.encodePacked("./scripts/jsons/", title, ".json")));
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations:", leavesWithProofs.length);
    }

    // ==================== SV3: All ====================

    /// @notice Generate all SV3 JSONs (SwapModule + Aave + Pendle + sUSDe Withdrawal)
    function generateSv3All() public {
        generateSv3SwapModule();
        generateSv3Aave();
        generateSv3Pendle();
        generateSv3SusdeWithdrawal();
    }

    // ==================== Internal helpers ====================

    /// @notice Internal helper for Aave/Spark JSON generation with multi-curator support
    function _generateAaveJSON(
        string memory title,
        address subvault,
        string memory subvaultName,
        address pool,
        string memory poolName,
        address[] memory collaterals,
        address[] memory loans,
        address[] memory collateralToggles,
        uint8 categoryId
    ) internal {
        address[] memory curators = getCurators();
        ProtocolDeployment memory $ = Constants.protocolDeployment();

        // Generate proofs for ALL curators
        IVerifier.VerificationPayload[] memory leaves = new IVerifier.VerificationPayload[](200);
        uint256 iterator = 0;

        for (uint256 i = 0; i < curators.length; i++) {
            AaveLibrary.Info memory aaveInfo = AaveLibrary.Info({
                subvault: subvault,
                subvaultName: subvaultName,
                curator: curators[i],
                aaveInstance: pool,
                aaveInstanceName: poolName,
                collaterals: collaterals,
                loans: loans,
                collateralToggles: collateralToggles,
                categoryId: categoryId
            });

            iterator = ArraysLibrary.insert(
                leaves,
                AaveLibrary.getAaveProofs($.bitmaskVerifier, aaveInfo),
                iterator
            );
        }

        assembly {
            mstore(leaves, iterator)
        }

        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leavesWithProofs) =
            ProofLibrary.generateMerkleProofs(leaves);

        // Generate descriptions for ALL curators
        string[] memory descriptions = new string[](200);
        iterator = 0;

        for (uint256 i = 0; i < curators.length; i++) {
            AaveLibrary.Info memory aaveInfo = AaveLibrary.Info({
                subvault: subvault,
                subvaultName: subvaultName,
                curator: curators[i],
                aaveInstance: pool,
                aaveInstanceName: poolName,
                collaterals: collaterals,
                loans: loans,
                collateralToggles: collateralToggles,
                categoryId: categoryId
            });

            iterator = ArraysLibrary.insert(
                descriptions,
                AaveLibrary.getAaveDescriptions(aaveInfo),
                iterator
            );
        }

        assembly {
            mstore(descriptions, iterator)
        }

        ProofLibrary.storeProofs(title, merkleRoot, leavesWithProofs, descriptions);

        console.log("");
        console.log(string(abi.encodePacked("=== ", title, " Generation Complete ===")));
        console.log("JSON file:", string(abi.encodePacked("./scripts/jsons/", title, ".json")));
        console.log("Merkle root:", vm.toString(merkleRoot));
        console.log("Number of operations:", leavesWithProofs.length);
    }
}
