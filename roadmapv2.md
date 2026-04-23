# TreasuriFi Protocol — Roadmap

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│              TreasuryBondToken (ERC-3525)                │
│  4 slots = 2Y, 5Y, 10Y, 30Y yield curve exposure       │
│  value = size of exposure to that maturity bucket       │
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

**Simplification choices (vs full T-REX):**

- No TREXFactory / ImplementationAuthority / IAFactory / proxy architecture
- No ModularCompliance or compliance modules
- Direct deploy of IdentityRegistry, ClaimIssuer, Identity contracts
- Compliance enforced via `_beforeValueTransfer()` hook, not T-REX Token.sol

**Backing model:** SPV + Proof of Reserve

- Off-chain custodian (simulated on testnet) holds T-Bills backing all outstanding tokens
- `ReserveOracle` attests the custodian's reserve balance on-chain
- `mint()` checks `reserveOracle.isReserveSufficient(mintCost)` before issuance — blocks if underbacked
- Reserve data stale after 24 hours — stricter than yield oracle (72h) because backing is more critical
- In production, `ReserveOracle` is replaced by a Chainlink PoR feed with no changes to the token contract

**Bond model:** Yield Curve Exposure (see `bondstructure.md`)

- 4 fixed slots = maturity buckets (2Y, 5Y, 10Y, 30Y)
- Tokens in the same slot are fungible (transferValue enabled)
- NAV = modified duration model: `par × [1 - modDuration × (currentYield - entryYield)]`
- Carry accrual: holders earn yield pro-rata via `claimYield()`
- Mint/redeem priced in USDC at current NAV
- Risk controls: `maxSupplyPerSlot` caps total exposure per bucket

**Financial model constants:**

| Slot | Maturity | Modified Duration | FRED Series |
| ---- | -------- | ----------------- | ----------- |
| 1    | 2Y       | 1.9               | DGS2        |
| 2    | 5Y       | 4.5               | DGS5        |
| 3    | 10Y      | 8.7               | DGS10       |
| 4    | 30Y      | 19.5              | DGS30       |

---

## PHASE 1 — Identity & Compliance (ONCHAINID + T-REX direct deploy)

> No factory. Deploy IdentityRegistry and ClaimIssuer directly.
> Use real ONCHAINID Identity contracts with claim-based KYC verification.
> This demonstrates understanding of the ERC-3643 identity model
> without the enterprise deployment infrastructure.

---

### TASK 1.1 — Understand the ONCHAINID + T-REX identity model

Before writing any code, understand the claim-based identity system.

- [ ] **1.1.1** Read the ONCHAINID documentation — understand the `Identity` contract (one per investor)
- [ ] **1.1.2** Understand `ClaimIssuer` — the entity that signs KYC claims using ECDSA
- [ ] **1.1.3** Understand the claim lifecycle: ClaimIssuer signs → claim added to Identity → IdentityRegistry verifies
- [ ] **1.1.4** Understand `IdentityRegistry` — maps `wallet → Identity contract`, calls `isVerified(wallet)` to check claims
- [ ] **1.1.5** Understand `IdentityRegistryStorage` — separate storage that IdentityRegistry reads from
- [ ] **1.1.6** Understand `ClaimTopicsRegistry` — defines which claim topics are required (e.g. topic `1` = KYC)
- [ ] **1.1.7** Understand `TrustedIssuersRegistry` — defines which ClaimIssuers are trusted and for which topics

📚 **Reference:**

- ONCHAINID documentation → https://docs.onchainid.com
- ONCHAINID GitHub → https://github.com/onchain-id/solidity
- `Identity.sol` → `lib/solidity/contracts/Identity.sol`
- `ClaimIssuer.sol` → `lib/solidity/contracts/ClaimIssuer.sol`
- T-REX documentation → https://docs.tokeny.com
- `IdentityRegistry.sol` → `lib/T-REX/contracts/registry/implementation/IdentityRegistry.sol`
- `IdentityRegistryStorage.sol` → `lib/T-REX/contracts/registry/implementation/IdentityRegistryStorage.sol`
- `ClaimTopicsRegistry.sol` → `lib/T-REX/contracts/registry/implementation/ClaimTopicsRegistry.sol`
- `TrustedIssuersRegistry.sol` → `lib/T-REX/contracts/registry/implementation/TrustedIssuersRegistry.sol`
- ERC-3643 standard → https://eips.ethereum.org/EIPS/eip-3643

#### 📄 State after TASK 1.1

**🇮🇹 Italiano**
Nessun codice scritto. Hai una comprensione chiara del modello claim-based identity: sai che ogni investor ha un contratto `Identity`, che il `ClaimIssuer` firma i claim KYC, e che `IdentityRegistry.isVerified()` è la funzione che il tuo token chiamerà per bloccare i trasferimenti non compliant.

**🇬🇧 English**
No code written. You have a clear understanding of the claim-based identity model: you know that each investor has an `Identity` contract, that the `ClaimIssuer` signs KYC claims, and that `IdentityRegistry.isVerified()` is the function your token will call to block non-compliant transfers.

---

### TASK 1.2 — Write `script/DeployIdentity.s.sol`

Deploy the identity/compliance layer directly — no factory, no proxies.

- [ ] **1.2.1** Deploy `ClaimTopicsRegistry` — call `addClaimTopic(1)` to register topic 1 (KYC)
- [ ] **1.2.2** Deploy `ClaimIssuer` (from ONCHAINID) — the entity that will sign investor KYC claims
- [ ] **1.2.3** Deploy `TrustedIssuersRegistry` — call `addTrustedIssuer(claimIssuer, [1])` to trust the ClaimIssuer for topic 1
- [ ] **1.2.4** Deploy `IdentityRegistryStorage`
- [ ] **1.2.5** Deploy `IdentityRegistry` — pass addresses of `TrustedIssuersRegistry`, `ClaimTopicsRegistry`, `IdentityRegistryStorage`
- [ ] **1.2.6** Bind `IdentityRegistryStorage` to `IdentityRegistry` by calling `bindIdentityRegistry(identityRegistry)` on the storage
- [ ] **1.2.7** Save all deployed addresses to `deployments/identity.json`

📚 **Reference:**

- `ClaimTopicsRegistry.sol` → `lib/T-REX/contracts/registry/implementation/ClaimTopicsRegistry.sol`
- `TrustedIssuersRegistry.sol` → `lib/T-REX/contracts/registry/implementation/TrustedIssuersRegistry.sol`
- `IdentityRegistryStorage.sol` → `lib/T-REX/contracts/registry/implementation/IdentityRegistryStorage.sol`
- `IdentityRegistry.sol` → `lib/T-REX/contracts/registry/implementation/IdentityRegistry.sol`
- `ClaimIssuer.sol` → `lib/solidity/contracts/ClaimIssuer.sol`
- Foundry scripting → https://book.getfoundry.sh/tutorials/solidity-scripting

