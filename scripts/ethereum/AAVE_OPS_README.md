# Aave Operations Helper for tqETH

This guide explains how to generate Merkle tree JSON files for Aave operations on tqETH subvaults.

## Overview

The helper functions in `tqETHLibrary.sol` automatically generate all the verification payloads, Merkle proofs, and descriptions needed for:

1. **Aave Operations**: supply, withdraw, borrow, repay for specified assets
2. **eMode Management**: setUserEMode for Aave efficiency mode
3. **Vault Operations**: deposit/redeem to push/pull liquidity from main vault

## Quick Start

### Using the Pre-configured Helper

For the default configuration (WETH + wstETH as collateral, USDC + USDT + USDE as loans):

```solidity
import "./tqETHLibrary.sol";
import "../common/ProofLibrary.sol";

// In your script:
address subvault = vault.subvaultAt(3); // Your Aave ops subvault
address curator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;

// Generate everything automatically
(bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leaves) =
    tqETHLibrary.getAaveOperationsProofs(subvault, Constants.TQETH, curator);

string[] memory descriptions =
    tqETHLibrary.getAaveOperationsDescriptions(subvault, Constants.TQETH, curator);

// Save to JSON file
ProofLibrary.storeProofs(
    "ethereum:tqETH:aaveOps",
    merkleRoot,
    leaves,
    descriptions
);
```

This generates a JSON file at `scripts/jsons/ethereum:tqETH:aaveOps.json` with:
- **16 Aave operations**:
  - setUserEMode(1)
  - For WETH: approve, supply, withdraw
  - For wstETH: approve, supply, withdraw
  - For USDC: approve, borrow, repay
  - For USDT: approve, borrow, repay
  - For USDE: approve, borrow, repay
- **~10 Vault operations**: deposit/redeem for ETH, WETH, wstETH queues
- **All with the same Merkle root**

### Custom Asset Configuration

For custom collateral and loan assets:

```solidity
address[] memory collaterals = new address[](2);
collaterals[0] = Constants.WETH;
collaterals[1] = Constants.WSTETH;

address[] memory loans = new address[](3);
loans[0] = Constants.USDC;
loans[1] = Constants.USDT;
loans[2] = Constants.USDE;

AaveLibrary.Info memory aaveInfo = tqETHLibrary.getAaveInfo(
    subvault,
    "subvault3",  // subvault name
    curator,
    collaterals,
    loans,
    1  // categoryId: 1 = ETH correlated eMode
);

// Then use AaveLibrary.getAaveProofs(), etc.
```

## What Operations Are Included?

### For Each Collateral Asset
1. `IERC20(asset).approve(AaveCore, anyInt)` - Approve Aave to spend
2. `AaveCore.supply(asset, anyInt, subvault, anyInt)` - Supply collateral
3. `AaveCore.withdraw(asset, anyInt, subvault)` - Withdraw collateral

### For Each Loan Asset
1. `IERC20(asset).approve(AaveCore, anyInt)` - Approve for repayment
2. `AaveCore.borrow(asset, anyInt, 2, anyInt, subvault)` - Borrow (variable rate = 2)
3. `AaveCore.repay(asset, anyInt, 2, subvault)` - Repay loan

### eMode
1. `AaveCore.setUserEMode(categoryId)` - Set efficiency mode

### Vault Operations (Push/Pull Liquidity)
For each deposit queue (ETH, WETH, wstETH):
- `DepositQueue.deposit(...)` - Push liquidity to main vault
- `IERC20.approve(queue, ...)` - Approve queue (for non-ETH assets)

For each redeem queue (wstETH):
- `RedeemQueue.redeem(...)` - Request withdrawal from vault
- `RedeemQueue.claim(...)` - Claim withdrawal

## Parameter Validation with Bitmasks

The bitmasks control which parameters must match exactly vs "any":

```solidity
// Example: Supply operation
AaveCore.supply(
    WETH,      // ← Must be WETH exactly (bitmask: 0xFFF...FFF)
    anyAmount, // ← Can be any amount (bitmask: 0x000...000)
    subvault,  // ← Must be this subvault (bitmask: 0xFFF...FFF)
    anyRef     // ← Can be any referral (bitmask: 0x000...000)
)
```

Key points:
- **Caller**: Always checked (must be the specified curator/agent)
- **Target**: Always checked (must be Aave Core or specific queue)
- **Value**: Always 0 (no ETH sent)
- **Asset addresses**: Checked exactly
- **Amounts**: Allowed to be anything ("any")
- **Recipient (onBehalfOf)**: Always must be the subvault

## Available Helper Functions

### Pre-configured (Recommended)

```solidity
// Get proofs for WETH+wstETH collateral, USDC+USDT+USDE loans
tqETHLibrary.getAaveOperationsProofs(subvault, vault, caller)

// Get human-readable descriptions
tqETHLibrary.getAaveOperationsDescriptions(subvault, vault, caller)

// Get test calls (for verification)
tqETHLibrary.getAaveOperationsSubvaultCalls(subvault, vault, caller, leaves)
```

### Custom Configuration

