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
    ├── treasury.depositUsdcFromOpenNewPosition()   ← USDC utente → Treasury
    ├── _convertUsdcToUsd18()
    └── _mint()
            └── _beforeValueTransfer()
                    ├── ERC3643._beforeValueTransfer()  [KYC, freeze wallet, pause]
                    └── _beforeMint()
                            ├── _riskManagerBeforeMint()
                            │       ├── _getLastValidYields()   [isStale + frozen + cache]
                            │       ├── _getLastValidReserves() [isStale + frozen + cache]
                            │       ├── _validateMintReserves() [coverage check]  ← stub
                            │       └── s_totalLiabilitiesPerSlot[slot] += value
                            └── init PositionData
```

### Flusso burn (closePosition / closePartialPosition)
```
closePosition()
    ├── _closePositionValue()     ← calcola usdcPayout, yield, fees, NAV
    ├── _validateInstantLiquidity()      ← check USDC on-chain Treasury  [RiskManager]
    ├── _burn()
    │       └── _beforeValueTransfer()
    │               ├── ERC3643._beforeValueTransfer()
    │               └── _beforeBurn()
    │                       ├── _riskManagerBeforeBurn()
    │                       │       ├── _getLastValidYields()
    │                       │       ├── _getLastValidReserves()
    │                       │       └── s_totalLiabilitiesPerSlot[slot] -= value
    │                       └── delete / mantieni PositionData
    └── treasury.withdrawUsdcFromClosePosition()
```

### Perché `_validateInstantLiquidity` è fuori dal hook

Il hook `_riskManagerBeforeBurn` riceve `_value` (USD 18 dec, balance token), ma il check di liquidità richiede `usdcPayout` (USDC 6 dec, già al netto di NAV, conversione e fees). `usdcPayout` è disponibile solo in `closePosition`/`closePartialPosition` prima di `_burn`. Spostare il check nel layer pubblico è la soluzione corretta: il hook rimane responsabile di oracle + freeze + aggiornamento liabilities, il layer pubblico del check di liquidità immediata.

---

## 3. Modello delle liquidità

Il protocollo ha tre pool distinte che coprono rischi diversi su orizzonti temporali diversi.

```
┌─────────────────────────────────────────────────────┐
│                  OFF-CHAIN (SPV)                    │
│                                                     │
│  POOL 1 — T-BILL PORTFOLIO (per slot)               │
│  twoYearUsdBondsValue                               │
│  fiveYearUsdBondsValue         illiquido            │
│  tenYearUsdBondsValue          liquidazione: giorni │
│  thirtyYearUsdBondsValue                            │
│                                                     │
│  POOL 2 — CASH BUFFER SPV (per slot)                │
│  twoYearUsdCashValue                                │
│  fiveYearUsdCashValue          semi-liquido         │
│  tenYearUsdCashValue           trasferimento: ore   │
│  thirtyYearUsdCashValue                             │
│                                                     │
└──────────────────┬──────────────────────────────────┘
                   │ SPV chiama injectLiquidity()
                   │ prima dal cash buffer,
                   │ poi liquidando T-Bill se necessario
                   ▼
┌─────────────────────────────────────────────────────┐
│                  ON-CHAIN (Treasury)                │
│                                                     │
│  POOL 3 — USDC TREASURY (per slot)                  │
│  s_totalUsdcPerSlot[slot]      immediatamente       │
│                                disponibile          │
└─────────────────────────────────────────────────────┘
```

### Grandezze contabili

| Grandezza | Dove vive | Unità | Risponde a |
|---|---|---|---|
| `liabilities[slot]` | `s_totalLiabilitiesPerSlot` | USD 18 dec | "quanto dobbiamo in totale?" |
| `bondsValue[slot]` | cache `s_lastValidReserves` | USD 18 dec | "siamo solvibili a lungo?" |
| `cashBuffer[slot]` | cache `s_lastValidReserves` | USD 18 dec | "possiamo pagare a breve?" |
| `usdcTreasury[slot]` | `Treasury.s_totalUsdcPerSlot` | USDC 6 dec | "possiamo pagare adesso?" |

### Check al mint — Reserve Coverage (Pool 1 + 2 vs liabilities)

Risponde a: *"lo SPV ha abbastanza patrimonio per coprire tutte le posizioni aperte più quella nuova?"*

```
portfolioValue[slot] = bondsValue[slot] + cashBuffer[slot]  [USD 18 dec]
requiredReserves     = (liabilities[slot] + mintValue) × reserveBuffer / 100

