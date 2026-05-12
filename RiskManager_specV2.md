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
            ├── _validateRedemptionWindow()         [RiskManager]
            ├── _validateLockPeriod()               [RiskManager]
            ├── _validateRedeemLiquidity()          [RiskManager]
            └── _validateRedeemRateLimit()          [RiskManager]
```

---

## 3. Dati necessari

Il RiskManager non legge mai gli oracle direttamente nelle transazioni utente. Lavora su una **cache interna validata** (`s_lastValidYields`, `s_lastValidReserves`) che viene aggiornata da Chainlink Automation.

### Flusso dati
```
Chainlink Automation
    └── BondAutomation.performUpkeep()
            └── BondFunctionsConsumer → Chainlink Functions → BondOracle
                    └── TreasuryBondToken._updateYieldsValues()
                            ├── shock detection per slot
                            ├── aggiornamento s_lastValidYields (cache)
                            └── freeze slot anomali

Chainlink Automation
    └── ReservesAutomation.performUpkeep()
            └── ReservesFunctionsConsumer → Chainlink Functions → ReservesOracle
                    └── TreasuryBondToken._updateReservesValues()
                            ├── shock detection per slot (bond value + cash buffer)
                            ├── aggiornamento s_lastValidReserves (cache)
                            └── freeze slot anomali
```

### Per transazione utente (mint/burn/claimYield)
| Dato | Quando | Come |
|---|---|---|
| `isStale()` yields | per-tx (guardia finale) | `i_yieldsOracle.isStale()` |
| `isStale()` reserves | per-tx (guardia finale) | `i_reservesOracle.isStale()` |
| `slot frozen` | per-tx | `s_slotState[slot].frozen` |
| yield corrente | letto dalla cache | `s_lastValidYields` |
| reserve corrente | letta dalla cache | `s_lastValidReserves` |
| liabilities per slot | storage condiviso | `s_totalLiabilitiesPerSlot[slot]` |

---

## 4. Storage

Il RiskManager possiede il seguente storage. Tutto `internal` per essere accessibile al figlio.

```solidity
// ─── Immutabili oracle e automation ─────────────────────────────────────────

IBondAutomation    internal immutable i_yieldsAutomation;
IReservesAutomation internal immutable i_reservesAutomation;
IReservesOracle    internal immutable i_reservesOracle;
IBondOracle        internal immutable i_yieldsOracle;
uint256            internal immutable i_gracePeriod;  // da i_yieldsAutomation
uint256            internal immutable i_interval;     // da i_yieldsAutomation

// ─── Timestamp ultimo trigger manuale ────────────────────────────────────────

uint256 internal s_lastUpkeepTriggerReserves;
uint256 internal s_lastUpkeepTriggerYields;

// ─── Cache dati validati (aggiornata da automation) ───────────────────────────

// Cache completa yields per tutti e 4 gli slot — consumata da _getLastValidYields()
BondYieldsResponse internal s_lastValidYields;

// Cache completa reserves per tutti e 4 gli slot — consumata da _getLastValidReserves()
ReservesResponse   internal s_lastValidReserves;

// ─── Shock filter (valori precedenti per calcolo delta) ──────────────────────

// Ultimo yield accettato per slot — serve solo per il check shock durante l'aggiornamento
mapping(uint256 => uint256) internal s_lastValidYieldPerSlot;

// Ultimo valore bond USD accettato per slot — shock detection reserves
mapping(uint256 => uint256) internal s_lastValidReservePerSlot;

// Ultimo cash buffer USD accettato per slot — shock detection cash
mapping(uint256 => uint256) internal s_lastValidCashBufferPerSlot;

// ─── Slot freeze state (packed: 3 bool in 1 storage slot) ────────────────────

struct SlotFreezeState {
    bool frozenByYields;    // anomalia rilevata nel feed yields
    bool frozenByReserves;  // anomalia rilevata nel feed reserves
    bool frozen;            // risultante — unico campo letto nelle tx utente
}
mapping(uint256 => SlotFreezeState) internal s_slotState;

// ─── Liabilities per slot ────────────────────────────────────────────────────

// Valore totale delle posizioni aperte per slot, in USDC equivalente
// Aggiornato su mint (+value), burn (-value), yield claim
mapping(uint256 => uint256) private s_totalLiabilitiesPerSlot;

// ─── Costanti ────────────────────────────────────────────────────────────────

