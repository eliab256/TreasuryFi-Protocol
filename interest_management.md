# Interest Management — TreasuryFi Protocol

## 1. Modello di riferimento

Gli interessi replicano il comportamento di un T-Bill a **tasso fisso bloccato al mint**, non a tasso variabile. Questo è intenzionale: ogni posizione si comporta come un bond con coupon fisso definito al momento dell'acquisto, indipendentemente da come si muove il yield oracle successivamente.

La formula di accrual è:

```
accrued = principalUsdc × entryYield × elapsed / (PERCENTAGE_PRECISION × 365 days)
```

dove:
- `principalUsdc = balanceOf(tokenId) × entryNAV / PAR_VALUE`
- `entryYield` = yield in bps bloccato al mint (da `PositionData`)
- `elapsed = block.timestamp - lastClaimTimestamp`

---

## 2. Equivalenza con il calcolo TradFi

In TradFi:
```
interessi = faceValue × couponRate × elapsed / 365
```

Nel protocollo:
```
interessi = principalUsdc × entryYield × elapsed / (10000 × 365 days)
```

`principalUsdc` = face value della posizione (quanto hai investito in USDC al netto delle fee)
`entryYield` = coupon rate bloccato al mint

Sono matematicamente identici. L'unica differenza è che in TradFi il face value è convenzionale ($1000 per T-Bill), qui è il deposito effettivo dell'utente.

---

## 3. Fee di gestione

Il protocollo trattiene una **management fee** sugli interessi lordi. La fee non viene detratta dal `entryYield` salvato in `PositionData` — viene calcolata al momento della distribuzione:

```
grossAccrued  = principalUsdc × entryYield × elapsed / (PERCENTAGE_PRECISION × 365 days)
managementFee = grossAccrued × MANAGEMENT_FEE_BPS / PERCENTAGE_PRECISION
netPayout     = grossAccrued - managementFee
```

`netPayout` va all'utente, `managementFee` va al `feeCollector` — entrambi prelevati dal Treasury.

Esempio con entryYield=450bps (4.50%), MANAGEMENT_FEE_BPS=50bps (0.50%), principal=10.000 USDC, elapsed=180 giorni:

```
grossAccrued  = 10.000 × 450 × 180 / (10.000 × 365) = 221.92 USDC
managementFee = 221.92 × 50 / 10.000                 =   1.10 USDC
netPayout     = 221.92 - 1.10                         = 220.82 USDC
```

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
    _claimYield(_tokenId);
    
    // 2. solo dopo, riduci il value
    _burnValue(_tokenId, _valueToBurn);
    
    // 3. paga il payout USDC proporzionale
}
```

---

## 7. Interazione con il trasferimento parziale

Quando `transferFrom(fromTokenId, to, value)` crea un nuovo token, il contratto deve:

1. Chiamare `_claimYield(fromTokenId)` prima della scissione — liquida gli interessi del mittente sull'intero value
2. Creare il nuovo token con `PositionData` ereditata dal sorgente
3. Impostare `lastClaimTimestamp` del nuovo token a `block.timestamp`

Il ricevente inizia ad accumulare interessi dal momento del ricevimento, non dal mint originale del sorgente. Il lock period invece è ereditato (`mintTimestamp` del sorgente) — non si resetta.

```
token #42: value=1000, entryYield=450, lastClaim=t0
  ↓ transferFrom(#42, alice, 400) al tempo t1
  ↓ _claimYield(#42) → paga interessi su 1000 per periodo [t0, t1]

token #42: value=600, lastClaim=t1
token #99: value=400, entryYield=450 (ereditato), lastClaim=t1, mintTimestamp ereditato
```

---

## 8. Claim durante un trasferimento intero del token

Quando `transferFrom(from, to, tokenId)` trasferisce l'intero token ERC-721 style, il nuovo owner eredita tutto incluso `lastClaimTimestamp`. Il protocollo deve decidere se:

**A) Liquidare prima del trasferimento** — il mittente riceve gli interessi maturati, il ricevente ricomincia da zero con `lastClaim=now`

**B) Trasferire anche gli interessi maturati** — il ricevente può claimare gli interessi maturati prima del trasferimento

La scelta A è più sicura e coerente con il comportamento del trasferimento parziale. Va implementata in `_beforeTransfer`:

```solidity
function _beforeTransfer(...) internal {
    // liquida interessi al mittente prima del trasferimento
    _claimYield(_fromTokenId);
    // lastClaimTimestamp viene aggiornato dal claim
    // il ricevente eredita lastClaim=now → nessun interesse pregresso
}
```

---

## 9. Flusso USDC del Treasury per gli interessi

```
claimYield(tokenId)
  │
  ├── calcola grossAccrued  → dal Treasury a user
  ├── calcola managementFee → dal Treasury a feeCollector
  │
  └── Treasury.withdrawForYield(slot, grossAccrued, user, managementFee, feeCollector)
         │
         ├── priorità: s_protocolLiquidityPerSlot (yield aggiunto dallo SPV)
         └── fallback:  s_userDepositsPerSlot     (depositi utenti)
```

La priorità sulla liquidità del protocollo garantisce che i depositi degli utenti non vengano erosi dal pagamento degli interessi in condizioni normali — lo SPV versa periodicamente i rendimenti reali dei T-Bill nel Treasury, e da lì vengono distribuiti.

---

## 10. Invariante di solvibilità per gli interessi

In qualsiasi momento, il Treasury deve poter coprire tutti gli interessi maturati e non ancora claimati su tutti i token attivi. Questo è verificabile come:

```
totalAccruedLiabilities = Σ [balanceOf(tokenId) × entryNAV/PAR × entryYield × elapsed / (10000 × 365)]
                          per ogni tokenId attivo

Treasury.protocolLiquidityTotal >= totalAccruedLiabilities
```

Questo check non è implementato on-chain per ogni operazione (troppo costoso — richiederebbe iterare su tutti i token), ma va monitorato off-chain con alert e può essere verificato su richiesta tramite una funzione di view dedicata.
