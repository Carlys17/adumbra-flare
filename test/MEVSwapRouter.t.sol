// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/MEVSwapRouter.sol";
import "../src/mocks/MockERC20.sol";

contract MEVSwapRouterTest is Test {
    MEVSwapRouter router;
    MockERC20 fXRP;    // input
    MockERC20 usdc;    // output

    // Enclave signer key (dev only – real TEE uses attestation)
    uint256 enclavePriv = 0xabcd;
    address enclavePub;

    address user = address(0xBEEF);
    uint256 amountIn = 100 ether;

    function setUp() public {
        enclavePub = vm.addr(enclavePriv);
        fXRP = new MockERC20("Fake XRP", "FXRP", 1_000_000 ether);
        usdc = new MockERC20("Fake USDC", "USDC", 1_000_000 ether);

        router = new MEVSwapRouter(enclavePub);

        // Fund user with FXRP + approve
        fXRP.transfer(user, amountIn);
        vm.prank(user);
        fXRP.approve(address(router), amountIn);

        // Fund router with USDC (so we can pay output)
        usdc.transfer(address(router), 200_000 ether);
    }

    function _makeOrder() internal view returns (
        MEVSwapRouter.SignedOrder memory, bytes32
    ) {
        MEVSwapRouter.SwapOrder memory order = MEVSwapRouter.SwapOrder({
            user: user,
            tokenIn: address(fXRP),
            tokenOut: address(usdc),
            amountIn: amountIn,
            minAmountOut: 1 ether,   // router pays 1 USDC per 100 FXRP
            deadline: block.timestamp + 3600,
            orderNonce: router.nonce()
        });

        bytes32 digest = keccak256(abi.encode(
            "MEVSwap",
            order.user,
            order.tokenIn,
            order.tokenOut,
            order.amountIn,
            order.minAmountOut,
            order.deadline,
            order.orderNonce
        ));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(enclavePriv, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        MEVSwapRouter.SignedOrder memory so = MEVSwapRouter.SignedOrder(order, sig);
        return (so, digest);
    }

    function testHappyPath() public {
        (MEVSwapRouter.SignedOrder memory so, ) = _makeOrder();
        uint256 usdcBefore = usdc.balanceOf(user);
        uint256 fXRPBefore = fXRP.balanceOf(user);

        vm.prank(user);
        uint256 amountOut = router.executeSwap(so);

        assertEq(usdc.balanceOf(user) - usdcBefore, so.order.minAmountOut, "USDC not received");
        assertEq(fXRP.balanceOf(user), fXRPBefore - so.order.amountIn, "FXRP not spent");
        assertEq(amountOut, so.order.minAmountOut);
    }

    function testRevertExpired() public {
        (MEVSwapRouter.SignedOrder memory so, ) = _makeOrder();
        vm.warp(block.timestamp + 4000); // past deadline
        vm.prank(user);
        vm.expectRevert(MEVSwapRouter.Expired.selector);
        router.executeSwap(so);
    }

    function testRevertWrongSigner() public {
        (MEVSwapRouter.SignedOrder memory so, ) = _makeOrder();
        // Tamper signature – use a different key
        bytes32 fakeDigest = keccak256("tampered");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1234, fakeDigest);
        so.signature = abi.encodePacked(r, s, v);
        vm.prank(user);
        vm.expectRevert(MEVSwapRouter.UnauthorizedSigner.selector);
        router.executeSwap(so);
    }

    function testRevertReplay() public {
        (MEVSwapRouter.SignedOrder memory so, ) = _makeOrder();
        vm.prank(user);
        router.executeSwap(so);
        // Replay same order -> nonce mismatch
        vm.prank(user);
        vm.expectRevert(MEVSwapRouter.Replay.selector);
        router.executeSwap(so);
    }

    function testRevertSlippage() public {
        // Sign an order that demands more USDC than the router holds
        MEVSwapRouter.SwapOrder memory order = MEVSwapRouter.SwapOrder({
            user: user,
            tokenIn: address(fXRP),
            tokenOut: address(usdc),
            amountIn: amountIn,
            minAmountOut: 999_999 ether, // more than router balance
            deadline: block.timestamp + 3600,
            orderNonce: router.nonce()
        });
        bytes32 digest = keccak256(abi.encode(
            "MEVSwap",
            order.user,
            order.tokenIn,
            order.tokenOut,
            order.amountIn,
            order.minAmountOut,
            order.deadline,
            order.orderNonce
        ));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(enclavePriv, digest);
        MEVSwapRouter.SignedOrder memory so = MEVSwapRouter.SignedOrder(order, abi.encodePacked(r, s, v));

        vm.prank(user);
        vm.expectRevert(MEVSwapRouter.SlippageExceeded.selector);
        router.executeSwap(so);
    }
}
