// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INumaPrice {
    function GetNumaPriceEth(
        uint _amount
    ) external view returns (uint256);


    function GetNumaPerEth(
        uint _amount
    ) external view returns (uint256);
}
