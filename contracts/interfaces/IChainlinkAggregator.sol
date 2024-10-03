// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IChainlinkAggregator {
    function minAnswer() external view returns (int192);
    function maxAnswer() external view returns (int192);
}
