// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IAOM3RewardDistributor {
    function notifyRewardAmount(uint256 amount) external;
}

contract AOM3Strategy is Ownable {
    address public immutable usdc;
    address public rewardDistributor;

    constructor(address _usdc) Ownable(msg.sender) {
        usdc = _usdc;
    }

    function setRewardDistributor(address _distributor) external onlyOwner {
        rewardDistributor = _distributor;
    }

    function deposit(uint256 amount) external {
        IERC20(usdc).transferFrom(msg.sender, address(this), amount);
    }

    function redeemWithFee(uint256 totalAmount, uint256 feeAmount, address to) external {
        uint256 netAmount = totalAmount - feeAmount;

        if (feeAmount > 0 && rewardDistributor != address(0)) {
            IERC20(usdc).approve(rewardDistributor, feeAmount);
            IAOM3RewardDistributor(rewardDistributor).notifyRewardAmount(feeAmount);
        }

        IERC20(usdc).transfer(to, netAmount);
    }
}