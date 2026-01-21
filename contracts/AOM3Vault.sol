// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title AOM3Vault
 * @notice Protocol for disciplined savings with delta-neutral yield strategies.
 */
contract AOM3Vault is Ownable, ReentrancyGuard {
    IERC20 public usdc;
    address public yieldStrategy; // Address ของ Liminal Vault

    struct QuestPlan {
        address owner;
        uint256 monthlyAmount;
        uint256 totalDeposited;
        uint256 currentStreak;
        uint256 durationMonths;
        uint256 startTimestamp;
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

    /**
     * @dev ตรวจสอบว่าปัจจุบันอยู่ในช่วง 1-7 วันแรกของเดือน (UTC) หรือไม่.
     */
    function isInsideWindow() public view returns (bool) {
        uint256 day = (block.timestamp / 86400) % 31; 
        return (day >= 0 && day < 7); 
    }

    /**
     * @dev สร้างภารกิจการออมใหม่ เลือกได้ 6, 12, หรือ 24 เดือน.
     */
    function createQuest(uint256 _monthlyAmount, uint256 _durationMonths) external {
        require(_durationMonths == 6 || _durationMonths == 12 || _durationMonths == 24, "Invalid duration");
        
        uint256 questId = nextQuestId++;
        quests[questId] = QuestPlan({
            owner: msg.sender,
            monthlyAmount: _monthlyAmount,
            totalDeposited: 0,
            currentStreak: 0,
            durationMonths: _durationMonths,
            startTimestamp: block.timestamp,
            active: true
        });

        emit QuestCreated(questId, msg.sender, _monthlyAmount);
    }

    /**
     * @dev ฝากเงินประจำเดือน หากอยู่นอกหน้าต่าง Streak จะถูกรีเซ็ตและ Yield จะถูกริบ.
     */
    function deposit(uint256 _questId) external nonReentrant {
        QuestPlan storage quest = quests[_questId];
        require(quest.active, "Quest not active");
        require(msg.sender == quest.owner, "Not owner");

        uint256 amount = quest.monthlyAmount;
        require(usdc.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        bool inWindow = isInsideWindow();
        
        if (inWindow) {
            quest.currentStreak++; // เพิ่ม Streak เพื่อรับ PrizePoolBonus
        } else {
            quest.currentStreak = 0; // รีเซ็ต Streak หากผิดนัด
        }

        quest.totalDeposited += amount;
        
        // ส่งเงินไปยังกลยุทธ์ Delta-Neutral Hedge
        usdc.approve(yieldStrategy, amount);
        
        emit DepositExecuted(_questId, amount, inWindow);
    }

    /**
     * @dev ถอนเงินต้นคืนเมื่อภารกิจครบกำหนด.
     */
    function withdraw(uint256 _questId) external nonReentrant {
        QuestPlan storage quest = quests[_questId];
        require(block.timestamp >= quest.startTimestamp + (quest.durationMonths * 30 days), "Not matured");
        
        uint256 amount = quest.totalDeposited;
        quest.active = false;
        
        require(usdc.transfer(msg.sender, amount), "Transfer failed");
        emit WithdrawalExecuted(_questId, amount);
    }
}