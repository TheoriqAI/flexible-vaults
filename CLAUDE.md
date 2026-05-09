# Flexible Vaults — Claude Quick Reference

This is a Mellow tqETH flexible-vaults fork. Work centers on generating merkle-root-gated permission JSONs, merging them, and validating on mainnet forks before rotating the on-chain root.

---

## Vault / Subvault layout

| Name | Address | Chain |
|------|---------|-------|
| Prod Vault (tqETH) | `0xDbC81B33A23375A90c8Ba4039d5738CB6f56fE8d` | Ethereum |
| SV3 (Aave/Spark/Morpho) | `0x36d8d9fC89eEB1aBbfc6101Cc23945e79416D9f3` | Ethereum |
| SV4 (Aave eMode 44 / Pendle / Spark eMode 0 / ...) | `0xB747b828A22001cAC25243C18408697845C3B68E` | Ethereum |
| Monad Prod Vault | `0x799d2847cF8Dfcb4f17ec28737f17C0E82Eb445c` | Monad |
| Monad SV0 (Euler / SwapModule / Morpho / NTT+CCIP+CCTP) | `0x0C7cb4e1241F4B7Fd65DE59FDE5a6dBFf190fB20` | Monad |
| prodCurator (Ethereum) | `0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8` | — |
| prodCurator (Monad) | `0x5FFA51F64Bc40c5af3a435A95e9616cc2Df9F01B` | — |
| activeAdmin (Ethereum tests) | `0x2D95cb50F204B8B84606751F262b407C08528c85` | — |
| Monad admin (detected dynamically via `getRoleMember(bytes32(0), 0)`) | — | — |

### SwapModule addresses

| Subvault | SwapModule | Chain |
|----------|-----------|-------|
| SV2 (Ethereum) | `0xD1EE1697e278F9bC73BFFeF4495FB0Cd91B375Cf` | Ethereum |
| SV3 (Ethereum) | `0xb1578423a1db4ede605b718b9b749751e44ff552` | Ethereum |
| SV4 (Ethereum) | `0x114dea9b67A31E704dAbE28bed51C49C01940DDf` | Ethereum |
| Monad SV0 | `0x34C39003f5D5Dbb022926642b0fD28A2fd9ec544` | Monad |

