// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts_5.0.2/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts_5.0.2/access/IAccessControl.sol";

interface INuma is IERC20, IAccessControl {
    function mint(address to, uint256 amount) external;
}
