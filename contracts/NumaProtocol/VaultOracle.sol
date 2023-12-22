//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IVaultOracle.sol";
import "../libraries/OracleUtils.sol";


// only works with tokens that have 18 decimals
contract VaultOracle is Ownable, IVaultOracle,OracleUtils
{
    mapping(address => address) public tokenToFeed;
    event TokenFeed(address _tokenAddress,address _chainlinkFeed);


    constructor() Ownable(msg.sender)
    {

    }

    /**
     * @dev value in Eth (in wei) of this amount of token 
     */  
    function getTokenPrice(address _tokenAddress,uint256 _amount) external view returns (uint256)
    {
        address priceFeed = tokenToFeed[_tokenAddress];
        require(priceFeed != address(0),"currency not supported");
        return getPriceInEth(_amount,priceFeed);
    }



    /**
     * @dev value in Eth (in wei) of this 1 token
     */  
    function getTokenPrice(address _tokenAddress) external view returns (uint256,uint256,bool)
    {
        address priceFeed = tokenToFeed[_tokenAddress];
        require(priceFeed != address(0),"currency not supported");
        (uint80 roundID, int256 price, , uint256 timeStamp, uint80 answeredInRound) = AggregatorV3Interface(priceFeed).latestRoundData();
        require(answeredInRound >= roundID, "Answer given before round");
        require(timeStamp != 0, "Invalid timestamp");
        require(price > 0, "Price must be greater than 0");
        uint256 decimalPrecision = AggregatorV3Interface(priceFeed).decimals();
        return (uint256(price),decimalPrecision,(ethLeftSide(priceFeed)));
    }


    /**
     * @dev set a chainlink price feed associated to an ERC20 token
     */  
    function setTokenFeed(address _tokenAddress, address _chainlinkFeed) external onlyOwner  
    {
        tokenToFeed[_tokenAddress] = _chainlinkFeed;
        emit TokenFeed(_tokenAddress,_chainlinkFeed);
    }

}