if portfolioValue[slot] < requiredReserves → revert InsufficientReserves
```

### Check al burn — Liquidity Check (Pool 3 vs payout immediato)

Risponde a: *"c'è abbastanza USDC cash nel Treasury per pagare adesso?"*

```
totalUsdcOut = usdcPayout + netYield + earlyFee + managementFee  [USDC 6 dec]

if treasury.getTotalUsdcPerSlot(slot) < totalUsdcOut → revert InsufficientLiquidity
```

### Scenario di stress esemplificativo

```
Liabilities slot 10Y:          1.000.000 USD
T-Bill value slot 10Y:         1.100.000 USD   → solvibile ✅
Cash buffer slot 10Y (SPV):       80.000 USD
USDC Treasury slot 10Y:           20.000 USDC

Utente vuole riscattare 50.000 USDC:
  Reserve check al mint (precedente): 1.180.000 > 1.100.000 × 110% → PASS ✅
  Liquidity check al burn: 20.000 < 50.000 → REVERT ❌

→ Non è insolvenza. Lo SPV deve chiamare injectLiquidity() con 30.000 USDC.
→ La redemption window (V1 stub) sincronizza questo operativamente.
```

---

## 4. Storage

```solidity
// ─── Immutabili ──────────────────────────────────────────────────────────────

IBondAutomation     internal immutable i_yieldsAutomation;
IReservesAutomation internal immutable i_reservesAutomation;
IReservesOracle     internal immutable i_reservesOracle;
IBondOracle         internal immutable i_yieldsOracle;
ITreasury           internal immutable i_treasury;       // per _validateInstantLiquidity
uint256             internal immutable i_gracePeriod;
uint256             internal immutable i_interval;

// ─── Timestamp trigger manuale ───────────────────────────────────────────────

uint256 internal s_lastUpkeepTriggerReserves;
uint256 internal s_lastUpkeepTriggerYields;

// ─── Cache dati validati ─────────────────────────────────────────────────────
// Aggiornata da Chainlink Automation via _updateYieldsValues() / _updateReservesValues()
// Letta nelle tx utente — nessuna chiamata oracle diretta durante mint/burn

BondYieldsResponse internal s_lastValidYields;
ReservesResponse   internal s_lastValidReserves;
// NOTA: i valori USD in ReservesResponse sono salvati in 18 decimali
// (convertiti da 8 dec al momento della validazione, vedi sezione 5)

// ─── Shock filter ────────────────────────────────────────────────────────────
// Ultimi valori accettati per slot — usati solo durante _updateLastValidYields/Reserves
// NON usati nelle tx utente

mapping(uint256 => uint256) internal s_lastValidYieldPerSlot;    // bps
mapping(uint256 => uint256) internal s_lastValidReservePerSlot;  // USD 8 dec (raw oracle)
mapping(uint256 => uint256) internal s_lastValidCashBufferPerSlot; // USD 8 dec (raw oracle)

// ─── Freeze state per slot ───────────────────────────────────────────────────
// 3 bool in 1 slot di storage (1 SLOAD per leggere tutto)

struct SlotFreezeState {
    bool frozenByYields;    // anomalia feed yields
    bool frozenByReserves;  // anomalia feed reserves
    bool frozen;            // risultante — unico campo letto nelle tx utente
}
mapping(uint256 => SlotFreezeState) internal s_slotState;

// ─── Liabilities per slot ────────────────────────────────────────────────────
// Valore totale posizioni aperte per slot, in USD 18 decimali
// +value al mint, -value al burn

mapping(uint256 => uint256) private s_totalLiabilitiesPerSlot;

// ─── Parametri di rischio per slot ──────────────────────────────────────────

struct SlotRiskParams {
    uint32 reserveBuffer;        // % overcollateral richiesta (es. 110 = 110%), base 100
    uint128 maxDailyRedeem;       // cap USDC riscattabile in 24h per slot (V1 stub = 0 = disabilitato)
    uint32 redeemWindowOpen;     // secondi dall'inizio settimana (V1 stub = 0)
    uint32 redeemWindowDuration; // durata finestra in secondi   (V1 stub = 0 = sempre aperta)
}
mapping(uint256 => SlotRiskParams) internal s_slotRiskParams;

// ─── Costanti ────────────────────────────────────────────────────────────────

