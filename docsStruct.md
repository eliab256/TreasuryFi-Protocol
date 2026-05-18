# RWA Bond Yield Curve Protocol Documentation

---

# 1. Introduction

This protocol enables the tokenization of fixed-income exposure through maturity-based bond buckets.

Instead of forcing users to directly purchase and manage individual bonds until expiration, the protocol offers tokenized exposure to predefined maturity buckets:

- 2 Years
- 5 Years
- 10 Years
- 30 Years

The goal is to provide continuous exposure to the yield curve without requiring users to manually manage bond maturity rollover.

## Core Problem

Traditional bonds introduce several inefficiencies:

- Capital lock-up until maturity
- Manual maturity management
- Limited liquidity
- Difficult access to diversified yield curve exposure
- High operational friction for retail investors

## Protocol Solution

The protocol abstracts these complexities by allowing users to:

- Open positions on specific maturity buckets
- Earn yield over time
- Trade full or fractional positions
- Close positions partially or fully
- Maintain exposure without directly handling bond expiration

---

# 2. Protocol Architecture

The protocol is composed of multiple smart contract layers.

## 2.1 Position Manager

Responsible for:

- Opening positions
- Closing positions
- Partial redemptions
- Position accounting

## 2.2 Yield Engine

Responsible for:

- Yield accrual calculations
- Interest distribution
- Timestamp-based reward accounting

## 2.3 NAV Manager

Responsible for:

- Updating Net Asset Value
- Tracking asset valuation changes
- Maintaining accurate pricing

## 2.4 Marketplace Layer

Responsible for:

- Secondary market trading
- Fractional transfers
- Position liquidity

## 2.5 Compliance Layer

Responsible for:

- Investor verification
- Transfer restrictions
- Regulatory compliance checks

---

# 3. Token Standard Design

The protocol uses two token standards.

## 3.1 ERC-3525

:contentReference[oaicite:1]{index=1} is used because positions require:

- Fungibility within the same maturity bucket
- Individual ownership tracking
- Fractional transfers

Each slot represents a specific maturity:

| Slot ID | Maturity |
|----------|------------|
| 1 | 2 Years |
| 2 | 5 Years |
| 3 | 10 Years |
| 4 | 30 Years |

## Why not ERC20?

- No position individuality
- No maturity separation
- No structured ownership logic

## Why not ERC721?

- No native fractional transfers
- Poor fit for bond fractions

ERC-3525 solves both limitations.

---

# 4. Compliance Layer

The protocol integrates :contentReference[oaicite:2]{index=2}.

This enables:

- Identity verification
- Investor whitelisting
- Transfer restrictions
- Regulatory compliance

This layer is critical for Real World Asset tokenization.

---

# 5. Chainlink Infrastructure

The protocol integrates multiple :contentReference[oaicite:3]{index=3} services.

## 5.1 Chainlink Functions

Used to:

- Fetch external bond yield data
- Retrieve off-chain financial data
- Update protocol yields

## 5.2 Chainlink Automation

Used to:

- Trigger NAV updates
- Automate protocol maintenance
- Reduce manual intervention

## 5.3 Chainlink Price Feeds

Used to:

- Retrieve market prices
- Improve valuation accuracy

---

# 6. Position Lifecycle

This is one of the protocol’s most important components.

## 6.1 Open Position

Users:

- Select maturity bucket
- Deposit capital
- Mint ERC-3525 position token

Protocol stores:

- Principal
- Entry NAV
- Yield rate
- Timestamp

## 6.2 Hold Position

During holding:

- Yield accrues over time
- NAV changes may impact valuation
- Position remains tradable

## 6.3 Claim Interest

Users can claim accrued interest generated during the holding period.

Interest depends on:

- Initial yield
- Principal
- Holding duration

## 6.4 Trade Position

Users can trade:

- Entire positions
- Fractional positions

This improves liquidity.

## 6.5 Close Position

Users can:

- Fully close positions
- Partially close positions

Redemption value depends on:

- Principal
- Accrued yield
- Current NAV

---

# 7. Yield Accounting Model

This is one of the most technically complex parts of the protocol.

The protocol tracks yield using:

- NAV
- Timestamp
- Principal
- Yield rate

## Accrued Yield Formula

AccruedYield = Principal × YieldRate × TimeElapsed / 365

## Position Value Formula

PositionValue = Principal + AccruedYield

This ensures:

- Accurate accounting
- Fair redemption
- Correct partial exits

---

# 8. Why NAV-Based Accounting

Instead of fixed redemption logic, the protocol uses NAV.

Benefits include:

- Dynamic pricing
- More realistic financial modeling
- Better representation of asset performance
- Cleaner accounting logic

This mimics traditional fixed-income portfolio management systems.

---

# 9. Core Smart Contract Functions

## openPosition()

Creates new investment positions.

## claimYield()

Allows users to collect accrued yield.

## closePartialPosition()

Allows partial redemption.

## closePosition()

Fully exits the investment.

## transferValue()

Used for ERC-3525 fractional transfers.

---

# 10. Security Considerations

Potential risks include:

- Oracle manipulation
- Stale price feeds
- Incorrect NAV updates
- Reentrancy attacks
- Access control vulnerabilities
- Precision loss
- Rounding issues

Mitigations:

- Restricted access roles
- Oracle validation
- Safe accounting mechanisms
- Future testing expansion

---

# 11. Testing Strategy

Current testing includes:

- Deployment tests
- Core functionality tests

Planned improvements:

- Unit tests
- Integration tests
- Fork tests
- Invariant testing

Testing framework:

:contentReference[oaicite:4]{index=4}

---

# 12. Local Deployment

Current deployment environment:

- Local development environment

Tech stack:

- Solidity
- :contentReference[oaicite:5]{index=5}

Deployment flow:

```bash
forge build
forge test
forge script script/DeployProtocol.s.sol
```

# 13. Future Improvements

The protocol is currently in a functional local deployment stage, with core logic implemented and validated. Several enhancements are planned to evolve it into a production-grade RWA infrastructure.

## 13.1 Real-World Asset Integration

- Integration with real bond data providers
- Connection to institutional treasury APIs
- On-chain/off-chain reconciliation for bond pricing and yield curves

## 13.2 Governance Layer

- Introduction of DAO-based governance
- Parameter control (fees, yield sources, risk settings)
- Upgrade mechanisms for protocol modules

## 13.3 Multi-Chain Expansion

- Deployment on additional EVM-compatible networks
- Cross-chain position representation
- Liquidity unification across chains

## 13.4 Secondary Market Optimization

- Improved liquidity routing
- Better price discovery mechanisms
- Enhanced fractional trading efficiency

## 13.5 Institutional Features

- KYC/AML integrations for regulated investors
- Permissioned pools for institutional capital
- Reporting and audit tools

---

# 14. Design Decisions

This section explains the key architectural and financial choices behind the protocol design.

## 14.1 Why Maturity Buckets Instead of Individual Bonds

Tokenizing individual bonds would create excessive fragmentation and liquidity inefficiency.

Using maturity buckets instead provides:

- Simplified user experience
- Better liquidity aggregation
- Easier portfolio construction
- Reduced state complexity on-chain

This design abstracts traditional bond ladders into a cleaner on-chain model.

---

## 14.2 Why ERC-3525 for Position Representation

:contentReference[oaicite:0]{index=0} was chosen because the protocol requires:

- Partial ownership of positions
- Structured value representation
- Slot-based categorization (maturity buckets)

It combines the advantages of fungible and non-fungible tokens, making it suitable for structured financial instruments.

---

## 14.3 Why ERC-3643 for Compliance

:contentReference[oaicite:1]{index=1} is used to enforce regulatory constraints:

- Investor whitelisting
- Transfer restrictions based on identity
- Compliance-aware token transfers

This is essential for Real World Asset tokenization, where regulatory constraints cannot be ignored.

---

## 14.4 Why Chainlink Infrastructure

:contentReference[oaicite:2]{index=2} is used because the protocol requires reliable external data and automation.

- Functions: fetch off-chain bond yield and financial data
- Automation: trigger periodic NAV updates
- Price Feeds: ensure accurate valuation inputs

This reduces trust assumptions and improves robustness.

---

## 14.5 Why NAV-Based Accounting

The protocol uses Net Asset Value (NAV) instead of fixed redemption logic.

This design choice allows:

- Continuous revaluation of positions
- More accurate yield representation
- Alignment with traditional fixed-income portfolio models
- Fair partial redemption calculations

NAV-based accounting better reflects real-world financial behavior.

---

# 15. Conclusion

This protocol demonstrates a structured approach to bringing fixed-income markets on-chain using modular blockchain infrastructure.

Key innovations include:

- Tokenized maturity buckets for yield curve exposure
- Semi-fungible position representation via ERC-3525
- Compliance enforcement through ERC-3643
- Oracle-driven yield and pricing via Chainlink
- NAV-based accounting for accurate financial modeling

The result is a hybrid system that bridges traditional fixed-income finance with decentralized infrastructure, enabling more accessible, flexible, and composable bond exposure.