#### 📄 State after TASK 1.2

**🇮🇹 Italiano**
Il layer di compliance è deployato: ClaimTopicsRegistry (con topic KYC), TrustedIssuersRegistry (con ClaimIssuer trusted), IdentityRegistryStorage e IdentityRegistry collegati tra loro. Nessun investor è ancora registrato.

**🇬🇧 English**
The compliance layer is deployed: ClaimTopicsRegistry (with KYC topic), TrustedIssuersRegistry (with trusted ClaimIssuer), IdentityRegistryStorage and IdentityRegistry wired together. No investor is registered yet.

---

### TASK 1.3 — Write `script/RegisterInvestor.s.sol`

Register a new investor through the full ONCHAINID claim flow, handling the realistic case where the investor may already have an Identity on-chain (from another protocol).

- [ ] **1.3.0** Check if the investor already has an Identity on this chain:
  - Query `IdFactory.getIdentity(investorWallet)` — returns `address(0)` if none exists
  - If Identity exists, skip deploy (1.3.1) and go to 1.3.2
  - If Identity exists and already has a valid KYC claim from your trusted issuer, skip 1.3.1 and 1.3.2 and go directly to 1.3.3
- [ ] **1.3.1** Deploy a new `Identity.sol` contract for the investor wallet (directly, no IdFactory) — only if no Identity exists
- [ ] **1.3.2** Check if the KYC claim already exists on the Identity:
  - Compute `claimId = keccak256(abi.encode(claimIssuerAddress, topic))`
  - Call `Identity.getClaim(claimId)` — skip signing and `addClaim` if a valid claim from your issuer is already present
  - If claim is missing, use the `ClaimIssuer` signing key to create it off-chain:
    - Hash: `keccak256(abi.encode(identityAddress, topic, data))`
    - Sign the hash with the ClaimIssuer's private key (ECDSA)
- [ ] **1.3.3** Add the signed claim to the investor's `Identity` contract by calling `addClaim(topic, scheme, issuer, signature, data, uri)` — only if claim was missing
- [ ] **1.3.4** Call `IdentityRegistry.registerIdentity(wallet, identityContract, countryCode)` to link wallet → identity
- [ ] **1.3.5** Verify: call `IdentityRegistry.isVerified(wallet)` — must return `true`
- [ ] **1.3.6** Write a Foundry test:
  - Register investor A with no prior Identity → full flow → `isVerified(A)` returns `true`
  - Register investor B with existing Identity but no KYC claim → skip deploy, add claim → `isVerified(B)` returns `true`
  - Register investor C with existing Identity and existing claim from your trusted issuer → skip deploy and addClaim → `isVerified(C)` returns `true`
  - Investor D not registered → `isVerified(D)` returns `false`
  - Register investor E with claim from untrusted issuer → `isVerified(E)` returns `false`
  - Register investor F, then ClaimIssuer revokes the claim → `isVerified(F)` returns `false` without touching `IdentityRegistry`

📚 **Reference:**

- ONCHAINID claim issuance → https://docs.onchainid.com/developers/claim-issuance
- `IdFactory.getIdentity()` → `lib/solidity/contracts/factory/IdFactory.sol`
- `Identity.sol` `getClaim()` + `addClaim()` → `lib/solidity/contracts/Identity.sol`
- `ClaimIssuer.sol` + `revokeClaimBySignature()` → `lib/solidity/contracts/ClaimIssuer.sol`
- `IdentityRegistry.registerIdentity()` → `lib/T-REX/contracts/registry/implementation/IdentityRegistry.sol`
- Foundry `vm.sign()` for ECDSA signatures → https://book.getfoundry.sh/cheatcodes/sign

#### 📄 State after TASK 1.3

**🇮🇹 Italiano**
Il layer di identità è completo, testato e realistico. Lo script gestisce i tre scenari possibili (deploy completo, riuso con claim mancante, riuso completo) e i test coprono sia i path positivi sia i casi di failure architetturalmente rilevanti: issuer non fidato e claim revocato lato `ClaimIssuer` senza toccare l'`IdentityRegistry`. Il contratto `IdentityRegistry` è la fonte di verità sulla compliance KYC che `TreasuryBondToken` interrogherà.

**🇬🇧 English**
The identity layer is complete, tested, and production-realistic. The script handles all three possible scenarios (full deploy, reuse with missing claim, full reuse) and the tests cover both happy paths and the architecturally relevant failure cases: untrusted issuer and claim revoked on the `ClaimIssuer` side without modifying the `IdentityRegistry`. The `IdentityRegistry` contract is the KYC compliance source of truth that `TreasuryBondToken` will query.

---

## PHASE 2 — Reserve Layer (SPV + Proof of Reserve)

> Build the reserve backing layer before the yield oracle and token.
> ReserveOracle is a mock of a Chainlink Proof of Reserve feed — architecturally
> identical to production, with a simulated custodian instead of a real one.
> The token depends on this contract for its mint gate.

---

### TASK 2.1 — Understand the Proof of Reserve model

Before writing any code, understand how real RWA protocols back their tokens.

- [ ] **2.1.1** Study how Ondo Finance (OUSG) and Backed Finance use off-chain custodians with on-chain reserve attestation
- [ ] **2.1.2** Understand the Chainlink PoR `AggregatorV3Interface` — the production interface this mock simulates
- [ ] **2.1.3** Understand the separation: smart contracts handle settlement, custodians handle real-world custody, oracles bridge the two
- [ ] **2.1.4** Understand what `isReserveSufficient(mintCost)` must check: `reserveBalance >= currentSupplyValue + mintCost`

📚 **Reference:**

- Chainlink Proof of Reserve → https://docs.chain.link/data-feeds/proof-of-reserve
- Ondo Finance → https://github.com/ondoprotocol/tokenized-funds
- Backed Finance → https://github.com/backed-fi/backed-protocol
- Chainlink `AggregatorV3Interface` → `lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol`

#### 📄 State after TASK 2.1

**🇮🇹 Italiano**
Nessun codice scritto. Hai una comprensione chiara del modello SPV + PoR: sai che il custodian detiene asset reali off-chain, che l'oracle attesta il saldo on-chain, e che il contratto token blocca il mint se le riserve sono insufficienti.

