#!/usr/bin/env bash
# Scripted walkthrough for the Adumbra demo recording.
# Every step runs for real against the live Coston2 deployment.
set -uo pipefail
export PATH="$PATH:/root/.foundry/bin"
cd /root/adumbra-flare
source /root/flare-deployer.env

ROUTER=0x8D129cb1deb2736A86d97182c5809CBf1759Ab8c
FXRP=0x92bdD788e158Db8d7b0F2Dc32ddefe0fC8783fC5
USDC=0x1cAAb501Cb8D7959e5Def5577863a4b346523552
RPC=https://coston2-api.flare.network/ext/C/rpc
KEY=$DEPLOYER_KEY
USER=$DEPLOYER_ADDR
AMT=100000000000000000000

C='\033[36m'; G='\033[32m'; Y='\033[33m'; D='\033[90m'; B='\033[1m'; R='\033[0m'
say()  { echo -e "${C}${B}$1${R}"; sleep 0.7; }
note() { echo -e "${D}$1${R}"; sleep 0.4; }
ok()   { echo -e "${G}$1${R}"; sleep 0.5; }
num()  { python3 -c "print(f'{int('$1')/1e18:,.2f}')"; }
lt()   { python3 -c "import sys; sys.exit(0 if int('$1') < int('$2') else 1)"; }

# --- Pre-flight, before narration: output liquidity, allowance, and a clean
# enclave port. A stale enclave holding :7070 would sign with the wrong domain
# separator and every order would revert with UnauthorizedSigner.
pkill -f adumbra-enclave >/dev/null 2>&1 || true
sleep 1

RESERVE=$(cast call $USDC 'balanceOf(address)(uint256)' $ROUTER --rpc-url $RPC | awk '{print $1}')
if lt "$RESERVE" 60000000000000000000; then
  cast send $USDC "transfer(address,uint256)" $ROUTER 200000000000000000000 \
    --private-key $KEY --rpc-url $RPC --legacy >/dev/null 2>&1
fi
ALLOW=$(cast call $FXRP 'allowance(address,address)(uint256)' $USER $ROUTER --rpc-url $RPC | awk '{print $1}')
if lt "$ALLOW" "$AMT"; then
  cast send $FXRP "approve(address,uint256)" $ROUTER $AMT \
    --private-key $KEY --rpc-url $RPC --legacy >/dev/null 2>&1
fi

echo -e "${B}Adumbra${R} — Confidential Order Routing for FXRP on Flare"
echo -e "${D}Route in shadow. Settle on chain.${R}"
echo -e "${D}Flare Summer Signal · Bounty 2: Confidential Compute Apps${R}"
echo
sleep 1.5

say "[1/6] Live and source-verified on Flare Coston2"
note "  AdumbraRouter  $ROUTER"
NONCE=$(cast call $ROUTER 'nonce()(uint256)' --rpc-url $RPC | awk '{print $1}')
echo -e "  order nonce: ${B}${NONCE}${R}"
FXRP_BEFORE=$(cast call $FXRP 'balanceOf(address)(uint256)' $USER --rpc-url $RPC | awk '{print $1}')
USDC_BEFORE=$(cast call $USDC 'balanceOf(address)(uint256)' $USER --rpc-url $RPC | awk '{print $1}')
echo -e "  trader FXRP  $(num $FXRP_BEFORE)"
echo -e "  trader USDC  $(num $USDC_BEFORE)"
sleep 1.2
echo

say "[2/6] Starting the enclave"
note "  In production this binary runs inside SGX / AWS Nitro."
note "  It holds the signing key and never reveals its routing logic."
ENCLAVE_KEY=$KEY ./tee/target/release/adumbra-enclave --serve > /tmp/adumbra-demo-tee.log 2>&1 &
TEE_PID=$!
trap 'kill $TEE_PID 2>/dev/null' EXIT
sleep 2
if ! curl -s -o /dev/null -m 3 -X OPTIONS http://localhost:7070/sign; then
  echo -e "${Y}  enclave failed to start${R}"; cat /tmp/adumbra-demo-tee.log; exit 1
