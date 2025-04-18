// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INumaPrinter {
    function getTWAPPriceInEth(
        uint _numaAmount,
        uint32 _interval
    ) external view returns (uint256);
}