uint256 internal constant MAX_YIELD_SHOCK_BPS    = 5  * PERCENTAGE_PRECISION; // 5%
uint256 internal constant MAX_YIELD              = 20 * PERCENTAGE_PRECISION; // 20% bound assoluto
uint256 internal constant MAX_RESERVES_SHOCK_BPS = 30 * PERCENTAGE_PRECISION; // 30%
uint256 internal constant USD8_TO_USD18          = 1e10; // fattore conversione pura, no price feed
```

### Nota su `maxSupply`

`maxSupply` è stato eliminato da `SlotRiskParams`. Il reserve coverage check è già un cap dinamico implicito: se le riserve non coprono le nuove liabilities con il buffer richiesto, il mint viene bloccato. Un cap hardcoded sarebbe un vincolo separato e ridondante rispetto alla solvibilità reale. Se in futuro serve un tetto assoluto per policy (es. limite regolatorio per slot), si reintroduce come campo governance-settabile.

### Nota su `lockPeriod`

`lockPeriod` non è in `SlotRiskParams` perché è già gestito via `PENALTY_PERIOD_*` in `TokenConstants` e via `_calculateEarlyRedeemFee` in `TreasuryBondToken`. Il lock è un soft deterrent economico (fee decrescente), non un hard block. Se si vuole aggiungere un hard block in V2, si aggiunge `lockPeriod` a `SlotRiskParams` con la relativa validazione.

---

## 5. Unità di misura

| Grandezza | Unità | Note |
|---|---|---|
| Yield da BondOracle | bps (es. 450 = 4.50%) | Scala `PERCENTAGE_PRECISION` = 10000 |
| USD values da ReservesOracle (raw) | USD 8 dec | Formato Chainlink price feed |
| USD values nella cache `s_lastValidReserves` | USD 18 dec | Convertiti con `* USD8_TO_USD18` al momento dello storage |
| Liabilities `s_totalLiabilitiesPerSlot` | USD 18 dec | Coerente con la cache |
| USDC amounts (Treasury, payout utente) | USDC 6 dec | Formato token USDC |
| Fee percentages | scalate per `PERCENTAGE_PRECISION` | Base `MAX_PERCENTAGE = 100 * PERCENTAGE_PRECISION` |
| PAR | 1e18 | Valore nominale per unità token |

### Perché convertire le reserves a 18 dec al momento dello storage

Le reserves dall'oracle arrivano in 8 decimali. Convertirle a 18 dec (`* 1e10`) **una sola volta** al momento della validazione e del caching ha due vantaggi:

1. Il check `_validateMintReserves` è un confronto diretto `uint256 vs uint256` senza conversioni
2. Nessuna chiamata al price feed USDC coinvolta — `USD8_TO_USD18 = 1e10` è una moltiplicazione pura

Lo shock filter (`_validateAndUpdateLastValidReserve`) lavora sui valori raw in 8 dec perché confronta due valori consecutivi dello stesso oracle — la scala non importa purché sia consistente.

---

## 6. Funzioni implementate V1

### 6.1 Costruttore

```solidity
constructor(
    address _yieldsAutomation,
    address _reservesAutomation,
    address _reservesOracle,
    address _yieldsOracle,
    address _treasury          // ← aggiunto rispetto a V2, necessario per _validateInstantLiquidity
)
```

### 6.2 Cache update — yields: `_updateYieldsValues()`

Entry point chiamato da automation o manualmente. Coordina update e freeze.

**Flusso interno:**
```
_updateYieldsValues()
    └── _updateLastValidYields()
            ├── Controlla se oracle.getLastUpdatedTimestamp() > s_lastValidYields.timestamp
            │       └── Se no → return (false×4)  [nessuna azione, dati già freschi]
            ├── Legge BondYieldsResponse da i_yieldsOracle.getAllYields()
            ├── Per ogni slot → _validateAndUpdateLastValidYield()
            │       ├── bounds: 0 < yield ≤ MAX_YIELD (20%)
            │       │       └── fallimento → emit InvalidYield, return true (freeze)
            │       ├── shock: |yield - s_lastValidYieldPerSlot[slot]| ≤ MAX_YIELD_SHOCK_BPS (5%)
            │       │       └── fallimento → emit ExcessiveYieldShock, return true (freeze)
            │       └── successo → aggiorna s_lastValidYieldPerSlot[slot], return false
            ├── Se tutti ok → s_lastValidYields = newResponse (aggiornamento atomico)
            └── Se almeno uno anomalo → mixed response:
                    ├── slot sani ricevono nuovo valore
                    ├── slot anomali mantengono valore cached
                    └── timestamp non aggiornato (non si marca come fresco)
    └── _setYieldsSlotFrozen(slot, freezeN) per ogni slot