fi
ok "  enclave listening on :7070"
echo

say "[3/6] The trader submits an intent — 100 FXRP for USDC"
note "  They declare WHAT they want. Never HOW to route it."
INTENT=$(printf '{"user":"%s","symbol_in":"FXRP","symbol_out":"USDC","token_in":"%s","token_out":"%s","amount_in":"%s","slippage_bps":50,"nonce":%s}' \
  "$USER" "$FXRP" "$USDC" "$AMT" "$NONCE")
echo -e "${D}  POST localhost:7070/sign${R}"
sleep 0.8
ORDER=$(curl -s -X POST http://localhost:7070/sign -H 'Content-Type: application/json' -d "$INTENT")
# Abbreviate the 132-char signature for display only so the frame never wraps.
echo "$ORDER" | python3 -c "
import json,sys
o=json.load(sys.stdin)
s=o['signature']
o['signature']=s[:14]+'...'+s[-12:]
print(json.dumps(o,indent=4))
" | sed 's/^/  /'
sleep 2
echo
note "  What is absent from that response is the point: no path, no pools,"
note "  no quote derivation, no slippage strategy. That never left the enclave."
sleep 1.8
echo

MIN_OUT=$(echo "$ORDER" | jq -r '.min_amount_out')
DEADLINE=$(echo "$ORDER" | jq -r '.deadline')
SIG=$(echo "$ORDER" | jq -r '.signature')

say "[4/6] The contract re-derives the digest and runs ecrecover"
note "  A different key, one altered field, a stale deadline, a reused nonce → revert."
ORDER_JSON=$(printf '{"user":"%s","tokenIn":"%s","tokenOut":"%s","amountIn":"%s","minOut":"%s","deadline":"%s","nonce":"%s"}' \
  "$USER" "$FXRP" "$USDC" "$AMT" "$MIN_OUT" "$DEADLINE" "$NONCE")
CALLDATA=$(./.venv/bin/python3 scripts/encode_calldata.py "$ORDER_JSON" "$SIG")
SIM=$(cast call $ROUTER "$CALLDATA" --from "$USER" --rpc-url $RPC 2>&1)
if [[ "$SIM" == 0x* ]]; then
  SIM_OUT=$(python3 -c "print(int('$SIM', 16))")
  ok "  signature accepted — static call returns $(num $SIM_OUT) USDC out"
else
  echo -e "${Y}  simulation reverted:${R} $SIM"; exit 1
fi
sleep 1.5
echo

say "[5/6] Settling on Flare"
TX=$(cast send $ROUTER "$CALLDATA" --private-key $KEY --rpc-url $RPC --legacy 2>&1)
if echo "$TX" | grep -q 'status .*1 (success)'; then
  echo "$TX" | grep -E '^blockNumber|^gasUsed|^status|^transactionHash' | sed 's/^/  /'
else
  echo -e "${Y}  submission failed:${R}"; echo "$TX" | head -5 | sed 's/^/  /'; exit 1
fi
sleep 1.5
echo

say "[6/6] Settled"
FXRP_AFTER=$(cast call $FXRP 'balanceOf(address)(uint256)' $USER --rpc-url $RPC | awk '{print $1}')
USDC_AFTER=$(cast call $USDC 'balanceOf(address)(uint256)' $USER --rpc-url $RPC | awk '{print $1}')
NEW_NONCE=$(cast call $ROUTER 'nonce()(uint256)' --rpc-url $RPC | awk '{print $1}')
echo -e "  FXRP  $(num $FXRP_BEFORE)  →  $(num $FXRP_AFTER)"
echo -e "  USDC  $(num $USDC_BEFORE)  →  $(num $USDC_AFTER)"
echo -e "  order nonce  ${NONCE} → ${NEW_NONCE}   ${D}this order can never replay${R}"
sleep 1.8
echo
ok "By the time a searcher can read this transaction, it is already settled."
note "There is no ordering advantage left to extract."
echo
echo -e "${Y}github.com/Carlys17/adumbra-flare${R}"
sleep 1.5
