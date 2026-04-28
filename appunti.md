onchainId lato user: se non ce l' ha lo crea alrimenti usa il suo già creato


# Dati del protocollo – struttura completa

| Dato | Da dove lo prendi | A cosa serve | Nota critica |
|------|------------------|--------------|--------------|
| Yield curve (2Y, 5Y, 10Y, 30Y) | FRED API / Chainlink Functions | Definire la struttura dei tassi di mercato, pricing implicito dei bond, base per tutte le sensibilità | È un input macro, non misura rischio direttamente |
| NAV del vault (SVP total USD value) | API SVP / calcolo off-chain (bond prices × quantity + cash) | Misura il valore totale degli asset del vault, base per collateralizzazione e mint/redeem | Non rappresenta il rischio di tasso |
| DV01 per bucket (2Y, 5Y, 10Y, 30Y) | Calcolo derivato da yield curve + duration model (off-chain o oracle dedicato) | Misura la sensibilità del vault ai movimenti dei tassi (risk engine) | NON è dato di mercato diretto, è modellato |
| Liabilities ERC-3525 (per bucket) | On-chain (balance per slot ERC-3525) | Misura l’esposizione venduta agli utenti per ogni bucket di curva | È stato del protocollo, non dato esterno |
| Key rate spreads (2Y–10Y, 5Y–30Y ecc.) | Derivato dalla yield curve (FRED) | Monitoraggio forma curva, regime detection (steep/flat/inverted) | Opzionale, utile per risk monitoring |
| Cash / liquidity del vault | On-chain SVP state | Garantire liquidità per redemption e buffer di sicurezza | Parte del NAV ma non del rischio tasso |
| Conversion layer (NAV → exposure) | Logica del protocollo | Tradurre asset del vault in esposizione per bucket | È logica interna, non un feed esterno |
| Risk aggregation (assets vs liabilities) | Derivato internamente | Verificare solvibilità del sistema e mismatch di esposizione | È il cuore del risk management |



┌──────────────────────────────────────────────┐
│                LAYER 1                       │
│           MARKET DATA LAYER                 │
│ (External Oracles / Data Providers)         │
├──────────────────────────────────────────────┤
│ • Yield Curve (2Y / 5Y / 10Y / 30Y)        │
│   → FRED / Chainlink Functions              │
│                                              │
│ • Key Rate Spreads (optional)              │
│   → derived from yield curve                │  li calcolo nel contratto treasuryBond
│                                              │
│ OUTPUT: term structure of interest rates     │
└──────────────────────────────────────────────┘
                     ↓


┌──────────────────────────────────────────────┐
│                LAYER 2                       │
│            VAULT / SVP LAYER                │
│ (Asset Side – On-chain + Oracle SVP API)    │
├──────────────────────────────────────────────┤
│ • Treasury holdings (2Y / 5Y / 10Y / 30Y)   │
│ • Cash reserves                              │
│ • Mark-to-market pricing                     │
│                                              │
│ • NAV Oracle (USD total value)              │
│                                              │
│ OUTPUT: Total assets in USD (NAV)            │
└──────────────────────────────────────────────┘
                     ↓    

┌──────────────────────────────────────────────┐
│                LAYER 3                       │
│          LIABILITY LAYER (ERC-3525)        │
│ (User Exposure – On-chain state)            │
├──────────────────────────────────────────────┤
│ Slot 2Y  → tokenized exposure 2Y           │
│ Slot 5Y  → tokenized exposure 5Y           │ ok
│ Slot 10Y → tokenized exposure 10Y          │
│ Slot 30Y → tokenized exposure 30Y          │
│                                              │
│ • total supply per bucket                   │
│ • mint/burn accounting                      │
│                                              │
│ OUTPUT: exposure sold to users              │
└──────────────────────────────────────────────┘
                     ↓       

┌──────────────────────────────────────────────┐
│                LAYER 4                       │
│            RISK ENGINE LAYER                │
│ (Off-chain or Oracle Computation Layer)     │
├──────────────────────────────────────────────┤
│ • DV01 per bucket (2Y / 5Y / 10Y / 30Y)     │
│ • Duration exposure of vault assets         │
│ • Liability exposure mapping                │
│                                              │
│ • Net exposure calculation:                 │
│   Assets DV01 vs Liabilities DV01           │
│                                              │
│ OUTPUT: risk state of protocol              │
└──────────────────────────────────────────────┘
                     ↓     

┌──────────────────────────────────────────────┐
│                LAYER 5                       │
│        PROTOCOL LOGIC LAYER (ON-CHAIN)      │
├──────────────────────────────────────────────┤
│ • Mint / Redeem logic                       │
│ • Collateral checks                         │
│ • Rebalancing triggers                      │
│ • Bucket accounting (ERC-3525 interaction)  │
│                                              │
│ INPUT:                                       │
│ - NAV (Layer 2)                             │
│ - Liabilities (Layer 3)                     │
│ - Risk signals (Layer 4)                    │
│                                              │
│ OUTPUT: token issuance + state updates       │
└──────────────────────────────────────────────┘