Ethereum fork URL used in tests: `http://108.53.61.201:8550` (user's private fork, unreachable from external Claude envs — swap to `https://ethereum-rpc.publicnode.com` only temporarily for diagnostic runs, always restore).

---

## Key directories

```
scripts/
  configs/                    — JSON configs consumed by generators (e.g. prod-sv4-pendle.json)
  common/
    protocols/                — AaveLibrary, PendleLibrary, SwapModuleLibrary, CCTPLibrary, NTTLibrary, EulerLibrary
    interfaces/               — IMorpho, IAavePoolV3, INttManagerWithExecutor, IEulerVault, ...
  ethereum/
    Constants.sol             — all Ethereum addresses (tokens, PT tokens, Pendle markets, Aave, Spark, Morpho)
    GenerateAaveOpsJSON.s.sol — Aave/Spark ops generator (Spark uses same code, just pass Constants.SPARK as pool)
    GenerateMorphoJSON.s.sol  — Morpho market ops
    GeneratePendleJSON.s.sol  — consumes scripts/configs/prod-sv4-pendle.json
    GenerateSwapModuleJSON.s.sol — SwapModule (per-asset push/pull/approve)
    GenerateEnterExitJSON.s.sol  — Lido/Ethena/srUSDe withdrawals
    GenerateAaveOpsJSONCrossChain.s.sol — CCTP bridge ops for SV4
  monad/
    Constants.sol             — Monad addresses (MON, WMON, WETH, WSTETH, USDC, Euler vaults, NTT/CCIP/CCTP)
    MVT.s.sol / test/monLibrary.sol — Monad SV0 generator
  jsons/
    prod/tqETH/               — all PROD JSONs live here (sv3/sv4/monad SV0)
      sv4-aaveOps-emode44.json, sv4-morphoOps.json, sv4-pendlePT.json, sv4-swapModule.json,
      sv4-withdrawals.json, sv4-cctpBridge-USDC-monad.json, sv4-sparkOps-emode0.json,
      ethereum:tqETH:prod:sv4:all.json             ← merged root
      ethereum:tqETH:prod:sv3:all.json             ← merged root
      monad:tqMON:prod:sv0:all.json                ← merged root
  merge_jsons_new.py          — Solidity-compatible leaf hashing, regenerates root+proofs
                                (emits merge_metadata top-level with timestamp + sources)

test/
  ProdSubvaultIntegration.t.sol     — SV3 tests (Aave + Spark + Morpho savETH + SwapModule + CCIP + NTT)
  ProdSv4EMode44Integration.t.sol   — SV4 full suite
  MonadSv0Integration.t.sol          — Monad SV0 (Euler, SwapModule, NTT, CCIP, CCTP, Morpho, Merkl)
```

---

## A. Generate a new JSON

1. **Add constants** to `scripts/ethereum/Constants.sol` (or monad/Constants.sol). Always `cast to-check-sum-address` first.
2. **Pick or add a generator function** in the matching `Generate*JSON.s.sol`:
   - Aave/Spark → `GenerateAaveOpsJSON.s.sol`, call `generateWithCustomAssets(subvault, isProd, pool, collaterals, borrows, suffix, categoryId)`
   - Pendle → edit `scripts/configs/prod-sv4-pendle.json` (strategies array), generator reads it
   - SwapModule → edit asset array in `GenerateSwapModuleJSON.s.sol` for the relevant subvault function
   - Morpho → `GenerateMorphoJSON.s.sol`
3. **Run** with mainnet fork RPC (subvault addresses are read from on-chain Vault):
   ```bash
   forge script scripts/ethereum/GenerateAaveOpsJSON.s.sol \
     --sig "generateProdSv4SparkEMode0(uint8)" 0 \
     --rpc-url https://ethereum-rpc.publicnode.com --via-ir
   ```
4. **Move output** from `scripts/jsons/ethereum:tqETH:...json` → `scripts/jsons/prod/tqETH/sv4-<name>.json`, delete the `-lean` file.

### Gotchas
- Generator reverts with "call to non-contract address" if RPC doesn't have the vault (needs a real Ethereum RPC).
- USDT's `approve` rejects non-zero → non-zero; account for this in tests (use exact amounts that drain allowance to 0 before re-approving).

---

## B. Merge JSONs into `all.json`

```bash
cd /Users/jpickett713/chainML/forks/flexible-vaults
python3 scripts/merge_jsons_new.py ethereum:tqETH:prod:sv4:all \
  scripts/jsons/prod/tqETH/sv4-aaveOps-emode44.json \
  scripts/jsons/prod/tqETH/sv4-morphoOps.json \
  scripts/jsons/prod/tqETH/sv4-swapModule.json \
  scripts/jsons/prod/tqETH/sv4-pendlePT.json \
  scripts/jsons/prod/tqETH/sv4-withdrawals.json \
  scripts/jsons/prod/tqETH/sv4-cctpBridge-USDC-monad.json \
  scripts/jsons/prod/tqETH/sv4-sparkOps-emode0.json
```

- Output lands in `scripts/jsons/<title>.json` — move it to `scripts/jsons/prod/tqETH/` after.
- Order of input files == order of indices in merged output. **Append new files to preserve existing test indices.**
- Script emits `merge_metadata` (UTC timestamp + source file list with per-file op counts). Tests ignore it — they only read `merkle_root` and `merkle_proofs`.
- Root changes every merge because the tree is fully regenerated.

### Current merge orders (order → index ranges in `all.json`)

#### SV4 (164 ops, root `0x1e0613cae95ac63c100be84c7dbb3a78ba5305e747332cc7d98d39a92d313f10`)
| Indices | Source file | Contents |
|---------|-------------|----------|
| 0–21 | `sv4-aaveOps-emode44.json` | Aave Core eMode 44 (22 ops) |
| 22–77 | `sv4-morphoOps.json` | Morpho 7 markets (56 ops) |
| 78–103 | `sv4-swapModule.json` | SwapModule ETH/WETH/wstETH/USDC/USDT/USDe/sUSDe/NUSD/Sierra (26 ops) |
| 104–133 | `sv4-pendlePT.json` | Pendle 4 markets (30 ops) |
| 134–142 | `sv4-withdrawals.json` | Withdrawals Lido/sUSDe/sNUSD/srUSDe (9 ops) |
| 143–144 | `sv4-cctpBridge-USDC-monad.json` | CCTP USDC → Monad (2 ops) |
| 145–163 | `sv4-sparkOps-emode0.json` | Spark eMode 0 (19 ops) |

#### SV3 (74 ops, root `0xdfcf365d967ea0221e7ef44b56fba8aab6ccb84774c1145e605bb2f54141cbe4`)
| Indices | Source file | Contents |
|---------|-------------|----------|
| 0–21 | `sv3-aaveOps-emode1.json` | Aave eMode 1 (22 ops) |
| 22–43 | `sv3-sparkOps-emode1.json` | Spark eMode 1 (22 ops) |
| 44–51 | `sv3-morphoOps.json` | Morpho WETH/savETH market (8 ops incl. approvals) |
| 52–69 | `sv3-swapModule.json` | SwapModule (18 ops: approves + push/pull per asset) |
| 70–71 | `sv3-ccipBridge-wstETH-monad.json` | CCIP wstETH → Monad (2 ops) |
| 72–73 | `sv3-nttBridge-WETH-monad.json` | NTT WETH → Monad (2 ops) |

Note: SV3's Lido withdrawals JSON exists (`ethereum:tqETH:prod:sv3:lidoWithdrawal.json`) but **is not merged** into current all.json. Future versioning tracking in `merge_jsons_new.py`'s `merge_metadata` field should catch this kind of drift.

#### Monad SV0 (68 ops, root `0x7275f345f55cbe2f8cb73bddc53dc90dac7722a61248a40d06afbada60a14c27`)
| Indices | Source file | Contents |
|---------|-------------|----------|
| 0–16 | `monad:tqMON:prod:sv0:eulerOps.json` | Euler USDC/WETH/wstETH supply/withdraw + borrow approves (17 ops) |
| 17–25 | (part of eulerOps) | EVC collateral/controller enable/disable (9 ops) |
| 26–36 | `monad:tqMON:prod:sv0:swapModule.json` | SwapModule WMON/MON/USDC/WETH push/pull (11 ops) |
| 37–38 | `monad:tqMON:prod:sv0:nttBridge.json` | NTT approve + transfer (2 ops) |
| 39–40 | `monad:tqMON:prod:sv0:ccipBridge.json` | CCIP approve + ccipSend (2 ops) |
| 41–42 | `monad:tqMON:prod:sv0:cctpBridge.json` | CCTP approve + depositForBurn (2 ops) |
| 43–66 | `monad:tqMON:prod:sv0:morphoOps.json` | Morpho 3 markets USDC/aHYPER, USDC/syzUSD, USDC/mHYPER (24 ops: 8 per market) |
| 67 | `monad:tqMON:prod:sv0:merklClaim.json` | Merkl toggleOperator (1 op) |

---

## C. Configs (`scripts/configs/`)

### `prod-sv4-pendle.json` (consumed by `GeneratePendleJSON.s.sol`)

```json
{
  "subvaultIndex": 4,
  "isProd": true,
  "strategies": [
    {
      "ptToken":      "0x...",          // PT token address
      "market":       "0x...",          // Pendle market address
      "inputTokens":  ["0x...", ...],   // allowed assets to swap INTO PT (enter)
      "outputTokens": ["0x...", ...],   // allowed assets to exit PT TO (exit + post-expiry)
      "description":  "PT-<asset>-<EXPIRY>"
    }
  ]
}
```

Ops generated per strategy: `2*inputTokens.length + 1 + 2*outputTokens.length`
(input approves + swapExactTokenForPt per input + PT approve + swapExactPtForToken per output + exitPostExpToToken per output)

### `prod-sv4-withdrawals.json` / `prod-sv3-withdrawals.json` (consumed by `GenerateEnterExitJSON.s.sol`)

```json
{
  "subvaultIndex": 4,
  "outputSuffix": "withdrawals",
  "enableLidoWithdrawal":   true,   // Lido unstETH NFT flow (request, claim)
  "enableSusdeWithdrawal":  true,   // Ethena sUSDe cooldown + unstake
  "enableSnusdDeposit":     true,   // sNUSD vault deposit + cooldownShares
  "enableSrusdeWithdraw":   true,   // srUSDe withdraw post-cooldown
  "curveSwaps": [],
  "pushAssets": [],
  "pullAssets": []
}
```

Each toggle controls which enter/exit ops get included.

---

## D. Detailed op index maps

### SV4 (164 ops)

```
0:        Aave setUserEMode(44)
1-3:      sUSDe    (approve, supply, withdraw)
4-6:      PT-srUSDe-24JUN2026 (approve, supply, withdraw)
7-9:      wstETH   (approve, supply, withdraw)
10-12:    WETH     (approve, supply, withdraw)
13-15:    USDe     (approve, borrow, repay)
16-18:    USDC     (approve, borrow, repay)
19-21:    USDT     (approve, borrow, repay)

22-29:    Morpho sNUSD/USDC             (approve coll, approve loan, supply, supplyCollateral, repay, borrow, withdraw, withdrawCollateral)
30-37:    Morpho reUSD/USDC
38-45:    Morpho savUSD/USDC
46-53:    Morpho sUSN/USDC
54-61:    Morpho PT-savUSD-14MAY2026/USDC
62-69:    Morpho PT-sNUSD-4JUN2026/USDC
70-77:    Morpho PT-reUSD-25JUN2026/USDC

78-80:    SwapModule ETH       (push, pull — ETH uses value, no approve)
81-83:    SwapModule WETH      (approve, push, pull)
84-86:    SwapModule wstETH    (approve, push, pull)
87-89:    SwapModule USDC      (approve, push, pull)
90-92:    SwapModule USDT      (approve, push, pull)
93-95:    SwapModule USDe      (approve, push, pull)
96-98:    SwapModule sUSDe     (approve, push, pull)
99-101:   SwapModule NUSD      (approve, push, pull)
102-103:  SwapModule Sierra    (approve, push, pull)   ← 2 ops? verify if apxUSD added

104-112:  Pendle PT-sUSDe-06MAY2026    (2 input approves, 2 swapTokenForPt, 1 PT approve, 2 swapPtForToken, 2 exitPostExp)
113-123:  Pendle PT-srUSDe-24JUN2026   (3 input approves, 3 swapTokenForPt, 1 PT approve, 2 swapPtForToken, 2 exitPostExp)
124-128:  Pendle PT-sNUSD-03JUN2026    (1 approve, 1 swapTokenForPt, 1 PT approve, 1 swapPtForToken, 1 exitPostExp)
129-133:  Pendle PT-Sierra-01JUL2026   (1 approve, 1 swapTokenForPt, 1 PT approve, 1 swapPtForToken, 1 exitPostExp)

134:      Lido: submitRequest (wstETH → Lido unstETH)
135:      Lido: claimWithdrawal
136-138:  sUSDe withdrawal flow (cooldownShares + unstake + …)
139-140:  sNUSD deposit cooldown ops
141-142:  srUSDe withdraw ops

143:      CCTP approve USDC → TokenMessengerV2
144:      CCTP depositForBurn (USDC → Monad)

145:      Spark setUserEMode(0)
146-148:  Spark wstETH (approve, supply, withdraw)
149-151:  Spark WETH   (approve, supply, withdraw)
152-154:  Spark USDC   (approve, supply, withdraw)
155-157:  Spark USDT   (approve, supply, withdraw)
158-160:  Spark USDC   (approve, borrow, repay)
161-163:  Spark USDT   (approve, borrow, repay)
```

### SV3 (74 ops)

```
0:       Aave setUserEMode(1)
1-3:     Aave WETH    (approve, supply, withdraw)
4-6:     Aave wstETH  (approve, supply, withdraw)
7-9:     Aave WETH    (approve, borrow, repay)
10-12:   Aave wstETH  (approve, borrow, repay)
13-15:   Aave USDC    (approve, borrow, repay)
16-18:   Aave USDT    (approve, borrow, repay)
19-21:   Aave USDe    (approve, borrow, repay)

22:      Spark setUserEMode(1)
23-25:   Spark WETH   (approve, supply, withdraw)
26-28:   Spark wstETH (approve, supply, withdraw)
29-31:   Spark WETH   (approve, borrow, repay)
32-34:   Spark wstETH (approve, borrow, repay)
35-37:   Spark USDC   (approve, borrow, repay)
38-40:   Spark USDT   (approve, borrow, repay)
41-43:   Spark USDe   (approve, borrow, repay)

44:      Morpho approve savETH → Morpho
45:      Morpho approve WETH   → Morpho
46:      Morpho supply (WETH/savETH market)
47:      Morpho supplyCollateral (WETH/savETH)
48:      Morpho repay (WETH/savETH)
49:      Morpho borrow (WETH/savETH)
50:      Morpho withdraw (WETH/savETH)
51:      Morpho withdrawCollateral (WETH/savETH)

52-69:   SwapModule (6 assets × 3 ops: approve, push, pull → WETH, wstETH, USDC, USDT, USDe, sUSDe)

70-71:   CCIP wstETH → Monad (approve, ccipSend)
72-73:   NTT  WETH  → Monad (approve, transfer)
```

Morpho WETH/savETH market id: `0xd98cd88ae5b336086b39fb1d62ba6171282e946105b010143f0e89f8fe7cff36`

### Monad SV0 (68 ops)

```
0-2:     Euler USDC   (approve, deposit, withdraw)
3-5:     Euler WETH   (approve, deposit, withdraw)
6-8:     Euler wstETH (approve, deposit, withdraw)
9-12:    Euler WETH   borrow side (approve, borrow, repay, liquidate)
13-16:   Euler USDC   borrow side (approve, borrow, repay, liquidate)
17-22:   EVC enable/disable collateral (USDC, WETH, wstETH × enable/disable)
23-25:   EVC enableController WETH, enableController USDC, disableController

26-28:   SwapModule WMON  (approve, push, pull)
29-30:   SwapModule MON   (push, pull)              ← native, no approve
31-33:   SwapModule USDC  (approve, push, pull)
34-36:   SwapModule WETH  (approve, push, pull)

37-38:   NTT  WETH   → Ethereum SV3 (approve, transfer)
39-40:   CCIP wstETH → Ethereum SV3 (approve, ccipSend)
41-42:   CCTP USDC   → Ethereum SV4 (approve, depositForBurn)

43-50:   Morpho USDC/aHYPER         (8 ops)
51-58:   Morpho USDC/syzUSD         (8 ops)
59-66:   Morpho USDC/mHYPER         (8 ops)

67:      Merkl toggleOperator(subvault, curator)
```

Morpho market IDs on Monad:
- USDC/aHYPER: `0x9e8441e7af65860feac831ebc117473e3033321abf528ebc8fbde1eeaaa3a626`
- USDC/syzUSD: `0x647f2acdadd47ed0fad3ef826e3513fd7fdf9328b0c1f24b8c762c6d79511bf6`
- USDC/mHYPER: `0x2761e7fe2dc3b712a7cf6d46286abc26864a65767d823c32ca554fa4ba309c6b`

Euler vaults on Monad:
- EULER_USDC: `0x1E4D67c666c2Ccf27A0aF980fE6c8e0f05aC8949`
- EULER_WETH (v2): `0x502e4a0B61dEBA3015Eb9E51116B832003B22c2C`
- EULER_WSTETH (v2): `0x61788859B923989dFeb995b8DE5CbBcD719475e9`
- EVC: `0x7a9324E8f270413fa2E458f5831226d99C7477CD`

---

## E. Test against fork

1. Test files use `vm.createSelectFork("http://108.53.61.201:8550")` — the user's private fork. From external Claude envs, temporarily swap to public RPC:
   ```bash
   sed -i '' 's|http://108.53.61.201:8550|https://ethereum-rpc.publicnode.com|' test/<file>.t.sol
   forge test --match-test <name> --match-path test/<file>.t.sol --via-ir -vv
   sed -i '' 's|https://ethereum-rpc.publicnode.com|http://108.53.61.201:8550|' test/<file>.t.sol
   ```
   For Monad: `https://rpc.monad.xyz` is public and works.
2. Test pattern (`ProdSv4EMode44Integration.t.sol`):
   - `setUp()` reads `all.json`, extracts `merkle_root`, sets it via `verifier.setMerkleRoot` pranked as admin
   - `_exec(target, value, calldata, proofIndex)` wraps `ICallModule.call(...)` with `_payload(idx)` — grabs verificationData + proof from JSON
   - Fund subvault via `deal(token, subvault4, amount)`; `vm.deal(subvault, x ether)` for native
3. Test every index the new JSON introduces. Update the index-map comment at the top of the file.
4. FFI tests (NTT bridge) require `ffi=true` in foundry.toml and curl+jq on PATH — they hit the Wormhole executor API for signed quotes.

### Public-RPC gotchas
- Aave supply caps may be hit (e.g. sUSDe, PT-srUSDe, WETH). Tests check for caps with try/catch or skip supplies when hitting them.
- Tenderly/Safe simulation and private fork state differ from public RPC — if a test fails on public RPC but passes on private, it's usually mainnet state (frozen reserves, WETH pause, etc.), not the proof.

---

## F. Build calldata for Safe execution

Solidity's `abi.encodeCall` is the reliable way (not `cast`, which can get struct types wrong — e.g. `FeeArgs.dbps` is `uint16`, selector is `0x924105c3` for the NTT transfer). Pattern:

```solidity
// test/NTTEncodeTest.t.sol (throwaway)
contract T is Test {
    function test_Print() public pure {
        bytes memory cd = abi.encodeCall(INttManagerWithExecutor.transfer, (...));
        console.logBytes(cd);
    }
}
```

Run with `forge test --match-test test_Print --match-path test/NTTEncodeTest.t.sol --via-ir -vv`, then delete the test file.

### Safe tx format (structured — if Safe UI handles nested structs)
- `to` = subvault
- `value` = 0 (MON/ETH comes from subvault's own balance)
- `data` = `call(target, value, callData, payload)` (Safe UI encodes)
- `payload.verificationType = 3` (CUSTOM_VERIFIER; **enum index is 3, not 2** — common mistake)
- `payload.verificationData` = exact hex from JSON (watch for copy-paste truncation — SV4/SV0 NTT bridge verificationData is 1120 bytes)
- `payload.proof` = array of 6+ bytes32 hashes

### Safe tx format (pre-encoded)
If the Safe UI struggles with structs, encode `Subvault.call(...)` as raw bytes yourself and submit with `value: 0`, `data: <that blob>`. Avoids all Safe encoding ambiguity.

### NTT bridge specifics (Monad → Ethereum)
- Fresh signed quote (~15 min TTL):
  ```bash
  curl -s -X POST "https://executor.labsapis.com/v0/quote" \
    -H "Content-Type: application/json" \
    -d '{"srcChain":48,"dstChain":2,"relayInstructions":"0x01000000000000000000000000000f424000000000000000000000000000000000"}'
  ```
- Call `value` = `estimatedCost + 0.01 ether` buffer (for Axelar delivery price, ~65535 wei)
- Rate limit: bridging >10 WETH in one tx can exceed NTT outbound capacity — split into chunks
- `INttManagerWithExecutor.transfer` interface at `scripts/common/interfaces/INttManagerWithExecutor.sol`, selector `0x924105c3`

### Common hasRole check
`verifier.verifyCall` calls `vault().hasRole(CALLER_ROLE, who)` where `CALLER_ROLE = keccak256("permissions.Verifier.CALLER_ROLE")` = `0x877766a829235d063c3ba37802a4874fcf1b575d310fbe898df17d8ebabee463`. `who` is `msg.sender` to `Subvault.call`. For the Safe flow that means the Safe itself must hold CALLER_ROLE (prodCurator Safes do).

---

## G. Common repo commands

```bash
# Build
forge build --via-ir

# Run all SV4 tests
forge test --match-path test/ProdSv4EMode44Integration.t.sol --via-ir

# Run all Monad SV0 tests
forge test --match-path test/MonadSv0Integration.t.sol --via-ir

# Single test with logs
forge test --match-test test_ProdSv4_SparkEMode0Operations --via-ir -vv

# Inspect a merged all.json
python3 -c "import json; d=json.load(open('scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv4:all.json')); print(d['merkle_root'], len(d['merkle_proofs']))"
```

---

## H. Notes / gotchas

- **Solc version warning** (IDE flags `pragma 0.8.25` as incompatible with local 0.8.34) — Forge uses the correct version; ignore the IDE diagnostic.
- **`merge_metadata`** top-level field was added to `merge_jsons_new.py` — versioning provenance. Don't strip it; tests don't read it.
- **Bitmask verifier** (`BitmaskVerifier.sol`): `verificationData = abi.encode(verifier_address, bytes32 hash, bytes bitmask)`. Bitmask layout is `who(32) + where(32) + value(32) + data(N)`. Length must be exactly `data.length + 96`.
- **Fork state mutations** (`vm.deal`, `deal`, `vm.prank`) don't persist between tests.
- **apxUSD, PT-apxUSD-17JUN2026, PT-srUSDe-01APR2026** were added to `Constants.sol` and `prod-sv4-pendle.json` but the SV4 JSONs haven't been regenerated yet. Regenerate + remerge when ready to ship those.
- Current SV4 merkle root on-chain: _check_ `verifier4.merkleRoot()` before any rotation PR.
