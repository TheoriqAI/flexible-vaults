# Flexible Vaults — Claude Quick Reference

This is a Mellow tqETH flexible-vaults fork. Work centers on generating merkle-root-gated permission JSONs, merging them into one `all.json` per subvault, validating on mainnet forks, then rotating the on-chain root.

> **Repo root:** `/Users/jpickett713/theoriq/flexible-vaults` (use this in every `cd`/path — older docs referenced a `chainML/forks` path that no longer applies).

> ⛔ **BEFORE changing any permission JSON, read [`PERMISSION_GUARDRAILS.md`](PERMISSION_GUARDRAILS.md).** Permission changes are **additive by default** — never remove/narrow an allowed asset or op unless the user explicitly names it. Config/eMode switches are NOT a reason to drop leaves. wstETH + WETH must always stay as Aave/Spark collateral (ETH vault).

---

## 0. Mental model — how a permission becomes a merkle leaf

This is the single most important thing to understand. Everything else is plumbing around it.

```
 Constants.sol (addresses)                 scripts/configs/*.json (strategies/toggles)
            │                                              │
            ▼                                              ▼
 Generate*JSON.s.sol  ──calls──►  scripts/common/protocols/<Protocol>Library.sol
            │                                  │
            │   for each allowed op:           │  builds a VerificationPayload via
            │                                  │  ProofLibrary.makeVerificationPayload(...)
            ▼                                  ▼
   ProofLibrary.generateMerkleProofs(leaves)  ──►  (merkle_root, per-leaf proofs)
            │
            ▼
   JsonLibrary.toJson(...)  ──►  scripts/jsons/<title>.json   (per-protocol file)
            │
            ▼
   merge_jsons_new.py  ──►  scripts/jsons/<title>:all.json   (one root over all ops)
            │
            ▼
   verifier.setMerkleRoot(root)   (on-chain rotation, by admin/timelock)
            │
            ▼
   At call time: Subvault.call → CallModule → Verifier.verifyCall → BitmaskVerifier.verifyCall
```

### The leaf

Every allowed operation is one **leaf**. A leaf is an `IVerifier.VerificationPayload`:

```solidity
struct VerificationPayload {
    VerificationType verificationType; // we always use CUSTOM_VERIFIER (=3)
    bytes verificationData;            // abi.encodePacked(bytes32(bitmaskVerifierAddr), abi.encode(hash, bitmask))
    bytes32[] proof;                   // merkle proof, filled in by generateMerkleProofs
}
```

`VerificationType` enum (exact integer values — `src/interfaces/permissions/IVerifier.sol`):

| Value | Name | Meaning |
|-------|------|---------|
| 0 | `ONCHAIN_COMPACT` | (who, where, selector) in an on-chain allowlist set |
| 1 | `MERKLE_COMPACT` | merkle proof of `keccak256(abi.encode(who, where, selector))` |
| 2 | `MERKLE_EXTENDED` | merkle proof of `keccak256(abi.encode(who, where, value, data))` |
| 3 | `CUSTOM_VERIFIER` | delegate to an `ICustomVerifier` (we use `BitmaskVerifier`) |

**All of our generated leaves are type 3.** For Safe execution `payload.verificationType = 3` (common mistake: people put 2).

### The BitmaskVerifier (`src/permissions/BitmaskVerifier.sol`)

A leaf doesn't pin an exact calldata — it pins a **masked** calldata, so "any amount / any deadline" can be allowed while the function, target, caller, and key addresses are fixed.

`calculateHash(bitmask, who, where, value, data)` folds a keccak chain over:
- `bitmask[0:32]` & `who`  (caller)
- `bitmask[32:64]` & `where` (target contract)
- `bitmask[64:96]` & `value` (ETH sent)
- `bitmask[96:]` & each byte of `data` (calldata, byte-by-byte)

So `verificationData = abi.encode(expectedHash, bitmask)` (then prefixed with the verifier address — see below). At call time `verifyCall` recomputes the masked hash from the *actual* call and requires it to equal `expectedHash`. **Invariant: `bitmask.length == data.length + 0x60` (96).** If not, it returns false.

Bitmask field layout = `who(32) + where(32) + value(32) + data(N)`. A field set to all-`0xff` means "must match exactly"; all-`0x00` means "wildcard / any".

`ProofLibrary.makeBitmask(who, where, value, selector, callData)` builds the mask: the four bools force-match who/where/value/selector; the rest of `callData`'s mask bytes are whatever you passed (generators pass `type(uint160).max` / `0` sentinels in the encoded args to mark which args are pinned vs. wildcarded).

### The verificationData wrapper

`ProofLibrary.makeVerificationPayload` (`scripts/common/ProofLibrary.sol`) produces:

```solidity
hash_ = bitmaskVerifier.calculateHash(bitmask, who, where, value, data);
payload.verificationType = CUSTOM_VERIFIER;
payload.verificationData = abi.encodePacked(
    bytes32(uint256(uint160(bitmaskVerifierAddr))),  // first 32 bytes = verifier address
    abi.encode(hash_, bitmask)                       // then (expectedHash, bitmask)
);
```

`Verifier.verifyCall` reads the first 20 bytes of `verificationData` as the custom verifier address, then forwards the rest.

### The leaf hash (must match between Solidity and Python)

```
leaf = keccak256( bytes.concat( keccak256( abi.encode(uint8 verificationType, keccak256(verificationData)) ) ) )
```

- Solidity: `ProofLibrary.generateMerkleProofs` (`scripts/common/ProofLibrary.sol:81-83`)
- Python: `hash_leaf_solidity` (`scripts/merge_jsons_new.py:49-72`)

