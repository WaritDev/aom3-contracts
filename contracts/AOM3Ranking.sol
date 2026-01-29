// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

contract AOM3Ranking is Ownable {
    struct UserStats {
        uint256 lifetimeDP; 
        uint256 currentActiveDP; 
        uint256 totalQuests;
        uint256 totalMonths;
    }

    address public vault;
    mapping(address => UserStats) public userStats;
    address[] public allParticipants;
    mapping(address => bool) private hasJoined;

    event RankUpdated(address indexed user, uint256 currentDP, uint256 lifetimeDP, uint256 totalMonths);
    event StatsDecreased(address indexed user, uint256 amountReduced, string reason);

    modifier onlyVault() {
        require(msg.sender == vault, "AOM3: Only Vault can update ranking");
        _;
    }

    constructor() Ownable(msg.sender) {}

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function registerNewQuest(address _user, uint256 _dp, uint256 _months) external onlyVault {
        UserStats storage stats = userStats[_user];
        
        stats.lifetimeDP += _dp;
        stats.currentActiveDP += _dp;
        stats.totalQuests += 1;
        stats.totalMonths += _months;

        if (!hasJoined[_user]) {
            allParticipants.push(_user);
            hasJoined[_user] = true;
        }

        emit RankUpdated(_user, stats.currentActiveDP, stats.lifetimeDP, stats.totalMonths);
    }

    function reduceActiveDP(address _user, uint256 _dp) external onlyVault {
        if (userStats[_user].currentActiveDP >= _dp) {
            userStats[_user].currentActiveDP -= _dp;
        } else {
            userStats[_user].currentActiveDP = 0;
        }
        
        emit StatsDecreased(_user, _dp, "Quest Completed/Withdrawn");
    }

    function getUserFullStats(address _user) external view returns (UserStats memory) {
        return userStats[_user];
    }

    function getTotalParticipants() external view returns (uint256) {
        return allParticipants.length;
    }
}