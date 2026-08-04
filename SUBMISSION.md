# Flare Summer Signal — Submission

## 1. Project Name
**MEV-Safe FXRP Swap Router** — TEE-protected swap routing for Flare.

## 2. Selected Bounty
**Bounty 2 — Confidential Compute Apps**

## 3. Short Product Description
A swap router for Flare that moves route selection and price/slippage logic inside a
Trusted Execution Environment. The enclave computes the optimal path and signs a
constrained order; the on-chain contract verifies the enclave signature and executes
atomically. MEV bots never see the route, the exact quote, or the slippage strategy
until the transaction is already settled.

## 4. Target User
DeFi users on Flare swapping FXRP / FAssets who lose value to sandwich attacks and
front-running, and protocols that want MEV-resistant execution without changing user
wallet behavior.

## 5. Demo Link / Video / Working App
- **Live on Coston2** — verified TEE-signed swap:
  https://coston2-explorer.flare.network/tx/0x7fd340e3c1fa6f6eefe07baac20455e17fbcdb8428ef0027f427ed3be8d3ce25
- **Frontend** — `frontend/index.html` (viem + MetaMask, points at the Coston2 deployment).
  Run `cd frontend && python3 -m http.server 8080`, start the TEE with
  `mevswap-tee --serve`, then open http://localhost:8080 on Coston2.
- **Local end-to-end script** — `bash scripts/e2e_demo.sh` runs the whole flow against anvil.

## 6. GitHub Repo
https://github.com/Carlys17/flare-swap-router

## 7. How It Uses Flare
- **Flare Confidential Compute is the core mechanism**: route selection, quoting, and
  order signing happen inside a TEE. Only the signed, constrained result reaches the chain.
- **Flare EVM (Coston2)** hosts `MEVSwapRouter`, which verifies the enclave signature with
  `ecrecover` (EIP-2 low-s enforced), checks the deadline and nonce, and executes the swap.
- Targets the **FXRP / FAssets** flow specifically, which is Flare's distinguishing asset layer.

### What runs privately inside the TEE
Route path and intermediate hops, the exact price quote, the slippage strategy that
produces `minAmountOut`, and the enclave signing key.

### What is verified / consumed on-chain
`tokenIn`, `tokenOut`, `amountIn`, `minAmountOut`, `deadline`, `orderNonce`, and the
enclave signature. The contract recovers the signer and rejects anything not signed by
the pinned enclave key, anything past its deadline, and any replayed nonce.

### Trust assumptions
The enclave signing key is pinned at deploy time as an immutable. In production it is
bound to a hardware attestation (SGX quote / Nitro PCR) which the contract would verify
before accepting the key. Users trust the enclave for *route quality only*, not custody:
funds move only via an order bound to `order.user`, capped at `amountIn`, floored at
`minAmountOut`, and single-use per nonce.

### Why confidential compute rather than a normal smart contract
A pure on-chain router must publish route and slippage parameters in calldata before
execution — precisely the data a searcher needs to sandwich the trade. No amount of
on-chain logic can hide it, because contract inputs and state are public. Moving the
decision into a TEE means the profitable information does not exist publicly until the
trade is already settled.

## 8. What Was Newly Built During the Program
Built from scratch during the hackathon (no pre-existing project):
- `MEVSwapRouter.sol` — enclave signature verification, replay/nonce guard, deadline
  enforcement, slippage floor, atomic execution.
- `tee/src/main.rs` — Rust enclave service: private route computation, keccak256 digest
  construction byte-compatible with Solidity `abi.encode`, recoverable ECDSA signing,
  CLI one-shot mode plus an HTTP `/sign` server mode with CORS.
- `frontend/index.html` — viem + MetaMask app: reads on-chain nonce, requests the TEE
  signature, handles ERC20 approval, submits `executeSwap`.
- `scripts/encode_calldata.py` — ABI encoder for the nested `SignedOrder` tuple that
  `cast` cannot parse.
- `scripts/e2e_demo.sh` — full local end-to-end verification run.
- 5 Foundry tests covering happy path, expired order, replayed nonce, wrong signer, and
  slippage failure.
- Coston2 deployment plus a verified on-chain TEE-signed swap.

## 9. Smart Contract Addresses / Deployment
Deployed on **Flare Coston2** (chainId 114, RPC `https://coston2-api.flare.network/ext/C/rpc`):

| Contract | Address |
|---|---|
| MEVSwapRouter | `0x393647f18a98b1CdDC51699FCC09cdca5Ec88fe7` |
| Mock FXRP | `0x22f6e913FF7DcFaB517334e5cdd6A142047E945a` |
| Mock USDC | `0x0F28c0801CB65fcA544cd43353E5aF993F44f690` |

Verified TEE-signed swap: tx `0x7fd340e3c1fa6f6eefe07baac20455e17fbcdb8428ef0027f427ed3be8d3ce25`
(block 33624550) — 100 FXRP in, 51.74 USDC out, router nonce 0 → 1.

## 10. Technical Execution Evidence
```
forge test
[PASS] testHappyPath()          (gas: 133000)
[PASS] testRevertExpired()      (gas: 30930)
[PASS] testRevertReplay()       (gas: 130764)
[PASS] testRevertSlippage()     (gas: 72194)
[PASS] testRevertWrongSigner()  (gas: 37821)
5 passed; 0 failed; 0 skipped
```
```
TEE HTTP service (POST localhost:7070/sign) → live response
{
  "min_amount_out": "51740000000000000000",
  "order_nonce": "1",
  "signature": "0x1c0b038ab5bc0f110a29db3bd75fa7b98b5d86075fe2287837fcf81fba01c303...",
  "tee_report": "Enclave 0x423ece2094 routed FXRP -> USDC at rate 0.520000"
}
```

## 11. Roadmap / Next Steps
1. Real multi-hop routing inside the TEE (SparkDEX / BlazeSwap quoters) replacing the dev rate table.
2. On-chain attestation verification (SGX quote / Nitro PCR) so the signing key is provably enclave-bound.
3. Real AMM execution along the enclave-chosen path instead of the single-leg reserve model.
4. Sealed-bid batch auction so multiple intents clear together, removing ordering-based MEV entirely.
5. Songbird, then Flare mainnet.

## 12. Deployment Target
Deployed and verified on **Coston2**. Songbird and mainnet are next steps.

## Contact
Carly E Sipahutar — sipahutarc3@gmail.com — GitHub [@Carlys17](https://github.com/Carlys17)
