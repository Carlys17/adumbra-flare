// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AdumbraRouter.sol";
import "../src/mocks/MockERC20.sol";

contract AdumbraRouterTest is Test {
    AdumbraRouter router;
    MockERC20 fXRP;
    MockERC20 usdc;

    uint256 enclavePriv = 0xabcd;
    address enclavePub;

    address user = address(0xBEEF);
    uint256 amountIn = 100 ether;

    function setUp() public {
        enclavePub = vm.addr(enclavePriv);
        fXRP = new MockERC20("Fake XRP", "FXRP", 1_000_000 ether);
        usdc = new MockERC20("Fake USDC", "USDC", 1_000_000 ether);

        router = new AdumbraRouter(enclavePub, address(this));

        fXRP.transfer(user, amountIn);
        vm.prank(user);
        fXRP.approve(address(router), amountIn);

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
            minAmountOut: 1 ether,
            deadline: block.timestamp + 3600,
            orderNonce: router.userNonces(user)
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

    function testHappyPath_Relayer() public {
        (AdumbraRouter.SignedOrder memory so, ) = _makeOrder();
        address relayer = address(0xCAFE);

        // Anyone can submit — order is bound to user, not msg.sender
        vm.prank(relayer);
        uint256 amountOut = router.executeSwap(so);
        assertEq(amountOut, so.order.minAmountOut);
    }

    function testRevertExpired() public {
        (AdumbraRouter.SignedOrder memory so, ) = _makeOrder();
        vm.warp(block.timestamp + 4000);
        vm.prank(user);
        vm.expectRevert(AdumbraRouter.Expired.selector);
        router.executeSwap(so);
    }

    function testRevertWrongSigner() public {
        (AdumbraRouter.SignedOrder memory so, ) = _makeOrder();
        bytes32 digest = _digest(so.order);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x1234, digest);
        so.signature = abi.encodePacked(r, s, v);
        vm.prank(user);
        vm.expectRevert(AdumbraRouter.UnauthorizedSigner.selector);
        router.executeSwap(so);
    }

    function testRevertTamperedOrder() public {
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
        vm.prank(user);
        vm.expectRevert(AdumbraRouter.Replay.selector);
        router.executeSwap(so);
    }

    function testRevertSlippage() public {
        AdumbraRouter.SwapOrder memory order = AdumbraRouter.SwapOrder({
            user: user,
            tokenIn: address(fXRP),
            tokenOut: address(usdc),
            amountIn: amountIn,
            minAmountOut: 999_999 ether,
            deadline: block.timestamp + 3600,
            orderNonce: router.userNonces(user)
        });
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(enclavePriv, _digest(order));
        AdumbraRouter.SignedOrder memory so =
            AdumbraRouter.SignedOrder(order, abi.encodePacked(r, s, v));

        vm.prank(user);
        vm.expectRevert(AdumbraRouter.SlippageExceeded.selector);
        router.executeSwap(so);
    }

    function testPerUserNonces() public {
        address user2 = address(0x1234);
        fXRP.transfer(user2, amountIn);
        vm.prank(user2);
        fXRP.approve(address(router), amountIn);

        // User 1 executes — their nonce goes 0 → 1
        (AdumbraRouter.SignedOrder memory so1, ) = _makeOrder();
        vm.prank(user1());
        router.executeSwap(so1);
        assertEq(router.userNonces(user), 1);
        assertEq(router.userNonces(user2), 0); // user2 untouched
    }

    function testFuzz_RevertTamperedAmount(uint256 tamperAmount) public {
        (AdumbraRouter.SignedOrder memory so, ) = _makeOrder();
        so.order.amountIn = amountIn + tamperAmount;
        vm.prank(user);
        vm.expectRevert(AdumbraRouter.UnauthorizedSigner.selector);
        router.executeSwap(so);
    }

    function testFuzz_RevertTamperedUser(address fuzzUser) public {
        (AdumbraRouter.SignedOrder memory so, ) = _makeOrder();
        so.order.user = fuzzUser;
        vm.prank(user);
        vm.expectRevert(AdumbraRouter.UnauthorizedSigner.selector);
        router.executeSwap(so);
    }

    function testFuzz_RevertTamperedTokenIn(address fuzzToken) public {
        (AdumbraRouter.SignedOrder memory so, ) = _makeOrder();
        so.order.tokenIn = fuzzToken;
        vm.prank(user);
        vm.expectRevert(AdumbraRouter.UnauthorizedSigner.selector);
        router.executeSwap(so);
    }

    function testFuzz_RevertTamperedMinOut(uint256 fuzzMinOut) public {
        (AdumbraRouter.SignedOrder memory so, ) = _makeOrder();
        so.order.minAmountOut = fuzzMinOut;
        vm.prank(user);
        vm.expectRevert(AdumbraRouter.UnauthorizedSigner.selector);
        router.executeSwap(so);
    }

    function testRescue_AsOwner() public {
        uint256 balBefore = fXRP.balanceOf(address(this));
        router.rescue(address(fXRP), 1 ether);
        assertEq(fXRP.balanceOf(address(this)), balBefore + 1 ether);
    }

    function testRevertRescue_NotOwner() public {
        vm.prank(user);
        vm.expectRevert("not owner");
        router.rescue(address(fXRP), 1 ether);
    }

    function testRenounceOwnership() public {
        router.renounceOwnership();
        assertEq(router.owner(), address(0));
        vm.expectRevert("not owner");
        router.rescue(address(fXRP), 1 ether);
    }

    function user1() internal view returns (address) {
        return user;
    }
}