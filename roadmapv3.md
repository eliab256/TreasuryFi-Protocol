# TreasuryFi Protocol — Roadmap v3

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│              TreasuryBondToken (ERC-3525)                │
│  4 slots = rolling pools of T-Bills per maturity bucket │
│  value = shares of the pool for that duration bucket    │
├─────────────────────────────────────────────────────────┤
│  Fee Model                                              │
│  ├── mint fee (0.10% of USDC deposited)                 │
│  ├── management fee (0.50% spread on gross yield)       │
│  └── early redemption fee (0.50% if within lock period) │
├─────────────────────────────────────────────────────────┤
│  Lock Period Model (replaces fixed maturity)            │
│  ├── mintedAt[tokenId] saved at mint                    │
│  ├── lock period per slot: 30d / 90d / 180d / 365d      │
│  └── mintedAt inherited by derived tokens on transfer   │
├─────────────────────────────────────────────────────────┤
│  T-REX Compliance Layer (direct deploy, no factory)     │
│  IdentityRegistry + ClaimIssuer (ONCHAINID)             │
│  → isVerified() as transfer guard                       │
├─────────────────────────────────────────────────────────┤
│  Chainlink Functions (pricing layer)                    │
│  BondFunctionsConsumer → FRED API → BondOracle          │
├─────────────────────────────────────────────────────────┤
│  Chainlink Automation (scheduling layer)                │
│  BondAutomation → triggers yield updates every 24h      │
├─────────────────────────────────────────────────────────┤
│  Reserve Layer (backing layer)                          │
│  ReserveOracle (mock PoR) ← custodian pushes balance   │
│  → isReserveSufficient() as mint gate                   │
│  [production: Chainlink PoR AggregatorV3Interface]      │
└─────────────────────────────────────────────────────────┘
```

**Bond model:** Rolling Pool + Yield Curve Exposure (see `bondstructure.md`)

- Each slot = rolling pool of T-Bills with similar duration managed by the SPV off-chain
- No 1:1 mapping between token and individual T-Bill issuance
- No fixed maturity per token — bucket is perpetual by design, replicated via lock periods
- Tokens in the same slot are fungible (transferValue disabled between tokenIds; transferFrom creates a new derived token)
- NAV = modified duration model: `par × [1 - modDuration × (currentYield - entryYield)]`
- Carry accrual: holders earn net yield pro-rata via `claimYield()` (gross yield minus management fee)
- Mint/redeem priced in USDC at current NAV
- Risk controls: `maxSupplyPerSlot` caps total exposure per bucket

**Fee model:**

| Fee                   | Rate    | Trigger                                      | Recipient      |
| --------------------- | ------- | -------------------------------------------- | -------------- |
| Mint fee              | 0.10%   | On every mint, deducted from USDC deposit    | `feeCollector` |
| Management fee        | 0.50%   | On every `claimYield()`, spread on gross yield | `feeCollector` |
| Early redemption fee  | 0.50%   | On redeem within slot lock period            | `feeCollector` |

**Lock period model (replaces maturity date):**

| Slot | Maturity | Lock Period |
| ---- | -------- | ----------- |
| 1    | 2Y       | 30 days     |
| 2    | 5Y       | 90 days     |
| 3    | 10Y      | 180 days    |
| 4    | 30Y      | 365 days    |

- `mintedAt[tokenId]` saved at mint time
- On `transferFrom(uint256, address, uint256)` the new derived token inherits `mintedAt` from the source token
- Lock period enforced at redeem: if `block.timestamp - mintedAt[tokenId] < slotLockPeriod(slot)` → early redemption fee applied

**Financial model constants:**

| Slot | Maturity | Modified Duration | FRED Series |
| ---- | -------- | ----------------- | ----------- |
| 1    | 2Y       | 1.9               | DGS2        |
| 2    | 5Y       | 4.5               | DGS5        |
| 3    | 10Y      | 8.7               | DGS10       |
| 4    | 30Y      | 19.5              | DGS30       |

---

## PHASE 1 — Identity & Compliance (ONCHAINID + T-REX direct deploy)

### TASK 1.1 — Understand the ONCHAINID + T-REX identity model

- [ ] **1.1.1** Read the ONCHAINID documentation — understand the `Identity` contract (one per investor)
- [ ] **1.1.2** Understand `ClaimIssuer` — the entity that signs KYC claims using ECDSA
- [ ] **1.1.3** Understand the claim lifecycle: ClaimIssuer signs → claim added to Identity → IdentityRegistry verifies
- [ ] **1.1.4** Understand `IdentityRegistry` — maps `wallet → Identity contract`, calls `isVerified(wallet)`
- [ ] **1.1.5** Understand `IdentityRegistryStorage` — separate storage that IdentityRegistry reads from
- [ ] **1.1.6** Understand `ClaimTopicsRegistry` — defines which claim topics are required (e.g. topic `1` = KYC)
- [ ] **1.1.7** Understand `TrustedIssuersRegistry` — defines which ClaimIssuers are trusted and for which topics

📚 **Reference:** ONCHAINID docs, T-REX docs, ERC-3643 standard

#### 📄 State after TASK 1.1

**🇮🇹** Nessun codice scritto. Comprensione chiara del modello claim-based identity.

**🇬🇧** No code written. Clear understanding of the claim-based identity model.

---

### TASK 1.2 — Write `script/DeployIdentity.s.sol`

- [ ] **1.2.1** Deploy `ClaimTopicsRegistry` — call `addClaimTopic(1)`
- [ ] **1.2.2** Deploy `ClaimIssuer`
- [ ] **1.2.3** Deploy `TrustedIssuersRegistry` — call `addTrustedIssuer(claimIssuer, [1])`
- [ ] **1.2.4** Deploy `IdentityRegistryStorage`
- [ ] **1.2.5** Deploy `IdentityRegistry`
- [ ] **1.2.6** Bind storage to registry via `bindIdentityRegistry()`
- [ ] **1.2.7** Save all deployed addresses to `deployments/identity.json`

#### 📄 State after TASK 1.2

**🇮🇹** Layer di compliance deployato. Nessun investor ancora registrato.

**🇬🇧** Compliance layer deployed. No investor registered yet.

---

### TASK 1.3 — Write `script/RegisterInvestor.s.sol`

- [ ] **1.3.0** Check if investor already has an Identity on-chain
- [ ] **1.3.1** Deploy new `Identity.sol` for investor wallet if none exists
- [ ] **1.3.2** Sign KYC claim with ClaimIssuer key, call `addClaim()` on Identity if claim missing
- [ ] **1.3.3** Call `IdentityRegistry.registerIdentity(wallet, identityContract, countryCode)`
- [ ] **1.3.4** Verify: `IdentityRegistry.isVerified(wallet)` must return `true`
- [ ] **1.3.5** Write Foundry tests covering: full flow, reuse with missing claim, reuse with existing claim, unregistered wallet, untrusted issuer, revoked claim

#### 📄 State after TASK 1.3

**🇮🇹** Layer di identità completo e testato. `IdentityRegistry` è la fonte di verità KYC.

**🇬🇧** Identity layer complete and tested. `IdentityRegistry` is the KYC source of truth.

---

## PHASE 2 — Reserve Layer (SPV + Proof of Reserve)

### TASK 2.1 — Understand the Proof of Reserve model

- [ ] **2.1.1** Study how Ondo Finance and Backed Finance use off-chain custodians with on-chain reserve attestation
- [ ] **2.1.2** Understand the Chainlink PoR `AggregatorV3Interface`
- [ ] **2.1.3** Understand the rolling pool model: no 1:1 mapping between token and T-Bill
- [ ] **2.1.4** Understand what `isReserveSufficient(mintCost)` must check

#### 📄 State after TASK 2.1

**🇮🇹** Comprensione chiara del modello SPV + PoR + rolling pool.

**🇬🇧** Clear understanding of the SPV + PoR + rolling pool model.

---

### TASK 2.2 — Write `IReserveOracle.sol` and `ReserveOracle.sol`

- [ ] **2.2.1** Define `IReserveOracle` interface: `getReserves()`, `isReserveSufficient()`, `isStale()`, `lastUpdated()`
- [ ] **2.2.2** Implement `ReserveOracle.sol` with: `reserveBalance`, `trackedSupplyValue`, `custodian`, `STALENESS_THRESHOLD = 24 hours`
- [ ] **2.2.3** Implement `updateReserves()`, `notifyMint()`, `notifyRedeem()`, `setCustodian()`, `setTokenContract()`
- [ ] **2.2.4** Write unit tests covering: sufficient/insufficient reserves, staleness, unauthorized callers, notify flows

#### 📄 State after TASK 2.2

**🇮🇹** `ReserveOracle.sol` completo e testato. Architettura identica alla produzione.

**🇬🇧** `ReserveOracle.sol` complete and tested. Architecture identical to production.

---

## PHASE 3 — Oracle Layer (Chainlink Functions)

### TASK 3.1 — Write `BondOracle.sol`

- [ ] **3.1.1** Define `BondData` struct: `uint256 yieldBPS`, `uint256 lastUpdated`
- [ ] **3.1.2** Define `mapping(uint256 slot => BondData) public bonds`
- [ ] **3.1.3** Implement `updateYield()`, `getYield()`, `isStale()` (72h threshold)
- [ ] **3.1.4** Emit `YieldUpdated(uint256 indexed slot, uint256 yieldBPS, uint256 timestamp)`
- [ ] **3.1.5** Define `IBondOracle` interface
- [ ] **3.1.6** Write unit tests

#### 📄 State after TASK 3.1

**🇮🇹** `BondOracle.sol` deployabile. Fonte di verità on-chain per i rendimenti dei 4 bucket.

**🇬🇧** `BondOracle.sol` deployable. On-chain source of truth for yields of the 4 buckets.

---

### TASK 3.2 — Write `BondFunctionsConsumer.sol`

- [ ] **3.2.1** Inherit `FunctionsClient`, `ConfirmedOwner`
- [ ] **3.2.2** Implement `sendRequest(uint256 slot)` and `fulfillRequest()`
- [ ] **3.2.3** Write JS source (`functions/fetchYield.js`): FRED API → parse yield → `encodeUint256(Math.round(value * 100))`
- [ ] **3.2.4** Configure Chainlink Functions subscription on Sepolia
- [ ] **3.2.5** Write integration test with mock DON response

#### 📄 State after TASK 3.2

**🇮🇹** Pipeline oracle operativo end-to-end.

**🇬🇧** Oracle pipeline fully operational end-to-end.

---

## PHASE 4 — Automation Layer (Chainlink Automation)

### TASK 4.1 — Write `BondAutomation.sol`

- [ ] **4.1.1** Implement `AutomationCompatibleInterface`
- [ ] **4.1.2** Implement `checkUpkeep()` and `performUpkeep()` — loops slots 1–4 calling `sendRequest(slot)`
- [ ] **4.1.3** `interval = 24 hours`, `setInterval()` owner-only
- [ ] **4.1.4** Register on Chainlink Automation dashboard, fund with LINK
- [ ] **4.1.5** Write unit tests

#### 📄 State after TASK 4.1

**🇮🇹** Layer oracle completamente autonomo.

**🇬🇧** Oracle layer fully autonomous.

---

## PHASE 5 — Token Layer (ERC-3525 + T-REX + Fee Model + Lock Period)

### TASK 5.1 — Understand ERC-3525

- [ ] **5.1.1** Read ERC-3525 EIP — slot/value model, ERC-721 extension
- [ ] **5.1.2** Understand how `slot` works and fungibility within a slot
- [ ] **5.1.3** Understand `transferFrom(uint256, address, uint256)` — creates a new derived token
- [ ] **5.1.4** Understand `_beforeValueTransfer()` and `_afterValueTransfer()` hooks
- [ ] **5.1.5** Understand why `transferFrom(uint256, uint256, uint256)` is disabled in this protocol

#### 📄 State after TASK 5.1

**🇮🇹** Comprensione solida del modello ERC-3525 e delle scelte di design del protocollo.

**🇬🇧** Solid understanding of the ERC-3525 model and the protocol's design choices.

---

### TASK 5.2 — Write `TreasuryBondToken.sol` — Base ERC-3525

- [ ] **5.2.1** Import and inherit `ERC3525` from Solv Protocol
- [ ] **5.2.2** Define slot constants: `SLOT_2Y = 1`, `SLOT_5Y = 2`, `SLOT_10Y = 3`, `SLOT_30Y = 4`
- [ ] **5.2.3** Implement constructor: name, symbol, value decimals
- [ ] **5.2.4** Override `transferFrom(uint256, uint256, uint256)` with `revert` — token-to-token value transfer disabled
- [ ] **5.2.5** Write basic test: deploy, verify name/symbol/decimals, verify disabled transferFrom reverts

#### 📄 State after TASK 5.2

**🇮🇹** Token ERC-3525 base funzionante. transferFrom token-to-token disabilitato.

**🇬🇧** Working base ERC-3525 token. Token-to-token transferFrom disabled.

---

### TASK 5.3 — Add T-REX compliance

- [ ] **5.3.1** Store `IIdentityRegistry public identityRegistry` and `IBondOracle public bondOracle`
- [ ] **5.3.2** Store `mapping(address => bool) private frozenWallets`
- [ ] **5.3.3** Override `_beforeValueTransfer()`: skip on mint, check `isVerified(to)`, `!isStale(slot)`, `!frozenWallets[from]`
- [ ] **5.3.4** Implement `freeze()`, `unfreeze()`, `forcedTransfer()` — owner only
- [ ] **5.3.5** Emit events: `WalletFrozen`, `WalletUnfrozen`, `ForcedTransfer`

#### 📄 State after TASK 5.3

**🇮🇹** Token compliance-aware. Wallet non verificati, frozen e oracle stale bloccano i trasferimenti.

**🇬🇧** Token is compliance-aware. Unverified, frozen wallets and stale oracle block transfers.

---

### TASK 5.4 — Add NAV pricing model

- [ ] **5.4.1** Define duration constants per slot (scaled by 100): `DURATION_2Y = 190`, `DURATION_5Y = 450`, `DURATION_10Y = 870`, `DURATION_30Y = 1950`
- [ ] **5.4.2** Define `PAR_VALUE = 10000`, `PRECISION = 100`
- [ ] **5.4.3** Store `mapping(uint256 tokenId => uint256 entryYieldBPS) public entryYields`
- [ ] **5.4.4** Implement `getNAV(uint256 tokenId)` — modified duration formula with int256 for negative delta
- [ ] **5.4.5** Implement `getPositionValue(uint256 tokenId)` — `balanceOf(tokenId) * getNAV(tokenId) / PAR_VALUE`
- [ ] **5.4.6** Write NAV tests: unchanged yield → par, +50bps 10Y → -4.35%, -100bps 30Y → +19.5%, floor at 0

#### 📄 State after TASK 5.4

**🇮🇹** Modello di pricing implementato. NAV realistico e verificabile.

**🇬🇧** Pricing model implemented. NAV is realistic and verifiable.

---

### TASK 5.5 — Add Fee Model and Lock Period

- [ ] **5.5.1** Define fee constants:
  ```solidity
  uint256 public constant MINT_FEE_BPS         = 10;  // 0.10%
  uint256 public constant MANAGEMENT_FEE_BPS   = 50;  // 0.50%
  uint256 public constant EARLY_REDEEM_FEE_BPS = 50;  // 0.50%
  ```
- [ ] **5.5.2** Define lock period constants per slot:
  ```solidity
  uint256 public constant LOCK_PERIOD_2Y  = 30 days;
  uint256 public constant LOCK_PERIOD_5Y  = 90 days;
  uint256 public constant LOCK_PERIOD_10Y = 180 days;
  uint256 public constant LOCK_PERIOD_30Y = 365 days;
  ```
- [ ] **5.5.3** Store `address public feeCollector` — set in constructor
- [ ] **5.5.4** Store `mapping(uint256 tokenId => uint256 mintTimestamp) public mintedAt`
- [ ] **5.5.5** Implement `slotLockPeriod(uint256 slot) public pure returns (uint256)` — returns lock period for slot
- [ ] **5.5.6** Write unit tests for fee and lock period constants

#### 📄 State after TASK 5.5

**🇮🇹** Costanti fee e lock period definite. `feeCollector` configurato.

**🇬🇧** Fee and lock period constants defined. `feeCollector` configured.

---

### TASK 5.6 — Add USDC-priced Mint with PoR gate and mint fee

- [ ] **5.6.1** Store `IReserveOracle public reserveOracle`, `IERC20 public paymentToken`, `address public treasury`
- [ ] **5.6.2** Implement `mint(address to, uint256 slot, uint256 value)`:
  - `onlyOwner`
  - Validate slot, verify recipient, check oracle freshness
  - Compute `cost = value * getNAVForNewMint(slot) / PAR_VALUE`
  - Check `reserveOracle.isReserveSufficient(cost)` and `!reserveOracle.isStale()`
  - Deduct mint fee: `fee = cost * MINT_FEE_BPS / 10000`
  - Transfer `fee` → `feeCollector`, `cost - fee` → `treasury`
  - Call `_mint(to, slot, value)`, save `entryYields[newTokenId]` and `mintedAt[newTokenId] = block.timestamp`
  - Call `reserveOracle.notifyMint(cost - fee)`
  - Emit `TokenMinted(address indexed to, uint256 indexed slot, uint256 value, uint256 cost, uint256 fee)`
- [ ] **5.6.3** Write mint tests: correct USDC charge + fee split, unverified wallet revert, invalid slot revert, insufficient reserves revert, stale reserve revert, entryYield and mintedAt saved correctly

#### 📄 State after TASK 5.6

**🇮🇹** Mint con fee e gate PoR completo. La mint fee è trattenuta al momento del deposito.

**🇬🇧** Mint with fee and PoR gate complete. Mint fee is retained at deposit time.

---

### TASK 5.7 — Add Redeem with early redemption fee

- [ ] **5.7.1** Implement `redeem(uint256 tokenId, uint256 value)`:
  - `require(ownerOf(tokenId) == msg.sender)`
  - Compute `payout = value * getNAV(tokenId) / PAR_VALUE`
  - Check lock period: `if (block.timestamp - mintedAt[tokenId] < slotLockPeriod(slot))`
    - Compute `earlyFee = payout * EARLY_REDEEM_FEE_BPS / 10000`
    - Transfer `earlyFee` → `feeCollector`
    - Reduce `payout -= earlyFee`
  - Transfer `payout` → `msg.sender` from `treasury`
  - Call `_burnValue(tokenId, value)` and `reserveOracle.notifyRedeem(payout)`
  - Emit `TokenRedeemed(address indexed owner, uint256 indexed tokenId, uint256 value, uint256 payout, bool earlyRedemption, uint256 fee)`
- [ ] **5.7.2** Write redeem tests:
  - Redeem after lock period → no fee ✅
  - Redeem within lock period → early fee applied ✅
  - Fee goes to `feeCollector` ✅
  - Partial redeem ✅
  - NAV-adjusted payout ✅
  - `notifyRedeem` called ✅

#### 📄 State after TASK 5.7

**🇮🇹** Redeem con early redemption fee implementato. La fee si applica solo entro il lock period.

**🇬🇧** Redeem with early redemption fee implemented. Fee applies only within the lock period.

---

### TASK 5.8 — Add transferFrom override with mintedAt propagation

- [ ] **5.8.1** Override `transferFrom(uint256 fromTokenId_, address to_, uint256 value_)`:
  ```solidity
  function transferFrom(
      uint256 fromTokenId_,
      address to_,
      uint256 value_
  ) public payable override returns (uint256 newTokenId) {
      newTokenId = super.transferFrom(fromTokenId_, to_, value_);
      mintedAt[newTokenId] = mintedAt[fromTokenId_];
  }
  ```
- [ ] **5.8.2** Write tests:
  - Transfer creates new tokenId ✅
  - New token inherits `mintedAt` from source ✅
  - Recipient cannot reset lock period via transfer ✅
  - `entryYields` also propagated to new token ✅

#### 📄 State after TASK 5.8

**🇮🇹** `mintedAt` si propaga correttamente al token derivato. Il lock period non può essere aggirato tramite transfer.

**🇬🇧** `mintedAt` correctly propagates to derived token. Lock period cannot be bypassed via transfer.

---

### TASK 5.9 — Add Yield Accrual with management fee (`claimYield`)

- [ ] **5.9.1** Store `mapping(uint256 tokenId => uint256 lastClaimTimestamp) public lastClaimed`
- [ ] **5.9.2** Initialize `lastClaimed[tokenId] = block.timestamp` at mint
- [ ] **5.9.3** Implement `claimYield(uint256 tokenId)`:
  ```solidity
  require(ownerOf(tokenId) == msg.sender);
  uint256 slot = slotOf(tokenId);
  uint256 grossYield = bondOracle.getYield(slot);
  uint256 netYield = grossYield - MANAGEMENT_FEE_BPS;
  uint256 value = balanceOf(tokenId);
  uint256 elapsed = block.timestamp - lastClaimed[tokenId];

  uint256 accrued = value * netYield * elapsed / (10000 * 365 days);
  uint256 feeAccrued = value * MANAGEMENT_FEE_BPS * elapsed / (10000 * 365 days);

  lastClaimed[tokenId] = block.timestamp;
  paymentToken.transferFrom(treasury, msg.sender, accrued);
  paymentToken.transferFrom(treasury, feeCollector, feeAccrued);
  emit YieldClaimed(msg.sender, tokenId, accrued, feeAccrued);
  ```
- [ ] **5.9.4** Reset `lastClaimed` on `transferFrom` to prevent double-claiming
- [ ] **5.9.5** Write yield tests:
  - 30 days at 4.50% gross → correct net accrual (4.00%) ✅
  - Management fee correctly routed to `feeCollector` ✅
  - Claim twice without time passing → accrued = 0 ✅
  - Transfer resets `lastClaimed` ✅

#### 📄 State after TASK 5.9

**🇮🇹** `claimYield()` paga lo yield netto all'holder e la management fee al `feeCollector`. Il modello di revenue del protocollo è completo.

**🇬🇧** `claimYield()` pays net yield to holder and management fee to `feeCollector`. Protocol revenue model is complete.

---

### TASK 5.10 — Add Risk Controls

- [ ] **5.10.1** Store `mapping(uint256 slot => uint256) public maxSupplyPerSlot`
- [ ] **5.10.2** Store `mapping(uint256 slot => uint256) public totalSupplyPerSlot`
- [ ] **5.10.3** Add check in mint: `require(totalSupplyPerSlot[slot] + value <= maxSupplyPerSlot[slot])`
- [ ] **5.10.4** Update `totalSupplyPerSlot` on mint and redeem
- [ ] **5.10.5** Implement `setMaxSupplyPerSlot(uint256 slot, uint256 maxSupply)` — `onlyOwner`
- [ ] **5.10.6** Write tests: within cap, exceeding cap, redeem frees capacity

#### 📄 State after TASK 5.10

**🇮🇹** Risk controls implementati. Cap per slot limita la concentrazione di rischio.

**🇬🇧** Risk controls implemented. Per-slot cap limits risk concentration.

---

### TASK 5.11 — Full Token Test Suite

- [ ] **5.11.1** Integration test combining all features:
  - Mint: USDC payment + mint fee split + PoR check + compliance check ✅
  - Mint: insufficient reserves ❌
  - Mint: stale reserve data ❌
  - Mint: unverified recipient ❌
  - Mint: slot cap exceeded ❌
  - Transfer: verified wallets, mintedAt inherited ✅
  - Transfer: unverified recipient ❌
  - Transfer: frozen sender ❌
  - Transfer: stale oracle ❌
  - Redeem after lock period: no fee, correct USDC payout ✅
  - Redeem within lock period: early fee applied and routed to feeCollector ✅
  - claimYield: net yield to holder + management fee to feeCollector ✅
  - claimYield after transfer: lastClaimed reset ✅
  - NAV changes with yield movement (rate hike → NAV drops) ✅
  - Forced transfer bypasses compliance ✅
  - Full lifecycle: mint → yield accrual → transfer (mintedAt inherited) → early redeem (fee applied) ✅
  - Full lifecycle: mint → yield accrual → wait lock period → redeem (no fee) ✅
  - ReserveOracle trackedSupplyValue correctly updated through mint → redeem ✅

#### 📄 State after TASK 5.11

**🇮🇹** `TreasuryBondToken.sol` completo e testato. Tutti i flussi critici coperti incluso il modello fee completo e il lock period.

**🇬🇧** `TreasuryBondToken.sol` complete and tested. All critical flows covered including the full fee model and lock period enforcement.

---

## PHASE 6 — Deploy & Integration

### TASK 6.1 — Deployment scripts

- [ ] **6.1.1** `script/DeployIdentity.s.sol`
- [ ] **6.1.2** `script/RegisterInvestor.s.sol`
- [ ] **6.1.3** `script/DeployReserveOracle.s.sol` — set custodian, initial reserve balance
- [ ] **6.1.4** `script/DeployOracle.s.sol` — deploy `BondOracle` + `BondFunctionsConsumer`
- [ ] **6.1.5** `script/DeployAutomation.s.sol`
- [ ] **6.1.6** `script/DeployToken.s.sol` — pass `identityRegistry`, `bondOracle`, `reserveOracle`, `paymentToken`, `treasury`, `feeCollector`
- [ ] **6.1.7** `script/WireContracts.s.sol` — set all cross-contract references
- [ ] **6.1.8** Save all addresses to `deployments/sepolia.json`

#### 📄 State after TASK 6.1

**🇮🇹** Tutti i contratti deployati su Sepolia e collegati.

**🇬🇧** All contracts deployed on Sepolia and wired.

---

### TASK 6.2 — End-to-end integration test

- [ ] **6.2.1** Deploy entire system in a Foundry fork test
- [ ] **6.2.2** Register two investor identities
- [ ] **6.2.3** Custodian pushes initial reserve balance (e.g. 1,000,000 USDC)
- [ ] **6.2.4** Trigger manual yield fetch → verify yield stored in `BondOracle`
- [ ] **6.2.5** Mint slot 10Y to investor A → verify: mint fee to feeCollector, remaining USDC to treasury, entryYield and mintedAt saved, PoR check passed
- [ ] **6.2.6** Verify `ReserveOracle.trackedSupplyValue` increased by net mint cost
- [ ] **6.2.7** Attempt mint exceeding reserve balance ❌
- [ ] **6.2.8** Transfer value from A to B → verify new tokenId inherits `mintedAt` from A's token
- [ ] **6.2.9** Attempt transfer to unregistered wallet ❌
- [ ] **6.2.10** Freeze investor A → attempt transfer ❌
- [ ] **6.2.11** Simulate oracle staleness via `vm.warp(+73h)` → attempt transfer ❌
- [ ] **6.2.12** Simulate reserve staleness via `vm.warp(+25h)` → attempt mint ❌
- [ ] **6.2.13** Forced transfer from frozen wallet ✅
- [ ] **6.2.14** Update oracle yield (rate hike) → verify NAV drops per modified duration
- [ ] **6.2.15** Warp 30 days → investor B calls `claimYield()` → verify net yield to B + management fee to feeCollector
- [ ] **6.2.16** Investor B redeems within lock period → verify early redemption fee applied and routed to feeCollector
- [ ] **6.2.17** Warp past lock period → investor B redeems remainder → no early fee ✅
- [ ] **6.2.18** Verify `ReserveOracle.trackedSupplyValue` decreased correctly after redeems
- [ ] **6.2.19** Attempt mint exceeding `maxSupplyPerSlot` ❌

#### 📄 State after TASK 6.2

**🇮🇹** Protocollo validato end-to-end. Tutti i flussi critici coperti incluso il ciclo fee completo.

**🇬🇧** Protocol validated end-to-end. All critical flows covered including the complete fee lifecycle.

---

### TASK 6.3 — README.md

- [ ] **6.3.1** Project overview and architecture diagram
- [ ] **6.3.2** Rolling pool model explanation (no 1:1 token → T-Bill mapping)
- [ ] **6.3.3** Fee model section: mint fee, management fee, early redemption fee with examples
- [ ] **6.3.4** Lock period section: rationale, table per slot, mintedAt propagation
- [ ] **6.3.5** Bond model explanation (link to `bondstructure.md`)
- [ ] **6.3.6** Each contract and its role
- [ ] **6.3.7** Deployed addresses on Sepolia with Etherscan links
- [ ] **6.3.8** Instructions: clone, install, test, deploy
- [ ] **6.3.9** Chainlink Functions and Automation setup
- [ ] **6.3.10** Known limitations

#### 📄 State after TASK 6.3

**🇮🇹** Progetto completo e documentato.

**🇬🇧** Project complete and documented.

---

## Dependency Order & Parallelism

### Deploy order (sequential)

```
1. ClaimTopicsRegistry + ClaimIssuer + TrustedIssuersRegistry
   ↓
