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
4. **ReservesOracle** attests the USD value of T-Bills held by the off-chain custodian (SPV)
5. **TreasuryBondToken (ERC-3525)** uses both oracles to:
   - **Gate minting** — `openNewPosition()` checks `ReservesOracle` and `RiskManager` to ensure reserves cover total liabilities before issuance
   - **Price mint/redeem** in USDC at NAV (modified duration model)
   - **Collect protocol fees** — entry fee (0.2%), management fee on yield (20%), early redemption fee (up to 5%)
   - **Track mint timestamp** per token for penalty period enforcement
   - **Accrue yield** over time — holders call `claimYield()` for carry payments net of protocol fee
   - **Enforce risk controls** — per-slot reserve buffer, oracle freshness checks, slot freeze on anomalous data, daily redeem limits, redemption windows
6. **IdentityRegistry (T-REX / ONCHAINID)** ensures only KYC-verified investors can hold or receive tokens
7. Every transfer checks: is the recipient verified? Is the oracle data fresh? Is the slot frozen?

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
        │         ReservesOracle (mock PoR on testnet)
        │         [production: Chainlink PoR AggregatorV3Interface]
        │                    │
        ▼                    ▼
TreasuryBondToken (ERC-3525)
   ├── openNewPosition()  → RiskManager reserve check + isVerified(to) + collects entry fee in USDC
   ├── transferFrom()     → creates new tokenId inheriting mintTimestamp from source token, settles yield before split
   ├── closePosition()    → burns value, pays USDC at NAV minus early redemption fee (if within penalty period)
   ├── claimYield()       → pays accrued carry in USDC net of management fee
   └── freeze/unfreeze/forcedTransfer → admin controls (ERC-3643)
        │
        ▼
RiskManager (abstract, inherited by TreasuryBondToken)
   ├── _riskManagerBeforeMint()             → reserve coverage check + liabilities update
   ├── _riskManagerBeforeBurn()             → staleness/freeze check + liabilities update
   ├── _riskManagerBeforeTransferLiquidity() → on-chain liquidity check + rate limit
   ├── updateYieldsValues()                 → validates oracle data, freezes anomalous slots
   └── updateReserveValues()                → validates oracle data, freezes anomalous slots
        │
        ▼
Treasury
   └── holds USDC per slot, handles deposits/withdrawals/fee accounting
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
├── types.sol                           # Shared structs: PositionData, SlotRiskParams, constructor params
│
├── automation/
│   ├── BaseAutomation.sol              # Abstract base: Chainlink Automation with 24h interval + grace period logic
│   ├── BondAutomation.sol              # Chainlink Automation: triggers yield update
│   ├── ReservesAutomation.sol          # Chainlink Automation: triggers reserves update
│   └── UpdateRiskManagerAutomation.sol # Triggers RiskManager cache update on-chain
│
├── interfaces/
│   ├── IBaseAutomation.sol
│   ├── IBondAutomation.sol
│   ├── IBondFunctionsConsumer.sol
│   ├── IBondOracle.sol
│   ├── IERC3525.sol
│   ├── IERC3643.sol
│   ├── IReservesAutomation.sol
│   ├── IReservesFunctionsConsumer.sol
│   ├── IReservesOracle.sol
│   ├── ITreasury.sol
│   ├── ITreasuryBondToken.sol
│   └── IUpdateRiskManagerAutomation.sol
│
├── library/
│   └── YieldsMath.sol                  # NAV and yield accrual math
│
├── oracles/
│   ├── BondOracle.sol                  # On-chain yield storage per slot
│   ├── BondFunctionsConsumer.sol       # Chainlink Functions client: FRED API → BondOracle
│   ├── ReservesOracle.sol              # Mock Proof of Reserve: attests custodian reserve balance
│   └── ReservesFunctionsConsumer.sol   # Chainlink Functions client for reserves
│
└── tokens/
    ├── TreasuryBondToken.sol           # ERC-3525 token: lifecycle, fees, compliance
    ├── RiskManager.sol                 # Abstract: oracle validation, slot freeze, reserve/liquidity checks
    ├── Treasury.sol                    # USDC liquidity management per slot
    ├── UsdcUsdConverter.sol            # USDC/USD conversion via Chainlink price feed
    ├── ERC3525.sol                     # Semi-fungible token base
    ├── ERC3643.sol                     # T-REX compliance base
    └── TokenConstants.sol              # Protocol-wide constants
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
TreasuryBondToken ───────────────────────────────────────────────┐
      │                                                           │
      │  checks before mint (via RiskManager):                    │
      │  - reserve coverage: (liabilities + mintValue) × buffer   │
      │    ≤ bondsValue[slot] + cashBuffer[slot]                   │
      │  - slot not frozen, oracle data not stale                  │
      │                                                           │
      ▼                                                           │