```solidity
// Create custom Aave info
tqETHLibrary.getAaveInfo(
    subvault,
    subvaultName,
    caller,
    collateralAssets,  // address[] - what can be supplied
    loanAssets,        // address[] - what can be borrowed
    categoryId         // uint8 - Aave eMode (0=none, 1=ETH, etc.)
)

// Then use AaveLibrary directly:
AaveLibrary.getAaveProofs(bitmaskVerifier, aaveInfo)
AaveLibrary.getAaveDescriptions(aaveInfo)
AaveLibrary.getAaveCalls(aaveInfo)
```

## Multiple Callers, Same Root

You can generate operations for multiple callers that share the same Merkle root:

```solidity
// Approach 1: Generate separate JSONs, then merge manually
generateJSON("ethereum:tqETH:aaveOps:curator", subvault, curator);
generateJSON("ethereum:tqETH:aaveOps:agent1", subvault, agent1);

// Approach 2: Build combined leaves array
IVerifier.VerificationPayload[] memory allLeaves = new IVerifier.VerificationPayload[](100);
uint256 iterator = 0;

// Add curator operations
(, IVerifier.VerificationPayload[] memory curatorLeaves) =
    tqETHLibrary.getAaveOperationsProofs(subvault, vault, curator);
iterator = ArraysLibrary.insert(allLeaves, curatorLeaves, iterator);

// Add agent1 operations
(, IVerifier.VerificationPayload[] memory agent1Leaves) =
    tqETHLibrary.getAaveOperationsProofs(subvault, vault, agent1);
iterator = ArraysLibrary.insert(allLeaves, agent1Leaves, iterator);

// Generate single root for all
assembly { mstore(allLeaves, iterator) }
(bytes32 root, IVerifier.VerificationPayload[] memory leavesWithProofs) =
    ProofLibrary.generateMerkleProofs(allLeaves);
```

## Using the Generated Script

1. **Set the subvault address** in `GenerateAaveOpsJSON.s.sol`:
   ```solidity
   address subvault = vault.subvaultAt(3); // Replace with actual index
   ```

2. **Run for curator**:
   ```bash
   forge script scripts/ethereum/GenerateAaveOpsJSON.s.sol --sig "generateForCurator()"
   ```

3. **Run for agent1**:
   ```bash
   forge script scripts/ethereum/GenerateAaveOpsJSON.s.sol --sig "generateForAgent1()"
   ```

4. **Run for all 5 assets**:
   ```bash
   forge script scripts/ethereum/GenerateAaveOpsJSON.s.sol --sig "generateAllAssetsExample()"
   ```

## Understanding the Merkle Root

### How It Works
- **One root per subvault verifier**: Each subvault has its own verifier contract with one Merkle root
- **Multiple callers share the root**: The root contains leaves for ALL allowed operations by ALL callers
- **Verification**: When a caller tries an operation, the verifier checks if there's a valid leaf+proof for that (caller, target, function, params) combination

### Example
```
Merkle Root: 0xabcd...
├─ Leaf 1: curator.supply(WETH, any, subvault, any)
├─ Leaf 2: curator.withdraw(WETH, any, subvault)
├─ Leaf 3: curator.borrow(USDC, any, 2, any, subvault)
├─ Leaf 4: agent1.supply(WETH, any, subvault, any)
├─ Leaf 5: agent1.withdraw(WETH, any, subvault)
└─ ... (all other operations)
```

Both curator and agent1 operations are in the same tree with the same root!

## Aave eMode Category IDs

- `0`: No eMode (all assets, lower LTV)
- `1`: ETH correlated (WETH, wstETH, stETH - higher LTV)
- `2`: USD correlated (USDC, USDT, DAI - higher LTV)

Use eMode category 1 when collateral and loans are both ETH-based for better capital efficiency.

## Asset Addresses (Constants)

All available in `Constants.sol`:
- `Constants.WETH` - 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
- `Constants.WSTETH` - 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
- `Constants.USDC` - 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
- `Constants.USDT` - 0xdAC17F958D2ee523a2206206994597C13D831ec7
- `Constants.USDE` - 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3
- `Constants.AAVE_CORE` - 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2
- `Constants.TQETH` - 0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d

## Next Steps

After generating the JSON file:

1. **Review the JSON** at `scripts/jsons/ethereum:tqETH:aaveOps.json`
2. **Set the Merkle root** on the subvault verifier:
   ```solidity
   IVerifier verifier = Subvault(subvault).verifier();
   verifier.setMerkleRoot(merkleRoot);
   ```
3. **Test the operations** using the test calls from `getAaveOperationsSubvaultCalls()`
4. **Grant roles** to the callers:
   ```solidity
   vault.grantRole(Permissions.CALLER_ROLE, curator);
   vault.grantRole(Permissions.PULL_LIQUIDITY_ROLE, curator);
   vault.grantRole(Permissions.PUSH_LIQUIDITY_ROLE, curator);
   ```

## Troubleshooting

**Q: Can I limit the amount that can be borrowed?**
A: No, bitmasks only support exact matching or "any". Use Aave's eMode and vault limits instead.

**Q: How do I add more assets later?**
A: Generate a new JSON with the expanded asset list, get a new Merkle root, and call `setMerkleRoot()` again.

**Q: Can different subvaults share the same root?**
A: No, each subvault has its own verifier instance with its own root. But multiple callers on the same subvault share one root.

**Q: What if I want supply and withdraw but not borrow/repay?**
A: Use `AaveLibrary.getAaveInfo()` with an empty `loans` array, or build your own leaves array using the patterns in `AaveLibrary.sol`.
