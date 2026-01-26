// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AOM3Strategy is Ownable {
    address public immutable usdc;

    constructor(address _usdc) Ownable(msg.sender) {
        usdc = _usdc;
    }

    function deposit(uint256 amount) external {
        IERC20(usdc).transferFrom(msg.sender, address(this), amount);
    }

    function redeem(uint256 amount, address to) external {
        IERC20(usdc).transfer(to, amount);
    }
}