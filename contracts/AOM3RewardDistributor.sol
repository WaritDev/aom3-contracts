// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AOM3RewardDistributor is Ownable {
    IERC20 public usdc;
    uint256 public totalRewardsCollected;

    event RewardReceived(address indexed from, uint256 amount);
    event RewardDistributed(address indexed to, uint256 amount);

    constructor(address _usdc) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
    }

    function notifyRewardAmount(uint256 amount) external {
        require(usdc.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        totalRewardsCollected += amount;
        emit RewardReceived(msg.sender, amount);
    }

    function distributeReward(address to, uint256 amount) external onlyOwner {
        require(amount <= usdc.balanceOf(address(this)), "Inadequate funds");
        usdc.transfer(to, amount);
        emit RewardDistributed(to, amount);
    }
}