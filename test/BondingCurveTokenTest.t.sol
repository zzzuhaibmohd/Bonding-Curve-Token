// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/BondingCurveToken.sol";
import "forge-std/console2.sol";

contract BondingCurveTokenTest is Test {
    BondingCurveToken token;
    address owner = makeAddr("owner");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address carol = makeAddr("carol");
    address dave = makeAddr("dave");
    address eve = makeAddr("eve");

    function setUp() public {
        vm.prank(owner);
        token = new BondingCurveToken("LolCoin", "LOL");
        vm.deal(owner, 5000 ether);
        vm.deal(alice, 5000 ether);
        vm.deal(bob, 5000 ether);
        vm.deal(carol, 5000 ether);
        vm.deal(dave, 5000 ether);
        vm.deal(eve, 5000 ether);

        _buyTokens(owner, 1000 ether);
    }

    function test_PriceIncreaseOnBuy() public {
        uint256 priceBefore = token.calculatePrice(token.totalSupply());

        _buyTokens(alice, 2000 ether);
        _buyTokens(bob, 2000 ether);

        uint256 priceAfter = token.calculatePrice(token.totalSupply());

        assertGt(priceAfter, priceBefore, "Price should increase");
        assertGt(token.balanceOf(alice), token.balanceOf(bob), "Later buyers should get fewer tokens");
    }

    function test_SellTokensInProfit() public {
        _buyTokens(alice, 500 ether);
        _buyTokens(bob, 500 ether);

        uint256 aliceBalance = token.balanceOf(alice);
        vm.prank(alice);
        uint256 etherReturned = token.sell(aliceBalance);
        assertGt(etherReturned, 500 ether, "Should receive more than 500 ether");
    }

    function test_FailBuyAndSellAfterMax() public {
        _buyTokens(alice, 5000 ether);
        _buyTokens(bob, 5000 ether);

        vm.expectRevert(BondingCurveToken.BondingCurveToken__CurveIsClosed.selector);
        vm.prank(carol);
        token.buy{value: 100 ether}();

        uint256 aliceBalance = token.balanceOf(alice);
        vm.expectRevert(BondingCurveToken.BondingCurveToken__CurveIsClosed.selector);
        _sellTokens(alice, aliceBalance);
    }

    function test_BuyZeroTokensFails() public {
        vm.expectRevert(BondingCurveToken.BondingCurveToken__EthAmountMustBeGreaterThanZero.selector);
        _buyTokens(alice, 0 ether);
    }

    function test_SellZeroTokensFails() public {
        vm.expectRevert(BondingCurveToken.BondingCurveToken__AmountMustBeGreaterThanZero.selector);
        _sellTokens(alice, 0);
    }

    function test_SellMoreThanBalanceFails() public {
        _buyTokens(alice, 1000 ether);

        uint256 aliceBalance = token.balanceOf(alice) + 1;
        vm.expectRevert(BondingCurveToken.BondingCurveToken__InsufficientBalance.selector);
        _sellTokens(alice, aliceBalance);
    }

    function test_WithdrawEtherFailsIfCurveIsNotClosed() public {
        vm.prank(owner);
        vm.expectRevert(BondingCurveToken.BondingCurveToken__CurveIsNotClosed.selector);
        token.withdrawEther();
    }

    function test_WithdrawEther() public {
        _buyTokens(alice, 5000 ether);
        _buyTokens(bob, 5000 ether);

        uint256 balanceBefore = address(owner).balance;
        vm.prank(owner);
        token.withdrawEther();
        uint256 balanceAfter = address(owner).balance;
        assertEq(balanceAfter, balanceBefore + token.MAX_ETH_SUPPLY(), "Owner should have 10000 ether");
    }

    function testFuzz_PriceAlwaysIncreases(uint256 amount0, uint256 amount1) public {
        amount0 = bound(amount0, 500 ether, 5000 ether);

        uint256 priceOne = token.calculatePrice(token.totalSupply());
        _buyTokens(alice, amount0);

        uint256 priceTwo = token.calculatePrice(token.totalSupply());
        assertGt(priceTwo, priceOne, "Price should increase");
    }

    function testFuzz_BuyAndSellTokens(uint256 buyAmount, uint256 sellPercentage) public {
        // Bound buy amount to reasonable values
        buyAmount = bound(buyAmount, 0.01 ether, 1000 ether);
        // Bound sell percentage to 1-100%
        sellPercentage = bound(sellPercentage, 1, 100);

        uint256 tokensBought = _buyTokens(alice, buyAmount);

        assertGt(tokensBought, 0, "Should receive tokens");

        // Calculate tokens to sell based on percentage
        uint256 tokensToSell = (tokensBought * sellPercentage) / 100;
        if (tokensToSell == 0) tokensToSell = 1; // Ensure at least 1 token is sold

        uint256 etherReturned = _sellTokens(alice, tokensToSell);

        assertGt(etherReturned, 0, "Should receive ether");
        assertEq(token.balanceOf(alice), tokensBought - tokensToSell, "User should have fewer tokens");
    }

    function testFuzz_MultipleBuyers(uint256[] calldata amounts) public {
        vm.assume(amounts.length > 0 && amounts.length <= 5);

        address[] memory buyers = new address[](5);
        buyers[0] = alice;
        buyers[1] = bob;
        buyers[2] = carol;
        buyers[3] = makeAddr("dave");
        buyers[4] = makeAddr("eve");

        vm.deal(buyers[3], 5000 ether);
        vm.deal(buyers[4], 5000 ether);

        uint256 previousPrice = token.calculatePrice(token.totalSupply());

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amount = bound(amounts[i], 0.01 ether, 500 ether);

            // Skip if curve is closed
            if (token.isCurveClosed()) break;

            _buyTokens(buyers[i], amount);

            uint256 currentPrice = token.calculatePrice(token.totalSupply());
            assertGe(currentPrice, previousPrice, "Price should never decrease");
            previousPrice = currentPrice;
        }
    }

    function testFuzz_MaxEthSupply(uint256[] calldata amounts) public {
        vm.assume(amounts.length > 0 && amounts.length <= 3);

        address[] memory buyers = new address[](3);
        buyers[0] = alice;
        buyers[1] = bob;
        buyers[2] = carol;

        uint256 totalEth = 0;

        for (uint256 i = 0; i < amounts.length; i++) {
            // Make sure we can potentially reach MAX_ETH_SUPPLY
            uint256 amount = bound(amounts[i], 3334 ether, 4999 ether);

            // Skip if curve is already closed
            if (token.isCurveClosed()) break;

            _buyTokens(buyers[i], amount);

            totalEth += amount;
        }

        if (totalEth >= token.MAX_ETH_SUPPLY()) {
            assertTrue(token.isCurveClosed(), "Curve should be closed when MAX_ETH_SUPPLY is reached");

            vm.expectRevert(BondingCurveToken.BondingCurveToken__CurveIsClosed.selector);
            _buyTokens(alice, address(alice).balance);

            // Test owner can withdraw
            uint256 ownerBalanceBefore = address(owner).balance;
            vm.prank(owner);
            token.withdrawEther();
            uint256 ownerBalanceAfter = address(owner).balance;

            assertEq(
                ownerBalanceAfter, ownerBalanceBefore + token.MAX_ETH_SUPPLY(), "Owner should receive MAX_ETH_SUPPLY"
            );
        }
    }

    receive() external payable {}

    // Helper functions
    function _buyTokens(address buyer, uint256 amount) internal returns (uint256) {
        vm.prank(buyer);
        uint256 tokensBought = token.buy{value: amount}();
        return tokensBought;
    }

    function _sellTokens(address seller, uint256 amount) internal returns (uint256) {
        vm.prank(seller);
        uint256 etherReturned = token.sell(amount);
        return etherReturned;
    }
}
