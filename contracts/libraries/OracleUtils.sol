// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import {IChainlinkAggregator} from "../interfaces/IChainlinkAggregator.sol";
import {IChainlinkPriceFeed} from "../interfaces/IChainlinkPriceFeed.sol";

import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

contract OracleUtils {
    uint256 private constant GRACE_PERIOD_TIME = 3600;

    error SequencerDown();
    error GracePeriodNotOver();

    address internal sequencerUptimeFeed;
    constructor(address _uptimeFeedAddress) {
        sequencerUptimeFeed = _uptimeFeedAddress;
    }

    modifier checkSequencerActive() {
        if (sequencerUptimeFeed != address(0)) {
            (
                ,
                /*uint80 roundID*/ int256 answer,
                uint256 startedAt /*uint256 updatedAt*/ /*uint80 answeredInRound*/,
                ,

            ) = AggregatorV2V3Interface(sequencerUptimeFeed).latestRoundData();

            // Answer == 0: Sequencer is up
            // Answer == 1: Sequencer is down
            bool isSequencerUp = answer == 0;
            if (!isSequencerUp) {
                revert SequencerDown();
            }

            // Make sure the grace period has passed after the
            // sequencer is back up.
            uint256 timeSinceUp = block.timestamp - startedAt;
            if (timeSinceUp <= GRACE_PERIOD_TIME) {
                revert GracePeriodNotOver();
            }
        }
        _;
    }

    /**
     * @dev chainlink call to a pricefeed with any amount
     */
    function ethToToken(
        uint256 _ethAmount,
        address _pricefeed,
        uint128 _chainlink_heartbeat,
        uint256 _decimals
    ) public view checkSequencerActive returns (uint256 tokenAmount) {
        (
            uint80 roundID,
            int256 price,
            ,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = AggregatorV3Interface(_pricefeed).latestRoundData();

        // heartbeat check
        require(
            timeStamp >= block.timestamp - _chainlink_heartbeat,
            "Stale pricefeed"
        );

        // minAnswer/maxAnswer check
        IChainlinkAggregator aggregator = IChainlinkAggregator(
            IChainlinkPriceFeed(_pricefeed).aggregator()
        );
        require(
            ((price > int256(aggregator.minAnswer())) &&
                (price < int256(aggregator.maxAnswer()))),
            "min/max reached"
        );

        require(answeredInRound >= roundID, "Answer given before round");

        //if ETH is on the left side of the fraction in the price feed
        if (ethLeftSide(_pricefeed)) {
            tokenAmount = FullMath.mulDiv(
                _ethAmount,
                uint256(price),
                10 ** AggregatorV3Interface(_pricefeed).decimals()
            );
        } else {
            tokenAmount = FullMath.mulDiv(
                _ethAmount,
                10 ** AggregatorV3Interface(_pricefeed).decimals(),
                uint256(price)
            );
        }

        // audit fix
        tokenAmount = tokenAmount * 10 ** (18 - _decimals);
    }

    /**
     * @dev chainlink call to a pricefeed with any amount
     */
    function ethToTokenRoundUp(
        uint256 _ethAmount,
        address _pricefeed,
        uint128 _chainlink_heartbeat,
        uint256 _decimals
    ) public view checkSequencerActive returns (uint256 tokenAmount) {
        (
            uint80 roundID,
            int256 price,
            ,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = AggregatorV3Interface(_pricefeed).latestRoundData();

        // heartbeat check
        require(
            timeStamp >= block.timestamp - _chainlink_heartbeat,
            "Stale pricefeed"
        );

        // minAnswer/maxAnswer check
        IChainlinkAggregator aggregator = IChainlinkAggregator(
            IChainlinkPriceFeed(_pricefeed).aggregator()
        );
        require(
            ((price > int256(aggregator.minAnswer())) &&
                (price < int256(aggregator.maxAnswer()))),
            "min/max reached"
        );

        require(answeredInRound >= roundID, "Answer given before round");

        //if ETH is on the left side of the fraction in the price feed
        if (ethLeftSide(_pricefeed)) {
            tokenAmount = FullMath.mulDivRoundingUp(
                _ethAmount,
                uint256(price),
                10 ** AggregatorV3Interface(_pricefeed).decimals()
            );
        } else {
            tokenAmount = FullMath.mulDivRoundingUp(
                _ethAmount,
                10 ** AggregatorV3Interface(_pricefeed).decimals(),
                uint256(price)
            );
        }
        // audit fix
        tokenAmount = tokenAmount * 10 ** (18 - _decimals);
    }

    /**
     * @dev chainlink call to a pricefeed with any amount
     */
    function tokenToEth(
        uint256 _amount,
        address _pricefeed,
        uint128 _chainlink_heartbeat,
        uint256 _decimals
    ) public view checkSequencerActive returns (uint256 EthValue) {
        (
            uint80 roundID,
            int256 price,
            ,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = AggregatorV3Interface(_pricefeed).latestRoundData();

        // heartbeat check
        require(
            timeStamp >= block.timestamp - _chainlink_heartbeat,
            "Stale pricefeed"
        );

        // minAnswer/maxAnswer check
        IChainlinkAggregator aggregator = IChainlinkAggregator(
            IChainlinkPriceFeed(_pricefeed).aggregator()
        );
        require(
            ((price > int256(aggregator.minAnswer())) &&
                (price < int256(aggregator.maxAnswer()))),
            "min/max reached"
        );

        require(answeredInRound >= roundID, "Answer given before round");

        //if ETH is on the left side of the fraction in the price feed
        if (ethLeftSide(_pricefeed)) {
            EthValue = FullMath.mulDiv(
                _amount,
                10 ** AggregatorV3Interface(_pricefeed).decimals(),
                uint256(price)
            );
        } else {
            EthValue = FullMath.mulDiv(
                _amount,
                uint256(price),
                10 ** AggregatorV3Interface(_pricefeed).decimals()
            );
        }

        // audit fix
        EthValue = EthValue * 10 ** (18 - _decimals);
    }

    /**
     * @dev chainlink call to a pricefeed with any amount
     */
    function tokenToEthRoundUp(
        uint256 _amount,
        address _pricefeed,
        uint128 _chainlink_heartbeat,
        uint256 _decimals
    ) public view checkSequencerActive returns (uint256 EthValue) {
        (
            uint80 roundID,
            int256 price,
            ,
            uint256 timeStamp,
            uint80 answeredInRound
        ) = AggregatorV3Interface(_pricefeed).latestRoundData();

        // heartbeat check
        require(
            timeStamp >= block.timestamp - _chainlink_heartbeat,
            "Stale pricefeed"
        );

        // minAnswer/maxAnswer check
        IChainlinkAggregator aggregator = IChainlinkAggregator(
            IChainlinkPriceFeed(_pricefeed).aggregator()
        );
        require(
            ((price > int256(aggregator.minAnswer())) &&
                (price < int256(aggregator.maxAnswer()))),
            "min/max reached"
        );

        require(answeredInRound >= roundID, "Answer given before round");

        //if ETH is on the left side of the fraction in the price feed
        if (ethLeftSide(_pricefeed)) {
            EthValue = FullMath.mulDivRoundingUp(
                _amount,
                10 ** AggregatorV3Interface(_pricefeed).decimals(),
                uint256(price)
            );
        } else {
            EthValue = FullMath.mulDivRoundingUp(
                _amount,
                uint256(price),
                10 ** AggregatorV3Interface(_pricefeed).decimals()
            );
        }
        // audit fix
        EthValue = EthValue * 10 ** (18 - _decimals);
    }

    function ethLeftSide(address _chainlinkFeed) internal view returns (bool) {
        string memory description = AggregatorV3Interface(_chainlinkFeed)
            .description();
        bytes memory descriptionBytes = bytes(description);
        bytes memory ethBytes = bytes("ETH");
        for (uint i = 0; i < 3; i++)
            if (descriptionBytes[i] != ethBytes[i]) return false;
        return true;
    }
}
