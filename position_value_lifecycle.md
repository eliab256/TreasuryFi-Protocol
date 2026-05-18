# Position Value Lifecycle — TreasuryFi Protocol

## 1. Modello concettuale

Ogni token ERC-3525 rappresenta **esposizione al rischio di tasso** su un bucket della curva Treasury, non un deposito USDC. Il `value` del token è una quantità astratta di unità di esposizione; il suo controvalore in USDC è una funzione del NAV corrente, che si muove con i tassi di mercato.

```
token.value = unità di esposizione al tasso del bucket
valore USDC  = token.value × NAV(slot, t) / PAR_VALUE
```

Il NAV segue il modello Modified Duration. Quando i tassi salgono rispetto all'entry il NAV scende, quando scendono sale:

```
tassi saliti:  NAV(t) = PAR × (MAX_PERCENTAGE - D_mod × (y_current - y_entry) / PERCENTAGE_PRECISION) / MAX_PERCENTAGE
tassi scesi:   NAV(t) = PAR × (MAX_PERCENTAGE + D_mod × (y_entry - y_current) / PERCENTAGE_PRECISION) / MAX_PERCENTAGE
```

dove `y_entry` è il yield al momento del mint, `y_current` è il yield corrente, e `D_mod` è la duration modificata dello slot:

| Slot | D_mod |
|------|-------|
| 2Y   | 1.9   |
| 5Y   | 4.5   |
| 10Y  | 8.5   |
| 30Y  | 18    |

**Cap a zero:** se lo shock di tasso è abbastanza severo da portare il discount a ≥ 100% (`D_mod × yieldShock ≥ MAX_PERCENTAGE`), il NAV viene cappato a 0 anziché diventare negativo. In quel caso `closePosition` funziona normalmente — il token viene bruciato, le liabilities ridotte, e l'utente riceve esclusivamente lo yield accumulato fino a quel momento (il payout sul capitale è 0). Questo è un guardrail di sicurezza matematica: con i parametri attuali il RiskManager congela lo slot per `ExcessiveYieldShock` prima che questo scenario si materializzi in produzione.

---

## 2. Apertura della posizione — openNewPosition()

L'utente deposita USDC. Il protocollo:

1. Preleva la entry fee (0.2%) e la invia al `feeCollector`
2. Trasferisce i USDC netti al `Treasury`
3. Legge il yield corrente dall'oracle → `y_current = BondOracle.getYield(slot)`
4. Converte i USDC netti in USD a 18 decimali tramite il price feed USDC/USD → `netAmountInUsd`
5. Minta il token ERC-3525 con `value = netAmountInUsd`
6. Salva `PositionData`:

```solidity
s_fromIdToPositionData[tokenId] = PositionData({
    entryYield:          y_current,       // yield bloccato al mint, in bps
    entryNAV:            C.PAR,           // sempre PAR al mint (vedere nota sotto)
    mintTimestamp:       block.timestamp, // per lock period e early redeem fee
    lastClaimTimestamp:  block.timestamp  // inizializzato al mint
});
```

### Cosa rappresenta `entryNAV`

`entryNAV` è fissato a `PAR` al momento del mint. Insieme a `token.value`, permette di ricostruire il principale USD investito in qualsiasi momento:

```
principalUsd = token.value × entryNAV / PAR_VALUE
             = token.value × PAR / PAR
             = token.value
```

`entryNAV` è progettato per supportare un futuro mercato secondario: quando un token cambia mano tramite trasferimento, il nuovo holder eredita l'`entryNAV` originale del sorgente (che potrebbe essere diverso da PAR se il token è stato trasferito dopo una variazione di tassi), preservando la corretta base di calcolo degli interessi.

---

## 3. Vita della posizione — variazione del NAV

Dopo il mint, il valore USDC della posizione varia con i tassi di mercato anche se `token.value` rimane invariato.

```
t=0  (mint):    y=4.50%, NAV=PAR,                                  valore USDC = 1000
t=6m (tassi↑): y=5.00%, NAV=PAR×(1-8.5×0.005)=PAR×0.9575,        valore USDC = 957.5
t=12m (tassi↓): y=4.00%, NAV=PAR×(1+8.5×0.005)=PAR×1.0425,       valore USDC = 1042.5
```

`token.value` non cambia. Cambia solo il prezzo in USDC di ogni unità.

---

## 4. Chiusura completa — closePosition()

1. Legge `token.value` e `slotOf(tokenId)`
2. Calcola il NAV corrente in base alla direzione del movimento dei tassi (vedi sezione 1)
3. Calcola il payout lordo → `usdcPayoutBeforeFees = token.value × navNow / PAR`, convertito da USD18 a USDC
4. Calcola l'early redemption fee se `block.timestamp < mintTimestamp + penaltyPeriod[slot]`:
   - la fee decresce linearmente da `PERCENTAGE_EXIT_FEE_MAX` (5%) a 0 nel corso del penalty period
   - `earlyRedeemFee = usdcPayoutBeforeFees × currentFeePercentage / MAX_PERCENTAGE`
   - `usdcPayout = usdcPayoutBeforeFees - earlyRedeemFee` → fee al `feeCollector`
