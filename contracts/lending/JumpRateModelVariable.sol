// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "./InterestRateModel.sol";
import "@openzeppelin/contracts_5.0.2/access/Ownable.sol";

/**
 * @title Compound's JumpRateModel Contract V3
 * @author Compound (modified by Dharma Labs)
 * @notice Version 2 modifies Version 1 by enabling updateable parameters.
 * @notice Version 3 includes Ownable and have updatable blocksPerYear.
 * @notice Version 4 moves blocksPerYear to the constructor.
 */
contract JumpRateModelVariable is InterestRateModel, Ownable {
    //event NewInterestParams(uint baseRatePerBlock, uint multiplierPerBlock, uint jumpMultiplierPerBlock, uint kink);

    /**
     * @notice The approximate number of blocks per year that is assumed by the interest rate model
     */
    uint public blocksPerYear;

    // Utilization Settings
    /// @notice The minimum utilization wherein no adjustment to full utilization and vertex rates occurs
    uint256 public immutable MIN_TARGET_UTIL;
    /// @notice The maximum utilization wherein no adjustment to full utilization and vertex rates occurs
    uint256 public immutable MAX_TARGET_UTIL;
    /// @notice The utilization at which the slope increases
    uint256 public immutable VERTEX_UTILIZATION;
    /// @notice precision of utilization calculations
    uint256 public constant UTIL_PREC = 1e18; // 18 decimals

    // Interest Rate Settings (all rates are per block)
    /// @notice The minimum interest rate (per block) when utilization is 100%
    uint256 public immutable MIN_FULL_UTIL_RATE; // 18 decimals
    /// @notice The maximum interest rate (per block) when utilization is 100%
    uint256 public immutable MAX_FULL_UTIL_RATE; // 18 decimals
    /// @notice The interest rate (per second) when utilization is 0%
    uint256 public immutable ZERO_UTIL_RATE; // 18 decimals
    /// @notice The interest rate half life in seconds, determines rate of adjustments to rate curve
    uint256 public immutable RATE_HALF_LIFE; // 1 decimals
    /// @notice The percent of the delta between max and min
    uint256 public immutable VERTEX_RATE_PERCENT; // 18 decimals
    /// @notice The precision of interest rate calculations
    uint256 public constant RATE_PREC = 1e18; // 18 decimals

    /**
     * @notice A name for user-friendliness, e.g. WBTC
     */
    string public name;

    /// @notice The ```constructor``` function
    /// @param _name The name of the contract name
    /// @param _vertexUtilization The utilization at which the slope increases
    /// @param _vertexRatePercentOfDelta The percent of the delta between max and min, defines vertex rate
    /// @param _minUtil The minimum utilization wherein no adjustment to full utilization and vertex rates occurs
    /// @param _maxUtil The maximum utilization wherein no adjustment to full utilization and vertex rates occurs
    /// @param _zeroUtilizationRate The interest rate (per second) when utilization is 0%
    /// @param _minFullUtilizationRate The minimum interest rate at 100% utilization
    /// @param _maxFullUtilizationRate The maximum interest rate at 100% utilization
    /// @param _rateHalfLife The half life parameter for interest rate adjustments
    constructor(
        string memory _name,
        uint256 _vertexUtilization,
        uint256 _vertexRatePercentOfDelta,
        uint256 _minUtil,
        uint256 _maxUtil,
        uint256 _zeroUtilizationRate,
        uint256 _minFullUtilizationRate,
        uint256 _maxFullUtilizationRate,
        uint256 _rateHalfLife,
        address _owner
    ) Ownable(_owner) {
        name = _name;
        MIN_TARGET_UTIL = _minUtil;
        MAX_TARGET_UTIL = _maxUtil;
        VERTEX_UTILIZATION = _vertexUtilization;
        ZERO_UTIL_RATE = _zeroUtilizationRate;
        MIN_FULL_UTIL_RATE = _minFullUtilizationRate;
        MAX_FULL_UTIL_RATE = _maxFullUtilizationRate;
        RATE_HALF_LIFE = _rateHalfLife;
        VERTEX_RATE_PERCENT = _vertexRatePercentOfDelta;
    }

    /**
     * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market (currently unused)
     * @return The utilization rate as a mantissa between [0, 1e18]
     */
    function utilizationRate(
        uint cash,
        uint borrows,
        uint reserves
    ) public pure override returns (uint) {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        return (borrows * 1e18) / (cash + borrows - reserves);
    }

    function getFullUtilizationInterest(
        uint256 _deltaTime,
        uint256 _utilization,
        uint256 _fullUtilizationInterest
    ) internal view returns (uint256 _newFullUtilizationInterest) {
        if (_utilization < MIN_TARGET_UTIL) {
            // 18 decimals
            uint256 _deltaUtilization = ((MIN_TARGET_UTIL - _utilization) *
                1e18) / MIN_TARGET_UTIL;
            // 36 decimals
            uint256 _decayGrowth = (RATE_HALF_LIFE * 1e36) +
                (_deltaUtilization * _deltaUtilization * _deltaTime);
            // 18 decimals
            _newFullUtilizationInterest = ((_fullUtilizationInterest *
                (RATE_HALF_LIFE * 1e36)) / _decayGrowth);
        } else if (_utilization > MAX_TARGET_UTIL) {
            // 18 decimals
            uint256 _deltaUtilization = ((_utilization - MAX_TARGET_UTIL) *
                1e18) / (UTIL_PREC - MAX_TARGET_UTIL);
            // 36 decimals
            uint256 _decayGrowth = (RATE_HALF_LIFE * 1e36) +
                (_deltaUtilization * _deltaUtilization * _deltaTime);
            // 18 decimals
            _newFullUtilizationInterest = ((_fullUtilizationInterest *
                _decayGrowth) / (RATE_HALF_LIFE * 1e36));
        } else {
            _newFullUtilizationInterest = _fullUtilizationInterest;
        }
        if (_newFullUtilizationInterest > MAX_FULL_UTIL_RATE) {
            _newFullUtilizationInterest = (MAX_FULL_UTIL_RATE);
        } else if (_newFullUtilizationInterest < MIN_FULL_UTIL_RATE) {
            _newFullUtilizationInterest = (MIN_FULL_UTIL_RATE);
        }
    }

    /**
     * @notice Calculates the current borrow rate per block, with the error code expected by the market
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @param _OldfullUtilizationRate current full utilization rate
     * @return _newRatePerBlock The borrow rate percentage per block as a mantissa (scaled by 1e18)
     */
    function getBorrowRate(
        uint cash,
        uint borrows,
        uint reserves,
        uint deltaTime,
        uint _OldfullUtilizationRate
    )
        public
        view
        override
        returns (uint256 _newRatePerBlock, uint256 _newFullUtilizationInterest)
    {
        uint _utilization = utilizationRate(cash, borrows, reserves);

        _newFullUtilizationInterest = getFullUtilizationInterest(
            deltaTime,
            _utilization,
            _OldfullUtilizationRate
        );

        // _vertexInterest is calculated as the percentage of the delta between min and max interest
        uint256 _vertexInterest = (((_newFullUtilizationInterest -
            ZERO_UTIL_RATE) * VERTEX_RATE_PERCENT) / RATE_PREC) +
            ZERO_UTIL_RATE;

        if (_utilization <= VERTEX_UTILIZATION) {
            // For readability, the following formula is equivalent to:
            // uint256 _slope = ((_vertexInterest - ZERO_UTIL_RATE) * UTIL_PREC) / VERTEX_UTILIZATION;
            // _newRatePerSec = uint64(ZERO_UTIL_RATE + ((_utilization * _slope) / UTIL_PREC));

            // 18 decimals
            _newRatePerBlock = (ZERO_UTIL_RATE +
                (_utilization * (_vertexInterest - ZERO_UTIL_RATE)) /
                VERTEX_UTILIZATION);
        } else {
            // For readability, the following formula is equivalent to:
            // uint256 _slope = (((_newFullUtilizationInterest - _vertexInterest) * UTIL_PREC) / (UTIL_PREC - VERTEX_UTILIZATION));
            // _newRatePerSec = uint64(_vertexInterest + (((_utilization - VERTEX_UTILIZATION) * _slope) / UTIL_PREC));

            // 18 decimals
            _newRatePerBlock = (_vertexInterest +
                ((_utilization - VERTEX_UTILIZATION) *
                    (_newFullUtilizationInterest - _vertexInterest)) /
                (UTIL_PREC - VERTEX_UTILIZATION));
        }
    }

    /**
     * @notice Calculates the current supply rate per block
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @param reserveFactorMantissa The current reserve factor for the market
     * @return The supply rate percentage per block as a mantissa (scaled by 1e18)
     */
    function getSupplyRate(
        uint cash,
        uint borrows,
        uint reserves,
        uint reserveFactorMantissa,
        uint deltaTime,
        uint fullUtilizationRate
    ) public view override returns (uint) {
        uint oneMinusReserveFactor = 1e18 - reserveFactorMantissa;
        (uint borrowRate, ) = getBorrowRate(
            cash,
            borrows,
            reserves,
            deltaTime,
            fullUtilizationRate
        );
        uint rateToPool = (borrowRate * oneMinusReserveFactor) / 1e18;
        return (utilizationRate(cash, borrows, reserves) * rateToPool) / 1e18;
    }
}
