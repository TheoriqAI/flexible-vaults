# Pendle PT Operations Guide

## Overview

This guide explains how to generate Merkle tree proofs for Pendle PT (Principal Token) operations in the Mellow vault system. The integration allows curators to:
- Buy PT tokens using input assets (USDe, sUSDe, etc.)
- Sell PT tokens back to underlying assets
- Redeem expired PT tokens

**Security Model**: All operations are restricted via bitmask verification to prevent:
- External router exploits (no `extRouter` allowed)
- Unauthorized token swaps (receiver must be subvault)
- Limit order manipulation (no limit orders)

---

## Quick Start

### 1. Generate JSON for Pre-Prod Subvault 3

```bash
forge script scripts/ethereum/GeneratePendleJSON.s.sol \
  --sig "generatePreProdCuratorWithIndex(uint256)" 3 \
  --via-ir \
  --rpc-url $ETHEREUM_RPC_URL
```

### 2. Generate JSON for Prod Subvault 0

```bash
forge script scripts/ethereum/GeneratePendleJSON.s.sol \
  --sig "generateProdCuratorWithIndex(uint256)" 0 \
  --via-ir \
  --rpc-url $ETHEREUM_RPC_URL
```

---

## Architecture

### File Structure

```
scripts/
├── ethereum/
│   ├── GeneratePendleJSON.s.sol    # Main script to generate JSON
│   ├── Constants.sol                # Pendle addresses and constants
│   └── PENDLE_GUIDE.md             # This guide
├── common/
│   ├── protocols/
│   │   └── PendleLibrary.sol       # Proof generation logic
│   └── interfaces/
│       └── IPendleRouter.sol       # Pendle Router V3 interface
└── jsons/
    └── ethereum:tqETH:preprod:sv3:pendlePT.json  # Generated JSON
```

### Components

1. **[IPendleRouter.sol](../common/interfaces/IPendleRouter.sol)**: Complete Pendle Router V3 interface with all struct definitions
2. **[PendleLibrary.sol](../common/protocols/PendleLibrary.sol)**: Generates Merkle proofs with security restrictions
3. **[GeneratePendleJSON.s.sol](GeneratePendleJSON.s.sol)**: Forge script to generate JSON files
4. **[Constants.sol](Constants.sol)**: Pendle addresses (router, PT tokens, markets)

---

## Pendle Operations

### 1. Token Approvals

For each input token (USDe, sUSDe), approve the Pendle Router:

```solidity
IERC20(inputToken).approve(PENDLE_ROUTER, amount);
```

**Bitmask**: Locks target (router), allows any amount

### 2. Buy PT (swapExactTokenForPt)

Swap input tokens for PT:

```solidity
IPendleRouter(PENDLE_ROUTER).swapExactTokenForPt(
    receiver,     // LOCKED: Must be subvault
    market,       // LOCKED: Must be approved market
    minPtOut,     // ALLOWED: Any minimum
    guessPtOut,   // ALLOWED: Any approximation params
    tokenInput,   // RESTRICTED: See below
    limitOrderData // LOCKED: Must be empty (no limit orders)
);
```

**TokenInput Restrictions**:
- `tokenIn`: ALLOWED - Any token from the approved input tokens array
- `netTokenIn`: ALLOWED - Any amount
- `tokenMintSy`: LOCKED - Must be the configured SY token (e.g., sUSDe)
- `pendleSwap`: LOCKED - Must be `address(0)` (no Pendle aggregator)
- `swapData.swapType`: LOCKED - Must be `SwapType.NONE` (0)
- `swapData.extRouter`: LOCKED - Must be `address(0)` (no external router)
- `swapData.extCalldata`: ALLOWED - Any (but ignored since no ext router)
- `swapData.needScale`: ALLOWED - Any

**LimitOrderData Restrictions**:
- `limitRouter`: LOCKED - Must be `address(0)` (no limit orders)
- All other fields: ALLOWED but ignored

**Security**: This prevents external router exploits and ensures all swaps happen through Pendle's internal logic only.

### 3. PT Approval

