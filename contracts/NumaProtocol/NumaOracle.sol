// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/INumaPrice.sol";
/// @title NumaOracle
/// @notice Responsible for getting prices from chainlink and uniswap V3 pools
/// @dev 
contract NumaOracle is Ownable 
{
    address public immutable weth9;
    uint32 public intervalShort;
    uint32 public intervalLong;
    
    INumaPrice public numaPrice;
    uint public tolerance1000;

    event IntervalShort(uint32 _intervalShort);
    event IntervalLong(uint32 _intervalLong);
    event FlexFeeThreshold(uint256 _flexFeeThreshold);
    event NumaPrice(address _numaPrice,uint _tolerance1000);

    constructor(address _weth9,uint32 _intervalShort,uint32 _intervalLong,address initialOwner) Ownable(initialOwner) 
    {
        weth9 = _weth9;
        intervalShort = _intervalShort;
        intervalLong = _intervalLong;
      
    }

    function setNumaPrice(address _numaPriceAddress,uint _tolerance1000) external onlyOwner 
    {
       
        numaPrice = INumaPrice(_numaPriceAddress);
        tolerance1000 = _tolerance1000;
        emit NumaPrice(_numaPriceAddress,_tolerance1000);
    }
    function setIntervalShort(uint32 _interval) external onlyOwner 
    {
        require(_interval > 0, "Interval must be nonzero");
        intervalShort = _interval;
        emit IntervalShort(intervalShort);
    }

    function setIntervalLong(uint32 _interval) external onlyOwner 
    {
        require(_interval > intervalShort, "intervalLong must be greater than intervalShort");
        intervalLong = _interval;
        emit IntervalLong(intervalLong);
    }



    /**
     * @dev Get chainlink price from price feed address
     * @notice filter invalid Chainlink feeds ie 0 timestamp, invalid round IDs
     * @param {address} _chainlinkFeed chainlink feed address
     * @return {uint256} the chainlink price 
     */    
    function chainlinkPrice(address _chainlinkFeed) public view returns (uint256) 
    {
        (uint80 roundID, int256 price, , uint256 timeStamp, uint80 answeredInRound) = AggregatorV3Interface(_chainlinkFeed).latestRoundData();
        require(answeredInRound >= roundID, "Answer given before round");
        require(timeStamp != 0, "Invalid timestamp");
        require(price > 0, "Price must be greater than 0");
        return uint256(price);
    }


    /**
     * @dev Fetch uniswap V3 pool average price over an interval
     * @notice Will revert if interval is older than oldest pool observation
     * @param {address} _uniswapV3Pool pool address
     * @param {uint32} _interval interval value
     * @return the price in sqrt x96 format
     */  
    function getV3SqrtPriceAvg (address _uniswapV3Pool, uint32 _interval) public view returns (uint160) 
    {
        require(_interval > 0, "interval cannot be zero");
        //Returns TWAP prices for short and long intervals
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = _interval; // from (before)
        secondsAgo[1] = 0; // to (now)
       
        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(_uniswapV3Pool).observe(secondsAgo);

        // tick(imprecise as it's an integer) to sqrtPriceX96
        return TickMath.getSqrtRatioAtTick(int24((tickCumulatives[1] - tickCumulatives[0]) / int56(int32(_interval))));// TODO: added the int56(int32( cast, check it
    }

    /**
     * @dev Get price using uniswap V3 pool returning lowest price from 2 intervals inputs 
     * @notice Use minimum price between 2 intervals inputs 
     * @param {address} _uniswapV3Pool pool address
     * @param {uint32} _intervalShort first interval value
     * @param {uint32} _intervalLong 2nd interval value
     * @return the price in sqrt x96 format 
     */  
    function getV3SqrtLowestPrice(address _uniswapV3Pool, uint32 _intervalShort, uint32 _intervalLong) public view returns (uint160) 
    {
        require(_intervalLong > _intervalShort, "intervalLong must be longer than intervalShort");

        uint160 sqrtPriceX96;

        //Spot price of the token
        (uint160 sqrtPriceX96Spot, , , , , , ) = IUniswapV3Pool(_uniswapV3Pool).slot0();

        //TWAP prices for short and long intervals
        uint160 sqrtPriceX96Short = getV3SqrtPriceAvg(_uniswapV3Pool, _intervalShort);        
        uint160 sqrtPriceX96Long = getV3SqrtPriceAvg(_uniswapV3Pool, _intervalLong);
        //Takes the lowest token price denominated in WETH
        //Condition checks to see if WETH is in denominator of pair, ie: token1/token0
        if (IUniswapV3Pool(_uniswapV3Pool).token0() == weth9) 
        {
            sqrtPriceX96 = (sqrtPriceX96Long >= sqrtPriceX96Short ? sqrtPriceX96Long : sqrtPriceX96Short);
            sqrtPriceX96 = (sqrtPriceX96 >= sqrtPriceX96Spot ? sqrtPriceX96 : sqrtPriceX96Spot);
        }
        else 
        {
            sqrtPriceX96 = (sqrtPriceX96Long <= sqrtPriceX96Short ? sqrtPriceX96Long : sqrtPriceX96Short);
            sqrtPriceX96 = (sqrtPriceX96 <= sqrtPriceX96Spot ? sqrtPriceX96 : sqrtPriceX96Spot);
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
    function getV3SqrtHighestPrice(address _uniswapV3Pool, uint32 _intervalShort, uint32 _intervalLong) public view returns (uint160) 
    {
        require(_intervalLong > _intervalShort, "intervalLong must be longer than intervalShort");

        uint160 sqrtPriceX96;
        //Spot price of the token
        (uint160 sqrtPriceX96Spot, , , , , , ) = IUniswapV3Pool(_uniswapV3Pool).slot0();
        //TWAP prices for short and long intervals
        uint160 sqrtPriceX96Short = getV3SqrtPriceAvg(_uniswapV3Pool, _intervalShort);
        uint160 sqrtPriceX96Long = getV3SqrtPriceAvg(_uniswapV3Pool, _intervalLong);

        //Takes the highest token price denominated in WETH
        //Condition checks to see if WETH is in denominator of pair, ie: token1/token0
        if (IUniswapV3Pool(_uniswapV3Pool).token0() == weth9) 
        {
            sqrtPriceX96 = (sqrtPriceX96Long <= sqrtPriceX96Short ? sqrtPriceX96Long : sqrtPriceX96Short);
            sqrtPriceX96 = (sqrtPriceX96 <= sqrtPriceX96Spot ? sqrtPriceX96 : sqrtPriceX96Spot);
        }
        else 
        {
            sqrtPriceX96 = (sqrtPriceX96Long >= sqrtPriceX96Short ? sqrtPriceX96Long : sqrtPriceX96Short);
            sqrtPriceX96 = (sqrtPriceX96 >= sqrtPriceX96Spot ? sqrtPriceX96 : sqrtPriceX96Spot);
        }
        return sqrtPriceX96;
    }


    /**
     * @dev check if _chainlinkFeed.description() starts with "ETH" 
     * @param {address} _chainlinkFeed chainlink feed address
     * @return {bool} true if chainlinkFeed.description() starts with "ETH" 
     */
    function ethLeftSide(address _chainlinkFeed) internal view returns (bool) 
    {
        if (_chainlinkFeed == address(0)) return true;
        string memory description = AggregatorV3Interface(_chainlinkFeed).description();
        bytes memory descriptionBytes = bytes(description);
        bytes memory ethBytes = bytes("ETH");
        for (uint i = 0; i < 3; i++) if (descriptionBytes[i] != ethBytes[i]) return false;
        return true;
    }




    /**
     * @dev number of numa tokens needed to mint amount 
     * @notice Uses mulDivRoundingUp instead of mulDiv. Will round up number of numa to be burned.
     * @param {address} _pool the pool to be used
     * @param {uint32} _intervalShort the short interval
     * @param {uint32} _intervalLong the long interval
     * @param {address} _chainlinkFeed chainlink feed
     * @param {uint256} _amount amount we want to mint
     * @param {address} _weth9 weth address
     * @return {uint256} amount needed to be burnt
     */
    function getTokensForAmountCeiling(address _pool, uint32 _intervalShort, uint32 _intervalLong, address _chainlinkFeed, uint256 _amount,  address _weth9) public view returns (uint256)
     {
       
        uint160 sqrtPriceX96 = getV3SqrtLowestPrice(_pool, _intervalShort, _intervalLong);
        uint256 numerator = (IUniswapV3Pool(_pool).token0() == _weth9 ? sqrtPriceX96 : FixedPoint96.Q96);
        uint256 denominator = (numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96);
        //numa per ETH, times _amount
        uint256 numaPerETH = FullMath.mulDivRoundingUp(FullMath.mulDivRoundingUp(numerator, numerator, denominator), _amount, denominator);
        
        // check that numa price is within vault's price bounds to prevent price manipulation
        if (address(numaPrice) != address(0))
        {
            // do it only if we specified a contract that can give us numa price
            uint256 numaPerEthVault = numaPrice.GetPriceFromVaultWithoutFees(_amount);
            // TODO: check this way of using percent, could I get rounding issues?
            numaPerEthVault = numaPerEthVault + (numaPerEthVault*tolerance1000)/1000;
            if (numaPerETH < numaPerEthVault)
            {
                revert("numa price out of vault's bounds");
            }       
        }

        if (_chainlinkFeed == address(0)) 
        {
            revert("oracle should be set");
        }
        uint256 linkFeed = chainlinkPrice(_chainlinkFeed);
        uint256 decimalPrecision = AggregatorV3Interface(_chainlinkFeed).decimals();
        uint256 tokensForAmount;
        //if ETH is on the left side of the fraction in the price feed
        if (ethLeftSide(_chainlinkFeed))
        {
            tokensForAmount = FullMath.mulDivRoundingUp(numaPerETH, 10**decimalPrecision, linkFeed);
        }
        else
        {
            tokensForAmount = FullMath.mulDivRoundingUp(numaPerETH, linkFeed, 10**decimalPrecision);
        }

        return tokensForAmount;
    }
        


   

    /**
     * @dev number of Numa that will be minted by burning this amount of nuAsset using numa pool and chainlink
     * @param {address} _pool Numa pool address
     * @param {uint32} _intervalShort the short interval
     * @param {uint32} _intervalLong the long interval
     * @param {address} _chainlinkFeed chainlink feed
     * @param {uint256} _amount amount we want to burn
     * @param {address} _weth9 weth address
     */
    function getNbOfNumaFromAssetUsingOracle(address _pool, uint32 _intervalShort, uint32 _intervalLong, address _chainlinkFeed, uint256 _amount, address _weth9) public view returns (uint256) 
    {
        // highest price for numa to minimize amount to mint
        uint160 sqrtPriceX96 = getV3SqrtHighestPrice(_pool, _intervalShort, _intervalLong);
        uint256 numerator = (IUniswapV3Pool(_pool).token0() == _weth9 ? sqrtPriceX96 : FixedPoint96.Q96);
        uint256 denominator = (numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96);
        //numa per ETH, times _amount
        uint256 numaPerETH = FullMath.mulDiv(FullMath.mulDiv(numerator, numerator, denominator), _amount, denominator);

        // check that numa price is within vault's price bounds to prevent price manipulation
        if (address(numaPrice) != address(0))
        {
            // do it only if we specified a contract that can give us numa price
            uint256 numaPerEthVault = numaPrice.GetPriceFromVaultWithoutFees(_amount);
            numaPerEthVault = numaPerEthVault - (numaPerEthVault*tolerance1000)/1000;
            if (numaPerETH > numaPerEthVault)
            {
                revert("numa price out of vault's bounds");
            }       
        }

        if (_chainlinkFeed == address(0)) 
        {
            revert("oracle should be set");
        }
        uint256 linkFeed = chainlinkPrice(_chainlinkFeed);
        uint256 decimalPrecision = AggregatorV3Interface(_chainlinkFeed).decimals();
        uint256 tokensForAmount;
        //if ETH is on the left side of the fraction in the price feed
        if (ethLeftSide(_chainlinkFeed)) {
            tokensForAmount = FullMath.mulDiv(numaPerETH, 10**decimalPrecision, linkFeed);
        } else {
            tokensForAmount = FullMath.mulDiv(numaPerETH, linkFeed, 10**decimalPrecision);
        }
        return tokensForAmount;
    }

    /**
     * @dev number of numa tokens needed to mint this amount of nuAsset
     * @param {uint256} _amount amount we want to mint
     * @param {address} _chainlinkFeed chainlink feed
     * @param {address} _numaPool Numa pool address
     * @return {uint256} amount of Numa needed to be burnt
     */
    function getNbOfNumaNeeded(uint256 _amount, address _chainlinkFeed, address _numaPool) external view returns (uint256) 
    {       
       return getTokensForAmountCeiling(_numaPool, intervalShort, intervalLong, _chainlinkFeed, _amount, weth9);
    }


    /**
     * @dev number of Numa that will be minted by burning this amount of nuAsset
     * @param {uint256} _amount amount we want to burn
     * @param {address} _chainlinkFeed chainlink feed
     * @param {address} _numaPool Numa pool address
     * @param {address} _tokenPool nuAsset pool address
     * @return {uint256} amount of Numa that will be minted
     */
    function getNbOfNumaFromAsset(uint256 _amount, address _chainlinkFeed, address _numaPool) external view returns (uint256) 
    {
        uint256 _output;
        // we use chainlink price
        _output = getNbOfNumaFromAssetUsingOracle(_numaPool, intervalShort, intervalLong, _chainlinkFeed, _amount, weth9);
        return _output;
    }

    /**
     * @dev number of numa tokens needed to mint amount 
     * @notice same as getTokensForAmountCeiling but without rounding up
     * @param {address} _pool the pool to be used
     * @param {uint32} _intervalShort the short interval
     * @param {uint32} _intervalLong the long interval
     * @param {address} _chainlinkFeed chainlink feed
     * @param {uint256} _amount amount we want to mint
     * @param {address} _weth9 weth address
     * @return {uint256} amount needed to be burnt
     */
    // function getTokensForAmount(address _pool, uint32 _intervalShort, uint32 _intervalLong, address _chainlinkFeed, uint256 _amount, address _weth9) public view returns (uint256) {
    //     uint160 sqrtPriceX96 = getV3SqrtLowestPrice(_pool, _intervalShort, _intervalLong);
    //     uint256 numerator = (IUniswapV3Pool(_pool).token0() == _weth9 ? sqrtPriceX96 : FixedPoint96.Q96);
    //     uint256 denominator = (numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96);
    //     //numa per ETH, times _amount
    //     uint256 numaPerETH = FullMath.mulDiv(FullMath.mulDiv(numerator, numerator, denominator), _amount, denominator);

    //     if (_chainlinkFeed == address(0)) return numaPerETH;
    //     uint256 linkFeed = chainlinkPrice(_chainlinkFeed);
    //     uint256 decimalPrecision = AggregatorV3Interface(_chainlinkFeed).decimals();
    //     uint256 tokensForAmount;
    //     //if ETH is on the left side of the fraction in the price feed
    //     if (ethLeftSide(_chainlinkFeed)) {
    //         tokensForAmount = FullMath.mulDiv(numaPerETH, 10**decimalPrecision, linkFeed);
    //     } else {
    //         tokensForAmount = FullMath.mulDiv(numaPerETH, linkFeed, 10**decimalPrecision);
    //     }
    //     return tokensForAmount;
    // }




    // NEW FUNCTIONS FOR SYNTHETIC SWAP
    // TODO: TESTS PRINTER&ORACLE
    function getNbOfNuAsset(uint256 _amount, address _chainlinkFeed, address _numaPool) external view returns (uint256) 
    {       
       return nbOfNuAssetFromNuma(_numaPool, intervalShort, intervalLong, _chainlinkFeed, _amount, weth9);
    }



    // TODO: test me 
    // TODO: ceiling too?  --> should be round down as it's inverted but mulDiv already rounds down
    function nbOfNuAssetFromNuma(address _pool, uint32 _intervalShort, uint32 _intervalLong, address _chainlinkFeed, uint256 _amount, address _weth9) public view returns (uint256) {
        uint160 sqrtPriceX96 = getV3SqrtLowestPrice(_pool, _intervalShort, _intervalLong);
        uint256 numerator = (IUniswapV3Pool(_pool).token0() == _weth9 ? sqrtPriceX96 : FixedPoint96.Q96);
        uint256 denominator = (numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96);
        //numa per ETH, times _amount
        //uint256 numaPerETH = FullMath.mulDiv(FullMath.mulDiv(numerator, numerator, denominator), _amount, denominator);
        uint256 EthPerNuma = FullMath.mulDiv(FullMath.mulDiv(denominator, denominator, numerator), _amount, numerator);

        if (_chainlinkFeed == address(0)) return EthPerNuma;
        uint256 linkFeed = chainlinkPrice(_chainlinkFeed);
        uint256 decimalPrecision = AggregatorV3Interface(_chainlinkFeed).decimals();
        uint256 tokensForAmount;
        //if ETH is on the left side of the fraction in the price feed
        // if (ethLeftSide(_chainlinkFeed)) {
        //     tokensForAmount = FullMath.mulDiv(numaPerETH, 10**decimalPrecision, linkFeed);
        // } else {
        //     tokensForAmount = FullMath.mulDiv(numaPerETH, linkFeed, 10**decimalPrecision);
        // }

        if (ethLeftSide(_chainlinkFeed)) 
        {
            tokensForAmount = FullMath.mulDiv(EthPerNuma, linkFeed,10**decimalPrecision);
        }
        else
        {
            tokensForAmount = FullMath.mulDiv(EthPerNuma, 10**decimalPrecision,linkFeed);
        }



        return tokensForAmount;
    }



    function getNbOfAssetneeded(uint256 _amountNumaOut, address _chainlinkFeed, address _numaPool, address _tokenPool) external view returns (uint256) 
    {
        uint256 _output;
        // if nuAsset price using uniswap pool is below threshold we use pool value as price reference
        if (isTokenBelowThreshold(flexFeeThreshold, _tokenPool, intervalShort, intervalLong, _chainlinkFeed, weth9)) 
        {
            //_output = getNbOfNumaFromAssetUsingPools(_numaPool, _tokenPool, intervalShort, intervalLong, _amount, weth9);
            _output = getNbOfAssetNeededUsingPools(_numaPool, _tokenPool, intervalShort, intervalLong, _amountNumaOut, weth9);
        } 
        else 
        {
            // if not we use chainlink price
            _output = getNbOfAssetNeededUsingOracle(_numaPool, intervalShort, intervalLong, _chainlinkFeed, _amountNumaOut, weth9);
        }
        return _output;
    }


    // amount of asset needed to burn to get this Numa amount
    function getNbOfAssetNeededUsingOracle(address _pool, uint32 _intervalShort, uint32 _intervalLong, address _chainlinkFeed, uint256 _amountNumaOut, address _weth9) public view returns (uint256) 
    {
        
        // highest price for numa to minimize amount to mint
        uint160 sqrtPriceX96 = getV3SqrtHighestPrice(_pool, _intervalShort, _intervalLong);
        uint256 numerator = (IUniswapV3Pool(_pool).token0() == _weth9 ? sqrtPriceX96 : FixedPoint96.Q96);
        uint256 denominator = (numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96);
        //numa per ETH, times _amount
        uint256 EthPerNuma = FullMath.mulDiv(FullMath.mulDiv(denominator, denominator, numerator), _amountNumaOut, numerator);

        if (_chainlinkFeed == address(0)) return EthPerNuma;
        uint256 linkFeed = chainlinkPrice(_chainlinkFeed);
        uint256 decimalPrecision = AggregatorV3Interface(_chainlinkFeed).decimals();
        uint256 tokensForAmount;
        //if ETH is on the left side of the fraction in the price feed
        if (ethLeftSide(_chainlinkFeed)) {
            tokensForAmount = FullMath.mulDiv(EthPerNuma,linkFeed, 10**decimalPrecision);
        } else {
            tokensForAmount = FullMath.mulDiv(EthPerNuma, 10**decimalPrecision,linkFeed);
        }
        return tokensForAmount;
    }

    function getNbOfAssetNeededUsingPools(address _numaPool, address _tokenPool, uint32 _intervalShort, uint32 _intervalLong, uint256 _amountNumaOut, address _weth9) public view returns (uint256) 
    {
        // highest price for numa to minimize amount to mint
        uint160 numaSqrtPriceX96 = getV3SqrtHighestPrice(_numaPool, _intervalShort, _intervalLong);
        // lowest price for nuAsset to maximize amount to burn
        uint160 tokenSqrtPriceX96 = getV3SqrtLowestPrice(_tokenPool, _intervalShort, _intervalLong);
        uint256 numaA;
        uint256 numaPrice;
        uint256 tokenA;
        uint256 tokenPrice;


        if (IUniswapV3Pool(_numaPool).token1() == _weth9) 
        {
            numaA = FullMath.mulDiv(numaSqrtPriceX96, numaSqrtPriceX96, FixedPoint96.Q96);
            numaPrice = FullMath.mulDiv(numaA, _amountNumaOut, FixedPoint96.Q96);
        }
        else 
        {
            numaA = FullMath.mulDiv(FixedPoint96.Q96, FixedPoint96.Q96, numaSqrtPriceX96);
            numaPrice = FullMath.mulDiv(numaA, _amountNumaOut, numaSqrtPriceX96);
        }

        // tokenPrice is ETH/Token
        if (IUniswapV3Pool(_tokenPool).token0() == _weth9) 
        {
            tokenA = FullMath.mulDiv(tokenSqrtPriceX96, tokenSqrtPriceX96, FixedPoint96.Q96);
            tokenPrice = FullMath.mulDiv(tokenA, 1e18, FixedPoint96.Q96);
        }
        else
        {
            tokenA = FullMath.mulDiv(FixedPoint96.Q96, FixedPoint96.Q96, tokenSqrtPriceX96);
            tokenPrice = FullMath.mulDiv(tokenA, 1e18, tokenSqrtPriceX96);
        }

        //Multiplying numaPrice by tokenPrice and dividing by 1e18
        //In other words, numa * amount / Tokens -> Number of numa to mint for a given amount
        return FullMath.mulDiv(numaPrice, tokenPrice, 1e18); 
    }

}