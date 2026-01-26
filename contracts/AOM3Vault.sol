// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface ILiminalVault {
    function deposit(uint256 amount) external;
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
        bool active;
    }

    mapping(uint256 => QuestPlan) public quests;
    uint256 public nextQuestId;

    event QuestCreated(uint256 indexed questId, address indexed owner, uint256 amount);
    event DepositExecuted(uint256 indexed questId, uint256 amount, bool insideWindow);
    event WithdrawalExecuted(uint256 indexed questId, uint256 amount);

    constructor(address _usdc, address _yieldStrategy) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        yieldStrategy = _yieldStrategy;
    }

    function getDayOfMonth(uint256 timestamp) public pure returns (uint256) {
        uint256 secondsInDay = 86400;
        uint256 daysSinceEpoch = timestamp / secondsInDay;
        return ((daysSinceEpoch + 3) % 31) + 1; 
    }

    function isInsideWindow() public view returns (bool) {
        uint256 day = getDayOfMonth(block.timestamp);
        return (day >= 1 && day <= 7); 
    }

    function createQuest(uint256 _monthlyAmount, uint256 _durationMonths) external nonReentrant {
        require(_durationMonths == 6 || _durationMonths == 12 || _durationMonths == 24, "Invalid duration");
        require(_monthlyAmount > 0, "Amount must be > 0");
        require(usdc.transferFrom(msg.sender, address(this), _monthlyAmount), "First deposit failed");

        uint256 questId = nextQuestId++;
        quests[questId] = QuestPlan({
            owner: msg.sender,
            monthlyAmount: _monthlyAmount,
            totalDeposited: _monthlyAmount,
            currentStreak: 1,
            durationMonths: _durationMonths,
            startTimestamp: block.timestamp,
            lastDepositTimestamp: block.timestamp,
            active: true
        });

        _forwardToStrategy(_monthlyAmount);

        emit QuestCreated(questId, msg.sender, _monthlyAmount);
    }

    function deposit(uint256 _questId) external nonReentrant {
        QuestPlan storage quest = quests[_questId];
        require(quest.active, "Quest not active");
        require(msg.sender == quest.owner, "Not owner");
        require(block.timestamp > quest.lastDepositTimestamp + 20 days, "Too soon for next deposit");

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
        ILiminalVault(yieldStrategy).deposit(_amount);
    }

    function withdraw(uint256 _questId) external nonReentrant {
        QuestPlan storage quest = quests[_questId];
        require(block.timestamp >= quest.startTimestamp + (quest.durationMonths * 30 days), "Not matured");
        require(msg.sender == quest.owner, "Not owner");

        uint256 amount = quest.totalDeposited;
        quest.active = false;
        
        require(usdc.transfer(msg.sender, amount), "Transfer failed");
        emit WithdrawalExecuted(_questId, amount);
    }
}