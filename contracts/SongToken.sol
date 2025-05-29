// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract SongToken is ERC20, Ownable, ERC20Permit {
    uint256 public constant MAX_SUPPLY = 100000;
    uint256 public freezeAmount;
    uint256 public freezeEndTime;

    constructor(address initialOwner, string memory tokenName, string memory tokenSymbol)
        ERC20(tokenName, tokenSymbol)
        Ownable(msg.sender)
        ERC20Permit(tokenName)
    {
        _mint(initialOwner, MAX_SUPPLY);

        freezeAmount = (MAX_SUPPLY * 10) / 100;
        freezeEndTime = block.timestamp + 365 days; 
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (msg.sender == owner() && block.timestamp < freezeEndTime) {
            uint256 availableBalance = balanceOf(msg.sender) - freezeAmount;
            require(amount <= availableBalance, "Transfer amount exceeds available balance during freeze period");
        }
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        if (sender == owner() && block.timestamp < freezeEndTime) {
            uint256 availableBalance = balanceOf(sender) - freezeAmount;
            require(amount <= availableBalance, "Transfer amount exceeds available balance during freeze period");
        }
        return super.transferFrom(sender, recipient, amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return 0;
    }
}