```

**Formula shock yields:**
```
delta    = |yield_corrente - s_lastValidYieldPerSlot[slot]|  [bps]
if delta > MAX_YIELD_SHOCK_BPS (= 50000 bps = 5%) → freeze
```

Esempio: yield passa da 450 bps a 1100 bps → delta = 650 > 500 → freeze.

### 6.3 Cache update — reserves: `_updateReservesValues()`

Stesso pattern di `_updateYieldsValues`. Valida due metriche per slot in sequenza:
1. `_validateAndUpdateLastValidReserve` — bond USD value
2. `_validateAndUpdateLastValidCashBuffer` — cash buffer USD value (solo se il bond value era valido)

**Formula shock reserves (percentuale, non assoluta):**
```
delta    = |reserve_corrente - s_lastValidReservePerSlot[slot]|  [USD 8 dec raw]
shockBps = (delta × MAX_PERCENTAGE) / s_lastValidReservePerSlot[slot]
if shockBps > MAX_RESERVES_SHOCK_BPS (= 300000 = 30%) → freeze
```

Esempio: riserva passa da 1.000.000 USD a 1.400.000 USD → delta 40% > 30% → freeze.

**Conversione a 18 dec al momento dello storage nella cache:**
```solidity
// In _updateLastValidReserves, DOPO la validazione shock:
s_lastValidReserves.twoYearUsdBondsValue = newReservesResponse.twoYearUsdBondsValue * USD8_TO_USD18;
s_lastValidReserves.twoYearUsdCashValue  = newReservesResponse.twoYearUsdCashValue  * USD8_TO_USD18;
// ... idem per tutti gli slot
```

I valori raw in 8 dec rimangono nei mapping `s_lastValidReservePerSlot` e `s_lastValidCashBufferPerSlot` perché servono solo per il calcolo dello shock nei cicli successivi.

### 6.4 Freeze management

**`_setSlotFrozenOnMainContract(uint256 _slot, bool _frozen)`** (internal)

Freeze/unfreeze manuale da admin. Imposta entrambi `frozenByYields` e `frozenByReserves` allo stesso valore — semantica di override totale. Un solo `SLOAD` + `SSTORE` su `s_slotState[_slot]` (struct packed).

**`_setYieldsSlotFrozen` / `_setReservesSlotFrozen`** (private)

Aggiornano il rispettivo flag e ricalcolano `frozen = frozenByYields || frozenByReserves`. Emettono `SlotFrozen` / `SlotUnfrozen` solo se `frozen` cambia effettivamente stato.

### 6.5 Getter sicuri per la cache: `_getLastValidYields` / `_getLastValidReserves`

```solidity
function _getLastValidYields(uint256 _slot) internal view returns (BondYieldsResponse memory) {
    if (i_yieldsOracle.isStale())     revert RiskManager__StaleOracleData();
    if (s_slotState[_slot].frozen)    revert RiskManager__SlotFrozen(_slot);
    return s_lastValidYields;
}
```

Stessa logica per `_getLastValidReserves`. Questi sono gli unici punti dove si controlla `isStale()` nelle tx utente — nessuna duplicazione nei lifecycle hook.

### 6.6 Liquidity check: `_validateInstantLiquidity`

```solidity
function _validateInstantLiquidity(uint256 _slot, uint256 _requiredLiquidity) internal {
    uint256 available = i_treasury.getTotalUsdcPerSlot(_slot);
    if (available < _requiredLiquidity) {
        revert RiskManager__InsufficientLiquidity(_slot, available, _requiredLiquidity);
    }
}
```

`_requiredLiquidity` è in USDC 6 dec ed è calcolato nel layer pubblico di `TreasuryBondToken`:

```solidity
uint256 totalUsdcOut = usdcPayout + netYieldToClaimInUsdc + earlyRedeemFeeUsdc + managmentFeeInUsdc;
_validateInstantLiquidity(slot, totalUsdcOut);
```

Include tutte le uscite dalla treasury slot per quella transazione: principal rimborsato, yield netto, fee di uscita anticipata, management fee.

### 6.7 Trigger manuale automation

**`_triggerYieldsUpkeep()` / `_triggerReservesUpkeep()`** (internal)

Anti-spam: revert se `block.timestamp ≤ s_lastUpkeepTrigger + i_interval + i_gracePeriod`. Se il cooldown è passato, chiama `checkUpkeep("")` prima di `performUpkeep("")` per evitare revert inutili.

### 6.8 Lifecycle hooks

**`_riskManagerBeforeMint(uint256 _slot, uint256 _value)`**
```solidity
function _riskManagerBeforeMint(uint256 _slot, uint256 _value) internal {
    BondYieldsResponse memory yields   = _getLastValidYields(_slot);   // isStale + frozen
    ReservesResponse   memory reserves = _getLastValidReserves(_slot); // isStale + frozen

    _validateMintReserves(_slot, _value, reserves); // stub da completare

    s_totalLiabilitiesPerSlot[_slot] += _value;
}
```

**`_riskManagerBeforeBurn(uint256 _slot, uint256 _value)`**
```solidity
function _riskManagerBeforeBurn(uint256 _slot, uint256 _value) internal {
    BondYieldsResponse memory yields   = _getLastValidYields(_slot);
    ReservesResponse   memory reserves = _getLastValidReserves(_slot);
    // Nessun liquidity check qui — vedi sezione 2 per il motivo architetturale

    s_totalLiabilitiesPerSlot[_slot] -= _value;
}
```

**`_riskManagerBeforeClaimingYield(uint256 _slot, uint256 _value)`**
```solidity
function _riskManagerBeforeClaimingYield(uint256 _slot, uint256 _value) internal {
    BondYieldsResponse memory yields   = _getLastValidYields(_slot);
    ReservesResponse   memory reserves = _getLastValidReserves(_slot);
    // Nessun aggiornamento liabilities: il claim non cambia il principal
}
```

### 6.9 Configurazione parametri slot: `_setSlotRiskParams`

```solidity
function _setSlotRiskParams(uint256 _slot, SlotRiskParams memory _params) internal {
    if (_params.reserveBuffer < 100) revert RiskManager__InvalidSlotParams();
    if (_params.redeemWindowOpen >= 7 days) revert RiskManager__InvalidSlotParams();
    if (_params.redeemWindowOpen + _params.redeemWindowDuration > 7 days)
        revert RiskManager__InvalidSlotParams();
    s_slotRiskParams[_slot] = _params;
    emit SlotRiskParamsUpdated(_slot, _params);
}
```

Chiamata nel costruttore di `TreasuryBondToken` per ogni slot. Esposta come funzione pubblica con `OWNER_ROLE` per aggiornamenti governance.

**Valori consigliati al deploy:**

| Slot | `reserveBuffer` | Motivazione |
|---|---|---|
| 2Y  | 105 | D_mod basso (1.9), T-Bill liquidi, rischio tasso minimo |
| 5Y  | 108 | D_mod medio (4.5) |
| 10Y | 112 | D_mod alto (8.5), sensibilità tasso significativa |
| 30Y | 120 | D_mod massimo (18), 1% di shock tasso = 18% variazione NAV |

---

## 7. Funzioni stub da completare V1

### 7.1 `_validateMintReserves` — Reserve Coverage Check

**Dati necessari:**

| Dato | Source | Unità |
|---|---|---|
| `bondsValue[slot]` | `reserves.{slot}UsdBondsValue` | USD 18 dec (già convertito in cache) |
| `cashBuffer[slot]` | `reserves.{slot}UsdCashValue` | USD 18 dec (già convertito in cache) |
| `liabilities[slot]` | `s_totalLiabilitiesPerSlot[slot]` | USD 18 dec |
| `mintValue` | parametro hook | USD 18 dec |
| `reserveBuffer` | `s_slotRiskParams[slot].reserveBuffer` | % base 100 |

**Formula:**
```
portfolioValue   = bondsValue[slot] + cashBuffer[slot]
requiredReserves = (liabilities[slot] + mintValue) × reserveBuffer / 100

