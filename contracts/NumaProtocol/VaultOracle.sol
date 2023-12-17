//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import "../interfaces/IVaultOracle.sol";

contract VaultOracle is Ownable, IVaultOracle
{
    
    mapping(address => address) public tokenToFeed;

    event TokenAdded(address _tokenAddress,_chainlinkFeed);

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

    function ethLeftSide(address _chainlinkFeed) internal view returns (bool) 
    {
        string memory description = AggregatorV3Interface(_chainlinkFeed).description();
        bytes memory descriptionBytes = bytes(description);
        bytes memory ethBytes = bytes("ETH");
        for (uint i = 0; i < 3; i++) if (descriptionBytes[i] != ethBytes[i]) return false;
        return true;
    }



    function addSupportedToken(address _tokenAddress, address _chainlinkFeed) external onlyOwner  
    {
        tokenToFeed[_tokenAddress] = _chainlinkFeed;
        emit TokenAdded(_tokenAddress,_chainlinkFeed);
    }


}