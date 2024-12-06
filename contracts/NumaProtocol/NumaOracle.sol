// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import "@openzeppelin/contracts_5.0.2/access/Ownable2Step.sol";
import "@openzeppelin/contracts_5.0.2/utils/math/Math.sol";

import "../nuAssets/nuAssetManager.sol";
import "../interfaces/INumaOracle.sol";
import "../interfaces/INumaTokenToEthConverter.sol";

/// @title NumaOracle
/// @notice Responsible for getting prices from chainlink and uniswap V3 pools
/// @dev
contract NumaOracle is Ownable2Step, INumaOracle {
    address public immutable token;
    uint32 public intervalShort;
    uint32 public intervalLong;
    //uint maxSpotOffsetBps = 145;//1.45%
    //uint maxSpotOffsetSqrtBps = 1204;//sqrt(1.45%)

    uint160 maxSpotOffsetPlus1SqrtBps = 10072;
    uint160 maxSpotOffsetMinus1SqrtBps = 9927;

    nuAssetManager public nuAManager;

    event IntervalShort(uint32 _intervalShort);
    event IntervalLong(uint32 _intervalLong);
    event MaxSpotOffsetBps(uint _maxSpotOffsetBps);
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

    /**
     * 
     * @param _interval short twap interval
     */
    function setIntervalShort(uint32 _interval) external onlyOwner {
        require(_interval > 0, "Interval must be nonzero");
        intervalShort = _interval;
        emit IntervalShort(intervalShort);
    }

    /**
     * 
     * @param _interval long twap interval
     */
    function setIntervalLong(uint32 _interval) external onlyOwner {
        require(
            _interval > intervalShort,
            "intervalLong must be greater than intervalShort"
        );
        intervalLong = _interval;
        emit IntervalLong(intervalLong);
    }

    /**
     * 
     * @param _maxSpotOffsetBps offset percentage variable (cf doc)
     */
    function setMaxSpotOffsetBps(uint _maxSpotOffsetBps) external onlyOwner {
        require(_maxSpotOffsetBps < 10000, "percentage must be less than 100");

        maxSpotOffsetPlus1SqrtBps =
            100 *
            uint160(Math.sqrt(10000 + _maxSpotOffsetBps));

        maxSpotOffsetMinus1SqrtBps =
            100 *
            uint160(Math.sqrt(10000 - _maxSpotOffsetBps));

        emit MaxSpotOffsetBps(_maxSpotOffsetBps);
    }

    /**
     * @notice numa twap price in eth
     * @param _numaPool pool address
     * @param _converter converter from pool token to eth
     * @param _numaAmount amount
     * @param _interval time interval to consider
     */
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

        uint256 TokenPerNumaMulAmount = FullMath.mulDivRoundingUp(
            FullMath.mulDivRoundingUp(denominator, denominator, numerator),
            _numaAmount,
            numerator
        );

        uint EthPerNumaMulAmount = TokenPerNumaMulAmount;
        if (_converter != address(0)) {
            EthPerNumaMulAmount = INumaTokenToEthConverter(_converter)
                .convertTokenToEth(TokenPerNumaMulAmount);
        }

        return EthPerNumaMulAmount;
    }

    /**
     * @notice returns lowest price from long interval (twap), short interval (twap) and spot
     * @param _numaPool pool address
     * @param _numaAmount amount
     */
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

        uint256 TokenPerNumaMulAmount = FullMath.mulDiv(
            FullMath.mulDiv(denominator, denominator, numerator), // numa decimals
            _numaAmount,
            numerator
        );

        return TokenPerNumaMulAmount;
    }

    /**
     * @notice returns pool spot numa price
     * @param _numaPool pool
     * @param _numaAmount amount
     */
    function getV3SpotPrice(
        address _numaPool,
        uint _numaAmount
    ) external view returns (uint256) {
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(_numaPool).slot0();
        uint256 numerator = (
            IUniswapV3Pool(_numaPool).token0() == token
                ? sqrtPriceX96
                : FixedPoint96.Q96
        );
        uint256 denominator = (
            numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96
        );

        uint256 TokenPerNumaMulAmount = FullMath.mulDivRoundingUp(
            FullMath.mulDivRoundingUp(denominator, denominator, numerator),
            _numaAmount,
            numerator
        );

        return TokenPerNumaMulAmount;
    }

    /**
     * @notice returns highest price from long interval (twap), short interval (twap) and spot
     * @param _numaPool pool address
     * @param _numaAmount amount
     */
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

        uint256 TokenPerNumaMulAmount = FullMath.mulDivRoundingUp(
            FullMath.mulDivRoundingUp(denominator, denominator, numerator),
            _numaAmount,
            numerator
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

        //Takes the lowest token price denominated in token
        //Condition checks to see if token is in denominator of pair, ie: token1/token0
        if (IUniswapV3Pool(_uniswapV3Pool).token0() == token) {
            sqrtPriceX96 = (
                sqrtPriceX96Long >= sqrtPriceX96Short
                    ? sqrtPriceX96Long
                    : sqrtPriceX96Short
            );

            // comparing to spot price with numaLPspotPrice*(1+maxSpotOffsetBps)
            // inverted because numa price is 1/sqrtPriceX96
            uint160 sqrtPriceX96SpotModified = (sqrtPriceX96Spot * 10000) /
                maxSpotOffsetPlus1SqrtBps;

            sqrtPriceX96 = (
                sqrtPriceX96 >= sqrtPriceX96SpotModified
                    ? sqrtPriceX96
                    : sqrtPriceX96SpotModified
            );
        } else {
            sqrtPriceX96 = (
                sqrtPriceX96Long <= sqrtPriceX96Short
                    ? sqrtPriceX96Long
                    : sqrtPriceX96Short
            );
            // comparing to spot price with numaLPspotPrice*(1+maxSpotOffsetBps)
            uint160 sqrtPriceX96SpotModified = (sqrtPriceX96Spot *
                maxSpotOffsetPlus1SqrtBps) / 10000;

            sqrtPriceX96 = (
                sqrtPriceX96 <= sqrtPriceX96SpotModified
                    ? sqrtPriceX96
                    : sqrtPriceX96SpotModified
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

            // comparing to spot price with numaLPspotPrice*(1+maxSpotOffsetBps)
            // inverted because numa price is 1/sqrtPriceX96
            uint160 sqrtPriceX96SpotModified = (sqrtPriceX96Spot * 10000) /
                maxSpotOffsetMinus1SqrtBps;

            sqrtPriceX96 = (
                sqrtPriceX96 <= sqrtPriceX96SpotModified
                    ? sqrtPriceX96
                    : sqrtPriceX96SpotModified
            );
        } else {
            sqrtPriceX96 = (
                sqrtPriceX96Long >= sqrtPriceX96Short
                    ? sqrtPriceX96Long
                    : sqrtPriceX96Short
            );

            // comparing to spot price with numaLPspotPrice*(1+maxSpotOffsetBps)
            uint160 sqrtPriceX96SpotModified = (sqrtPriceX96Spot *
                maxSpotOffsetMinus1SqrtBps) / 10000;

            sqrtPriceX96 = (
                sqrtPriceX96 >= sqrtPriceX96SpotModified
                    ? sqrtPriceX96
                    : sqrtPriceX96SpotModified
            );
        }
        return sqrtPriceX96;
    }

    /**
     * @notice convert eth to nuasset 
     * @param _nuAsset nuAsset address
     * @param _amount amount
     */
    function ethToNuAsset(
        address _nuAsset,
        uint256 _amount
    ) public view returns (uint256 tokenAmount) {
        tokenAmount = nuAManager.ethToNuAsset(_nuAsset, _amount);
    }

    /**
     * @notice convert eth to nuasset by rounding up
     * @param _nuAsset nuAsset address
     * @param _amount amount
     */
    function ethToNuAssetRoundUp(
        address _nuAsset,
        uint256 _amount
    ) public view returns (uint256 tokenAmount) {
        tokenAmount = nuAManager.ethToNuAssetRoundUp(_nuAsset, _amount);
    }

   /**
     * @notice convert nuasset to eth with rounding up
     * @param _nuAsset nuAsset address
     * @param _amount amount
     */
    function nuAssetToEthRoundUp(
        address _nuAsset,
        uint256 _amount
    ) public view returns (uint256 EthValue) {
        EthValue = nuAManager.nuAssetToEthRoundUp(_nuAsset, _amount);
    }

   /**
     * @notice convert nuasset to eth
     * @param _nuAsset nuAsset address
     * @param _amount amount
     */
    function nuAssetToEth(
        address _nuAsset,
        uint256 _amount
    ) public view returns (uint256 EthValue) {
        EthValue = nuAManager.nuAssetToEth(_nuAsset, _amount);
    }

    /**
     * @notice convert eth to numa 
     * @param _ethAmount eth amount
     * @param _numaPool pool address
     * @param _converter token to eth converter address
     * @param _priceType highest or lowest
     */
    function ethToNuma(
        uint256 _ethAmount,
        address _numaPool,
        address _converter,
        PriceType _priceType
    ) external view returns (uint256 numaAmount) {
        // eth --> pool token
        uint tokenAmount = _ethAmount;
        if (_converter != address(0)) {
            tokenAmount = INumaTokenToEthConverter(_converter)
                .convertEthToToken(_ethAmount);
        }

        uint160 sqrtPriceX96;
        if (_priceType == PriceType.HighestPrice) {
            sqrtPriceX96 = getV3SqrtHighestPrice(
                _numaPool,
                intervalShort,
                intervalLong
            );
        } else {
            sqrtPriceX96 = getV3SqrtLowestPrice(
                _numaPool,
                intervalShort,
                intervalLong
            );
        }

        uint256 numerator = (
            IUniswapV3Pool(_numaPool).token0() == token
                ? sqrtPriceX96
                : FixedPoint96.Q96
        );

        uint256 denominator = (
            numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96
        );

        if (_priceType == PriceType.HighestPrice) {
            // burning nuassets
            // numaAmount has to be minimized so rounding down
            numaAmount = FullMath.mulDiv(
                FullMath.mulDiv(numerator, numerator, denominator),
                tokenAmount,
                denominator
            );
        } else {
            // minting nuassets
            // numaAmount has to be maximized so rounding up
            numaAmount = FullMath.mulDivRoundingUp(
                FullMath.mulDivRoundingUp(numerator, numerator, denominator),
                tokenAmount,
                denominator
            );
        }
    }

    /**
     * @notice nuasset to nuasset conversion
     * @param _nuAssetAmountIn amount in
     * @param _nuAssetIn nuasset input address
     * @param _nuAssetOut nuasset output address
     */
    function getNbOfNuAssetFromNuAsset(
        uint256 _nuAssetAmountIn,
        address _nuAssetIn,
        address _nuAssetOut
    ) external view returns (uint256) {
        uint256 nuAssetOutPerETHmulAmountIn = nuAManager.ethToNuAsset(
            _nuAssetOut,
            _nuAssetAmountIn
        );
        uint256 tokensForAmount = nuAManager.nuAssetToEth(
            _nuAssetIn,
            nuAssetOutPerETHmulAmountIn
        );
        return tokensForAmount;
    }

    /**
     * @notice convert numa to eth
     * @param _numaAmount numa amount
     * @param _numaPool pool address
     * @param _converter token to eth converter address
     * @param _priceType lowest or highest price from pool
     */
    function numaToEth(
        uint256 _numaAmount,
        address _numaPool,
        address _converter,
        PriceType _priceType
    ) external view returns (uint256) {
        uint160 sqrtPriceX96;

        if (_priceType == PriceType.HighestPrice) {
            sqrtPriceX96 = getV3SqrtHighestPrice(
                _numaPool,
                intervalShort,
                intervalLong
            );
        } else {
            sqrtPriceX96 = getV3SqrtLowestPrice(
                _numaPool,
                intervalShort,
                intervalLong
            );
        }

        uint256 numerator = (
            IUniswapV3Pool(_numaPool).token0() == token
                ? sqrtPriceX96
                : FixedPoint96.Q96
        );
        uint256 denominator = (
            numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96
        );

        uint256 TokenPerNumaMulAmount;

        if (_priceType == PriceType.HighestPrice) {
            // we use numa highest price when burning nuassets to numa
            // in that case rounding should be in favor of the protocol so we round UP
            TokenPerNumaMulAmount = FullMath.mulDivRoundingUp(
                FullMath.mulDivRoundingUp(denominator, denominator, numerator),
                _numaAmount,
                numerator // numa decimals
            );
        } else {
            // we use numa lowest price when minting nuassets from numa
            // in that case rounding should be in favor of the protocol so we round DOWN
            TokenPerNumaMulAmount = FullMath.mulDiv(
                FullMath.mulDiv(denominator, denominator, numerator),
                _numaAmount,
                numerator // numa decimals
            );
        }

        uint256 ethForAmount = TokenPerNumaMulAmount;
        if (_converter != address(0)) {
            ethForAmount = INumaTokenToEthConverter(_converter)
                .convertTokenToEth(TokenPerNumaMulAmount);
        }

        return ethForAmount;
    }
}
