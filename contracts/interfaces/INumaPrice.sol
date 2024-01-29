// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;



interface INumaPrice  {
    function GetPriceFromVaultWithoutFees(uint _amount) external view returns (uint256);
}