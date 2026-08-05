# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- **Production-ready repository structure**
  - `LICENSE` — MIT License
  - `SECURITY.md` — Security policy and responsible disclosure
  - `CONTRIBUTING.md` — Contributor guide with setup, testing, and code style
  - `CHANGELOG.md` — This file
  - `CODEOWNERS` — Code ownership rules
- **CI/CD pipelines**
  - Foundry CI — Solidity tests + gas report on every PR
  - Rust CI — Enclave tests + clippy linting on every PR

### Changed
- Updated README with production readiness checklist

## [1.0.0] - 2026-06-15

### Added
- Initial release — Flare Summer Signal hackathon submission
- **AdumbraRouter.sol** — On-chain enclave signature verification + atomic swap execution
  - `ecrecover` with EIP-2 low-s enforcement
  - Nonce replay guard
  - Deadline enforcement
  - Slippage floor protection
- **tee/src/main.rs** — Rust enclave service
  - Private route computation
  - ECDSA order signing (byte-compatible with Solidity `abi.encode`)
  - CLI one-shot mode + HTTP `/sign` server mode
- **frontend/index.html** — viem + MetaMask wallet UI
- **scripts/** — E2E demo + ABI encoder
- **test/AdumbraRouter.t.sol** — 6 Foundry tests (all passing)
- Coston2 testnet deployment (source-verified)
- Live demo: https://adumbra.carly17.my.id/
- Video demo on YouTube

### Roadmap
- Multi-hop routing against SparkDEX and BlazeSwap
- SGX/Nitro attested keys
- AMM execution (real DEX settlement)
- Sealed-bid batching
- Songbird → Flare mainnet deployment
- Independent security audit