// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockRanking {
    address public vault;

    function setVault(address _vault) external {
        vault = _vault;
    }

    function registerNewQuest(address _user, uint256 _dp, uint256 _months) external {
        // Mock function
    }

    function reduceActiveDP(address _user, uint256 _dp) external {
        // Mock function
    }
}