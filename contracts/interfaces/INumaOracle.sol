// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INumaOracle {
    function getNbOfNumaNeeded(
        uint256 _amount,
        address _chainlinkFeed,
        uint128 _chainlink_heartbeat,
        address _numaPool
    ) external view returns (uint256);
    function getNbOfNumaFromAsset(
        uint256 _amount,
        address _chainlinkFeed,
        uint128 _chainlink_heartbeat,
        address _numaPool
    ) external view returns (uint256);
    function getNbOfNuAsset(
        uint256 _amount,
        address _chainlinkFeed,
        uint128 _chainlink_heartbeat,
        address _numaPool
    ) external view returns (uint256);
    function getNbOfAssetneeded(
        uint256 _amountNumaOut,
        address _chainlinkFeed,
        uint128 _chainlink_heartbeat,
        address _numaPool
    ) external view returns (uint256);
}
