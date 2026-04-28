---
name: injective-autosign
description: Set up AuthZ delegation on Injective for session-based auto-trading. Grants a scoped, time-limited permission to an ephemeral key so the AI can place and close perpetual trades without a wallet popup or password prompt for every order. Use authz_grant to enable, authz_revoke to disable. Requires the Injective MCP server to be connected.
license: MIT
metadata:
  author: InjectiveLabs
  version: "1.0.0"
---

# Injective AutoSign Skill

## Overview

AuthZ delegation lets a user grant a scoped, on-chain permission to a secondary key (the "grantee") to execute specific message types on their behalf. This enables session-based trading without password prompts per trade.

**Security model**: The grant is scoped to specific Cosmos message types (trading only — no withdrawals or transfers). It expires automatically. The user can revoke at any time.

## Setup: Grant AuthZ Permission

```
authz_grant
  granterAddress: inj1...     ← your main wallet
  password: ****              ← keystore password (one-time, for signing the grant tx)
  granteeAddress: inj1...     ← ephemeral/session key to grant permission to
  msgTypes:                   ← list of allowed message types
    - MsgCreateDerivativeMarketOrder
    - MsgCreateDerivativeLimitOrder
    - MsgCancelDerivativeOrder
    - MsgBatchUpdateOrders
    - MsgIncreasePositionMargin
  expirySeconds: 86400        ← optional, default 86400 (24h). No chain-enforced max — indefinite grants (e.g. year 2099 = 4_070_908_800) are valid.
```

After this one transaction, the grantee can trade on behalf of the granter for the duration.

## Revoke AuthZ Permission

```
authz_revoke
  granterAddress: inj1...
  password: ****
  granteeAddress: inj1...
  msgTypes:
    - MsgCreateDerivativeMarketOrder
    - MsgCreateDerivativeLimitOrder
    - MsgCancelDerivativeOrder
    - MsgBatchUpdateOrders
    - MsgIncreasePositionMargin
```

Revoke immediately cancels all permissions for the specified message types. Partial revocation (removing specific msg types) is supported.

For browser AutoSign implementations, do not describe clearing local storage, deleting a session key, or disconnecting a wallet as revocation. Those actions only remove the local grantee key. A real revoke must sign and broadcast `MsgRevoke` from the granter wallet for every delegated message type, then clear local session state only after the revoke transaction succeeds.

## Safe Message Types for Trading

Only grant these types — they cover all perpetual trading operations:

| Message Type | What it allows |
|---|---|
| `MsgCreateDerivativeMarketOrder` | Open/close positions via market order |
| `MsgCreateDerivativeLimitOrder` | Place limit orders |
| `MsgCancelDerivativeOrder` | Cancel limit orders |
| `MsgBatchUpdateOrders` | Batch order operations |
| `MsgIncreasePositionMargin` | Add margin to existing position |

**Never grant**: `MsgSend`, `MsgWithdraw`, governance messages, or any transfer-related types.

## Workflow: One-Click Session Trading

1. User grants AuthZ to session key (one wallet confirmation)
2. AI uses session key to trade for duration of grant
3. Grant expires automatically OR user revokes manually

```
# Check existing grants on-chain (via Injective Indexer or explorer)
# injective.network → account → authz tab

# Grant (one-time per session)
authz_grant(granterAddress, password, granteeAddress, msgTypes, expirySeconds: 86400)

# Trade freely during session — no password needed if using grantee key
# ...

# Revoke when done
authz_revoke(granterAddress, password, granteeAddress, msgTypes)
```

## Notes

- AuthZ is an on-chain Cosmos SDK primitive — the grant is recorded on Injective and verifiable by anyone.
- The granter pays gas for the grant and revoke transactions. The grantee pays gas for authorized transactions.
- Injective's fee delegation (if enabled) can cover grantee gas, enabling fully gasless session trading.
- Expiry is an absolute UNIX timestamp in seconds, not a duration. 86400 = 24h from epoch (always already expired); use `nowSec() + duration` for relative TTLs, or a far-future constant like `4_070_908_800` (2099-01-01) for "indefinite".
- Picking a duration: short TTLs (24–72h) suit server-custody apps where rotating the grantee key bounds breach impact. Long/indefinite TTLs are safe in client-custody apps because the user can clear localStorage to effectively revoke; the on-chain grant still lingers but no one holds the key.
- If the grantee key is compromised, revoke immediately — the grant is limited to trading actions only, not withdrawals.