if portfolioValue < requiredReserves → revert InsufficientReserves
```

**Esempio numerico:**
```
bondsValue[10Y]   = 950.000e18 USD
cashBuffer[10Y]   =  80.000e18 USD
portfolioValue    = 1.030.000e18 USD

liabilities[10Y]  =   800.000e18 USD
mintValue         =   100.000e18 USD
reserveBuffer     = 112

requiredReserves  = (800.000 + 100.000) × 112 / 100 = 1.008.000e18 USD

1.030.000 > 1.008.000 → PASS ✅
```

**Scenario di stress:**
```
Tassi salgono, NAV T-Bill scende:
bondsValue[10Y]   = 850.000e18 USD (-10%)
portfolioValue    = 930.000e18 USD

requiredReserves  = 1.008.000e18 USD

930.000 < 1.008.000 → REVERT InsufficientReserves ❌
Nuovo mint bloccato per slot 10Y fino a ricopertura riserve
```

**Implementazione:**
```solidity
function _validateMintReserves(
    uint256 _slot,
    uint256 _mintValue,
    ReservesResponse memory _reserves
) private {
    uint256 bondsValue;
    uint256 cashValue;

    if (_slot == C.SLOT_2Y)  { bondsValue = _reserves.twoYearUsdBondsValue;  cashValue = _reserves.twoYearUsdCashValue; }
    else if (_slot == C.SLOT_5Y)  { bondsValue = _reserves.fiveYearUsdBondsValue; cashValue = _reserves.fiveYearUsdCashValue; }
    else if (_slot == C.SLOT_10Y) { bondsValue = _reserves.tenYearUsdBondsValue;  cashValue = _reserves.tenYearUsdCashValue; }
    else if (_slot == C.SLOT_30Y) { bondsValue = _reserves.thirtyYearUsdBondsValue; cashValue = _reserves.thirtyYearUsdCashValue; }

    uint256 portfolioValue   = bondsValue + cashValue;
    uint256 currentLiab      = s_totalLiabilitiesPerSlot[_slot];
    uint256 reserveBuffer    = s_slotRiskParams[_slot].reserveBuffer;
    uint256 requiredReserves = (currentLiab + _mintValue) * reserveBuffer / 100;

    if (portfolioValue < requiredReserves) {
        revert RiskManager__InsufficientReserves(_slot, portfolioValue, requiredReserves);
    }
}
```

### 7.2 `_validateRedemptionWindow` — Finestra Operativa SPV

**Perché esiste:**

La liquidità del Treasury viene rifornita dallo SPV che liquida T-Bill off-chain. Questa operazione richiede ore o giorni lavorativi. Senza finestre, un utente potrebbe riscattare alle 3:00 di domenica quando lo SPV non ha operatori disponibili. La finestra non è una restrizione arbitraria — è la controparte on-chain del NAV settlement time dei fondi comuni TradFi.

**Formula:**
```
secondsIntoWeek = block.timestamp % 7 days
windowEnd       = redeemWindowOpen + redeemWindowDuration

