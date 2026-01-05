# Quick Example: Generate Aave Operations JSON

## Scenario
You want to create a new subvault (subvault3) for Aave operations with:
- **Collateral**: WETH, wstETH
- **Loans**: USDC, USDT, USDE
- **Caller**: The existing curator (0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8)
- **Operations**: supply, withdraw, borrow, repay + push/pull liquidity from vault

## Step 1: In your deployment script

```solidity
// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./tqETH.s.sol";  // Extends the existing tqETH deploy script

contract DeployAaveOpsSubvault is Deploy {
    function run() external {
        vm.startBroadcast();

        Vault vault = Vault(payable(Constants.TQETH));
        address curator = 0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8;

        // 1. Create the verifier
        ProtocolDeployment memory $ = Constants.protocolDeployment();
        address verifier = $.verifierFactory.create(
            0,
            proxyAdmin,
            abi.encode(vault, bytes32(0))
        );

        // 2. Create the subvault
        address subvault = vault.createSubvault(0, proxyAdmin, verifier);

        console.log("Subvault created:", subvault);

        // 3. Generate proofs and descriptions
        (bytes32 merkleRoot, IVerifier.VerificationPayload[] memory leaves) =
            tqETHLibrary.getAaveOperationsProofs(subvault, address(vault), curator);

        string[] memory descriptions =
            tqETHLibrary.getAaveOperationsDescriptions(subvault, address(vault), curator);

        // 4. Save to JSON file
        ProofLibrary.storeProofs(
            "ethereum:tqETH:subvault3",  // Will create ethereum:tqETH:subvault3.json
            merkleRoot,
            leaves,
            descriptions
        );

        console.log("JSON saved with merkle root:", vm.toString(merkleRoot));
        console.log("Operations count:", leaves.length);

        // 5. Set the merkle root on the verifier
        IVerifier(verifier).setMerkleRoot(merkleRoot);

        console.log("Merkle root set on verifier");

        vm.stopBroadcast();
    }
}
```

## Step 2: Run the script

```bash
forge script scripts/ethereum/DeployAaveOpsSubvault.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

## What Gets Generated

File: `scripts/jsons/ethereum:tqETH:subvault3.json`

```json
{
  "title": "ethereum:tqETH:subvault3",
  "merkle_root": "0xabc123...",
  "merkle_proofs": [
    {
      "verificationType": 3,
      "description": {
        "description": "AaveInstance(Core).setUserEMode(categoryId=1)",
        "abi": { ... },
        "parameters": {
          "caller": "0xcca5bafea783b0ed8d11fd6d9f97c155332a16b8",
          "target": "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2",
          "value": "0"
        },
        "innerParameters": {
          "categoryId": "1"
        }
      },
      "verificationData": "0x...",
      "proof": ["0x...", "0x...", "0x..."]
    },
    {
      "verificationType": 3,
      "description": {
        "description": "IERC20(WETH).approve(AaveInstance(Core), anyInt)",
        "abi": { ... },
        "parameters": {
          "caller": "0xcca5bafea783b0ed8d11fd6d9f97c155332a16b8",
          "target": "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
          "value": "0"
        },
        "innerParameters": {
          "to": "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2",
          "amount": "any"
        }
      },
      "verificationData": "0x...",
      "proof": ["0x...", "0x..."]
    },
    {
      "verificationType": 3,
      "description": {
        "description": "AaveInstance(Core).supply(WETH, anyInt, subvault3, anyInt)",
        "abi": { ... },
        "parameters": {
          "caller": "0xcca5bafea783b0ed8d11fd6d9f97c155332a16b8",
          "target": "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2",
          "value": "0"
        },
        "innerParameters": {
          "asset": "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
          "amount": "any",
          "onBehalfOf": "0x...[subvault]",
          "referralCode": "0"
        }
      },
      "verificationData": "0x...",
      "proof": ["0x..."]
    },
    // ... (13 more Aave operations)
    // ... (~10 deposit/redeem operations)
  ]
}
```

## Step 3: Use in Production

Now the curator can call these operations:

```solidity
// Example: Supply 10 WETH as collateral
vault.call(
    subvault,
    Constants.WETH,
    abi.encodeCall(IERC20.approve, (Constants.AAVE_CORE, 10 ether)),
    ""  // empty proof - verifier checks merkle tree
);

vault.call(
    subvault,
    Constants.AAVE_CORE,
    abi.encodeCall(IAavePoolV3.supply, (Constants.WETH, 10 ether, subvault, 0)),
    ""
);

// Example: Borrow 5000 USDC
vault.call(
    subvault,
    Constants.AAVE_CORE,
    abi.encodeCall(IAavePoolV3.borrow, (Constants.USDC, 5000e6, 2, 0, subvault)),
    ""
);
```

## Alternative: Multiple Callers

If you want both curator AND agent1 to have access:

```solidity
// Generate operations for both callers
IVerifier.VerificationPayload[] memory allLeaves = new IVerifier.VerificationPayload[](50);
uint256 iterator = 0;

// Curator operations
AaveLibrary.Info memory curatorInfo = tqETHLibrary.getAaveOperationsInfo(subvault, curator);
iterator = ArraysLibrary.insert(
    allLeaves,
    AaveLibrary.getAaveProofs($.bitmaskVerifier, curatorInfo),
    iterator
);

// Agent1 operations
AaveLibrary.Info memory agent1Info = tqETHLibrary.getAaveOperationsInfo(subvault, agent1);
iterator = ArraysLibrary.insert(
    allLeaves,
    AaveLibrary.getAaveProofs($.bitmaskVerifier, agent1Info),
    iterator
);

// Add vault operations for both
// ... (similar pattern for CoreVaultLibrary)

// Trim and generate root
assembly { mstore(allLeaves, iterator) }
(bytes32 root, IVerifier.VerificationPayload[] memory leavesWithProofs) =
    ProofLibrary.generateMerkleProofs(allLeaves);

// Now both curator and agent1 can call with the same root!
IVerifier(verifier).setMerkleRoot(root);
```

## Customizing Assets

Want different assets? Just modify the helper:

```solidity
// Only WETH collateral, only USDC loans
function getCustomAaveInfo(address subvault, address curator)
    internal pure returns (AaveLibrary.Info memory)
{
    address[] memory collaterals = new address[](1);
    collaterals[0] = Constants.WETH;

    address[] memory loans = new address[](1);
    loans[0] = Constants.USDC;

    return tqETHLibrary.getAaveInfo(
        subvault,
        "subvault3",
        curator,
        collaterals,
        loans,
        0  // No eMode
    );
}
```

## Summary

**You need**:
1. Helper function call: `tqETHLibrary.getAaveOperationsProofs()`
2. Save to JSON: `ProofLibrary.storeProofs()`
3. Set root: `verifier.setMerkleRoot()`

**You get**:
- Supply/withdraw for WETH, wstETH
- Borrow/repay for USDC, USDT, USDE
- Push/pull liquidity to main vault
- All with proper bitmask verification
- All in one Merkle root
- All operations work with "any" amount