Custodian / SPV (off-chain)                                       │
      │                                                           │
      │  holds rolling pool of T-Bills per maturity bucket        │
      │                                                           │
      ▼                                                           │
ReservesOracle (on-chain) ◄────── custodian pushes balance ───────┘
```

#### Implementation on testnet (Sepolia)

| Layer          | Production                               | Testnet (this protocol)                              |
| -------------- | ---------------------------------------- | ---------------------------------------------------- |
| Custody        | Regulated SPV holds real T-Bills         | Simulated — no real assets                           |
| Reserve feed   | Chainlink PoR `AggregatorV3Interface`    | `ReservesOracle.sol` (mock updater)                  |
| Reserve update | Chainlink node attests custodian wallet  | `custodian` address calls `updateUsdValues()`        |
| Mint gate      | Reserve coverage check via RiskManager   | `RiskManager._validateMintReserves()` with buffer    |

---

### Fee Model

The protocol has three distinct fee mechanisms that together make it economically sustainable for the service provider.

#### Economic flow

```
T-Bill gross yield (e.g. 4.00% annual)
        │
        ├── management fee (20% of gross yield) → feeCollector
        │
        └── net yield (80% of gross yield) → holder via claimYield()

On entry:
        entry fee (0.2% of USDC deposited) → feeCollector

On early redemption (within penalty period):
        early redemption fee (up to 5% of payout, decreasing linearly to 0) → feeCollector
```

The protocol does not create yield — it **passes through** yield from real T-Bills, retaining a spread. This is identical to how Ondo Finance and other RWA protocols generate revenue.

#### 1. Entry Fee (one-time, on deposit)

Charged at `openNewPosition()` time as a percentage of the USDC deposited. Deducted before USDC reaches the treasury.

```solidity
// PERCENTAGE_ENTRY_FEE = 0.2% (2 * PERCENTAGE_PRECISION / 10, in MAX_PERCENTAGE scale)

uint256 feeCollected = (_amount * C.PERCENTAGE_ENTRY_FEE) / C.MAX_PERCENTAGE;
uint256 netAmount    = _amount - feeCollected;
// netAmount goes to Treasury, feeCollected stays in Treasury fee accounting
```

#### 2. Management Fee (continuous, on yield)

Deducted from the gross yield at the time of `claimYield()`. The holder receives net yield; the spread goes to `feeCollector`.

```solidity
// PERCENTAGE_YIELD_FEE = 20% of gross yield

uint256 principalUsd  = YieldsMath.calculatePrincipalUsd(value, positionData.entryNAV, PAR);
uint256 elapsedTime   = block.timestamp - positionData.lastClaimTimestamp;
uint256 grossAccrued  = principalUsd * positionData.entryYield * elapsedTime
                        / (365 days * PERCENTAGE_PRECISION);

uint256 managementFee = grossAccrued * C.PERCENTAGE_YIELD_FEE / C.MAX_PERCENTAGE;
uint256 netPayout     = grossAccrued - managementFee;
// netPayout → holder, managementFee → feeCollector via Treasury
```

#### 3. Early Redemption Fee (conditional, on redeem before penalty period)

Because each slot is a rolling pool with no fixed maturity, the protocol enforces a **penalty period per slot** instead of a maturity date. Redeeming before the penalty period expires incurs a fee that **decreases linearly to zero** as the penalty period elapses.

```solidity
// Penalty periods per slot
uint256 public constant PENALTY_PERIOD_2Y  =  30 days;
uint256 public constant PENALTY_PERIOD_5Y  =  60 days;
uint256 public constant PENALTY_PERIOD_10Y =  90 days;
uint256 public constant PENALTY_PERIOD_30Y = 180 days;

// PERCENTAGE_EXIT_FEE_MAX = 5% (maximum fee, applied at t=0)
// Fee decreases linearly: at t=penaltyPeriod the fee reaches 0

