# Cross-Chain Aave Operations Guide

## Quick Summary

✅ **Add new assets**: Just modify the collateral/loan arrays
✅ **Different chain**: Change Aave pool address + asset addresses + RPC
✅ **Chain ID in filename**: Automatic! Format: `chainName:chainId:aaveOps.json`

---

## 1. Adding New Assets (Same Chain)

### Option A: Modify the Helper Function

Edit [tqETHLibrary.sol:274-297](../ethereum/tqETHLibrary.sol#L274-L297):

```solidity
function getAaveOperationsInfo(address subvault, address curator)
    internal pure returns (AaveLibrary.Info memory)
{
    // STEP 1: Change array size
    address[] memory collaterals = new address[](4);  // Was 3, now 4
    collaterals[0] = Constants.WETH;
    collaterals[1] = Constants.WSTETH;
    collaterals[2] = Constants.USDE;
    collaterals[3] = Constants.DAI;  // ← NEW ASSET!

    // STEP 2: Change array size
    address[] memory loans = new address[](4);  // Was 3, now 4
    loans[0] = Constants.USDC;
    loans[1] = Constants.USDT;
    loans[2] = Constants.USDE;
    loans[3] = Constants.WEETH;  // ← NEW ASSET!

    return AaveLibrary.Info({
        subvault: subvault,
        subvaultName: "aaveOps",
        curator: curator,
        aaveInstance: Constants.AAVE_CORE,
        aaveInstanceName: "Core",
        collaterals: collaterals,
        loans: loans,
        categoryId: 0
    });
}
```

### Option B: Use Custom Generator

Use `GenerateAaveOpsJSON.s.sol:generateCustomJSON()` with your own arrays:

```solidity
address[] memory collaterals = new address[](5);
collaterals[0] = Constants.WETH;
collaterals[1] = Constants.WSTETH;
collaterals[2] = Constants.USDC;
collaterals[3] = Constants.USDT;
collaterals[4] = Constants.USDE;

address[] memory loans = new address[](3);
loans[0] = Constants.USDC;
loans[1] = Constants.USDT;
loans[2] = Constants.DAI;

generateCustomJSON(
    "ethereum:tqETH:customAave",
    subvault,
    "subvault3",
    curator,
    collaterals,
    loans,
    0  // eMode category
);
```

---

## 2. Cross-Chain Deployment

### Step-by-Step Process

#### Step 1: Find Aave Pool Address for Your Chain

| Chain | Aave V3 Pool Address |
|-------|---------------------|
| Ethereum | `0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2` |
| Arbitrum | `0x794a61358D6845594F94dc1DB02A252b5b4814aD` |
| Optimism | `0x794a61358D6845594F94dc1DB02A252b5b4814aD` |
| Polygon | `0x794a61358D6845594F94dc1DB02A252b5b4814aD` |
| Base | `0xA238Dd80C259a72e81d7e4664a9801593F98d1c5` |
| Avalanche | `0x794a61358D6845594F94dc1DB02A252b5b4814aD` |

📖 Full list: https://docs.aave.com/developers/deployed-contracts/v3-mainnet

#### Step 2: Find Asset Addresses on Target Chain

Example for **Arbitrum**:

```solidity
// Arbitrum asset addresses
WETH:   0x82aF49447D8a07e3bd95BD0d56f35241523fBab1
wstETH: 0x5979D7b546E38E414F7E9822514be443A4800529
USDC:   0xaf88d065e77c8cC2239327C5EDb3A432268e5831
USDT:   0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9
USDe:   0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34
```

#### Step 3: Use Cross-Chain Generator

Edit [GenerateAaveOpsJSONCrossChain.s.sol](GenerateAaveOpsJSONCrossChain.s.sol):

```solidity
function generateArbitrum() external {
    ChainConfig memory config = ChainConfig({
        chainId: 42161,
        chainName: "arbitrum",
        aavePool: 0x794a61358D6845594F94dc1DB02A252b5b4814aD,
        collateralAssets: new address[](3),
        loanAssets: new address[](3),
        eModeCategory: 0
    });

    // Set your asset addresses
    config.collateralAssets[0] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;  // WETH
    config.collateralAssets[1] = 0x5979D7b546E38E414F7E9822514be443A4800529;  // wstETH
    config.collateralAssets[2] = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;  // USDe

    config.loanAssets[0] = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;  // USDC
    config.loanAssets[1] = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;  // USDT
    config.loanAssets[2] = 0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34;  // USDe

    address subvault = 0xYourSubvaultAddress;  // ← SET THIS!
    address curator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;
    address vault = 0xYourArbitrumVaultAddress;  // ← SET THIS!

    generateForChain(config, subvault, vault, curator);
}
```

#### Step 4: Generate with Correct RPC

```bash
# Ethereum
forge script scripts/ethereum/GenerateAaveOpsJSONCrossChain.s.sol \
  --sig "generateEthereum()" \
  --rpc-url $ETHEREUM_RPC_URL

# Arbitrum
forge script scripts/ethereum/GenerateAaveOpsJSONCrossChain.s.sol \
  --sig "generateArbitrum()" \
  --rpc-url $ARBITRUM_RPC_URL

# Base
forge script scripts/ethereum/GenerateAaveOpsJSONCrossChain.s.sol \
  --sig "generateBase()" \
  --rpc-url $BASE_RPC_URL
```

---

## 3. Output Files with Chain ID ✅

### Automatic Naming

The cross-chain generator **automatically includes chain ID** in the filename:

```
Format: {chainName}:{chainId}:aaveOps.json

Examples:
├── ethereum:1:aaveOps.json       ← Ethereum mainnet
├── arbitrum:42161:aaveOps.json   ← Arbitrum One
├── base:8453:aaveOps.json        ← Base
├── optimism:10:aaveOps.json      ← Optimism
└── polygon:137:aaveOps.json      ← Polygon
```

**No overwrites!** Each chain gets its own file.

### File Contents

```json
{
  "title": "arbitrum:42161:aaveOps",
  "merkle_root": "0xdef456...",
  "merkle_proofs": [
    {
      "verificationType": 3,
      "description": {
        "description": "AaveInstance(AaveV3).supply(WETH, anyInt, aaveOps, anyInt)",
        "parameters": {
          "caller": "0xcca5bafea783b0ed8d11fd6d9f97c155332a16b8",
          "target": "0x794a61358D6845594F94dc1DB02A252b5b4814aD",
          "value": "0"
        }
      },
      "verificationData": "0x...",
      "proof": ["0x...", "0x..."]
    }
  ]
}
```

---

## 4. Complete Example: Ethereum → Arbitrum

### Scenario
You have operations on Ethereum and want to add the same on Arbitrum.

### Steps

1. **Deploy on Arbitrum** (if not done):
   ```bash
   # Deploy vault and subvault on Arbitrum
   forge script scripts/arbitrum/Deploy.s.sol \
     --rpc-url $ARBITRUM_RPC_URL \
     --broadcast
   ```

2. **Configure Arbitrum in the script**:
   ```solidity
   // In GenerateAaveOpsJSONCrossChain.s.sol:generateArbitrum()
   address subvault = 0xArbitrumSubvaultAddress;  // From step 1
   address vault = 0xArbitrumVaultAddress;        // From step 1
   address curator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332a16b8;  // Same curator!
   ```

3. **Generate Arbitrum JSON**:
   ```bash
   forge script scripts/ethereum/GenerateAaveOpsJSONCrossChain.s.sol \
     --sig "generateArbitrum()" \
     --rpc-url $ARBITRUM_RPC_URL

   # Output:
   # Generated JSON file: ./scripts/jsons/arbitrum:42161:aaveOps.json
   # Merkle root: 0xdef456...
   # Operations count: 22
   ```

4. **Set root on Arbitrum**:
   ```bash
   # Deploy script or separate transaction on Arbitrum
   cast send $VERIFIER_ADDRESS \
     "setMerkleRoot(bytes32)" \
     0xdef456... \
     --rpc-url $ARBITRUM_RPC_URL \
     --private-key $DEPLOYER_KEY
   ```

5. **Now you have**:
   - ✅ `ethereum:1:aaveOps.json` with root `0xabc123...`
   - ✅ `arbitrum:42161:aaveOps.json` with root `0xdef456...`
   - ✅ Same curator can operate on both chains!

---

## 5. Quick Reference: What Changes Per Chain?

| Item | Ethereum | Arbitrum | Base |
|------|----------|----------|------|
| **Aave Pool** | `0x87870...` | `0x794a6...` | `0xA238D...` |
| **WETH** | `0xC02aa...` | `0x82aF4...` | `0x42000...` |
| **wstETH** | `0x7f39C...` | `0x5979D...` | `0xc1CBa...` |
| **USDC** | `0xA0b86...` | `0xaf88d...` | `0x83358...` |
| **RPC URL** | ETH RPC | ARB RPC | BASE RPC |
| **Chain ID** | 1 | 42161 | 8453 |
| **Output File** | `ethereum:1:aaveOps.json` | `arbitrum:42161:aaveOps.json` | `base:8453:aaveOps.json` |

---

## 6. Advanced: Custom Chain Configuration

For a completely new chain:

```solidity
function generateCustomChain() external {
    ChainConfig memory config = ChainConfig({
        chainId: 12345,                    // ← Your chain ID
        chainName: "mychain",              // ← Your chain name
        aavePool: 0x...,                   // ← Aave pool address
        collateralAssets: new address[](2),
        loanAssets: new address[](2),
        eModeCategory: 0
    });

    // Set assets
    config.collateralAssets[0] = 0x...;
    config.collateralAssets[1] = 0x...;
    config.loanAssets[0] = 0x...;
    config.loanAssets[1] = 0x...;

    // Deploy addresses
    address subvault = 0x...;
    address vault = 0x...;
    address curator = 0x...;

    generateForChain(config, subvault, vault, curator);
}
```

Run with:
```bash
forge script scripts/ethereum/GenerateAaveOpsJSONCrossChain.s.sol \
  --sig "generateCustomChain()" \
  --rpc-url $YOUR_CHAIN_RPC
```

Output: `./scripts/jsons/mychain:12345:aaveOps.json`

---

## 7. Troubleshooting

### Different asset addresses on different chains?
✅ **Solution**: Each chain has its own `ChainConfig` with chain-specific addresses.

### Files overwriting each other?
✅ **Solution**: Chain ID is in the filename - impossible to overwrite!

### Same curator across chains?
✅ **Solution**: Use the same curator address in all chain configs. The Merkle root will be different per chain, but the curator's EOA is the same.

### Need to add asset later?
✅ **Solution**:
1. Modify the collateral/loan arrays
2. Re-run the generator
3. Get new Merkle root
4. Call `verifier.setMerkleRoot(newRoot)` on-chain

---

## 8. Summary Checklist

- [ ] Find Aave pool address for target chain
- [ ] Find asset addresses on target chain
- [ ] Update ChainConfig in the script
- [ ] Set subvault, vault, curator addresses
- [ ] Run with correct RPC URL
- [ ] JSON file generated: `{chainName}:{chainId}:aaveOps.json`
- [ ] Deploy root on-chain: `verifier.setMerkleRoot(root)`
- [ ] Grant roles: `vault.grantRole(CALLER_ROLE, curator)`

**Result**: Multi-chain Aave operations with zero file conflicts! 🎉
