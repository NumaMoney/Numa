// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts_5.0.2/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts_5.0.2/access/Ownable.sol";

contract LstTokenMock is ERC20, Ownable {
    constructor(
        address initialOwner
    ) ERC20("LstTokenMock", "lstETH") Ownable(initialOwner) {
        _mint(msg.sender, 100000000 * 10 ** decimals());
    }
}
