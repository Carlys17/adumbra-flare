// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AdumbraRouter.sol";
import "../src/mocks/MockERC20.sol";

contract AdumbraRouterTest is Test {
    AdumbraRouter router;
    MockERC20 fXRP;    // input
    MockERC20 usdc;    // output

    // Enclave signer key (dev only – a real TEE uses an attested key)
    uint256 enclavePriv = 0xabcd;
    address enclavePub;

    address user = address(0xBEEF);
    uint256 amountIn = 100 ether;

    function setUp() public {
        enclavePub = vm.addr(enclavePriv);
        fXRP = new MockERC20("Fake XRP", "FXRP", 1_000_000 ether);
        usdc = new MockERC20("Fake USDC", "USDC", 1_000_000 ether);

        router = new AdumbraRouter(enclavePub);

        // Fund user with FXRP + approve
        fXRP.transfer(user, amountIn);
        vm.prank(user);
        fXRP.approve(address(router), amountIn);

        // Fund router with USDC so it can pay output
        usdc.transfer(address(router), 200_000 ether);
    }

    function _digest(AdumbraRouter.SwapOrder memory order) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            "Adumbra",
            order.user,
            order.tokenIn,
            order.tokenOut,
            order.amountIn,
            order.minAmountOut,
            order.deadline,
            order.orderNonce
        ));
    }

    function _makeOrder() internal view returns (AdumbraRouter.SignedOrder memory, bytes32) {
        AdumbraRouter.SwapOrder memory order = AdumbraRouter.SwapOrder({
            user: user,
            tokenIn: address(fXRP),
            tokenOut: address(usdc),
            amountIn: amountIn,
            minAmountOut: 1 ether,   // router pays 1 USDC per 100 FXRP in this fixture
            deadline: block.timestamp + 3600,
            orderNonce: router.nonce()
        });

        bytes32 digest = _digest(order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(enclavePriv, digest);
        bytes memory sig = abi.encodePacked(r, s, v);
        return (AdumbraRouter.SignedOrder(order, sig), digest);
    }

    function testHappyPath() public {
        (AdumbraRouter.SignedOrder memory so, ) = _makeOrder();
        uint256 usdcBefore = usdc.balanceOf(user);
        uint256 fXRPBefore = fXRP.balanceOf(user);

        vm.prank(user);
        uint256 amountOut = router.executeSwap(so);

        assertEq(usdc.balanceOf(user) - usdcBefore, so.order.minAmountOut, "USDC not received");
        assertEq(fXRP.balanceOf(user), fXRPBefore - so.order.amountIn, "FXRP not spent");
        assertEq(amountOut, so.order.minAmountOut);
    }

    function testRevertExpired() public {
        (AdumbraRouter.SignedOrder memory so, ) = _makeOrder();
        vm.warp(block.timestamp + 4000); // past deadline
        vm.prank(user);
        vm.expectRevert(AdumbraRouter.Expired.selector);
        router.executeSwap(so);
    }

    function testRevertWrongSigner() public {
        (AdumbraRouter.SignedOrder memory so, ) = _makeOrder();
        // Sign the same order with a key that is not the pinned enclave key
        bytes32 digest = _digest(so.order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1234, digest);
        so.signature = abi.encodePacked(r, s, v);
        vm.prank(user);
        vm.expectRevert(AdumbraRouter.UnauthorizedSigner.selector);
        router.executeSwap(so);
    }

    function testRevertTamperedOrder() public {
        // A valid enclave signature must not carry over to a modified order:
        // bumping amountIn after signing changes the digest, so recovery fails.
        (AdumbraRouter.SignedOrder memory so, ) = _makeOrder();
        so.order.amountIn = amountIn + 1;
        vm.prank(user);
        vm.expectRevert(AdumbraRouter.UnauthorizedSigner.selector);
        router.executeSwap(so);
    }

    function testRevertReplay() public {
        (AdumbraRouter.SignedOrder memory so, ) = _makeOrder();
        vm.prank(user);
        router.executeSwap(so);
        // Replaying the same order fails the nonce check
        vm.prank(user);
        vm.expectRevert(AdumbraRouter.Replay.selector);
        router.executeSwap(so);
    }

    function testRevertSlippage() public {
        // Sign an order demanding more USDC than the router holds
        AdumbraRouter.SwapOrder memory order = AdumbraRouter.SwapOrder({
            user: user,
            tokenIn: address(fXRP),
            tokenOut: address(usdc),
            amountIn: amountIn,
            minAmountOut: 999_999 ether, // exceeds router balance
            deadline: block.timestamp + 3600,
            orderNonce: router.nonce()
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(enclavePriv, _digest(order));
        AdumbraRouter.SignedOrder memory so =
            AdumbraRouter.SignedOrder(order, abi.encodePacked(r, s, v));

        vm.prank(user);
        vm.expectRevert(AdumbraRouter.SlippageExceeded.selector);
        router.executeSwap(so);
    }
}
