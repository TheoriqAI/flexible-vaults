# ⛔ Permission Guardrails — READ BEFORE CHANGING ANY PERMISSION JSON

Merkle-gated permissions ARE the vault's security boundary. Removing or narrowing them
silently is dangerous — a dropped leaf means the curator can no longer perform a real,
in-use strategy on live funds. These rules are non-negotiable.

## Rule 0 — Permission changes are ADDITIVE by default

- **Never remove, narrow, or drop an allowed asset or operation unless the user explicitly
  names that specific asset/op for removal.** "Add X", "switch to Y", "update Z" is NOT
  permission to remove anything else.
- Adding a new capability must not delete an existing one as a side effect.
- Append-only is the safe pattern (also keeps test group-offsets stable — see CLAUDE.md §I0).

## Rule 1 — Migrations preserve the full existing asset set

When you regenerate a group for any reason (eMode switch, protocol version bump, market
swap, refactor, "clean up"), the new asset list must be a **superset** of the old one
minus only what the user explicitly asked to drop.

- The ONLY assets you may auto-drop are ones that are **provably dead** (e.g. an expired PT
  whose market has passed expiry). Even then: **call it out explicitly** in your response
  ("dropping PT-srUSDe-25JUN2026, expired") and never bundle it silently.
- Everything else — collaterals, borrows, markets, swap tokens — carries forward verbatim.

## Rule 2 — eMode / config settings are NOT a permission scope

- Aave/Spark **eMode is a per-account runtime setting** (`setUserEMode`), not the set of
  assets you're allowed to touch. Switching eMode is **never** a reason to drop supply/
  borrow leaves for other assets.
- Aave **V3.2 "liquid eMode"**: assets outside the active eMode category remain usable as
  collateral at their **base (non-eMode) risk params**. So being in a stablecoin eMode does
  NOT stop wstETH/WETH from being collateral — keep their leaves.

## Rule 3 — ETH-vault invariant (tqETH)

- **wstETH and WETH must always remain suppliable as collateral on Aave AND Spark.** This is
  an ETH vault; ETH LSTs are core collateral. Do not remove them under any config change.
- (Incident 2026-07: an eMode 44→24 switch silently dropped wstETH/WETH Aave collateral.
  Restored in root `0x702414…`. This file exists because of that.)

## Rule 4 — Diff-and-surface before every regenerate/merge

Before you regenerate a group or re-merge `all.json`, compute and show the user a diff of
the **allowed asset/op set** vs. the currently-shipped JSON:

```bash
# per-group op descriptions (old vs new) — anything in OLD but not NEW is a DROP, flag it
python3 -c "import json,re; d=json.load(open('<file>.json')); [print(re.search(r'\"description\"\s*:\s*\"([^\"]+)\"',json.dumps(p)).group(1)) for p in d['merkle_proofs']]"
```

If any asset/op is **removed** relative to what's live, STOP and get explicit user
confirmation naming that asset before proceeding. Never let a removal reach a merge/rotation
without it being called out in plain language.

## Pre-rotation checklist

- [ ] New asset/op set ⊇ old set, minus only user-named removals (+ flagged expired assets).
- [ ] wstETH + WETH collateral present on Aave and Spark (ETH-vault invariant).
- [ ] Any drop was surfaced to the user in words and explicitly approved.
- [ ] `merge_metadata.sources` op counts re-derived; full test suite green at head.
- [ ] `verifier.merkleRoot()` read on-chain and diffed against the intended new root.
