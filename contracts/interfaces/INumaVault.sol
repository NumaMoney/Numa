// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INumaVault {
    function getEthBalance() external view returns (uint256);
    function getSellNumaSimulateExtract(uint256 _amount) external view returns (uint256);
}
