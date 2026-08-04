# Adumbra — Flare Summer Signal Submission

## 1. Project Name
**Adumbra** — Confidential Order Routing for FXRP on Flare.

## 2. Selected Bounty
**Bounty 2 — Confidential Compute Apps**

## 3. Short Product Description
Adumbra runs swap route selection inside a Trusted Execution Environment. The enclave
computes the optimal path and the slippage floor privately, then signs a constrained
order. On-chain, only the enclave signature is verified and the order executed — the
route, the exact quote, and the slippage strategy never enter the public mempool, so MEV
searchers have nothing to front-run.

## 4. Target User
FXRP and FAssets traders on Flare who currently lose value to sandwich attacks and
front-running, plus protocols and aggregators that want MEV-resistant execution without
asking users to change wallets or workflows.

## 5. Demo Link / Video / Working App
- **Live on Coston2** — verified enclave-signed swap:
  https://coston2-explorer.flare.network/tx/0x15e696943c87289629a5cb2ad241a1fe8bdf4b5a0dc76e60a342052cb0322bf6
- **Frontend** — `frontend/index.html` (viem + MetaMask, wired to the Coston2 deployment).
  Run `cd frontend && python3 -m http.server 8080`, start the enclave with
  `adumbra-enclave --serve`, then open http://localhost:8080 with MetaMask on Coston2.
- **Local end-to-end script** — `bash scripts/e2e_demo.sh` executes the entire flow
  against anvil: fund, approve, enclave sign, execute, verify balances.

## 6. GitHub Repo
https://github.com/Carlys17/adumbra-flare

## 7. How It Uses Flare

**Flare Confidential Compute is the core mechanism, not an add-on.** Route selection,
quoting, and order signing all happen inside the enclave. Only the signed, constrained
result reaches the chain.

**Flare EVM (Coston2)** hosts `AdumbraRouter`, which recovers the enclave signer with
`ecrecover` (EIP-2 low-s enforced), checks the deadline and nonce, and settles the swap
atomically.

Targets the **FXRP / FAssets** flow specifically — Flare's distinguishing asset layer,
where MEV protection has direct user impact.

### What runs privately inside the TEE
Route path and intermediate hops, the exact price quote, the slippage strategy that
produces `minAmountOut`, and the enclave signing key.

### What is verified and consumed on-chain
`tokenIn`, `tokenOut`, `amountIn`, `minAmountOut`, `deadline`, `orderNonce`, and the
enclave signature. The contract recovers the signer and rejects anything not signed by
the pinned enclave key, anything past its deadline, and any replayed nonce.

### Trust assumptions
The enclave signing key is pinned at deploy time as an immutable. In production it is
bound to a hardware attestation — SGX quote or Nitro PCR — which the contract verifies
before accepting the key. Users trust the enclave for **route quality only, never
custody**: funds move solely via an order bound to `order.user`, capped at `amountIn`,
floored at `minAmountOut`, expiring at `deadline`, single-use per nonce. A compromised
enclave cannot drain a user; at worst it returns a bad-but-bounded quote. The contract
remains the enforcement layer for everything the enclave decides in private.

### Why confidential compute rather than a normal smart contract
A pure on-chain router cannot hide its inputs: calldata and state are public by
construction, so route and slippage parameters are visible before the trade lands. This
is not an implementation flaw better Solidity can fix — it is the EVM execution model. A
TEE changes *when* the information becomes public: by the time the route is observable,
the trade is already settled and no ordering advantage remains to extract.

## 8. What Was Newly Built During the Program
Adumbra was built from scratch during the hackathon; there was no pre-existing project.

- `AdumbraRouter.sol` — enclave signature verification (`ecrecover`, EIP-2 low-s),
  nonce replay guard, deadline enforcement, slippage floor, atomic execution.
- `tee/src/main.rs` — the enclave service: private route computation, keccak256 digest
  construction byte-for-byte compatible with Solidity `abi.encode`, recoverable ECDSA
  signing, CLI one-shot mode plus an HTTP `/sign` server mode with CORS.
- `frontend/index.html` — viem + MetaMask app: reads the on-chain nonce, requests the
  enclave signature, handles ERC20 approval, submits `executeSwap`.
- `scripts/encode_calldata.py` — ABI encoder for the nested `SignedOrder` tuple, a shape
  `cast` cannot parse.
- `scripts/e2e_demo.sh` — full local end-to-end verification run.
- 6 Foundry tests: happy path, expired order, replayed nonce, wrong signer, tampered
  order, slippage failure.
- Coston2 deployment plus a verified on-chain enclave-signed swap.

## 9. Smart Contract Addresses / Deployment
Deployed on **Flare Coston2** (chainId 114, RPC `https://coston2-api.flare.network/ext/C/rpc`):

| Contract | Address |
|---|---|
| AdumbraRouter | `0xcA1BFA56281a5082EfcAa64bbd34653b0AfCCAc7` |
| Mock FXRP | `0x92bdD788e158Db8d7b0F2Dc32ddefe0fC8783fC5` |
| Mock USDC | `0x1cAAb501Cb8D7959e5Def5577863a4b346523552` |

Verified enclave-signed swap: tx `0x15e696943c87289629a5cb2ad241a1fe8bdf4b5a0dc76e60a342052cb0322bf6`
(block 33625271) — 100 FXRP in, 51.74 USDC out, router nonce 0 → 1.

## 10. Technical Execution Evidence
```
forge test
[PASS] testHappyPath()           (gas: 133235)
[PASS] testRevertExpired()       (gas: 30982)
[PASS] testRevertReplay()        (gas: 131021)
[PASS] testRevertSlippage()      (gas: 72450)
[PASS] testRevertTamperedOrder() (gas: 36520)
[PASS] testRevertWrongSigner()   (gas: 39451)
6 passed; 0 failed; 0 skipped
```
```
Enclave HTTP service — live response from POST localhost:7070/sign
{
  "min_amount_out": "51740000000000000000",
  "order_nonce": "0",
  "signature": "0x...",
  "tee_report": "Enclave 0x423ece2094 routed FXRP -> USDC at rate 0.520000"
}
```

## 11. Roadmap / Next Steps
1. **Real routing** — multi-hop quoting inside the enclave against SparkDEX and BlazeSwap,
   replacing the dev rate table.
2. **Attested keys** — on-chain SGX quote / Nitro PCR verification so the signing key is
   provably enclave-bound rather than deployer-pinned.
3. **AMM execution** — settle along the enclave-chosen path instead of the single-leg
   reserve model used for this demo.
4. **Sealed-bid batching** — clear multiple intents together so ordering-based MEV
   disappears entirely rather than being merely hidden.
5. **Songbird, then Flare mainnet.**

## 12. Deployment Target
Deployed and verified on **Coston2**. Songbird and mainnet are the next steps.

## Contact
Carly E Sipahutar — sipahutarc3@gmail.com — GitHub [@Carlys17](https://github.com/Carlys17)
