// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "./CToken.sol";

abstract contract PriceOracleCollateralBorrow {
    /// @notice Indicator that this is a PriceOracle contract (for inspection)
    bool public constant isPriceOracle = true;

    /**
     * @notice Get the underlying price of a cToken asset
     * @param cToken The cToken to get the underlying price of
     * @return The underlying asset price mantissa (scaled by 1e18).
     *  Zero means the price is unavailable.
     */
    function getUnderlyingPriceAsCollateral(
        CToken cToken
    ) external view virtual returns (uint);
    function getUnderlyingPriceAsBorrowed(
        CToken cToken
    ) external view virtual returns (uint);
}
