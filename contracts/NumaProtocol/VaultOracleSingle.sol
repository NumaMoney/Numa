//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interfaces/IVaultOracleSingle.sol";
import "../libraries/OracleUtils.sol";

contract VaultOracleSingle is IVaultOracleSingle, OracleUtils {
    address public feed;

    uint128 chainlink_heartbeat;

    constructor(address _feed, uint128 _chainlink_heartbeat) {
        feed = _feed;
        chainlink_heartbeat = _chainlink_heartbeat;
    }

    /**
     * @dev value in Eth (in wei) of this amount of token
     */
    function getTokenPrice(uint256 _amount) external view returns (uint256) {
        require(feed != address(0), "currency not supported");
        return getPriceInEth(_amount, feed, chainlink_heartbeat);
    }

    // /**
    //  * @dev value in Eth (in wei) of 1 token
    //  */
    // function getTokenPrice() external view returns (uint256,uint256,bool)
    // {

    //     (uint80 roundID, int256 price, , uint256 timeStamp, uint80 answeredInRound) = AggregatorV3Interface(feed).latestRoundData();
    //     require(timeStamp >= block.timestamp - chainlink_heartbeat , "Stale pricefeed");
    //     require(answeredInRound >= roundID, "Answer given before round");
    //     require(price > 0, "Price must be greater than 0");
    //     uint256 decimalPrecision = AggregatorV3Interface(feed).decimals();
    //     return (uint256(price),decimalPrecision,(ethLeftSide(feed)));
    // }
}
