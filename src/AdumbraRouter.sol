// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AdumbraRouter
/// @notice Confidential order routing for FXRP on Flare.
///
///         Swap route selection happens inside a Trusted Execution Environment.
///         The enclave computes the optimal path and the slippage floor
///         privately, then signs a constrained order. On-chain we verify only
///         the enclave signature and settle the order atomically, so the route,
///         the exact quote, and the slippage strategy never enter the public
///         mempool and MEV searchers have nothing to front-run.
///
///         Route in shadow. Settle on chain.
interface IERC20Minimal {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract AdumbraRouter {
    /// @dev Domain separator bound into every order digest. Must stay byte-for-byte
    ///      identical to the value the enclave uses when building the digest.
    string private constant DOMAIN = "Adumbra";

    // --- Enclave verification ---
    address public immutable enclaveSigner;

    // Per-user nonces — each trader gets their own replay-protected sequence
    mapping(address => uint256) public userNonces;

    // --- Ownership (for rescue / upgrades) ---
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    struct SwapOrder {
        address user;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 deadline;
        uint256 orderNonce;
    }

    struct SignedOrder {
        SwapOrder order;
        bytes signature;
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

    constructor(address _enclaveSigner, address _owner) {
        require(_enclaveSigner != address(0), "zero signer");
        require(_owner != address(0), "zero owner");
        enclaveSigner = _enclaveSigner;
        owner = _owner;
    }

    /// @notice Execute an enclave-signed swap. Anyone may submit (relayers), but
    ///         the order is bound to `user` so only they benefit.
    function executeSwap(SignedOrder calldata so) external returns (uint256 amountOut) {
        SwapOrder memory o = so.order;

        // === CHECKS ===
        if (o.deadline < block.timestamp - 30) revert Expired();
        if (o.orderNonce != userNonces[o.user]) revert Replay();

        bytes32 digest = keccak256(abi.encode(
            DOMAIN, o.user, o.tokenIn, o.tokenOut,
            o.amountIn, o.minAmountOut, o.deadline, o.orderNonce
        ));
        if (recoverSigner(digest, so.signature) != enclaveSigner) revert UnauthorizedSigner();

        // === EFFECTS — state change BEFORE external calls (reentrancy guard) ===
        unchecked {
            userNonces[o.user] = o.orderNonce + 1;
        }

        // === INTERACTIONS ===
        if (!IERC20Minimal(o.tokenIn).transferFrom(o.user, address(this), o.amountIn)) {
            revert TransferFailed();
        }

        uint256 balOut = IERC20Minimal(o.tokenOut).balanceOf(address(this));
        if (balOut < o.minAmountOut) revert SlippageExceeded();
        amountOut = o.minAmountOut;

        if (!IERC20Minimal(o.tokenOut).transfer(o.user, amountOut)) revert TransferFailed();

        emit SwapExecuted(o.user, o.tokenIn, o.tokenOut, o.amountIn, amountOut, o.orderNonce);
    }

    function recoverSigner(bytes32 digest, bytes calldata sig) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(sig);
        // EIP-2: reject high-s to prevent signature malleability
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

    // --- Admin ---
    function rescue(address token, uint256 amount) external onlyOwner {
        require(IERC20Minimal(token).transfer(msg.sender, amount), "transfer failed");
    }

    function renounceOwnership() external onlyOwner {
        owner = address(0);
    }
}