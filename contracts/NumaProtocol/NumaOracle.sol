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
         console.log("****getV3SqrtLowestPrice***");
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

        uint256 numaPerETHmulAmount = (
            numerator == sqrtPriceX96 ?
        FullMath.mulDivRoundingUp(
            FullMath.mulDivRoundingUp(numerator, numerator* 10**18, denominator),
            _nuAssetAmount,
            denominator * 10**IERC20Metadata(token).decimals()// numa decimals
        ) 
        : FullMath.mulDivRoundingUp(
            FullMath.mulDivRoundingUp(numerator, numerator * 10**IERC20Metadata(token).decimals(), denominator),// numa decimals
            _nuAssetAmount,
            denominator* 10**18
        )
        );

        if (_converter != address(0))
        {
            numaPerETHmulAmount = INumaTokenToEthConverter(_converter).convertNumaPerTokenToNumaPerEth(numaPerETHmulAmount);//,0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3,1000*86400,0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612,1000*86400) ;
        }
        console.log(numaPerETHmulAmount);

     
        if (numaPerETHmulAmount < _numaPerEthVault)
        {
            numaPerETHmulAmount = _numaPerEthVault;
        }

        uint256 tokensForAmount = nuAManager.getPriceInEthRoundUp(_nuAsset,numaPerETHmulAmount);
        return tokensForAmount;
    }


    function getNbOfNuAssetFromNuAsset( uint256 _nuAssetAmountIn,
        address _nuAssetIn,
        address _nuAssetOut
    ) external view returns (uint256) 
    {
 
        uint256 nuAssetOutPerETHmulAmount = nuAManager.getTokenPerEth(_nuAssetOut,_nuAssetAmountIn);
        uint256 tokensForAmount = nuAManager.getPriceInEth(_nuAssetIn,nuAssetOutPerETHmulAmount);
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
        uint    _numaPerEthVault
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

        uint256 numaPerETHmulAmount = (
            numerator == sqrtPriceX96 ?
            FullMath.mulDivRoundingUp(
                FullMath.mulDivRoundingUp(numerator, numerator* 10**18, denominator),
                _nuAssetAmount,
                denominator * 10**IERC20Metadata(token).decimals()
            ) 
            : FullMath.mulDivRoundingUp(
                FullMath.mulDivRoundingUp(numerator, numerator * 10**IERC20Metadata(token).decimals(), denominator),
                _nuAssetAmount,
                denominator* 10**18
            )
        );

        if (_converter != address(0))
        {
            numaPerETHmulAmount = INumaTokenToEthConverter(_converter).convertNumaPerTokenToNumaPerEth(numaPerETHmulAmount);//,0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3,1000*86400,0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612,1000*86400) ;
        }


        // numaUSDC pool
        //numaPerETHmulAmount = nuAManager.convertNumaPerUSDCToNumaPerEth(numaPerETHmulAmount,0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3,1000*86400,0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612,1000*86400) ;



        // check that numa price is within vault's price bounds to prevent price manipulation
        // if (address(numaPrice) != address(0)) {
        //     // do it only if we specified a contract that can give us numa price
        //     uint256 numaPerEthVault = numaPrice.GetNumaPerEth(
        //         _nuAssetAmount
        //     );
        //     (uint16 sellfee,) = numaPrice.getSellFee();
        //     numaPerEthVault = (numaPerEthVault * 1000) / (sellfee);

        //     if (numaPerETHmulAmount > numaPerEthVault) 
        //     {
        //         // clip price
        //         numaPerETHmulAmount = numaPerEthVault;
        //         //revert("numa price out of vault's bounds");
        //     }
        // }

        if (numaPerETHmulAmount > _numaPerEthVault)
        {
            numaPerETHmulAmount = _numaPerEthVault;
        }

        uint256 tokensForAmount = nuAManager.getPriceInEth(_nuAsset,numaPerETHmulAmount);

        return tokensForAmount;
    }


    function getNbOfNuAsset(
        uint256 _numaAmount,
        address _nuAsset,
        address _numaPool,
        address _converter,
        uint    _EthPerNumaVault
    ) external view returns (uint256) 
    {

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

        uint256 EthPerNuma = (
            numerator == sqrtPriceX96 ?
                FullMath.mulDivRoundingUp(
                    FullMath.mulDivRoundingUp(denominator, denominator*10**IERC20Metadata(token).decimals() , numerator),
                    _numaAmount,
                    numerator * 10**18// numa decimals
            ) 
            : FullMath.mulDivRoundingUp(
                FullMath.mulDivRoundingUp(denominator, denominator * 10**18, numerator),// numa decimals
                _numaAmount,
                numerator* 10**IERC20Metadata(token).decimals()
            )
        );

        if (_converter != address(0))
        {
            EthPerNuma = INumaTokenToEthConverter(_converter).convertTokenPerNumaToEthPerNuma(EthPerNuma);//,0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3,1000*86400,0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612,1000*86400) ;
        }



        if (EthPerNuma > _EthPerNumaVault)
        {
            EthPerNuma = _EthPerNumaVault;
        }

        uint256 tokensForAmount = nuAManager.getTokenPerEth(_nuAsset,EthPerNuma);
        return tokensForAmount;
    }



    function getNbOfAssetneeded(
        uint256 _amountNumaOut,
        address _nuAsset,
        address _numaPool,
        address _converter,
        uint _EthPerNumaVault

    ) external view returns (uint256) 
    {
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


        uint256 EthPerNuma = (
            numerator == sqrtPriceX96 ?
            FullMath.mulDivRoundingUp(
                    FullMath.mulDivRoundingUp(denominator, denominator*10**IERC20Metadata(token).decimals() , numerator),
                    _amountNumaOut,
                    numerator * 10**18// numa decimals
            ) 
            : FullMath.mulDivRoundingUp(
                FullMath.mulDivRoundingUp(denominator, denominator * 10**18, numerator),// numa decimals
                _amountNumaOut,
                numerator* 10**IERC20Metadata(token).decimals()
            )
        );

        if (_converter != address(0))
        {
            EthPerNuma = INumaTokenToEthConverter(_converter).convertTokenPerNumaToEthPerNuma(EthPerNuma);//,0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3,1000*86400,0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612,1000*86400) ;
        }


 
        // check that numa price is within vault's price bounds to prevent price manipulation
        // if (address(numaPrice) != address(0)) {
        //     // do it only if we specified a contract that can give us numa price
        //     uint256 EthPerNumaVault = numaPrice.GetNumaPriceEth(
        //         _amountNumaOut
        //     );


        //     (uint16 sellfee,) = numaPrice.getSellFee();
        //     EthPerNumaVault = (EthPerNumaVault * sellfee) /1000;

        //     if (EthPerNuma < EthPerNumaVault) 
        //     {
        //          // clip price
        //         EthPerNuma = EthPerNumaVault;
        //         //revert("numa price out of vault's bounds");
        //     }
        // }

        if (EthPerNuma < _EthPerNumaVault)
        {
            EthPerNuma = _EthPerNumaVault;
        }

        uint256 tokensForAmount = nuAManager.getTokenPerEthRoundUp(_nuAsset,EthPerNuma);
        return tokensForAmount;
    }

   
}