Approve PT token to router for selling:

```solidity
IERC20(ptToken).approve(PENDLE_ROUTER, amount);
```

### 4. Sell PT (swapExactPtForToken)

Swap PT back to underlying token:

```solidity
IPendleRouter(PENDLE_ROUTER).swapExactPtForToken(
    receiver,       // LOCKED: Must be subvault
    market,         // LOCKED: Must be approved market
    exactPtIn,      // ALLOWED: Any amount
    tokenOutput,    // RESTRICTED: See below
    limitOrderData  // LOCKED: Must be empty
);
```

**TokenOutput Restrictions**:
- `tokenOut`: ALLOWED - Any output token
- `minTokenOut`: ALLOWED - Any minimum
- `tokenRedeemSy`: LOCKED - Must be the configured SY token
- `pendleSwap`: LOCKED - Must be `address(0)`
- `swapData`: Same restrictions as buy operation

### 5. Redeem Expired PT (exitPostExpToToken)

After PT expiry, redeem for underlying:

```solidity
IPendleRouter(PENDLE_ROUTER).exitPostExpToToken(
    receiver,      // LOCKED: Must be subvault
    market,        // LOCKED: Must be approved market
    netPtIn,       // ALLOWED: Any amount
    minTokenOut,   // ALLOWED: Any minimum
    tokenOutput    // RESTRICTED: Same as sell operation
);
```

---

## Configuration

### PT Strategy Configuration

Each PT strategy requires:

```solidity
struct PTStrategy {
    address ptToken;          // PT token address (e.g., PT-sUSDe-27MAR2025)
    address market;           // Pendle market address
    address[] inputTokens;    // Allowed input tokens (e.g., [USDe, sUSDe])
    address mintSyToken;      // SY token for minting (e.g., sUSDe)
}
```

### Example: PT-sUSDe-27MAR2025

```solidity
PTStrategy memory strategy = PTStrategy({
    ptToken: 0xd0609ac13000d88b0bebf5bb21074916edd92bb1,
    market: 0xfabeefc5369aa5270b401f4ee062d17fb5f1ec2a,
    inputTokens: [
        0x4c9EDD5852cd905f086C759E8383e09bff1E68B3,  // USDe
        0xC58D044404d8B14e953C115E67823784dEA53d8F   // sUSDe (WRONG - see note below)
    ],
    mintSyToken: 0xC58D044404d8B14e953C115E67823784dEA53d8F  // sUSDe (WRONG - see note below)
});
```

**⚠️ IMPORTANT NOTE**: The sUSDe address `0xC58D044404d8B14e953C115E67823784dEA53d8F` you provided appears to be incorrect. The actual sUSDe address on mainnet is:
- **Correct sUSDe**: `0x9D39A5DE30e57443BfF2A8307A4256c8797A3497`

Please verify the token addresses before deployment!

### Constants Added to Constants.sol

```solidity
// Pendle
address public constant PENDLE_ROUTER = 0x888888888889758F76e7103c6CbF23ABbF58F946;
address public constant PT_SUSDE_27MAR2025 = 0xd0609ac13000d88b0bebf5bb21074916edd92bb1;
address public constant PENDLE_MARKET_PT_SUSDE_27MAR2025 = 0xfabeefc5369aa5270b401f4ee062d17fb5f1ec2a;
```

---

## Adding New PT Strategies

### Option 1: Modify getPendlePTConfig()

