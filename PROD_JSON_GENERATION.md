# Production JSON Generation Commands

This document contains the exact commands and configuration files used to generate the production subvault operation JSONs.

## Production Subvault 3 (ethereum:tqETH:prod:sv3:all.json)

### Configuration
- **Subvault Index**: 3
- **Subvault Address**: `0x36d8d9fC89eEB1aBbfc6101Cc23945e79416D9f3`
- **Operations**: Aave + Spark + SwapModule
- **eMode**: 1 (ETH correlated)
- **SwapModule Address**: `0xb1578423A1DB4ede605b718B9B749751e44FF552`

### Step 1: Generate Aave Operations
```bash
forge script scripts/ethereum/GenerateAaveOpsJSON.s.sol --sig "generateProdSv3Aave(uint8)" 1 --via-ir --rpc-url https://rpc.mevblocker.io
```

**Output File**: `./scripts/jsons/ethereum:tqETH:prod:sv3:aaveOps-emode1.json`

### Step 2: Generate Spark Operations
```bash
forge script scripts/ethereum/GenerateAaveOpsJSON.s.sol --sig "generateProdSv3Spark(uint8)" 1 --via-ir --rpc-url https://rpc.mevblocker.io
```

**Output File**: `./scripts/jsons/ethereum:tqETH:prod:sv3:sparkOps-emode1.json`

### Step 3: Generate SwapModule Operations
```bash
forge script scripts/ethereum/GenerateSwapModuleJSON.s.sol --sig "generateProdWithSwapModule(uint256,address)" 3 0xb1578423A1DB4ede605b718B9B749751e44FF552 --via-ir --rpc-url https://rpc.mevblocker.io
```

**Output File**: `./scripts/jsons/ethereum:tqETH:prod:sv3:swapModule.json`

### Step 4: Merge All Operations
```bash
forge script scripts/ethereum/MergeJSONs.s.sol --sig "mergeThreeJSONsForProdSv3()" --via-ir --rpc-url https://rpc.mevblocker.io
```

**Output File**: `./scripts/jsons/ethereum:tqETH:prod:sv3:all.json`

**Final Result**:
- **Total Operations**: 62 (22 Aave + 22 Spark + 18 SwapModule)
- **Merkle Root**: `0x83203154f133b58ede8bfc0601021ab72142d4ad7c02a35a151a8942be703d7b`

---

## Production Subvault 4 (ethereum:tqETH:prod:sv4:all.json)

### Configuration Files

#### scripts/configs/prod-sv4-pendle.json
```json
{
  "subvaultIndex": 4,
  "isProd": true,
  "strategies": [
    {
      "ptToken": "0xC6F3e4Ea2D61c219e68545B90A44A42609D2aaCA",
      "market": "0x60f42E4a1E2f2bD89fEA2DE82F9a7929df0E0dfe",
      "inputTokens": ["0x4c9EDD5852cd905f086C759E8383e09bff1E68B3"],
      "mintSyToken": "0x4457a5B0Ed74F95910f98E8C7Bb0c5E6933f6B8C",
      "description": "PT-jrUSDe-27MAR2025"
    },
    {
      "ptToken": "0x0776b04d31A30B4E2D2AA7952bD7b19b5ee92A71",
      "market": "0xE8483517077afa11A9B07f849cee2552f040d7b2",
      "inputTokens": ["0x4c9EDD5852cd905f086C759E8383e09bff1E68B3"],
      "mintSyToken": "0x8f1bcb8b6Fb2fd0E4fE81A8Da3F89deEF79d5fC7",
      "description": "PT-sNUSD-04MAR2026"
    },
    {
      "ptToken": "0x1F84a51296691320478c98b8d77f2Bbd17D34350",
      "market": "0xAAdbc004dACf10E1FDbD87ca1A40ecAF77Cc5b02",
      "inputTokens": ["0x4c9EDD5852cd905f086C759E8383e09bff1E68B3"],
      "mintSyToken": "0x4c9EDD5852cd905f086C759E8383e09bff1E68B3",
      "description": "PT-USDe"
    },
    {
      "ptToken": "0xE8483517077afa11A9B07f849cee2552f040d7b2",
      "market": "0xEd81F8ba2941c3979DE2265c295748a6B6956567",
      "inputTokens": ["0x4c9EDD5852cd905f086C759E8383e09bff1E68B3"],
      "mintSyToken": "0x9D39A5DE30e57443BfF2A8307A4256c8797A3497",
      "description": "PT-sUSDe"
    },
    {
      "ptToken": "0x9Bf45ab47747F4B4dD09B3C2c73953484b4eB375",
      "market": "0xAFB7d6d1e9BcA5B675aDC9b4f52F0CDfDdec9654",
      "inputTokens": ["0x4c9EDD5852cd905f086C759E8383e09bff1E68B3", "0x3d7d6fdf07EE548B939A80edbc9B2256d0cdc003"],
      "mintSyToken": "0x3d7d6fdf07EE548B939A80edbc9B2256d0cdc003",
      "description": "PT-srUSDe-01APR2026"
    }
  ]
}
```