## Browser-Based AutoSign (MetaMask + EIP-712)

When implementing AutoSign in a browser frontend (e.g. `autosign.ts` with `enableAutoSign`):

### evmChainId must come from MetaMask at grant time
The `evmChainId` stored in the AutoSign state must be the **actual MetaMask chain at the moment the grant tx is signed**, NOT a hardcoded value:

```typescript
// ✅ Correct — read from MetaMask
const evmChainId = parseInt(
  await window.ethereum.request({ method: 'eth_chainId' }), 16
)

// ❌ Wrong — hardcoding bypasses MetaMask's chain enforcement
const evmChainId = 2525
```

### Valid chains for AutoSign grants
MetaMask must be on **Ethereum mainnet (1)** or **Injective EVM (2525)** when granting AutoSign.
The same `evmChainId` used during the grant tx MUST be used for all subsequent `broadcastAutoSign` calls.

### SDK version
Pin to exactly `@injectivelabs/sdk-ts: 1.17.8`. Newer versions (1.18+) produce different EIP-712 typed data that Injective mainnet rejects.

### Browser revoke flow
Use the same EIP-712 transaction assembly as the grant flow, but build one `MsgRevoke` per delegated message type:

```typescript
const msgRevokes = msgTypes.map((messageType) =>
  MsgRevoke.fromJSON({
    granter: granterAddress,
    grantee: granteeAddress,
    messageType,
  })
)
```

The `@injectivelabs/sdk-ts` `MsgRevoke.fromJSON` helper expects the field name `messageType`; using `msgTypeUrl` or `msg_type_url` leaves the revoke message type empty. After broadcasting succeeds, delete the local grantee key/session bundle. If broadcasting fails or the user rejects the signature, keep the local session visible so the user can retry the on-chain revoke.

## Where the grantee key lives — two architectures

Once a user signs the `MsgGrant`, the app needs to hold the **grantee private key** somewhere so subsequent `MsgAuthzExec` envelopes can be signed without a wallet popup. There are two real options. Both are valid; pick deliberately based on the app.

### Option A — Client custody (`localStorage` in the browser)

The grantee key never leaves the user's device. The browser signs and broadcasts every `MsgAuthzExec` itself, typically via `MsgBroadcasterWithPk.broadcastWithFeeDelegation`.

| | |
|---|---|
| **Storage** | `localStorage` (per-domain, per-device) |
| **Signing** | In-browser, using the SDK |
| **Broadcast** | Browser → Injective fee-delegation relay (HTTP) |
| **Server role** | Optional — only needed for things the browser can't do (faucet, secret-keyed actions) |

**Pros**
- No server-side custody surface — keys never touch your infrastructure.
- Simpler trust story to communicate ("the key is only on your device").
- No session-persistence layer needed on the server (no JSON file, no DB).
- Clears naturally when the user clears site data.

**Cons**
- Browser must bundle the broadcaster SDK. Measured cost when adding `MsgBroadcasterWithPk` + chain SDK to a frontend that already imported `@injectivelabs/sdk-ts` for read APIs: **+110KB minified, +16KB gzipped**.
- Two open tabs can race the grantee account's `account sequence`. Mitigate with a `BroadcastChannel` lock or by blocking on `simulateTx` retries.
- No server-side observability — can't enforce per-user trade limits, rate limits, or kill switches without a separate signing step.
- Dropped network mid-broadcast = dropped trade; the client loses the request.

**Right when**: the app is consumer-facing, the trust pitch matters, you don't need server-side guardrails, and you're OK with the bundle cost.

### Option B — Server custody (in-memory or persisted)

The browser sends the grantee `privateKeyHex` to the server right after the grant. The server holds it (RAM-only, file-backed JSON, or Redis/DB) and signs `MsgAuthzExec` on every trade request.

| | |
|---|---|
| **Storage** | Server RAM, JSON file (chmod 600), or DB |
| **Signing** | Server-side, using the SDK in Node |
| **Broadcast** | Server → Injective fee-delegation relay |
| **Server role** | Critical — every trade flows through it |

