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
}

contract AOM3RewardDistributor is Ownable, ReentrancyGuard {
    IERC20 public usdc;
    IAOM3Vault public vault;

    uint256 public lastSnapshotAmount;
    uint256 public lastSnapshotDay;

    // บันทึกว่า Quest ID นี้เบิกรางวัลของรอบวันนี้ไปหรือยัง
    mapping(uint256 => mapping(uint256 => bool)) public hasClaimed;

    event RewardReceived(address indexed from, uint256 amount);
    event RewardClaimed(uint256 indexed questId, address indexed to, uint256 amount);

    constructor(address _usdc, address _vault) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        vault = IAOM3Vault(_vault);
    }

    function getDayOfMonth() public view returns (uint256) {
        return ((block.timestamp / 86400 + 3) % 31) + 1;
    }

    function notifyRewardAmount(uint256 amount) external {
        require(usdc.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        emit RewardReceived(msg.sender, amount);
    }

    function claimReward(uint256 _questId) external nonReentrant {
        uint256 day = getDayOfMonth();
        require(day == 1 || day == 16, "Not a distribution day");

        uint256 epochDay = block.timestamp / 86400;
        require(!hasClaimed[_questId][epochDay], "Already claimed for this round");

        (address owner,,,,,,, uint256 userDP, bool active) = vault.quests(_questId);
        require(msg.sender == owner, "Not quest owner");
        require(active, "Quest must be active to earn rewards");

        if (epochDay > lastSnapshotDay) {
            lastSnapshotAmount = usdc.balanceOf(address(this));
            lastSnapshotDay = epochDay;
        }

        uint256 totalDP = vault.totalDisciplinePoints();
        require(totalDP > 0, "No DP in system");

        uint256 rewardAmount = (lastSnapshotAmount * userDP) / totalDP;
        require(rewardAmount > 0, "No rewards available for your DP share");

        hasClaimed[_questId][epochDay] = true;
        require(usdc.transfer(owner, rewardAmount), "Reward transfer failed");

        emit RewardClaimed(_questId, owner, rewardAmount);
    }
}