// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INumaTokenToEthConverter {
    function convertNumaPerTokenToNumaPerEth(
        uint256 _numaPerTokenmulAmount
    ) external view returns (uint256);
    function convertTokenPerNumaToEthPerNuma(
        uint256 _tokenPerNumamulAmount
    ) external view returns (uint256);
}
