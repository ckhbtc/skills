---
name: injective-rfq-mm-onboarding
description: One-shot onboarding workflow for becoming a market maker on Injective RFQ. Walks through the four prerequisites — whitelist registration (admin-gated), AuthZ grants on the RFQ contract, USDC + INJ balance prep, and an end-to-end smoke test — in the order they need to happen. Use when the user is setting up an MM bot for the first time, after a wallet rotation, or troubleshooting a "maker not registered" / "authorization not found" rejection. Pulls together `injective-rfq-autosign` + `injective-rfq-quote` + `injective-funding`. Mainnet RFQ contract: `inj12stwq95jet57edcu4a65r48r46s9rzrs938n8k` (takes effect June 3); testnet examples remain available.
license: MIT
metadata:
  author: ck
  version: "1.0.0"
---

# Injective RFQ MM Onboarding Skill

> **Mainnet RFQ contract:** `inj12stwq95jet57edcu4a65r48r46s9rzrs938n8k` (takes effect June 3). Testnet examples below still use testnet endpoints.

## Overview

Stand up a new market-maker wallet on Injective RFQ from zero. Four steps, in strict order — skipping or reordering will produce confusing errors at later steps:

1. **Whitelist registration** (admin-gated) — `register_makers` on the RFQ contract.
2. **AuthZ grants** — `MsgSend` + `MsgPrivilegedExecuteContract` to the contract (see `injective-rfq-autosign`).
3. **Balance prep** — USDC margin in the trading subaccount, INJ for gas.
4. **Smoke test** — round-trip a real RFQ end-to-end before going live.

This skill is the orchestrator. The actual primitives live in:

- `injective-rfq-autosign` — step 2
- `injective-funding` — step 3
- `injective-rfq-quote` — step 4
- `InjectiveLabs/rfq-testing` `scripts/register_makers.py` — step 1

Reference walkthrough: [`https://rfq.inj.so/runbook.html`](https://rfq.inj.so/runbook.html).

Mainnet RFQ contract: `inj12stwq95jet57edcu4a65r48r46s9rzrs938n8k` (takes effect June 3).

## Prerequisites you bring

- An Injective testnet wallet (private key in `TESTNET_MM_PRIVATE_KEY`).
- Admin contact for whitelist registration — you can't self-register.
- Access to a clone of `InjectiveLabs/rfq-testing`.

## Step 1 — Whitelist registration (admin)

The RFQ contract maintains a whitelist of approved makers. An admin runs `register_makers` once per maker address; without it, you should not expect normal request routing, and any quote that reaches settlement will be rejected with `maker not registered`.

```bash
# Admin runs this — you don't:
RFQ_ENV=testnet TESTNET_ADMIN_PRIVATE_KEY=<...> \
  python scripts/register_makers.py --maker inj1<your-address>
```

Verify it landed:

```bash
curl -s "https://testnet.sentry.lcd.injective.network/cosmwasm/wasm/v1/contract/inj1qw7jk82hjvf79tnjykux6zacuh9gl0z0wl3ruk/smart/$(echo -n '{"list_makers":{}}' | base64)" | python3 -m json.tool
```

Your address should appear under `data.makers`.

If you can't reach an admin: rfq.inj.so docs link to the maker-registration flow.

## Step 2 — AuthZ grants

Grant the RFQ contract permission to execute on your behalf. Both grants are mandatory:

```bash
RFQ_ENV=testnet TESTNET_MM_PRIVATE_KEY=<...> \
  python scripts/setup_authz_grants.py
```

Or follow `injective-rfq-autosign` for the full breakdown — `GenericAuthorization`, `expiration: null`, gas heuristics, both `MsgSend` + `MsgPrivilegedExecuteContract`.

Verify on-chain:

```bash
curl -s "https://testnet.sentry.lcd.injective.network/cosmos/authz/v1beta1/grants?granter=inj1<your-address>&grantee=inj1qw7jk82hjvf79tnjykux6zacuh9gl0z0wl3ruk" | python3 -m json.tool
```

Expect two grants, both with `expiration: null`.

## Step 3 — Balance prep

You need:

- **USDC** in the trading subaccount — for posting margin on quotes you fill. Address: `erc20:0x0C382e685bbeeFE5d3d9C29e29E341fEE8E84C5d`. Get it from the testnet faucet.
- **INJ** in the bank — for gas on AuthZ grants and the occasional on-chain settlement.

```bash
# Sanity-check via the account skill or LCD:
curl -s "https://testnet.sentry.lcd.injective.network/cosmos/bank/v1beta1/balances/inj1<your-address>"
```

For mass MM provisioning across many wallets, use `injective-funding`.

## Step 4 — Smoke test

Before going live, run a real RFQ round-trip from your MM key:

1. Run `examples/test_roundtrip.py` from `rfq-testing` with both `TESTNET_RETAIL_PRIVATE_KEY` and `TESTNET_MM_PRIVATE_KEY` set. It opens both TakerStream and MakerStream, sends an RFQ request, has the test MM sign a v2 quote, and waits for the quote ACK.
2. The expected sequence:
   - Retail `request_ack` (rfq_id assigned)
   - Test MM receives request on MakerStream
   - MM signs + sends quote with `sign_mode="v2"`
   - Indexer ACKs the quote (`status="success"`)
   - For settlement coverage, run `examples/test_settlement.py` after the quote round-trip passes.

3. Watch for these specific failure modes:
   - `maker not registered` → step 1 didn't land; re-check whitelist
   - `authorization not found` → step 2 didn't land; re-check grants
   - `insufficient subaccount balance` → step 3; top up USDC
   - `not in canonical decimal form` → your bot is sending non-canonical decimals; see `injective-rfq-quote` `to_canonical(x, tick)`
   - `signature does not match maker address` → you're using v1 (raw JSON) but the indexer expects v2 (EIP-712); use `sign_quote_v2` from `rfq_test.crypto.eip712`

If all four steps pass, you're cleared to point your bot at the same MakerStream URL with the production pricing logic.

## Common onboarding pitfalls

| Symptom | Likely cause | Fix |
|---|---|---|
| MakerStream connects, no requests arrive | Subscribed without `maker_address` header | Pass `maker_address=<your-address>` when constructing `MakerStreamClient` |
| Every quote rejected with `maker not registered` | Step 1 skipped or admin used wrong address | Verify with the `list_makers` query above |
| `authorization not found` at settlement | Step 2 missing one of the two grants | Re-run `setup_authz_grants.py` |
| `must be one of "v1", "v2"` | Wire `sign_mode` empty | Library default is `"v2"`; only fires if you bypassed `MakerStreamClient.send_quote` |
| Quotes accepted at indexer, contract rejects at settle | Wire decimal ≠ signed decimal | Use `to_canonical(x, tick)` for every decimal field |

## What comes after onboarding

- `injective-rfq-quote` — your live MM loop.
- `injective-rfq-conditional-order` — handle the maker side of TP/SL flows (the indexer fires the request; you quote against it like a regular RFQ).
- `injective-derivatives-market-data` — market metadata for pricing logic.
- `injective-positions` — manage positions you've taken via filled quotes.

## See also

- [`injective-rfq-autosign`](../injective-rfq-autosign/) — step 2 standalone.
- [`injective-rfq-quote`](../injective-rfq-quote/) — step 4 + your steady-state loop.
- [`injective-funding`](../injective-funding/) — step 3 at scale (many wallets at once).
- [`injective-rfq-trade`](../injective-rfq-trade/) — the taker side; useful for end-to-end smoke testing.
