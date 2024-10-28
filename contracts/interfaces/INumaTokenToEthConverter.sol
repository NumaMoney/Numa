// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INumaTokenToEthConverter {
    function convertEthToToken(
        uint256 _ethAmount
    ) external view returns (uint256);

    function convertTokenToEth(
        uint256 _tokenAmount
    ) external view returns (uint256);
}