Tree: leaves are **sorted**, combined with `Hashes.commutativeKeccak256` (sorts each pair before hashing), root at tree index 0. Both implementations agree byte-for-byte — that's why the Python merge produces a root the Solidity verifier accepts. **The root changes on every merge** because the tree is fully regenerated.

### JSON shape (`JsonLibrary.toJson`)

```jsonc
{
  "title": "ethereum:tqETH:prod:sv4:all",
  "merkle_root": "0x...",
  "merge_metadata": { ... },          // added by merge_jsons_new.py; tests ignore it
  "merkle_proofs": [
    {
      "verificationType": 3,
      "description": { "description": "...", "abi": ..., "parameters": ..., "innerParameters": ... },
      "verificationData": "0x...",     // verifier addr + (hash, bitmask)
      "proof": ["0x...", ...]
    }
  ]
}
```

Tests read only `merkle_root` and `merkle_proofs[i].verificationData` + `proof`. `description` is human-readable provenance.

---

## A. Vault / Subvault layout

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

### PermissionedChainlinkOracle deployments (SV4 assets — deployed 2026-07-01, Ethereum mainnet, verified)

Deployed via `scripts/ethereum/oracle/DeployPermissionedChainlink.s.sol` (`deploy(uint256 i)`; preview with `preview()`). All: owner = prodCurator `0xcca5BafEa783B0Ed8D11FD6D9F97c155332A16b8`, `decimals=8`, `minAllowedAnswer=0.9e8`, `maxAllowedAnswer=2e8`, `description="USD price of <symbol>"`, `updatePrice(int256)` is owner-only. Contract `src/oracles/PermissionedChainlink.sol` (pragma lowered 0.8.35→0.8.25 to compile). **These are the price sources to wire into the AaveOracle deploy arrays for these 5 assets.**

| Asset | Oracle address | initialAnswer (8dec) | Source |
|-------|----------------|----------------------|--------|
| reUSDe `0xdDC0…CCC5a` | `0x5b430Dfb2DfD72b906C6BfF0b326640090F6AEB4` | `137886000` ($1.37886) | desk-provided (no on-chain price) |
| reUSD `0x5086…70c72` | `0x7De0912436f4081eA6F5F69c0b6a34b64cCf1a38` | `108653000` ($1.08653) | desk-provided (no on-chain price) |
| USD3 `0x056B…5eCc` | `0xd05C96aad89AC7F15ACd06A88CD28EC90f06537E` | `116116600` ($1.161166) | on-chain ERC4626 (→USDC) |
| sUSD3 `0xf689…64a7` | `0x2E55fA1aA757FdeDfa6A2F34B1BDbedFFcac46bA` | `127694353` ($1.276944) | on-chain ERC4626 (→USD3→USDC) |
| sNUSD `0x08EF…E313` | `0xd3C3F2471e1A9408915ee2Dfca6815c1A14f1fF0` | `105863720` ($1.058637) | on-chain ERC4626 (→nUSD) |

**AaveOracle** (`scripts/ethereum/oracle/DeployAaveOracle.s.sol`, deployed 2026-07-01, verified): `0x31F153A68bFbe87061b335A76062E3C1edA923B8`. Wires 7 asset→source pairs: NUSD (idx0, must stay 0), SIERRA (idx1), + the 5 PermissionedChainlink feeds above (reUSDe/reUSD/USD3/sUSD3/sNUSD, idx2–6). addressesProvider `0x2f39…4E9e`, fallback `0x5458…a0C2`, base USD 1e8.

### RPC access (Ethereum) — IAP tunnel, not a public fork

The old private fork `http://108.53.61.201:8550` is **dead**. Ethereum tests and generators reach the prod **`eth-reth` archive node** over an **IAP SSH tunnel** — no public IP whitelist, gated by your Google identity:

```bash
# GCP project exodus-bots, VM eth-reth (us-central1-a). Keep this running in one terminal:
gcloud compute ssh eth-reth --zone us-central1-a --project exodus-bots \
  --tunnel-through-iap -- -N -L 8545:localhost:8545
```

Tests/generators then use `http://localhost:8545` (the default). Two env overrides:
- `ETH_RPC_URL` — point at a different RPC.
- `FORK_BLOCK` — pin a fork block (`0` = chain head, the default). Pin a pre-expiry block (e.g. `25000000`, ~late Apr 2026) to exercise an expired Pendle market's *enter* path on-chain.

`eth-reth` is a full **archive** node, so any historical `FORK_BLOCK` works. Monad public RPC `https://rpc.monad.xyz` works directly (no tunnel). Other GCP eth nodes in `exodus-bots`: `eth-geth`, `eth-nethermind` (RPC is internal-only on port 8545 — reach via the same IAP tunnel pattern; nothing is public).

---

## B. Key directories

