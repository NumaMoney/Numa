// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts_5.0.2/token/ERC20/utils/SafeERC20.sol";
import "./INumaLeverageStrategy.sol";
import "./CNumaToken.sol";
import "../NumaProtocol/NumaVault.sol";
// TODO:
// - test leverage
// - implem close and test that profit is the same
// - check if another strategy would work: LP swap, check profit
// - slippage/margin and other parameters
// - LTV and other info
// - check strategies code an security potential issues
// - flashloan V2 using standart flashloan and borrowonbehalf from ctoken (callable only from a strategy) + liquidation strategies
// ou juste liquidation strategies
contract NumaLeverageVaultSwap is INumaLeverageStrategy {
    NumaVault vault;

    constructor(address _vault) {
        vault = NumaVault(_vault);
    }

    function getAmountIn(
        uint256 _amount,
        bool _closePos
    ) external view returns (uint256) {
        CNumaToken caller = CNumaToken(msg.sender);
        return caller.getVaultAmountIn(_amount, _closePos);
    }

    function swap(
        uint256 _inputAmount,
        uint256 _minAmount,
        bool _closePosition
    ) external returns (uint256) {
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
            return result;
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
            return result;
        } else {
            revert("not allowed");
        }
    }

    function getStrategyLTV(
        address _tokenAddress,
        uint256 _amount
    ) external view returns (uint256) {}
}
