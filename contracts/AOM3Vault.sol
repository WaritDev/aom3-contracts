// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

struct Signature {
    uint256 r;
    uint256 s;
    uint8 v;
}

struct DepositWithPermit {
    address user;
    uint64 usd;
    uint64 deadline;
    Signature signature;
}

interface IHyperliquidBridge {
    function batchedDepositWithPermit(DepositWithPermit[] calldata deposits) external;
}

interface IAOM3Ranking {
    function registerNewQuest(address _user, uint256 _dp, uint256 _months) external;
    function reduceActiveDP(address _user, uint256 _dp) external;
}

contract AOM3Vault is Ownable, ReentrancyGuard {
    IAOM3Ranking public ranking;
    address public immutable usdc;
    IHyperliquidBridge public immutable bridge;

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
    // ✅ เพิ่มการเก็บยอดเงินสะสมรายคน เพื่อให้ Frontend อ่านค่า virtualBalance ได้ทันที
    mapping(address => uint256) public userBalance; 

    uint256 public nextQuestId;
    uint256 public totalDisciplinePoints;
    uint256 private constant SECONDS_PER_MONTH = 2629743;

    event QuestCreated(uint256 indexed questId, address indexed owner, uint256 amount, uint256 dp);
    event DepositSynced(uint256 indexed questId, uint256 amount, uint256 bonusDP);
    event WithdrawalClosed(uint256 indexed questId, uint256 amount, uint256 dpSubtracted);

    constructor(address _ranking, address _usdc, address _bridge) Ownable(msg.sender) {
        ranking = IAOM3Ranking(_ranking);
        usdc = _usdc;
        bridge = IHyperliquidBridge(_bridge);
    }

    function getMultiplier(uint256 _months) public pure returns (uint256) {
        if (_months == 3) return 100; 
        if (_months == 6) return 120;
        if (_months == 12) return 150;
        if (_months == 18) return 180;
        if (_months == 24) return 200;
        revert("Invalid duration");
    }

    function isInsideWindow() public view returns (bool) {
        uint256 day = ((block.timestamp / 86400 + 3) % 31) + 1;
        return (day >= 1 && day <= 7); 
    }

    function createQuestWithPermit(
        uint64 _monthlyAmount, 
        uint256 _durationMonths,
        uint64 _deadline,
        uint8 v, bytes32 r, bytes32 s
    ) external nonReentrant {
        require(_monthlyAmount > 0, "Amount must be > 0");

        DepositWithPermit[] memory deposits = new DepositWithPermit[](1);
        deposits[0] = DepositWithPermit({
            user: msg.sender,
            usd: _monthlyAmount,
            deadline: _deadline,
            signature: Signature({ r: uint256(r), s: uint256(s), v: v })
        });

        bridge.batchedDepositWithPermit(deposits);
        uint256 multiplier = getMultiplier(_durationMonths);
        uint256 questDP = (uint256(_monthlyAmount) * _durationMonths * multiplier) / (100 * 1e6);

        uint256 questId = nextQuestId++;
        quests[questId] = QuestPlan({
            owner: msg.sender,
            monthlyAmount: uint256(_monthlyAmount),
            totalDeposited: uint256(_monthlyAmount),
            currentStreak: 1,
            durationMonths: _durationMonths,
            startTimestamp: block.timestamp,
            lastDepositTimestamp: block.timestamp,
            dp: questDP,
            active: true
        });

        userBalance[msg.sender] += uint256(_monthlyAmount);
        totalDisciplinePoints += questDP;
        ranking.registerNewQuest(msg.sender, questDP, _durationMonths);

        emit QuestCreated(questId, msg.sender, uint256(_monthlyAmount), questDP);
    }

    function depositWithPermit(
        uint256 _questId,
        uint64 _deadline,
        uint8 v, bytes32 r, bytes32 s
    ) external nonReentrant {
        QuestPlan storage quest = quests[_questId];
        require(quest.active, "Quest not active");
        require(msg.sender == quest.owner, "Not owner");
        require(isInsideWindow(), "Not in window");
        require((block.timestamp / SECONDS_PER_MONTH) > (quest.lastDepositTimestamp / SECONDS_PER_MONTH), "Already synced");
        uint64 amountToDeposit = uint64(quest.monthlyAmount);

        DepositWithPermit[] memory deposits = new DepositWithPermit[](1);
        deposits[0] = DepositWithPermit({
            user: msg.sender,
            usd: amountToDeposit,
            deadline: _deadline,
            signature: Signature({ r: uint256(r), s: uint256(s), v: v })
        });
        bridge.batchedDepositWithPermit(deposits);

        quest.currentStreak++;
        uint256 bonusDP = (quest.monthlyAmount * getMultiplier(quest.durationMonths)) / (100 * 1e6);
        
        quest.dp += bonusDP;
        totalDisciplinePoints += bonusDP;
        userBalance[msg.sender] += uint256(amountToDeposit);
        ranking.registerNewQuest(msg.sender, bonusDP, 0);

        quest.totalDeposited += quest.monthlyAmount;
        quest.lastDepositTimestamp = block.timestamp;

        emit DepositSynced(_questId, quest.monthlyAmount, bonusDP);
    }

    function withdraw(uint256 _questId) external nonReentrant {
        QuestPlan storage quest = quests[_questId];
        require(msg.sender == quest.owner, "Not owner");
        require(quest.active, "Quest not active");

        totalDisciplinePoints -= quest.dp;
        ranking.reduceActiveDP(msg.sender, quest.dp);
        userBalance[msg.sender] -= quest.totalDeposited;

        quest.active = false;
        emit WithdrawalClosed(_questId, quest.totalDeposited, quest.dp);
    }
}