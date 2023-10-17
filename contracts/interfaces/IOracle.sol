// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;



interface IOracle  
{
    function getCost(uint256 _amount, address _chainlinkFeed, address _xftPool) external view returns (uint256);
  
}