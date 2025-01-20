//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interfaces/INumaTokenToEthConverter.sol";
import "../libraries/OracleUtils.sol";

contract USDToEthConverter is INumaTokenToEthConverter, OracleUtils {
   
    address public immutable pricefeedETH_USD;
    uint128 immutable chainlink_heartbeatETH_USD;

    //uint decimals;

    constructor(
        address _pricefeedETH_USD,
        uint128 _chainlink_heartbeatETH_USD,
        address _uptimeFeedAddress //,
    )
        //uint _decimals
        OracleUtils(_uptimeFeedAddress)
    {

        pricefeedETH_USD = _pricefeedETH_USD;
        chainlink_heartbeatETH_USD = _chainlink_heartbeatETH_USD;
        //decimals = _decimals;
    }

   /**
    * @dev eth to pool token using 2 oracles 
    */
    function convertEthToToken(
        uint256 _ethAmount
    ) public view checkSequencerActive returns (uint256 tokenAmount) {
       
        (
            uint80 roundID2,
            int256 price2,
            ,
            uint256 timeStamp2,
            uint80 answeredInRound2
        ) = AggregatorV3Interface(pricefeedETH_USD).latestRoundData();

        // heartbeat check
        require(
            timeStamp2 >= block.timestamp - chainlink_heartbeatETH_USD,
            "Stale pricefeed"
        );

        // minAnswer/maxAnswer check
        IChainlinkAggregator aggregator2 = IChainlinkAggregator(
            IChainlinkPriceFeed(pricefeedETH_USD).aggregator()
        );
        require(
            ((price2 > int256(aggregator2.minAnswer())) &&
                (price2 < int256(aggregator2.maxAnswer()))),
            "min/max reached"
        );
        require(answeredInRound2 >= roundID2, "Answer given before round");

        // compose oracles

        // Chainlink ETH/USD price feed has 8 decimals; ethAmount is in wei (18 decimals)
        // To convert:
        //   (ethAmount in wei) * (ethPriceUsd) / 10^(decimals difference)
        //   = ethAmount * ethPriceUsd / 10^8
        tokenAmount = (_ethAmount * uint256(price2)) / 1e8;
    }

   /**
    * @dev pool token to eth using 2 oracles 
    */
    function convertTokenToEth(
        uint256 _tokenAmount
    ) public view checkSequencerActive returns (uint256 ethValue) {
       
        (
            uint80 roundID2,
            int256 price2,
            ,
            uint256 timeStamp2,
            uint80 answeredInRound2
        ) = AggregatorV3Interface(pricefeedETH_USD).latestRoundData();

        // heartbeat check
        require(
            timeStamp2 >= block.timestamp - chainlink_heartbeatETH_USD,
            "Stale pricefeed"
        );

        // minAnswer/maxAnswer check
        IChainlinkAggregator aggregator2 = IChainlinkAggregator(
            IChainlinkPriceFeed(pricefeedETH_USD).aggregator()
        );
        require(
            ((price2 > int256(aggregator2.minAnswer())) &&
                (price2 < int256(aggregator2.maxAnswer()))),
            "min/max reached"
        );

        require(answeredInRound2 >= roundID2, "Answer given before round");


        // Chainlink ETH/USD price feed has 8 decimals; usdAmount is in 18 decimals
        // To convert:
        //   (usdAmount in 18 decimals) * 10^(decimals difference) / ethPriceUsd
        //   = usdAmount * 10^8 / ethPriceUsd
        ethValue = (_tokenAmount * 1e8) / uint256(price2);
    }
}