if secondsIntoWeek < redeemWindowOpen || secondsIntoWeek > windowEnd → revert
```

Se `redeemWindowDuration == 0` → finestra sempre aperta (default sicuro per testnet e V1 iniziale).

**Implementazione:**
```solidity
function _validateRedemptionWindow(uint256 _slot) internal view {
    SlotRiskParams memory params = s_slotRiskParams[_slot];
    if (params.redeemWindowDuration == 0) return; // sempre aperta

    uint256 secondsIntoWeek = block.timestamp % 7 days;
    uint256 windowStart     = params.redeemWindowOpen;
    uint256 windowEnd       = windowStart + params.redeemWindowDuration;

    if (secondsIntoWeek < windowStart || secondsIntoWeek > windowEnd) {
        revert RiskManager__RedemptionWindowClosed(_slot, windowStart, windowEnd, secondsIntoWeek);
    }
}
```

**Dove viene chiamata:** in `closePosition` e `closePartialPosition` di `TreasuryBondToken`, prima di `_validateinstantLiquidity` e di `_burn`. È `view` — nessun side effect.

**Getter per frontend:**
```solidity
function getNextRedemptionWindow(uint256 _slot)
    external view
    returns (uint256 nextWindowOpen, uint256 windowDuration)
{
    SlotRiskParams memory params = s_slotRiskParams[_slot];
    windowDuration = params.redeemWindowDuration;
    if (windowDuration == 0) return (block.timestamp, 0);

    uint256 secondsIntoWeek = block.timestamp % 7 days;
    uint256 weekStart       = block.timestamp - secondsIntoWeek;

    if (secondsIntoWeek <= params.redeemWindowOpen) {
        nextWindowOpen = weekStart + params.redeemWindowOpen;
    } else {
        nextWindowOpen = weekStart + 7 days + params.redeemWindowOpen;
    }
}
```

### 7.3 `_validateRedeemRateLimit` — Anti Bank-Run

**Perché esiste:**

Limita il volume giornaliero di rimborsi per slot. Se anche tutti i check precedenti passano, impedisce che in 24h esca più di `maxDailyRedeem` USDC da uno slot. Protegge il cash buffer on-chain da svuotamenti rapidi.

**Formula:**
```
// Reset contatore se siamo in un nuovo giorno
if block.timestamp > s_dailyRedeemWindowStart[slot] + 1 days:
    s_dailyRedeemVolume[slot]      = 0
    s_dailyRedeemWindowStart[slot] = block.timestamp

