// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "../CErc20.sol";
import "../CToken.sol";
import "../PriceOracleCollateralBorrow.sol";
import "../EIP20Interface.sol";

interface ComptrollerLensInterface {
    function markets(address) external view returns (bool, uint);
    function oracle() external view returns (PriceOracleCollateralBorrow);
    //function getAccountLiquidity(address) external view returns (uint, uint, uint,uint);
    function getAccountLiquidityIsolate(
        address,
        CToken,
        CToken
    ) external view returns (uint, uint, uint, uint);
    function getAssetsIn(address) external view returns (CToken[] memory);
    function borrowCaps(address) external view returns (uint);
}

contract CompoundLens {
    struct CTokenMetadata {
        address cToken;
        uint exchangeRateCurrent;
        uint supplyRatePerBlock;
        uint borrowRatePerBlock;
        uint reserveFactorMantissa;
        uint totalBorrows;
        uint totalReserves;
        uint totalSupply;
        uint totalCash;
        bool isListed;
        uint collateralFactorMantissa;
        address underlyingAssetAddress;
        uint cTokenDecimals;
        uint underlyingDecimals;
        uint borrowCap;
    }

    function cTokenMetadata(
        CToken cToken
    ) public returns (CTokenMetadata memory) {
        uint exchangeRateCurrent = cToken.exchangeRateCurrent();
        ComptrollerLensInterface comptroller = ComptrollerLensInterface(
            address(cToken.comptroller())
        );
        (bool isListed, uint collateralFactorMantissa) = comptroller.markets(
            address(cToken)
        );
        address underlyingAssetAddress;
        uint underlyingDecimals;

        if (compareStrings(cToken.symbol(), "cETH")) {
            underlyingAssetAddress = address(0);
            underlyingDecimals = 18;
        } else {
            CErc20 cErc20 = CErc20(address(cToken));
            underlyingAssetAddress = cErc20.underlying();
            underlyingDecimals = EIP20Interface(cErc20.underlying()).decimals();
        }

        uint borrowCap = 0;
        (bool borrowCapSuccess, bytes memory borrowCapReturnData) = address(
            comptroller
        ).call(
                abi.encodePacked(
                    comptroller.borrowCaps.selector,
                    abi.encode(address(cToken))
                )
            );
        if (borrowCapSuccess) {
            borrowCap = abi.decode(borrowCapReturnData, (uint));
        }

        return
            CTokenMetadata({
                cToken: address(cToken),
                exchangeRateCurrent: exchangeRateCurrent,
                supplyRatePerBlock: cToken.supplyRatePerBlock(),
                borrowRatePerBlock: cToken.borrowRatePerBlock(),
                reserveFactorMantissa: cToken.reserveFactorMantissa(),
                totalBorrows: cToken.totalBorrows(),
                totalReserves: cToken.totalReserves(),
                totalSupply: cToken.totalSupply(),
                totalCash: cToken.getCash(),
                isListed: isListed,
                collateralFactorMantissa: collateralFactorMantissa,
                underlyingAssetAddress: underlyingAssetAddress,
                cTokenDecimals: cToken.decimals(),
                underlyingDecimals: underlyingDecimals,
                borrowCap: borrowCap
            });
    }

    function cTokenMetadataAll(
        CToken[] calldata cTokens
    ) external returns (CTokenMetadata[] memory) {
        uint cTokenCount = cTokens.length;
        CTokenMetadata[] memory res = new CTokenMetadata[](cTokenCount);
        for (uint i = 0; i < cTokenCount; i++) {
            res[i] = cTokenMetadata(cTokens[i]);
        }
        return res;
    }

    struct CTokenBalances {
        address cToken;
        uint balanceOf;
        uint borrowBalanceCurrent;
        uint balanceOfUnderlying;
        uint tokenBalance;
        uint tokenAllowance;
    }

    function cTokenBalances(
        CToken cToken,
        address payable account
    ) public returns (CTokenBalances memory) {
        uint balanceOf = cToken.balanceOf(account);
        uint borrowBalanceCurrent = cToken.borrowBalanceCurrent(account);
        uint balanceOfUnderlying = cToken.balanceOfUnderlying(account);
        uint tokenBalance;
        uint tokenAllowance;

        if (compareStrings(cToken.symbol(), "cETH")) {
            tokenBalance = account.balance;
            tokenAllowance = account.balance;
        } else {
            CErc20 cErc20 = CErc20(address(cToken));
            EIP20Interface underlying = EIP20Interface(cErc20.underlying());
            tokenBalance = underlying.balanceOf(account);
            tokenAllowance = underlying.allowance(account, address(cToken));
        }

        return
            CTokenBalances({
                cToken: address(cToken),
                balanceOf: balanceOf,
                borrowBalanceCurrent: borrowBalanceCurrent,
                balanceOfUnderlying: balanceOfUnderlying,
                tokenBalance: tokenBalance,
                tokenAllowance: tokenAllowance
            });
    }

    function cTokenBalancesAll(
        CToken[] calldata cTokens,
        address payable account
    ) external returns (CTokenBalances[] memory) {
        uint cTokenCount = cTokens.length;
        CTokenBalances[] memory res = new CTokenBalances[](cTokenCount);
        for (uint i = 0; i < cTokenCount; i++) {
            res[i] = cTokenBalances(cTokens[i], account);
        }
        return res;
    }

    struct CTokenUnderlyingPrice {
        address cToken;
        uint underlyingPriceAsBorrow;
        uint underlyingPriceAsCollateral;
    }

    function cTokenUnderlyingPrice(
        CNumaToken cToken
    ) public view returns (CTokenUnderlyingPrice memory) {
        ComptrollerLensInterface comptroller = ComptrollerLensInterface(
            address(cToken.comptroller())
        );
        PriceOracleCollateralBorrow priceOracle = comptroller.oracle();

        return
            CTokenUnderlyingPrice({
                cToken: address(cToken),
                underlyingPriceAsBorrow: priceOracle
                    .getUnderlyingPriceAsBorrowed(cToken),
                underlyingPriceAsCollateral: priceOracle
                    .getUnderlyingPriceAsCollateral(cToken)
            });
    }

    function cTokenUnderlyingPriceAll(
        CNumaToken[] calldata cTokens
    ) external returns (CTokenUnderlyingPrice[] memory) {
        uint cTokenCount = cTokens.length;
        CTokenUnderlyingPrice[] memory res = new CTokenUnderlyingPrice[](
            cTokenCount
        );
        for (uint i = 0; i < cTokenCount; i++) {
            res[i] = cTokenUnderlyingPrice(cTokens[i]);
        }
        return res;
    }

    struct AccountLimits {
        CToken[] markets;
        uint liquidity;
        uint shortfall;
        uint badDebt;
    }

    // function getAccountLimits(ComptrollerLensInterface comptroller, address account) public view returns (AccountLimits memory) {
    //     (uint errorCode, uint liquidity, uint shortfall,uint badDebt) = comptroller.getAccountLiquidity(account);
    //     require(errorCode == 0);

    //     return AccountLimits({
    //         markets: comptroller.getAssetsIn(account),
    //         liquidity: liquidity,
    //         shortfall: shortfall,
    //         badDebt: badDebt
    //     });
    // }

    function getAccountLimits(
        ComptrollerLensInterface comptroller,
        address account,
        CToken collateral,
        CToken borrow
    ) public view returns (AccountLimits memory) {
        (
            uint errorCode,
            uint liquidity,
            uint shortfall,
            uint badDebt
        ) = comptroller.getAccountLiquidityIsolate(account, collateral, borrow);
        require(errorCode == 0);

        return
            AccountLimits({
                markets: comptroller.getAssetsIn(account),
                liquidity: liquidity,
                shortfall: shortfall,
                badDebt: badDebt
            });
    }

    function compareStrings(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) ==
            keccak256(abi.encodePacked((b))));
    }

    function add(
        uint a,
        uint b,
        string memory errorMessage
    ) internal pure returns (uint) {
        uint c = a + b;
        require(c >= a, errorMessage);
        return c;
    }

    function sub(
        uint a,
        uint b,
        string memory errorMessage
    ) internal pure returns (uint) {
        require(b <= a, errorMessage);
        uint c = a - b;
        return c;
    }
}