**Pros**
- Frontend bundle stays small (broadcaster + chain SDK live server-side).
- Single place to enforce position caps, rate limits, MEV routing, post-trade hooks.
- Nonce/sequencing is naturally serialized (single broadcaster instance).
- Survives client-side disasters (browser crash mid-broadcast still completes).

**Cons**
- Real custody risk: a server breach reveals every active grantee key. Even though grants are scoped + time-limited, this is a leak surface.
- Need session-persistence to survive restarts (in-memory Maps lose every session on `pm2 restart`).
- "Where's my key?" answer is more complicated to explain to security-conscious users.

**Right when**: the app needs server-side guardrails, the grantee population is small enough that custody is acceptable (e.g. internal/ops tooling), or bundle size on the client is a hard constraint.

### Migration tips

- **Going A → B**: send `privateKeyHex` server-side on `MsgGrant` success; persist it; route trades through a server endpoint. Add `chmod 600` to whatever file holds the key map.
- **Going B → A**: stop sending the key server-side; have the browser sign/broadcast directly. Drop the session-token concept on the server (it's just "is the local key non-expired?" now). Remember to also strip any `requireSession` middleware that was guarding trade endpoints.

### What doesn't change

Either way, the **on-chain AuthZ grant** is identical — same `MsgGrant`, same scoping, same expiration, same revoke path. The choice is purely about who *holds* the grantee key after grant.

## Practical lessons (client-custody)

These show up the first time you build a real client-custody AuthZ app. Worth handling up front.

### Fresh-wallet retry

A `MsgGrant` from a wallet that has never transacted on Injective fails with `account not found` or `insufficient funds` — the chain has no account record yet. The recipe:

1. Catch the error, detect it (`msg.includes('not found')` && account-related, or `insufficient funds`).
2. Hit your faucet endpoint with the granter's `inj1` address — a tiny INJ send is enough to register the account.
3. Sleep ~5s for block inclusion.
4. Retry the grant once. Don't loop indefinitely; if the second attempt fails, surface the original error.

The faucet must run server-side (it holds a private key). This is the one server-side route that survives a "everything client-side" architecture.

### Multi-wallet localStorage keying

Don't store the grantee under a single global key like `app-grantee`. Key it by the granter's `inj1` address:

```ts
// Good
localStorage.setItem('app-grantee', JSON.stringify({
  [granterAddress]: { privateKeyHex, granteeAddress, ... },
  ...
}));

// Bad — surfaces stale key from previous wallet after MetaMask account swap
localStorage.setItem('app-grantee', JSON.stringify(currentGrantee));
```

When the user swaps wallets, `getGrantee(currentInjAddress)` either returns the right key for that wallet or `null` (which forces a fresh grant). Without per-granter keying, the new wallet inherits the old wallet's grantee and trades fail with confusing on-chain mismatch errors.

### `accountsChanged` listener

In a browser app you must listen for MetaMask's `accountsChanged` event and clear the *previous* granter's grantee from localStorage when the wallet swaps. Otherwise a swap leaves stale keys that can resurface on a re-connect.

```ts
ethereum.on('accountsChanged', (accounts) => {
  const newInj = ethToInj(accounts[0]);
  if (newInj !== prevInj) {
    clearGrantee(prevInj);      // wipe the old wallet's grantee
    setActiveWallet(newInj);
  }
});
```

Disconnect should also clear the current wallet's grantee — disconnect and swap are similar threats: the user expects "I'm done with this wallet" to also mean "stop holding its grantee key".

### Indefinite vs short-lived grants

In server-custody apps, short rotating grants (24–72h) make sense as a breach-impact bound. In client-custody apps, the user controls the key — they can clear localStorage at any time and the app loses access. So an "indefinite" grant (year 2099) is actually the better UX: no surprise re-authorize prompts ever, and revocation is a local-storage-clear away.

The on-chain grant lingering after a localStorage-clear is a non-issue: no one holds the key. It's effectively dead. If true on-chain hygiene matters (e.g. for chain explorers showing a clean grants list), wire the disconnect flow to also sign a `MsgRevoke`.