```
scripts/
  configs/                    — JSON configs consumed by generators via vm.parseJson
    prod-sv4-pendle.json        (GeneratePendleJSON.generateFromConfig)
    prod-sv4-withdrawals.json   (GenerateEnterExitJSON.generateFromConfig)
    prod-sv3-withdrawals.json, prod-sv2-withdrawals.json
    preprod-* variants
  common/
    Permissions.sol           — all role hashes (CALLER_ROLE, SWAP_MODULE_*_ROLE, SET_MERKLE_ROOT_ROLE, ...)
    ProofLibrary.sol          — makeBitmask, makeVerificationPayload, generateMerkleProofs, storeProofs
    JsonLibrary.sol           — toJson(...) → the on-disk JSON shape
    ParameterLibrary.sol      — builds the human-readable "description" parameter maps
    ABILibrary.sol            — selector → ABI string for descriptions
    protocols/                — one library per protocol (see §E table)
    interfaces/               — IMorpho, IAavePoolV3, INttManagerWithExecutor, IEulerVault, IPendleRouter, ...
  ethereum/
    Constants.sol             — all Ethereum addresses (tokens, PT tokens, Pendle markets, Aave, Spark, Morpho)
    Generate*JSON.s.sol       — generators (see §E)
  monad/
    Constants.sol             — Monad addresses (MON, WMON, WETH, WSTETH, USDC, Euler vaults, NTT/CCIP/CCTP)
    Generate*JSON.s.sol, MVT.s.sol, test/monLibrary.sol
  jsons/
    prod/tqETH/               — all PROD JSONs live here (per-protocol + merged all.json for sv3/sv4/monad SV0)
  merge_jsons_new.py          — Solidity-compatible leaf hashing; regenerates root + proofs; emits merge_metadata
  merge_jsons.py              — older variant; prefer merge_jsons_new.py

test/
  ProdSubvaultIntegration.t.sol     — SV3 (Aave + Spark + Morpho savETH + SwapModule + CCIP + NTT)
  ProdSv4EMode44Integration.t.sol   — SV4 full suite
  ProdSv4EMode38Integration.t.sol   — SV4 eMode 38 variant
  MonadSv0Integration.t.sol         — Monad SV0 (Euler, SwapModule, NTT, CCIP, CCTP, Morpho, Merkl)
  ProdSv2Integration.t.sol, TqGLDPreProdSv*Integration.t.sol, LidoWithdrawalTest.t.sol
```

---

## C. Generate a new (or updated) per-protocol JSON

1. **Add constants** to `scripts/ethereum/Constants.sol` (or `scripts/monad/Constants.sol`). Always `cast to-check-sum-address` first.
2. **Pick/extend the generator** (see §E for the real entry-point signatures). For most protocols you call a `generateProdSv<N>...` function; for Pendle/withdrawals you edit the config JSON and call `generateFromConfig`.
3. **Run** against a mainnet fork RPC (subvault addresses are read from the on-chain Vault, so the RPC must actually have the vault deployed):
   ```bash
   forge script scripts/ethereum/GenerateAaveOpsJSON.s.sol \
     --sig "generateProdSv4SparkEMode0(uint8)" 0 \
     --rpc-url http://localhost:8545 --via-ir   # IAP tunnel to eth-reth (see §A); or any ETH RPC
   ```
4. **Move output** from `scripts/jsons/<title>.json` → `scripts/jsons/prod/tqETH/sv4-<name>.json`, and delete any `-lean` companion file.

### Gotchas
- Reverts with "call to non-contract address" if the RPC doesn't have the vault (needs a real Ethereum/Monad RPC).
- USDT `approve` rejects non-zero → non-zero; account for this in tests (drain allowance to 0 before re-approving).
- `-lean` JSONs omit the ABI block in descriptions; they're a byproduct, not used by tests/merge.

---

## D. Merge per-protocol JSONs into `all.json`

```bash
cd /Users/jpickett713/theoriq/flexible-vaults
python3 scripts/merge_jsons_new.py ethereum:tqETH:prod:sv4:all \
  scripts/jsons/prod/tqETH/sv4-aaveOps-emode24.json \
  scripts/jsons/prod/tqETH/sv4-morphoOps.json \
  scripts/jsons/prod/tqETH/sv4-swapModule.json \
  scripts/jsons/prod/tqETH/sv4-pendlePT.json \
  scripts/jsons/prod/tqETH/sv4-pendleLp.json \
  scripts/jsons/prod/tqETH/sv4-withdrawals.json \
  scripts/jsons/prod/tqETH/sv4-cctpBridge-USDC-monad.json \
  scripts/jsons/prod/tqETH/sv4-sparkOps-emode0.json \
  scripts/jsons/prod/tqETH/sv4-nest.json
```

- Output lands in `scripts/jsons/<title>.json` — move it to `scripts/jsons/prod/tqETH/` afterward.
- **Order of input files == order of indices in merged output. Append new files to preserve existing test indices.**
- The script verifies every proof against the regenerated root before writing (`verify_proof`); it raises if any fails.
- Emits `merge_metadata` (UTC + unix timestamp, per-file op counts, source paths). Tests ignore it. Use it to detect drift (a file silently dropped from a merge).

### Current merge orders (order → index ranges in `all.json`)

> Always re-derive these from `merge_metadata.sources` after a merge; the snapshots below are point-in-time.

#### SV4 — **313 ops** (Jun–Jul 2026 expansion), root `0x702414b8216d459f200c74d2e529090f0677e63be958e1a83f623d81507a9c1a`
| Start | Source file | Ops | Contents |
|-------|-------------|-----|----------|
| 0 | `sv4-aaveOps-emode24.json` | 19 | **Aave eMode 24** — collateral **sUSDe (boosted) + wstETH + WETH** (base-param, V3.2 liquid eMode), borrow USDe/USDC/USDT. *Replaced eMode 44 (expired PT-srUSDe coll); wstETH/WETH restored — it's an ETH vault* |
| 19 | `sv4-morphoOps.json` | 112 | **Morpho 14 markets** (3 stables + PT-reUSD-10DEC + USD3 + AA_FalconX + cbBTC + XAUt + wstETH/WBTC/WETH×USDC/USDT). *Removed sUSN + 3 expired PTs* |
| 131 | `sv4-swapModule.json` | 41 | SwapModule 14 assets (added sNUSD/USD3/reUSDe/sUSD3) |
| 172 | `sv4-pendlePT.json` | 58 | Pendle 12 strategies (4 expired→exit-only; live: Sierra-01JUL/06AUG, USDG, nOPAL, reUSDe, USD3, sUSD3, reUSD) |
| 230 | `sv4-pendleLp.json` | 33 | **Pendle LP** (add/remove single-token + 1 reward claim) on 8 live markets — full `0xff` locks |
| 263 | `sv4-withdrawals.json` | 19 | Lido/sUSDe/sNUSD/srUSDe + **USD3 (4) + sUSD3 (5, `startCooldown`)** |
| 282 | `sv4-cctpBridge-USDC-monad.json` | 2 | CCTP USDC → Monad |
| 284 | `sv4-sparkOps-emode0.json` | 19 | Spark eMode 0 |
| 303 | `sv4-nest.json` | 10 | **Nest nOPAL** deposit (predicate proxy, 644-byte leaf) + redeem (USDC+USDT vaults: requestRedeem/redeem/updateRedeem) |