function _calculateEarlyRedeemFee(uint256 _mintTimestamp, uint256 _usdValue, uint256 _slot)
    internal view returns (uint256 feeAmount)
{
    uint256 penaltyPeriod = _getPenaltyPeriod(_slot);
    uint256 elapsedTime   = block.timestamp - _mintTimestamp;

    if (elapsedTime >= penaltyPeriod) return 0; // no fee after penalty period

    uint256 remainingTime      = penaltyPeriod - elapsedTime;
    uint256 currentFeePercentage = (C.PERCENTAGE_EXIT_FEE_MAX * remainingTime) / penaltyPeriod;
    feeAmount = (_usdValue * currentFeePercentage) / C.MAX_PERCENTAGE;
}
```

Penalty periods are longer for longer-duration buckets, reflecting the illiquidity premium of longer-term fixed income — consistent with TradFi market conventions.

#### mintTimestamp propagation on transferFrom

When `transferFrom(uint256 fromTokenId, address to, uint256 value)` creates a new derived token, the new token inherits the `mintTimestamp` of the source token. This is handled inside `_beforeTransfer` → `_beforeValueTransfer`:

```solidity
s_fromIdToPositionData[_toTokenId] = PositionData({
    entryYield:         fromPosData.entryYield,
    entryNAV:           fromPosData.entryNAV,
    mintTimestamp:      fromPosData.mintTimestamp,   // inherited — lock period cannot be reset
    lastClaimTimestamp: block.timestamp              // reset: new token accrues from transfer moment
});
```

Before the split, `_claimYield(fromTokenId)` is called to settle all accrued yield to the sender up to the transfer moment. The new token starts with zero accrued yield.

---

### Bond Model: Yield Curve Exposure, Not Individual Bonds

This protocol does **not** model individual bond instruments (specific CUSIP, coupon, price). Instead, it models **exposure to the yield curve** using 4 maturity buckets backed by rolling pools of T-Bills.

**Why this choice:**

1. **Data availability.** FRED API provides one yield per maturity bucket. Per-issuance data requires Bloomberg or Refinitiv — not suitable for on-chain oracle pipelines.
2. **Financial modeling level.** This protocol operates at **Level 2 — Risk Modeling** (yield curve exposure per duration bucket), not Level 1 (individual bond microstructure).
3. **ERC-3525 slot/value model.** Tokens in the same slot are fungible. This maps naturally to pool shares: all \"10Y pool shares\" are fungible regardless of mint time.
4. **Simplicity and composability.** 4 fixed slots keep the system simple, gas-efficient, and easy to integrate with DeFi protocols.

> **Interview-grade explanation:** \"Each ERC-3525 slot represents shares in a rolling pool of T-Bills with similar duration, not a specific issuance. This allows the protocol to model interest rate risk per maturity bucket, preserve fungibility within each slot, and replicate the rolling portfolio model used by institutional RWA protocols like Ondo Finance.\"

---

### Financial Model: NAV, Yield Accrual, and USDC Settlement

#### NAV — Modified Duration Model

When yields rise the NAV falls; when yields fall the NAV rises:

```
tassi saliti: NAV = PAR × (MAX_PERCENTAGE - D_mod × (y_current - y_entry) / PERCENTAGE_PRECISION) / MAX_PERCENTAGE
tassi scesi:  NAV = PAR × (MAX_PERCENTAGE + D_mod × (y_entry - y_current) / PERCENTAGE_PRECISION) / MAX_PERCENTAGE
```

NAV is capped at 0 if the discount reaches or exceeds 100% — a mathematical safety guardrail that prevents underflow. In practice the RiskManager freezes the slot on `ExcessiveYieldShock` (>5% shock) before this level is reached.

| Slot | Maturity | $D_{mod}$ | Yield +50bps → NAV change |
| ---- | -------- | --------- | ------------------------- |
| 1    | 2Y       | 1.9       | -0.95%                    |
| 2    | 5Y       | 4.5       | -2.25%                    |
| 3    | 10Y      | 8.5       | -4.25%                    |
| 4    | 30Y      | 18        | -9.00%                    |

#### Yield Accrual — `claimYield()`

```
grossAccrued = principalUsd × entryYield / PERCENTAGE_PRECISION × elapsed / 365 days
netPayout    = grossAccrued × (1 - PERCENTAGE_YIELD_FEE / MAX_PERCENTAGE)
```

Where `principalUsd = token.value × entryNAV / PAR` (USD 18 decimals). The management fee portion accrues to `feeCollector`.

#### USDC Settlement — Open and Close

| Operation                          | Price                            | Fee                                                    |
| ---------------------------------- | -------------------------------- | ------------------------------------------------------ |
| `openNewPosition(to, slot, usdc)`  | 1:1 USDC → USD via price feed   | Entry fee (0.2%) deducted from deposit                 |
| `closePosition(tokenId)`           | `token.value × NAV / PAR` USDC  | Early redemption fee (0–5%) if within penalty period   |

#### Risk Controls

| Control                  | Implementation                                                                         |
| ------------------------ | -------------------------------------------------------------------------------------- |
| Reserve coverage         | `RiskManager._validateMintReserves()` — blocks mint if portfolio < liabilities × buffer |
| Dynamic reserve buffer   | Increases buffer up to 1.5× during 2s10s yield curve inversion                        |
| Slot freeze              | Anomalous yield or reserve data freezes the affected slot, leaving others operational  |
| Oracle freshness         | `_checkSlotSafe()` — blocks mint/burn if yield or reserve oracle is stale              |
| On-chain liquidity check | `_validateInstantLiquidity()` — blocks redeem if USDC in Treasury < payout required    |
| Daily redeem limit       | `_validateRedeemRateLimit()` — caps daily USDC outflow per slot (anti bank-run)        |
| Redemption window        | `_validateRedemptionWindow()` — restricts redemptions to SPV operational hours         |
| Frozen wallets           | ERC-3643: blocks transfers from frozen addresses                                       |

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

Compliance is enforced in `_beforeValueTransfer()`, which delegates to `_beforeMint`, `_beforeBurn`, or `_beforeTransfer` depending on the operation. The ERC-3643 layer handles KYC checks, wallet freeze, and pause. The RiskManager layer handles oracle freshness and slot freeze.

---

### Oracle Architecture: Three Contracts, Separation of Concerns

| Contract                  | Role                                                                  | Chainlink dependency? |
| ------------------------- | --------------------------------------------------------------------- | --------------------- |
| `BondOracle`              | Stores yields, exposes `getAllYields()` and `isStale()`               | ❌ None               |
| `BondFunctionsConsumer`   | Calls Chainlink Functions, writes to BondOracle                       | ✅ FunctionsClient    |
| `ReservesOracle`          | Attests custodian reserve balances per slot                           | ❌ None (mock)        |
| `ReservesFunctionsConsumer` | Calls Chainlink Functions, writes to ReservesOracle               | ✅ FunctionsClient    |

RiskManager reads from both oracles **indirectly** via a validated cache (`s_lastValidYields`, `s_lastValidReserves`, `s_lastValidSlotMarketData`). Oracle data is never read directly during user transactions — it flows through the cache update functions (`updateYieldsValues`, `updateReserveValues`) triggered by Chainlink Automation.

---

### Contract Architecture: Abstract Bases + Internal Functions + Access-Controlled Public Wrappers

Three of the abstract base contracts inherited by `TreasuryBondToken` follow a common pattern: logic is implemented as `internal` functions in the base, then surfaced in `TreasuryBondToken` as `public`/`external` functions with the appropriate access controls.

```
Abstract base contract
    └── _internalFunction(params) internal   ← logic here, no access control

