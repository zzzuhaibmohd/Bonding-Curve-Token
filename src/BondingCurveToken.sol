// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BondingCurveToken is ERC20, Ownable {
    // Custom errors
    error BondingCurveToken__EthAmountMustBeGreaterThanZero();
    error BondingCurveToken__NoTokensToMint();
    error BondingCurveToken__CurveIsClosed();
    error BondingCurveToken__MaxEthSupplyReached();
    error BondingCurveToken__AmountMustBeGreaterThanZero();
    error BondingCurveToken__InsufficientBalance();
    error BondingCurveToken__FailedToSendEther();
    error BondingCurveToken__CurveIsNotClosed();

    // @note: helps maintain precision in the price calculation
    uint256 public constant PRICE_SCALE = 1 ether;

    //@note: used to normalize the supply and reserve
    uint256 public constant SUPPLY_SCALE = 1 ether;

    // @note: This is the parameter that controls the steepness of the curve.
    // @note: A higher value results in a steeper curve, meaning the price increases more rapidly as supply increases.
    uint256 public constant CURVE_PARAMETER = 1;

    uint256 public constant MAX_ETH_SUPPLY = 10000 ether;
    bool public isCurveClosed = false;
    uint256 public totalEtherCollected = 0;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) Ownable(msg.sender) {}

    function calculatePrice(uint256 supply) public view returns (uint256) {
        return (CURVE_PARAMETER * (supply / SUPPLY_SCALE) * (supply / SUPPLY_SCALE) * PRICE_SCALE);
    }

    function calculateTokens(uint256 ethAmount, uint256 currentSupply)
        internal
        view
        returns (uint256 tokensToMint, uint256 totalCost)
    {
        uint256 newSupply = currentSupply;
        totalCost = 0;
        tokensToMint = 0;

        while (totalCost < ethAmount) {
            uint256 nextPrice = calculatePrice(newSupply);
            if (totalCost + nextPrice > ethAmount) {
                uint256 remainingEth = ethAmount - totalCost;
                tokensToMint += (remainingEth * SUPPLY_SCALE) / nextPrice;
                totalCost = ethAmount;
                break;
            } else {
                totalCost += nextPrice;
                newSupply += SUPPLY_SCALE;
                tokensToMint += SUPPLY_SCALE;
            }
        }
    }

    function calculatePurchaseReturn(uint256 ethAmount) public view returns (uint256) {
        (uint256 tokensToMint,) = calculateTokens(ethAmount, totalSupply());
        return tokensToMint;
    }

    function calculateEth(uint256 amount, uint256 currentSupply)
        internal
        view
        returns (uint256 ethToReturn, uint256 tokensBurned)
    {
        ethToReturn = 0;
        tokensBurned = 0;

        while (tokensBurned < amount) {
            uint256 currentPrice = calculatePrice(currentSupply - tokensBurned);
            if (tokensBurned + SUPPLY_SCALE > amount) {
                uint256 remainingTokens = amount - tokensBurned;
                ethToReturn += (remainingTokens * currentPrice) / SUPPLY_SCALE;
                tokensBurned += remainingTokens;
            } else {
                ethToReturn += currentPrice;
                tokensBurned += SUPPLY_SCALE;
            }
        }
    }

    function buy() public payable returns (uint256) {
        if (msg.value <= 0) revert BondingCurveToken__EthAmountMustBeGreaterThanZero();
        if (isCurveClosed) revert BondingCurveToken__CurveIsClosed();

        uint256 tokensToMint = calculatePurchaseReturn(msg.value);
        if (tokensToMint <= 0) revert BondingCurveToken__NoTokensToMint();

        uint256 etherCollected = totalEtherCollected + msg.value;
        uint256 etherToReturn = 0;

        if (etherCollected > MAX_ETH_SUPPLY) {
            etherToReturn = etherCollected - MAX_ETH_SUPPLY;
            (bool success,) = payable(msg.sender).call{value: etherToReturn}("");
            if (!success) revert BondingCurveToken__FailedToSendEther();

            totalEtherCollected = MAX_ETH_SUPPLY;
            isCurveClosed = true;
        } else {
            totalEtherCollected = etherCollected;
            if (totalEtherCollected == MAX_ETH_SUPPLY) {
                isCurveClosed = true;
            }
        }

        _mint(msg.sender, tokensToMint);
        return tokensToMint;
    }

    function sell(uint256 amount) public returns (uint256) {
        if (amount <= 0) revert BondingCurveToken__AmountMustBeGreaterThanZero();
        if (balanceOf(msg.sender) < amount) revert BondingCurveToken__InsufficientBalance();
        if (isCurveClosed) revert BondingCurveToken__CurveIsClosed();

        (uint256 ethToReturn,) = calculateEth(amount, totalSupply());
        _burn(msg.sender, amount);
        (bool success,) = payable(msg.sender).call{value: ethToReturn}("");
        if (!success) revert BondingCurveToken__FailedToSendEther();
        return ethToReturn;
    }

    function withdrawEther() public onlyOwner {
        if (!isCurveClosed) revert BondingCurveToken__CurveIsNotClosed();
        totalEtherCollected = 0;
        (bool success,) = payable(owner()).call{value: address(this).balance}("");
        if (!success) revert BondingCurveToken__FailedToSendEther();
    }
}
