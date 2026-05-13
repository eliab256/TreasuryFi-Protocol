# RiskManager — Specifica Tecnica V3

## Indice
1. [Scopo e responsabilità](#1-scopo-e-responsabilità)
2. [Posizione nell'architettura](#2-posizione-nellarchitettura)
3. [Modello delle liquidità](#3-modello-delle-liquidità)
4. [Storage](#4-storage)
5. [Unità di misura](#5-unità-di-misura)
6. [Funzioni implementate V1](#6-funzioni-implementate-v1)
7. [Funzioni stub da completare V1](#7-funzioni-stub-da-completare-v1)
8. [Integrazione con TreasuryBondToken](#8-integrazione-con-treasurybondtoken)
9. [Custom Errors ed Eventi](#9-custom-errors-ed-eventi)
10. [Funzioni V2](#10-funzioni-v2)
11. [Note implementative](#11-note-implementative)

---

## 1. Scopo e responsabilità

`RiskManager` è un contratto **abstract** che implementa tutti i controlli di rischio finanziario del protocollo TreasuryFi.

Responsabilità:
- Validare i dati oracle prima di qualsiasi operazione (freshness, bounds, shock)
- Garantire che le riserve off-chain coprano le liability per ogni slot
- Garantire che la liquidità on-chain sia sufficiente per ogni rimborso
- Isolare gli slot anomali senza bloccare l'intero protocollo

### Cosa NON fa
- Non gestisce identità o compliance → `ERC3643`
- Non gestisce la logica dei token ERC3525 → `ERC3525`
- Non gestisce le fee di business → `TreasuryBondToken`
- Non gestisce la pausa globale → `ERC3643`

---

## 2. Posizione nell'architettura

```
TreasuryBondToken is ERC3643, ERC3525, RiskManager, UsdcUsdConverter, ReentrancyGuard
```

### Flusso mint
```
openNewPosition()
    ├── _calculateEntryFees()
    ├── treasury.depositUsdcFromOpenNewPosition()
    ├── _convertUsdcToUsd18()
    └── _mint()
            └── _beforeValueTransfer()
                    ├── ERC3643._beforeValueTransfer()  [KYC, freeze wallet, pause]
                    └── _beforeMint()
                            ├── _riskManagerBeforeMint()
                            │       ├── _checkSlotSafe()            [isStale + frozen]
                            │       ├── _validateMintReserves()     [coverage check]
                            │       └── s_totalLiabilitiesPerSlot[slot] += value
                            └── init PositionData
```

### Flusso burn
```
closePosition()
    ├── _closePositionValue()
    ├── _validateRedemptionWindow()   ← view
    ├── _validateInstantLiquidity()   ← check USDC on-chain
    ├── _burn()
    │       └── _beforeValueTransfer()
    │               ├── ERC3643._beforeValueTransfer()
    │               └── _beforeBurn()
    │                       └── _riskManagerBeforeBurn()
    │                               ├── _checkSlotSafe()
    │                               └── s_totalLiabilitiesPerSlot[slot] -= value
    └── treasury.withdrawUsdcFromClosePosition()
```

### Separazione responsabilità tra i due storage di mercato

| Storage | Tipo | Decimali | Usato per |
|---|---|---|---|
| `s_lastValidSlotMarketData[slot]` | `SlotMarketData` packed | 8 dec raw | Shock detection nei cicli successivi |
| `s_lastValidReserves` | `ReservesResponse` | 18 dec | Coverage check al mint |

**Non confondere i due.** `_validateMintReserves` usa `s_lastValidReserves`. `_validateAndUpdateLastValidReserve` usa `s_lastValidSlotMarketData` per confronto con il ciclo precedente.

---

## 3. Modello delle liquidità

```
┌──────────────────────────────────────────┐
│           OFF-CHAIN (SPV)                │
│  POOL 1 — T-BILL (per slot)              │
│  illiquido — liquidazione: giorni        │
│                                          │
│  POOL 2 — CASH BUFFER SPV (per slot)     │
│  semi-liquido — trasferimento: ore       │
└──────────────┬───────────────────────────┘
               │ injectLiquidity()
               ▼
┌──────────────────────────────────────────┐
│           ON-CHAIN (Treasury)            │
│  POOL 3 — USDC (per slot)                │
│  immediatamente disponibile              │
└──────────────────────────────────────────┘
```

| Grandezza | Dove vive | Unità | Risponde a |
|---|---|---|---|
| `liabilities[slot]` | `s_totalLiabilitiesPerSlot` | USD 18 dec | "quanto dobbiamo in totale?" |
| `bondsValue[slot]` | `s_lastValidReserves` | USD 18 dec | "siamo solvibili a lungo?" |
| `cashBuffer[slot]` | `s_lastValidReserves` | USD 18 dec | "possiamo pagare a breve?" |
| `usdcTreasury[slot]` | `Treasury.s_totalUsdcPerSlot` | USDC 6 dec | "possiamo pagare adesso?" |

### Check al mint — Reserve Coverage
```
portfolioValue   = bondsValue[slot] + cashBuffer[slot]            [USD 18 dec, da s_lastValidReserves]
requiredReserves = (liabilities[slot] + mintValue) × reserveBuffer / MAX_PERCENTAGE

if portfolioValue < requiredReserves → revert InsufficientReserves
```

### Check al burn — Liquidity Check
```
totalUsdcOut = usdcPayout + netYield + earlyFee + managementFee   [USDC 6 dec]

if treasury.getTotalUsdcLiquidityPerSlot(slot) < totalUsdcOut → revert InsufficientLiquidity
```

---

## 4. Storage

```solidity
// ─── Immutabili ──────────────────────────────────────────────────────────────

IBondAutomation     internal immutable i_yieldsAutomation;
IReservesAutomation internal immutable i_reservesAutomation;
IReservesOracle     internal immutable i_reservesOracle;
IBondOracle         internal immutable i_yieldsOracle;
ITreasury           internal immutable i_treasury;
uint256             internal immutable i_gracePeriod;
uint256             internal immutable i_interval;

// ─── Cache dati validati (USD 18 dec) ────────────────────────────────────────

BondYieldsResponse internal s_lastValidYields;
ReservesResponse   internal s_lastValidReserves;  // valori USD già in 18 dec

// ─── Shock filter (raw oracle, 1 SLOAD per slot) ─────────────────────────────
// Usato SOLO durante _updateLastValidYields/Reserves.
// yield in bps, reserve/cashBuffer in USD 8 dec raw.

struct SlotMarketData {
    uint32  yield;        //  4 bytes
    uint112 reserve;      // 14 bytes  → 32 bytes totali = 1 SLOAD
    uint112 cashBuffer;   // 14 bytes
}
mapping(uint256 => SlotMarketData) internal s_lastValidSlotMarketData;

// ─── Freeze state (3 bool = 1 SLOAD) ────────────────────────────────────────

struct SlotFreezeState {
    bool frozenByYields;
    bool frozenByReserves;
    bool frozen;            // unico campo letto nelle tx utente
}
mapping(uint256 => SlotFreezeState) internal s_slotFrozenState;

// ─── Liabilities (USD 18 dec) ────────────────────────────────────────────────

mapping(uint256 => uint256) private s_totalLiabilitiesPerSlot;

// ─── Risk params per slot (1 SLOAD) — definiti in types.sol ─────────────────
// struct SlotRiskParams {
//     uint128 maxDailyRedeem;        // 16 bytes ─┐
//     uint32  redeemWindowOpen;      //  4 bytes  │ 28 bytes = 1 storage slot
//     uint32  redeemWindowDuration;  //  4 bytes  │
//     uint32  reserveBuffer;         //  4 bytes ─┘
// }
mapping(uint256 => SlotRiskParams) internal s_slotRiskParams;

// ─── Rate limit redeem (V1 stub = non dichiarati nel codice corrente) ─────────

mapping(uint256 => uint256) internal s_dailyRedeemVolume;        // da aggiungere
mapping(uint256 => uint256) internal s_dailyRedeemWindowStart;   // da aggiungere

// ─── Costanti ────────────────────────────────────────────────────────────────

uint256 internal constant MAX_YIELD_SHOCK_BPS    = 5  * C.PERCENTAGE_PRECISION;
uint256 internal constant MAX_YIELD              = 20 * C.PERCENTAGE_PRECISION;
uint256 internal constant MAX_RESERVES_SHOCK_BPS = 30 * C.PERCENTAGE_PRECISION;
uint256 private  constant USD8_TO_USD18          = 1e10;
```

### Nota su `reserveBuffer` e unità

Espresso in scala `PERCENTAGE_PRECISION` (base `MAX_PERCENTAGE = 1_000_000`):

| Slot | `reserveBuffer` | Percentuale |
|---|---|---|
| 2Y  | 1_050_000 | 105% |
| 5Y  | 1_080_000 | 108% |
| 10Y | 1_120_000 | 112% |
| 30Y | 1_200_000 | 120% |

Formula: `requiredReserves = (liabilities + mintValue) * reserveBuffer / MAX_PERCENTAGE`

---

## 5. Unità di misura

| Grandezza | Unità |
|---|---|
| Yield oracle raw / `SlotMarketData.yield` | bps |
| `SlotMarketData.reserve/cashBuffer` | USD 8 dec raw |
| `s_lastValidReserves.*` | USD 18 dec |
| `s_totalLiabilitiesPerSlot` | USD 18 dec |
| USDC amounts Treasury/payout | USDC 6 dec |
| `reserveBuffer` | `× PERCENTAGE_PRECISION` (base `MAX_PERCENTAGE = 1_000_000`) |

---

## 6. Funzioni implementate V1

### 6.1 `_setSlotRiskParams` / `_checkSlotRiskParamsSet`

Validazione: `reserveBuffer >= MAX_PERCENTAGE`, finestra settimanale coerente. `_checkSlotRiskParamsSet` usa `reserveBuffer == 0` come proxy per "non configurato".

### 6.2 `_updateYieldsValues` / `_updateLastValidYields`

Shock filter yields:
```
delta = |yield_nuovo - s_lastValidSlotMarketData[slot].yield|
if delta > MAX_YIELD_SHOCK_BPS → freeze, emit ExcessiveYieldShock
```
Bounds: `0 < yield ≤ MAX_YIELD`. Se valido, aggiorna `s_lastValidSlotMarketData[slot].yield` (uint32). Cache `s_lastValidYields` aggiornata atomicamente o con mixed response.

### 6.3 `_updateReservesValues` / `_updateLastValidReserves`

Shock filter reserves (percentuale):
```
delta    = |reserve_nuovo - s_lastValidSlotMarketData[slot].reserve|
shockBps = (delta × MAX_PERCENTAGE) / s_lastValidSlotMarketData[slot].reserve
if shockBps > MAX_RESERVES_SHOCK_BPS → freeze, emit ExcessiveReserveShock
```

Conversione a 18 dec al momento dello storage nella cache:
```solidity
// ramo "tutti validi"
s_lastValidReserves.twoYearUsdBondsValue = newResponse.twoYearUsdBondsValue * USD8_TO_USD18;

// ramo "mixed response"
twoYearUsdBondsValue: freezeSlot1
    ? cached.twoYearUsdBondsValue                          // già 18 dec
    : newResponse.twoYearUsdBondsValue * USD8_TO_USD18,    // converti
```

**⚠️ Audit issue aperto:** nel ramo mixed response, `totalUsdBondsValue` e `totalUsdPortfolioValue` vengono presi da `newReservesResponse` (totale oracle), ma i per-slot frozen mantengono il valore cached. Il totale oracle include il valore nuovo dello slot frozen → `totalUsdBondsValue != somma dei per-slot stored`. Fix: ricalcolare i totali sommando i per-slot in base ai freeze flag.

### 6.4 Freeze management

`_setSlotFrozenOnMainContract`: admin override, 1 SLOAD + 1 SSTORE.
`_setYieldsSlotFrozen` / `_setReservesSlotFrozen`: aggiornano il flag specifico e ricalcolano `frozen = frozenByYields || frozenByReserves`. Evento emesso solo se `frozen` cambia.

### 6.5 `_checkSlotSafe`

```solidity
function _checkSlotSafe(uint256 _slot) internal view {
    if (i_yieldsOracle.isStale() || i_reservesOracle.isStale())
        revert RiskManager__StaleOracleData();
    if (s_slotFrozenState[_slot].frozen)
        revert RiskManager__SlotFrozen(_slot);
}
```

Guardia leggera usata dai lifecycle hook. Non carica dati in memoria.

### 6.6 `_validateInstantLiquidity`

```solidity
function _validateInstantLiquidity(uint256 _slot, uint256 _requiredLiquidity) internal {
    uint256 available = i_treasury.getTotalUsdcLiquidityPerSlot(_slot);
    if (available < _requiredLiquidity)
        revert RiskManager__InsufficientLiquidity(_slot, available, _requiredLiquidity);
}
```

Visibilità **`internal`** (non `private`).

### 6.7 `_validateRedemptionWindow`

```solidity
function _validateRedemptionWindow(uint256 _slot, SlotRiskParams memory _riskParams) internal view {
    if (_riskParams.redeemWindowDuration == 0) return;

    uint256 secondsIntoWeek = block.timestamp % 7 days;
    uint256 windowOpen  = _riskParams.redeemWindowOpen;
    uint256 windowClose = windowOpen + _riskParams.redeemWindowDuration;

    if (secondsIntoWeek < windowOpen || secondsIntoWeek > windowClose)
        revert RiskManager__RedemptionWindowClosed(_slot, secondsIntoWeek, windowOpen, windowClose);
}
```

### 6.8 `_getNextRedemptionWindow`

Getter interno. Da esporre come `public view` in `TreasuryBondToken`.

### 6.9 Lifecycle hooks

**`_riskManagerBeforeMint`:**
```solidity
function _riskManagerBeforeMint(uint256 _slot, uint256 _value) internal {
    _checkSlotSafe(_slot);

    // Usa s_lastValidReserves (USD 18 dec) — NON s_lastValidSlotMarketData (8 dec raw)
    ReservesResponse memory reserves = s_lastValidReserves;
    SlotRiskParams   memory params   = s_slotRiskParams[_slot];

    _validateMintReserves(_slot, _value, reserves, params.reserveBuffer);

    s_totalLiabilitiesPerSlot[_slot] += _value;
}
```

**`_riskManagerBeforeBurn`:**
```solidity
function _riskManagerBeforeBurn(uint256 _slot, uint256 _value) internal {
    _checkSlotSafe(_slot);
    s_totalLiabilitiesPerSlot[_slot] -= _value;
}
```

**`_riskManagerBeforeClaimingYield`:**
```solidity
function _riskManagerBeforeClaimingYield(uint256 _slot, uint256 _value) internal {
    _checkSlotSafe(_slot);
    // Nessun aggiornamento liabilities — il claim non cambia il principal
}
```

### 6.10 Trigger manuale automation

Anti-spam con cooldown `i_interval + i_gracePeriod`. `checkUpkeep("")` prima di `performUpkeep("")`.

---

## 7. Funzioni stub da completare V1

### 7.1 `_validateMintReserves`

```solidity
function _validateMintReserves(
    uint256 _slot,
    uint256 _mintValue,
    ReservesResponse memory _reserves,
    uint256 _reserveBuffer
) private view {
    uint256 bondsValue;
    uint256 cashValue;

    if      (_slot == C.SLOT_2Y)  { bondsValue = _reserves.twoYearUsdBondsValue;    cashValue = _reserves.twoYearUsdCashValue; }
    else if (_slot == C.SLOT_5Y)  { bondsValue = _reserves.fiveYearUsdBondsValue;   cashValue = _reserves.fiveYearUsdCashValue; }
    else if (_slot == C.SLOT_10Y) { bondsValue = _reserves.tenYearUsdBondsValue;    cashValue = _reserves.tenYearUsdCashValue; }
    else if (_slot == C.SLOT_30Y) { bondsValue = _reserves.thirtyYearUsdBondsValue; cashValue = _reserves.thirtyYearUsdCashValue; }

    uint256 portfolioValue   = bondsValue + cashValue;
    uint256 requiredReserves = (s_totalLiabilitiesPerSlot[_slot] + _mintValue)
                               * _reserveBuffer / C.MAX_PERCENTAGE;

    if (portfolioValue < requiredReserves)
        revert RiskManager__InsufficientReserves(_slot, portfolioValue, requiredReserves);
}
```

### 7.2 `_validateRedeemRateLimit`

```
if block.timestamp > s_dailyRedeemWindowStart[slot] + 1 days:
    s_dailyRedeemVolume[slot] = 0
    s_dailyRedeemWindowStart[slot] = block.timestamp

if s_dailyRedeemVolume[slot] + redeemValue > maxDailyRedeem → revert
s_dailyRedeemVolume[slot] += redeemValue
```

`maxDailyRedeem == 0` → disabilitato. **⚠️ Side effect** — chiamare dopo tutti i check view.

Storage da aggiungere: `s_dailyRedeemVolume` e `s_dailyRedeemWindowStart`.

---

## 8. Integrazione con TreasuryBondToken

### `closePosition`

```solidity
SlotRiskParams memory params = s_slotRiskParams[slot];  // 1 SLOAD, riusato
_validateRedemptionWindow(slot, params);                 // view
uint256 totalOut = usdcPayout + netYield + earlyFee + mgmtFee;
_validateInstantLiquidity(slot, totalOut);
// _validateRedeemRateLimit(slot, totalOut, params.maxDailyRedeem);  // stub
_burn(_tokenId);
i_treasury.withdrawUsdcFromClosePosition(...);
```

### Configurazione costruttore

```solidity
_setSlotRiskParams(C.SLOT_2Y,  SlotRiskParams({ maxDailyRedeem: 0, redeemWindowOpen: 0, redeemWindowDuration: 0, reserveBuffer: 1_050_000 }));
_setSlotRiskParams(C.SLOT_5Y,  SlotRiskParams({ maxDailyRedeem: 0, redeemWindowOpen: 0, redeemWindowDuration: 0, reserveBuffer: 1_080_000 }));
_setSlotRiskParams(C.SLOT_10Y, SlotRiskParams({ maxDailyRedeem: 0, redeemWindowOpen: 0, redeemWindowDuration: 0, reserveBuffer: 1_120_000 }));
_setSlotRiskParams(C.SLOT_30Y, SlotRiskParams({ maxDailyRedeem: 0, redeemWindowOpen: 0, redeemWindowDuration: 0, reserveBuffer: 1_200_000 }));
```

---

## 9. Custom Errors ed Eventi

```solidity
// Implementati
error RiskManager__InvalidYield(uint256 slot, uint256 yield);
error RiskManager__ExcessiveYieldShock(uint256 slot, uint256 shock);
error RiskManager__ZeroAddress();
error RiskManager__AutomationGracePeriodNotElapsed();
error RiskManager__SlotAlreadyFrozen(uint256 slot);
error RiskManager__SlotNotFrozen(uint256 slot);
error RiskManager__SlotFrozen(uint256 slot);
error RiskManager__SlotAlreadyInState(uint256 slot, bool frozen);
error RiskManager__StaleOracleData();
error RiskManager__InvalidReserve(uint256 slot, uint256 reserve);
error RiskManager__InsufficientLiquidity(uint256 slot, uint256 available, uint256 required);
error RiskManager__InsufficientReserves(uint256 slot, uint256 available, uint256 required);
error RiskManager__RedemptionWindowClosed(uint256 slot, uint256 current, uint256 open, uint256 close);
error RiskManager__InvalidSlotParams();
error RiskManager__InvalidReserveBuffer();
error RiskManager__SlotRiskParamsNotSet(uint256 slot);

// Da aggiungere
error RiskManager__DailyRedeemLimitExceeded(uint256 slot, uint256 attempted, uint256 remaining);
error RiskManager__SolvencyNotGuaranteed();

// Implementati
event SlotFrozen(uint256 indexed slot);
event SlotUnfrozen(uint256 indexed slot);
event InvalidYield(uint256 indexed slot, uint256 yield);
event ExcessiveYieldShock(uint256 indexed slot, uint256 shock);
event InvalidReserve(uint256 indexed slot, uint256 reserve);
event ExcessiveReserveShock(uint256 indexed slot, uint256 shock);
event InvalidCashBuffer(uint256 indexed slot, uint256 cashBuffer);
event ExcessiveCashBufferShock(uint256 indexed slot, uint256 shock);
event SlotRiskParamsUpdated(uint256 indexed slot, uint256 reserveBuffer, uint256 maxDailyRedeemBps, uint256 redeemWindowOpen, uint256 redeemWindowDuration);
```

---

## 10. Funzioni V2

### 10.1 `_isSolvent` / `_assertSolvency` (parzialmente in V1 con bug)

```solidity
function _isSolvent() internal view returns (bool) {
    // Se frozen per reserves, dati non attendibili
    if (s_slotFrozenState[C.SLOT_2Y].frozenByReserves  ||
        s_slotFrozenState[C.SLOT_5Y].frozenByReserves  ||
        s_slotFrozenState[C.SLOT_10Y].frozenByReserves ||
        s_slotFrozenState[C.SLOT_30Y].frozenByReserves)
        return false;

    // Cache già in 18 dec — NON moltiplicare per USD8_TO_USD18
    uint256 totalPortfolio = s_lastValidReserves.totalUsdPortfolioValue;

    uint256 totalLiabilities = s_totalLiabilitiesPerSlot[C.SLOT_2Y]
                             + s_totalLiabilitiesPerSlot[C.SLOT_5Y]
                             + s_totalLiabilitiesPerSlot[C.SLOT_10Y]
                             + s_totalLiabilitiesPerSlot[C.SLOT_30Y];

    return totalPortfolio >= totalLiabilities;
}
```

Nota: `totalUsdPortfolioValue` soffre dell'audit issue del ramo mixed response (sezione 6.3).

### 10.2 Curve Blocking, Mint Rate Limit, Dynamic Buffer, Window bisettimanale

Vedi spec V2.

---

## 11. Note implementative

### Ordine check in closePosition

```
1. _closePositionValue()          — nessun side effect su RiskManager storage
2. SlotRiskParams caricato        — 1 SLOAD, riusato da step 3
3. _validateRedemptionWindow()    — view, no side effect
4. _validateInstantLiquidity()    — view su Treasury
5. _validateRedeemRateLimit()     — ⚠️ side effect: aggiorna s_dailyRedeemVolume
6. _burn()                        — _riskManagerBeforeBurn: decrementa liabilities
7. treasury.withdraw()
```

### Testing Foundry

```solidity
// Reserve coverage
// portfolio = 900_000e18, liabilities = 850_000e18, mint = 50_000e18, buffer = 1_120_000
// required = 900_000e18 * 1_120_000 / 1_000_000 = 1_008_000e18 > 900_000e18 → revert

// Shock reserves +40%
// lastReserve = 1_000_000e8, new = 1_400_000e8
// shockBps = 400_000 * 1_000_000 / 1_000_000 = 400_000 > 300_000 → freeze

// Redemption window
vm.warp(weekStart + 32400 + 3600);        // lunedì 10:00 → PASS
vm.warp(weekStart + 6 days + 23 * 3600); // domenica 23:00 → revert
```