Edit [GeneratePendleJSON.s.sol:130-160](GeneratePendleJSON.s.sol#L130-L160):

```solidity
function getPendlePTConfig(address subvault, address caller)
    internal pure returns (PendleLibrary.Info memory)
{
    PendleLibrary.PTStrategy[] memory strategies = new PendleLibrary.PTStrategy[](2); // Increase size

    // Strategy 1: PT-sUSDe-27MAR2025
    address[] memory inputTokens1 = new address[](2);
    inputTokens1[0] = Constants.USDE;
    inputTokens1[1] = Constants.SUSDE;

    strategies[0] = PendleLibrary.PTStrategy({
        ptToken: Constants.PT_SUSDE_27MAR2025,
        market: Constants.PENDLE_MARKET_PT_SUSDE_27MAR2025,
        inputTokens: inputTokens1,
        mintSyToken: Constants.SUSDE
    });

    // Strategy 2: PT-weETH-27JUN2025 (example)
    address[] memory inputTokens2 = new address[](2);
    inputTokens2[0] = Constants.WETH;
    inputTokens2[1] = Constants.WEETH;

    strategies[1] = PendleLibrary.PTStrategy({
        ptToken: 0xYourPTAddress,
        market: 0xYourMarketAddress,
        inputTokens: inputTokens2,
        mintSyToken: Constants.WEETH
    });

    return PendleLibrary.Info({
        subvault: subvault,
        subvaultName: "pendlePT",
        curator: caller,
        pendleRouter: Constants.PENDLE_ROUTER,
        pendleRouterName: "PendleRouterV3",
        strategies: strategies
    });
}
```

### Option 2: Use generateCustomJSON()

Call the custom generator with your own strategies:

```solidity
PendleLibrary.PTStrategy[] memory strategies = new PendleLibrary.PTStrategy[](1);

address[] memory inputTokens = new address[](1);
inputTokens[0] = Constants.USDC;

strategies[0] = PendleLibrary.PTStrategy({
    ptToken: 0xYourPTAddress,
    market: 0xYourMarketAddress,
    inputTokens: inputTokens,
    mintSyToken: Constants.USDC
});

generateCustomJSON(
    "ethereum:tqETH:customPT",
    subvault,
    "customPT",
    curator,
    strategies
);
```

---

## Finding Pendle Markets

### 1. Pendle App

Visit https://app.pendle.finance/trade/markets and find your desired PT market.

### 2. Get Market Address

Click on the PT market and copy the contract addresses from Etherscan:
- PT token address
- Market address
- SY token address (used for `mintSyToken`)

### 3. Popular Markets (Ethereum Mainnet)

| PT Token | Expiry | Market Address | SY Token |
|----------|--------|----------------|----------|
| PT-sUSDe | 27-MAR-2025 | `0xfabeefc5369aa5270b401f4ee062d17fb5f1ec2a` | sUSDe |
| PT-weETH | 27-MAR-2025 | `0xF32e58F36aB2F8E064F6A1c8E6964Cc42Cd4A42E` | weETH |
| PT-ezETH | 27-MAR-2025 | `0xDe715330043799D7a80249660d1e6b61eB3713B3` | ezETH |

**Always verify addresses on Etherscan before use!**

---

## Security Features

### Bitmask Restrictions

All Pendle operations use bitmask verification to lock down critical parameters:

#### 1. Receiver Always Locked

```solidity
// Template
receiver: subvault

// Bitmask
receiver: address(type(uint160).max)  // LOCK

// Result: Funds can ONLY go to subvault, never curator or external addresses
```

#### 2. No External Routers

```solidity
// Template
swapData: {
    swapType: SwapType.NONE,  // 0
    extRouter: address(0),
    extCalldata: "",
    needScale: false
}

// Bitmask
swapData: {
    swapType: type(uint8).max,           // LOCK to NONE
    extRouter: address(type(uint160).max), // LOCK to 0x0
    extCalldata: "",                     // ALLOW (ignored)
    needScale: true                      // ALLOW (ignored)
}

// Result: No external router can be called, preventing arbitrary code execution
```

#### 3. No Limit Orders

```solidity
// Template
limitOrderData: {
    limitRouter: address(0),
    epsSkipMarket: 0,
    normalFills: [],
    flashFills: [],
    optData: ""
}

// Bitmask
limitOrderData: {
    limitRouter: address(type(uint160).max),  // LOCK to 0x0
    epsSkipMarket: 0,                         // ALLOW
    normalFills: [],                          // ALLOW (empty)
    flashFills: [],                           // ALLOW (empty)
    optData: ""                               // ALLOW (empty)
}

// Result: No limit orders can be executed, preventing off-chain order manipulation
```

#### 4. Market and SY Token Locked

```solidity
// Buy PT: market and mintSyToken locked
market: address(type(uint160).max)        // LOCK
tokenMintSy: address(type(uint160).max)   // LOCK

// Result: Can only trade on approved markets with approved SY tokens
```

### What's Allowed

| Parameter | Restriction | Reason |
|-----------|------------|--------|
| `tokenIn` | Any from array | Allow flexible input (USDe or sUSDe) |
| `netTokenIn` | Any amount | Allow any swap size |
| `minPtOut` | Any | Allow curator to set slippage |
| `exactPtIn` | Any | Allow any sell size |
| `minTokenOut` | Any | Allow curator to set slippage |
| `approxParams` | Any | Required for PT pricing |

### What's Locked

| Parameter | Value | Reason |
|-----------|-------|--------|
| `receiver` | Subvault | Prevent fund theft |
| `market` | Approved market | Prevent malicious markets |
| `mintSyToken` | Configured SY | Prevent wrong token minting |
| `tokenRedeemSy` | Configured SY | Prevent wrong token redemption |
| `swapType` | NONE (0) | Prevent external router calls |
| `extRouter` | address(0) | Prevent arbitrary code execution |
| `pendleSwap` | address(0) | Prevent Pendle aggregator (simplified security model) |
| `limitRouter` | address(0) | Prevent limit order exploitation |

---

## JSON Output Format

Generated JSON file: `./scripts/jsons/ethereum:tqETH:preprod:sv3:pendlePT.json`

```json
{
  "title": "ethereum:tqETH:preprod:sv3:pendlePT",
  "merkle_root": "0xabc123...",
  "merkle_proofs": [
    {
      "verificationType": 3,
      "description": {
        "description": "Approve USDe to PendleRouter(PendleRouterV3)",
        "parameters": {
          "caller": "0x55666095cd083a92e368c0cbaa18d8a10d3b65ec",
          "target": "0x4c9edd5852cd905f086c759e8383e09bff1e68b3",
          "value": "0"
        }
      },
      "verificationData": "0x...",
      "proof": ["0x...", "0x..."]
    },
    {
      "verificationType": 3,
      "description": {
        "description": "PendleRouter(PendleRouterV3).swapExactTokenForPt(receiver=pendlePT, market=0xfabeefc..., inputToken=any, minPtOut=any, NO_EXT_SWAP)",
        "parameters": {
          "caller": "0x55666095cd083a92e368c0cbaa18d8a10d3b65ec",
          "target": "0x888888888889758f76e7103c6cbf23abbf58f946",
          "value": "0"
        }
      },
      "verificationData": "0x...",
      "proof": ["0x...", "0x..."]
    }
    // ... more operations
  ]
}
```

---

## Deployment Workflow

### 1. Generate JSON

```bash
forge script scripts/ethereum/GeneratePendleJSON.s.sol \
  --sig "generatePreProdCuratorWithIndex(uint256)" 3 \
  --via-ir \
  --rpc-url $ETHEREUM_RPC_URL
```

**Output**:
```
=== Generation Complete ===
JSON file: ./scripts/jsons/ethereum:tqETH:preprod:sv3:pendlePT.json
Merkle root: 0xabc123...
Number of operations: 11
```

### 2. Review JSON

Inspect the generated file to verify:
- Correct PT token addresses
- Correct market addresses
- Security restrictions in place (NO_EXT_SWAP, receiver=subvault)

### 3. Set Merkle Root On-Chain

```bash
# Using cast
cast send $VERIFIER_ADDRESS \
  "setMerkleRoot(bytes32)" \
  0xabc123... \
  --rpc-url $ETHEREUM_RPC_URL \
  --private-key $DEPLOYER_KEY

# Or via Safe multisig
# Add transaction in Safe UI with the setMerkleRoot calldata
```

### 4. Grant CALLER_ROLE

Ensure curator has permission:

```bash
cast call $SUBVAULT \
  "hasRole(bytes32,address)" \
  $(cast keccak "CALLER_ROLE") \
  $CURATOR_ADDRESS \
  --rpc-url $ETHEREUM_RPC_URL
```

If returns `false`, grant the role:

```bash
cast send $SUBVAULT \
  "grantRole(bytes32,address)" \
  $(cast keccak "CALLER_ROLE") \
  $CURATOR_ADDRESS \
  --rpc-url $ETHEREUM_RPC_URL \
  --private-key $ADMIN_KEY
```

### 5. Execute Operations

Now the curator can call operations through the subvault's CallModule using the generated proofs from the JSON file.

---

## Example: Buy PT-sUSDe with USDe

### 1. Approve USDe

Find the approval proof in the JSON:

```json
{
  "description": "Approve USDe to PendleRouter(PendleRouterV3)",
  "verificationData": "0x...",
  "proof": ["0x...", "0x..."]
}
```

### 2. Call Through CallModule

```solidity
// Approval
callModule.call(
    USDE,                    // target: USDe token
    0,                       // value: 0
    approveCalldata,         // data: approve(router, 1000e18)
    (3, verificationData, proof)  // verification
);

// Buy PT
callModule.call(
    PENDLE_ROUTER,          // target: Pendle Router
    0,                      // value: 0
    swapExactTokenForPtCalldata,  // data: swapExactTokenForPt(...)
    (3, verificationData, proof)  // verification
);
```

The BitmaskVerifier will check:
1. Caller has CALLER_ROLE ✅
2. Hash matches Merkle proof ✅
3. Receiver is subvault ✅
4. No external router ✅
5. Market is approved ✅

---

## Troubleshooting

### Error: "Stack too deep"

Use `--via-ir` flag:

```bash
forge script scripts/ethereum/GeneratePendleJSON.s.sol \
  --sig "generatePreProdCuratorWithIndex(uint256)" 3 \
  --via-ir \  # ← REQUIRED
  --rpc-url $ETHEREUM_RPC_URL
```

### Error: "Subvault address not set"

The vault may not have a subvault at that index. Check available subvaults:

```bash
cast call $VAULT "subvaultAt(uint256)" 3 --rpc-url $ETHEREUM_RPC_URL
```

### Error: "Hash mismatch in BitmaskVerifier"

Common causes:
1. **Extra bytes in calldata**: Use `cast calldata` to generate proper encoding
2. **Wrong token address**: Verify token address in Constants.sol
3. **Incorrect struct encoding**: Ensure struct fields match exactly

### Wrong sUSDe Address

If you see address `0xC58D044404d8B14e953C115E67823784dEA53d8F` in your config, update to:
- **Correct sUSDe**: `0x9D39A5DE30e57443BfF2A8307A4256c8797A3497`

Update in [Constants.sol](Constants.sol#L28) and regenerate JSON.

---

## Security Checklist

Before deploying to production:

- [ ] Verified PT token address on Etherscan
- [ ] Verified market address on Etherscan
- [ ] Verified SY token (mintSyToken) address
- [ ] Confirmed PT expiry date matches expected maturity
- [ ] Reviewed all input tokens in the array
- [ ] Checked that `swapType` is locked to `NONE` (0)
- [ ] Checked that `extRouter` is locked to `address(0)`
- [ ] Checked that `limitRouter` is locked to `address(0)`
- [ ] Checked that `receiver` is locked to subvault address
- [ ] Tested JSON generation on preprod first
- [ ] Verified Merkle root generation is deterministic
- [ ] Granted CALLER_ROLE to curator
- [ ] Set Merkle root on BitmaskVerifier contract

---

## Advanced: Multi-PT Strategies

### Generate JSON with Multiple PT Markets

Edit [GeneratePendleJSON.s.sol:getPendlePTConfig()](GeneratePendleJSON.s.sol#L130):

```solidity
PendleLibrary.PTStrategy[] memory strategies = new PendleLibrary.PTStrategy[](3);

// PT-sUSDe-27MAR2025
address[] memory inputs1 = new address[](2);
inputs1[0] = Constants.USDE;
inputs1[1] = Constants.SUSDE;
strategies[0] = PendleLibrary.PTStrategy({
    ptToken: Constants.PT_SUSDE_27MAR2025,
    market: Constants.PENDLE_MARKET_PT_SUSDE_27MAR2025,
    inputTokens: inputs1,
    mintSyToken: Constants.SUSDE
});

// PT-weETH-27MAR2025
address[] memory inputs2 = new address[](1);
inputs2[0] = Constants.WEETH;
strategies[1] = PendleLibrary.PTStrategy({
    ptToken: 0xYourPTweETH,
    market: 0xYourMarketweETH,
    inputTokens: inputs2,
    mintSyToken: Constants.WEETH
});

// PT-ezETH-27JUN2025
address[] memory inputs3 = new address[](1);
inputs3[0] = 0xYourEZETH;
strategies[2] = PendleLibrary.PTStrategy({
    ptToken: 0xYourPTezETH,
    market: 0xYourMarketezETH,
    inputTokens: inputs3,
    mintSyToken: 0xYourEZETH
});
```

**Result**: Single JSON with 3×11 = 33 operations (approvals + swaps for each PT)

---

## Comparison: Pendle vs Aave

| Feature | Aave | Pendle PT |
|---------|------|-----------|
| **Operations** | supply, withdraw, borrow, repay | swapTokenForPt, swapPtForToken, exitPostExp |
| **Approvals** | One per asset | One per input token + one per PT |
| **Security Model** | Bitmask locks recipient | Bitmask locks recipient + NO external routers |
| **Complexity** | Simple (4 operations × N assets) | Medium (5 operations × N strategies) |
| **Configurability** | Asset arrays (collaterals, loans) | PT strategies (markets, input tokens, SY tokens) |
| **Expiry** | N/A | PT expires, needs exitPostExp |

---

## Cross-Chain Support

Pendle is deployed on multiple chains. To add support:

### 1. Add Chain Constants

```solidity
// In Constants.sol or new chain file
address public constant PENDLE_ROUTER_ARBITRUM = 0x888888888889758F76e7103c6CbF23ABbF58F946;
```

### 2. Update Script

Create `GeneratePendleJSONArbitrum.s.sol` or add chain parameter to existing script.

### 3. Verify Addresses

Each chain has different PT markets and SY tokens. Always verify on:
- https://app.pendle.finance/trade/markets
- Chain-specific Etherscan (arbiscan.io, etc.)

---

## References

- **Pendle Docs**: https://docs.pendle.finance/
- **Pendle Markets**: https://app.pendle.finance/trade/markets
- **Pendle GitHub**: https://github.com/pendle-finance/pendle-core-v2-public
- **Etherscan (Pendle Router)**: https://etherscan.io/address/0x888888888889758F76e7103c6CbF23ABbF58F946

---

## Summary

✅ **Created Files**:
1. `IPendleRouter.sol` - Complete Router V3 interface
2. `PendleLibrary.sol` - Proof generation with security restrictions
3. `GeneratePendleJSON.s.sol` - Script for prod/preprod JSON generation
4. `Constants.sol` - Added Pendle addresses
5. `PENDLE_GUIDE.md` - This comprehensive guide

✅ **Security Features**:
- Receiver locked to subvault
- No external routers (swapType=0, extRouter=0x0)
- No limit orders (limitRouter=0x0)
- Market and SY token locked
- Input tokens restricted to approved array

✅ **Configuration**:
- PT-sUSDe-27MAR2025
- Input tokens: USDe, sUSDe (⚠️ verify address!)
- Market: `0xfabeefc5369aa5270b401f4ee062d17fb5f1ec2a`

✅ **Next Steps**:
1. Verify sUSDe address is correct (`0x9D39A5...` not `0xC58D04...`)
2. Run script to generate JSON
3. Review security restrictions in generated file
4. Deploy Merkle root to BitmaskVerifier
5. Grant CALLER_ROLE to curator
6. Execute first PT purchase to test

**🚨 CRITICAL**: Always verify token addresses on Etherscan before deploying to production!
