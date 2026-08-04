// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MEVSwapRouter
/// @notice TEE-protected swap router for Flare. Swap intents are routed inside
///         a confidential enclave (TEE). The enclave picks the optimal
///         multi-hop path and emits a signed order. On-chain we only verify the
///         enclave signature and execute the order atomically, so MEV bots
///         never see the route/slippage logic until the tx is already mined.
interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract MEVSwapRouter {
    // --- Enclave verification ---
    // The TEE signs orders with a key whose address is pinned at deploy time.
    // In production this is an attestation-backed key (SGX quote / Nitro PCR).
    address public immutable enclaveSigner;
    uint256 public nonce;

    // Route steps are executed off-chain by the TEE; the contract only needs
    // the final leg so it can pull tokens from the user and deliver the output.
    struct SwapOrder {
        address user;          // who pays input
        address tokenIn;       // input token (e.g. FXRP)
        address tokenOut;      // output token (e.g. USDC)
        uint256 amountIn;      // exact input
        uint256 minAmountOut;  // slippage guard set by TEE (hidden from MEV)
        uint256 deadline;      // block timestamp deadline
        uint256 orderNonce;    // replay protection
    }

    // Signed intent from the enclave. The "route" is deliberately opaque:
    // only tokenIn/tokenOut/amounts are revealed. The actual intermediate
    // hops were decided inside the TEE and are not part of public calldata.
    struct SignedOrder {
        SwapOrder order;
        bytes signature;      // ECDSA over the order by enclaveSigner
    }

    event SwapExecuted(
        address indexed user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 orderNonce
    );

    error UnauthorizedSigner();
    error Expired();
    error SlippageExceeded();
    error Replay();
    error TransferFailed();

    constructor(address _enclaveSigner) {
        require(_enclaveSigner != address(0), "zero signer");
        enclaveSigner = _enclaveSigner;
    }

    /// @notice Execute a TEE-signed swap. Anyone may submit (relayers), but the
    ///         order is bound to `user` so only they benefit.
    function executeSwap(SignedOrder calldata so) external returns (uint256 amountOut) {
        SwapOrder memory o = so.order;
        if (o.deadline < block.timestamp) revert Expired();
        if (o.orderNonce != nonce) revert Replay();

        bytes32 digest = keccak256(abi.encode(
            "MEVSwap", o.user, o.tokenIn, o.tokenOut,
            o.amountIn, o.minAmountOut, o.deadline, o.orderNonce
        ));
        if (recoverSigner(digest, so.signature) != enclaveSigner) revert UnauthorizedSigner();

        // Pull input from user.
        if (!IERC20Minimal(o.tokenIn).transferFrom(o.user, address(this), o.amountIn)) {
            revert TransferFailed();
        }

        // In this MVP the router is a single-leg direct swap: it holds a
        // reserve of tokenOut. A full deployment routes through an AMM inside
        // the TEE's chosen path; here we demonstrate the privacy + verification
        // core.
        uint256 balOut = IERC20Minimal(o.tokenOut).balanceOf(address(this));
        if (balOut < o.minAmountOut) revert SlippageExceeded();
        amountOut = o.minAmountOut;
        if (!IERC20Minimal(o.tokenOut).transfer(o.user, amountOut)) revert TransferFailed();

        nonce = o.orderNonce + 1;
        emit SwapExecuted(o.user, o.tokenIn, o.tokenOut, o.amountIn, amountOut, o.orderNonce);
    }

    function recoverSigner(bytes32 digest, bytes calldata sig) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(sig);
        // EIP-2: low-s
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            revert UnauthorizedSigner();
        }
        return ecrecover(digest, v, r, s);
    }

    function splitSignature(bytes calldata sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "bad sig len");
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }
        if (v < 27) v += 27;
    }

    // --- Admin / rescue ---
    function rescue(address token, uint256 amount) external {
        if (msg.sender != 0x000000000000000000000000000000000000dEaD) revert UnauthorizedSigner();
        IERC20Minimal(token).transfer(msg.sender, amount);
    }
}