2. IdentityRegistryStorage + IdentityRegistry
   ↓
3. Register investors
   ↓
4. ReserveOracle
   ↓
5. BondOracle
   ↓
6. BondFunctionsConsumer (needs BondOracle)
   ↓
7. BondAutomation (needs BondFunctionsConsumer)
   ↓
8. TreasuryBondToken (needs IdentityRegistry + BondOracle + ReserveOracle + feeCollector)
   ↓
9. Wire: set tokenContract on ReserveOracle
```

### Independent tracks (can be developed in parallel)

```
┌─────────────────────────────┐    ┌──────────────────────────────┐
│  TRACK A — Identity/KYC     │    │  TRACK B — Oracle Layers      │
│  TASK 1.1 → 1.3             │    │  TASK 2.1 → 4.1              │
└──────────┬──────────────────┘    └──────────┬───────────────────┘
           │                                  │
           └──────────┬───────────────────────┘
                      ▼
           ┌──────────────────────────────────┐
           │  TRACK C — Token                  │
           │  TASK 5.1  Understand ERC-3525    │
           │  TASK 5.2  Base token             │
           │  TASK 5.3  Compliance             │
           │  TASK 5.4  NAV model              │
           │  TASK 5.5  Fee + lock constants   │
           │  TASK 5.6  Mint with fee + PoR    │
           │  TASK 5.7  Redeem + early fee     │
           │  TASK 5.8  transferFrom + mintedAt│
           │  TASK 5.9  claimYield + mgmt fee  │
           │  TASK 5.10 Risk controls          │
           │  TASK 5.11 Full test suite        │
           └──────────┬───────────────────────┘
                      ▼
           ┌──────────────────────┐
           │  TRACK D — Integration│
           │  TASK 6.1 → 6.3      │
           └──────────────────────┘
```
