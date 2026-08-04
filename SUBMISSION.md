# Flare Summer Signal — MEV-Safe FXRP Swap Router (TEE)

**Bounty 2: Confidential Compute Apps**

## 1. Project Name
**MEV-Safe FXRP Swap Router** — TEE-protected swap routing for Flare.

## 2. Short Product Description
A swap router for Flare that moves route selection and price/slippage logic
inside a confidential enclave (TEE). The enclave picks the optimal multi-hop
path and emits a signed order; on-chain we only verify the enclave signature
and execute atomically. MEV bots never see the route, the exact quote, or the
slippage strategy until the transaction is already mined.

## 3. Target User
DeFi users on Flare who swap FXRP / FAssets and USDC and want protection from
front-running, sandwich attacks, and other MEV extraction without changing
their wallet behavior.

## 4. How It Uses Flare
- **Flare Confidential Compute** is the core: route calculation and order
  signing happen inside a TEE (SGX / AWS Nitro model), keeping the trade
  intent private until settlement.
- **Flare EVM** (Coston2 testnet target) hosts the `MEVSwapRouter` contract
  that verifies the enclave signature and executes the swap.
- Designed to sit on top of Flare's FAssets / FXRP ecosystem.

## 5. What Was Newly Built
- `MEVSwapRouter.sol` — on-chain contract: enclave-signature verification,
  replay protection (nonce), slippage guard, atomic swap execution.
- `tee/` (Rust) — enclave service: private route computation, digest building,
  ECDSA order signing with an attested key.
- `frontend/` — wallet UI that shows only the final transaction (route hidden).
- `scripts/e2e_demo.sh` — end-to-end demo: TEE signs order -> on-chain execute
  -> balances verified.
- 5 Foundry tests (happy path, expired, replay, wrong signer, slippage).

## 6. Demo / Video
- Live local demo: `bash scripts/e2e_demo.sh` (runs against a local anvil node).
- Frontend: `frontend/index.html` (open in browser, demo mode).

## 7. GitHub Repo
https://github.com/Carlys17/flare-swap-router

## 8. Smart Contract Addresses / Deployment
- Local anvil deployment (see e2e log) for demonstration.
- Coston2 deployment: in progress.

## 9. Roadmap / Next Steps
1. Wire real multi-hop routing (SparkDEX / BlazeSwap quoters) inside the TEE.
2. Add enclave attestation (SGX quote / Nitro PCR validation) for the signing key.
3. Deploy to Flare Coston2 and mainnet.
4. Add sealed-bid auction module on top (Bounty 2 extension).
