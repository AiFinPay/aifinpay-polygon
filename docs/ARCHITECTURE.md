# AiFinPay — Architecture (Polygon)

## Contract Dependency Graph

```
                    ┌─────────────────────────┐
                    │      AiFinPayCore        │
                    │       (v5.3)             │
                    │  - mintPassport()        │
                    │  - b2bPay()              │
                    │  - topUpStable()         │
                    │  - reserveSeatStable()   │
                    └───┬──────────┬───────────┘
                        │          │
              ┌─────────┘          └──────────┐
              ▼                               ▼
   ┌──────────────────┐           ┌──────────────────┐
   │  AgentPassport   │           │   MSECCOToken    │
   │  (ERC-721)       │           │   (ERC-20)       │
   │  Soulbound NFT   │           │  Non-transferable│
   │  1 per wallet    │           │  2 decimals      │
   └──────────────────┘           └──────────────────┘
              │
              ▼
   ┌──────────────────┐
   │   B2BSplitter    │
   │  98.99% merchant │
   │  1.00%  treasury │
   │  0.01%  creator  │
   └──────────────────┘
              │
    ┌─────────┴──────────┐
    ▼                    ▼
┌─────────┐    ┌──────────────────┐
│Merchant │    │  Gnosis Safe     │
│ Wallet  │    │  4-of-4 Treasury │
└─────────┘    └──────────────────┘
```

---

## Contract Responsibilities

### AiFinPayCore
- Central protocol controller
- Owns references to AgentPassport, MSECCOToken, B2BSplitter, treasury
- Handles all user-facing operations
- Enforces pause state, Pyth oracle, stablecoin decimal conversion

### AgentPassport (ERC-721)
- Issues soulbound identity NFT to each agent wallet
- Stores per-agent: IP creator, daily spend limit, current spend, last reset day
- `checkAndSpend()` called by Core to enforce daily limits
- `_beforeTokenTransfer()` blocks all transfers after mint (soulbound)

### MSECCOToken (ERC-20)
- Tracks compute credits per agent
- `mint()` called on top-up, `burn()` called on b2bPay
- `transfer()` and `transferFrom()` always revert — non-transferable
- 2 decimal places (100 units = 1 mSECCO = 1 USD cent)

### B2BSplitter
- Receives full payment and splits atomically
- Uses SafeERC20 for all transfers
- Connected to treasury (Gnosis Safe)

---

## Oracle Integration

**Pyth Pull Oracle** for MATIC/USD.
- Max staleness: 60 seconds
- Falls back gracefully if price feed is stale

---

## Multi-Chain Architecture

| Chain | Contracts | Treasury |
|-------|-----------|----------|
| Polygon Mainnet | AiFinPayCore, AgentPassport, MSECCOToken, B2BSplitter | Gnosis Safe 4-of-4 |
| Solana Mainnet | aifinpay_contract (Anchor) | Squads 3-of-4 |

Both chains share same economics. SDK handles chain routing transparently.

---

## Security Patterns

| Pattern | Applied In |
|---------|-----------|
| Checks-Effects-Interactions | mintPassport(), b2bPay() |
| SafeERC20 | All ERC-20 token transfers |
| ReentrancyGuard | mintPassport() |
| One-time setCore() | AgentPassport, MSECCOToken |
| Soulbound ERC-721 | AgentPassport._beforeTokenTransfer() |
| Non-transferable ERC-20 | MSECCOToken.transfer() |
| Decimal divisor constant | STABLE_DECIMALS_DIVISOR = 10_000 |