Aave group (19 ops) offsets: `0` setUserEMode(24); `1-3` sUSDe approve/supply/withdraw; `4-6` wstETH; `7-9` WETH; `10-12` USDe approve/borrow/repay; `13-15` USDC; `16-18` USDT.

> Older root snapshots: `0x9c3002…` (307, before wstETH/WETH Aave collateral), `0x1e0613…` (164), `0xdae750…` (165). Always re-derive group starts from `merge_metadata.sources` and **verify `verifier4.merkleRoot()` on-chain before any rotation.**

**Open TODOs / operational notes for this SV4 expansion:**
- **Test suite migrated + green** — full SV4 suite (12/12) passes at head against the 313-op root; run with `--skip PermissionedChainlink --gas-limit 9000000000000000000`.
- **SwapModule roles (mainnet op)** — admin `0x8907D6089fC71AA6a9a7bb9EC5b1170e92489ebf` must `grantRole(TOKEN_IN_ROLE/TOKEN_OUT_ROLE, token)` for sNUSD/USD3/reUSDe/sUSD3 so swaps validate (push/pull work from the root alone). Separate from rotating the root.
- **TODO: fix existing PT-swap masking** — `PendleLibrary._makeSwap*` masks locked addresses with the address value (partial lock) and wildcards `pendleSwap`/`extRouter` (`mask=0`) — the "no external router" lock is *not* enforced (medium-high: a curator could route swap inputs through an arbitrary aggregator). The new `GeneratePendleLpJSON` uses correct full `type(uint160).max` locks; fold the same into `PendleLibrary` and regen `sv4-pendlePT.json`.
- **Large generations need `--gas-limit 9000000000000000000`** — the O(n²) JSON-string builder hits `MemoryOOG` above ~80 ops (Morpho 112, etc.).

#### SV3 — **74 ops**, root `0xdfcf365d967ea0221e7ef44b56fba8aab6ccb84774c1145e605bb2f54141cbe4`
| Indices | Source file | Ops | Contents |
|---------|-------------|-----|----------|
| 0–21 | `sv3-aaveOps-emode1.json` | 22 | Aave eMode 1 |
| 22–43 | `sv3-sparkOps-emode1.json` | 22 | Spark eMode 1 |
| 44–51 | `sv3-morphoOps.json` | 8 | Morpho WETH/savETH market (incl. approvals) |
| 52–69 | `sv3-swapModule.json` | 18 | SwapModule (approve+push+pull per asset) |
| 70–71 | `sv3-ccipBridge-wstETH-monad.json` | 2 | CCIP wstETH → Monad |
| 72–73 | `sv3-nttBridge-WETH-monad.json` | 2 | NTT WETH → Monad |

Note: SV3's Lido withdrawals JSON exists (`ethereum:tqETH:prod:sv3:lidoWithdrawal.json`) but **is not merged** into the current all.json (SV3 all.json predates `merge_metadata`, so its `sources` is empty).

#### Monad SV0 — **68 ops**, root `0x7275f345f55cbe2f8cb73bddc53dc90dac7722a61248a40d06afbada60a14c27`
| Indices | Source file | Ops | Contents |
|---------|-------------|-----|----------|
| 0–25 | `monad:tqMON:prod:sv0:eulerOps.json` | 26 | Euler supply/withdraw/borrow approves (0–16) + EVC collateral/controller enable/disable (17–25) |
| 26–36 | `monad:tqMON:prod:sv0:swapModule.json` | 11 | SwapModule WMON/MON/USDC/WETH push/pull |
| 37–38 | `monad:tqMON:prod:sv0:nttBridge.json` | 2 | NTT approve + transfer |
| 39–40 | `monad:tqMON:prod:sv0:ccipBridge.json` | 2 | CCIP approve + ccipSend |
| 41–42 | `monad:tqMON:prod:sv0:cctpBridge.json` | 2 | CCTP approve + depositForBurn |
| 43–66 | `monad:tqMON:prod:sv0:morphoOps.json` | 24 | Morpho 3 markets (USDC/aHYPER, USDC/syzUSD, USDC/mHYPER) — 8 ops each |
| 67 | `monad:tqMON:prod:sv0:merklClaim.json` | 1 | Merkl toggleOperator |

---

## E. Generator → protocol library → ops map (real entry points)

Every generator builds leaves via a `scripts/common/protocols/<X>Library.sol` `get<X>Proofs(...)` + `get<X>Descriptions(...)` pair, then calls `ProofLibrary.generateMerkleProofs` + `storeProofs`. Run any with `forge script scripts/<chain>/<File>.s.sol --sig "<fn(args)>" <args> --rpc-url <rpc> --via-ir`.

### Ethereum (`scripts/ethereum/`)

