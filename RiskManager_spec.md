# RiskManager — Specifica Tecnica

## Indice
1. [Scopo e responsabilità](#1-scopo-e-responsabilità)
2. [Posizione nell'architettura](#2-posizione-nellarchitettura)
3. [Dati necessari](#3-dati-necessari)
4. [Storage](#4-storage)
5. [Dipendenze esterne](#5-dipendenze-esterne)
6. [Funzioni V1](#6-funzioni-v1)
7. [Integrazione con TreasuryBondToken](#7-integrazione-con-treasurybondtoken)
8. [Custom Errors](#8-custom-errors)
9. [Funzioni V2](#9-funzioni-v2)

---

## 1. Scopo e responsabilità

`RiskManager` è un contratto **abstract** che implementa tutti i controlli di rischio finanziario del protocollo TreasuryFi. Non gestisce compliance (quella è responsabilità di `ERC3643`) e non gestisce lo stato dei token (quello è responsabilità di `ERC3525`).

Il RiskManager è il **motore di rischio on-chain** equivalente a un fixed-income risk engine tradizionale. Deve garantire:

- Che i dati oracle siano validi prima di qualsiasi operazione
- Che le riserve coprano sempre le liability
- Che singole operazioni non destabilizzino il protocollo
- Che ogni slot sia isolato dagli altri in caso di problemi

### Cosa NON fa
- Non gestisce identità o compliance (→ ERC3643)
- Non gestisce la logica dei token ERC3525 (→ ERC3525)
- Non gestisce i fee di business (→ TreasuryBondToken)
- Non gestisce pause globali (→ ERC3643)

---

## 2. Posizione nell'architettura

```
TreasuryBondToken is ERC3643, ERC3525, RiskManager, AccessControl
```

### Linearizzazione MRO risultante
```
TreasuryBondToken → ERC3643 → ERC3525 → RiskManager → AccessControl
```

### Flusso di chiamata in _beforeMint
```
TreasuryBondToken._beforeValueTransfer()
    └── super() → ERC3643._beforeValueTransfer()   [compliance]
                      └── super() → ERC3525 [vuoto]

    └── _beforeMint()
            ├── _validateSlotNotFrozen()            [RiskManager]
            ├── _validateOracleData()               [RiskManager]
            ├── _validateYieldShock()               [RiskManager]
            ├── _validateMintReserves()             [RiskManager]
            └── _validateSlotCap()                  [RiskManager]
```

### Flusso di chiamata in _beforeBurn (redeem)
```
    └── _beforeBurn()
            ├── _validateSlotNotFrozen()            [RiskManager]
            ├── _validateOracleData()               [RiskManager]
            ├── _validateLockPeriod()               [RiskManager]
            ├── _validateRedeemLiquidity()          [RiskManager]
            └── _validateRedeemRateLimit()          [RiskManager]
```

---

## 3. Dati necessari

Per implementare le funzioni V1, il RiskManager ha bisogno di accedere a:

### Dal BondOracle
| Dato | Perché serve | Come ottenerlo |
|---|---|---|
| `yield attuale per slot` | shock filter, bounds check | `i_bondOracle.getYield(slot)` |
| `isStale()` | freshness check | `i_bondOracle.isStale()` |

### Dal ReservesOracle
| Dato | Perché serve | Come ottenerlo |
|---|---|---|
| `USD value per slot` | reserve coverage check | `i_reservesOracle.getUsdValue(slot)` |
| `total USD value` | solvency check globale | `i_reservesOracle.getTotalUsdValue()` |
| `isStale()` | freshness check | `i_reservesOracle.isStale()` |

### Da TreasuryBondToken (via dipendenza astratta)
| Dato | Perché serve | Come ottenerlo |
|---|---|---|
| `valore del token` | frozen value check, redeem validation | `balanceOf(tokenId)` — dichiarata virtual |
| `liabilities per slot` | reserve coverage | `s_totalValuePerSlot[slot]` — storage condiviso |
| `PositionData del token` | lock period check | `s_fromIdToPositionData[tokenId]` — storage condiviso |

---

## 4. Storage

Il RiskManager possiede il seguente storage. Tutto `internal` per essere accessibile al figlio.

```solidity
// ─── Parametri per slot ──────────────────────────────────────────────────────

struct SlotRiskParams {
    uint256 maxSupply;      // valore massimo mintabile per slot (in USDC decimals)
    uint256 lockPeriod;     // secondi di lock prima del redeem (es. 30 giorni = 30 days)
    uint256 reserveBuffer;  // % di overcollateral richiesta (es. 110 = 110%, base 100)
    uint256 maxDailyRedeem; // massimo valore riscattabile in 24h per slot
}
mapping(uint256 => SlotRiskParams) internal s_slotRiskParams;

// ─── Shock filter ────────────────────────────────────────────────────────────

// ultimo yield valido registrato per slot, usato per calcolare il delta
mapping(uint256 => uint64) internal s_lastValidYield;

// ─── Rate limiting redeem ────────────────────────────────────────────────────

// volume di redeem accumulato oggi per slot
mapping(uint256 => uint256) internal s_dailyRedeemVolume;

// timestamp dell'ultimo reset del contatore giornaliero per slot
mapping(uint256 => uint256) internal s_dailyRedeemWindowStart;

// ─── Slot freeze ─────────────────────────────────────────────────────────────

// se true, il slot è bloccato per qualsiasi operazione (mint e redeem)
mapping(uint256 => bool) internal s_slotFrozen;

// ─── Costanti ────────────────────────────────────────────────────────────────

// delta massimo accettabile tra due yield consecutivi (in basis points)
// es. 500 = 5% — se yield passa da 4% a 9% in un update, viene rifiutato
uint64 internal constant MAX_YIELD_DELTA = 500;

// yield massimo accettabile in assoluto (in basis points)
// es. 2000 = 20%
uint64 internal constant MAX_YIELD = 2000;

// yield minimo accettabile (deve essere > 0)
uint64 internal constant MIN_YIELD = 1;
```

---

## 5. Dipendenze esterne

Il RiskManager è `abstract` e non eredita `ERC3525`. Per accedere ai dati dei token dichiara dipendenze virtuali che il contratto figlio risolve:

```solidity
// dichiarate in RiskManager, implementate da ERC3525 nel figlio
function balanceOf(uint256 tokenId) public view virtual returns (uint256);
```

Per gli oracle, il RiskManager non li conosce direttamente — li riceve come parametro nelle funzioni di validazione oppure il figlio li passa attraverso funzioni `virtual` da fare override:

```solidity
// il figlio implementa questi due getter che wrappano gli oracle immutabili
function _getYieldForSlot(uint256 slot) internal view virtual returns (uint64);
function _getReserveForSlot(uint256 slot) internal view virtual returns (uint256);
function _getTotalReserves() internal view virtual returns (uint256);
function _areOraclesStale() internal view virtual returns (bool yieldStale, bool reserveStale);
```

Questo pattern mantiene il RiskManager testabile in isolamento senza dover deployare gli oracle reali.

---

## 6. Funzioni V1

### 6.1 Admin — configurazione parametri slot

**`_setSlotRiskParams(uint256 slot, SlotRiskParams memory params)`**
- Imposta i parametri di rischio per uno slot specifico
- Chiamata dal costruttore di TreasuryBondToken per ogni slot (2Y, 5Y, 10Y, 30Y)
- Verifica che `maxSupply > 0`, `reserveBuffer >= 100`, `lockPeriod` coerente con la maturity dello slot
- Accessibile solo con `OWNER_ROLE` quando esposta come funzione pubblica nel figlio

**`_freezeSlot(uint256 slot)`** / **`_unfreezeSlot(uint256 slot)`**
- Blocca/sblocca tutte le operazioni su uno slot specifico
- Da chiamare manualmente dall'admin in caso di anomalia rilevata
- Emette evento `SlotFrozen(slot)` / `SlotUnfrozen(slot)`
- Non sostituisce il pause globale di ERC3643 — quello blocca tutto, questo blocca un singolo slot

---

### 6.2 Oracle Validation

**`_validateOracleData(uint256 slot)`**

Scopo: garantire che i dati oracle siano freschi e nel range accettabile prima di qualsiasi operazione.

Logica:
1. Chiama `_areOraclesStale()` → se uno dei due oracle è stale, revert
2. Legge yield corrente via `_getYieldForSlot(slot)`
3. Verifica `yield >= MIN_YIELD` e `yield <= MAX_YIELD`
4. Se i bound non sono rispettati → revert `RiskManager__YieldOutOfBounds`

Chiamata in: `_beforeMint`, `_beforeBurn`

---

**`_validateYieldShock(uint256 slot)`**

Scopo: proteggere il protocollo da errori oracle che producono valori anomali rispetto all'ultimo dato valido.

Logica:
1. Legge `prevYield = s_lastValidYield[slot]`
2. Se `prevYield == 0` (primo aggiornamento) → skip check, salva il valore corrente e return
3. Calcola `delta = |currentYield - prevYield|`
4. Se `delta > MAX_YIELD_DELTA` → revert `RiskManager__YieldShockDetected`
5. Aggiorna `s_lastValidYield[slot] = currentYield`

Nota importante: questa funzione ha side effect (aggiorna storage) quindi non è `view`. Va chiamata con attenzione nel flusso — solo quando si è certi che l'operazione andrà a buon fine (dopo tutti i check view). Valutare se aggiornarla in `_afterValueTransfer` invece che in `_before`.

Chiamata in: `_beforeMint` (dopo `_validateOracleData`)

---

### 6.3 Reserve Coverage

**`_validateMintReserves(uint256 slot, uint256 mintValue)`**

Scopo: garantire che le riserve disponibili per lo slot coprano le liability esistenti più il nuovo mint.

Logica:
1. Legge `reserves = _getReserveForSlot(slot)`
2. Legge `liabilities = s_totalValuePerSlot[slot]` (storage condiviso con TreasuryBondToken)
3. Legge `buffer = s_slotRiskParams[slot].reserveBuffer`
4. Calcola `requiredReserves = (liabilities + mintValue) * buffer / 100`
5. Se `reserves < requiredReserves` → revert `RiskManager__InsufficientReserves`

Nota sul buffer: con `reserveBuffer = 110`, il protocollo richiede il 110% di copertura. Se le liability sono 1000 USDC e si vuole mintare per altri 100, servono almeno 1210 USDC in riserva.

Chiamata in: `_beforeMint`

---

**`_validateRedeemLiquidity(uint256 slot, uint256 payout)`**

Scopo: garantire che ci sia liquidità sufficiente per pagare il redeem corrente.

Logica:
1. Legge `availableLiquidity = _getReserveForSlot(slot)`
2. Se `availableLiquidity < payout` → revert `RiskManager__InsufficientLiquidity`

Nota: `payout` è il valore in USDC che il protocollo deve trasferire all'utente, già calcolato (al netto delle fee) prima di chiamare questa funzione.

Chiamata in: `_beforeBurn`

---

### 6.4 Slot Controls

**`_validateSlotNotFrozen(uint256 slot)`**

Scopo: bloccare qualsiasi operazione su uno slot marcato come frozen.

Logica:
1. Se `s_slotFrozen[slot] == true` → revert `RiskManager__SlotFrozen`

Chiamata in: `_beforeMint`, `_beforeBurn`, `_beforeTransfer`

---

**`_validateSlotCap(uint256 slot, uint256 mintValue)`**

Scopo: impedire che il valore totale mintato per uno slot superi il cap configurato.

Logica:
1. Legge `cap = s_slotRiskParams[slot].maxSupply`
2. Legge `current = s_totalValuePerSlot[slot]`
3. Se `current + mintValue > cap` → revert `RiskManager__SlotCapExceeded`

Chiamata in: `_beforeMint`

---

### 6.5 Lock Period e Redeem

**`_validateLockPeriod(uint256 tokenId)`**

Scopo: impedire il redeem prima che sia trascorso il lock period dall'apertura della posizione.

Logica:
1. Legge `positionData = s_fromIdToPositionData[tokenId]` (storage condiviso)
2. Legge `lockPeriod = s_slotRiskParams[slotOf(tokenId)].lockPeriod`
3. Calcola `unlockTime = positionData.positionMintTimestamp + lockPeriod`
4. Se `block.timestamp < unlockTime` → revert `RiskManager__PositionStillLocked` con `unlockTime`

Chiamata in: `_beforeBurn`

---

**`_validateRedeemRateLimit(uint256 slot, uint256 redeemValue)`**

Scopo: proteggere il protocollo da bank run limitando il volume di redeem giornaliero per slot.

Logica:
1. Se `block.timestamp > s_dailyRedeemWindowStart[slot] + 1 days`:
   - reset `s_dailyRedeemVolume[slot] = 0`
   - aggiorna `s_dailyRedeemWindowStart[slot] = block.timestamp`
2. Legge `maxDaily = s_slotRiskParams[slot].maxDailyRedeem`
3. Se `s_dailyRedeemVolume[slot] + redeemValue > maxDaily` → revert `RiskManager__DailyRedeemLimitExceeded`
4. Incrementa `s_dailyRedeemVolume[slot] += redeemValue`

Nota: come `_validateYieldShock`, questa funzione ha side effect. Va chiamata solo quando si è certi che il burn andrà a buon fine.

Chiamata in: `_beforeBurn`

---

### 6.6 Fee Sanity (statica)

**`_validateFeeConfiguration(uint256 fee, uint256 slot)`**

Scopo: verificare al momento della configurazione che le fee siano matematicamente sensate.

Logica:
1. Se `fee >= PERCENTAGE_PRECISION` (>= 100%) → revert `RiskManager__FeeExceedsMax`
2. Legge `expectedMinYield = MIN_YIELD * 100` (conversione basis points → stessa scala delle fee)
3. Se `fee > expectedMinYield` → revert `RiskManager__FeeExceedsExpectedYield`

Chiamata in: setter delle fee in TreasuryBondToken, non nel flusso di ogni operazione.

---

### 6.7 Yield Curve Detection (solo detection, no blocking)

**`_detectCurveInversion()`** → `returns (bool isInverted)`

Scopo: rilevare se la curva dei rendimenti è invertita (2Y > 10Y), condizione che segnala un cambio di regime di rischio.

Logica:
1. Legge `yield2Y = _getYieldForSlot(SLOT_2Y)`
2. Legge `yield10Y = _getYieldForSlot(SLOT_10Y)`
3. Return `yield2Y > yield10Y`

Nota: questa funzione è `view` e non blocca nulla. Va usata per:
- Emettere un evento `CurveInversionDetected()` in `_afterValueTransfer` o su chiamata admin
- Consentire agli admin di decidere se congelare manualmente gli slot con duration alta

Non implementare blocco automatico in V1 — richiede governance parametri che non sono ancora definiti.

---

## 7. Integrazione con TreasuryBondToken

### Come vengono chiamate le funzioni

```solidity
// TreasuryBondToken._beforeMint()
function _beforeMint(address _to, uint256 _toTokenId, uint256 _slot, uint256 _value) internal {
    _validateSlotNotFrozen(_slot);      // RiskManager
    _validateOracleData(_slot);         // RiskManager
    _validateYieldShock(_slot);         // RiskManager — ha side effect
    _validateMintReserves(_slot, _value); // RiskManager
    _validateSlotCap(_slot, _value);    // RiskManager
}

// TreasuryBondToken._beforeBurn()
function _beforeBurn(address _from, uint256 _fromTokenId, uint256 _slot, uint256 _value) internal {
    _validateSlotNotFrozen(_slot);              // RiskManager
    _validateOracleData(_slot);                 // RiskManager
    _validateLockPeriod(_fromTokenId);          // RiskManager
    _validateRedeemLiquidity(_slot, payout);    // RiskManager — payout calcolato prima
    _validateRedeemRateLimit(_slot, _value);    // RiskManager — ha side effect
}
```

### Override delle dipendenze astratte in TreasuryBondToken

```solidity
function _getYieldForSlot(uint256 slot) internal view override returns (uint64) {
    return i_bondOracle.getYield(slot);
}

function _getReserveForSlot(uint256 slot) internal view override returns (uint256) {
    return i_reservesOracle.getUsdValue(slot);
}

function _getTotalReserves() internal view override returns (uint256) {
    return i_reservesOracle.getTotalUsdValue();
}

function _areOraclesStale() internal view override returns (bool yieldStale, bool reserveStale) {
    yieldStale = i_bondOracle.isStale();
    reserveStale = i_reservesOracle.isStale();
}
```

---

## 8. Custom Errors

```solidity
error RiskManager__SlotFrozen(uint256 slot);
error RiskManager__OracleStale(string oracleName);
error RiskManager__YieldOutOfBounds(uint256 slot, uint64 yield);
error RiskManager__YieldShockDetected(uint256 slot, uint64 prev, uint64 current, uint64 delta);
error RiskManager__InsufficientReserves(uint256 slot, uint256 available, uint256 required);
error RiskManager__InsufficientLiquidity(uint256 slot, uint256 available, uint256 required);
error RiskManager__SlotCapExceeded(uint256 slot, uint256 current, uint256 cap);
error RiskManager__PositionStillLocked(uint256 tokenId, uint256 unlockTime);
error RiskManager__DailyRedeemLimitExceeded(uint256 slot, uint256 attempted, uint256 remaining);
error RiskManager__FeeExceedsMax();
error RiskManager__FeeExceedsExpectedYield();
error RiskManager__InvalidSlotParams();
```

### Eventi

```solidity
event SlotFrozen(uint256 indexed slot, address indexed triggeredBy);
event SlotUnfrozen(uint256 indexed slot, address indexed triggeredBy);
event SlotRiskParamsUpdated(uint256 indexed slot, SlotRiskParams params);
event CurveInversionDetected(uint64 yield2Y, uint64 yield10Y, uint256 timestamp);
event YieldShockPrevented(uint256 indexed slot, uint64 prevYield, uint64 attemptedYield);
```

---

## 9. Funzioni V2

Queste funzioni non vanno implementate in V1 ma il contratto deve essere progettato per accoglierle senza refactoring strutturale.

### 9.1 Curve Blocking automatico

**`_validateCurveRegime(uint256 slot)`**

Blocca mint su slot con duration alta (10Y, 30Y) quando la curva è invertita.

Requisiti prima di implementare:
- Definire quale soglia di inversione attiva il blocco (es. spread 2Y-10Y > 50bps)
- Definire da chi può essere overriddato (governance? timelock?)
- Definire per quanto tempo rimane attivo il blocco prima di un reset automatico

---

### 9.2 Mint Rate Limiting

**`_validateMintRateLimit(uint256 slot, uint256 mintValue)`**

Limita il volume di mint giornaliero per slot. Stesso pattern del redeem rate limit.

Perché in V2: il rischio che il mint rate limit tenta di coprire (whale che distorce composizione pool) non è presente nel modello attuale dove il NAV viene dall'oracle e non dalla composizione. Diventa rilevante se in futuro il protocollo aggiunge liquidità secondaria o AMM.

---

### 9.3 Dynamic Fees

**`_calculateDynamicFeeMultiplier(uint256 slot)`** → `returns (uint256)`

Moltiplicatore applicato alle fee base in funzione di:
- Shape della curva (invertita → fee più alte su slot lunghi)
- Volatilità implicita dai movimenti recenti di yield
- Pressione di redeem (se `dailyRedeemVolume` è alto → fee di uscita più alte)

In V1 questa funzione va dichiarata `virtual` e restituisce `PERCENTAGE_PRECISION` (moltiplicatore 1x, nessun effetto). In V2 si fa override con la logica reale senza toccare il flusso di calcolo fee.

---

### 9.4 Fee Sanity Runtime

**`_validateYieldDistribution(uint256 tokenId, uint256 yieldToClaim)`**

Verifica che lo yield che si sta per distribuire non superi lo yield effettivamente generato dalla posizione secondo l'oracle.

Requisiti prima di implementare:
- Tracking dello yield distribuito accumulato per tokenId
- Calcolo dello yield teorico massimo basato su `interestRate`, `positionMintTimestamp` e yield oracle
- Confronto tra i due con tolleranza per arrotondamenti

---

### 9.5 Solvency Invariant globale

**`_assertSolvency()`**

Verifica che `totalReserves >= sum(s_totalValuePerSlot[*])` su tutti gli slot.

Perché in V2: richiede iterazione su tutti gli slot ad ogni operazione — costoso in gas. Va implementato come check su chiamata esplicita admin o tramite monitoring off-chain con trigger on-chain solo in caso di violazione.

---

## Note implementative finali

**Ordine delle chiamate con side effect**

Le funzioni `_validateYieldShock` e `_validateRedeemRateLimit` aggiornano storage. Questo le rende rischiose in `_before` — se una chiamata successiva nel flusso fa revert, lo storage viene comunque modificato. Valutare di spostare queste due funzioni in `_afterValueTransfer` dove si è certi che l'operazione è andata a buon fine.

**Separazione delle unità**

Attenzione alle unità di misura quando si confrontano valori:
- Yield da BondOracle: `uint64` in basis points (400 = 4.00%)
- USD values da ReservesOracle: `uint256` con 8 decimals
- USDC amounts: `uint256` con 6 decimals
- Fee percentages in TreasuryBondToken: `uint256` scalate per `PERCENTAGE_PRECISION`

Prima di qualsiasi confronto cross-oracle verificare sempre che le unità siano allineate.

**Testing**

Il pattern delle dipendenze astratte (`_getYieldForSlot`, `_getReserveForSlot`, ecc.) consente di testare il RiskManager in isolamento con mock che restituiscono valori controllati, senza deployare BondOracle e ReservesOracle nei test unitari.
