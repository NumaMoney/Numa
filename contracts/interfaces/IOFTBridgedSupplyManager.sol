// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IOFTBridgedSupplyManager {
    function getBridgedSupply() external view returns (uint);

}