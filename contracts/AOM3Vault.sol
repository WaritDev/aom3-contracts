// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
interface IAOM3Strategy {
    function deposit(uint256 amount) external;
    function redeemWithFee(uint256 totalAmount, uint256 feeAmount, address to) external;
}

contract AOM3Vault is Ownable, ReentrancyGuard {
    IERC20 public usdc;
    address public yieldStrategy; 

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

    event QuestCreated(uint256 indexed questId, address indexed owner, uint256 amount, uint256 dp);
    event DepositExecuted(uint256 indexed questId, uint256 amount, bool insideWindow);
    event WithdrawalExecuted(uint256 indexed questId, uint256 amount, uint256 dpSubtracted);

    constructor(address _usdc, address _yieldStrategy) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        yieldStrategy = _yieldStrategy;
    }

    function getMultiplier(uint256 _months) public pure returns (uint256) {
        if (_months == 3 || _months == 6) return 100;
        if (_months == 12) return 120;
        if (_months == 18) return 150;
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

    function createQuest(uint256 _monthlyAmount, uint256 _durationMonths) external nonReentrant {
        uint256 multiplier = getMultiplier(_durationMonths);
        require(_monthlyAmount > 0, "Amount must be > 0");
        require(usdc.transferFrom(msg.sender, address(this), _monthlyAmount), "First deposit failed");
        uint256 questDP = (_monthlyAmount * multiplier) / 100;

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

        _forwardToStrategy(_monthlyAmount);

        emit QuestCreated(questId, msg.sender, _monthlyAmount, questDP);
    }

    function deposit(uint256 _questId) external nonReentrant {
        QuestPlan storage quest = quests[_questId];
        require(quest.active, "Quest not active");
        require(msg.sender == quest.owner, "Not owner");
        require(block.timestamp > quest.lastDepositTimestamp + 20 days, "Too soon");

        uint256 amount = quest.monthlyAmount;
        require(usdc.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        bool inWindow = isInsideWindow();
        if (inWindow) {
            quest.currentStreak++;
        } else {
            quest.currentStreak = 0;
        }

        quest.totalDeposited += amount;
        quest.lastDepositTimestamp = block.timestamp;

        _forwardToStrategy(amount);
        
        emit DepositExecuted(_questId, amount, inWindow);
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
        quest.active = false;
        IAOM3Strategy(yieldStrategy).redeemWithFee(totalAmount, penaltyFee, msg.sender);
        emit WithdrawalExecuted(_questId, totalAmount - penaltyFee, quest.dp);
    }
}