uint256 internal constant MAX_YIELD_SHOCK_BPS   = 5  * PERCENTAGE_PRECISION; // 5%
uint256 internal constant MAX_YIELD             = 20 * PERCENTAGE_PRECISION; // 20% bounds assoluto
uint256 internal constant MAX_RESERVES_SHOCK_BPS = 30 * PERCENTAGE_PRECISION; // 30%
```

---

## 5. Dipendenze esterne

Il RiskManager detiene **direttamente** le reference agli oracle e ai contratti automation come immutabili. Non usa funzioni virtual astratte — gli oracle sono conosciuti al deploy e passati al costruttore.

```solidity
constructor(
    address _yieldsAutomation,
    address _reservesAutomation,
    address _reservesOracle,
    address _yieldsOracle
) {
    i_yieldsAutomation   = IBondAutomation(_yieldsAutomation);
    i_reservesAutomation = IReservesAutomation(_reservesAutomation);
    i_reservesOracle     = IReservesOracle(_reservesOracle);
    i_yieldsOracle       = IBondOracle(_yieldsOracle);
    (i_interval, i_gracePeriod, ) = i_yieldsAutomation.getAllUpkeepInfo();
}
```

I check di validità oracle nelle tx utente usano `i_yieldsOracle.isStale()` e `i_reservesOracle.isStale()` direttamente — nessun layer di indirection virtual.

**Nota per i test**: poiché gli oracle sono immutabili, i test unitari del RiskManager devono deployare mock degli oracle o usare Foundry `vm.mockCall` sulle interfacce.

---

## 6. Funzioni V1

> **Stato implementazione**: le sezioni 6.1–6.3 sono completamente implementate. Le sezioni 6.4–6.8 sono stub nel contratto (commenti presenti, logica da completare).

### 6.1 Cache update — yields

**`_updateYieldsValues()`** (internal)

Point of entry chiamato dall'automation o manualmente. Coordina update e freeze:

```
_updateYieldsValues()
    └── _updateLastValidYields()
            ├── Controlla se il timestamp oracle è più recente di s_lastValidYields.timestamp
            │       └── Se no → return (false, false, false, false)  [nessuna azione]
            ├── Legge BondYieldsResponse da i_yieldsOracle.getAllYields()
            ├── _validateAndUpdateLastValidYield() per ogni slot
            │       ├── bounds check (0 < yield ≤ MAX_YIELD)
            │       ├── shock check (delta con s_lastValidYieldPerSlot[slot] ≤ MAX_YIELD_SHOCK_BPS)
            │       └── se ok: aggiorna s_lastValidYieldPerSlot[slot], return false
            │           se anomalia: emit evento, return true (freezeSlot)
            ├── Se tutti ok → s_lastValidYields = newResponse (aggiornamento atomico)
            └── Se almeno uno anomalo → mixed response:
                    ├── slot sani ricevono il nuovo valore
                    ├── slot frozen mantengono il vecchio valore
                    └── timestamp = cached.timestamp (non si marca come fresco)
    └── _setYieldsSlotFrozen() per ogni slot (aggiorna SlotFreezeState)
