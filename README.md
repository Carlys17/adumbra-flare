# MEV-Safe FXRP Swap Router

**TEE-protected swap routing for Flare.** Swap intents are routed inside a confidential enclave (TEE). The enclave picks the optimal multi-hop path and emits a signed order. On-chain we only verify the enclave signature and execute the order atomically, so MEV bots never see the route/slippage logic until the tx is already mined.

## Hackathon

Flare Summer Signal — **Bounty 2: Confidential Compute Apps** ($6,000 pool)

## Live Deployment (Flare Coston2, chainId 114)

| Contract | Address |
|---|---|
| MEVSwapRouter | `0x393647f18a98b1CdDC51699FCC09cdca5Ec88fe7` |
| Mock FXRP | `0x22f6e913FF7DcFaB517334e5cdd6A142047E945a` |
| Mock USDC | `0x0F28c0801CB65fcA544cd43353E5aF993F44f690` |

Verified swap on Coston2: tx [`0x7fd340e3c1fa6f6eefe07baac20455e17fbcdb8428ef0027f427ed3be8d3ce25`](https://coston2-explorer.flare.network/tx/0x7fd340e3c1fa6f6eefe07baac20455e17fbcdb8428ef0027f427ed3be8d3ce25) — 100 FXRP in, 51.74 USDC out, TEE-signed, block 33624550.

## Why This Matters

MEV is a live pain point in DeFi. On Flare, FXRP and FAssets users face the same sandwich/front-run risks as on other EVM chains. This project shows how Flare Confidential Compute can harden core DeFi primitives without changing user behavior.

## Architecture

```
 Wallet UI (viem + MetaMask)
    │
    │  1. swap intent (user, tokenIn, tokenOut, amountIn, slippage)
    ▼
 [ TEE / Enclave ]  ── HTTP :7070 POST /sign
    │  2. calculate optimal route privately
    │  3. build order with minAmountOut + deadline + nonce
    │  4. sign order with enclave attested key
    ▼
 Signed Order (on-chain readable fields only)
    user, tokenIn, tokenOut, amountIn, minAmountOut, deadline, nonce, signature
    ▼
 MEVSwapRouter (Flare Coston2)
    │  5. verify enclave signature (ecrecover, EIP-2 low-s)
    │  6. check deadline + nonce (replay guard)
    │  7. pull input from user, deliver output
    ▼
 Final tx (MEV bots see only this)
```

### Trust Assumptions

- The enclave signing key is pinned at deploy time (`enclaveSigner` immutable). In production this key is bound to a hardware attestation quote (SGX) or PCR measurement (AWS Nitro); the contract would additionally verify the attestation document before accepting the key.
- The contract trusts the enclave's `minAmountOut` as the slippage floor. Users trust the enclave for route quality, not for custody: funds only move via `transferFrom` on an order bound to `order.user`, and the nonce prevents replay.
- Everything the enclave decides privately is still constrained on-chain: an enclave cannot drain a user, cannot exceed `amountIn`, and cannot execute past `deadline`.

### Privacy Boundary

- **Private (inside TEE)**: route path, intermediate hops, exact price quote, slippage strategy, enclave key material
- **Public (on-chain)**: `tokenIn`, `tokenOut`, `amountIn`, `minAmountOut`, `deadline`, `orderNonce`, `signature`

## Why Confidential Compute (not plain smart contracts)

A pure on-chain router must publish its route and slippage parameters in calldata before execution, which is exactly the information MEV searchers need to sandwich the trade. Moving route selection into a TEE means the profitable information does not exist publicly until the trade is already settled. A plain smart contract cannot achieve this: everything it reads and computes is visible in the mempool and in state.

## Repo Layout

```
flare-swap-router/
├── src/
│   ├── MEVSwapRouter.sol      # on-chain verification + execution
│   └── mocks/MockERC20.sol
├── test/MEVSwapRouter.t.sol   # 5 Foundry tests
├── tee/
│   ├── Cargo.toml
│   └── src/main.rs            # enclave service: CLI + HTTP :7070 modes
├── frontend/index.html        # viem + MetaMask wallet UI
├── scripts/
│   ├── e2e_demo.sh            # full local end-to-end run
│   └── encode_calldata.py     # nested-tuple ABI encoder
├── SUBMISSION.md
└── README.md
```

## Stack

| Layer | Technology | Role |
|---|---|---|
| Confidential compute | Rust enclave service (SGX/Nitro model) | Private route calculation + order signing |
| On-chain | Solidity 0.8.x, Foundry | Signature verification + swap execution guard |
| Network | Flare Coston2 (deployed) | Live testnet deployment |
| Frontend | viem + MetaMask | Wallet UI, shows only the final transaction |

## Running It

### Prerequisites
Rust 1.78+, Foundry (`foundryup`), Python 3.12 with `eth-abi` + `pycryptodome`.

### Tests
```bash
forge test
```
```
[PASS] testHappyPath()          (gas: 133000)
[PASS] testRevertExpired()      (gas: 30930)
[PASS] testRevertReplay()       (gas: 130764)
[PASS] testRevertSlippage()     (gas: 72194)
[PASS] testRevertWrongSigner()  (gas: 37821)
5 passed; 0 failed
```

### TEE service
```bash
cd tee && cargo build --release
# one-shot CLI mode
ENCLAVE_KEY=<hex> ./target/release/mevswap-tee --intent - --nonce 0 < intent.json
# HTTP server mode (used by the frontend)
ENCLAVE_KEY=<hex> ./target/release/mevswap-tee --serve   # listens on :7070
```

### End-to-end demo (local anvil)
```bash
anvil --port 8545 &
# deploy router + mocks, write /tmp/addresses.env, then:
bash scripts/e2e_demo.sh
```

### Frontend
```bash
cd frontend && python3 -m http.server 8080
# open http://localhost:8080 with MetaMask on Coston2
```

## What Was Newly Built During the Program

Everything in this repo was built during Flare Summer Signal — there was no pre-existing project:

- `MEVSwapRouter.sol`: enclave-signature verification (ecrecover with EIP-2 low-s check), nonce replay guard, deadline enforcement, slippage floor, atomic swap execution.
- `tee/src/main.rs`: Rust enclave service. Private route/rate computation, ABI-compatible keccak256 digest construction matching the Solidity side byte-for-byte, ECDSA recoverable signing, plus both a CLI one-shot mode and an HTTP `/sign` server mode with CORS for browser use.
- `frontend/index.html`: viem + MetaMask app that reads the on-chain nonce, requests a TEE signature over HTTP, handles ERC20 approval, and submits `executeSwap`.
- `scripts/encode_calldata.py`: ABI encoder for the nested `SignedOrder` tuple (`cast` cannot parse this shape).
- `scripts/e2e_demo.sh`: full local end-to-end verification run.
- Coston2 deployment and a verified on-chain TEE-signed swap.

## Roadmap / Next Steps

1. Wire real multi-hop routing inside the TEE (SparkDEX / BlazeSwap quoters) instead of the current dev rate table.
2. Add enclave attestation verification on-chain (SGX quote / Nitro PCR) so the signing key is provably enclave-bound rather than pinned by the deployer.
3. Replace the single-leg reserve model with real AMM execution on the enclave-chosen path.
4. Add a sealed-bid batch auction module so multiple intents clear together, removing ordering-based MEV entirely.
5. Deploy to Songbird, then Flare mainnet.

## License

MIT
