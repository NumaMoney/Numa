// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;



interface IVaultOracle  
{
    function getTokenPrice(address _tokenAddress) external view returns (uint256,uint256,bool);
   
}