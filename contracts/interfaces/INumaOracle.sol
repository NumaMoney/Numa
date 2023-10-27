// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;



interface INumaOracle  
{
    function getCost(uint256 _amount, address _chainlinkFeed, address _xftPool) external view returns (uint256);
    function getCostSimpleShift(uint256 _amount, address _chainlinkFeed, address _xftPool, address _tokenPool) external view returns (uint256); 
  
}