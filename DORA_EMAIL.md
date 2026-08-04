Subject: #QwenGrowthPlan + MEV-Safe FXRP Swap Router

Dear DoraHacks & Flare Summer Signal Team,

I'm submitting the MEV-Safe FXRP Swap Router (TEE) for Bounty 2: Confidential Compute Apps.

1. Agent Task Scenario
The project implements a TEE-protected swap routing layer on Flare that shields FXRP swap orders from MEV (Miner Extractable Value) attacks. In traditional DeFi, user swap transactions sit exposed in the mempool where bots can front-run, sandwich-attack, or manipulate execution. By moving order composition and signing inside a Trusted Execution Environment, the raw swap intent and routing logic never touch an untrusted host — MEV bots see only the final signed transaction already committed for execution.

2. Prompt
The architecture follows a TEE-first design: a Rust service running inside an enclave receives swap requests, computes the optimal route, and signs the composed order with an enclave-held key. The signed order is relayed on-chain where the verification contract confirms the signature before executing the swap. From the perspective of MEV searchers, the mempool contains only the opaque, already-finalized transaction — the routing logic, amounts, and timing signals were decided confidentially inside the enclave.

3. Qwen 3.8 Actual Performance
All 5 Forge tests pass:
- testHappyPath, testRevertExpired, testRevertReplay, testRevertWrongSigner, testRevertSlippage
End-to-end demo verified working on local anvil:
- TEE signed order -> executeSwap -> status=1 (success)
- tx: 0xf6de35a4604e2e08c4440a562d628094c7cf8e056a4f59fc264122d9a0a36cf6
- 100 FXRP -> 51.74 USDC
Repository: https://github.com/Carlys17/flare-swap-router

4. Evaluation
- Prototype: fully working with passing tests and verified execution
- Signature verification: on-chain ECDSA/secp256k1 of TEE-signed orders
- TEE service: Rust enclave service operational, signing orders
- Frontend: demo UI included

5. Contact
Carly E Sipahutar
Email: sipahutarc3@gmail.com

Thank you for your consideration.

Best regards,
Carly E Sipahutar
