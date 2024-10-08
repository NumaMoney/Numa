// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import "@openzeppelin/contracts_5.0.2/access/Ownable2Step.sol";

import "../nuAssets/nuAssetManager.sol";
import "../interfaces/INumaOracle.sol";
import "../interfaces/INumaTokenToEthConverter.sol";

import "forge-std/console.sol";
import "forge-std/console2.sol";
/// @title NumaOracle
/// @notice Responsible for getting prices from chainlink and uniswap V3 pools
/// @dev
contract NumaOracle is Ownable2Step, INumaOracle {
    address public immutable token;
    uint32 public intervalShort;
    uint32 public intervalLong;

    nuAssetManager public nuAManager;

    event IntervalShort(uint32 _intervalShort);
    event IntervalLong(uint32 _intervalLong);

    constructor(
        address _token,
        uint32 _intervalShort,
        uint32 _intervalLong,
        address initialOwner,
        address _nuAManager
    ) Ownable(initialOwner) {
        token = _token;
        intervalShort = _intervalShort;
        intervalLong = _intervalLong;
        nuAManager = nuAssetManager(_nuAManager);
    }

    function setIntervalShort(uint32 _interval) external onlyOwner {
        require(_interval > 0, "Interval must be nonzero");
        intervalShort = _interval;
        emit IntervalShort(intervalShort);
    }

    function setIntervalLong(uint32 _interval) external onlyOwner {
        require(
            _interval > intervalShort,
            "intervalLong must be greater than intervalShort"
        );
        intervalLong = _interval;
        emit IntervalLong(intervalLong);
    }
    function getTWAPPriceInEth(
        address _numaPool,
        address _converter,
        uint _numaAmount,
        uint32 _interval
    ) external view returns (uint256) {
        uint160 sqrtPriceX96 = getV3SqrtPriceAvg(_numaPool, _interval);

        uint256 numerator = (
            IUniswapV3Pool(_numaPool).token0() == token
                ? sqrtPriceX96
                : FixedPoint96.Q96
        );
        uint256 denominator = (
            numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96
        );

        uint256 TokenPerNumaMulAmount = (
            numerator == sqrtPriceX96
                ? FullMath.mulDivRoundingUp(
                    FullMath.mulDivRoundingUp(
                        denominator,
                        denominator * 10 ** IERC20Metadata(token).decimals(),
                        numerator
                    ),
                    _numaAmount,
                    numerator * 10 ** 18 // numa decimals
                )
                : FullMath.mulDivRoundingUp(
                    FullMath.mulDivRoundingUp(
                        denominator,
                        denominator * 10 ** 18,
                        numerator
                    ), // numa decimals
                    _numaAmount,
                    numerator * 10 ** IERC20Metadata(token).decimals()
                )
        );

        uint EthPerNumaMulAmount = TokenPerNumaMulAmount;
        if (_converter != address(0)) {
            EthPerNumaMulAmount = INumaTokenToEthConverter(_converter)
                .convertTokenToEth(TokenPerNumaMulAmount);
        }

        return EthPerNumaMulAmount;
    }

    function getV3LowestPrice(
        address _numaPool,
        uint _numaAmount
    ) external view returns (uint256) {
        uint160 sqrtPriceX96 = getV3SqrtLowestPrice(
            _numaPool,
            intervalShort,
            intervalLong
        );
        uint256 numerator = (
            IUniswapV3Pool(_numaPool).token0() == token
                ? sqrtPriceX96
                : FixedPoint96.Q96
        );
        uint256 denominator = (
            numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96
        );

        uint256 TokenPerNumaMulAmount = (
            numerator == sqrtPriceX96
                ? FullMath.mulDivRoundingUp(
                    FullMath.mulDivRoundingUp(
                        denominator,
                        denominator * 10 ** IERC20Metadata(token).decimals(),
                        numerator
                    ),
                    _numaAmount,
                    numerator * 10 ** 18 // numa decimals
                )
                : FullMath.mulDivRoundingUp(
                    FullMath.mulDivRoundingUp(
                        denominator,
                        denominator * 10 ** 18,
                        numerator
                    ), // numa decimals
                    _numaAmount,
                    numerator * 10 ** IERC20Metadata(token).decimals()
                )
        );

        return TokenPerNumaMulAmount;
    }

    function getV3HighestPrice(
        address _numaPool,
        uint _numaAmount
    ) external view returns (uint256) {
        uint160 sqrtPriceX96 = getV3SqrtHighestPrice(
            _numaPool,
            intervalShort,
            intervalLong
        );
        uint256 numerator = (
            IUniswapV3Pool(_numaPool).token0() == token
                ? sqrtPriceX96
                : FixedPoint96.Q96
        );
        uint256 denominator = (
            numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96
        );

        uint256 TokenPerNumaMulAmount = (
            numerator == sqrtPriceX96
                ? FullMath.mulDivRoundingUp(
                    FullMath.mulDivRoundingUp(
                        denominator,
                        denominator * 10 ** IERC20Metadata(token).decimals(),
                        numerator
                    ),
                    _numaAmount,
                    numerator * 10 ** 18 // numa decimals
                )
                : FullMath.mulDivRoundingUp(
                    FullMath.mulDivRoundingUp(
                        denominator,
                        denominator * 10 ** 18,
                        numerator
                    ), // numa decimals
                    _numaAmount,
                    numerator * 10 ** IERC20Metadata(token).decimals()
                )
        );

        return TokenPerNumaMulAmount;
    }
 
    /**
     * @dev Fetch uniswap V3 pool average price over an interval
     * @notice Will revert if interval is older than oldest pool observation
     * @param {address} _uniswapV3Pool pool address
     * @param {uint32} _interval interval value
     * @return the price in sqrt x96 format
     */
    function getV3SqrtPriceAvg(
        address _uniswapV3Pool,
        uint32 _interval
    ) public view returns (uint160) {
        require(_interval > 0, "interval cannot be zero");
        //Returns TWAP prices for short and long intervals
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = _interval; // from (before)
        secondsAgo[1] = 0; // to (now)

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(_uniswapV3Pool)
            .observe(secondsAgo);

        // tick(imprecise as it's an integer) to sqrtPriceX96
        return
            TickMath.getSqrtRatioAtTick(
                int24(
                    (tickCumulatives[1] - tickCumulatives[0]) /
                        int56(int32(_interval))
                )
            );
    }

    /**
     * @dev Get price using uniswap V3 pool returning lowest price from 2 intervals inputs
     * @notice Use minimum price between 2 intervals inputs
     * @param {address} _uniswapV3Pool pool address
     * @param {uint32} _intervalShort first interval value
     * @param {uint32} _intervalLong 2nd interval value
     * @return the price in sqrt x96 format
     */
    function getV3SqrtLowestPrice(
        address _uniswapV3Pool,
        uint32 _intervalShort,
        uint32 _intervalLong
    ) public view returns (uint160) {
        require(
            _intervalLong > _intervalShort,
            "intervalLong must be longer than intervalShort"
        );

        uint160 sqrtPriceX96;

        //Spot price of the token
        (uint160 sqrtPriceX96Spot, , , , , , ) = IUniswapV3Pool(_uniswapV3Pool)
            .slot0();

        //TWAP prices for short and long intervals
        uint160 sqrtPriceX96Short = getV3SqrtPriceAvg(
            _uniswapV3Pool,
            _intervalShort
        );
        uint160 sqrtPriceX96Long = getV3SqrtPriceAvg(
            _uniswapV3Pool,
            _intervalLong
        );
        console2.log(sqrtPriceX96Spot);
        console2.log(sqrtPriceX96Short);
        console2.log(sqrtPriceX96Long);
        //Takes the lowest token price denominated in token
        //Condition checks to see if token is in denominator of pair, ie: token1/token0
        if (IUniswapV3Pool(_uniswapV3Pool).token0() == token) {
            sqrtPriceX96 = (
                sqrtPriceX96Long >= sqrtPriceX96Short
                    ? sqrtPriceX96Long
                    : sqrtPriceX96Short
            );
            sqrtPriceX96 = (
                sqrtPriceX96 >= sqrtPriceX96Spot
                    ? sqrtPriceX96
                    : sqrtPriceX96Spot
            );
        } else {
            sqrtPriceX96 = (
                sqrtPriceX96Long <= sqrtPriceX96Short
                    ? sqrtPriceX96Long
                    : sqrtPriceX96Short
            );
            sqrtPriceX96 = (
                sqrtPriceX96 <= sqrtPriceX96Spot
                    ? sqrtPriceX96
                    : sqrtPriceX96Spot
            );
        }
        return sqrtPriceX96;
    }

    /**
     * @dev Get price using uniswap V3 pool returning largest price from 2 intervals inputs
     * @notice Use maximum price between 2 intervals inputs
     * @param {address} _uniswapV3Pool the pool to be used
     * @param {uint32} _intervalShort the short interval
     * @param {uint32} _intervalLong the long interval
     * @return the price in sqrt x96 format
     */
    function getV3SqrtHighestPrice(
        address _uniswapV3Pool,
        uint32 _intervalShort,
        uint32 _intervalLong
    ) public view returns (uint160) {
        require(
            _intervalLong > _intervalShort,
            "intervalLong must be longer than intervalShort"
        );

        uint160 sqrtPriceX96;
        //Spot price of the token
        (uint160 sqrtPriceX96Spot, , , , , , ) = IUniswapV3Pool(_uniswapV3Pool)
            .slot0();
        //TWAP prices for short and long intervals
        uint160 sqrtPriceX96Short = getV3SqrtPriceAvg(
            _uniswapV3Pool,
            _intervalShort
        );
        uint160 sqrtPriceX96Long = getV3SqrtPriceAvg(
            _uniswapV3Pool,
            _intervalLong
        );

        //Takes the highest token price denominated in token
        //Condition checks to see if token is in denominator of pair, ie: token1/token0
        if (IUniswapV3Pool(_uniswapV3Pool).token0() == token) {
            sqrtPriceX96 = (
                sqrtPriceX96Long <= sqrtPriceX96Short
                    ? sqrtPriceX96Long
                    : sqrtPriceX96Short
            );
            sqrtPriceX96 = (
                sqrtPriceX96 <= sqrtPriceX96Spot
                    ? sqrtPriceX96
                    : sqrtPriceX96Spot
            );
        } else {
            sqrtPriceX96 = (
                sqrtPriceX96Long >= sqrtPriceX96Short
                    ? sqrtPriceX96Long
                    : sqrtPriceX96Short
            );
            sqrtPriceX96 = (
                sqrtPriceX96 >= sqrtPriceX96Spot
                    ? sqrtPriceX96
                    : sqrtPriceX96Spot
            );
        }
        return sqrtPriceX96;
    }

    /**
     * @dev number of numa tokens needed to mint this amount of nuAsset
     * @param {uint256} _nuAssetAmount amount we want to mint
     * @param {address} _nuAsset the nuAsset address
     * @param {address} _numaPool Numa pool address
     * @return {uint256} amount of Numa needed to be burnt
     */
    function getNbOfNumaNeeded(
        uint256 _nuAssetAmount,
        address _nuAsset,
        address _numaPool,
        address _converter,
        uint _numaPerEthVault
    ) external view returns (uint256) {
        uint160 sqrtPriceX96 = getV3SqrtLowestPrice(
            _numaPool,
            intervalShort,
            intervalLong
        );

        uint256 numerator = (
            IUniswapV3Pool(_numaPool).token0() == token
                ? sqrtPriceX96
                : FixedPoint96.Q96
        );

        console.log(numerator);

        uint256 denominator = (
            numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96
        );

        console.log(denominator);

        uint256 numaPerTokenMulAmount = (
            numerator == sqrtPriceX96
                ? FullMath.mulDivRoundingUp(
                    FullMath.mulDivRoundingUp(
                        numerator,
                        numerator * 10 ** 18,
                        denominator
                    ),
                    _nuAssetAmount,
                    denominator * 10 ** IERC20Metadata(token).decimals() // numa decimals
                )
                : FullMath.mulDivRoundingUp(
                    FullMath.mulDivRoundingUp(
                        numerator,
                        numerator * 10 ** IERC20Metadata(token).decimals(),
                        denominator
                    ), // numa decimals
                    _nuAssetAmount,
                    denominator * 10 ** 18
                )
        );

        uint numaPerETHmulAmount = numaPerTokenMulAmount;
        if (_converter != address(0)) {
            numaPerETHmulAmount = INumaTokenToEthConverter(_converter)
                .convertEthToToken(numaPerTokenMulAmount);
        }

        console2.log("oracle numa per eth");
        console.log(numaPerTokenMulAmount);
        console.log(numaPerETHmulAmount);

        if (numaPerETHmulAmount < _numaPerEthVault) {
            console.log("clipped by vault");
            console.log(_numaPerEthVault);
            numaPerETHmulAmount = _numaPerEthVault;
        }

        uint256 tokensForAmount = nuAManager.getPriceInEthRoundUp(
            _nuAsset,
            numaPerETHmulAmount
        );
        return tokensForAmount;
    }

    function getNbOfNuAssetFromNuAsset(
        uint256 _nuAssetAmountIn,
        address _nuAssetIn,
        address _nuAssetOut
    ) external view returns (uint256) {
        uint256 nuAssetOutPerETHmulAmountIn = nuAManager.getTokenPerEth(
            _nuAssetOut,
            _nuAssetAmountIn
        );
        uint256 tokensForAmount = nuAManager.getPriceInEth(
            _nuAssetIn,
            nuAssetOutPerETHmulAmountIn
        );
        return tokensForAmount;
    }

    /**
     * @dev number of Numa that will be minted by burning this amount of nuAsset
     * @param {uint256} _nuAssetAmount amount we want to mint
     * @param {address} _nuAsset the nuAsset address
     * @param {address} _numaPool Numa pool address
     * @return {uint256} amount of Numa that will be minted
     */
    function getNbOfNumaFromAsset(
        uint256 _nuAssetAmount,
        address _nuAsset,
        address _numaPool,
        address _converter,
        uint _ethToNumaMulAmountVault
    ) external view returns (uint256) {
        // highest price for numa to minimize amount to mint
        uint160 sqrtPriceX96 = getV3SqrtHighestPrice(
            _numaPool,
            intervalShort,
            intervalLong
        );
        uint256 numerator = (
            IUniswapV3Pool(_numaPool).token0() == token
                ? sqrtPriceX96
                : FixedPoint96.Q96
        );
        uint256 denominator = (
            numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96
        );

        uint256 numaPerTokenMulAmount = (
            numerator == sqrtPriceX96
                ? FullMath.mulDivRoundingUp(
                    FullMath.mulDivRoundingUp(
                        numerator,
                        numerator * 10 ** 18,
                        denominator
                    ),
                    _nuAssetAmount,
                    denominator * 10 ** IERC20Metadata(token).decimals()
                )
                : FullMath.mulDivRoundingUp(
                    FullMath.mulDivRoundingUp(
                        numerator,
                        numerator * 10 ** IERC20Metadata(token).decimals(),
                        denominator
                    ),
                    _nuAssetAmount,
                    denominator * 10 ** 18
                )
        );

        uint numaPerETHmulAmount = numaPerTokenMulAmount;
                console.log("numaPerTokenMulAmount",numaPerETHmulAmount);



       

            //



        if (_converter != address(0)) {
            numaPerETHmulAmount = INumaTokenToEthConverter(_converter)
                .convertEthToToken(numaPerTokenMulAmount);
        }
    console.log("numaPerEthMulAmount",numaPerETHmulAmount);
        if (numaPerETHmulAmount > _ethToNumaMulAmountVault) {
            numaPerETHmulAmount = _ethToNumaMulAmountVault;
        }
  console.log("numaPerEthMulAmount",numaPerETHmulAmount);
        uint256 tokensForAmount = nuAManager.getPriceInEth(
            _nuAsset,
            numaPerETHmulAmount
        );

        return tokensForAmount;
    }

    function getNbOfNuAsset(
        uint256 _numaAmount,
        address _nuAsset,
        address _numaPool,
        address _converter,
        uint _EthPerNumaVault
    ) external view returns (uint256) {
        uint160 sqrtPriceX96 = getV3SqrtLowestPrice(
            _numaPool,
            intervalShort,
            intervalLong
        );
        uint256 numerator = (
            IUniswapV3Pool(_numaPool).token0() == token
                ? sqrtPriceX96
                : FixedPoint96.Q96
        );
        uint256 denominator = (
            numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96
        );

        uint256 TokenPerNumaMulAmount = (
            numerator == sqrtPriceX96
                ? FullMath.mulDivRoundingUp(
                    FullMath.mulDivRoundingUp(
                        denominator,
                        denominator * 10 ** IERC20Metadata(token).decimals(),
                        numerator
                    ),
                    _numaAmount,
                    numerator * 10 ** 18 // numa decimals
                )
                : FullMath.mulDivRoundingUp(
                    FullMath.mulDivRoundingUp(
                        denominator,
                        denominator * 10 ** 18,
                        numerator
                    ), // numa decimals
                    _numaAmount,
                    numerator * 10 ** IERC20Metadata(token).decimals()
                )
        );

        uint256 EthPerNumaMulAmount = TokenPerNumaMulAmount;
        if (_converter != address(0)) {
            EthPerNumaMulAmount = INumaTokenToEthConverter(_converter)
                .convertTokenToEth(TokenPerNumaMulAmount);
        }

        if (EthPerNumaMulAmount > _EthPerNumaVault) {
            EthPerNumaMulAmount = _EthPerNumaVault;
        }

        uint256 tokensForAmount = nuAManager.getTokenPerEth(
            _nuAsset,
            EthPerNumaMulAmount
        );
        return tokensForAmount;
    }

    function getNbOfAssetneeded(
        uint256 _amountNumaOut,
        address _nuAsset,
        address _numaPool,
        address _converter,
        uint _EthPerNumaVault
    ) external view returns (uint256) {
        // highest price for numa to minimize amount to mint
        uint160 sqrtPriceX96 = getV3SqrtHighestPrice(
            _numaPool,
            intervalShort,
            intervalLong
        );
        uint256 numerator = (
            IUniswapV3Pool(_numaPool).token0() == token
                ? sqrtPriceX96
                : FixedPoint96.Q96
        );
        uint256 denominator = (
            numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96
        );

        uint256 TokenPerNuma = (
            numerator == sqrtPriceX96
                ? FullMath.mulDivRoundingUp(
                    FullMath.mulDivRoundingUp(
                        denominator,
                        denominator * 10 ** IERC20Metadata(token).decimals(),
                        numerator
                    ),
                    _amountNumaOut,
                    numerator * 10 ** 18 // numa decimals
                )
                : FullMath.mulDivRoundingUp(
                    FullMath.mulDivRoundingUp(
                        denominator,
                        denominator * 10 ** 18,
                        numerator
                    ), // numa decimals
                    _amountNumaOut,
                    numerator * 10 ** IERC20Metadata(token).decimals()
                )
        );

        uint256 EthPerNuma = TokenPerNuma;
        if (_converter != address(0)) {
            EthPerNuma = INumaTokenToEthConverter(_converter)
                .convertTokenToEth(TokenPerNuma);
        }

        if (EthPerNuma < _EthPerNumaVault) {
            EthPerNuma = _EthPerNumaVault;
        }

        uint256 tokensForAmount = nuAManager.getTokenPerEthRoundUp(
            _nuAsset,
            EthPerNuma
        );
        return tokensForAmount;
    }
}
