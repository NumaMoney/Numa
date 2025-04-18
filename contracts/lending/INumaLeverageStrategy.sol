// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INumaLeverageStrategy {
    function getAmountIn(
        uint256 _amount,
        bool _closePos
    ) external view returns (uint256);

    function swap(
        uint256 _inputAmount,
        uint256 _minAmount,
        bool _closePosition
    ) external returns (uint256, uint256);
}
