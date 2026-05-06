# Position Value Lifecycle — TreasuryFi Protocol

## 1. Modello concettuale

Ogni token ERC-3525 rappresenta **esposizione al rischio di tasso** su un bucket della curva Treasury, non un deposito USDC. Il `value` del token è una quantità astratta di unità di esposizione; il suo controvalore in USDC è una funzione del NAV corrente, che si muove con i tassi di mercato.

```
token.value = unità di esposizione al tasso del bucket
valore USDC  = token.value × NAV(slot, t) / PAR_VALUE
```

Il NAV segue il modello Modified Duration:

```
NAV(t) = PAR × [1 - D_mod × (y_current(t) - y_entry)]
```

dove `y_entry` è il yield al momento del mint e `D_mod` è la duration modificata dello slot (1.9 per 2Y, 4.5 per 5Y, 8.7 per 10Y, 19.5 per 30Y).

---

## 2. Apertura della posizione — openNewPosition()

L'utente deposita USDC. Il protocollo:

1. Preleva la mint fee (0.10%) e la invia al `feeCollector`
2. Trasferisce i USDC netti al `Treasury`
3. Legge il yield corrente dall'oracle → `y_current = BondOracle.getYield(slot)`
4. Calcola il NAV corrente → `entryNAV = PAR × [1 - D_mod × (y_current - y_current)]` = PAR (al mint, per definizione il NAV è sempre PAR se l'utente è il primo holder, oppure il NAV di mercato corrente)
5. Calcola le unità da mintare → `valueToMint = (usdcNetti × PAR) / entryNAV`
6. Minta il token ERC-3525 con `value = valueToMint`
7. Salva `PositionData`:

```solidity
s_fromIdToPositionData[tokenId] = PositionData({
    entryYield:          y_current,       // yield bloccato al mint, in bps
    entryNAV:            entryNAV,        // NAV per unità al mint
    mintTimestamp:       block.timestamp, // per lock period
    lastClaimTimestamp:  block.timestamp  // inizializzato al mint
});
```

### Cosa rappresenta `entryNAV`

`entryNAV` è il **valore nominale per unità** al momento dell'acquisto. Moltiplicato per `value` restituisce il principale USDC investito (al netto delle fee), che è la base su cui vengono calcolati gli interessi — equivalente al face value in TradFi.

```
principalUsdc = token.value × entryNAV / PAR_VALUE
```

---

## 3. Vita della posizione — variazione del NAV

Dopo il mint, il valore USDC della posizione varia con i tassi di mercato anche se `token.value` rimane invariato.

```
t=0  (mint):    y=4.50%, NAV=PAR,       valore USDC = 1000
t=6m (tassi↑): y=5.00%, NAV=PAR×[1-8.7×0.005]=0.9565, valore USDC = 956.5
t=12m (tassi↓): y=4.00%, NAV=PAR×[1-8.7×(-0.005)]=1.0435, valore USDC = 1043.5
```

`token.value` non cambia. Cambia solo il prezzo in USDC di ogni unità.

---

## 4. Chiusura completa — closePosition()

1. Legge `token.value` e `slotOf(tokenId)`
2. Calcola il NAV corrente → `navNow = PAR × [1 - D_mod × (y_current - y_entry)]`
3. Calcola il payout → `payout = token.value × navNow / PAR`
4. Verifica lock period → se `block.timestamp < mintTimestamp + lockPeriod[slot]`:
   - `earlyFee = payout × EARLY_REDEEM_FEE_BPS / 10000`
   - `payout -= earlyFee` → fee al `feeCollector`
5. Brucia il token ERC-3525
6. Trasferisce `payout` USDC dal Treasury all'utente

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

### Propagazione di mintedAt

Il nuovo token #99 eredita il `mintTimestamp` del token sorgente #42. Questo è fondamentale: il ricevente non può resettare il lock period ricevendo un trasferimento.

```solidity
// in _afterValueTransfer, quando _from != address(0) e _to != address(0)
s_fromIdToPositionData[_toTokenId] = PositionData({
    entryYield:         s_fromIdToPositionData[_fromTokenId].entryYield,
    entryNAV:           s_fromIdToPositionData[_fromTokenId].entryNAV,
    mintTimestamp:      s_fromIdToPositionData[_fromTokenId].mintTimestamp,  // ereditato
    lastClaimTimestamp: block.timestamp  // reset al momento del trasferimento
});
```

`lastClaimTimestamp` viene resettato a `block.timestamp` — non al mint del sorgente — perché prima del trasferimento il contratto deve chiamare `_claimYield(fromTokenId)` per liquidare gli interessi maturati fino a quel momento in capo al mittente. Il nuovo token parte da zero interessi maturati.

### Flusso completo del trasferimento

```
transferFrom(fromTokenId=#42, to=alice, value=400)
  │
  ├── 1. _beforeValueTransfer()
  │       ├── ERC3643: isVerified(alice)? KYC check
  │       └── RiskManager: slot frozen? oracle stale?
  │
  ├── 2. _claimYield(#42)   ← liquida interessi maturati sul token sorgente
  │       └── paga al mittente gli interessi su tutto il value prima della scissione
  │
  ├── 3. ERC3525: crea token #99 con value=400, copia slot da #42
  │
  ├── 4. _afterValueTransfer()
  │       └── copia PositionData da #42 a #99
  │           lastClaimTimestamp[#99] = block.timestamp
  │
  └── 5. token #42: value=600, lastClaimTimestamp aggiornato dal claim al punto 2
       token #99: value=400, lastClaimTimestamp=now, entryYield/entryNAV ereditati
```

---

## 7. Tabella riassuntiva del ciclo di vita

| Operazione | token.value | PositionData | Treasury USDC |
|---|---|---|---|
| `openNewPosition` | Creato | Inizializzata | +usdcNetti |
| `claimYield` | Invariato | lastClaim aggiornato | -interessi |
| `closePartialPosition` | Ridotto | Invariata | -payout parziale |
| `closePosition` | Distrutto | Eliminata | -payout totale |
| `transferFrom(tokenId→addr)` | Invariato (token intero) | Copiata al ricevente | 0 |
| `transferFrom(tokenId, addr, value)` | Ridotto su sorgente | Copiata + lastClaim reset su nuovo | 0 |

---

## 8. Invariante fondamentale

In qualsiasi momento, per qualsiasi token:

```
principalUsdc = balanceOf(tokenId) × entryNAV / PAR_VALUE
```

Questo valore è **sempre ricostruibile on-chain** senza dati storici esterni, perché `entryNAV` è salvato in `PositionData` al mint.
