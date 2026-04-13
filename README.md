# TreasuriFi Protocol — Smart Contracts & Tech Stack

"https://api.stlouisfed.org/fred/series/observations?series_id=DGS10&api_key=84e614f27ef30e5217824b37a161fc52&sort_order=desc&limit=1&file_type=json"

## Smart Contracts Structure

```
contracts/
│
├── identity/
│   ├── ClaimIssuer.sol              # ERC-3643: issues verified KYC claims
│   └── IdentityRegistry.sol         # ERC-3643: registry of verified wallets
│
├── tokens/
│   └── TreasuryBondToken.sol        # ERC-3525: slot=maturity, value=USD face value
│                                    # ERC-3643 compliance hook on every transfer
│
├── oracles/
│   ├── BondOracle.sol               # Receives and stores data from Functions
│   └── BondFunctionsConsumer.sol    # Chainlink Functions: calls FRED API
│
└── automation/
    └── BondAutomation.sol           # Chainlink Automation: triggers 24h update
```

## Tech Stack

| Layer           | Tool                                       |
| --------------- | ------------------------------------------ |
| Smart Contracts | Foundry                                    |
| ERC-3643        | T-REX Protocol (Tokeny)                    |
| ERC-3525        | Solv Protocol reference implementation     |
| Oracle          | Chainlink Functions + Automation (Sepolia) |
| Data            | FRED API (Federal Reserve) — free          |
| Indexing        | The Graph — Subgraph Studio                |
| Frontend        | Next.js + wagmi + viem                     |
| Testnet         | Sepolia                                    |


📌 Roadmap Suggerita
Settimana 1 → ERC-3643: ClaimIssuer + IdentityRegistry + test KYC flow
Settimana 2 → ERC-3525: TreasuryBondToken con slot/scadenze + transfer hook
Settimana 3 → Chainlink Functions: script FRED API + BondOracle on-chain
Settimana 4 → Chainlink Automation: aggiornamento automatico 24h
Settimana 5 → The Graph: subgraph con tutti gli eventi
Settimana 6 → Frontend minimale + README dettagliato + deploy Sepolia