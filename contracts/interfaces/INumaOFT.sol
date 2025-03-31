// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;


interface INumaOFT {
    function setMinter(address _minter) external;
    function mint(address _to, uint256 _amount) external;
}
