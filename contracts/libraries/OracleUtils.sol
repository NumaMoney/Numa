// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

contract OracleUtils {

    /**
     * @dev chainlink call to a pricefeed with any amount
     */  
    function getPriceInEth(uint256 _amount, address _pricefeed) public view returns (uint256)
    {
        (uint80 roundID, int256 price, , uint256 timeStamp, uint80 answeredInRound) = AggregatorV3Interface(_pricefeed).latestRoundData();
        require(answeredInRound >= roundID, "Answer given before round");
        require(timeStamp != 0, "Invalid timestamp");
        require(price > 0, "Price must be greater than 0");
        uint256 decimalPrecision = AggregatorV3Interface(_pricefeed).decimals();

        uint256 EthValue;

        //if ETH is on the left side of the fraction in the price feed
        if (ethLeftSide(_pricefeed)) 
        {
            EthValue = FullMath.mulDiv(_amount, 10**decimalPrecision,uint256(price));
        }
        else 
        {
            EthValue = FullMath.mulDiv(_amount,uint256(price), 10**decimalPrecision);
        }
        return EthValue;
    }

    function ethLeftSide(address _chainlinkFeed) internal view returns (bool) 
    {
        string memory description = AggregatorV3Interface(_chainlinkFeed).description();
        bytes memory descriptionBytes = bytes(description);
        bytes memory ethBytes = bytes("ETH");
        for (uint i = 0; i < 3; i++) if (descriptionBytes[i] != ethBytes[i]) return false;
        return true;
    }
}