```

**`_triggerYieldsUpkeep()`** (internal)

Permette all'admin del contratto figlio di forzare manualmente un ciclo di automation, con protezione da spam tramite `i_interval + i_gracePeriod`:

1. Se `block.timestamp <= s_lastUpkeepTriggerYields + i_interval + i_gracePeriod` → revert `AutomationGracePeriodNotElapsed`
2. Chiama `i_yieldsAutomation.checkUpkeep("")` — se upkeep non necessario, non esegue
3. Se necessario: `i_yieldsAutomation.performUpkeep("")` + aggiorna `s_lastUpkeepTriggerYields`

---

### 6.2 Cache update — reserves

**`_updateReservesValues()`** (internal)

Stesso pattern di `_updateYieldsValues`. Valida due metriche per slot:
- bond USD value (`_validateAndUpdateLastValidReserve`)
- cash buffer USD value (`_validateAndUpdateLastValidCashBuffer`): solo se il bond value era valido

Logica mixed response:
- `cashBufferUsdTotalValue`: se **almeno uno** slot è frozen, tieni il valore cached
- `totalUsdBondsValue` / `totalUsdPortfolioValue`: solo se **tutti** gli slot sono frozen, tieni cached; altrimenti usa il valore dell'oracle (già ricalcolato off-chain)

**`_triggerReservesUpkeep()`** (internal) — stesso pattern di `_triggerYieldsUpkeep`.

---

### 6.3 Slot freeze management

**`_setSlotFrozenOnMainContract(uint256 _slot, bool _frozen)`** (internal)

Permette all'admin del contratto figlio di forzare manualmente il freeze/unfreeze di uno slot.
- Legge `s_slotState[_slot]` (1 SLOAD, ottiene tutti e 3 i bool)
- Se già nello stato richiesto → revert `SlotAlreadyInState`
- Imposta entrambi `frozenByYields` e `frozenByReserves` al valore richiesto
- Aggiorna `frozen` ed emette `SlotFrozen` / `SlotUnfrozen`

**`_getLastValidYields(uint256 _slot)`** (internal view)

Getter sicuro per i consumer interni (TreasuryBondToken):
1. `isStale()` yields → revert se stale
2. `s_slotState[_slot].frozen` → revert se frozen
3. Return `s_lastValidYields`

**`_getLastValidReserves(uint256 _slot)`** (internal view) — stesso pattern per reserves.

---

### 6.4 Lifecycle hooks (parzialmente implementati)

I tre lifecycle hook sono presenti e chiamati dal contratto figlio. Ogni hook:
- ✅ Controlla `isStale()` su entrambi gli oracle (guardia residuale)
- ✅ Controlla `s_slotState[_slot].frozen`
- ✅ Legge `s_lastValidYields` / `s_lastValidReserves` dalla cache
- ✅ Aggiorna `s_totalLiabilitiesPerSlot` (mint: +value, burn: -value)
- ⚠️ Check reserve coverage e liquidity: **stub** — la logica è segnata con commento ma non implementata

```solidity
function _riskManagerBeforeMint(uint256 _slot, uint256 _value) internal
function _riskManagerBeforeBurn(uint256 _slot, uint256 _value) internal
function _riskManagerBeforeClaimingYield(uint256 _slot, uint256 _value) internal
```

---

### 6.5 Reserve coverage (stub da completare)

**`_validateMintReserves(uint256 _slot, uint256 _mintValue)`**

Da implementare dentro `_riskManagerBeforeMint` (step 4, attualmente vuoto).

Logica prevista:
1. Legge `reserves = s_lastValidReserves` dalla cache (già caricata nel hook)
2. Legge `liabilities = s_totalLiabilitiesPerSlot[_slot]`
3. Confronta `reserves.slotUsdBondsValue[slot]` con `liabilities + _mintValue` applicando un buffer configurabile
4. Se insufficiente → revert `RiskManager__InsufficientReserves`

**`_validateRedeemLiquidity(uint256 _slot, uint256 _payout)`**

Da implementare dentro `_riskManagerBeforeBurn` (step 4, attualmente vuoto).

`_payout` è il valore USDC al netto delle fee, già calcolato da TreasuryBondToken prima di chiamare il hook.

---

### 6.6 Lock period, redemption window, rate limiting (stub da completare)

Vedi spec originale sezioni 6.5 e 6.6. Nessuna di queste feature è presente nel contratto corrente.
Da implementare come funzioni private richiamate dai lifecycle hook.

---

### 6.7 Fee Sanity (stub da completare)

Vedi spec originale sezione 6.7.

---

### 6.8 Yield Curve Detection (stub da completare)

Vedi spec originale sezione 6.8.

---

## 7. Integrazione con TreasuryBondToken

### Come vengono chiamate le funzioni

```solidity
// TreasuryBondToken._beforeMint()
function _beforeMint(address _to, uint256 _toTokenId, uint256 _slot, uint256 _value) internal {
    _riskManagerBeforeMint(_slot, _value);   // RiskManager: isStale + frozen + liabilities update
    // reserve coverage check — stub da completare in RiskManager
}

// TreasuryBondToken._closePositionValue() / closePosition()
function _closePosition(...) internal {
    _riskManagerBeforeBurn(_slot, _value);   // RiskManager: isStale + frozen + liabilities update
    // liquidity check — stub da completare in RiskManager
}