**🇬🇧 English**
No code written. You have a clear understanding of the SPV + PoR model: the custodian holds real assets off-chain, the oracle attests the balance on-chain, and the token contract blocks minting if reserves are insufficient.

---

### TASK 2.2 — Write `IReserveOracle.sol` and `ReserveOracle.sol`

Mock Proof of Reserve contract. On testnet the custodian is simulated; in production this interface is implemented by a Chainlink PoR feed.

- [ ] **2.2.1** Define `IReserveOracle` interface in `src/interfaces/IReserveOracle.sol`:
  - `getReserves() external view returns (uint256)` — total USD value attested by custodian (6 decimals, USDC-denominated)
  - `isReserveSufficient(uint256 usdcAmount) external view returns (bool)` — true if reserves cover current supply + new mint
  - `isStale() external view returns (bool)` — true if reserve data is older than 24 hours
  - `lastUpdated() external view returns (uint256)` — timestamp of last reserve update
- [ ] **2.2.2** Implement `ReserveOracle.sol`:
  - `reserveBalance` — USDC value (6 decimals) attested by custodian
  - `trackedSupplyValue` — total USDC value of all outstanding tokens (updated by token contract on mint/redeem)
  - `custodian` — address authorized to push reserve updates (simulates the Chainlink node / custodian)
  - `STALENESS_THRESHOLD = 24 hours` — stricter than yield oracle (72h) because backing is more critical
  - `updateReserves(uint256 newBalance)` — callable only by `custodian`
  - `notifyMint(uint256 usdcAmount)` / `notifyRedeem(uint256 usdcAmount)` — callable only by `TreasuryBondToken`, updates `trackedSupplyValue`
  - `isReserveSufficient(uint256 usdcAmount)` — returns `reserveBalance >= trackedSupplyValue + usdcAmount`
  - `isStale()` — returns `block.timestamp > lastUpdated + STALENESS_THRESHOLD`
  - `setCustodian(address)` — `onlyOwner`
  - `setTokenContract(address)` — `onlyOwner`, authorizes who can call `notifyMint`/`notifyRedeem`
- [ ] **2.2.3** Write unit tests:
  - Fresh reserves, sufficient → `isReserveSufficient(amount)` returns `true` ✅
  - Fresh reserves, insufficient → `isReserveSufficient(amount)` returns `false` ✅
  - Reserves updated → `getReserves()` returns new value ✅
  - `notifyMint` increases `trackedSupplyValue` ✅
  - `notifyRedeem` decreases `trackedSupplyValue` ✅
  - Unauthorized caller on `updateReserves` ❌ (expect revert)
  - Unauthorized caller on `notifyMint` ❌ (expect revert)
  - Stale data after 24h + 1s → `isStale()` returns `true` ✅
  - Fresh data → `isStale()` returns `false` ✅
  - `isReserveSufficient` reverts if data is stale ✅

📚 **Reference:**

- Chainlink PoR documentation → https://docs.chain.link/data-feeds/proof-of-reserve
- `AggregatorV3Interface` pattern → `lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol`
- OpenZeppelin `Ownable` → `lib/openzeppelin-contracts/contracts/access/Ownable.sol`
- Foundry `vm.warp` → https://book.getfoundry.sh/cheatcodes/warp

#### 📄 State after TASK 2.2

**🇮🇹 Italiano**
`ReserveOracle.sol` e `IReserveOracle.sol` sono completi e testati. Il contratto funge da mock Proof of Reserve: il custodian aggiorna il saldo delle riserve, il token notifica mint e redeem, e `isReserveSufficient()` blocca emissioni non coperte. L'architettura è identica alla produzione — solo il custodian è simulato.

**🇬🇧 English**
`ReserveOracle.sol` and `IReserveOracle.sol` are complete and tested. The contract acts as a mock Proof of Reserve: the custodian updates the reserve balance, the token notifies mints and redeems, and `isReserveSufficient()` blocks underbacked issuance. The architecture is identical to production — only the custodian is simulated.

---

## PHASE 3 — Oracle Layer (Chainlink Functions)

> Build the yield data pipeline. Two contracts with separation of concerns:
> BondOracle = pure storage, BondFunctionsConsumer = Chainlink Functions client.

---

### TASK 3.1 — Write `BondOracle.sol`

On-chain storage contract that receives and exposes yield data per maturity bucket. Pure storage — no Chainlink dependency.

- [ ] **3.1.1** Define `BondData` struct: `uint256 yieldBPS`, `uint256 lastUpdated`
- [ ] **3.1.2** Define `mapping(uint256 slot => BondData) public bonds` — one entry per maturity bucket (slots 1–4)
- [ ] **3.1.3** Store `address public authorizedUpdater` — only `BondFunctionsConsumer` can write
- [ ] **3.1.4** Implement `setAuthorizedUpdater(address)` — restricted to `owner`
- [ ] **3.1.5** Implement `updateYield(uint256 slot, uint256 yieldBPS)` — restricted to `authorizedUpdater`
- [ ] **3.1.6** Implement `getYield(uint256 slot)` — returns latest yield for a given maturity bucket
- [ ] **3.1.7** Implement `isStale(uint256 slot)` — returns `true` if `lastUpdated < block.timestamp - 72 hours`
- [ ] **3.1.8** Emit event: `YieldUpdated(uint256 indexed slot, uint256 yieldBPS, uint256 timestamp)`
- [ ] **3.1.9** Define `IBondOracle` interface in `src/interfaces/IBondOracle.sol` — used by `TreasuryBondToken`
- [ ] **3.1.10** Write unit tests: update yield, staleness check, unauthorized caller revert, getYield returns correct data

📚 **Reference:**

- Solidity mappings and structs → https://docs.soliditylang.org/en/latest/types.html#mappings
- OpenZeppelin `Ownable` → `lib/openzeppelin-contracts/contracts/access/Ownable.sol`
- Foundry unit testing → https://book.getfoundry.sh/forge/tests

#### 📄 State after TASK 3.1

**🇮🇹 Italiano**
`BondOracle.sol` è deployabile e funge da fonte di verità on-chain per i rendimenti dei 4 maturity bucket. Sa distinguere un dato fresco da uno stale. Non ha dipendenze Chainlink — è puro storage con access control. `IBondOracle.sol` è definita per l'uso nel token.

**🇬🇧 English**
`BondOracle.sol` is deployable and acts as the on-chain source of truth for yields of the 4 maturity buckets. It can distinguish fresh data from stale. It has no Chainlink dependencies — it is pure storage with access control. `IBondOracle.sol` is defined for use in the token.