| Generator file | Prod entry point(s) | Library | Ops per unit |
|----------------|---------------------|---------|--------------|
| `GenerateAaveOpsJSON.s.sol` | `generateProdSv4AaveEMode44(uint8)` (44), `generateProdSv4SparkEMode0(uint8)` (0), `generateProdSv3Aave(uint8)`, `generateProdSv3Spark(uint8)`, `generateProdSv3AllEMode1()`; low-level `generateWithCustomAssets(...)` | `AaveLibrary` | `1 (setUserEMode) + 3·collaterals + 3·loans + collateralToggles` |
| `GenerateMorphoJSON.s.sol` | `generateProdSv4Morpho()`, `generateProdSv3Morpho()`, `generateProd(uint256)`, `generateFromConfig(string)` | `MorphoLibrary` | `8 per market` (2 approves + supply + supplyCollateral + repay + borrow + withdraw + withdrawCollateral) |
| `GenerateSwapModuleJSON.s.sol` | `generateProdSv4WithSwapModule(address)`, `generateProdSv3WithSwapModule(address)`, `generateProdWithSwapModule(uint256,address)` | `SwapModuleLibrary` | `3 per ERC20 asset` (approve+push+pull), `2 per native` (push+pull) |
| `GeneratePendleJSON.s.sol` | `generateFromConfig(string)` (reads `scripts/configs/prod-sv4-pendle.json`), `generateProdCurator()`, `generateProdCuratorWithIndex(uint256)` | `PendleLibrary` | `2·inputTokens + 1 (PT approve) + 2·outputTokens` per strategy |
| `GenerateEnterExitJSON.s.sol` | `generateFromConfig(string,bool)` (config, isProd), `generateProdLidoWithdrawal(uint256)`, `generateProdCurveSwapsFromConfig(string)` | direct (ERC4626/`sUSDe`/`sNUSD`/Lido/Curve/UniV3) | depends on enabled toggles |
| `GenerateCCTPBridgeJSON.s.sol` | `generateProdSv4USDCToMonad(address targetSubvault)` | `CCTPLibrary` | `2` (approve + depositForBurn) |
| `GenerateCCIPBridgeJSON.s.sol` | `generateProdSv3WstETHToMonad()` | `CCIPLibrary` | `2` (approve + ccipSend) |
| `GenerateNTTBridgeJSON.s.sol` | `generateProdSv3WETHToMonad(address targetSubvault)` | `NTTLibrary` | `2` (approve + transfer) |
| `GenerateAaveOpsJSONCrossChain.s.sol` | `generateEthereum()` / `generateForChain(...)` | `AaveLibrary` + `CCTPLibrary` | CCTP bridge ops for SV4 |
| `GenerateOFTJSON.s.sol`, `GenerateUniswapV3JSON.s.sol`, `GenerateUniswapV4JSON.s.sol`, `GenerateTqGLDJSON.s.sol` | `generateProd()` etc. | `OFTLibrary` / `UniswapV3Library` / `UniswapV4Library` | as noted in each library |

### Monad (`scripts/monad/`)

| Generator file | Prod entry point | Library | Ops |
|----------------|------------------|---------|-----|
| `GenerateEulerJSON.s.sol` | `generateSv0Prod()` | `EulerLibrary` | Euler supply/withdraw/borrow + EVC enable/disable |
| `GenerateSwapModuleJSON.s.sol` | `generateSv0Prod()` | `SwapModuleLibrary` | 3 per ERC20, 2 per native |
| `GenerateMorphoJSON.s.sol` | `generateSv0()` | `MorphoLibrary` | 8 per market |
| `GenerateBridgeJSON.s.sol` | `generateSv0()` (internal `generateNTT`/`generateCCIP`/`generateCCTP`) | `NTTLibrary`/`CCIPLibrary`/`CCTPLibrary` | 2 each |
| `GenerateMerklJSON.s.sol` | `generateSv0()` | — | 1 (toggleOperator) |

### Protocol libraries (`scripts/common/protocols/`)

| Library | Generates |
|---------|-----------|
| `AaveLibrary` | `setUserEMode`, per-collateral approve/supply/withdraw, per-loan approve/borrow/repay, optional `setUserUseReserveAsCollateral` toggles. Spark reuses this — just pass the Spark pool as `aaveInstance`. |
| `MorphoLibrary` | per market: approve collateral, approve loan, supply, supplyCollateral, repay, borrow, withdraw, withdrawCollateral. |
| `PendleLibrary` | per strategy: input approves + `swapExactTokenForPt` per input, PT approve, `swapExactPtForToken` per output, `exitPostExpToToken` per output. |
| `SwapModuleLibrary` | per asset: ERC20 `approve(swapModule)` + `pushAssets` + `pullAssets` (native omits approve). |
| `CCTPLibrary` | USDC approve + `depositForBurn`. |
| `CCIPLibrary` | token approve + `ccipSend`. |
| `NTTLibrary` | token approve + `transfer` (NttManagerWithExecutor, selector `0x924105c3`). |
| `EulerLibrary` | Euler vault deposit/withdraw/borrow/repay + EVC collateral/controller toggles. |
| `ERC4626Library` | approve underlying + deposit/mint/redeem/withdraw. |
| `ERC20Library` | single `approve` per (asset, spender). |
| `OFTLibrary` | optional approve + LayerZero `send`. |
| `CurveLibrary` | approve + `exchange` (used directly in `GenerateEnterExitJSON`). |
| `WethLibrary` | WETH `deposit` (payable) + `withdraw`. |

---

## F. Configs (`scripts/configs/`)

### `prod-sv4-pendle.json` (consumed by `GeneratePendleJSON.generateFromConfig`)

