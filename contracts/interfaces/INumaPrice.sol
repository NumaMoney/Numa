// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INumaPrice {
    function GetNumaPriceEth(
        uint _amount
    ) external view returns (uint256);


    function GetNumaPerEth(
        uint _amount
    ) external view returns (uint256);

    function getBuyFee() external view returns (uint16);
    function getSellFee() external view returns (uint16);
}