---

### TASK 3.2 — Write `BondFunctionsConsumer.sol`

Chainlink Functions client that fetches FRED API data off-chain and writes results to `BondOracle`.

- [ ] **3.2.1** Import and inherit `FunctionsClient` from Chainlink
- [ ] **3.2.2** Import `ConfirmedOwner` for access control
- [ ] **3.2.3** Declare state variables: `subscriptionId`, `gasLimit`, `donId`, reference to `BondOracle`
- [ ] **3.2.4** Implement `sendRequest(uint256 slot)`:
  - Build a `FunctionsRequest.Request` using the library
  - Encode `args[0] = slot` as a string
  - Call `_sendRequest()` with the encoded request, subscription ID, gas limit, don ID
  - Store `requestId → slot` in a mapping for use in `fulfillRequest`
- [ ] **3.2.5** Implement `fulfillRequest(bytes32 requestId, bytes memory response, bytes memory err)`:
  - If `err` is non-empty: store in `s_lastError`, emit `RequestFailed`
  - Otherwise: decode `response` as `uint256 yieldBPS`, call `bondOracle.updateYield(slot, yieldBPS)`
- [ ] **3.2.6** Emit events: `YieldRequestSent`, `YieldRequestFulfilled`, `RequestFailed`
- [ ] **3.2.7** Write the off-chain JS source script (`functions/fetchYield.js`):
  - Map `args[0]` (slot) to FRED series ID: `1→DGS2`, `2→DGS5`, `3→DGS10`, `4→DGS30`
  - Call FRED API using `secrets.fredApiKey`
  - Parse `observations[0].value` (e.g. `"4.29"`)
  - Return `Functions.encodeUint256(Math.round(parseFloat(value) * 100))` → `429`
- [ ] **3.2.8** Configure Chainlink Functions subscription on Sepolia via the Functions dashboard
- [ ] **3.2.9** Upload `fredApiKey` as an encrypted secret using the Chainlink Functions CLI
- [ ] **3.2.10** Fund the subscription with testnet LINK
- [ ] **3.2.11** Write integration test simulating a mock DON response

📚 **Reference:**

- Chainlink Functions getting started → https://docs.chain.link/chainlink-functions/getting-started
- `FunctionsClient.sol` → `lib/chainlink-brownie-contracts/contracts/src/v0.8/functions/v1_3_0/FunctionsClient.sol`
- `FunctionsRequest.sol` library → `lib/chainlink-brownie-contracts/contracts/src/v0.8/functions/dev/v1_X/libraries/FunctionsRequest.sol`
- `ConfirmedOwner.sol` → `lib/chainlink-brownie-contracts/contracts/src/v0.8/shared/access/ConfirmedOwner.sol`
- Chainlink Functions — using secrets → https://docs.chain.link/chainlink-functions/tutorials/api-use-secrets
- FRED API documentation → https://fred.stlouisfed.org/docs/api/fred/series_observations.html
- FRED series: DGS2, DGS5, DGS10, DGS30 → https://fred.stlouisfed.org/series/DGS10
- Chainlink Functions Playground → https://functions.chain.link/playground

#### 📄 State after TASK 3.2

**🇮🇹 Italiano**
Il pipeline oracle è completamente funzionante end-to-end. `BondFunctionsConsumer` invia lo script JS al DON, riceve il rendimento dalla FRED API e lo scrive in `BondOracle`. Il contratto gestisce sia il successo che gli errori. La subscription è configurata su Sepolia.

**🇬🇧 English**
The oracle pipeline is fully operational end-to-end. `BondFunctionsConsumer` sends the JS script to the DON, receives the yield from the FRED API, and writes it to `BondOracle`. The contract handles both success and errors. The subscription is configured on Sepolia.

---

## PHASE 4 — Automation Layer (Chainlink Automation)

---

### TASK 4.1 — Write `BondAutomation.sol`

Automatically triggers `BondFunctionsConsumer.sendRequest()` for all 4 slots every 24 hours.

- [ ] **4.1.1** Import and implement `AutomationCompatibleInterface` from Chainlink
- [ ] **4.1.2** Store references to `BondFunctionsConsumer` and `BondOracle`
- [ ] **4.1.3** Declare `uint256 public interval = 24 hours` and `uint256 public lastUpkeep`
- [ ] **4.1.4** Declare `uint256 public constant SLOT_COUNT = 4`
- [ ] **4.1.5** Implement `checkUpkeep(bytes calldata)`:
  - Return `upkeepNeeded = block.timestamp >= lastUpkeep + interval`
- [ ] **4.1.6** Implement `performUpkeep(bytes calldata)`:
  - Require `checkUpkeep()` is true
  - Loop over slots `1` to `SLOT_COUNT`, call `functionsConsumer.sendRequest(slot)` for each
  - Update `lastUpkeep = block.timestamp`
  - Emit `UpkeepPerformed(block.timestamp)`
- [ ] **4.1.7** Implement `setInterval(uint256 newInterval)` — owner only, for flexibility
- [ ] **4.1.8** Register the contract on the Chainlink Automation dashboard on Sepolia
- [ ] **4.1.9** Fund the Automation upkeep with testnet LINK
- [ ] **4.1.10** Write unit tests: upkeep not needed (interval not elapsed), upkeep triggered, interval update

📚 **Reference:**

- Chainlink Automation compatible contracts → https://docs.chain.link/chainlink-automation/guides/compatible-contracts
- `AutomationCompatibleInterface` → `lib/chainlink-brownie-contracts/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol`
- Chainlink Automation dashboard (Sepolia) → https://automation.chain.link/sepolia

#### 📄 State after TASK 4.1

**🇮🇹 Italiano**
L'intero layer oracle è autonomo. `BondAutomation` triggera automaticamente l'aggiornamento dei rendimenti per tutti e 4 i maturity bucket ogni 24 ore. I dati FRED API fluiscono on-chain in modo completamente automatizzato.

**🇬🇧 English**
The entire oracle layer is autonomous. `BondAutomation` automatically triggers yield updates for all 4 maturity buckets every 24 hours. FRED API data flows on-chain in a fully automated way.

---

## PHASE 5 — Token Layer (ERC-3525 + T-REX Compliance + PoR mint gate)

> The token is built last because it depends on all previous layers.
> Bond model: 4 fixed slots = yield curve exposure (see bondstructure.md).
> Compliance: query IdentityRegistry.isVerified() in \_beforeValueTransfer().
> Backing: query ReserveOracle.isReserveSufficient() in mint().

---