```jsonc
{
  "subvaultIndex": 4,
  "isProd": true,
  "strategies": [
    {
      "ptToken":      "0x...",        // PT token address
      "market":       "0x...",        // Pendle market address
      "inputTokens":  ["0x...", ...], // assets allowed to swap INTO PT (enter)
      "outputTokens": ["0x...", ...], // assets allowed to exit PT TO (exit + post-expiry)
      "description":  "PT-<asset>-<EXPIRY>"
    }
  ]
}
```
Keys read by Solidity: `.subvaultIndex`, `.isProd`, `.strategies[i].{ptToken,market,inputTokens,outputTokens}` (`description` is for humans).
Ops per strategy: `2·inputTokens.length + 1 + 2·outputTokens.length`.

> **Current drift:** this config has **6 strategies** (adds `PT-srUSDe-01APR2026` and `PT-apxUSD-17JUN2026`), but `sv4-pendlePT.json` / `all.json` still encode only the **4** original markets. Regenerate Pendle + re-merge when shipping those (also requires their constants in `Constants.sol`).

### `prod-sv4-withdrawals.json` / `prod-sv3-withdrawals.json` (consumed by `GenerateEnterExitJSON.generateFromConfig(string,bool)`)

```jsonc
{
  "subvaultIndex": 4,
  "outputSuffix": "withdrawals",
  "enableLidoWithdrawal":   true,   // Lido unstETH: wstETH approve + requestWithdrawalsWstETH + claimWithdrawal
  "enableSusdeWithdrawal":  true,   // Ethena sUSDe: cooldownShares + unstake
  "enableSnusdDeposit":     true,   // sNUSD: nUSD approve + deposit + cooldownShares + unstake
  "enableSrusdeWithdraw":   true,   // srUSDe: withdraw post-cooldown
  "curveSwaps": [],
  "pushAssets": [],
  "pullAssets": []
}
```
Keys read: `.subvaultIndex`, `.outputSuffix`, the four `enable*` toggles, `.curveSwaps`, `.pushAssets`, `.pullAssets` (preprod enterExit also reads `.uniV3Swaps`). Each toggle gates which ops get included.

---

## G. Detailed op index maps

### SV4 (165 ops)

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

78-79:    SwapModule ETH       (push, pull — ETH uses value, no approve)  ← 2 ops
80-82:    SwapModule WETH      (approve, push, pull)
83-85:    SwapModule wstETH    (approve, push, pull)
86-88:    SwapModule USDC      (approve, push, pull)
89-91:    SwapModule USDT      (approve, push, pull)
92-94:    SwapModule USDe      (approve, push, pull)
95-97:    SwapModule sUSDe     (approve, push, pull)
98-100:   SwapModule NUSD      (approve, push, pull)
101-103:  SwapModule Sierra    (approve, push, pull)

104-112:  Pendle PT-sUSDe-06MAY2026    (2 input approves, 2 swapTokenForPt, 1 PT approve, 2 swapPtForToken, 2 exitPostExp)
113-123:  Pendle PT-srUSDe-24JUN2026   (3 input approves, 3 swapTokenForPt, 1 PT approve, 2 swapPtForToken, 2 exitPostExp)
124-128:  Pendle PT-sNUSD-03JUN2026    (1 approve, 1 swapTokenForPt, 1 PT approve, 1 swapPtForToken, 1 exitPostExp)
129-133:  Pendle PT-Sierra-01JUL2026   (1 approve, 1 swapTokenForPt, 1 PT approve, 1 swapPtForToken, 1 exitPostExp)

134:      Lido: IERC20(wstETH).approve(LidoWithdrawalQueue)
135:      Lido: requestWithdrawalsWstETH([any], subvault4)
136:      Lido: claimWithdrawal(anyRequestId)
137:      sUSDe.cooldownShares(anyShares)
138:      sUSDe.unstake(subvault4)
139:      IERC20(nUSD).approve(sNUSD)
140:      sNUSD.deposit(anyAssets, subvault4)
141:      sNUSD.cooldownShares(anyShares)
142:      sNUSD.unstake(subvault4)
143:      srUSDe.withdraw(sUSDe, anyAmount, subvault4, subvault4)

144:      CCTP approve USDC → TokenMessengerV2
145:      CCTP depositForBurn (USDC → Monad)

146:      Spark setUserEMode(0)
147-149:  Spark wstETH (approve, supply, withdraw)
150-152:  Spark WETH   (approve, supply, withdraw)
153-155:  Spark USDC   (approve, supply, withdraw)
156-158:  Spark USDT   (approve, supply, withdraw)
159-161:  Spark USDC   (approve, borrow, repay)
162-164:  Spark USDT   (approve, borrow, repay)
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
47:      Morpho supplyCollateral
48:      Morpho repay
49:      Morpho borrow
50:      Morpho withdraw
51:      Morpho withdrawCollateral

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

## H. SwapModule specifics (`src/utils/SwapModule.sol`)

The SwapModule is a separate gated contract; the merkle leaves only authorize the curator to call `approve`/`pushAssets`/`pullAssets` on it. The *swap itself* is gated by AccessControl roles on the module (`Permissions.sol`):

| Role | Constant | Gates |
|------|----------|-------|
| `SWAP_MODULE_TOKEN_IN_ROLE` | `keccak256("utils.SwapModule.TOKEN_IN_ROLE")` | which tokens may be swap input |
| `SWAP_MODULE_TOKEN_OUT_ROLE` | `keccak256("utils.SwapModule.TOKEN_OUT_ROLE")` | which tokens may be swap output |
| `SWAP_MODULE_CALLER_ROLE` | `keccak256("utils.SwapModule.CALLER_ROLE")` | who may invoke the swap |
| `SWAP_MODULE_ROUTER_ROLE` | `keccak256("utils.SwapModule.ROUTER_ROLE")` | allowed routers |
| `SWAP_MODULE_SET_SLIPPAGE_ROLE` | `keccak256("utils.SwapModule.SET_SLIPPAGE_ROLE")` | slippage multiplier config |

