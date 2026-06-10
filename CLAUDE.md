# AiFinPay — Polygon Smart Contracts

## Project Overview
Solidity contracts for AiFinPay — AI-native financial OS.
x402 protocol: AI agents pay for services autonomously via HTTP 402 challenge/response.
Deployed on **Polygon Mainnet**.

## Stack
- **Language**: Solidity 0.8.35 (EVM Cancun)
- **Framework**: OpenZeppelin (ERC20, ERC721, Ownable, ReentrancyGuard, SafeERC20)
- **Build**: Hardhat + Bun
- **Treasury**: Gnosis Safe 4-of-4 multisig (`0xD31d82c4b35DABaA2ad7023C89A78A052D1f3c8e`)
- **Oracle**: Pyth Pull Oracle (MATIC/USD)

## Deployed Contracts (CANONICAL — redeployed 2026-06-11 with real manifesto hash, all verified, owner = Safe)
| Contract | Address |
|----------|---------|
| AiFinPayCore | `0x1071Bb1C827223D3D0115B0e1f114adAb9ceB94f` |
| AgentPassport | `0x14Cd0CfD78A8F1DC6002D715d4147448a2DAc1Dd` |
| MSECCOToken | `0x522FAB7dC9c0607c3664969c732b7Bef163B662d` |
| B2BSplitter | `0xE34Fc0E6694821c600Fa0955C0F74720ea6d8440` (unchanged) |

**DEPRECATED Cores (placeholder manifesto hash, do not use):** `0x8Ad9830D16b1f10333866a3f38C949CbB19f4BAD`, `0x24Bee0dfCD4d2f481E2f49A339F1C105a1611C7b` (+ their old MSECCO/Passport sets)

## Key Files
- `contracts/AiFinPayCore.sol` — main protocol contract (v5.3)
- `contracts/AgentPassport.sol` — soulbound ERC-721 identity NFT
- `contracts/MSECCOToken.sol` — non-transferable ERC-20 compute credits
- `contracts/B2BSplitter.sol` — atomic B2B payment splitter

## Constants & Economics
- `1 USD = 100 mSECCO` (1 cent = 1 mSECCO)
- USDC/USDT decimal divisor: `STABLE_DECIMALS_DIVISOR = 10_000` (6 decimals → 1 cent = 10,000 base units)
- B2B split: **98.99% merchant / 1.00% treasury / 0.01% IP creator**
- manifestoHash (real canonical, governable storage var): `0x27b28e3044b56df3332a60c27604686a634f922a184f62398a4e2f85df19c699` (SHA-256 of canonical manifesto, output of backend/manifesto-hash.js; updatable by the Safe via setManifestoHash). The old `a1b2c3d4…` was a placeholder that broke seat reservation — see the manifesto-hash fix.

## Audit Fixes Applied (Pironmind, May 2026)
- **CRIT-001**: Stablecoin decimal conversion — `amount / 10_000` (was `/100`, caused 100x over-minting)
- **HIGH-001 (Core)**: `mintPassport()` protected with `nonReentrant`
- **HIGH-001 (Passport)**: State written BEFORE `_safeMint()` — checks-effects-interactions pattern
- **MED-001**: `b2bPay()` enforces agent daily spend limit via `passport.checkAndSpend()`
- **MED-002**: `setCore()` is one-time only — reverts if already set (both MSECCOToken and AgentPassport)
- **LOW-001**: All ERC-20 transfers use `SafeERC20.safeTransferFrom()` — not raw `transferFrom()`

## Coding Rules

### Style Conventions
- **Function arguments**: Use `_` prefix (e.g., `_amount`, `_token`, `_agent`)
- **NatSpec**: Use `@param _argName` format matching the underscore-prefixed parameter
- **Indentation**: 4 spaces for Solidity
- **Line length**: 120 characters max for Solidity

### Solidity Best Practices
- Always use `SafeERC20` for token transfers — never raw `IERC20.transfer()` or `transferFrom()`
- `STABLE_DECIMALS_DIVISOR = 10_000` must be used for any USDC/USDT → mSECCO conversion
- Agent Passport is **soulbound** — `_beforeTokenTransfer` blocks all transfers (mint only)
- mSECCO is **non-transferable** — `transfer()` and `transferFrom()` always revert
- Keep Checks-Effects-Interactions order in all state-mutating functions
- All fund-touching functions must check `notPaused` modifier

### Prettier Config (`.prettierrc`)
```json
{
  "plugins": ["prettier-plugin-solidity"],
  "overrides": [{
    "files": "*.sol",
    "options": {
      "tabWidth": 4,
      "printWidth": 120,
      "trailingComma": "none"
    }
  }]
}
```

## Build & Test
```bash
# Install dependencies
bun install

# Compile contracts
bun run hardhat compile

# Run tests
bun run hardhat test

# Deploy to Polygon
bun run hardhat run scripts/deploy.ts --network polygon

# Deploy to Amoy testnet
bun run hardhat run scripts/deploy.ts --network amoy
```

## Related Contracts
- **Solana Program**: `5g9zWHF1Vv6GiGpA2ZbJQbSCDZd5hAk9AyvabRJvKFx2`
- **GitHub (Polygon)**: `https://github.com/syedhassan125/aifinpay-polygon`
- **GitHub (Solana)**: `https://github.com/syedhassan125/aifinpay`