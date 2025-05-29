// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {SongToken} from './SongToken.sol';


contract TokenFactory {
    event TokenCreated(address tokenAddress);

    function createToken(string memory name, string memory symbol) public {
        SongToken newToken = new SongToken(msg.sender, name, symbol);
        emit TokenCreated(address(newToken));
    }
}