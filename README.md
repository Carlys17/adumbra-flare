# MEV-Safe FXRP Swap Router

**TEE-protected swap routing for Flare.** Swap intents are routed inside a confidential enclave (TEE). The enclave picks the optimal multi-hop path and emits a signed order. On-chain we only verify the enclave signature and execute the order atomically, so MEV bots never see the route/slippage logic until the tx is already mined.

## Bounty
- Bounty 2: Confidential Compute Apps ($6,000 pool)

## Why This Matters
MEV is a live pain point in DeFi. On Flare, FXRP and FAssets users face the same sandwich/front-run risks as on other EVM chains. This project shows how Flare Confidential Compute can harden core DeFi primitives without changing user behavior.

## Architecture

```
 Wallet UI
    │
    │  1. swap intent (user, tokenIn, tokenOut, amountIn, slippage)
    ▼
 [ TEE / Enclave ]
    │  2. calculate optimal route privately
    │  3. build order with minAmountOut + deadline + nonce
    │  4. sign order with enclave attested key
    ▼
 Signed Order (on-chain readable fields only)
    user, tokenIn, tokenOut, amountIn, minAmountOut, deadline, nonce, signature
    ▼
 MEVSwapRouter (Flare EVM)
    │  5. verify enclave signature
    │  6. pull input from user
    │  7. deliver output
    ▼
 Final tx (MEV bots see only this)
```

### Privacy Boundary
- **Private (inside TEE)**: route path, intermediate hops, exact price quote, slippage strategy, enclave key material
- **Public (on-chain)**: `tokenIn`, `tokenOut`, `amountIn`, `minAmountOut`, `deadline`, `orderNonce`, `signature`

## Repo Layout

```
/root/flare-swap-router/
├── contracts/
│   ├── src/MEVSwapRouter.sol
│   ├── src/mocks/MockERC20.sol
│   ├── test/MEVSwapRouter.t.sol
│   └── foundry.toml
├── tee/
│   ├── Cargo.toml
│   └── src/main.rs
├── frontend/              # React wallet UI (coming)
├── scripts/
│   └── e2e_demo.sh
└── README.md
```

## Stack

| Layer | Technology | Role |
|---|---|---|
| Confidential compute | Rust enclave service (SGX/Nitro dev sim) | Private route calculation + order signing |
| On-chain | Solidity 0.8.x, Foundry | Swap execution guard + signature verification |
| Testnet target | Flare Coston2 | Deployment target |
| Frontend | React + Ethers | Wallet UI showing only final transaction |

## Getting Started

### Prerequisites
- Rust 1.78+
- Node.js 22+
- Foundry (`foundryup`)

### Build & Test

```bash
# Smart contracts
cd contracts
forge test

# TEE service
cd tee
cargo build --release

# End-to-end demo
bash scripts/e2e_demo.sh
```

## Submission Checklist (DoraHacks)
- [x] Project name
- [x] Selected bounty: Confidential Compute Apps
- [x] Short product description
- [x] Target user
- [ ] Demo link / video
- [x] GitHub repo / technical materials
- [x] Explanation of Flare usage
- [x] Explanation of what was newly built during the program
- [ ] Smart contract addresses / deployment details
- [ ] Short roadmap / next steps

## Next Steps
1. Add multi-hop routing inside TEE (quote SparkDEX/BlazeSwap)
2. Add enclave attestation flow (SGX quote / Nitro PCR validation)
3. Deploy on Coston2
4. Build wallet UI
5. Add sealed-bid auction module on top (Bounty 2 extension)
