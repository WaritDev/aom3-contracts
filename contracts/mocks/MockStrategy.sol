// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockStrategy {
    address public vault;
    IERC20 public usdc;

    constructor(address _usdc) {
        usdc = IERC20(_usdc);
    }

    function setVault(address _vault) external {
        vault = _vault;
    }

    function deposit(uint256 amount) external {
        require(msg.sender == vault, "Only vault");
        usdc.transferFrom(msg.sender, address(this), amount);
    }

    function redeemWithFee(uint256 totalAmount, uint256 feeAmount, address to) external {
        require(msg.sender == vault, "Only vault");
        usdc.transfer(to, totalAmount - feeAmount);
    }
}