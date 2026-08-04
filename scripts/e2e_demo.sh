#!/usr/bin/env bash
# End-to-end demo: TEE signs order -> on-chain executeSwap -> balances verified
set -euo pipefail
export PATH="$PATH:/root/.foundry/bin"
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(pwd)"

source /tmp/addresses.env 2>/dev/null || { echo "Run deploy first: source /tmp/addresses.env"; exit 1; }

KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
RPC=http://127.0.0.1:8545
USER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
USER_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
AMT=100000000000000000000

echo "== 1. Fund user with FXRP =="
cast send $FXRP_ADDR "transfer(address,uint256)" $USER $AMT --private-key $KEY --rpc-url $RPC > /dev/null
echo "  user FXRP: $(cast call $FXRP_ADDR 'balanceOf(address)(uint256)' $USER --rpc-url $RPC)"

echo "== 2. Fund router with USDC reserve =="
cast send $USDC_ADDR "transfer(address,uint256)" $CONTRACT_ADDR 200000000000000000000 --private-key $KEY --rpc-url $RPC > /dev/null

echo "== 3. User approves router =="
cast send $FXRP_ADDR "approve(address,uint256)" $CONTRACT_ADDR $AMT --private-key $USER_KEY --rpc-url $RPC > /dev/null

echo "== 4. Build swap intent and call TEE (Rust) =="
NONCE=$(cast call $CONTRACT_ADDR 'nonce()(uint256)' --rpc-url $RPC)
ORDER=$(echo '{"user":"'$USER'","symbol_in":"FXRP","symbol_out":"USDC","token_in":"'$FXRP_ADDR'","token_out":"'$USDC_ADDR'","amount_in":"'$AMT'","slippage_bps":50}' | ENCLAVE_KEY=$KEY tee/target/release/mevswap-tee --intent - --deadline 3600 --nonce $NONCE)
echo "$ORDER" | jq .

MIN_OUT=$(echo "$ORDER" | jq -r '.min_amount_out')
DEADLINE=$(echo "$ORDER" | jq -r '.deadline')
SIG=$(echo "$ORDER" | jq -r '.signature')

echo "  minAmountOut (wei): $MIN_OUT"
echo "  deadline:           $DEADLINE"
echo "  signature:          $SIG"

echo "== 5. Execute swap on-chain =="
ORDER_JSON='{"user":"'$USER'","tokenIn":"'$FXRP_ADDR'","tokenOut":"'$USDC_ADDR'","amountIn":"'$AMT'","minOut":"'$MIN_OUT'","deadline":"'$DEADLINE'","nonce":"'$NONCE'"}'
CALLDATA=$("$REPO_ROOT/.venv/bin/python3" "$REPO_ROOT/scripts/encode_calldata.py" "$ORDER_JSON" "$SIG")
echo "  calldata: ${CALLDATA:0:70}..."
cast send $CONTRACT_ADDR $CALLDATA --private-key $USER_KEY --rpc-url $RPC 2>&1 | grep -E "status|transactionHash"

echo "== 6. Verify balances =="
echo "  User FXRP balance:  $(cast call $FXRP_ADDR 'balanceOf(address)(uint256)' $USER --rpc-url $RPC)"
echo "  User USDC balance:  $(cast call $USDC_ADDR 'balanceOf(address)(uint256)' $USER --rpc-url $RPC)"
echo "  Router nonce:       $(cast call $CONTRACT_ADDR 'nonce()(uint256)' --rpc-url $RPC)"

echo ""
echo "DONE - swap executed through TEE-signed order"