TreasuryBondToken (inherits base)
    └── publicFunction(params) external onlyRole(SOME_ROLE) {
            _internalFunction(params);        ← guarded wrapper
        }
```

This pattern applies to `RiskManager`, `ERC3643`, and `UsdcUsdConverter`. It does **not** apply to the oracle or automation contracts, which are standalone deployments communicating via external calls.

#### `RiskManager` → `TreasuryBondToken`

`RiskManager` contains all risk control logic as `internal` functions. `TreasuryBondToken` exposes the admin entry points with `onlyRole`:

| Internal (RiskManager) | Public wrapper (TreasuryBondToken) | Role |
|---|---|---|
| `_setSlotRiskParams()` | `setSlotRiskParams()` | `OWNER_ROLE` |
| `_triggerYieldsUpkeep()` | `triggerYieldsUpkeep()` | `AUTOMATION_TRIGGERER_ROLE` |
| `_triggerReservesUpkeep()` | `triggerReservesUpkeep()` | `AUTOMATION_TRIGGERER_ROLE` |
| `_updateYieldsValues()` | `updateYieldsValues()` | `UPDATE_RISK_MANAGER_VALUES_ROLE` |
| `_updateReservesValues()` | `updateReserveValues()` | `UPDATE_RISK_MANAGER_VALUES_ROLE` |
| `_setSlotFrozenOnMainContract()` | `setSlotFrozen()` | `OWNER_ROLE` |
| `_assertSolvency()` | `assertSolvency()` | *(public view, no role)* |

The lifecycle hooks (`_riskManagerBeforeMint`, `_riskManagerBeforeBurn`, `_riskManagerBeforeTransferLiquidity`) remain fully internal — called from `TreasuryBondToken`'s `_beforeMint`/`_beforeBurn`/`_beforeTransfer` and never exposed.

#### `ERC3643` → `TreasuryBondToken`

`ERC3643` implements T-REX compliance logic as `internal` functions. `TreasuryBondToken` exposes the operator entry points with their respective T-REX roles:

| Internal (ERC3643) | Public wrapper (TreasuryBondToken) | Role |
|---|---|---|
| `_pause()` / `_unpause()` | `pause()` / `unpause()` | `PAUSER_ROLE` |
| `_setAddressFrozen()` | `setAddressFrozen()`, `batchSetAddressFrozen()` | `FREEZER_ROLE` |
| `_freezePartialToken()` / `_unfreezePartialToken()` | `freezePartialTokens()`, `unfreezePartialTokens()`, batch variants | `FREEZER_ROLE` |
| `_recoveryAddress()` | `recoveryAddress()` | `RECOVERY_ROLE` |
| `_executeRecoveryTransfer()` | `_executeRecoveryTransferExternal()` | `RECOVERY_ROLE` |

`forceTransfer` is defined directly in `TreasuryBondToken` (not a wrapper of an ERC3643 internal) because it additionally settles yield and clears frozen value before executing the transfer.

#### `UsdcUsdConverter` → `TreasuryBondToken`

`UsdcUsdConverter` provides USDC/USD conversion utilities as `internal` functions. The conversion functions (`_convertUsdcToUsd18`, `_convertUsd18ToUsdc`, etc.) are used **purely internally** by `TreasuryBondToken` — they are never exposed publicly. Only the state getters surface as `external view` functions, without a role guard since they are read-only:

| Internal (UsdcUsdConverter) | Public wrapper (TreasuryBondToken) | Role |
|---|---|---|
| `_getUsdc()` | `getUsdc()` | *(no role — view)* |
| `_getUsdUsdcPriceFeed()` | `getUsdcPriceFeed()` | *(no role — view)* |
| *(immutable)* | `getUsdcDecimals()` | *(no role — view)* |
| *(immutable)* | `getUsdcPriceFeedDecimals()` | *(no role — view)* |

#### Why this design

1. **Single access-control surface.** All `onlyRole` guards live in `TreasuryBondToken`. Base contracts contain zero role checks — they cannot be misconfigured independently.
2. **Separation of concerns.** Risk logic, compliance logic, and conversion utilities are isolated in their own modules. `TreasuryBondToken` is the integration layer, not the logic layer.
3. **Testability.** Internal functions in abstract contracts can be tested by deploying a minimal concrete wrapper that inherits only the module under test, without needing the full `TreasuryBondToken` setup.
4. **No proxy overhead.** All base contracts are inherited directly — the entire system compiles into a single bytecode deployment. No `delegatecall`, no proxy pattern, no storage slot collision risk.
5. **Solidity enforces it.** Abstract contracts cannot be deployed directly, making the inheritance boundary explicit and compile-time guaranteed.

---

## Dependencies

| Library              | Remapping               | Purpose                                                       |
| -------------------- | ----------------------- | ------------------------------------------------------------- |
| OpenZeppelin         | `@openzeppelin/`        | AccessControl, ReentrancyGuard, SafeERC20, SafeCast           |
| Chainlink            | `@chainlink/`           | FunctionsClient, AutomationCompatible, AggregatorV3Interface  |
| T-REX                | `@t-rex/`               | IdentityRegistry, ClaimTopicsRegistry, TrustedIssuersRegistry |
| ONCHAINID            | `@onchain-id/solidity/` | Identity, ClaimIssuer                                         |
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

- **No real custody:** `ReservesOracle` is a mock. In production, the reserve feed would come from a Chainlink PoR node attesting a real custodian wallet or SPV.
- **No redemption-side PoR:** the current model gates minting on reserve sufficiency but does not re-check reserves on yield accrual payouts.
- **No Proof of Reserve for yield oracle:** FRED data is fetched via Chainlink Functions DON but without cryptographic proof of data integrity. In production, multiple independent data sources provide this guarantee.

---

## License

MIT