// TreasuryBondToken.claimYield()
function claimYield(...) external {
    _riskManagerBeforeClaimingYield(_slot, yieldValue);  // RiskManager: isStale + frozen
}
```

### Consumer della cache

```solidity
// TreasuryBondToken usa la cache per leggere yield e reserves
BondYieldsResponse memory yields   = _getLastValidYields(_slot);    // isStale + frozen + cache
ReservesResponse memory reserves   = _getLastValidReserves(_slot);  // isStale + frozen + cache
```

### Aggiornamento cache dal contratto figlio

`TreasuryBondToken` espone funzioni pubbliche (con access control) che chiamano:

```solidity
_updateYieldsValues();    // chiamato da TreasuryBondToken.updateYields() con OPERATOR_ROLE
_updateReservesValues();  // chiamato da TreasuryBondToken.updateReserves() con OPERATOR_ROLE
_triggerYieldsUpkeep();   // chiamato da TreasuryBondToken.triggerYieldsUpkeep() con OWNER_ROLE
_triggerReservesUpkeep(); // chiamato da TreasuryBondToken.triggerReservesUpkeep() con OWNER_ROLE
_setSlotFrozenOnMainContract(_slot, _frozen); // con OWNER_ROLE
```

---

## 8. Custom Errors

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

// Da aggiungere con i stub da completare
error RiskManager__InsufficientReserves(uint256 slot, uint256 available, uint256 required);
error RiskManager__InsufficientLiquidity(uint256 slot, uint256 available, uint256 required);
error RiskManager__PositionStillLocked(uint256 tokenId, uint256 unlockTime);
error RiskManager__DailyRedeemLimitExceeded(uint256 slot, uint256 attempted, uint256 remaining);
error RiskManager__RedemptionWindowClosed(uint256 slot, uint256 windowStart, uint256 windowEnd, uint256 currentSecondInWeek);
error RiskManager__SlotCapExceeded(uint256 slot, uint256 current, uint256 cap);
```

### Eventi implementati

```solidity
event SlotFrozen(uint256 indexed slot);
event SlotUnfrozen(uint256 indexed slot);
event InvalidYield(uint256 indexed slot, uint256 yield);
event ExcessiveYieldShock(uint256 indexed slot, uint256 shock);
event InvalidReserve(uint256 indexed slot, uint256 reserve);
event ExcessiveReserveShock(uint256 indexed slot, uint256 shock);
event InvalidCashBuffer(uint256 indexed slot, uint256 cashBuffer);
event ExcessiveCashBufferShock(uint256 indexed slot, uint256 shock);
```

---

## 9. Funzioni V2

Queste funzioni non vanno implementate in V1 ma il contratto deve essere progettato per accoglierle senza refactoring strutturale.

> **Da completare in V1 prima** (stub presenti nel contratto):
> - Reserve coverage check in `_riskManagerBeforeMint`
> - Liquidity check in `_riskManagerBeforeBurn`
> - Lock period validation
> - Redemption window
> - Daily redeem rate limiting
> - Slot cap (`maxSupply`)

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

### 9.6 Redemption Window bisettimanale

La struttura attuale con `block.timestamp % 7 days` supporta solo finestre settimanali. Per lo slot 30Y è stato consigliato un ciclo bisettimanale.

Per supportarlo senza refactoring aggiungere in V2 un campo `windowCycleDays` a `SlotRiskParams` e modificare `_validateRedemptionWindow` per usare `block.timestamp % (windowCycleDays * 1 days)` invece di `% 7 days`.

In V1 il campo non esiste e il ciclo è sempre settimanale. Lo slot 30Y può usare una finestra di 4 ore settimanali come approssimazione accettabile.

---

## Note implementative finali

**Ordine delle chiamate con side effect**

Le funzioni `_validateYieldShock` e `_validateRedeemRateLimit` aggiornano storage. Questo le rende rischiose in `_before` — se una chiamata successiva nel flusso fa revert, lo storage viene comunque modificato. Valutare di spostare queste due funzioni in `_afterValueTransfer` dove si è certi che l'operazione è andata a buon fine.

`_validateRedemptionWindow` è `view` — nessun side effect, sicura in qualsiasi posizione del flusso.

**Separazione delle unità**

Attenzione alle unità di misura quando si confrontano valori:
- Yield da BondOracle: `uint64` in basis points (400 = 4.00%)
- USD values da ReservesOracle: `uint256` con 8 decimals
- USDC amounts: `uint256` con 6 decimals
- Fee percentages in TreasuryBondToken: `uint256` scalate per `PERCENTAGE_PRECISION`
- Redemption window: `uint256` in secondi, sempre riferita a `block.timestamp % 7 days`

Prima di qualsiasi confronto cross-oracle verificare sempre che le unità siano allineate.

**Testing**

Il pattern delle dipendenze astratte (`_getYieldForSlot`, `_getReserveForSlot`, ecc.) consente di testare il RiskManager in isolamento con mock che restituiscono valori controllati, senza deployare BondOracle e ReservesOracle nei test unitari.

Per testare `_validateRedemptionWindow` usare `vm.warp()` di Foundry per simulare diversi momenti della settimana:

```solidity
// lunedì 09:00 UTC — finestra aperta
vm.warp(1_700_000_000 - (1_700_000_000 % 7 days) + 32400);
// dovrebbe passare

// domenica 23:00 UTC — finestra chiusa
vm.warp(1_700_000_000 - (1_700_000_000 % 7 days) + 6 days + 23 hours);
// dovrebbe revertire con RedemptionWindowClosed
```
