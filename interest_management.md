# Interest Management — TreasuryFi Protocol

## 1. Modello di riferimento

Gli interessi replicano il comportamento di un T-Bill a **tasso fisso bloccato al mint**, non a tasso variabile. Questo è intenzionale: ogni posizione si comporta come un bond con coupon fisso definito al momento dell'acquisto, indipendentemente da come si muove il yield oracle successivamente.

La formula di accrual è:

```
accruedUsd = principalUsd × entryYield × elapsed / (MAX_PERCENTAGE × 365 days)
```

dove:
- `principalUsd = balanceOf(tokenId) × entryNAV / PAR` — in USD 18 decimali
- `entryYield` = yield bloccato al mint, scala **1% = 10.000** (es. 4.50% → 45.000)
- `elapsed = block.timestamp - lastClaimTimestamp`
- `MAX_PERCENTAGE = 100 × PERCENTAGE_PRECISION = 1.000.000` — rappresenta il 100%

> **Nota sulla scala yield:** il valore viene dall'oracle JS come `parseFloat(obs.value) * 10000` — quindi 4.50% → 45.000. Il divisore corretto per ottenere la frazione decimale è `MAX_PERCENTAGE` (1.000.000), non `PERCENTAGE_PRECISION` (10.000).

---

## 2. Equivalenza con il calcolo TradFi

In TradFi:
```
interessi = faceValue × couponRate × elapsed / 365
```

Nel protocollo:
```
accruedUsd = principalUsd × entryYield × elapsed / (1_000_000 × 365 days)
```

`principalUsd` = face value della posizione in USD 18 dec  
`entryYield` = coupon rate bloccato al mint, con scala 1% = 10.000  

Sono matematicamente identici. L'unica differenza è che in TradFi il face value è convenzionale ($1000 per T-Bill), qui è il deposito effettivo dell'utente convertito in USD. Il divisore è `MAX_PERCENTAGE = 1.000.000` perché la scala yield è ×100 rispetto ai bps classici.

---

## 3. Fee di gestione

Il protocollo trattiene una **management fee percentuale sugli interessi lordi**. La fee non è un tasso fisso sul capitale — è il **20% dello yield lordo** accumulato. Non viene detratta da `entryYield` in `PositionData`; viene calcolata al momento della distribuzione:

```
grossAccrued  = principalUsd × entryYield × elapsed / (MAX_PERCENTAGE × 365 days)
managementFee = grossAccrued × PERCENTAGE_YIELD_FEE / MAX_PERCENTAGE
netPayout     = grossAccrued - managementFee
```

dove `PERCENTAGE_YIELD_FEE = 20 × PERCENTAGE_PRECISION = 200.000` (20% in scala MAX_PERCENTAGE).

`netPayout` va all'utente, `managementFee` va al `feeCollector` — entrambi prelevati dal Treasury.

Esempio con entryYield=45.000 (4.50%), principal=10.000 USDC (≈ 10.000e18 USD), elapsed=180 giorni:

```
grossAccrued  = 10.000e18 × 45.000 × 180 / (1.000.000 × 365) = 221.92e18 USD = 221.92 USDC
managementFee = 221.92 × 200.000 / 1.000.000                  =  44.38 USDC  (20% del lordo)
netPayout     = 221.92 - 44.38                                 = 177.54 USDC
```

> **Perché percentuale sullo yield e non tasso fisso:** una fee fissa sul capitale crea un floor risk — con yield di mercato molto bassi la fee potrebbe superare lo yield generato, portando a un payout netto negativo. Una fee percentuale sullo yield lordo è sempre autocoerente: se lo yield è zero, la fee è zero.

---

## 4. lastClaimTimestamp — perché è necessario

Senza `lastClaimTimestamp`, ogni claim ricalcolerebbe gli interessi dall'apertura della posizione, pagando più volte lo stesso periodo. Il campo viene:

- **Inizializzato** a `mintTimestamp` al momento del mint
- **Aggiornato** a `block.timestamp` ad ogni claim
- **Resettato** a `block.timestamp` quando il token viene ricevuto via trasferimento parziale

```solidity
struct PositionData {
    uint256 entryYield;          // bps, bloccato al mint
    uint256 entryNAV;            // NAV per unità al mint
    uint256 mintTimestamp;       // per lock period
    uint256 lastClaimTimestamp;  // per calcolo elapsed corretto
}
```

---

## 5. Minimum claim interval

Per evitare micro-claims frequenti che aumentano i costi di gas e complicano la contabilità del Treasury, il protocollo impone un intervallo minimo tra due claim consecutivi:

```solidity
uint256 internal constant MIN_CLAIM_INTERVAL = 30 days;

if (block.timestamp - pos.lastClaimTimestamp < MIN_CLAIM_INTERVAL) {
    revert RiskManager__ClaimTooEarly(pos.lastClaimTimestamp + MIN_CLAIM_INTERVAL);
}
```

Questo intervallo è coerente con la natura mensile dei pagamenti cedolari in TradFi.

---

## 6. Interazione con closePartialPosition

Quando l'utente brucia parte del value, `balanceOf(tokenId)` si riduce. Questo riduce proporzionalmente il `principalUsdc` per i claim futuri:

```
Prima del partial close:
  value=1000, entryNAV=PAR → principalUsdc=1000 USDC
  claim su 180gg → 221.92 USDC

Dopo closePartialPosition(valueToBurn=400):
  value=600, entryNAV=PAR → principalUsdc=600 USDC
  claim su successivi 180gg → 133.15 USDC
```

Il contratto deve chiamare `_claimYield(tokenId)` **prima** di eseguire il burn, per liquidare gli interessi maturati sull'intero value prima della riduzione:

