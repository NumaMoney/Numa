//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interfaces/INumaTokenToEthConverter.sol";
import "../libraries/OracleUtils.sol";

import "forge-std/console2.sol";
contract USDCToEthConverter is INumaTokenToEthConverter, OracleUtils {
    address public pricefeedUSDC_USD;
    uint128 chainlink_heartbeatUSDC_USD;

    address public pricefeedETH_USD;
    uint128 chainlink_heartbeatETH_USD;

    uint decimals;

    constructor(
        address _pricefeedUSDC_USD,
        uint128 _chainlink_heartbeatUSDC_USD,
        address _pricefeedETH_USD,
        uint128 _chainlink_heartbeatETH_USD,
        address _uptimeFeedAddress,
        uint _decimals
    ) OracleUtils(_uptimeFeedAddress) {
        pricefeedUSDC_USD = _pricefeedUSDC_USD;
        chainlink_heartbeatUSDC_USD = _chainlink_heartbeatUSDC_USD;
        pricefeedETH_USD = _pricefeedETH_USD;
        chainlink_heartbeatETH_USD = _chainlink_heartbeatETH_USD;
        decimals = _decimals;
    }

   

     function convertEthToToken(
        uint256 _ethAmount
    ) public view checkSequencerActive returns (uint256 tokenAmount) {
        // 1st oracle
        (
            uint80 roundID,
            int256 price,
            ,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = AggregatorV3Interface(pricefeedUSDC_USD).latestRoundData();

        // heartbeat check
        require(
            timeStamp >= block.timestamp - chainlink_heartbeatUSDC_USD,
            "Stale pricefeed"
        );

        // minAnswer/maxAnswer check
        IChainlinkAggregator aggregator = IChainlinkAggregator(
            IChainlinkPriceFeed(pricefeedUSDC_USD).aggregator()
        );
        require(
            ((price > int256(aggregator.minAnswer())) &&
                (price < int256(aggregator.maxAnswer()))),
            "min/max reached"
        );


        console2.log("USDC/USD price",price);
        require(answeredInRound >= roundID, "Answer given before round");

        // 2nd oracle
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
        console2.log("ETH/USD price",price2);
        require(answeredInRound2 >= roundID2, "Answer given before round");


        // compose oracles

            tokenAmount = FullMath.mulDiv(
                _ethAmount,
                10 ** AggregatorV3Interface(pricefeedUSDC_USD).decimals() *
                    uint256(price2),
                uint256(price) *
                    10 ** AggregatorV3Interface(pricefeedETH_USD).decimals()
            );

       

        if (decimals < 18)
            tokenAmount = tokenAmount / (10 ** (18 - decimals));
        else
            tokenAmount = tokenAmount / (10 ** (decimals-18));

              console2.log(tokenAmount);

    }

   
    function convertTokenToEth(
        uint256 _tokenAmount
    ) public view checkSequencerActive returns (uint256 ethValue) {
        // 1st oracle
        (
            uint80 roundID,
            int256 price,
            ,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = AggregatorV3Interface(pricefeedUSDC_USD).latestRoundData();

        // heartbeat check
        require(
            timeStamp >= block.timestamp - chainlink_heartbeatUSDC_USD,
            "Stale pricefeed"
        );

        // minAnswer/maxAnswer check
        IChainlinkAggregator aggregator = IChainlinkAggregator(
            IChainlinkPriceFeed(pricefeedUSDC_USD).aggregator()
        );
        require(
            ((price > int256(aggregator.minAnswer())) &&
                (price < int256(aggregator.maxAnswer()))),
            "min/max reached"
        );

        require(answeredInRound >= roundID, "Answer given before round");

        // 2nd oracle
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
        // no need to check oracles direction as we can't change the oracles anyway
        // if feeds need to be changed a new converter will need to be deployed
         ethValue = FullMath.mulDiv(
                _tokenAmount,
                uint256(price) *
                    10 ** AggregatorV3Interface(pricefeedETH_USD).decimals()*10 ** (18 - decimals),
                10 ** AggregatorV3Interface(pricefeedUSDC_USD).decimals() *
                    uint256(price2)
            );

    }
    // function usdcLeftSide(address _chainlinkFeed) internal view returns (bool) {
    //     string memory description = AggregatorV3Interface(_chainlinkFeed)
    //         .description();
    //     bytes memory descriptionBytes = bytes(description);
    //     bytes memory usdcBytes = bytes("USDC");
    //     for (uint i = 0; i < 3; i++)
    //         if (descriptionBytes[i] != usdcBytes[i]) return false;
    //     return true;
    // }
}
