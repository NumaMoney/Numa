// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "./InterestRateModel.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";
/**
  * @title Compound's JumpRateModel Contract V3
  * @author Compound (modified by Dharma Labs)
  * @notice Version 2 modifies Version 1 by enabling updateable parameters.
  * @notice Version 3 includes Ownable and have updatable blocksPerYear.
  * @notice Version 4 moves blocksPerYear to the constructor.
  */
contract JumpRateModelVariable is InterestRateModel, Ownable {


    event NewInterestParams(uint baseRatePerBlock, uint multiplierPerBlock, uint jumpMultiplierPerBlock, uint kink);

    /**
     * @notice The approximate number of blocks per year that is assumed by the interest rate model
     */
    uint public blocksPerYear;

    /**
     * @notice The multiplier of utilization rate that gives the slope of the interest rate
     */
    //uint public multiplierPerBlock;

    /**
     * @notice The base interest rate which is the y-intercept when utilization rate is 0
     */
    uint public baseRatePerBlock;

    /**
     * @notice The multiplierPerBlock after hitting a specified utilization point
     */
    //uint public jumpMultiplierPerBlock;

    /**
     * @notice The utilization point at which the jump multiplier is applied
     */
    uint public kink;

    /**
     * @notice A name for user-friendliness, e.g. WBTC
     */
    string public name;

    /**
     * @notice Construct an interest rate model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
     * @param kink_ The utilization point at which the jump multiplier is applied
     * @param owner_ Sets the owner of the contract to someone other than msgSender
     * @param name_ User-friendly name for the new contract
     */
    constructor(uint blocksPerYear_, uint baseRatePerYear, uint multiplierPerYear, uint jumpMultiplierPerYear, uint kink_, 
            address owner_, string memory name_) Ownable(owner_)
    {
        blocksPerYear = blocksPerYear_;
        name = name_;
        updateJumpRateModelInternal(baseRatePerYear,  multiplierPerYear, jumpMultiplierPerYear, kink_);
    }

    /**
     * @notice Update the parameters of the interest rate model (only callable by owner, i.e. Timelock)
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
     * @param kink_ The utilization point at which the jump multiplier is applied
     */
    function updateJumpRateModel(uint baseRatePerYear, uint multiplierPerYear, uint jumpMultiplierPerYear, uint kink_) external onlyOwner {
        updateJumpRateModelInternal(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink_);
    }

    /**
     * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market (currently unused)
     * @return The utilization rate as a mantissa between [0, 1e18]
     */
    function utilizationRate(uint cash, uint borrows, uint reserves) public override pure returns (uint) 
    {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        return borrows * 1e18 / (cash + borrows - reserves);
    }
    
    /**
     * @notice Updates the blocksPerYear in order to make interest calculations simpler
     * @param blocksPerYear_ The new estimated eth blocks per year.
     */
    function updateBlocksPerYear(uint blocksPerYear_) external onlyOwner {
        blocksPerYear = blocksPerYear_;
    }


    function getFullUtilizationInterest(
        uint256 _deltaTime,
        uint256 _utilization,
        uint64 _fullUtilizationInterest
    ) internal view returns (uint64 _newFullUtilizationInterest) {

        // TODO: contract parameters
//         MIN_TARGET_UTIL The minimum utilization wherein no adjustment to full utilization and vertex rates occurs
// MAX_TARGET_UTIL The maximum utilization wherein no adjustment to full utilization and vertex rates occurs

// RATE_HALF_LIFE The half life parameter for interest rate adjustments

// MIN_FULL_UTIL_RATE _minFullUtilizationRate The minimum interest rate at 100% utilization
// MAX_FULL_UTIL_RATE _maxFullUtilizationRate The maximum interest rate at 100% utilization

        uint MIN_TARGET_UTIL;
 uint MAX_TARGET_UTIL;

 uint RATE_HALF_LIFE;

 uint MIN_FULL_UTIL_RATE;
 uint MAX_FULL_UTIL_RATE;
uint UTIL_PREC;

        if (_utilization < MIN_TARGET_UTIL) {
            // 18 decimals
            uint256 _deltaUtilization = ((MIN_TARGET_UTIL - _utilization) * 1e18) / MIN_TARGET_UTIL;
            // 36 decimals
            uint256 _decayGrowth = (RATE_HALF_LIFE * 1e36) + (_deltaUtilization * _deltaUtilization * _deltaTime);
            // 18 decimals
            _newFullUtilizationInterest = uint64((_fullUtilizationInterest * (RATE_HALF_LIFE * 1e36)) / _decayGrowth);
        } else if (_utilization > MAX_TARGET_UTIL) {
            // 18 decimals
            uint256 _deltaUtilization = ((_utilization - MAX_TARGET_UTIL) * 1e18) / (UTIL_PREC - MAX_TARGET_UTIL);
            // 36 decimals
            uint256 _decayGrowth = (RATE_HALF_LIFE * 1e36) + (_deltaUtilization * _deltaUtilization * _deltaTime);
            // 18 decimals
            _newFullUtilizationInterest = uint64((_fullUtilizationInterest * _decayGrowth) / (RATE_HALF_LIFE * 1e36));
        } else {
            _newFullUtilizationInterest = _fullUtilizationInterest;
        }
        if (_newFullUtilizationInterest > MAX_FULL_UTIL_RATE) {
            _newFullUtilizationInterest = uint64(MAX_FULL_UTIL_RATE);
        } else if (_newFullUtilizationInterest < MIN_FULL_UTIL_RATE) {
            _newFullUtilizationInterest = uint64(MIN_FULL_UTIL_RATE);
        }
    }


    /**
     * @notice Calculates the current borrow rate per block, with the error code expected by the market
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The borrow rate percentage per block as a mantissa (scaled by 1e18)
     */
    function getBorrowRate(uint cash, uint borrows, uint reserves,uint deltaTime,uint currentInterestRateMultiplier,uint currentInterestRateJumpMultiplier) public override view returns (uint,uint,uint) 
    {
        uint util = utilizationRate(cash, borrows, reserves);

        // compute current MaxRate/VertexRate from multiplierPerBlock/jumpMultiplierPerBlock
        // (vertexRate - baseRate)/kink = multiplierPerBlock
        // (maxRate - VertexRate)/(1 - kink) = jumpMultiplierPerBlock
        uint64 vertexRatePerBlock = uint64(kink * multiplierPerBlock + baseRatePerBlock);
        uint64 maxRatePerBlock = uint64(jumpMultiplierPerBlock * (1-kink)) +vertexRatePerBlock;
        // compute vertex_rate_percent from multiplier and jumpMultiplier
        // TODO: should be done at init because it's immutable
        // uint256 _vertexInterest = (((_newmaxRatePerBlock - ZERO_UTIL_RATE) * VERTEX_RATE_PERCENT) / RATE_PREC) +
        //     ZERO_UTIL_RATE;
        // vertexRatePerBlock = baseRatePerBlock + (maxRatePerBlock - baseRatePerBlock)* VERTEX_RATE_PERCENT;
        // --> VERTEX_RATE_PERCENT = (vertexRatePerBlock - baseRatePerBlock)/(maxRatePerBlock - baseRatePerBlock);
        // --> VERTEX_RATE_PERCENT = kink * multiplierPerBlock/(jumpMultiplierPerBlock * (1-kink) + kink * multiplierPerBlock)
        uint VERTEX_RATE_PERCENT = kink * multiplierPerBlock/(jumpMultiplierPerBlock * (1-kink) + kink * multiplierPerBlock);

        // DISABLED FOR NOW
        uint _newmaxRatePerBlock = maxRatePerBlock;
        //uint _newmaxRatePerBlock = getFullUtilizationInterest(deltaTime, util, maxRatePerBlock);



        // _vertexInterest is calculated as the percentage of the delta between min and max interest
        // uint256 _vertexInterest = (((_newmaxRatePerBlock - ZERO_UTIL_RATE) * VERTEX_RATE_PERCENT) / RATE_PREC) +
        //     ZERO_UTIL_RATE;
        uint _newVertexRatePerBlock = baseRatePerBlock + (maxRatePerBlock - baseRatePerBlock)* VERTEX_RATE_PERCENT;

        // then deduce multiplierPerBlock & jumpMultiplierPerBlock
        uint newMultiplierPerBlock = (_newVertexRatePerBlock - baseRatePerBlock)/kink;
        uint newJumpMultiplierPerBlock = (_newmaxRatePerBlock - _newVertexRatePerBlock)/(1 - kink);

        uint newRate;
        if (util <= kink) {
            newRate = (util * newMultiplierPerBlock / 1e18) + baseRatePerBlock;
        } else {
           
            uint normalRate = (kink * newMultiplierPerBlock / 1e18) + baseRatePerBlock;
            uint excessUtil = util - kink;
      

            newRate = (excessUtil * newJumpMultiplierPerBlock/ 1e18) + normalRate;
        }
        return (newRate,newMultiplierPerBlock,newJumpMultiplierPerBlock);
    }

    /**
     * @notice Calculates the current supply rate per block
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @param reserveFactorMantissa The current reserve factor for the market
     * @return The supply rate percentage per block as a mantissa (scaled by 1e18)
     */
    function getSupplyRate(uint cash, uint borrows, uint reserves, uint reserveFactorMantissa,uint deltaTime,uint currentInterestRateMultiplier,uint currentInterestRateJumpMultiplier) public override view returns (uint) {
        uint oneMinusReserveFactor = 1e18 - reserveFactorMantissa;
        (uint borrowRate,,) = getBorrowRate(cash, borrows, reserves,deltaTime,currentInterestRateMultiplier,currentInterestRateJumpMultiplier);
        uint rateToPool = borrowRate * oneMinusReserveFactor / 1e18;
        console.log("supply rate");
        console.logUint(rateToPool);
        return utilizationRate(cash, borrows, reserves) * rateToPool / 1e18;
    }

    /**
     * @notice Internal function to update the parameters of the interest rate model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
     * @param kink_ The utilization point at which the jump multiplier is applied
     */
    function updateJumpRateModelInternal(uint baseRatePerYear, uint multiplierPerYear, uint jumpMultiplierPerYear, uint kink_) internal {

        baseRatePerBlock = baseRatePerYear / blocksPerYear;
        multiplierPerBlock = (multiplierPerYear * 1e18) / (blocksPerYear * kink_);
        jumpMultiplierPerBlock = jumpMultiplierPerYear / blocksPerYear;
        kink = kink_;

        console.log("update parameter model");
        console.logUint(multiplierPerBlock);
        console.logUint(jumpMultiplierPerBlock);
        

        emit NewInterestParams(baseRatePerBlock, multiplierPerBlock, jumpMultiplierPerBlock, kink);

    }
}