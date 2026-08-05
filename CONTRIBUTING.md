# Contributing to Adumbra

Thank you for your interest in contributing to Adumbra! 🛡️

## Table of Contents

- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Running Tests](#running-tests)
- [Code Style](#code-style)
- [Submitting Changes](#submitting-changes)
- [Security](#security)

## Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
   git clone https://github.com/<your-username>/adumbra-flare.git
   cd adumbra-flare
   ```
3. Create a branch for your changes:
   ```bash
   git checkout -b feature/your-feature-name
   ```

## Development Setup

### Prerequisites

- **Rust 1.78+** — for the enclave service
- **Foundry** (`foundryup`) — for Solidity contracts
- **Python 3.12+** — with `eth-abi` and `pycryptodome`
- **Node.js 18+** — for frontend development

### Setup

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install Python dependencies
pip install eth-abi pycryptodome
```

## Running Tests

### Solidity (Foundry)

```bash
# Run all tests
forge test

# Run with gas snapshot
forge test --gas-report

# Run specific test
forge test --match-test testHappyPath
```

### Rust (Enclave)

```bash
cd tee
cargo test
```

### End-to-End

```bash
# Local anvil fork
anvil --port 8545 &
bash scripts/e2e_demo.sh
```

### Frontend

```bash
cd frontend
python3 -m http.server 8080
# Open http://localhost:8080 with MetaMask on Coston2
```

## Code Style

### Solidity

- Follow [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- Use `forge fmt` to format contracts
- Write NatSpec comments for all public functions
- Use `immutable` for constants set at deploy time

### Rust

- Run `cargo fmt` before committing
- Run `cargo clippy` for linting
- Document all public functions with `///` doc comments

### Frontend

- Use consistent indentation (2 spaces)
- Add comments for complex viem/wallet interactions

## Submitting Changes

1. Write tests for your changes
2. Ensure all tests pass:
   ```bash
   forge test && cd tee && cargo test
   ```
3. Format code:
   ```bash
   forge fmt && cd tee && cargo fmt
   ```
4. Update documentation if needed
5. Commit with a clear message:
   ```
   feat: add multi-hop routing in enclave
   fix: enforce EIP-2 low-s in signature verification
   docs: update deployment addresses for Songbird
   ```
6. Push to your fork and open a Pull Request

### Commit Message Format

We follow [Conventional Commits](https://www.conventionalcommits.org/):

| Type     | Description                              |
|----------|------------------------------------------|
| `feat`   | A new feature                            |
| `fix`    | A bug fix                                |
| `docs`   | Documentation only changes               |
| `style`  | Code style changes (formatting, etc.)    |
| `refactor` | Code changes that neither fix nor add |
| `test`   | Adding or updating tests                 |
| `chore`  | Maintenance tasks                        |

## Security

**This project handles real funds.** Security is paramount:

- Never commit private keys, enclave keys, or sensitive credentials
- Review all changes that affect signature verification or token transfers
- Report vulnerabilities via [SECURITY.md](SECURITY.md) — not public issues

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).