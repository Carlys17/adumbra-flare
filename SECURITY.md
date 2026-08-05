# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| main    | :white_check_mark: |

## Reporting a Vulnerability

**Adumbra handles real funds.** If you discover a security vulnerability, please report it responsibly:

1. **Do NOT** open a public GitHub Issue
2. Email the project maintainer at `carlysipahutar@proton.me`
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact assessment
   - Suggested fix (if any)

The team will acknowledge receipt within **48 hours** and aim to resolve critical issues within **7 days**.

## Security Considerations

### Smart Contract

- **Enclave signature verification** uses `ecrecover` with EIP-2 low-s enforcement
- **Nonce replay guard** prevents order re-submission
- **Deadline enforcement** limits order validity window
- **Slippage floor** protects users from bad quotes
- **No arbitrary code execution** — the router only pulls user-approved tokens

### Enclave (TEE)

- The enclave key is pinned at deploy time as an immutable `enclaveSigner`
- In production, the key will be bound to hardware attestation (SGX quote / Nitro PCR)
- Users trust the enclave for **route quality only, never custody**
- A compromised enclave cannot drain a user — it can at worst give a bad-but-bounded quote

### Frontend

- No private keys stored in the frontend
- All transactions are signed by the user's MetaMask wallet
- The enclave endpoint is the only external service dependency

## Audit Status

- [ ] Independent smart contract audit (planned before mainnet)
- [ ] Enclave code audit (planned before mainnet)
- [ ] Formal verification of signature verification logic

## Bug Bounty

A bug bounty program will be launched before mainnet deployment. Follow the project's social channels for announcements.