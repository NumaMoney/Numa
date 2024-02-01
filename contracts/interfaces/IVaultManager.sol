// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;


interface IVaultManager  
{   
    function getTotalBalanceEth() external view returns (uint256);
    function TokenToNuma(uint _inputAmount,uint _refValueWei,uint _decimals) external view returns (uint256);
    function NumaToToken(uint _inputAmount,uint _refValueWei,uint _decimals) external view returns (uint256);
}