At swap time the module checks tokenIn/tokenOut roles, balances, oracle-priced slippage, and deadline. So adding a SwapModule asset to the JSON is *necessary but not sufficient* — the token must also hold the IN/OUT roles on the module.

---

## I0. Group-offset test indices (no more cascading renumbering)

**Problem this solves:** proof indices in `all.json` are global. Insert one op mid-list (e.g. a new withdrawal) and every later op shifts, which used to mean re-numbering almost every test.

**The fix:** tests never hardcode a global index. They address ops as `_g(FILE, offsetWithinGroup)`, where each per-protocol file is a "group". The group's START index is computed at `setUp` from the merged JSON's `merge_metadata.sources` (which lists every source file and its `op_count`, in merge order = index order). So a group's start is just the running sum of earlier groups' `op_count`.

Each integration test contract carries:

```solidity
string constant F_AAVE = "sv4-aaveOps-emode44.json";   // one per group, exact source filename
// ...
mapping(bytes32 => uint256) internal _groupStart;

function _loadGroupOffsets() internal {                 // called at end of setUp()
    uint256 acc = 0;
    uint256 n = vm.parseJsonUint(json, ".merge_metadata.source_count");
    for (uint256 i = 0; i < n; i++) {
        string memory b = string.concat(".merge_metadata.sources[", vm.toString(i), "]");
        string memory fn = vm.parseJsonString(json, string.concat(b, ".filename"));
        _groupStart[keccak256(bytes(fn))] = acc;
        acc += vm.parseJsonUint(json, string.concat(b, ".op_count"));
    }
}

function _g(string memory file, uint256 off) internal view returns (uint256) {
    return _groupStart[keccak256(bytes(file))] + off;   // absolute proof index
}
```

Call sites read `_exec(target, 0, callData, _g(F_WDRAW, 3))` instead of `_exec(..., 137)`.

**Workflow when you change one group** (e.g. add a withdrawal op):
1. Append the op at the **end** of its per-protocol generator/file (append-only keeps existing offsets stable).
2. Re-run `merge_jsons_new.py` (its `merge_metadata.op_count` for that file bumps automatically).
3. In the test: add **one** new offset constant/use for the new op (`_g(F_WDRAW, 10)`), and write its test. **Nothing else changes** — every downstream group's start recomputes itself from the metadata; other groups' offsets are untouched.

Mid-group inserts (not appends) only shift offsets *within that one group* — still localized, never cascading across groups.

**Requirements / gotchas:**
- Group order in the test's `F_*` constants must match the merge command order (= `merge_metadata.sources` order). The filenames are the keys, so they must match the merged source filenames exactly.
- Needs `merge_metadata` present in `all.json` — all three prod `all.json` (sv4/sv3/sv0) now carry it. If you ever hand-edit an `all.json`, keep `merge_metadata.sources` accurate.
- SV3 additionally resolves Aave/Spark ops through `_findProofFor*` finders; those now return `_g(F_AAVE3/F_SPARK3, offset)` too (they were flipped from `pure` to `view` since `_g` reads state).
- Sanity-check after a merge: the Python one-liner in §K can print group starts; they must match what the tests expect.

---

## I. Test against fork

1. Start the IAP tunnel (see §A), then just run forge — Ethereum tests default to `http://localhost:8545` at chain head:
   ```bash
   forge test --match-path test/ProdSv4EMode44Integration.t.sol --via-ir
   # overrides: ETH_RPC_URL=<url>  FORK_BLOCK=<n>  (FORK_BLOCK=0 = head)
   FORK_BLOCK=25000000 forge test --match-path test/ProdSv4EMode44Integration.t.sol --via-ir
   ```
   `setUp()` reads RPC/block from `vm.envOr("ETH_RPC_URL", "http://localhost:8545")` and `vm.envOr("FORK_BLOCK", 0)` — no more sed-swapping the URL. Monad (`MonadSv0Integration.t.sol`) uses `https://rpc.monad.xyz` directly.
2. Test pattern (`ProdSv4EMode44Integration.t.sol`):
   - `setUp()` reads `all.json`, extracts `merkle_root`, sets it via `verifier.setMerkleRoot` pranked as admin, then `_loadGroupOffsets()` (see §I0).
   - `_exec(target, value, calldata, proofIndex)` wraps `ICallModule.call(...)` with `_payload(idx)`.
   - `_assertAuthorized(target, value, data, idx)` checks the merkle proof **without executing** (via `verifier.getVerificationResult`) — use this to prove an op is authorized regardless of market state (expiry/caps/liquidity).
   - Fund subvault via `deal(token, subvault4, amount)`; `vm.deal(subvault, x ether)` for native.
