# TreasuryFi Protocol

A tokenized U.S. Treasury yield curve exposure protocol built on Ethereum. It combines **ERC-3525** (semi-fungible tokens), **ERC-3643 / T-REX** (compliant identity), and **Chainlink** (oracle + automation) to model interest rate risk on-chain.

> Each token represents exposure to a segment of the Treasury yield curve — not an individual bond, but a position on interest rate risk.

---

## What This Protocol Does

TreasuryFi allows an issuer to mint security-compliant tokens that represent exposure to 4 maturity buckets of the U.S. Treasury yield curve:

| Slot | Maturity Bucket | FRED Series | Meaning                     |
| ---- | --------------- | ----------- | --------------------------- |
| 1    | 2-Year          | DGS2        | Short-term rate exposure    |
| 2    | 5-Year          | DGS5        | Mid-curve exposure          |
| 3    | 10-Year         | DGS10       | Benchmark Treasury exposure |
| 4    | 30-Year         | DGS30       | Long-term rate exposure     |

**The full lifecycle:**

1. **Chainlink Functions** fetches real-time Treasury yields from the [FRED API](https://fred.stlouisfed.org/) (Federal Reserve Economic Data)
2. **Chainlink Automation** triggers the fetch every 24 hours — no manual intervention
3. **BondOracle** stores the latest yield per maturity bucket on-chain
4. **TreasuryBondToken (ERC-3525)** uses the oracle data to:
   - **Price mint/redeem** in USDC at NAV (modified duration model)
   - **Track entry yield** per token for mark-to-market P&L
   - **Accrue yield** over time — holders call `claimYield()` for carry payments
   - **Enforce risk controls** — per-slot supply caps, oracle freshness checks
5. **IdentityRegistry (T-REX / ONCHAINID)** ensures only KYC-verified investors can hold or receive tokens
6. Every transfer checks: is the recipient verified? Is the oracle data fresh? Is the sender frozen?

### Contract Interaction Flow

```
Chainlink Automation (24h trigger)
        │
        ▼
BondFunctionsConsumer ──► Chainlink DON ──► FRED API
        │                                      │
        │              ◄── yield response ─────┘
        ▼
   BondOracle (stores yield per slot)
        │
        ▼
TreasuryBondToken (ERC-3525)
   ├── mint()          → investor pays USDC at NAV, saves entryYield
   ├── transferValue() → requires isVerified(to) + !isStale(slot) + !frozen(from)
   ├── redeem()        → burns value, pays USDC at current NAV
   ├── claimYield()    → pays accrued carry in USDC (yield × time held)
   ├── getNAV(tokenId) → modified duration model: par × [1 - D × (y_now - y_entry)]
   └── freeze/unfreeze/forcedTransfer → admin controls
        │
        ▼
IdentityRegistry (T-REX)
   └── isVerified(wallet) → checks Identity contract has valid KYC claim
        │
        ▼
ClaimIssuer (ONCHAINID)
   └── signed KYC claims stored on each investor's Identity contract
```

---

## Smart Contracts Structure

```
src/
├── automation/
│   └── BondAutomation.sol           # Chainlink Automation: triggers 24h yield update
│
├── interfaces/
│   └── IBondOracle.sol              # Interface for BondOracle (used by token)
│
├── oracles/
│   ├── BondOracle.sol               # On-chain yield storage (pure storage, no Chainlink dep)
│   └── BondFunctionsConsumer.sol    # Chainlink Functions client: FRED API → BondOracle
│
└── tokens/
    └── TreasuryBondToken.sol        # ERC-3525 token with T-REX compliance hooks
```

---

## Tech Stack

| Layer                 | Tool                                                                    |
| --------------------- | ----------------------------------------------------------------------- |
| Smart Contracts       | Foundry (Solidity 0.8.34)                                               |
| Semi-Fungible Token   | ERC-3525 — Solv Protocol reference implementation                       |
| Compliance / Identity | ERC-3643 — T-REX Protocol (Tokeny) + ONCHAINID                          |
| Oracle                | Chainlink Functions (Sepolia)                                           |
| Automation            | Chainlink Automation (Sepolia)                                          |
| Data Source           | FRED API (Federal Reserve) — free, no API key required for basic access |
| Testnet               | Sepolia                                                                 |

---

## Design Decisions

### Bond Model: Yield Curve Exposure, Not Individual Bonds

This protocol does **not** model individual bond instruments (specific CUSIP, coupon, price). Instead, it models **exposure to the yield curve** using 4 maturity buckets.

**Why this choice:**

1. **Data availability.** The FRED API provides one yield per maturity bucket (DGS2, DGS5, DGS10, DGS30). It does not provide per-issuance data (CUSIP-level pricing, individual coupons). To price individual bonds you would need Bloomberg, Refinitiv, or TreasuryDirect — all of which are either paid or not suitable for on-chain oracle pipelines.

2. **Financial modeling level.** There are two valid abstraction levels for fixed income on-chain:
   - **Level 1 — Bond Pricing:** model each bond as a unique instrument with its own ISIN, coupon, price, and yield-to-maturity. This is the microstructure approach.
   - **Level 2 — Risk Modeling:** model exposure to interest rate risk factors (duration, curve segments). This is how institutional risk systems work.

   This protocol operates at **Level 2**. Each ERC-3525 slot represents sensitivity to a segment of the Treasury curve, not a specific issuance.

3. **ERC-3525 slot/value model.** In ERC-3525, tokens in the same slot are fungible (you can `transferValue` between them). This maps naturally to yield curve exposure: all "10Y exposure" is fungible, regardless of when it was minted. If we modeled individual bonds, every issuance would need a separate slot, and fungibility within a maturity class would be lost.

4. **Simplicity and composability.** 4 fixed slots keep the system simple, gas-efficient, and easy to integrate with DeFi protocols that want to use Treasury exposure as collateral or in yield strategies.

> **Interview-grade explanation:** "The system abstracts individual bond instruments into maturity-based risk buckets. Each ERC-3525 slot represents exposure to a segment of the Treasury yield curve rather than a specific issuance, allowing the protocol to model interest rate risk instead of bond-level microstructure."

For the full financial rationale, see [`bondstructure.md`](bondstructure.md).

---

### Financial Model: NAV, Yield Accrual, and USDC Settlement

The protocol has three financial mechanics that make it more than a demo:

#### NAV — Modified Duration Model

Each token stores the yield at the time it was minted (`entryYield`). The NAV moves based on how the market yield has changed since then, weighted by the maturity bucket's modified duration:

$$NAV = par \times \left[1 - D_{mod} \times (y_{current} - y_{entry})\right]$$

Where:

- $par = 10000$ (100.00 in basis points)
- $D_{mod}$ = modified duration of the bucket
- $y_{current}$ = current yield from oracle (BPS)
- $y_{entry}$ = yield at mint time (BPS)

| Slot | Maturity | $D_{mod}$ | Yield +50bps → NAV change |
| ---- | -------- | --------- | ------------------------- |
| 1    | 2Y       | 1.9       | -0.95%                    |
| 2    | 5Y       | 4.5       | -2.25%                    |
| 3    | 10Y      | 8.7       | -4.35%                    |
| 4    | 30Y      | 19.5      | -9.75%                    |

**Example:** Investor mints 10Y exposure when yield = 4.00%. Later yield rises to 4.50%:

```
NAV = 10000 × [1 - 8.7 × (0.0450 - 0.0400)] = 10000 × [1 - 0.0435] = 9565
→ Token lost 4.35% in value (realistic for a 10Y Treasury)
```

#### Yield Accrual — `claimYield()`

Holders earn carry (annual yield) pro-rata over time:

$$accrued = value \times \frac{yield}{10000} \times \frac{elapsed}{365\ days}$$

The yield used is the **current oracle yield** at the time of claiming. This simulates a floating-rate carry on the position.

#### USDC Settlement — Mint and Redeem

| Operation                | Price                    | Flow                |
| ------------------------ | ------------------------ | ------------------- |
| `mint(to, slot, value)`  | `value × NAV / par` USDC | Investor → Treasury |
| `redeem(tokenId, value)` | `value × NAV / par` USDC | Treasury → Investor |

For new mints, `entryYield = currentYield`, so NAV = par, and cost = face value. For redeems, NAV reflects yield changes since mint.

#### Risk Controls

| Control             | Implementation                                                     |
| ------------------- | ------------------------------------------------------------------ |
| Max supply per slot | `maxSupplyPerSlot[slot]` — caps total exposure per maturity bucket |
| Frozen wallets      | `frozenWallets[addr]` — blocks transfers from frozen addresses     |
| Oracle freshness    | `isStale(slot)` — blocks operations if data > 72 hours old         |

> **Note on backing:** This protocol does not hold real Treasury securities. It is a **synthetic exposure protocol** — the NAV tracks yield curve movements but there is no Proof of Reserve. In a production system, a custodian (SPV or trust) would hold actual Treasuries, and a Chainlink Proof of Reserve oracle would attest the backing on-chain.

---

### T-REX: Simplified Compliance Without Factory Infrastructure

The T-REX protocol (ERC-3643) provides a complete enterprise-grade infrastructure for deploying compliant security tokens, including:

- `TREXFactory` — deploys an entire suite of contracts in one call via CREATE2
- `TREXImplementationAuthority` — manages implementation versions for proxy upgrades
- `IAFactory` — deploys new ImplementationAuthority instances
- `ModularCompliance` — plugin-based compliance modules (country restrictions, investor caps, etc.)
- Full proxy architecture for upgradeability

**This protocol uses T-REX's identity layer but not its factory/proxy infrastructure.**

**What we use:**
| Component | Source | Purpose |
|-----------|--------|---------|
| `IdentityRegistry` | T-REX | Maps wallet → Identity, exposes `isVerified()` |
| `IdentityRegistryStorage` | T-REX | Separate storage for the registry |
| `ClaimTopicsRegistry` | T-REX | Defines required claim topics (KYC = topic 1) |
| `TrustedIssuersRegistry` | T-REX | Defines which ClaimIssuers are trusted |
| `Identity` | ONCHAINID | Per-investor identity contract holding claims |
| `ClaimIssuer` | ONCHAINID | Signs and issues KYC claims |

**What we don't use and why:**
| Component | Reason for exclusion |
|-----------|---------------------|
| `TREXFactory` | Enterprise deploy infrastructure — adds complexity without demonstrating RWA understanding |
| `TREXImplementationAuthority` | Proxy versioning system — not needed for a non-upgradeable deployment |
| `IAFactory` | Factory for ImplementationAuthority — same as above |
| `IdFactory` | ONCHAINID factory for Identity contracts — we deploy Identity contracts directly |
| `ModularCompliance` | Plugin modules (country, investor cap) — compliance is enforced directly in `_beforeValueTransfer()` |
| `Token.sol` (T-REX) | T-REX's own ERC-20 token — we use ERC-3525 instead, with T-REX as external compliance check |
| Proxy architecture | All contracts deployed as implementations, not proxies — simplifies the system for a portfolio project |

**How compliance works without ModularCompliance:**

Instead of T-REX's modular plugin system, compliance rules are enforced directly inside `TreasuryBondToken._beforeValueTransfer()`:

```solidity
function _beforeValueTransfer(
    address from, address to,
    uint256, uint256, uint256 slot, uint256
) internal override {
    if (from == address(0)) return; // skip on mint
    require(identityRegistry.isVerified(to), "Recipient not KYC verified");
    require(!bondOracle.isStale(slot), "Oracle data stale");
    require(!frozenWallets[from], "Sender wallet is frozen");
}
```

This is simpler, more readable, and demonstrates the same security token concept: **every transfer is gated by on-chain KYC verification**.

---

### Oracle Architecture: Two Contracts, Separation of Concerns

The oracle layer is split into two contracts:

| Contract                | Role                                                | Chainlink dependency? |
| ----------------------- | --------------------------------------------------- | --------------------- |
| `BondOracle`            | Stores yields, exposes `getYield()` and `isStale()` | ❌ None               |
| `BondFunctionsConsumer` | Calls Chainlink Functions, writes to BondOracle     | ✅ FunctionsClient    |

**Why separate them:**

- `BondOracle` can be tested in isolation without mocking Chainlink
- `TreasuryBondToken` depends only on `IBondOracle` — it doesn't know or care about Chainlink
- If Chainlink Functions is replaced with another oracle, only `BondFunctionsConsumer` changes
- Clean interface boundary: `IBondOracle` is the only dependency the token needs

---

## Dependencies

| Library                                                                                        | Remapping               | Purpose                                                       |
| ---------------------------------------------------------------------------------------------- | ----------------------- | ------------------------------------------------------------- |
| [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts)                         | `@openzeppelin/`        | Access control (Ownable)                                      |
| [Chainlink Brownie Contracts](https://github.com/smartcontractkit/chainlink-brownie-contracts) | `@chainlink/`           | FunctionsClient, ConfirmedOwner, AutomationCompatible         |
| [T-REX](https://github.com/TokenySolutions/T-REX)                                              | `@t-rex/`               | IdentityRegistry, ClaimTopicsRegistry, TrustedIssuersRegistry |
| [ONCHAINID](https://github.com/onchain-id/solidity)                                            | `@onchain-id/solidity/` | Identity, ClaimIssuer                                         |
| [ERC-3525](https://github.com/solv-finance/erc-3525)                                           | `@erc3525/`             | ERC3525 base contract                                         |
| [Forge Std](https://github.com/foundry-rs/forge-std)                                           | `forge-std/`            | Test utilities                                                |

---

## Getting Started

```bash
# Clone
git clone https://github.com/<your-username>/TreasuryFi-Protocol.git
cd TreasuryFi-Protocol

# Install dependencies
forge install

# Build
forge build

# Test
forge test
```

---

## License

MIT