if s_dailyRedeemVolume[slot] + redeemValue > maxDailyRedeem[slot] → revert

s_dailyRedeemVolume[slot] += redeemValue
```

Se `maxDailyRedeem == 0` → rate limit disabilitato (default V1).

**⚠️ Side effect:** aggiorna `s_dailyRedeemVolume`. Chiamare solo dopo tutti i check view, immediatamente prima del burn.

**Storage aggiuntivo necessario:**
```solidity
mapping(uint256 => uint256) internal s_dailyRedeemVolume;
mapping(uint256 => uint256) internal s_dailyRedeemWindowStart;
```

---

## 8. Integrazione con TreasuryBondToken

### Flusso `closePosition` completo post-V3

```solidity
function closePosition(uint256 _tokenId) public nonReentrant onlyApprovedOrOwner(_tokenId) {
    address owner        = ownerOf(_tokenId);
    uint256 slot         = slotOf(_tokenId);
    uint256 tokenBalance = balanceOf(_tokenId);

    // 1. Calcola tutti i valori USDC (payout, yield, fees, NAV)
    (uint256 usdcPayout, uint256 netYield, uint256 mgmtFee,
     uint256 earlyFee,   uint256 currentNAV)
        = _closePositionValue(_tokenId, slot, tokenBalance);

    // 2. Check finestra operativa SPV [stub V1, no-op se duration == 0]
    _validateRedemptionWindow(slot);

    // 3. Check liquidità on-chain — usa il payout già calcolato
    uint256 totalOut = usdcPayout + netYield + earlyFee + mgmtFee;
    _validateInstantLiquidity(slot, totalOut);

    // 4. Rate limit [stub V1, no-op se maxDailyRedeem == 0]
    // _validateRedeemRateLimit(slot, totalOut);

    // 5. Burn — _riskManagerBeforeBurn aggiorna liabilities e verifica oracle
    _burn(_tokenId);

    // 6. Pagamento
    i_treasury.withdrawUsdcFromClosePosition(usdcPayout, owner, slot, netYield, earlyFee, mgmtFee);

    emit PositionClosed(owner, _tokenId, slot, tokenBalance, usdcPayout, currentNAV);
}
```

### Configurazione nel costruttore di TreasuryBondToken

```solidity
constructor(TreasuryBondTokenConstructorParams memory _params)
    RiskManager(
        _params.bondAutomation,
        _params.reservesAutomation,
        _params.reservesOracle,
        _params.bondOracle,
        _params.treasury          // ← nuovo parametro V3
    ) { ... }

// Dopo i check degli indirizzi:
_setSlotRiskParams(C.SLOT_2Y,  SlotRiskParams({ reserveBuffer: 105, maxDailyRedeem: 0, redeemWindowOpen: 0, redeemWindowDuration: 0 }));
_setSlotRiskParams(C.SLOT_5Y,  SlotRiskParams({ reserveBuffer: 108, maxDailyRedeem: 0, redeemWindowOpen: 0, redeemWindowDuration: 0 }));
_setSlotRiskParams(C.SLOT_10Y, SlotRiskParams({ reserveBuffer: 112, maxDailyRedeem: 0, redeemWindowOpen: 0, redeemWindowDuration: 0 }));
_setSlotRiskParams(C.SLOT_30Y, SlotRiskParams({ reserveBuffer: 120, maxDailyRedeem: 0, redeemWindowOpen: 0, redeemWindowDuration: 0 }));
```

---

## 9. Custom Errors ed Eventi

### Errors

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

// Da aggiungere con gli stub
error RiskManager__InsufficientReserves(uint256 slot, uint256 available, uint256 required);
error RiskManager__DailyRedeemLimitExceeded(uint256 slot, uint256 attempted, uint256 remaining);
error RiskManager__RedemptionWindowClosed(uint256 slot, uint256 windowStart, uint256 windowEnd, uint256 currentSecondInWeek);
error RiskManager__InvalidSlotParams();
```

### Events