### TASK 5.1 — Understand ERC-3525

Before writing the token, read the standard and the Solv Protocol reference implementation.

- [ ] **5.1.1** Read the ERC-3525 EIP to understand the slot/value model and how it extends ERC-721
- [ ] **5.1.2** Understand how `slot` works — all tokens with the same slot are fungible with each other
- [ ] **5.1.3** Understand how `value` works — the fungible quantity held within a semi-fungible token
- [ ] **5.1.4** Understand `transferValue()` — transfer value between two tokens of the same slot
- [ ] **5.1.5** Read the Solv Protocol reference implementation — identify which contracts to inherit and which hooks to override
- [ ] **5.1.6** Understand `_beforeValueTransfer()` — the hook that runs before any value movement

📚 **Reference:**

- ERC-3525 official EIP → https://eips.ethereum.org/EIPS/eip-3525
- Solv Protocol ERC-3525 reference implementation → `lib/erc-3525/contracts/ERC3525.sol`
- `ERC3525SlotEnumerable.sol` → `lib/erc-3525/contracts/ERC3525SlotEnumerable.sol`

#### 📄 State after TASK 5.1

**🇮🇹 Italiano**
Nessun codice scritto. Hai una comprensione solida del modello slot/value di ERC-3525, sai quale contratto ereditare da Solv Protocol e quali hook sovrascrivere per aggiungere la compliance T-REX.

**🇬🇧 English**
No code written. You have a solid understanding of the ERC-3525 slot/value model, know which contract to inherit from Solv Protocol, and which hooks to override to add T-REX compliance.

---

### TASK 5.2 — Write `TreasuryBondToken.sol` — Base ERC-3525

- [ ] **5.2.1** Import and inherit `ERC3525` from Solv Protocol (`@erc3525/ERC3525.sol`)
- [ ] **5.2.2** Define slot constants:
  ```solidity
  uint256 public constant SLOT_2Y  = 1;  // 2-Year Treasury exposure
  uint256 public constant SLOT_5Y  = 2;  // 5-Year Treasury exposure
  uint256 public constant SLOT_10Y = 3;  // 10-Year Treasury exposure
  uint256 public constant SLOT_30Y = 4;  // 30-Year Treasury exposure
  ```
- [ ] **5.2.3** Implement constructor: set name ("TreasuryFi Bond"), symbol ("TBOND"), value decimals (18)
- [ ] **5.2.4** Implement `slotURI(uint256 slot)` — returns metadata URI per maturity bucket
- [ ] **5.2.5** Implement `contractURI()` — returns contract-level metadata
- [ ] **5.2.6** Write basic test: deploy, verify name/symbol/decimals, verify slot constants

📚 **Reference:**

- `ERC3525.sol` → `lib/erc-3525/contracts/ERC3525.sol`
- `bondstructure.md` for slot design rationale

#### 📄 State after TASK 5.2

**🇮🇹 Italiano**
`TreasuryBondToken.sol` è un token ERC-3525 funzionante nella sua forma base. I 4 slot rappresentano i 4 maturity bucket della curva dei rendimenti Treasury. Il token è mintabile e trasferibile senza restrizioni — la compliance e il PoR gate verranno aggiunti nei task successivi.

**🇬🇧 English**
`TreasuryBondToken.sol` is a working ERC-3525 token in its base form. The 4 slots represent the 4 maturity buckets of the Treasury yield curve. The token is mintable and transferable without restrictions — compliance and PoR gate will be added in subsequent tasks.

---

### TASK 5.3 — Add T-REX compliance to `TreasuryBondToken.sol`

Integrate the T-REX `IdentityRegistry` as an external compliance check in the ERC-3525 transfer hooks.

- [ ] **5.3.1** Import `IIdentityRegistry` from T-REX → `@t-rex/registry/interface/IIdentityRegistry.sol`
- [ ] **5.3.2** Import `IBondOracle` from `src/interfaces/IBondOracle.sol`
- [ ] **5.3.3** Store `IIdentityRegistry public identityRegistry` — set in constructor
- [ ] **5.3.4** Store `IBondOracle public bondOracle` — set in constructor
- [ ] **5.3.5** Store `mapping(address => bool) private frozenWallets`
- [ ] **5.3.6** Override `_beforeValueTransfer(address from, address to, uint256 fromTokenId, uint256 toTokenId, uint256 slot, uint256 value)`:
  - Skip compliance check if `from == address(0)` (mint)
  - `require(identityRegistry.isVerified(to), "Recipient not KYC verified")`
  - `require(!bondOracle.isStale(slot), "Oracle data stale")`
  - `require(!frozenWallets[from], "Sender wallet is frozen")`
- [ ] **5.3.7** Implement `freeze(address wallet)` — `onlyOwner`
- [ ] **5.3.8** Implement `unfreeze(address wallet)` — `onlyOwner`
- [ ] **5.3.9** Implement `forcedTransfer(address from, address to, uint256 tokenId, uint256 value)` — `onlyOwner`, bypasses compliance hook
- [ ] **5.3.10** Emit events: `WalletFrozen`, `WalletUnfrozen`, `ForcedTransfer`

📚 **Reference:**

- `IIdentityRegistry` interface → `lib/T-REX/contracts/registry/interface/IIdentityRegistry.sol`
- ERC-3643 standard → https://eips.ethereum.org/EIPS/eip-3643
- T-REX `Token.sol` (reference for compliance patterns, NOT inherited) → `lib/T-REX/contracts/token/Token.sol`
- `_beforeValueTransfer` hook → `lib/erc-3525/contracts/ERC3525.sol`

#### 📄 State after TASK 5.3

**🇮🇹 Italiano**
Il token è compliance-aware. Ogni trasferimento di valore interroga `IdentityRegistry` e `BondOracle`. Wallet non verificati, wallet frozen e oracle stale bloccano i trasferimenti. L'admin può eseguire forced transfer.

**🇬🇧 English**
The token is compliance-aware. Every value transfer queries `IdentityRegistry` and `BondOracle`. Unverified wallets, frozen wallets, and stale oracle data block transfers. The admin can execute forced transfers.

---

### TASK 5.4 — Add NAV pricing model to `TreasuryBondToken.sol`

Implement a modified duration-based NAV model with entry yield tracking.

- [ ] **5.4.1** Define duration constants:
  ```solidity
  // Modified duration per slot (scaled by 100 for precision)
  uint256 public constant DURATION_2Y  = 190;   // 1.90
  uint256 public constant DURATION_5Y  = 450;   // 4.50
  uint256 public constant DURATION_10Y = 870;   // 8.70
  uint256 public constant DURATION_30Y = 1950;  // 19.50
  uint256 public constant PAR_VALUE = 10000;     // 100.00 in BPS
  uint256 public constant PRECISION = 100;
  ```
