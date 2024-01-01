// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;



interface IVaultOracle  
{
    function getTokenPrice(address _tokenAddress) external view returns (uint256,uint256,bool);    
    function getTokenPrice(address _tokenAddress,uint256 _amount) external view returns (uint256);
}