```solidity
// Implementati
event SlotFrozen(uint256 indexed slot);
event SlotUnfrozen(uint256 indexed slot);
event InvalidYield(uint256 indexed slot, uint256 yield);
event ExcessiveYieldShock(uint256 indexed slot, uint256 shock);
event InvalidReserve(uint256 indexed slot, uint256 reserve);
event ExcessiveReserveShock(uint256 indexed slot, uint256 shock);
event InvalidCashBuffer(uint256 indexed slot, uint256 cashBuffer);
event ExcessiveCashBufferShock(uint256 indexed slot, uint256 shock);

// Da aggiungere con gli stub
event SlotRiskParamsUpdated(uint256 indexed slot, SlotRiskParams params);
event CurveInversionDetected(uint256 yield2Y, uint256 yield10Y, uint256 timestamp);
```

---

## 10. Funzioni V2

### 10.1 Curve Blocking automatico

**`_validateCurveRegime(uint256 slot)`**

Blocca mint su slot 10Y e 30Y quando `yield2Y > yield10Y` con spread superiore a una soglia configurabile. Richiede definizione governance della soglia di attivazione e meccanismo di reset automatico.

### 10.2 Mint Rate Limiting

**`_validateMintRateLimit(uint256 slot, uint256 mintValue)`**

Stesso pattern del redeem rate limit. Rilevante quando il protocollo aggiunge liquidità secondaria o AMM.

### 10.3 Dynamic Reserve Buffer

**`_calculateDynamicBuffer(uint256 slot)`**

Moltiplicatore applicato al `reserveBuffer` base in funzione di volatilità implicita dai movimenti recenti di yield e shape della curva. In V1 restituisce 1x (nessun effetto). Da dichiarare `virtual` per override in V2.

### 10.4 Solvency Invariant globale

**`_assertSolvency()`**

Verifica `totalReserves >= sum(liabilities[*])` su tutti gli slot. Costoso in gas per ogni tx — da implementare come funzione view su chiamata esplicita admin + monitoring off-chain.

### 10.5 Redemption Window bisettimanale

Aggiungere `windowCycleDays` a `SlotRiskParams` e modificare `_validateRedemptionWindow` per usare `block.timestamp % (windowCycleDays * 1 days)`. Per lo slot 30Y (T-Bill illiquidi, SPV ha bisogno di più tempo) è consigliato un ciclo bisettimanale.

---

## 11. Note implementative

### Ordine dei check in closePosition

```
1. _closePositionValue()         — calcolo valori (nessun side effect su liabilities)
2. _validateRedemptionWindow()   — view, no side effect
3. _validateInstantLiquidity()          — view su Treasury, no side effect
4. _validateRedeemRateLimit()    — ⚠️ side effect: aggiorna s_dailyRedeemVolume
5. _burn()                       — state changes token + _riskManagerBeforeBurn (liabilities)
6. treasury.withdraw()           — trasferimento USDC
```

I check con side effect (step 4) vanno dopo tutti i check view. Se un check view fa revert, lo storage non viene modificato. Il burn (step 5) va dopo tutti i check perché è irreversibile.

### Side effect nei lifecycle hook

`_riskManagerBeforeBurn` aggiorna `s_totalLiabilitiesPerSlot[slot] -= value` nel `_beforeValueTransfer`, che viene chiamato **prima** degli state changes del token in ERC3525. Se un check successivo nel flusso di `_burn` facesse revert (non accade nell'implementazione corrente, ma è un rischio architetturale da tenere presente), le liabilities sarebbero già state decrementate. Tenere questa nota in mente per qualsiasi aggiunta futura di logica nel flusso di burn dopo `_beforeValueTransfer`.

### Testing con Foundry

```solidity
// Test _validateRedemptionWindow
// Lunedì 09:00 UTC — finestra aperta (redeemWindowOpen = 32400)
vm.warp(1_700_000_000 - (1_700_000_000 % 7 days) + 32400 + 1 hours);
// Domenica 23:00 UTC — finestra chiusa
vm.warp(1_700_000_000 - (1_700_000_000 % 7 days) + 6 days + 23 hours);

// Test shock filter reserves
// Imposta lastValidReserve a 1.000.000e8, poi simula update a 1.400.000e8 (+40% > 30%)
// Atteso: ExcessiveReserveShock emesso, slot frozen

// Test reserve coverage
// Imposta reserves a 900.000e18, liabilities a 850.000e18, buffer 110%
// required = 850.000 * 110 / 100 = 935.000 > 900.000
// Atteso: revert InsufficientReserves
```