3. **Test every index the new JSON introduces, and update the index-map comment at the top of the file.** Address ops via `_g(FILE, offset)` (see §I0) so a new op only touches its own group; appended ops cost zero edits elsewhere. (The proof array in `all.json` is in input/merge order — index = position; the internal merkle tree is sorted but that's invisible to `merkle_proofs[i]`.)
4. **Pendle / expiry-aware pattern (head-safe):** PT enter swaps (`swapExactTokenForPt`) revert `MarketExpired` once the PT expires, and AMM exits revert post-expiry too — only `exitPostExpToToken` executes. So at head: always `_assertAuthorized(...)` for every Pendle op (proof coverage), execute via `_pendleExec(callData, idx)` which asserts + runs tolerantly (returns bool), and seed PT with `deal(pt, subvault4, ...)` when an enter didn't run so exit paths still execute. To exercise an expired market's enter path on-chain, run with `FORK_BLOCK=25000000`.
5. FFI tests (NTT bridge) need `ffi=true` in `foundry.toml` and `curl`+`jq` on PATH (they hit the Wormhole executor API for signed quotes).

### Fork-state gotchas (head)
- **Expired PT markets** → `MarketExpired()` (selector `0xb2094b59`) on enter/AMM-exit. Expected at head; handle via the expiry-aware pattern above, or pin `FORK_BLOCK` to a pre-expiry block.
- **USDT at head** → subvaults can carry a residual mainnet allowance, and USDT's `approve` rejects non-zero→non-zero **and** returns no bool. Reset via a low-level `approve(0)` fixture before re-approving (see `test_ProdSv4_SparkEMode0Operations`), not a typed `IERC20(USDT).approve` (which reverts on return-decode).
- **Aave/Spark supply caps / frozen reserves** vary by block — a failure at head that passes at an older `FORK_BLOCK` is mainnet state, not a bad proof. Confirm authorization with `_assertAuthorized` / `getVerificationResult`.

---

## J. Build calldata for Safe execution

Use Solidity's `abi.encodeCall` (not `cast`, which mis-types structs — e.g. `FeeArgs.dbps` is `uint16`; NTT transfer selector is `0x924105c3`):

```solidity
// test/NTTEncodeTest.t.sol (throwaway)
contract T is Test {
    function test_Print() public pure {
        bytes memory cd = abi.encodeCall(INttManagerWithExecutor.transfer, (...));
        console.logBytes(cd);
    }
}
```
Run `forge test --match-test test_Print --match-path test/NTTEncodeTest.t.sol --via-ir -vv`, then delete it.

### Safe tx format (structured)
- `to` = subvault, `value` = 0 (token/ETH comes from the subvault's own balance)
- `data` = `call(target, value, callData, payload)`
- `payload.verificationType = 3` (CUSTOM_VERIFIER — **enum index 3, not 2**)
- `payload.verificationData` = exact hex from JSON (watch truncation — NTT bridge verificationData is 1120 bytes)
- `payload.proof` = the bytes32[] from the JSON

### Safe tx format (pre-encoded)
If the Safe UI struggles with nested structs, encode `Subvault.call(...)` to raw bytes yourself and submit `value: 0`, `data: <blob>`.

### NTT bridge specifics (Monad → Ethereum)
- Fresh signed quote (~15 min TTL):
  ```bash
  curl -s -X POST "https://executor.labsapis.com/v0/quote" \
    -H "Content-Type: application/json" \
    -d '{"srcChain":48,"dstChain":2,"relayInstructions":"0x01000000000000000000000000000f424000000000000000000000000000000000"}'
  ```
- Call `value` = `estimatedCost + 0.01 ether` buffer (Axelar delivery, ~65535 wei).
- Rate limit: >10 WETH in one tx can exceed NTT outbound capacity — split into chunks.
- Interface: `scripts/common/interfaces/INttManagerWithExecutor.sol`, selector `0x924105c3`.

### hasRole check
`Verifier.verifyCall` requires `vault().hasRole(CALLER_ROLE, who)` where `CALLER_ROLE = keccak256("permissions.Verifier.CALLER_ROLE")` = `0x877766a829235d063c3ba37802a4874fcf1b575d310fbe898df17d8ebabee463`, and `who` = `msg.sender` to `Subvault.call`. For the Safe flow the Safe itself must hold `CALLER_ROLE` (prodCurator Safes do).

---

## K. Common repo commands

```bash
# Build
forge build --via-ir

# Run a full subvault suite
forge test --match-path test/ProdSv4EMode44Integration.t.sol --via-ir
forge test --match-path test/MonadSv0Integration.t.sol --via-ir

# Single test with logs
forge test --match-test test_ProdSv4_SparkEMode0Operations --via-ir -vv

# Inspect a merged all.json (root + op count + per-file provenance)
python3 -c "import json; d=json.load(open('scripts/jsons/prod/tqETH/ethereum:tqETH:prod:sv4:all.json')); print(d['merkle_root'], len(d['merkle_proofs'])); print([(s['filename'],s['op_count']) for s in d.get('merge_metadata',{}).get('sources',[])])"

# List real generator entry points in a file
grep -nE 'function generate[A-Za-z0-9_]*\(' scripts/ethereum/GenerateAaveOpsJSON.s.sol
```

---

## L. Notes / gotchas

- **Solc version warning** — IDE flags `pragma 0.8.25` vs local 0.8.34. Forge uses the right version; ignore.
- **`merge_metadata`** is provenance only; don't strip it (tests don't read it). Use it to catch a file dropped from a merge.
- **Bitmask invariant**: `verificationData = abi.encode(verifierAddr, bytes32 hash, bytes bitmask)`; bitmask layout `who(32)+where(32)+value(32)+data(N)`, length must be exactly `data.length + 96`.
- **Re-sorting**: the merkle tree sorts all leaves, so inserting an op mid-list reshuffles indices for every later op. Append-only is the safe pattern; otherwise re-verify all test indices.
- **Fork state mutations** (`vm.deal`, `deal`, `vm.prank`) don't persist between tests.
- **Pending, not yet shipped**: `prod-sv4-pendle.json` carries 6 strategies (apxUSD, srUSDe-01APR) but the merged SV4 JSON only encodes the 4 original Pendle markets. Regenerate Pendle + re-merge to ship.
- **Before any rotation PR**: read `verifier4.merkleRoot()` (and SV3/Monad equivalents) on-chain and diff against the `all.json` you intend to set.
- **AGENTS.md** mirrors this file for Codex; keep the two in sync when editing.
</content>
