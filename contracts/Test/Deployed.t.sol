// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/console2.sol";
//
import "../interfaces/IVaultManager.sol";
import "../NumaProtocol/NumaOracle.sol";
//
import "./uniV3Interfaces/ISwapRouter.sol";

//
import "./utils/ExtendedTest.sol";

import "../lending/CNumaToken.sol";
import "../lending/NumaComptroller.sol";
import "../lending/NumaPriceOracleNew.sol";
import "../lending/ExponentialNoError.sol";
contract DeployedTest is ExtendedTest, ExponentialNoError
{
        enum ErrorDBG {
        NO_ERROR,
        UNAUTHORIZED,
        COMPTROLLER_MISMATCH,
        INSUFFICIENT_SHORTFALL,
        INSUFFICIENT_BADDEBT,
        INSUFFICIENT_LIQUIDITY,
        INVALID_CLOSE_FACTOR,
        INVALID_COLLATERAL_FACTOR,
        INVALID_LIQUIDATION_INCENTIVE,
        MARKET_NOT_ENTERED, // no longer possible
        MARKET_NOT_LISTED,
        MARKET_ALREADY_LISTED,
        MATH_ERROR,
        NONZERO_BORROW_BALANCE,
        PRICE_ERROR,
        REJECTION,
        SNAPSHOT_ERROR,
        TOO_MANY_ASSETS,
        TOO_MUCH_REPAY,
        BAD_DEBT
    }


    CNumaToken cnuma;
    CNumaToken clst;
    NumaComptroller comptroller;
    IERC20 numa;
    NumaPriceOracleNew oracle;
    function setUp() public  {

        string memory SEPO_RPC_URL = vm.envString("URL4");
        uint256 sepoliaFork = vm.createFork(SEPO_RPC_URL);

        vm.selectFork(sepoliaFork);


        clst = CNumaToken(0x035e59E8124B2E77B621207D2343e0d0101E0437);
        cnuma = CNumaToken(0xBc5117cbe75CBB64D78aF8dA55caAd69D97D7987);

        comptroller = NumaComptroller(0x53240272db70D7dC64b8d431eaBd6e081A597076);
        numa = IERC20(0xf478F8dEDebe67cC095693A9d6778dEb3fb67FFe );
        oracle = NumaPriceOracleNew(0x17AFd8D5f4c5A5e89c49c2a58e5E3260AC10246a);
    }



    function getHypotheticalAccountLiquidityIsolateInternal(
        address account,
        CToken cTokenModify,
        uint redeemTokens,
        uint borrowAmount
    ) internal view returns (ErrorDBG, uint, uint, uint) {
        NumaComptroller.AccountLiquidityLocalVars memory vars; // Holds all our calculation results
        uint oErr;

        // this function is called from borrowallowed or redeemallowed so we should either have reddemTokens = 0 or
        // borrowAmount = 0
        require(
            ((redeemTokens == 0) || (borrowAmount == 0)),
            "redeem and borrow"
        );

        // cTokenModify = redeemed --> other token = borrowed
        // cTokenModify = borrowed --> other token = collateral
        // CToken otherToken;
        // CToken[] memory assets = accountAssets[account];
        // for (uint i = 0; i < assets.length; i++) {
        //     CToken asset = assets[i];
        //     if (address(asset) != address(cTokenModify)) {
        //         otherToken = asset;
        //         break;
        //     }
        // }

        // CNumaToken collateral = CNumaToken(address(cTokenModify));
        // CNumaToken borrow = CNumaToken(address(otherToken));

                CNumaToken collateral = CNumaToken(address(cnuma));
        CNumaToken borrow = CNumaToken(address(clst));


        // if (borrowAmount > 0) {
        //     collateral = CNumaToken(address(otherToken));
        //     borrow = CNumaToken(address(cTokenModify));
        // }

        // collateral
        if (
            address(collateral) != address(0)
        ) // might happen in borrow case without collateral
        {
            // Read the balances and exchange rate from the cToken
            (
                oErr,
                vars.cTokenBalance,
                vars.borrowBalance,
                vars.exchangeRateMantissa
            ) = collateral.getAccountSnapshot(account);
            if (oErr != 0) {
                // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
                return (ErrorDBG.SNAPSHOT_ERROR, 0, 0, 0);
            }
            vars.collateralFactor = Exp({
                mantissa: 0.95 ether
            });
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            // Get the normalized price of the asset
            vars.oraclePriceMantissaCollateral = oracle
                .getUnderlyingPriceAsCollateral(collateral);
            if (vars.oraclePriceMantissaCollateral == 0) {
                return (ErrorDBG.PRICE_ERROR, 0, 0, 0);
            }
            vars.oraclePriceCollateral = Exp({
                mantissa: vars.oraclePriceMantissaCollateral
            });

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            vars.tokensToDenomCollateral = mul_(
                mul_(vars.collateralFactor, vars.exchangeRate),
                vars.oraclePriceCollateral
            );
            vars.tokensToDenomCollateralNoCollateralFactor = mul_(
                vars.exchangeRate,
                vars.oraclePriceCollateral
            );
            // sumCollateral += tokensToDenom * cTokenBalance

            // NUMALENDING: use collateral price
            vars.sumCollateral = mul_ScalarTruncateAddUInt(
                vars.tokensToDenomCollateral,
                vars.cTokenBalance,
                vars.sumCollateral
            );
            vars.sumCollateralNoCollateralFactor = mul_ScalarTruncateAddUInt(
                vars.tokensToDenomCollateralNoCollateralFactor,
                vars.cTokenBalance,
                vars.sumCollateralNoCollateralFactor
            );
        }
        // borrow
        // Read the balances and exchange rate from the cToken
        if (
            address(borrow) != address(0)
        ) // might happen in redeem case if no borrow was made
        {
            (
                oErr,
                vars.cTokenBalance,
                vars.borrowBalance,
                vars.exchangeRateMantissa
            ) = borrow.getAccountSnapshot(account);
            if (oErr != 0) {
                // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
                return (ErrorDBG.SNAPSHOT_ERROR, 0, 0, 0);
            }

            vars.oraclePriceMantissaBorrowed = oracle
                .getUnderlyingPriceAsBorrowed(borrow);

            // AUDITV2FIX: missing current borrow balance update
            vars.oraclePriceBorrowed = Exp({
                mantissa: vars.oraclePriceMantissaBorrowed
            });
            vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(
                vars.oraclePriceBorrowed,
                vars.borrowBalance,
                vars.sumBorrowPlusEffects
            );

            if (vars.oraclePriceMantissaBorrowed == 0) {
                return (ErrorDBG.PRICE_ERROR, 0, 0, 0);
            }
        }

        // Calculate effects of interacting with cTokenModify
        vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(
            vars.tokensToDenomCollateral,
            redeemTokens,
            vars.sumBorrowPlusEffects
        );
        vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(
            vars.oraclePriceBorrowed,
            borrowAmount,
            vars.sumBorrowPlusEffects
        );

        // These are safe, as the underflow condition is checked first
        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            return (
                ErrorDBG.NO_ERROR,
                vars.sumCollateral - vars.sumBorrowPlusEffects,
                0,
                0
            );
        } else {
            if (
                vars.sumCollateralNoCollateralFactor > vars.sumBorrowPlusEffects
            ) {
                return (
                    ErrorDBG.NO_ERROR,
                    0,
                    vars.sumBorrowPlusEffects - vars.sumCollateral,
                    0
                );
            }
            // returning bad debt
            else
                return (
                    ErrorDBG.NO_ERROR,
                    0,
                    vars.sumBorrowPlusEffects - vars.sumCollateral,
                    vars.sumBorrowPlusEffects -
                        vars.sumCollateralNoCollateralFactor
                );
        }
    }

    function test_leverage() public  {



        console2.log("CF numa",comptroller.collateralFactor(cnuma)); 
console2.log("CF lst",comptroller.collateralFactor(clst)); 
        // Leverage test
        address drew = 0xB0D3221A1844950b74C4ac7af1fF934182E2c67d;
        vm.startPrank(drew);


        console2.log("numa long liquidity");
        (,uint liquidity,uint shortfall,uint badDebt) = comptroller
            .getAccountLiquidityIsolate(drew, cnuma, clst);

        console2.log("liquidity:", liquidity);
        console2.log("shortfall:", shortfall);
        console2.log("badDebt:", badDebt);


        console2.log("numa short liquidity");
        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(drew, clst,cnuma);

        console2.log("liquidity:", liquidity);
        console2.log("shortfall:", shortfall);
        console2.log("badDebt:", badDebt);


        // KO shortfall 
        // borrowAllowed(0x035e59E8124B2E77B621207D2343e0d0101E0437, 0xB0D3221A1844950b74C4ac7af1fF934182E2c67d, 136975394887693 
        //[1.369e14])
        // borrowing LST: 1.369e14 to pay for 


        // collat: 10000000000000000000 + FL 1000000000000000000
        // collat: 10 numa + FL 1 numa

        // borrow to repay 1 numa 
        // 1.369e14 = 0.0001369 reth;

        //clst.leverageStrategy(10000000000000000000,	1000000000000000000,cnuma,0);

        // TEST mint then borrow
        numa.approve(address(cnuma), 11000000000000000000);
        cnuma.mint( 11000000000000000000);


        cnuma.accrueInterest();
        clst.accrueInterest();


        console2.log("liquidity after deposit");
        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(drew, cnuma, clst);
        console2.log("liquidity:", liquidity);
        console2.log("shortfall:", shortfall);
        console2.log("badDebt:", badDebt);

        // liquidity = 996040322988601 = 9.96040322988601e14

        //clst.borrow(1.369e14);
        //clst.borrow(1.369e13);

        uint borrowAmount = 1.369e12;
        NumaComptroller.AccountLiquidityLocalVars memory vars; // Holds all our calculation results
        uint oErr;
        
                        // Read the balances and exchange rate from the cToken
            (
                oErr,
                vars.cTokenBalance,
                vars.borrowBalance,
                vars.exchangeRateMantissa
            ) = cnuma.getAccountSnapshot(drew);
          
            // vars.collateralFactor = Exp({
            //     mantissa: markets[address(cnuma)].collateralFactorMantissa
            // });

            //             vars.collateralFactor = Exp({
            //     mantissa: comptroller.markets()[address(cnuma)].collateralFactorMantissa
            // });

                                  vars.collateralFactor = Exp({
                mantissa: 0.95 ether
            });
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            // Get the normalized price of the asset
            vars.oraclePriceMantissaCollateral = oracle
                .getUnderlyingPriceAsCollateral(cnuma);
          

            vars.oraclePriceCollateral = Exp({
                mantissa: vars.oraclePriceMantissaCollateral
            });

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            vars.tokensToDenomCollateral = mul_(
                mul_(vars.collateralFactor, vars.exchangeRate),
                vars.oraclePriceCollateral
            );
            vars.tokensToDenomCollateralNoCollateralFactor = mul_(
                vars.exchangeRate,
                vars.oraclePriceCollateral
            );
            // sumCollateral += tokensToDenom * cTokenBalance

            // NUMALENDING: use collateral price
            vars.sumCollateral = mul_ScalarTruncateAddUInt(
                vars.tokensToDenomCollateral,
                vars.cTokenBalance,
                vars.sumCollateral
            );


            console2.log("sumCollateral:", vars.sumCollateral);


            //
               (
                oErr,
                vars.cTokenBalance,
                vars.borrowBalance,
                vars.exchangeRateMantissa
            ) = clst.getAccountSnapshot(drew);
          

            vars.oraclePriceMantissaBorrowed = oracle
                .getUnderlyingPriceAsBorrowed(clst);

            // AUDITV2FIX: missing current borrow balance update
            vars.oraclePriceBorrowed = Exp({
                mantissa: vars.oraclePriceMantissaBorrowed
            });
            vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(
                vars.oraclePriceBorrowed,
                vars.borrowBalance,
                vars.sumBorrowPlusEffects
            );

          
        


        vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(
            vars.oraclePriceBorrowed,
            borrowAmount,
            vars.sumBorrowPlusEffects
        );
        console2.log("sumBorrowPlusEffects:", vars.sumBorrowPlusEffects);

        console2.log("uint(Error.INSUFFICIENT_LIQUIDITY)", uint(ErrorDBG.INSUFFICIENT_LIQUIDITY));


        uint allowed = comptroller.borrowAllowed(address(clst),drew,borrowAmount);
        console2.log("allowed:", allowed);

    //  (ErrorDBG, uint l , uint s , uint b) = getAccountLiquidityIsolateInternal(
    //    drew,
    //    cnuma,
    //     clst
    // ) ;

    // (ErrorDBG err, uint l , uint s , uint b) = getHypotheticalAccountLiquidityIsolateInternal(
    //     drew,
    //     clst,
    //     0,
    //     borrowAmount);


    //     console2.log("liquidity:", l);
    //     console2.log("shortfall:", s);
    //     console2.log("badDebt:", b);


    
    }


    function test_borrowALLOWED() public  {



        // Leverage test
        address drew = 0xB0D3221A1844950b74C4ac7af1fF934182E2c67d;
        vm.startPrank(drew);


      

        // TEST mint then borrow
        numa.approve(address(cnuma), 11000000000000000000);
        cnuma.mint( 11000000000000000000);


        uint borrowAmount = 1.369e12;

        uint allowed = comptroller.borrowAllowed(address(clst),drew,borrowAmount);
        console2.log("allowed:", allowed);

    NumaComptroller.AccountLiquidityLocalVars memory vars; // Holds all our calculation results
        uint oErr;
        
           (
                oErr,
                vars.cTokenBalance,
                vars.borrowBalance,
                vars.exchangeRateMantissa
            ) = cnuma.getAccountSnapshot(drew);

        console2.log("vars.exchangeRateMantissa", vars.exchangeRateMantissa);


         (
                oErr,
                vars.cTokenBalance,
                vars.borrowBalance,
                vars.exchangeRateMantissa
            ) = clst.getAccountSnapshot(drew);

        console2.log("vars.exchangeRateMantissa", vars.exchangeRateMantissa);
    
    }


}