```solidity
function closePartialPosition(uint256 _tokenId, uint256 _valueToBurn) public {
    // 1. liquida interessi maturati sull'intero value corrente
    (uint256 netPayout, uint256 managementFee) = _claimYield(_tokenId, s_fromIdToPositionData[_tokenId]);
    
    // 2. solo dopo, riduci il value
    _burnValue(_tokenId, _valueToBurn);
    
    // 3. paga il payout USDC proporzionale
}
```

---

## 7. Interazione con il trasferimento parziale

Quando `transferFrom(fromTokenId, to, value)` crea un nuovo token, il contratto deve:

1. Chiamare `_claimYield(fromTokenId, positionData)` prima della scissione — calcola e registra gli interessi del mittente sull'intero value; il trasferimento USDC viene eseguito dal layer pubblico dopo il ritorno
2. Creare il nuovo token con `PositionData` ereditata dal sorgente
3. Impostare `lastClaimTimestamp` del nuovo token a `block.timestamp`

Il ricevente inizia ad accumulare interessi dal momento del ricevimento, non dal mint originale del sorgente. Il lock period invece è ereditato (`mintTimestamp` del sorgente) — non si resetta.

```
token #42: value=1000, entryYield=45000 (4.50%), lastClaim=t0
  ↓ transferFrom(#42, alice, 400) al tempo t1
  ↓ _claimYield(#42, posData) → calcola interessi su 1000 per periodo [t0, t1]; aggiorna lastClaim

token #42: value=600, lastClaim=t1
token #99: value=400, entryYield=45000 (ereditato), lastClaim=t1, mintTimestamp ereditato
```

---

## 8. Claim durante un trasferimento intero del token

Quando `transferFrom(from, to, tokenId)` trasferisce l'intero token ERC-721 style, il nuovo owner eredita tutto incluso `lastClaimTimestamp`. Il protocollo deve decidere se:

**A) Liquidare prima del trasferimento** — il mittente riceve gli interessi maturati, il ricevente ricomincia da zero con `lastClaim=now`

**B) Trasferire anche gli interessi maturati** — il ricevente può claimare gli interessi maturati prima del trasferimento

La scelta A è più sicura e coerente con il comportamento del trasferimento parziale. È implementata in `_beforeTransfer`:

```solidity
function _beforeTransfer(...) internal {
    // calcola interessi al mittente prima del trasferimento; aggiorna lastClaimTimestamp
    (uint256 netPayout, uint256 managementFee) = _claimYield(_fromTokenId, positionData);
    // il trasferimento USDC avviene nel layer pubblico dopo _beforeTransfer
    // il ricevente eredita lastClaim=now → nessun interesse pregresso
}
```

---

## 9. Flusso USDC del Treasury per gli interessi

```
claimYield(tokenId)
  │
  ├── _claimYield(tokenId, positionData)
  │       └── calcola grossAccrued, managementFee, netPayout
  │           aggiorna lastClaimTimestamp
  │           NON trasferisce USDC
  │
  ├── _riskManagerBeforeTransferLiquidity(slot, netPayout + managementFee)
  │       └── verifica che il Treasury abbia liquidità sufficiente
  │
  └── i_treasury.transferUsdcFromYieldClaim(netPayout, msg.sender, slot, managementFee)
         └── preleva da s_totalUsdcPerSlot[slot]:
               netPayout → all'utente
               managementFee → al feeCollector
```

Il Treasury mantiene un unico mapping `s_totalUsdcPerSlot[slot]` per ogni slot. Non esiste una separazione contabile tra liquidità del protocollo e depositi utenti on-chain: entrambi confluiscono nello stesso pool per slot. Lo SPV rifornisce il Treasury chiamando `injectLiquidity()` quando necessario.

---

## 10. Invariante di solvibilità per gli interessi

In qualsiasi momento, il Treasury deve poter coprire tutti gli interessi maturati e non ancora claimati su tutti i token attivi. Questo è verificabile come:

```
totalAccruedLiabilities = Σ [balanceOf(tokenId) × entryNAV/PAR × entryYield × elapsed / (MAX_PERCENTAGE × 365)]
                          per ogni tokenId attivo

Treasury.s_totalUsdcPerSlot[slot] >= totalAccruedLiabilitiesPerSlot
```

(dove yield in scala 1% = 10.000, MAX_PERCENTAGE = 1.000.000)

Questo check non è implementato on-chain per ogni operazione (troppo costoso — richiederebbe iterare su tutti i token), ma va monitorato off-chain con alert e può essere verificato su richiesta tramite una funzione di view dedicata.

---

## 11. Minimum deposit — protezione da spam e dust

Il contratto impone un deposito minimo di **10 USDC** (`i_minimumDepositAmount`) come guardrail contro:

1. **Spam/dust attack**: senza floor, un attaccante potrebbe aprire migliaia di posizioni da 1 wei USDC, saturando `s_totalLiabilitiesPerSlot` e aumentando il costo gas di ogni operazione che opera per slot.
2. **Posizioni economicamente irrazionali**: con meno di ~10 USDC, lo yield annuo accumulato è inferiore al gas cost di un singolo `claimYield`. La posizione non verrebbe mai chiusa in modo economicamente razionale.
3. **Precision loss**: con `value` molto piccolo (pochi wei in USD 18 dec), la conversione `_convertUsd18ToUsdc` può azzerare il payout per troncamento intero, rendendo il rimborso impossibile.
4. **Reserve coverage**: ogni mint aggiunge a `s_totalLiabilitiesPerSlot[slot]` — anche le posizioni dust erodono il buffer di riserva disponibile per posizioni reali.

```solidity
if (_usdcAmount < i_minimumDepositAmount) revert TreasuryBondToken__BelowMinimumDeposit();
```