5. Verifica che il Treasury abbia liquidità sufficiente per coprire `usdcPayout + yieldAccumulato + fees`
6. Brucia il token ERC-3525
7. Trasferisce `usdcPayout + yieldAccumulato` dal Treasury all'utente

Il payout può essere superiore o inferiore al deposito originale a seconda del movimento dei tassi — esattamente come la vendita di un bond sul mercato secondario prima della scadenza.

---

## 5. Chiusura parziale — closePartialPosition()

L'utente vuole liquidare solo una parte della posizione (`valueToBurn < token.value`).

1. Calcola il payout proporzionale → `payout = valueToBurn × navNow / PAR`
2. Applica eventuale early redemption fee
3. Chiama `_burnValue(tokenId, valueToBurn)` → riduce `token.value` del valore bruciato
4. Il token **non viene distrutto** — continua ad esistere con `value` ridotto
5. `PositionData` rimane invariata (entryYield, entryNAV, mintTimestamp)

```
Prima:  token #42, slot=3, value=1000, entryNAV=PAR
Dopo:   token #42, slot=3, value=600,  entryNAV=PAR  ← stesso token, value ridotto
```

Il calcolo degli interessi successivi userà automaticamente il `value` ridotto tramite `balanceOf(tokenId)`, riducendo proporzionalmente il nominale.

---

## 6. Trasferimento parziale — transferFrom(fromTokenId, to, value)

Questo è il caso più complesso. L'ERC-3525 crea un **nuovo token** con il value trasferito:

```
token #42, slot=3, value=1000  →  token #42, slot=3, value=600
                                   token #99, slot=3, value=400  ← nuovo token per il ricevente
```

### Propagazione di mintTimestamp

Il nuovo token #99 eredita il `mintTimestamp` del token sorgente #42. Questo è fondamentale: il ricevente non può resettare il lock period ricevendo un trasferimento.

`lastClaimTimestamp` viene resettato a `block.timestamp` — non al mint del sorgente — perché il contratto liquida gli interessi maturati sul token sorgente prima della scissione. Il nuovo token parte da zero interessi maturati.

### Flusso completo del trasferimento

Tutta la logica avviene dentro `_beforeValueTransfer`, che per i trasferimenti delega a `_beforeTransfer`:

```
transferFrom(fromTokenId=#42, to=alice, value=400)
  │
  └── _beforeValueTransfer()
        │
        ├── 1. ERC3643: isVerified(alice)? KYC/AML check
        │
        └── _beforeTransfer()
              │
              ├── 2. _claimYield(#42)
              │       └── liquida gli interessi maturati su tutto il value del sorgente
              │           prima della scissione; paga al mittente; aggiorna lastClaimTimestamp[#42]
              │
              ├── 3. _riskManagerBeforeTransferLiquidity()
              │       └── verifica liquidità Treasury per yield + fee appena calcolati
              │
              ├── 4. i_treasury.transferUsdcFromYieldClaim()
              │       └── trasferisce yield al mittente
              │
              └── 5. propaga PositionData da #42 a #99
                      entryYield:         ereditato da #42
                      entryNAV:           ereditato da #42
                      mintTimestamp:      ereditato da #42   ← lock period non resettabile
                      lastClaimTimestamp: block.timestamp    ← parte da zero
```

Dopo il completamento della tx:
- token #42: `value=600`, `lastClaimTimestamp` aggiornato al momento del claim (step 2)
- token #99: `value=400`, `lastClaimTimestamp=now`, `entryYield`/`entryNAV` ereditati da #42

`_afterValueTransfer` è vuoto nell'implementazione corrente.

---

## 7. Tabella riassuntiva del ciclo di vita

| Operazione | token.value | PositionData | Treasury USDC |
|---|---|---|---|
| `openNewPosition` | Creato | Inizializzata | +usdcNetti |
| `claimYield` | Invariato | lastClaim aggiornato | -interessi |
| `closePartialPosition` | Ridotto | Invariata | -payout parziale |
| `closePosition` | Distrutto | Eliminata | -payout totale |
| `transferFrom(tokenId→addr)` | Invariato (token intero) | Copiata al ricevente | -yield liquidato al mittente |
| `transferFrom(tokenId, addr, value)` | Ridotto su sorgente | Copiata + lastClaim reset su nuovo | -yield liquidato al mittente |

---

## 8. Invariante fondamentale

In qualsiasi momento, per qualsiasi token:

```
principalUsd = balanceOf(tokenId) × entryNAV / PAR_VALUE
```

Questo valore è espresso in USD a 18 decimali ed è **sempre ricostruibile on-chain** senza dati storici esterni, perché `entryNAV` è salvato in `PositionData` al mint. La conversione a USDC avviene al momento del pagamento tramite il price feed USDC/USD.

---

## 9. Funzioni amministrative ERC-3643

