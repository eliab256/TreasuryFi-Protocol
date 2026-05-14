# RiskManager — Specifica Tecnica V3

## Indice
1. [Scopo e responsabilità](#1-scopo-e-responsabilità)
2. [Posizione nell'architettura](#2-posizione-nellarchitettura)
3. [Modello delle liquidità](#3-modello-delle-liquidità)
4. [Storage](#4-storage)
5. [Unità di misura](#5-unità-di-misura)
6. [Funzioni implementate V1](#6-funzioni-implementate-v1)
7. [Funzioni implementate — ex stub V1](#7-funzioni-implementate--ex-stub-v1)
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
                            │       ├── _checkSlotSafe()          [isStale yields+reserves + frozen]
                            │       ├── _validateMintReserves()   [coverage check + dynamic buffer]
                            │       └── s_totalLiabilitiesPerSlot[slot] += value
                            └── init PositionData
```

### Flusso burn (closePosition / closePartialPosition)
```
closePosition()
    ├── _closePositionValue()     ← calcola usdcPayout, yield, fees, NAV
    ├── _riskManagerBeforeTransferLiquidity()  [RiskManager]
    │       ├── _validateInstantLiquidity()  ← check USDC on-chain Treasury
    │       └── _validateRedeemRateLimit()    ← anti bank-run (stub V1 = no-op)
    ├── _burn()
    │       └── _beforeValueTransfer()
    │               ├── ERC3643._beforeValueTransfer()
    │               └── _beforeBurn()
    │                       ├── _riskManagerBeforeBurn()
    │                       │       ├── _checkSlotSafe()             [isStale + frozen]
    │                       │       ├── _validateRedemptionWindow()  [finestra SPV]
    │                       │       └── s_totalLiabilitiesPerSlot[slot] -= value
    │                       └── delete / mantieni PositionData
    └── treasury.withdrawUsdcFromClosePosition()
```

> **Perché `_riskManagerBeforeTransferLiquidity` è chiamato prima del burn:**
> Il hook `_riskManagerBeforeBurn` riceve `_value` (USD 18 dec), ma sia il check di liquidità che il rate limit operano in USDC 6 dec. `usdcPayout` è disponibile solo nel layer pubblico prima di `_burn`. Centralizzare questi check nel wrapper `_riskManagerBeforeTransferLiquidity` evita conversioni nel hook e li mantiene con le unità corrette.

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
requiredReserves     = (liabilities[slot] + mintValue) × reserveBuffer / MAX_PERCENTAGE

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
  Reserve check al mint (precedente): 1.180.000 > 1.100.000 × 1_100_000 / 1_000_000 → PASS ✅
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

// ─── Shock filter + market data per slot ────────────────────────────────────
// Packed in a single struct per slot — 1 SLOAD per tutte le info di mercato
// yield in bps (es. 4.50% = 45000), reserve e cashBuffer in USD 18 dec

struct SlotMarketData {
    uint32  yield;        // bps in PERCENTAGE_PRECISION scale (es. 4.50% = 45000)
    uint112 reserve;     // USD 18 dec (convertito da raw 8 dec al momento della validazione)
    uint112 cashBuffer;  // USD 18 dec (convertito da raw 8 dec al momento della validazione)
}
mapping(uint256 => SlotMarketData) private s_lastValidSlotMarketData;

// ─── Freeze state per slot ───────────────────────────────────────────────────
// 3 bool in 1 slot di storage (1 SLOAD per leggere tutto)

struct SlotFreezeState {
    bool frozenByYields;    // anomalia feed yields
    bool frozenByReserves;  // anomalia feed reserves
    bool frozen;            // risultante — unico campo letto nelle tx utente
}
mapping(uint256 => SlotFreezeState) internal s_slotFrozenState;

// ─── Liabilities per slot ────────────────────────────────────────────────────
// Valore totale posizioni aperte per slot, in USD 18 decimali
// +value al mint, -value al burn

mapping(uint256 => uint256) private s_totalLiabilitiesPerSlot;

// ─── Parametri di rischio per slot ──────────────────────────────────────────

struct SlotRiskParams {
    uint32 reserveBuffer;        // overcollateral in scala PERCENTAGE_PRECISION (es. 1_120_000 = 112%), deve essere >= MAX_PERCENTAGE
    uint128 maxDailyRedeem;      // cap USDC riscattabile in 24h per slot in USDC 6 dec (0 = disabilitato)
    uint32 redeemWindowOpen;     // secondi dall'inizio settimana (0 = sempre aperta)
    uint32 redeemWindowDuration; // durata finestra in secondi   (0 = sempre aperta)
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
            │       ├── shock: |yield - s_lastValidSlotMarketData[slot].yield| ≤ MAX_YIELD_SHOCK_BPS (5%)
            │       │       └── fallimento → emit ExcessiveYieldShock, return true (freeze)
            │       └── successo → aggiorna s_lastValidSlotMarketData[slot].yield, return false
            ├── Se tutti ok → s_lastValidYields = newResponse (aggiornamento atomico)
            └── Se almeno uno anomalo → mixed response:
                    ├── slot sani ricevono nuovo valore
                    ├── slot anomali mantengono valore cached
                    └── timestamp non aggiornato (non si marca come fresco)
    └── _setYieldsSlotFrozen(slot, freezeN) per ogni slot
```

**Formula shock yields:**
```
delta    = |yield_corrente - s_lastValidSlotMarketData[slot].yield|  [bps]
if delta > MAX_YIELD_SHOCK_BPS (= 50000 bps = 5%) → freeze
```

Esempio: yield passa da 450 bps a 1100 bps → delta = 650 > 500 → freeze.

### 6.3 Cache update — reserves: `_updateReservesValues()`

Stesso pattern di `_updateYieldsValues`. Valida due metriche per slot in sequenza:
1. `_validateAndUpdateLastValidReserve` — bond USD value
2. `_validateAndUpdateLastValidCashBuffer` — cash buffer USD value (solo se il bond value era valido)

**Formula shock reserves (percentuale, non assoluta):**
```
delta    = |reserve_corrente - s_lastValidSlotMarketData[slot].reserve|  [USD 18 dec]
shockBps = (delta × MAX_PERCENTAGE) / s_lastValidSlotMarketData[slot].reserve
if shockBps > MAX_RESERVES_SHOCK_BPS (= 300000 = 30%) → freeze
```

Esempio: riserva passa da 1.000.000 USD a 1.400.000 USD → delta 40% > 30% → freeze.

**Conversione a 18 dec al momento dello storage nella cache:**
```solidity
// In _validateAndUpdateLastValidReserve e _validateAndUpdateLastValidCashBuffer,
// DOPO la validazione shock, i valori vengono salvati in 18 dec in SlotMarketData:
s_lastValidSlotMarketData[slot].reserve    = newReserveValue * USD8_TO_USD18;
s_lastValidSlotMarketData[slot].cashBuffer = newCashBufferValue * USD8_TO_USD18;
// Il confronto shock usa anch'esso i valori in 18 dec (nessun raw 8 dec separato)
```

**Note — Latent inconsistency in the mixed-response branch:**

When 1–3 slots are frozen, `totalUsdBondsValue` and `totalUsdPortfolioValue` stored in `s_lastValidReserves` are taken from the raw oracle total (which still includes the new, potentially anomalous value for frozen slots), while the per-slot stored values for those slots are kept from cache. This means `totalUsdBondsValue ≠ sum(per-slot stored values)`.

This is **not an active vulnerability** in the current codebase. `_isSolvent()` — the only consumer of `totalUsdPortfolioValue` — reverts first on the `frozenByReserves` guard when any slot is frozen, so the inconsistent total is written to storage but never read in a dangerous path.

**Risk surface:** any future external getter that exposes `totalUsdBondsValue` or `totalUsdPortfolioValue` without the `frozenByReserves` guard would return a value inconsistent with the per-slot stored data. See section 6.11 for the guard that makes this safe.

### 6.4 Freeze management

**`_setSlotFrozenOnMainContract(uint256 _slot, bool _frozen)`** (internal)

Freeze/unfreeze manuale da admin. Imposta entrambi `frozenByYields` e `frozenByReserves` allo stesso valore — semantica di override totale. Un solo `SLOAD` + `SSTORE` su `s_slotState[_slot]` (struct packed).

**`_setYieldsSlotFrozen` / `_setReservesSlotFrozen`** (private)

Aggiornano il rispettivo flag e ricalcolano `frozen = frozenByYields || frozenByReserves`. Emettono `SlotFrozen` / `SlotUnfrozen` solo se `frozen` cambia effettivamente stato.

### 6.5 Safety check centralizzato: `_checkSlotSafe`

```solidity
function _checkSlotSafe(uint256 _slot) internal view {
    if (i_yieldsOracle.isStale() || i_reservesOracle.isStale()) revert RiskManager__StaleOracleData();
    if (s_slotFrozenState[_slot].frozen) revert RiskManager__SlotFrozen(_slot);
}
```

Questo è l'unico punto dove si controlla `isStale()` e il frozen state nelle tx utente. Controlla entrambi gli oracle (yields + reserves) in un'unica chiamata. I lifecycle hook chiamano `_checkSlotSafe` invece di funzioni getter distinte per la cache — nessuna duplicazione.

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
    _checkSlotSafe(_slot);  // isStale (yields + reserves) + frozen
    SlotMarketData memory marketData = s_lastValidSlotMarketData[_slot];
    SlotRiskParams memory riskParams = s_slotRiskParams[_slot];
    _validateMintReserves(_slot, _value, marketData.reserve, marketData.cashBuffer, riskParams.reserveBuffer);
    s_totalLiabilitiesPerSlot[_slot] += _value;
}
```

**`_riskManagerBeforeBurn(uint256 _slot, uint256 _value)`**
```solidity
function _riskManagerBeforeBurn(uint256 _slot, uint256 _value) internal {
    _checkSlotSafe(_slot);  // isStale + frozen
    SlotRiskParams memory riskParams = s_slotRiskParams[_slot];
    _validateRedemptionWindow(_slot, riskParams);
    s_totalLiabilitiesPerSlot[_slot] -= _value;
}
```

**`_riskManagerBeforeTransferLiquidity(uint256 _slot, uint256 _requiredLiquidity)`**
```solidity
function _riskManagerBeforeTransferLiquidity(uint256 _slot, uint256 _requiredLiquidity) internal {
    _validateInstantLiquidity(_slot, _requiredLiquidity);
    _validateRedeemRateLimit(_slot, _requiredLiquidity, s_slotRiskParams[_slot]);
}
```

Chiamato in `closePosition`, `closePartialPosition`, `claimYield` e `_beforeTransfer` (per lo yield settlato prima del transfer) con il totale USDC in uscita. Gestisce sia il check di liquidità che il rate limit in un unico punto, usando l'importo USDC corretto.

> **Nota su `claimYield`:** Il calcolo dello yield è basato esclusivamente sulla `PositionData` del token (entryYield, lastClaimTimestamp), non sui dati oracle correnti. Pertanto `claimYield` non richiede `_checkSlotSafe` — lo yield può essere distribuito anche se i dati oracle sono temporaneamente non aggiornati o lo slot è frozen.

### 6.9 Configurazione parametri slot: `_setSlotRiskParams`

```solidity
function _setSlotRiskParams(uint256 _slot, SlotRiskParams memory _params) internal {
    if (_params.reserveBuffer < C.MAX_PERCENTAGE) revert RiskManager__InvalidReserveBuffer(); // deve essere >= 100%
    if (_params.redeemWindowOpen >= 7 days) revert RiskManager__InvalidSlotParams();
    if (_params.redeemWindowOpen + _params.redeemWindowDuration > 7 days)
        revert RiskManager__InvalidSlotParams();
    s_slotRiskParams[_slot] = _params;
    emit SlotRiskParamsUpdated(
        _slot,
        _params.reserveBuffer,
        _params.maxDailyRedeem,
        _params.redeemWindowOpen,
        _params.redeemWindowDuration
    );
}
```

Chiamata nel costruttore di `TreasuryBondToken` per ogni slot. Esposta come funzione pubblica con `OWNER_ROLE` per aggiornamenti governance.

**Valori consigliati al deploy:**

| Slot | `reserveBuffer` | % effettivo | Motivazione |
|---|---|---|---|
| 2Y  | 1_050_000 | 105% | D_mod basso (1.9), T-Bill liquidi, rischio tasso minimo |
| 5Y  | 1_080_000 | 108% | D_mod medio (4.5) |
| 10Y | 1_120_000 | 112% | D_mod alto (8.5), sensibilità tasso significativa |
| 30Y | 1_200_000 | 120% | D_mod massimo (18), 1% di shock tasso = 18% variazione NAV |

### 6.10 Buffer dinamico per inversione curva: `_calculateDynamicBuffer` ✅ Implementato

Calcola un moltiplicatore da applicare al `reserveBuffer` configurato per lo slot. Chiamata internamente da `_validateMintReserves` per ottenere l'`effectiveBuffer`:

```
effectiveBuffer  = reserveBuffer × _calculateDynamicBuffer(slot) / MAX_PERCENTAGE
requiredReserves = (liabilities + mintValue) × effectiveBuffer / MAX_PERCENTAGE
```

**Logica:** monitora lo spread 2s10s (`yield2Y − yield10Y`). Se lo spread è negativo (curva invertita) e supera la soglia minima di rumore, il moltiplicatore aumenta proporzionalmente all'entità dell'inversione. Un'inversione profonda della curva è un leading indicator di stress economico — aumentare il buffer protocollo durante questi periodi riduce il rischio che nuovi mint vengano emessi in condizioni di mercato deteriorate.

**Protezioni contro falsi positivi da dati corrotti o non inizializzati:**

| Condizione | Perché è un rischio | Comportamento |
|---|---|---|
| `yield2Y == 0 \|\| yield10Y == 0` | Cache non ancora popolata dall'automation | Ritorna 1x |
| `SLOT_2Y.frozenByYields` o `SLOT_10Y.frozenByYields` | L'ultimo aggiornamento ha triggerato lo shock filter — dato non affidabile | Ritorna 1x |
| Spread < 25 bps | Differenza troppo piccola: rumore, arrotondamento, o dato appena aggiornato | Ritorna 1x |
| `_slot == SLOT_2Y` | D_mod ~1.9: l'inversione non impatta significativamente il NAV 2Y | Bypass completo — ritorna 1x |

**Gradualità del moltiplicatore** (per SLOT_5Y, SLOT_10Y, SLOT_30Y):

| Spread 2Y−10Y | Steps | Moltiplicatore | effectiveBuffer con base 112% |
|---|---|---|---|
| 25–49 bps | 1 | 1.1× | 123.2% |
| 50–74 bps | 2 | 1.2× | 134.4% |
| 75–99 bps | 3 | 1.3× | 145.6% |
| 100–124 bps | 4 | 1.4× | 156.8% |
| ≥ 125 bps | 5 (cap) | 1.5× | 168.0% |

Formula: `steps = floor((spread − 25bps) / 25bps) + 1`, capped a `MAX_CURVE_INVERSION_STEPS = 5`.

**Estensibilità:** dichiarata `internal view virtual` — in V2 può essere sovrascritta senza modificare `_validateMintReserves`, ad esempio per incorporare volatilità storica degli yield o metriche aggiuntive di curva.

### 6.11 Invariante di solvibilità globale: `_assertSolvency` ✅ Implementato

Verifica `totalPortfolioValue >= sum(liabilities[*])` su tutti gli slot. Implementata come coppia `_isSolvent() → bool` + `_assertSolvency()` che fa revert con `RiskManager__SolvencyNotGuaranteed`.

`_isSolvent` verifica prima che nessuno slot sia `frozenByReserves` (dato non affidabile → solvibilità non verificabile), poi confronta il portfolio totale con la somma delle liabilities.

Questo guard ha anche un secondo effetto: rende safe la latent inconsistency descritta in sezione 6.3. In caso di mixed-response (almeno uno slot frozen), `totalUsdPortfolioValue` in `s_lastValidReserves` potrebbe essere incoerente con la somma dei per-slot stored — ma `_isSolvent` fa revert sul check `frozenByReserves` prima di leggere il totale, quindi il valore inconsistente non viene mai consumato in un path pericoloso.

Esposta pubblicamente in `TreasuryBondToken` via `assertSolvency() external view`. Da chiamare su richiesta esplicita admin/monitoring off-chain — non è in nessun lifecycle hook (costo gas, già coperto dai check per-slot del `reserveBuffer`).

---

## 7. Funzioni implementate — ex stub V1

### 7.1 `_validateMintReserves` — Reserve Coverage Check ✅ Implementato

**Dati necessari:**

| Dato | Source | Unità |
|---|---|---|
| `bondsValue[slot]` | `reserves.{slot}UsdBondsValue` | USD 18 dec (già convertito in cache) |
| `cashBuffer[slot]` | `reserves.{slot}UsdCashValue` | USD 18 dec (già convertito in cache) |
| `liabilities[slot]` | `s_totalLiabilitiesPerSlot[slot]` | USD 18 dec |
| `mintValue` | parametro hook | USD 18 dec |
| `reserveBuffer` | `s_slotRiskParams[slot].reserveBuffer` | scala PERCENTAGE_PRECISION (es. 1_120_000 = 112%) |

**Formula:**
```
portfolioValue   = bondsValue[slot] + cashBuffer[slot]
requiredReserves = (liabilities[slot] + mintValue) × reserveBuffer / MAX_PERCENTAGE

if portfolioValue < requiredReserves → revert InsufficientReserves
```

**Esempio numerico:**
```
bondsValue[10Y]   = 950.000e18 USD
cashBuffer[10Y]   =  80.000e18 USD
portfolioValue    = 1.030.000e18 USD

liabilities[10Y]  =   800.000e18 USD
mintValue         =   100.000e18 USD
reserveBuffer     = 1_120_000  // 112% in PERCENTAGE_PRECISION

requiredReserves  = (800.000 + 100.000) × 1_120_000 / 1_000_000 = 1.008.000e18 USD

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
// I valori reserve e cashBuffer da SlotMarketData (USD 18 dec),
// bufferPercentage da SlotRiskParams (PERCENTAGE_PRECISION scale).
// Il dynamic multiplier (sezione 6.10) viene applicato prima del calcolo.
function _validateMintReserves(
    uint256 _slot,
    uint256 _value,
    uint256 _reserves,
    uint256 _cashBuffer,
    uint256 _bufferPercentage
) internal view {
    uint256 portfolioValue     = _reserves + _cashBuffer;
    uint256 currentLiab        = s_totalLiabilitiesPerSlot[_slot];
    uint256 dynamicMultiplier  = _calculateDynamicBuffer(_slot);       // 1x se curva normale, >1x se invertita
    uint256 effectiveBuffer    = _bufferPercentage * dynamicMultiplier / C.MAX_PERCENTAGE;
    uint256 requiredReserves   = (currentLiab + _value) * effectiveBuffer / C.MAX_PERCENTAGE;
    if (portfolioValue < requiredReserves) {
        revert RiskManager__InsufficientReserves(_slot, portfolioValue, requiredReserves);
    }
}
```

### 7.2 `_validateRedemptionWindow` — Finestra Operativa SPV ✅ Implementato

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

**Dove viene chiamata:** dentro `_riskManagerBeforeBurn`, che viene invocato dall'hook `_beforeBurn` durante `_burn()` in `closePosition` e `closePartialPosition`. È `view` — nessun side effect.

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

### 7.3 `_validateRedeemRateLimit` — Anti Bank-Run ✅ Implementato

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

    // 2. Check liquidità on-chain + rate limit (entrambi in USDC, nessun side effect se oracle stale)
    //    _riskManagerBeforeTransferLiquidity chiama:  
    //      a) _validateInstantLiquidity — view, no side effect
    //      b) _validateRedeemRateLimit  — ⚠️ side effect: aggiorna s_dailyRedeemVolume
    uint256 totalOut = usdcPayout + netYield + earlyFee + mgmtFee;
    _riskManagerBeforeTransferLiquidity(slot, totalOut);

    // 3. Burn — _riskManagerBeforeBurn: _checkSlotSafe + _validateRedemptionWindow + aggiorna liabilities
    _burn(_tokenId);

    // 4. Pagamento
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
        _params.treasury
    ) { ... }

// Dopo i check degli indirizzi (reserveBuffer in scala PERCENTAGE_PRECISION = 10_000):
_setSlotRiskParams(C.SLOT_2Y,  SlotRiskParams({ reserveBuffer: 1_050_000, maxDailyRedeem: 0, redeemWindowOpen: 0, redeemWindowDuration: 0 }));
_setSlotRiskParams(C.SLOT_5Y,  SlotRiskParams({ reserveBuffer: 1_080_000, maxDailyRedeem: 0, redeemWindowOpen: 0, redeemWindowDuration: 0 }));
_setSlotRiskParams(C.SLOT_10Y, SlotRiskParams({ reserveBuffer: 1_120_000, maxDailyRedeem: 0, redeemWindowOpen: 0, redeemWindowDuration: 0 }));
_setSlotRiskParams(C.SLOT_30Y, SlotRiskParams({ reserveBuffer: 1_200_000, maxDailyRedeem: 0, redeemWindowOpen: 0, redeemWindowDuration: 0 }));
```

---

## 10. Funzioni V2

### 10.1 Curve Blocking automatico

**`_validateCurveRegime(uint256 slot)`**

Blocca mint su slot 10Y e 30Y quando `yield2Y > yield10Y` con spread superiore a una soglia configurabile. Richiede definizione governance della soglia di attivazione e meccanismo di reset automatico.

### 10.2 Mint Rate Limiting

**`_validateMintRateLimit(uint256 slot, uint256 mintValue)`**

Stesso pattern del redeem rate limit. Rilevante quando il protocollo aggiunge liquidità secondaria o AMM.

### 10.3 Dynamic Reserve Buffer → ✅ Implementato in sezione 6.10

Buffer dinamico basato sulla shape della curva dei rendimenti (inversione 2s10s). Moltiplicatore graduale da 1.1x a 1.5x, con protezioni complete contro dati non inizializzati o corrotti. Dichiarato `virtual` per override in V2 con logica più ricca (rolling volatility, etc.).

### 10.4 Solvency Invariant globale → ✅ Implementato in sezione 6.11

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

// Test reserve coverage con dynamic buffer
// Imposta reserves a 900.000e18, liabilities a 850.000e18, buffer 1_120_000 (112%)
// Curva normale: required = 850.000 * 1_120_000 / 1_000_000 = 952.000 > 900.000 → revert
// Curva invertita spread 50bps (2Y frozen=false, 10Y frozen=false):
//   dynamicMultiplier = 1_200_000 (1.2x), effectiveBuffer = 1_120_000 * 1_200_000 / 1_000_000 = 1_344_000
//   required = 850.000 * 1_344_000 / 1_000_000 = 1_142_400 → revert con buffer maggiore
```