- [ ] **5.4.2** Store `mapping(uint256 tokenId => uint256 entryYieldBPS) public entryYields` — the yield at mint time
- [ ] **5.4.3** Store `function getDuration(uint256 slot) public pure returns (uint256)` — returns duration for slot
- [ ] **5.4.4** Implement `getNAV(uint256 tokenId)`:
  ```solidity
  // NAV = par × [1 - modDuration × (currentYield - entryYield)]
  uint256 currentYield = bondOracle.getYield(slot);
  uint256 entry = entryYields[tokenId];
  uint256 duration = getDuration(slot);
  int256 yieldDelta = int256(currentYield) - int256(entry);
  int256 nav = int256(PAR_VALUE) - (int256(duration) * yieldDelta / int256(PRECISION));
  return nav > 0 ? uint256(nav) : 0;
  ```
- [ ] **5.4.5** Implement `getPositionValue(uint256 tokenId)` — returns `balanceOf(tokenId) * getNAV(tokenId) / PAR_VALUE`
- [ ] **5.4.6** Write NAV tests:
  - Yield unchanged → NAV = PAR ✅
  - Yield rises 50bps on 10Y → NAV drops ~4.35% ✅
  - Yield drops 100bps on 30Y → NAV rises ~19.5% ✅
  - NAV floors at 0 for extreme yield spikes ✅

📚 **Reference:**

- Modified duration formula → https://www.investopedia.com/terms/m/modifiedduration.asp
- `bondstructure.md` — financial model rationale

#### 📄 State after TASK 5.4

**🇮🇹 Italiano**
Il modello di pricing è implementato. Ogni token ha un `entryYield` salvato al momento del mint. Il NAV si muove in funzione della variazione del yield di mercato rispetto all'entry yield, pesata per la modified duration del bucket. Il pricing è realistico e verificabile.

**🇬🇧 English**
The pricing model is implemented. Each token has an `entryYield` saved at mint time. NAV moves as a function of market yield change vs entry yield, weighted by the bucket's modified duration. Pricing is realistic and verifiable.

---

### TASK 5.5 — Add USDC-priced Mint and Redeem with PoR gate

Mint and redeem are priced in USDC at current NAV. Minting is gated by `ReserveOracle` — no token can be issued unless reserves cover the new issuance.

- [ ] **5.5.1** Import `IReserveOracle` from `src/interfaces/IReserveOracle.sol`
- [ ] **5.5.2** Store `IReserveOracle public reserveOracle` — set in constructor
- [ ] **5.5.3** Store `IERC20 public paymentToken` (USDC) — set in constructor
- [ ] **5.5.4** Store `address public treasury` — where USDC flows on mint, and from where it flows on redeem
- [ ] **5.5.5** Implement `mint(address to, uint256 slot, uint256 value)`:
  - `onlyOwner`
  - `require(slot >= 1 && slot <= 4, "Invalid slot")`
  - `require(identityRegistry.isVerified(to))`
  - `require(!bondOracle.isStale(slot))`
  - Compute `cost = value * getNAVForNewMint(slot) / PAR_VALUE`
  - `require(reserveOracle.isReserveSufficient(cost), "Insufficient reserves: PoR check failed")`
  - `require(!reserveOracle.isStale(), "Reserve data stale")`
  - `paymentToken.transferFrom(to, treasury, cost)`
  - Call `_mint(to, slot, value)`
  - Save `entryYields[newTokenId] = bondOracle.getYield(slot)`
  - Call `reserveOracle.notifyMint(cost)` to update tracked supply value
  - Emit `TokenMinted(address indexed to, uint256 indexed slot, uint256 value, uint256 cost)`
- [ ] **5.5.6** Implement `redeem(uint256 tokenId, uint256 value)`:
  - `require(ownerOf(tokenId) == msg.sender)`
  - Compute `payout = value * getNAV(tokenId) / PAR_VALUE`
  - `paymentToken.transferFrom(treasury, msg.sender, payout)`
  - Call `_burnValue(tokenId, value)`
  - Call `reserveOracle.notifyRedeem(payout)` to update tracked supply value
  - Emit `TokenRedeemed(address indexed owner, uint256 indexed slot, uint256 value, uint256 payout)`
- [ ] **5.5.7** Write mint/redeem tests:
  - Mint charges correct USDC amount ✅
  - Mint to unverified wallet ❌ (expect revert)
  - Mint with invalid slot ❌ (expect revert)
  - Mint with insufficient reserves ❌ (expect revert "Insufficient reserves: PoR check failed")
  - Mint with stale reserve data ❌ (expect revert "Reserve data stale")
  - Mint saves correct entryYield ✅
  - `notifyMint` called on ReserveOracle after successful mint ✅
  - Redeem pays correct USDC based on NAV ✅
  - Redeem partial position ✅
  - Redeem with yield change → different payout than mint cost ✅
  - `notifyRedeem` called on ReserveOracle after redeem ✅

📚 **Reference:**

- OpenZeppelin `IERC20` → `lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol`
- USDC on Sepolia (or mock ERC20 for tests)
- `IReserveOracle.sol` → `src/interfaces/IReserveOracle.sol`

#### 📄 State after TASK 5.5

**🇮🇹 Italiano**
Mint e redeem sono prezzati in USDC e il mint è gated dal Proof of Reserve. Un investitore non può ricevere token se le riserve non coprono il costo del mint. Il protocollo ha un flusso di cassa reale e un modello di backing realistico.

**🇬🇧 English**
Mint and redeem are priced in USDC and minting is gated by the Proof of Reserve. An investor cannot receive tokens if reserves do not cover the mint cost. The protocol has real cash flow and a realistic backing model.

---

### TASK 5.6 — Add Yield Accrual (`claimYield`)

Holders earn carry (yield) pro-rata over time, claimable on demand.

- [ ] **5.6.1** Store `mapping(uint256 tokenId => uint256 lastClaimTimestamp)` — initialized at mint time
- [ ] **5.6.2** Implement `claimYield(uint256 tokenId)`:
  ```solidity
  require(ownerOf(tokenId) == msg.sender);
  uint256 slot = slotOf(tokenId);
  uint256 yield = bondOracle.getYield(slot); // annual yield in BPS
  uint256 value = balanceOf(tokenId);
  uint256 elapsed = block.timestamp - lastClaimTimestamp[tokenId];
  // accrued = value × (yield / 10000) × (elapsed / 365 days)
  uint256 accrued = value * yield * elapsed / (10000 * 365 days);
  lastClaimTimestamp[tokenId] = block.timestamp;
  paymentToken.transferFrom(treasury, msg.sender, accrued);
  emit YieldClaimed(msg.sender, tokenId, accrued);
  ```
