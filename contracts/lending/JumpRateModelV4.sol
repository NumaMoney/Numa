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
contract JumpRateModelV4 is InterestRateModel, Ownable {
    event NewInterestParams(
        uint baseRatePerBlock,
        uint multiplierPerBlock,
        uint jumpMultiplierPerBlock,
        uint kink
    );

    /**
     * @notice The approximate number of blocks per year that is assumed by the interest rate model
     */
    uint public blocksPerYear;

    /**
     * @notice The multiplier of utilization rate that gives the slope of the interest rate
     */
    uint public multiplierPerBlock;

    /**
     * @notice The base interest rate which is the y-intercept when utilization rate is 0
     */
    uint public baseRatePerBlock;

    /**
     * @notice The multiplierPerBlock after hitting a specified utilization point
     */
    uint public jumpMultiplierPerBlock;

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
    constructor(
        uint blocksPerYear_,
        uint baseRatePerYear,
        uint multiplierPerYear,
        uint jumpMultiplierPerYear,
        uint kink_,
        address owner_,
        string memory name_
    ) Ownable(owner_) {
        blocksPerYear = blocksPerYear_;
        name = name_;
        updateJumpRateModelInternal(
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink_
        );
    }

    /**
     * @notice Update the parameters of the interest rate model (only callable by owner, i.e. Timelock)
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
     * @param kink_ The utilization point at which the jump multiplier is applied
     */
    function updateJumpRateModel(
        uint baseRatePerYear,
        uint multiplierPerYear,
        uint jumpMultiplierPerYear,
        uint kink_
    ) external onlyOwner {
        updateJumpRateModelInternal(
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink_
        );
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

    /**
     * @notice Updates the blocksPerYear in order to make interest calculations simpler
     * @param blocksPerYear_ The new estimated eth blocks per year.
     */
    function updateBlocksPerYear(uint blocksPerYear_) external onlyOwner {
        blocksPerYear = blocksPerYear_;
    }

    /**
     * @notice Calculates the current borrow rate per block, with the error code expected by the market
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @param deltaTime deltaTime since last update
     * @param _OldfullUtilizationRate fullUtilizationRate at last update
     * @return newRatePerBlock The borrow rate percentage per block as a mantissa (scaled by 1e18)
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
        returns (uint newRatePerBlock, uint newFullUtilizationInterest)
    {
        uint util = utilizationRate(cash, borrows, reserves);

        if (util <= kink) {
            newRatePerBlock =
                ((util * multiplierPerBlock) / 1e18) +
                baseRatePerBlock;
        } else {
            uint normalRate = ((kink * multiplierPerBlock) / 1e18) +
                baseRatePerBlock;
            uint excessUtil = util - kink;
            newRatePerBlock =
                ((excessUtil * jumpMultiplierPerBlock) / 1e18) +
                normalRate;
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

    /**
     * @notice Internal function to update the parameters of the interest rate model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by 1e18)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by 1e18)
     * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
     * @param kink_ The utilization point at which the jump multiplier is applied
     */
    function updateJumpRateModelInternal(
        uint baseRatePerYear,
        uint multiplierPerYear,
        uint jumpMultiplierPerYear,
        uint kink_
    ) internal {
        baseRatePerBlock = baseRatePerYear / blocksPerYear;
        multiplierPerBlock =
            (multiplierPerYear * 1e18) /
            (blocksPerYear * kink_);
        jumpMultiplierPerBlock = jumpMultiplierPerYear / blocksPerYear;
        kink = kink_;

        emit NewInterestParams(
            baseRatePerBlock,
            multiplierPerBlock,
            jumpMultiplierPerBlock,
            kink
        );
    }
}
