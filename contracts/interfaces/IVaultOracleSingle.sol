// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IVaultOracleSingle {
    //function getTokenPrice() external view returns (uint256,uint256,bool);
    function getTokenPrice(uint256 _amount) external view returns (uint256);
}
