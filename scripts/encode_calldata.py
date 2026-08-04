#!/usr/bin/env python3
"""Encode executeSwap calldata for AdumbraRouter using eth_abi."""
import sys, json

try:
    from eth_abi import encode
except ImportError:
    sys.exit("eth_abi not installed: pip install eth-abi")

def main():
    order = json.loads(sys.argv[1])  # {user, tokenIn, tokenOut, amountIn, minOut, deadline, nonce}
    sig = sys.argv[2]

    user = order["user"]
    tokenIn = order["tokenIn"]
    tokenOut = order["tokenOut"]
    amountIn = int(order["amountIn"])
    minOut = int(order["minOut"])
    deadline = int(order["deadline"])
    nonce = int(order["nonce"])

    sig_bytes = bytes.fromhex(sig[2:])

    # The function is executeSwap(((address,address,address,uint256,uint256,uint256,uint256),bytes))
    # Encode as a single tuple: ((swap_order_tuple), bytes)
    swap_order = (user, tokenIn, tokenOut, amountIn, minOut, deadline, nonce)
    signed_order = (swap_order, sig_bytes)

    # Use eth_abi to encode the full tuple
    encoded = encode(
        ["((address,address,address,uint256,uint256,uint256,uint256),bytes)"],
        [signed_order]
    )

    # Compute selector
    from Crypto.Hash import keccak
    k = keccak.new(digest_bits=256)
    k.update(b"executeSwap(((address,address,address,uint256,uint256,uint256,uint256),bytes))")
    selector = k.digest()[:4]

    print("0x" + selector.hex() + encoded.hex())

if __name__ == "__main__":
    main()
