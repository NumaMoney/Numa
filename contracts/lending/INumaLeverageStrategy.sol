// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// TODO: slippage?
interface INumaLeverageStrategy {
    //     function getFlashloanedLiquidity(
    //         uint256 _amount,bool _closePos
    //     ) external;

    //    function repayFlashloanedLiquidityAndRefund(
    //         uint256 _amount,bool _closePos
    //     ) external returns (uint256);

    function getAmountIn(
        uint256 _amount,
        bool _closePos
    ) external view returns (uint256);

    function swap(
        uint256 _inputAmount,
        uint256 _minAmount,
        bool _closePosition
    ) external returns (uint256);

    function getStrategyLTV(
        address _tokenAddress,
        uint256 _amount
    ) external view returns (uint256);
}
