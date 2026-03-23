// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol"; 

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

contract AOM3VaultDemo is Ownable, ReentrancyGuard {
    IAOM3Ranking public ranking;
    address public immutable usdc;
    IHyperliquidBridge public immutable bridge;
    address public rewardDistributor;

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
    mapping(address => uint256) public userBalance; 

    uint256 public nextQuestId;
    uint256 public totalDisciplinePoints;
    uint256 private constant SECONDS_PER_MONTH = 2592000; 

    event QuestCreated(uint256 indexed questId, address indexed owner, uint256 amount, uint256 dp);
    event DepositSynced(uint256 indexed questId, uint256 amount, uint256 bonusDP);
    event WithdrawalClosed(uint256 indexed questId, uint256 amount, uint256 dpSubtracted);
    event QuestDPBurned(uint256 indexed questId, address indexed owner, uint256 dpBurned);

    constructor(address _ranking, address _usdc, address _bridge) Ownable(msg.sender) {
        ranking = IAOM3Ranking(_ranking);
        usdc = _usdc;
        bridge = IHyperliquidBridge(_bridge);
    }

    function setRewardDistributor(address _distributor) external onlyOwner {
        require(_distributor != address(0), "Invalid address");
        rewardDistributor = _distributor;
    }

    function getMultiplier(uint256 _months) public pure returns (uint256) {
        if (_months == 3) return 100; 
        if (_months == 6) return 120;
        if (_months == 12) return 150;
        if (_months == 18) return 180;
        if (_months == 24) return 200;
        revert("Invalid duration");
    }

    function calculateMonthlyDP(uint256 _amount, uint256 _duration, uint256 _streak) public pure returns (uint256) {
        uint256 planMultiplier = getMultiplier(_duration); 
        uint256 streakMultiplier = 100 + (_streak * 10);
        return (_amount * planMultiplier * streakMultiplier) / (10000 * 1e6);
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
        uint256 questDP = calculateMonthlyDP(uint256(_monthlyAmount), _durationMonths, 1);

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
        uint256 bonusDP = calculateMonthlyDP(quest.monthlyAmount, quest.durationMonths, quest.currentStreak);
        
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
        require(quest.totalDeposited > 0, "Already withdrawn");
        uint256 totalAmount = quest.totalDeposited;
        uint256 totalDurationSec = quest.durationMonths * SECONDS_PER_MONTH;
        uint256 maturityDate = quest.startTimestamp + totalDurationSec;
        
        require(IERC20(usdc).transferFrom(msg.sender, address(this), totalAmount), "Transfer from user failed");
        bool isMaturedByTime = block.timestamp >= maturityDate;
        bool isMaturedByStreak = quest.currentStreak >= quest.durationMonths;

        if (!isMaturedByTime && !isMaturedByStreak) {
            uint256 remainingSec = maturityDate - block.timestamp;
            uint256 penaltyBps = 100 + ((remainingSec * 200) / totalDurationSec);
            uint256 penalty = (totalAmount * penaltyBps) / 10000;
            uint256 userReturn = totalAmount - penalty;

            require(IERC20(usdc).transfer(rewardDistributor, penalty), "Penalty transfer failed");
            require(IERC20(usdc).transfer(msg.sender, userReturn), "User transfer failed");

            uint256 burnedDP = quest.dp;
            totalDisciplinePoints -= burnedDP;
            ranking.reduceActiveDP(msg.sender, burnedDP);
            quest.dp = 0;
            quest.active = false;
            
            emit WithdrawalClosed(_questId, totalAmount, burnedDP);
        } else {
            require(IERC20(usdc).transfer(msg.sender, totalAmount), "Full transfer failed");
            emit WithdrawalClosed(_questId, totalAmount, 0);
        }

        userBalance[msg.sender] -= totalAmount;
        quest.totalDeposited = 0;
    }

    function getQuestDP(uint256 _questId) external view returns (uint256) {
        return quests[_questId].dp;
    }

    function burnQuestDP(uint256 _questId) external {
        require(msg.sender == rewardDistributor, "Only distributor can burn DP");
        QuestPlan storage quest = quests[_questId];
        
        uint256 dpToBurn = quest.dp;
        require(dpToBurn > 0, "No DP to burn");

        totalDisciplinePoints -= dpToBurn;
        ranking.reduceActiveDP(quest.owner, dpToBurn);
        quest.dp = 0;

        emit QuestDPBurned(_questId, quest.owner, dpToBurn);
    }
}