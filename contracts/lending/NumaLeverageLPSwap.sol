// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

pragma abicoder v2;
import "@openzeppelin/contracts_5.0.2/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import "./INumaLeverageStrategy.sol";
import "./CNumaToken.sol";
import "../NumaProtocol/NumaVault.sol";

// TODO:
// - test
// - check if another strategy would work
// - slippage/margin and other parameters
// - LTV and other info
// - flashloan V2 using standart flashloan and borrowonbehalf from ctoken (callable only from a strategy) + liquidation strategies
contract NumaLeverageLPSwap is INumaLeverageStrategy {
    ISwapRouter public immutable swapRouter;
    // IERC20 immutable numa;
    // IERC20 immutable reth;

    // For this example, we will set the pool fee to 0.3%.
    uint24 public constant poolFee = 500;
    NumaVault vault;

    //constructor(ISwapRouter _swapRouter,address _numa,address _reth,address _vault) {
    constructor(address _swapRouter, address _vault) {
        swapRouter = ISwapRouter(_swapRouter);
        //numa = _numa;
        // reth = _reth;
        vault = NumaVault(_vault);
    }

    function getAmountIn(
        uint256 _amount,
        bool _closePos
    ) external view returns (uint256) {
        // TODO
        CNumaToken caller = CNumaToken(msg.sender);
        return caller.getVaultAmountIn(_amount, _closePos);
    }

    function swapOut(
        uint256 _outputAmount,
        uint256 _maxAmountIn,
        bool _closePosition
    ) public returns (uint256) {
        CNumaToken cNuma = vault.cNuma();
        CNumaToken cLst = vault.cLstToken();
        IERC20 input = IERC20(cLst.underlying());
        IERC20 output = IERC20(cNuma.underlying());
        if (
            ((msg.sender == address(cLst)) && (!_closePosition)) ||
            ((msg.sender == address(cNuma)) && (_closePosition))
        ) {} else if (
            ((msg.sender == address(cNuma)) && (!_closePosition)) ||
            ((msg.sender == address(cLst)) && (_closePosition))
        ) {
            input = IERC20(cNuma.underlying());
            output = IERC20(cLst.underlying());
        } else {
            revert("not allowed");
        }
        // SWAP
        console2.log("TRANSFER");
        SafeERC20.safeTransferFrom(
            input,
            msg.sender,
            address(this),
            _maxAmountIn
        );
        input.approve(address(swapRouter), _maxAmountIn);

        console2.log("SWAP");
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams({
                tokenIn: address(input),
                tokenOut: address(output),
                fee: poolFee,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountOut: _outputAmount,
                amountInMaximum: _maxAmountIn,
                sqrtPriceLimitX96: 0
            });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        uint amountIn = swapRouter.exactOutputSingle(params);
        console2.log(amountIn);
        console2.log(_maxAmountIn);
        // TODO: what to do with excess
        // For exact output swaps, the amountInMaximum may not have all been spent.
        // If the actual amount spent (amountIn) is less than the specified maximum amount, we must refund the msg.sender and approve the swapRouter to spend 0.
        if (amountIn < _maxAmountIn) {
            input.approve(address(swapRouter), 0);
            SafeERC20.safeTransfer(input, msg.sender, _maxAmountIn - amountIn);
        }
        return amountIn;

        // if (((msg.sender == address(cLst)) && (!_closePosition))
        // || ((msg.sender == address(cNuma)) && (_closePosition)))
        // {
        //     IERC20 input = IERC20(cLst.underlying());
        //     IERC20 output = IERC20(cNuma.underlying());
        //     SafeERC20.safeTransferFrom(input,msg.sender,address(this),_maxAmountIn);
        //     input.approve(address(swapRouter), _maxAmountIn);

        //     ISwapRouter.ExactOutputSingleParams memory params =
        //         ISwapRouter.ExactOutputSingleParams({
        //         tokenIn: address(input),
        //         tokenOut: address(output),
        //         fee: poolFee,
        //         recipient: msg.sender,
        //         deadline: block.timestamp,
        //         amountOut: _outputAmount,
        //         amountInMaximum: _maxAmountIn,
        //         sqrtPriceLimitX96: 0
        //     });

        //     // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        //     uint amountIn = swapRouter.exactOutputSingle(params);

        //     // TODO: what to do with excess
        //     // For exact output swaps, the amountInMaximum may not have all been spent.
        //     // If the actual amount spent (amountIn) is less than the specified maximum amount, we must refund the msg.sender and approve the swapRouter to spend 0.
        //     if (amountIn < _maxAmountIn) {
        //         input.approve(address(swapRouter),0);
        //         SafeERC20.safeTransfer(input,msg.sender,_maxAmountIn - amountIn);
        //     }
        //     return amountIn;
        // }
        // else if (((msg.sender == address(cNuma))&& (!_closePosition))
        // || ((msg.sender == address(cLst)) && (_closePosition)))
        // {

        //     // TODO

        //     // IERC20 input = IERC20(cNuma.underlying());
        //     // IERC20 output = IERC20(cLst.underlying());
        //     // SafeERC20.safeTransferFrom(input,msg.sender,address(this),_maxAmountIn);
        //     // input.approve(address(swapRouter), _maxAmountIn);

        //     //  uint result = vault.sell(_inputAmount,_minAmount,msg.sender);
        //     // SafeERC20.safeTransferFrom(output,address(this),msg.sender,result);
        //     // return result;
        //     return 0;
        // }
        // else
        // {
        //     revert("not allowed");
        // }
    }

    function swap(
        uint256 _inputAmount,
        uint256 _minAmount,
        bool _closePosition
    ) external returns (uint256) {
        return swapOut(_minAmount, _inputAmount, _closePosition);
        // CNumaToken cNuma = vault.cNuma();
        // CNumaToken cLst = vault.cLstToken();
        // if (((msg.sender == address(cLst)) && (!_closePosition))
        // || ((msg.sender == address(cNuma)) && (_closePosition)))
        // {
        //     IERC20 input = IERC20(cLst.underlying());
        //     IERC20 output = IERC20(cNuma.underlying());
        //     SafeERC20.safeTransferFrom(input,msg.sender,address(this),_inputAmount);
        //     input.approve(address(vault),_inputAmount);
        //     uint result = vault.buy(_inputAmount,_minAmount,msg.sender);
        //     SafeERC20.safeTransferFrom(output,address(this),msg.sender,result);
        //     return result;
        // }
        // else if (((msg.sender == address(cNuma))&& (!_closePosition))
        // || ((msg.sender == address(cLst)) && (_closePosition)))
        // {
        //     IERC20 input = IERC20(cNuma.underlying());
        //     IERC20 output = IERC20(cLst.underlying());
        //     SafeERC20.safeTransferFrom(input,msg.sender,address(this),_inputAmount);
        //     input.approve(address(vault),_inputAmount);
        //      uint result = vault.sell(_inputAmount,_minAmount,msg.sender);
        //     SafeERC20.safeTransferFrom(output,address(this),msg.sender,result);
        //     return result;
        // }
        // else
        // {
        //     revert("not allowed");
        // }
    }

    function getStrategyLTV(
        address _tokenAddress,
        uint256 _amount
    ) external view returns (uint256) {}
}
