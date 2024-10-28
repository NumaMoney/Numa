// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts_5.0.2/token/ERC20/utils/SafeERC20.sol";
import "./INumaLeverageStrategy.sol";
import "./CNumaToken.sol";
import "../NumaProtocol/NumaVault.sol";

contract NumaLeverageVaultSwap is INumaLeverageStrategy {
    NumaVault vault;
    uint slippage = 10000; // 1e4/1e18

    constructor(address _vault) {
        vault = NumaVault(_vault);
    }

    function getAmountIn(
        uint256 _amount,
        bool _closePosition
    ) external view returns (uint256) {
        CNumaToken cNuma = vault.cNuma();
        CNumaToken cLstToken = vault.cLstToken();

        if (
            ((msg.sender == address(cLstToken)) && (!_closePosition)) ||
            ((msg.sender == address(cNuma)) && (_closePosition))
        ) {
            uint amountIn = vault.getBuyNumaAmountIn(_amount);
            amountIn = amountIn + (amountIn * slippage) / 1 ether;
            return amountIn;
        } else if (
            ((msg.sender == address(cNuma)) && (!_closePosition)) ||
            ((msg.sender == address(cLstToken)) && (_closePosition))
        ) {
            uint amountIn = vault.getSellNumaAmountIn(_amount);
            amountIn = amountIn + (amountIn * slippage) / 1 ether;
            return amountIn;
        } else {
            revert("not allowed");
        }
    }

    function swap(
        uint256 _inputAmount,
        uint256 _minAmount,
        bool _closePosition
    ) external returns (uint256, uint256) {
        CNumaToken cNuma = vault.cNuma();
        CNumaToken cLst = vault.cLstToken();
        if (
            ((msg.sender == address(cLst)) && (!_closePosition)) ||
            ((msg.sender == address(cNuma)) && (_closePosition))
        ) {
            IERC20 input = IERC20(cLst.underlying());
            SafeERC20.safeTransferFrom(
                input,
                msg.sender,
                address(this),
                _inputAmount
            );
            input.approve(address(vault), _inputAmount);
            uint result = vault.buy(_inputAmount, _minAmount, msg.sender);
            return (result, 0); // no excess input for vault as we swap from amountIn
        } else if (
            ((msg.sender == address(cNuma)) && (!_closePosition)) ||
            ((msg.sender == address(cLst)) && (_closePosition))
        ) {
            IERC20 input = IERC20(cNuma.underlying());
            SafeERC20.safeTransferFrom(
                input,
                msg.sender,
                address(this),
                _inputAmount
            );
            input.approve(address(vault), _inputAmount);
            uint result = vault.sell(_inputAmount, _minAmount, msg.sender);
            return (result, 0); // no excess input for vault as we swap from amountIn
        } else {
            revert("not allowed");
        }
    }
}
