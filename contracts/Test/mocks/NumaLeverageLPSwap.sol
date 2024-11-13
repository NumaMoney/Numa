// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

pragma abicoder v2;
import "@openzeppelin/contracts_5.0.2/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import "../../lending/INumaLeverageStrategy.sol";
import "../../lending/CNumaToken.sol";
import "../../NumaProtocol/NumaVault.sol";

// TODO:
// - test
// - check if another strategy would work
// - slippage/margin and other parameters
// - LTV and other info
// - flashloan V2 using standart flashloan and borrowonbehalf from ctoken (callable only from a strategy) + liquidation strategies
contract NumaLeverageLPSwap is INumaLeverageStrategy {
    ISwapRouter public immutable swapRouter;
    IUniswapV3Pool pool;
    // For this example, we will set the pool fee to 0.5%.
    uint24 public constant poolFee = 500;
    NumaVault vault;

    uint slippage = 0.01 ether; //1% slippage tolerated (fees + slippage)

    // Constants used to handle fixed-point arithmetic for price calculations
    uint256 constant Q96 = 2 ** 96;

    constructor(address _swapRouter, address _poolAddress, address _vault) {
        swapRouter = ISwapRouter(_swapRouter);
        pool = IUniswapV3Pool(_poolAddress);
        vault = NumaVault(_vault);
    }

    function getEstimatedInput(
        address tokenIn, // Input token address
        address tokenOut, // Output token address
        uint256 outputAmount // Desired output amount
    ) public view returns (uint256 inputAmount) {
        // Fetch the pool's current state (slot0) to get the sqrtPriceX96
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        // Determine token0 and token1 from the pool
        address token0 = pool.token0();
        address token1 = pool.token1();

        // Check if the input token is token0 or token1 in the pool
        bool isInputToken0 = (tokenIn == token0);

        // Calculate the price based on whether input token is token0 or token1
        if (isInputToken0) {
            // If input token is token0, price = (sqrtPriceX96)^2 / 2^192
            // uint256 priceX96 = uint256(sqrtPriceX96) ** 2;

            // // Calculate the required input amount using price (token0 -> token1)
            // inputAmount = (outputAmount * (2 ** 192)) / priceX96;

            // If input token is token0, price = (sqrtPriceX96)^2 / 2^192
            // We split the multiplication and division to avoid overflow
            uint256 priceX96 = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) /
                Q96;

            // Calculate the required input amount using price (token0 -> token1)
            inputAmount = (outputAmount * Q96) / priceX96;
        } else {
            // // If input token is token1, price = (2^192) / (sqrtPriceX96)^2
            // uint256 priceX96 = uint256(sqrtPriceX96) ** 2;

            // // Calculate the required input amount using price (token1 -> token0)
            // inputAmount = (outputAmount * priceX96) / (2 ** 192);

            // If input token is token1, price = (2^192) / (sqrtPriceX96)^2
            // We split the multiplication and division to avoid overflow
            uint256 priceX96 = (uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) /
                Q96;

            // Calculate the required input amount using price (token1 -> token0)
            inputAmount = (outputAmount * priceX96) / Q96;
        }
    }

    function getAmountIn(
        uint256 _amount,
        bool _closePosition
    ) external view returns (uint256) {
        CNumaToken cNuma = vault.cNuma();
        CNumaToken cLstToken = vault.cLstToken();
        // CNumaToken caller = CNumaToken(msg.sender);
        // return caller.getVaultAmountIn(_amount, _closePos);
        if (
            ((msg.sender == address(cLstToken)) && (!_closePosition)) ||
            ((msg.sender == address(cNuma)) && (_closePosition))
        ) {
            uint amountIn = getEstimatedInput(
                cLstToken.underlying(),
                cNuma.underlying(),
                _amount
            );
            amountIn = amountIn + (amountIn * slippage) / 1 ether;
            return amountIn;
        } else if (
            ((msg.sender == address(cNuma)) && (!_closePosition)) ||
            ((msg.sender == address(cLstToken)) && (_closePosition))
        ) {
            uint amountIn = getEstimatedInput(
                cNuma.underlying(),
                cLstToken.underlying(),
                _amount
            );
            amountIn = amountIn + (amountIn * slippage) / 1 ether;
            return amountIn;
        } else {
            revert("not allowed");
        }
    }

    function swapOut(
        uint256 _outputAmount,
        uint256 _maxAmountIn,
        bool _closePosition
    ) public returns (uint256, uint256) {
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
        SafeERC20.safeTransferFrom(
            input,
            msg.sender,
            address(this),
            _maxAmountIn
        );
        input.approve(address(swapRouter), _maxAmountIn);

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

        // For exact output swaps, the amountInMaximum may not have all been spent.
        // If the actual amount spent (amountIn) is less than the specified maximum amount, we must refund the msg.sender and approve the swapRouter to spend 0.
        if (amountIn < _maxAmountIn) {
            input.approve(address(swapRouter), 0);
            SafeERC20.safeTransfer(input, msg.sender, _maxAmountIn - amountIn);
            return (_outputAmount, _maxAmountIn - amountIn);
        }
        return (_outputAmount, 0);
    }

    function swap(
        uint256 _inputAmount,
        uint256 _minAmount,
        bool _closePosition
    ) external returns (uint256, uint256) {
        return swapOut(_minAmount, _inputAmount, _closePosition);
    }
}
