# Production Subvault Security Summary

This document summarizes the security constraints enforced by the merkle-proof permission system for production subvaults 3 and 4.

## Overview

| Subvault | Address | Operations | Merkle Root |
|----------|---------|------------|-------------|
| SV3 | `0x36d8d9fC89eEB1aBbfc6101Cc23945e79416D9f3` | 62 | `0x2bbe0a10fb022bb12e196d177ac653a11f4e31d7e994bc9a5d8ba03f39b1fc8c` |
| SV4 | `0xB747b828A22001cAC25243C18408697845C3B68E` | 55 | `0xc1a83ecb8e78ec151c401348962e2c24221b750578a6e13b796495248e923607` |

**Curator Address:** `0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8`

---

## Security Constraints

### 1. Caller Restriction

All operations are restricted to be called only by the **curator** address.

| Parameter | Locked Value |
|-----------|--------------|
| `caller` | `0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8` |

This prevents unauthorized parties from executing any permitted operations on behalf of the subvault.

---

### 2. Aave/Spark Operations

#### 2.1 Supply Operations
The `onBehalfOf` parameter is locked to the subvault address, ensuring supplied assets are credited to the subvault.

| Operation | Parameter | Locked Value |
|-----------|-----------|--------------|
| `supply(asset, amount, onBehalfOf, referralCode)` | `onBehalfOf` | Subvault address |

#### 2.2 Withdraw Operations
The `to` parameter is locked to the subvault address, ensuring withdrawn assets are sent to the subvault.

| Operation | Parameter | Locked Value |
|-----------|-----------|--------------|
| `withdraw(asset, amount, to)` | `to` | Subvault address |

#### 2.3 Borrow Operations
Both `onBehalfOf` and `interestRateMode` are locked.

| Operation | Parameter | Locked Value |
|-----------|-----------|--------------|
| `borrow(asset, amount, interestRateMode, referralCode, onBehalfOf)` | `onBehalfOf` | Subvault address |
| | `interestRateMode` | `2` (Variable Rate) |

#### 2.4 Repay Operations
Both `onBehalfOf` and `rateMode` are locked.

| Operation | Parameter | Locked Value |
|-----------|-----------|--------------|
| `repay(asset, amount, rateMode, onBehalfOf)` | `onBehalfOf` | Subvault address |
| | `rateMode` | `2` (Variable Rate) |

#### 2.5 Interest Rate Mode

All borrow and repay operations are locked to **interest rate mode 2 (Variable Rate)**. This prevents:
- Use of stable rate borrowing (mode 1)
- Potential rate manipulation attacks

---

### 3. Pendle Operations (SV4 Only)

All Pendle router operations have the `receiver` parameter locked to the subvault.

| Operation | Parameter | Locked Value |
|-----------|-----------|--------------|
| `swapExactTokenForPt` | `receiver` | Subvault address |
| `swapExactPtForToken` | `receiver` | Subvault address |
| `exitPostExpToToken` | `receiver` | Subvault address |

This ensures all swapped tokens and redeemed assets are sent to the subvault.

---

### 4. Swap Module Operations

Push and pull operations are restricted to specific swap module addresses for each subvault.

| Subvault | Swap Module Address |
|----------|---------------------|
| SV3 | `0xb1578423a1db4ede605b718b9b749751e44ff552` |
| SV4 | `0x114dea9b67a31e704dabe28bed51c49c01940ddf` |

All `pushAssets` and `pullAssets` calls target only the designated swap module for that subvault.

---

## Subvault 3 (SV3) - Detailed Operations

### Protocols
- **Aave V3** (eMode 1 - ETH Correlated)
- **Spark Protocol** (eMode 1 - ETH Correlated)
- **Swap Module**

### Supported Assets

| Asset | Approve | Supply | Withdraw | Borrow | Repay |
|-------|---------|--------|----------|--------|-------|
| WETH | ✓ | ✓ | ✓ | ✓ | ✓ |
| wstETH | ✓ | ✓ | ✓ | ✓ | ✓ |
| USDC | ✓ | - | - | ✓ | ✓ |
| USDT | ✓ | - | - | ✓ | ✓ |
| USDe | ✓ | - | - | ✓ | ✓ |
| sUSDe | ✓ | - | - | - | - |

### Swap Module Assets
WETH, wstETH, USDC, USDT, USDe, sUSDe

---

## Subvault 4 (SV4) - Detailed Operations

### Protocols
- **Aave V3** (eMode 32)
- **Pendle Finance** (PT tokens)
- **Swap Module**

### Aave Operations

| Asset | Approve | Supply | Withdraw | Borrow | Repay |
|-------|---------|--------|----------|--------|-------|
| wstETH | ✓ | ✓ | ✓ | - | - |
| PT-sUSDE-5FEB2026 | ✓ | ✓ | ✓ | - | - |
| USDe | ✓ | - | - | ✓ | ✓ |

### Pendle Markets
- Market `0x60f42e4a1e2f2bd89fea2de82f9a7929df0e0dfe` (PT-sUSDE)
- Market `0xe8483517077afa11a9b07f849cee2552f040d7b2`
- Market `0xaadbc004dacf10e1fdbd87ca1a40ecaf77cc5b02` (PT-USDe)
- Market `0xed81f8ba2941c3979de2265c295748a6b6956567` (PT-sUSDe)
- Market `0xafb7d6d1e9bca5b675adc9b4f52f0cdfddec9654`

### Swap Module Assets
WETH, wstETH, USDC, USDT, USDe, sUSDe

---

## Security Properties Summary

| Property | SV3 | SV4 |
|----------|-----|-----|
| Caller locked to curator | ✓ | ✓ |
| Supply `onBehalfOf` locked to subvault | ✓ | ✓ |
| Withdraw `to` locked to subvault | ✓ | ✓ |
| Borrow `onBehalfOf` locked to subvault | ✓ | ✓ |
| Repay `onBehalfOf` locked to subvault | ✓ | ✓ |
| Interest rate mode locked to 2 (Variable) | ✓ | ✓ |
| Pendle `receiver` locked to subvault | N/A | ✓ |
| Swap module push/pull to designated address | ✓ | ✓ |

---

## Merkle Proof System

The permission system uses a merkle tree where:
1. Each leaf represents a permitted operation with specific parameter constraints
2. The `BitmaskVerifier` validates that actual call parameters match the permitted values
3. Parameters marked as `0xFF...FF` in the bitmask are wildcards (any value allowed)
4. Parameters with specific values in the bitmask are locked to those values

### Verification Flow
1. Curator submits a call with a merkle proof
2. Verifier computes the leaf hash: `keccak256(bytes.concat(keccak256(abi.encode(verificationType, keccak256(verificationData)))))`
3. Merkle proof is verified against the stored root
4. BitmaskVerifier validates the call parameters against the bitmask

---

## JSON Files

| File | Description |
|------|-------------|
| `ethereum:tqETH:subvault3.json` | Merged SV3 permissions (Aave + Spark + SwapModule) |
| `ethereum:tqETH:subvault4.json` | Merged SV4 permissions (Aave + Pendle + SwapModule) |