### Configuration
- **Subvault Index**: 4
- **Subvault Address**: `0xB747b828A22001cAC25243C18408697845C3B68E`
- **Operations**: Pendle PT (5 markets) + Aave (eMode 32) + SwapModule
- **Aave Collateral**: wstETH + PT-sUSDe
- **Aave Debt**: USDe
- **eMode**: 32 (USDe correlated)
- **SwapModule Address**: `0x114dea9b67A31E704dAbE28bed51C49C01940DDf`

### Step 1: Generate Pendle PT Operations
```bash
forge script scripts/ethereum/GeneratePendlePTJSON.s.sol --sig "generateProdFromConfig()" --via-ir --rpc-url https://rpc.mevblocker.io
```

**Config File**: `./scripts/configs/prod-sv4-pendle.json`
**Output File**: `./scripts/jsons/ethereum:tqETH:prod:sv4:pendlePT.json`

### Step 2: Generate Aave Operations with eMode 32
```bash
forge script scripts/ethereum/GenerateAaveOpsJSON.s.sol --sig "generateProdSv4Aave(uint8)" 32 --via-ir --rpc-url https://rpc.mevblocker.io
```

**Output File**: `./scripts/jsons/ethereum:tqETH:prod:sv4:aaveOps-emode32.json`

**Assets**:
- Collateral: wstETH (`0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0`) + PT-sUSDe (`0xE8483517077afa11A9B07f849cee2552f040d7b2`)
- Borrow: USDe (`0x4c9EDD5852cd905f086C759E8383e09bff1E68B3`)

### Step 3: Generate SwapModule Operations
```bash
forge script scripts/ethereum/GenerateSwapModuleJSON.s.sol --sig "generateProdWithSwapModule(uint256,address)" 4 0x114dea9b67A31E704dAbE28bed51C49C01940DDf --via-ir --rpc-url https://rpc.mevblocker.io
```

**Output File**: `./scripts/jsons/ethereum:tqETH:prod:sv4:swapModule.json`

### Step 4: Merge All Operations
```bash
forge script scripts/ethereum/MergeJSONs.s.sol --sig "mergeThreeJSONsForProdSv4()" --via-ir --rpc-url https://rpc.mevblocker.io
```

**Output File**: `./scripts/jsons/ethereum:tqETH:prod:sv4:all.json`

**Final Result**:
- **Total Operations**: 55 (27 Pendle + 10 Aave + 18 SwapModule)
- **Merkle Root**: `0xc44fde11593c6a6c520dabdfd485d08f710d01e1f255a08906b0b6377f47820b`

---

## Test Commands

### Validate Prod Subvault 3 JSON
```bash
forge test --match-test test_ProdSv3_VerifyProofs --via-ir -vv --fork-url https://rpc.mevblocker.io
```

### Validate Prod Subvault 4 JSON
```bash
forge test --match-test test_ProdSv4_VerifyProofs --via-ir -vv --fork-url https://rpc.mevblocker.io
```

---

## Key Files

### Scripts
- `scripts/ethereum/GenerateAaveOpsJSON.s.sol` - Generates Aave and Spark operations
- `scripts/ethereum/GeneratePendlePTJSON.s.sol` - Generates Pendle PT operations
- `scripts/ethereum/GenerateSwapModuleJSON.s.sol` - Generates SwapModule operations
- `scripts/ethereum/MergeJSONs.s.sol` - Merges multiple JSON files
- `test/SetMerkleRootAndTest.t.sol` - Test contract for validation

### Config Files
- `scripts/configs/prod-sv4-pendle.json` - Pendle PT market configurations for prod sv4

### Constants
- `scripts/ethereum/Constants.sol` - Protocol addresses and constants
  - Added: `SUSDE`, `SRUSDE`, `PT_SRUSDE`, `PT_SRUSDE_MARKET`

### Output Files
#### Prod Subvault 3
- `scripts/jsons/ethereum:tqETH:prod:sv3:aaveOps-emode1.json`
- `scripts/jsons/ethereum:tqETH:prod:sv3:aaveOps-emode1-lean.json`
- `scripts/jsons/ethereum:tqETH:prod:sv3:sparkOps-emode1.json`
- `scripts/jsons/ethereum:tqETH:prod:sv3:sparkOps-emode1-lean.json`
- `scripts/jsons/ethereum:tqETH:prod:sv3:swapModule.json`
- `scripts/jsons/ethereum:tqETH:prod:sv3:all.json` ← **Final merged file**

#### Prod Subvault 4
- `scripts/jsons/ethereum:tqETH:prod:sv4:pendlePT.json`
- `scripts/jsons/ethereum:tqETH:prod:sv4:pendlePT-lean.json`
- `scripts/jsons/ethereum:tqETH:prod:sv4:aaveOps-emode32.json`
- `scripts/jsons/ethereum:tqETH:prod:sv4:aaveOps-emode32-lean.json`
- `scripts/jsons/ethereum:tqETH:prod:sv4:swapModule.json`
- `scripts/jsons/ethereum:tqETH:prod:sv4:all.json` ← **Final merged file**

---

## Summary

Both production subvault JSONs have been successfully generated, validated, and are ready for deployment:

✅ **Prod SV3**: 62 operations (Aave + Spark + SwapModule)
✅ **Prod SV4**: 55 operations (5 Pendle PT markets + Aave eMode 32 + SwapModule)

The merkle roots can be set on-chain to enable these operations for the respective subvaults.
