name: Tests

on:
  push:
    branches: [master]
  pull_request:
    branches: [master]

jobs:
  test-solidity:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Foundry
        uses: foundry-rs/foundry-toolchain@v1

      - name: Run Forge tests
        run: forge test -vvv

  test-rust:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Check Rust compiles
        run: |
          cd tee
          cargo check

      - name: Run Rust tests
        run: |
          cd tee
          cargo test