- [ ] **5.6.3** Ensure `lastClaimTimestamp` is set on mint and reset on `transferValue`
- [ ] **5.6.4** Write yield accrual tests:
  - Hold 30 days at 4.00% yield → correct accrual ✅
  - Claim twice without time passing → accrued = 0 ✅
  - Yield changes mid-period → uses current yield at claim time ✅
  - Transfer resets lastClaimTimestamp ✅

📚 **Reference:**

- Yield accrual math: `accrued = principal × rate × time`
- Foundry `vm.warp` for time simulation → https://book.getfoundry.sh/cheatcodes/warp

#### 📄 State after TASK 5.6

**🇮🇹 Italiano**
Gli holder guadagnano carry nel tempo. `claimYield()` calcola il rendimento maturato pro-rata e lo paga in USDC dalla treasury. Il protocollo simula un flusso cedolare realistico.

**🇬🇧 English**
Holders earn carry over time. `claimYield()` computes accrued yield pro-rata and pays it in USDC from the treasury. The protocol simulates a realistic coupon flow.

---

### TASK 5.7 — Add Risk Controls

- [ ] **5.7.1** Store `mapping(uint256 slot => uint256) public maxSupplyPerSlot` — cap total exposure per bucket
- [ ] **5.7.2** Store `uint256 public totalSupplyPerSlot` tracking — updated on mint/redeem
- [ ] **5.7.3** Add check in mint: `require(totalSupplyPerSlot[slot] + value <= maxSupplyPerSlot[slot], "Slot cap exceeded")`
- [ ] **5.7.4** Implement `setMaxSupplyPerSlot(uint256 slot, uint256 maxSupply)` — `onlyOwner`
- [ ] **5.7.5** Write tests:
  - Mint within cap ✅
  - Mint exceeding cap ❌ (expect revert)
  - Redeem frees capacity → mint again ✅
  - Owner updates cap ✅

📚 **Reference:**

- Risk management patterns in RWA protocols → https://github.com/ondoprotocol/tokenized-funds

#### 📄 State after TASK 5.7

**🇮🇹 Italiano**
Il protocollo ha controlli di rischio: cap per slot limita l'esposizione totale per maturity bucket. Questo previene concentrazione eccessiva del rischio.

**🇬🇧 English**
The protocol has risk controls: per-slot caps limit total exposure per maturity bucket. This prevents excessive risk concentration.

---

### TASK 5.8 — Full Token Test Suite

- [ ] **5.8.1** Integration test combining all features:
  - Mint with USDC payment + PoR check + compliance check ✅
  - Mint blocked by insufficient reserves ❌
  - Mint blocked by stale reserve data ❌
  - Transfer between verified wallets ✅
  - Transfer to unverified wallet ❌
  - Transfer from frozen wallet ❌
  - Transfer with stale yield oracle ❌
  - NAV changes with yield movement ✅
  - Claim yield after 30 days ✅
  - Redeem with USDC payout + notifyRedeem called ✅
  - Forced transfer bypasses compliance ✅
  - Slot cap enforcement ✅
  - Entry yield correctly saved per token ✅
  - ReserveOracle trackedSupplyValue correctly updated through full mint → redeem lifecycle ✅

📚 **Reference:**

- Foundry `vm.expectRevert` → https://book.getfoundry.sh/cheatcodes/expect-revert
- Foundry `vm.warp` → https://book.getfoundry.sh/cheatcodes/warp
- Foundry `vm.mockCall` → https://book.getfoundry.sh/cheatcodes/mock-call

#### 📄 State after TASK 5.8

**🇮🇹 Italiano**
`TreasuryBondToken.sol` è completo e testato. Il ciclo di vita è interamente coperto: emissione con USDC + gate PoR, compliance, NAV con modified duration, accrual yield, redemption con aggiornamento riserve, e risk controls.

**🇬🇧 English**
`TreasuryBondToken.sol` is complete and tested. The full lifecycle is covered: USDC-priced issuance with PoR gate, compliance, modified duration NAV, yield accrual, redemption with reserve update, and risk controls.

---

## PHASE 6 — Deploy & Integration

---

### TASK 6.1 — Deployment scripts

- [ ] **6.1.1** `script/DeployIdentity.s.sol` — deploy identity/compliance layer (from TASK 1.2)
- [ ] **6.1.2** `script/RegisterInvestor.s.sol` — register investor identities (from TASK 1.3)
- [ ] **6.1.3** `script/DeployReserveOracle.s.sol` — deploy `ReserveOracle`, set custodian address, set initial reserve balance
- [ ] **6.1.4** `script/DeployOracle.s.sol` — deploy `BondOracle` + `BondFunctionsConsumer`
- [ ] **6.1.5** `script/DeployAutomation.s.sol` — deploy `BondAutomation`
- [ ] **6.1.6** `script/DeployToken.s.sol` — deploy `TreasuryBondToken` with `identityRegistry`, `bondOracle`, `reserveOracle`
- [ ] **6.1.7** `script/WireContracts.s.sol` — set all cross-contract references:
  - Set `BondFunctionsConsumer` as `authorizedUpdater` on `BondOracle`
  - Authorize `BondAutomation` to call `BondFunctionsConsumer.sendRequest()`
  - Set `TreasuryBondToken` as `tokenContract` on `ReserveOracle` (authorizes `notifyMint`/`notifyRedeem`)
- [ ] **6.1.8** Save all deployed addresses to `deployments/sepolia.json`

📚 **Reference:**

- Foundry scripting with `vm.startBroadcast` → https://book.getfoundry.sh/tutorials/solidity-scripting

#### 📄 State after TASK 6.1

**🇮🇹 Italiano**
Tutti i contratti sono deployati su Sepolia e correttamente collegati. Il sistema è operativo.

**🇬🇧 English**
All contracts are deployed on Sepolia and correctly wired. The system is operational.

---

### TASK 6.2 — End-to-end integration test

