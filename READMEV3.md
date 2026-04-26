# TreasuryFi Protocol

A tokenized U.S. Treasury yield curve exposure protocol built on Ethereum. It combines **ERC-3525** (semi-fungible tokens), **ERC-3643 / T-REX** (compliant identity), **Chainlink** (oracle + automation), and a **Proof of Reserve** model to bring realistic RWA backing on-chain.

> Each token represents shares in a rolling pool of T-Bills exposed to a segment of the Treasury yield curve — not an individual bond, not a specific issuance, but a position on interest rate risk, backed by a simulated off-chain custodian attested via a Proof of Reserve oracle.

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

1. **Chainlink Functions** fetches real-time Treasury yields from the [FRED API](https://fred.stlouisfed.org/)
2. **Chainlink Automation** triggers the fetch every 24 hours — no manual intervention
3. **BondOracle** stores the latest yield per maturity bucket on-chain
4. **ReserveOracle** attests the USD value of T-Bills held by the off-chain custodian (SPV)
5. **TreasuryBondToken (ERC-3525)** uses both oracles to:
   - **Gate minting** — `mint()` checks `ReserveOracle` to ensure reserves cover total supply before issuance
   - **Price mint/redeem** in USDC at NAV (modified duration model)
   - **Collect protocol fees** — mint fee, management fee on yield, early redemption fee
   - **Track mint timestamp** per token for lock period enforcement
   - **Accrue yield** over time — holders call `claimYield()` for carry payments net of protocol fee
   - **Enforce risk controls** — per-slot supply caps, oracle freshness checks, lock period gate
6. **IdentityRegistry (T-REX / ONCHAINID)** ensures only KYC-verified investors can hold or receive tokens
7. Every transfer checks: is the recipient verified? Is the oracle data fresh? Is the sender frozen?

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
        │         Off-chain Custodian / SPV
        │         (rolling pool of T-Bills per maturity bucket)
        │                    │
        │                    ▼ (attests reserve balance)
        │         ReserveOracle (mock PoR on testnet)
        │         [production: Chainlink PoR AggregatorV3Interface]
        │                    │
        ▼                    ▼
TreasuryBondToken (ERC-3525)
   ├── mint()          → checks ReserveOracle (PoR gate) + isVerified(to) + collects mint fee in USDC
   ├── transferFrom()  → creates new tokenId inheriting mintedAt from source token
   ├── redeem()        → burns value, pays USDC at NAV minus early redemption fee (if within lock period)
   ├── claimYield()    → pays accrued carry in USDC net of management fee
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
│   ├── IBondOracle.sol              # Interface for BondOracle (used by token)
│   └── IReserveOracle.sol           # Interface for ReserveOracle (used by token)
│
├── oracles/
│   ├── BondOracle.sol               # On-chain yield storage (pure storage, no Chainlink dep)
│   ├── BondFunctionsConsumer.sol    # Chainlink Functions client: FRED API → BondOracle
│   └── ReserveOracle.sol            # Mock Proof of Reserve: attests custodian reserve balance
│
└── tokens/
    └── TreasuryBondToken.sol        # ERC-3525 token with T-REX compliance + PoR mint gate + fee model
```

---

## Tech Stack

| Layer                 | Tool                                                                    |
| --------------------- | ----------------------------------------------------------------------- |
| Smart Contracts       | Foundry (Solidity 0.8.34)                                               |
| Semi-Fungible Token   | ERC-3525 — Solv Protocol reference implementation                       |
| Compliance / Identity | ERC-3643 — T-REX Protocol (Tokeny) + ONCHAINID                          |
| Yield Oracle          | Chainlink Functions (Sepolia)                                           |
| Reserve Oracle        | Mock Proof of Reserve (testnet) — Chainlink PoR in production           |
| Automation            | Chainlink Automation (Sepolia)                                          |
| Data Source           | FRED API (Federal Reserve)                                              |
| Testnet               | Sepolia                                                                 |

---

## Design Decisions

### Backing Model: Rolling Pool + Proof of Reserve

This is the central architectural decision that differentiates TreasuryFi from a purely synthetic protocol.

#### Each slot is a pool, not an individual bond

Each ERC-3525 slot represents a **rolling pool of T-Bills** with similar duration, managed by the off-chain SPV:

```
Slot 10Y = pool of T-Bills with ~10Y duration
When a T-Bill matures → SPV purchases another ~10Y T-Bill
The pool maintains a constant average duration
→ no individual token has a fixed maturity date
→ the bucket is perpetual by design
```

This is the same model used by Ondo Finance (OUSG) and Backed Finance. There is no 1:1 mapping between a minted token and a specific T-Bill issuance. The SPV manages a portfolio; the protocol manages shares of that portfolio.

#### How real RWA protocols back their tokens

All major tokenized Treasury protocols share the same structural model:

1. Investor deposits fiat or stablecoins
2. A regulated **SPV** purchases T-Bills off-chain
3. A **Proof of Reserve oracle** attests on-chain that the SPV holds sufficient assets
4. The smart contract **blocks new mints** if the reserve attestation shows undercollateralization

```
Investor USDC
      │
      ▼
Smart Contract ──────────────────────────────────────────────┐
      │                                                       │
      │  checks before mint:                                  │
      │  reserveOracle.isReserveSufficient(mintCost)          │
      │                                                       │
      ▼                                                       │
Custodian / SPV (off-chain)                                   │
      │                                                       │
      │  holds rolling pool of T-Bills per maturity bucket   │
      │                                                       │
      ▼                                                       │
ReserveOracle (on-chain) ◄────── custodian pushes balance ───┘
```

#### Implementation on testnet (Sepolia)

| Layer          | Production                               | Testnet (this protocol)                           |
| -------------- | ---------------------------------------- | ------------------------------------------------- |
| Custody        | Regulated SPV holds real T-Bills         | Simulated — no real assets                        |
| Reserve feed   | Chainlink PoR `AggregatorV3Interface`    | `ReserveOracle.sol` (mock updater)                |
| Reserve update | Chainlink node attests custodian wallet  | `custodian` address calls `updateReserves()`      |
| Mint gate      | `require(porFeed.latestAnswer() >= ...)` | `require(reserveOracle.isReserveSufficient(...))` |

---

### Fee Model

The protocol has three distinct fee mechanisms that together make it economically sustainable for the service provider.

#### Economic flow

```
T-Bill gross yield (e.g. 4.50% annual)
        │
        ├── management fee (e.g. 0.50%) → feeCollector
        │
        └── net yield (e.g. 4.00%) → holder via claimYield()

On mint:
        mint fee (e.g. 0.10% of USDC deposited) → feeCollector

On early redemption:
        early redemption fee (e.g. 0.50% of payout) → feeCollector
```

The protocol does not create yield — it **passes through** yield from real T-Bills, retaining a spread. This is identical to how Ondo Finance and other RWA protocols generate revenue.

#### 1. Mint Fee (one-time, on deposit)

Charged at mint time as a percentage of the USDC deposited. Deducted before USDC reaches the treasury.

```solidity
uint256 public constant MINT_FEE_BPS = 10; // 0.10%

uint256 fee = cost * MINT_FEE_BPS / 10000;
paymentToken.transferFrom(to, feeCollector, fee);
paymentToken.transferFrom(to, treasury, cost - fee);
```

#### 2. Management Fee (continuous, on yield)

Deducted from the gross yield at the time of `claimYield()`. The holder receives net yield; the spread goes to `feeCollector`.

```solidity
uint256 public constant MANAGEMENT_FEE_BPS = 50; // 0.50% annual

uint256 grossYield = bondOracle.getYield(slot);
uint256 netYield = grossYield - MANAGEMENT_FEE_BPS;
uint256 accrued = value * netYield * elapsed / (10000 * 365 days);
uint256 feeAccrued = value * MANAGEMENT_FEE_BPS * elapsed / (10000 * 365 days);

paymentToken.transferFrom(treasury, msg.sender, accrued);
paymentToken.transferFrom(treasury, feeCollector, feeAccrued);
```

#### 3. Early Redemption Fee (conditional, on redeem before lock period)

Because each slot is a rolling pool with no fixed maturity, the protocol enforces a **lock period per slot** instead of a maturity date. Redeeming before the lock period expires incurs a penalty fee.

```solidity
// Lock periods per slot
uint256 public constant LOCK_PERIOD_2Y  = 30 days;
uint256 public constant LOCK_PERIOD_5Y  = 90 days;
uint256 public constant LOCK_PERIOD_10Y = 180 days;
uint256 public constant LOCK_PERIOD_30Y = 365 days;

uint256 public constant EARLY_REDEEM_FEE_BPS = 50; // 0.50%

mapping(uint256 tokenId => uint256 mintTimestamp) public mintedAt;

function redeem(uint256 tokenId, uint256 value) external {
    uint256 payout = value * getNAV(tokenId) / PAR_VALUE;
    uint256 elapsed = block.timestamp - mintedAt[tokenId];

    if (elapsed < slotLockPeriod(slotOf(tokenId))) {
        uint256 fee = payout * EARLY_REDEEM_FEE_BPS / 10000;
        payout -= fee;
        paymentToken.transfer(feeCollector, fee);
    }
    // burn and pay out...
}
```

Lock periods are longer for longer-duration buckets, reflecting the illiquidity premium of longer-term fixed income — consistent with TradFi market conventions.

#### mintedAt propagation on transferFrom

When `transferFrom(uint256 fromTokenId, address to, uint256 value)` creates a new derived token, the new token inherits the `mintedAt` of the source token:

```solidity
function transferFrom(
    uint256 fromTokenId_,
    address to_,
    uint256 value_
) public payable override returns (uint256 newTokenId) {
    newTokenId = super.transferFrom(fromTokenId_, to_, value_);
    mintedAt[newTokenId] = mintedAt[fromTokenId_];
}
```

This ensures lock period enforcement is consistent across the full token lifecycle — a recipient cannot reset the lock period by receiving a transfer.

---

### Bond Model: Yield Curve Exposure, Not Individual Bonds

This protocol does **not** model individual bond instruments (specific CUSIP, coupon, price). Instead, it models **exposure to the yield curve** using 4 maturity buckets backed by rolling pools of T-Bills.

**Why this choice:**

1. **Data availability.** FRED API provides one yield per maturity bucket. Per-issuance data requires Bloomberg or Refinitiv — not suitable for on-chain oracle pipelines.
2. **Financial modeling level.** This protocol operates at **Level 2 — Risk Modeling** (yield curve exposure per duration bucket), not Level 1 (individual bond microstructure).
3. **ERC-3525 slot/value model.** Tokens in the same slot are fungible. This maps naturally to pool shares: all "10Y pool shares" are fungible regardless of mint time.
4. **Simplicity and composability.** 4 fixed slots keep the system simple, gas-efficient, and easy to integrate with DeFi protocols.

> **Interview-grade explanation:** "Each ERC-3525 slot represents shares in a rolling pool of T-Bills with similar duration, not a specific issuance. This allows the protocol to model interest rate risk per maturity bucket, preserve fungibility within each slot, and replicate the rolling portfolio model used by institutional RWA protocols like Ondo Finance."

---

### Financial Model: NAV, Yield Accrual, and USDC Settlement

#### NAV — Modified Duration Model

$$NAV = par \times \left[1 - D_{mod} \times (y_{current} - y_{entry})\right]$$

| Slot | Maturity | $D_{mod}$ | Yield +50bps → NAV change |
| ---- | -------- | --------- | ------------------------- |
| 1    | 2Y       | 1.9       | -0.95%                    |
| 2    | 5Y       | 4.5       | -2.25%                    |
| 3    | 10Y      | 8.7       | -4.35%                    |
| 4    | 30Y      | 19.5      | -9.75%                    |

#### Yield Accrual — `claimYield()`

$$accrued = value \times \frac{netYield}{10000} \times \frac{elapsed}{365\ days}$$

Where `netYield = grossYield - MANAGEMENT_FEE_BPS`. The management fee portion accrues to `feeCollector`.

#### USDC Settlement — Mint and Redeem

| Operation                | Price                    | Fee                                          |
| ------------------------ | ------------------------ | -------------------------------------------- |
| `mint(to, slot, value)`  | `value × NAV / par` USDC | Mint fee deducted from deposit               |
| `redeem(tokenId, value)` | `value × NAV / par` USDC | Early redemption fee if within lock period   |

#### Risk Controls

| Control              | Implementation                                                     |
| -------------------- | ------------------------------------------------------------------ |
| Proof of Reserve     | `reserveOracle.isReserveSufficient()` — blocks mint if underbacked |
| Max supply per slot  | `maxSupplyPerSlot[slot]` — caps total exposure per maturity bucket |
| Frozen wallets       | `frozenWallets[addr]` — blocks transfers from frozen addresses     |
| Oracle freshness     | `isStale(slot)` — blocks operations if yield data > 72 hours old   |
| Reserve freshness    | `reserveOracle.isStale()` — blocks mint if PoR data > 24 hours old |
| Lock period          | `mintedAt[tokenId]` — early redemption fee if redeemed too early   |

---

### T-REX: Simplified Compliance Without Factory Infrastructure

**What we use:**

| Component               | Source     | Purpose                                                      |
| ----------------------- | ---------- | ------------------------------------------------------------ |
| `IdentityRegistry`      | T-REX      | Maps wallet → Identity, exposes `isVerified()`               |
| `IdentityRegistryStorage` | T-REX    | Separate storage for the registry                            |
| `ClaimTopicsRegistry`   | T-REX      | Defines required claim topics (KYC = topic 1)                |
| `TrustedIssuersRegistry`| T-REX      | Defines which ClaimIssuers are trusted                       |
| `Identity`              | ONCHAINID  | Per-investor identity contract holding claims                |
| `ClaimIssuer`           | ONCHAINID  | Signs and issues KYC claims                                  |

Compliance is enforced directly in `_beforeValueTransfer()`:

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

---

### Oracle Architecture: Three Contracts, Separation of Concerns

| Contract                | Role                                                               | Chainlink dependency? |
| ----------------------- | ------------------------------------------------------------------ | --------------------- |
| `BondOracle`            | Stores yields, exposes `getYield()` and `isStale()`                | ❌ None               |
| `BondFunctionsConsumer` | Calls Chainlink Functions, writes to BondOracle                    | ✅ FunctionsClient    |
| `ReserveOracle`         | Attests custodian reserve balance, exposes `isReserveSufficient()` | ❌ None (mock)        |

---

## Dependencies

| Library              | Remapping               | Purpose                                                       |
| -------------------- | ----------------------- | ------------------------------------------------------------- |
| OpenZeppelin         | `@openzeppelin/`        | Access control (Ownable)                                      |
| Chainlink            | `@chainlink/`           | FunctionsClient, AutomationCompatible                         |
| T-REX                | `@t-rex/`               | IdentityRegistry, ClaimTopicsRegistry, TrustedIssuersRegistry |
| ONCHAINID            | `@onchain-id/solidity/` | Identity, ClaimIssuer                                         |
| ERC-3525             | `@erc3525/`             | ERC3525 base contract                                         |
| Forge Std            | `forge-std/`            | Test utilities                                                |

---

## Getting Started

```bash
git clone https://github.com/<your-username>/TreasuryFi-Protocol.git
cd TreasuryFi-Protocol
forge install
forge build
forge test
```

---

## Known Limitations

- **No real custody:** `ReserveOracle` is a mock. In production, the reserve feed would come from a Chainlink PoR node attesting a real custodian wallet or SPV.
- **No redemption-side PoR:** the current model gates minting on reserve sufficiency but does not re-check reserves on yield accrual payouts.
- **Floating-rate carry:** `claimYield()` uses the current oracle yield at claim time, not a fixed coupon locked at mint. Real T-Bills have fixed yield to maturity.
- **Lock period as maturity proxy:** the protocol uses slot-level lock periods instead of per-token maturity dates. This is consistent with the rolling pool model but does not replicate the fixed-maturity behavior of individual T-Bills.
- **No Proof of Reserve for yield oracle:** FRED data is fetched via Chainlink Functions DON but without cryptographic proof of data integrity. In production, multiple independent data sources provide this guarantee.

---

## License

MIT
