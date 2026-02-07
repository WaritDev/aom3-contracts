// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IAOM3Strategy {
    function deposit(uint256 amount) external;
    function redeemWithFee(uint256 totalAmount, uint256 feeAmount, address to) external;
}

interface IAOM3Ranking {
    function registerNewQuest(address _user, uint256 _dp, uint256 _months) external;
    function reduceActiveDP(address _user, uint256 _dp) external;
}

contract AOM3Vault is Ownable, ReentrancyGuard {
    IERC20 public usdc;
    address public yieldStrategy; 
    IAOM3Ranking public ranking;

    struct QuestPlan {
        address owner;
        uint256 monthlyAmount;
        uint256 totalDeposited;
        uint256 currentStreak;
        uint256 durationMonths;
        uint256 startTimestamp;
        uint256 lastDepositTimestamp;
        uint256 dp;
        bool active;
    }

    mapping(uint256 => QuestPlan) public quests;
    uint256 public nextQuestId;
    uint256 public totalDisciplinePoints;
    uint256 private constant SECONDS_PER_MONTH = 2629743;

    event QuestCreated(uint256 indexed questId, address indexed owner, uint256 amount, uint256 dp);
    event DepositExecuted(uint256 indexed questId, uint256 amount, bool insideWindow, uint256 bonusDP);
    event WithdrawalExecuted(uint256 indexed questId, uint256 amount, uint256 dpSubtracted);

    constructor(address _usdc, address _yieldStrategy, address _ranking) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        yieldStrategy = _yieldStrategy;
        ranking = IAOM3Ranking(_ranking);
    }

    function getMultiplier(uint256 _months) public pure returns (uint256) {
        if (_months == 3) return 100; 
        if (_months == 6) return 120;
        if (_months == 12) return 150;
        if (_months == 18) return 180;
        if (_months == 24) return 200;
        revert("Invalid duration");
    }

    function getDayOfMonth(uint256 timestamp) public pure returns (uint256) {
        return ((timestamp / 86400 + 3) % 31) + 1; 
    }

    function isInsideWindow() public view returns (bool) {
        uint256 day = getDayOfMonth(block.timestamp);
        return (day >= 1 && day <= 7); 
    }

    function isNewMonth(uint256 _currentTimestamp, uint256 _lastTimestamp) public pure returns (bool) {
        if (_lastTimestamp == 0) return true;
        return (_currentTimestamp / SECONDS_PER_MONTH) > (_lastTimestamp / SECONDS_PER_MONTH);
    }

    function createQuest(uint256 _monthlyAmount, uint256 _durationMonths) external nonReentrant {
        uint256 multiplier = getMultiplier(_durationMonths);
        require(_monthlyAmount > 0, "Amount must be > 0");
        require(usdc.transferFrom(msg.sender, address(this), _monthlyAmount), "First deposit failed");
        uint256 questDP = (_monthlyAmount * _durationMonths * multiplier) / (100 * 1e6);

        uint256 questId = nextQuestId++;
        quests[questId] = QuestPlan({
            owner: msg.sender,
            monthlyAmount: _monthlyAmount,
            totalDeposited: _monthlyAmount,
            currentStreak: 1,
            durationMonths: _durationMonths,
            startTimestamp: block.timestamp,
            lastDepositTimestamp: block.timestamp,
            dp: questDP,
            active: true
        });

        totalDisciplinePoints += questDP;
        ranking.registerNewQuest(msg.sender, questDP, _durationMonths);

        _forwardToStrategy(_monthlyAmount);
        emit QuestCreated(questId, msg.sender, _monthlyAmount, questDP);
    }

    function deposit(uint256 _questId) external nonReentrant {
        QuestPlan storage quest = quests[_questId];
        require(quest.active, "Quest not active");
        require(msg.sender == quest.owner, "Not owner");
        require(isInsideWindow(), "Not in deposit window (Days 1-7)");
        require(isNewMonth(block.timestamp, quest.lastDepositTimestamp), "Already deposited this month");

        uint256 amount = quest.monthlyAmount;
        require(usdc.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        quest.currentStreak++;
        uint256 bonusDP = (amount * getMultiplier(quest.durationMonths)) / (100 * 1e6);
        
        quest.dp += bonusDP;
        totalDisciplinePoints += bonusDP;
        
        ranking.registerNewQuest(msg.sender, bonusDP, 0);

        quest.totalDeposited += amount;
        quest.lastDepositTimestamp = block.timestamp;

        _forwardToStrategy(amount);
        emit DepositExecuted(_questId, amount, true, bonusDP);
    }

    function _forwardToStrategy(uint256 _amount) internal {
        usdc.approve(yieldStrategy, _amount);
        IAOM3Strategy(yieldStrategy).deposit(_amount);
    }

    function withdraw(uint256 _questId) external nonReentrant {
        QuestPlan storage quest = quests[_questId];
        require(msg.sender == quest.owner, "Not owner");
        require(quest.active, "Quest not active");

        uint256 totalAmount = quest.totalDeposited;
        uint256 penaltyFee = 0;

        if (block.timestamp < quest.startTimestamp + (quest.durationMonths * 30 days)) {
            penaltyFee = (totalAmount * 10) / 100;
        }

        totalDisciplinePoints -= quest.dp;
        ranking.reduceActiveDP(msg.sender, quest.dp);

        quest.active = false;
        IAOM3Strategy(yieldStrategy).redeemWithFee(totalAmount, penaltyFee, msg.sender);
        emit WithdrawalExecuted(_questId, totalAmount - penaltyFee, quest.dp);
    }
}