- [ ] **6.2.1** Deploy entire system in a single Foundry fork test
- [ ] **6.2.2** Register two investor identities via ONCHAINID claim flow
- [ ] **6.2.3** Custodian pushes initial reserve balance to `ReserveOracle` (e.g. 1,000,000 USDC)
- [ ] **6.2.4** Trigger a manual Chainlink Functions request → verify yield stored in `BondOracle`
- [ ] **6.2.5** Mint bond tokens (slot 3 — 10Y exposure) to investor A — verify USDC charged at NAV and PoR check passed
- [ ] **6.2.6** Verify `entryYield` saved correctly for the minted token
- [ ] **6.2.7** Verify `ReserveOracle.trackedSupplyValue` increased by mint cost
- [ ] **6.2.8** Attempt mint that would exceed reserve balance ❌ → expect revert "Insufficient reserves: PoR check failed"
- [ ] **6.2.9** Transfer value from investor A to investor B (both verified) ✅
- [ ] **6.2.10** Attempt transfer to unregistered wallet ❌ → expect revert
- [ ] **6.2.11** Freeze investor A → attempt transfer ❌ → expect revert
- [ ] **6.2.12** Simulate oracle staleness via `vm.warp(block.timestamp + 73 hours)` → attempt transfer ❌ → expect revert
- [ ] **6.2.13** Simulate reserve staleness via `vm.warp(block.timestamp + 25 hours)` → attempt mint ❌ → expect revert
- [ ] **6.2.14** Owner executes forced transfer from frozen wallet ✅
- [ ] **6.2.15** Update oracle yield (simulate rate hike) → verify NAV drops according to modified duration
- [ ] **6.2.16** Warp 30 days → investor B calls `claimYield()` → verify correct USDC payout
- [ ] **6.2.17** Investor B redeems partial position → verify USDC payout at current NAV + `trackedSupplyValue` decreased
- [ ] **6.2.18** Attempt mint exceeding `maxSupplyPerSlot` ❌ → expect revert

📚 **Reference:**

- Foundry `vm.warp` → https://book.getfoundry.sh/cheatcodes/warp
- Foundry fork testing → https://book.getfoundry.sh/forge/fork-testing

#### 📄 State after TASK 6.2

**🇮🇹 Italiano**
Il protocollo è validato end-to-end. Tutti i flussi critici funzionano. I casi di fallimento generano revert corretti. Il NAV risponde ai cambiamenti della curva dei rendimenti. Il PoR gate blocca emissioni non coperte dalle riserve.

**🇬🇧 English**
The protocol is validated end-to-end. All critical flows work correctly. Expected failure cases produce correct reverts. NAV responds to yield curve changes. The PoR gate blocks underbacked issuance.

---

### TASK 6.3 — README.md

- [ ] **6.3.1** Project overview and architecture diagram
- [ ] **6.3.2** Backing model: SPV + PoR explanation, testnet vs production distinction
- [ ] **6.3.3** Bond model explanation: yield curve exposure, not individual bonds (link to `bondstructure.md`)
- [ ] **6.3.4** Explanation of each contract and its role
- [ ] **6.3.5** Deployed contract addresses on Sepolia with Etherscan links
- [ ] **6.3.6** Instructions: clone, install dependencies, run tests
- [ ] **6.3.7** Instructions: deploy to Sepolia
- [ ] **6.3.8** Chainlink Functions setup: subscription, secrets, fund with LINK
- [ ] **6.3.9** Chainlink Automation setup: register upkeep, fund with LINK
- [ ] **6.3.10** Known limitations and possible future improvements

📚 **Reference:**

- Ondo Finance → https://github.com/ondoprotocol/tokenized-funds
- Backed Finance → https://github.com/backed-fi/backed-protocol

#### 📄 State after TASK 6.3

**🇮🇹 Italiano**
Il progetto è completo. Chiunque può clonare il repo, leggere il README e comprendere architettura, modello di backing, modello finanziario e come testare il protocollo.

**🇬🇧 English**
The project is complete. Anyone can clone the repo, read the README, and immediately understand the architecture, backing model, financial model, and how to test the protocol.

---

## Dependency Order & Parallelism

### Deploy order (sequential — each step depends on the previous)

```
1. ClaimTopicsRegistry + ClaimIssuer + TrustedIssuersRegistry
   ↓
2. IdentityRegistryStorage + IdentityRegistry (needs CTR + TIR + IRS)
   ↓
3. Register investors (needs IR + ClaimIssuer)
   ↓
4. ReserveOracle
   ↓
5. BondOracle
   ↓
6. BondFunctionsConsumer (needs BondOracle)
   ↓
7. BondAutomation (needs BondFunctionsConsumer)
   ↓
8. TreasuryBondToken (needs IdentityRegistry + BondOracle + ReserveOracle)
   ↓
9. Wire: set tokenContract on ReserveOracle
```

### Independent tracks (can be developed in parallel)

```
┌─────────────────────────────┐    ┌──────────────────────────────┐
│  TRACK A — Identity/KYC     │    │  TRACK B — Oracle Layers      │
│                             │    │                              │
│  TASK 1.1  Study ONCHAINID  │    │  TASK 2.1  Study PoR         │
│  TASK 1.2  Deploy Identity   │    │  TASK 2.2  ReserveOracle.sol │
│  TASK 1.3  Register Investor │    │  TASK 3.1  BondOracle.sol    │
│                             │    │  TASK 3.2  BondFunctions     │
│                             │    │            Consumer.sol      │
│                             │    │  TASK 4.1  BondAutomation.sol│
└──────────┬──────────────────┘    └──────────┬───────────────────┘
           │                                  │
           └──────────┬───────────────────────┘
                      ▼
           ┌──────────────────────────┐
           │  TRACK C — Token          │
           │                          │
           │  TASK 5.1  Study 3525    │
           │  TASK 5.2  Base token    │
           │  TASK 5.3  Compliance    │
           │  TASK 5.4  NAV model     │
           │  TASK 5.5  USDC + PoR    │
           │  TASK 5.6  claimYield    │
           │  TASK 5.7  Risk controls │
           │  TASK 5.8  Full tests    │
           └──────────┬───────────────┘
                      ▼
           ┌──────────────────────┐
           │  TRACK D — Integration│
           │                      │
           │  TASK 6.1  Deploy     │
           │  TASK 6.2  E2E test   │
           │  TASK 6.3  README     │
           └──────────────────────┘
```

**Summary:**

- **Track A** (Identity/KYC) and **Track B** (Oracle Layers including ReserveOracle) are **completely independent** and can be developed in parallel.
- **Track C** (ERC-3525 Token) depends on both: it uses `IdentityRegistry` (Track A), `BondOracle`, and `ReserveOracle` (Track B).
- **Track D** (Integration) depends on everything else.
- Within each track, tasks must be executed in sequential order.
