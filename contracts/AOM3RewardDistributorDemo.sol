// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IAOM3Vault {
    function totalDisciplinePoints() external view returns (uint256);
    function quests(uint256 id) external view returns (
        address owner, uint256 monthlyAmount, uint256 totalDeposited,
        uint256 currentStreak, uint256 durationMonths, uint256 startTimestamp,
        uint256 lastDepositTimestamp, uint256 dp, bool active
    );
    function burnQuestDP(uint256 _questId) external; 
}

contract AOM3RewardDistributorDemo is Ownable, ReentrancyGuard {
    IERC20 public usdc;
    IAOM3Vault public vault;

    event RewardReceived(address indexed from, uint256 amount);
    event RewardClaimed(uint256 indexed questId, address indexed to, uint256 amount);

    constructor(address _usdc, address _vault) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        vault = IAOM3Vault(_vault);
    }

    function notifyRewardAmount(uint256 amount) external {
        require(usdc.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        emit RewardReceived(msg.sender, amount);
    }

    function claimReward(uint256 _questId) external nonReentrant {
        (address owner,,,,,,, uint256 userDP, ) = vault.quests(_questId);
        
        require(msg.sender == owner, "Not quest owner");
        require(userDP > 0, "No Active DP to claim");

        uint256 totalDP = vault.totalDisciplinePoints();
        require(totalDP > 0, "No DP in system");

        uint256 currentPoolBalance = usdc.balanceOf(address(this));
        require(currentPoolBalance > 0, "Reward pool is empty");

        uint256 rewardAmount = (currentPoolBalance * userDP) / totalDP;
        require(rewardAmount > 0, "No rewards available for your DP share");

        vault.burnQuestDP(_questId);

        require(usdc.transfer(owner, rewardAmount), "Reward transfer failed");

        emit RewardClaimed(_questId, owner, rewardAmount);
    }
}