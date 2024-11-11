// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "../../lending/PriceOracleCollateralBorrow.sol";
import "../../lending/CErc20.sol";

contract SimplePriceOracle is PriceOracleCollateralBorrow {
    mapping(address => uint) prices;
    event PricePosted(
        address asset,
        uint previousPriceMantissa,
        uint requestedPriceMantissa,
        uint newPriceMantissa
    );

    function _getUnderlyingAddress(
        CToken cToken
    ) private view returns (address) {
        address asset;
        if (compareStrings(cToken.symbol(), "cETH")) {
            asset = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        } else {
            asset = address(CErc20(address(cToken)).underlying());
        }
        return asset;
    }

    function getUnderlyingPrice(CToken cToken) public view returns (uint) {
        return prices[_getUnderlyingAddress(cToken)];
    }

    function getUnderlyingPriceAsCollateral(
        CNumaToken cToken
    ) public view override returns (uint) {
        return getUnderlyingPrice(cToken);
    }

    function getUnderlyingPriceAsBorrowed(
        CNumaToken cToken
    ) public view override returns (uint) {
        return getUnderlyingPrice(cToken);
    }

    function setUnderlyingPrice(
        CToken cToken,
        uint underlyingPriceMantissa
    ) public {
        address asset = _getUnderlyingAddress(cToken);
        emit PricePosted(
            asset,
            prices[asset],
            underlyingPriceMantissa,
            underlyingPriceMantissa
        );
        prices[asset] = underlyingPriceMantissa;
    }

    function setDirectPrice(address asset, uint price) public {
        emit PricePosted(asset, prices[asset], price, price);
        prices[asset] = price;
    }

    // v1 price oracle interface for use as backing of proxy
    function assetPrices(address asset) external view returns (uint) {
        return prices[asset];
    }

    function compareStrings(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) ==
            keccak256(abi.encodePacked((b))));
    }
}
