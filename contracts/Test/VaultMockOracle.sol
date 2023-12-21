//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;


import "../interfaces/IVaultOracle.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
contract VaultMockOracle is IVaultOracle
{
    uint price;


    constructor() 
    {

    }

    function setPrice(uint256 _price) external
    {
        price = _price;

    }


    function getTokenPrice(address _tokenAddress) external view returns (uint256,uint256,bool)
    {

        return ((price),18,false);
    }

    // function getTokenPriceSimple(address _tokenAddress) external view returns (uint256)
    // {

    //     return (price);
    // }

    function getTokenPrice(address _tokenAddress,uint256 _amount) external view returns (uint256)
    {
        return FullMath.mulDiv(_amount,uint256(price), 10**18);
        
    }

}