Queste funzioni implementano i poteri dell'emittente previsti dallo standard ERC-3643 (T-REX) per i security token regolamentati. Non interagiscono con il RiskManager — operano esclusivamente sullo strato di compliance e ownership dei token.

### 9.1 forceTransfer — `OWNER_ROLE`

```solidity
function forceTransfer(address _from, address _to, uint256 _tokenId) public onlyRole(OWNER_ROLE) returns (bool)
```

Trasferimento forzato di un token, bypassando i controlli di compliance (KYC, freeze wallet) e le approvazioni ERC-721. Casi d'uso: ordine regolatorio, sequestro di asset, correzione di un trasferimento errato.

**Sequenza:**
1. Liquida lo yield maturato e lo paga a `_from` (identico al comportamento del trasferimento normale)
2. Sblocca eventuali `frozenValue` sul token (altrimenti il transfer ERC-3525 fallirebbe)
3. Esegue `_transferTokenId` che bypassa i controlli di compliance

Il flag `s_forcedTransfer` viene impostato a `true` prima della chiamata e resettato a `false` dopo (anche in caso di revert tramite try/catch), così `_beforeValueTransfer` sa di essere in un contesto forzato.

### 9.2 recoveryAddress — `RECOVERY_ROLE`

```solidity
function recoveryAddress(address _lostWallet, address _newWallet, address _investorOnchainID) public onlyRole(RECOVERY_ROLE) returns (bool)
```

Recupero di token da un wallet inaccessibile (chiave privata persa, wallet compromesso) verso un nuovo wallet dello stesso investitore. Richiede che `_investorOnchainID` sia l'ONCHAINID verificato sia del wallet perso che di quello nuovo, garantendo che il recupero avvenga verso la stessa persona fisica/giuridica.

**Implementazione interna (`_executeRecoveryTransfer`):** scatta uno snapshot degli ID token prima del trasferimento (per evitare problemi di enumerazione durante il loop), poi chiama `_transferTokenId` per ogni token. I `frozenValue` per tokenId migrano automaticamente (il mapping `s_frozenValues[tokenId]` rimane invariato — le chiavi sono gli ID del token, non l'address).

### 9.3 pause / unpause — `PAUSER_ROLE`

```solidity
function pause()   public onlyRole(PAUSER_ROLE)
function unpause() public onlyRole(PAUSER_ROLE)
```

Pausa globale del protocollo. Quando attiva, tutti i trasferimenti ERC-3525 e ERC-721 vengono bloccati dall'hook `_beforeValueTransfer` tramite il controllo ERC-3643. Casi d'uso: incidente di sicurezza, manutenzione critica, ordine regolatorio urgente.

`openNewPosition`, `closePosition`, `claimYield` chiamano tutti internamente transfer/burn/mint — sono tutti bloccati dalla pausa.

### 9.4 setAddressFrozen / batchSetAddressFrozen — `FREEZER_ROLE`

```solidity
function setAddressFrozen(address _userAddress, bool _freeze) external onlyRole(FREEZER_ROLE)
function batchSetAddressFrozen(address[] calldata _userAddresses, bool[] calldata _freeze) external onlyRole(FREEZER_ROLE)
```

Congela o scongela un indirizzo. Un indirizzo congelato non può ricevere o inviare token — il check avviene in `_beforeValueTransfer` tramite ERC-3643. Casi d'uso: procedimento AML, ordine di blocco da autorità regolatoria.

La versione batch permette di operare su più indirizzi in una singola transazione.

### 9.5 freezePartialTokens / unfreezePartialTokens / batch — `FREEZER_ROLE`

```solidity
function freezePartialTokens(uint256 _tokenId, uint256 _amount)   external onlyRole(FREEZER_ROLE)
function unfreezePartialTokens(uint256 _tokenId, uint256 _amount) external onlyRole(FREEZER_ROLE)
function batchFreezePartialTokens(uint256[] calldata _tokenId, uint256[] calldata _amounts)   external onlyRole(FREEZER_ROLE)
function batchUnfreezePartialTokens(uint256[] calldata _tokenId, uint256[] calldata _amounts) external onlyRole(FREEZER_ROLE)
```

Congela una quantità parziale del `value` di un token specifico. Il `value` congelato non può essere trasferito o bruciato fino allo sblocco. Diversamente da `setAddressFrozen` che opera a livello di wallet, il freeze parziale opera a livello di singola posizione — utile per bloccare selettivamente solo parte dell'esposizione di un investitore.

`forceTransfer` sblocca automaticamente il `frozenValue` prima di eseguire il trasferimento forzato.

### Tabella ruoli amministrativi

| Funzione | Ruolo | Bypassa compliance? | Liquida yield? |
|---|---|---|---|
| `forceTransfer` | `OWNER_ROLE` | Sì | Sì |
| `recoveryAddress` | `RECOVERY_ROLE` | Sì | No |
| `pause` / `unpause` | `PAUSER_ROLE` | — (blocca tutto) | — |
| `setAddressFrozen` | `FREEZER_ROLE` | No | No |
| `freezePartialTokens` | `FREEZER_ROLE` | No | No |
