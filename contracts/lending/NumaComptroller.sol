// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "./CToken.sol";
import "./ErrorReporter.sol";
import "./PriceOracleCollateralBorrow.sol";
import "./ComptrollerInterface.sol";
import "./ComptrollerStorage.sol";
import "./Unitroller.sol";

/**
 * @title Numa's Comptroller Contract (forked from compound)
 * @author
 */
contract NumaComptroller is
    ComptrollerV7Storage,
    ComptrollerInterface,
    ComptrollerErrorReporter,
    ExponentialNoError
{
    /// @notice Emitted when an admin supports a market
    event MarketListed(CToken cToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(CToken cToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(CToken cToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(
        uint oldCloseFactorMantissa,
        uint newCloseFactorMantissa
    );

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(
        CToken cToken,
        uint oldCollateralFactorMantissa,
        uint newCollateralFactorMantissa
    );

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(
        uint oldLiquidationIncentiveMantissa,
        uint newLiquidationIncentiveMantissa
    );

    /// @notice Emitted when price oracle is changed
    event NewPriceOracle(
        PriceOracleCollateralBorrow oldPriceOracle,
        PriceOracleCollateralBorrow newPriceOracle
    );

    /// @notice Emitted when pause guardian is changed
    event NewPauseGuardian(address oldPauseGuardian, address newPauseGuardian);

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(CToken cToken, string action, bool pauseState);

    /// @notice Emitted when a new borrow-side COMP speed is calculated for a market
    event CompBorrowSpeedUpdated(CToken indexed cToken, uint newSpeed);

    /// @notice Emitted when a new supply-side COMP speed is calculated for a market
    event CompSupplySpeedUpdated(CToken indexed cToken, uint newSpeed);

    /// @notice Emitted when a new COMP speed is set for a contributor
    event ContributorCompSpeedUpdated(
        address indexed contributor,
        uint newSpeed
    );

    /// @notice Emitted when COMP is distributed to a supplier
    event DistributedSupplierComp(
        CToken indexed cToken,
        address indexed supplier,
        uint compDelta,
        uint compSupplyIndex
    );

    /// @notice Emitted when COMP is distributed to a borrower
    event DistributedBorrowerComp(
        CToken indexed cToken,
        address indexed borrower,
        uint compDelta,
        uint compBorrowIndex
    );

    /// @notice Emitted when borrow cap for a cToken is changed
    event NewBorrowCap(CToken indexed cToken, uint newBorrowCap);

    /// @notice Emitted when borrow cap guardian is changed
    event NewBorrowCapGuardian(
        address oldBorrowCapGuardian,
        address newBorrowCapGuardian
    );

    /// @notice The initial COMP index for a market
    uint224 public constant compInitialIndex = 1e36;

    // closeFactorMantissa must be strictly greater than this value
    uint internal constant closeFactorMinMantissa = 0.05e18; // 0.05

    // closeFactorMantissa must not exceed this value
    uint internal constant closeFactorMaxMantissa = 0.9e18; // 0.9

    // No collateralFactorMantissa may exceed this value
    uint internal constant collateralFactorMaxMantissa = 0.99e18; // 0.99

    uint ltvMinBadDebtLiquidations = 0.98 ether;
    uint ltvMinPartialLiquidations = 1.1 ether;

    constructor() {
        admin = msg.sender;
    }

    /*** Assets You Are In ***/

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    function getAssetsIn(
        address account
    ) external view returns (CToken[] memory) {
        CToken[] memory assetsIn = accountAssets[account];

        return assetsIn;
    }

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param cToken The cToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(
        address account,
        CToken cToken
    ) external view returns (bool) {
        return markets[address(cToken)].accountMembership[account];
    }

    function collateralFactor(CToken cToken) external view returns (uint) {
        Market storage m = markets[address(cToken)];
        return (m.collateralFactorMantissa);
    }

    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param cTokens The list of addresses of the cToken markets to be enabled
     * @return Success indicator for whether each corresponding market was entered
     */
    function enterMarkets(
        address[] memory cTokens
    ) public override returns (uint[] memory) {
        uint len = cTokens.length;

        uint[] memory results = new uint[](len);
        for (uint i = 0; i < len; i++) {
            CToken cToken = CToken(cTokens[i]);

            results[i] = uint(addToMarketInternal(cToken, msg.sender));
        }

        return results;
    }

    /**
     * @notice Add the market to the borrower's "assets in" for liquidity calculations
     * @param cToken The market to enter
     * @param borrower The address of the account to modify
     * @return Success indicator for whether the market was entered
     */
    function addToMarketInternal(
        CToken cToken,
        address borrower
    ) internal returns (Error) {
        Market storage marketToJoin = markets[address(cToken)];

        if (!marketToJoin.isListed) {
            // market is not listed, cannot join
            return Error.MARKET_NOT_LISTED;
        }

        if (marketToJoin.accountMembership[borrower] == true) {
            // already joined
            return Error.NO_ERROR;
        }

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        marketToJoin.accountMembership[borrower] = true;
        accountAssets[borrower].push(cToken);

        emit MarketEntered(cToken, borrower);

        return Error.NO_ERROR;
    }

    /**
     * @notice Removes asset from sender's account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param cTokenAddress The address of the asset to be removed
     * @return Whether or not the account successfully exited the market
     */
    function exitMarket(
        address cTokenAddress
    ) external override returns (uint) {
        CToken cToken = CToken(cTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the cToken */
        (uint oErr, uint tokensHeld, uint amountOwed, ) = cToken
            .getAccountSnapshot(msg.sender);
        require(oErr == 0, "exitMarket: getAccountSnapshot failed"); // semi-opaque error code

        /* Fail if the sender has a borrow balance */
        if (amountOwed != 0) {
            return
                fail(
                    Error.NONZERO_BORROW_BALANCE,
                    FailureInfo.EXIT_MARKET_BALANCE_OWED
                );
        }

        /* Fail if the sender is not permitted to redeem all of their tokens */
        uint allowed = redeemAllowedInternal(
            cTokenAddress,
            msg.sender,
            tokensHeld
        );
        if (allowed != 0) {
            return
                failOpaque(
                    Error.REJECTION,
                    FailureInfo.EXIT_MARKET_REJECTION,
                    allowed
                );
        }

        Market storage marketToExit = markets[address(cToken)];

        /* Return true if the sender is not already ‘in’ the market */
        if (!marketToExit.accountMembership[msg.sender]) {
            return uint(Error.NO_ERROR);
        }

        /* Set cToken account membership to false */
        delete marketToExit.accountMembership[msg.sender];

        /* Delete cToken from the account’s list of assets */
        // load into memory for faster iteration
        CToken[] memory userAssetList = accountAssets[msg.sender];
        uint len = userAssetList.length;
        uint assetIndex = len;
        for (uint i = 0; i < len; i++) {
            if (userAssetList[i] == cToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);

        // copy last item in list to location of item to be removed, reduce length by 1
        CToken[] storage storedList = accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        emit MarketExited(cToken, msg.sender);

        return uint(Error.NO_ERROR);
    }

    /*** Policy Hooks ***/

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param cToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @return 0 if the mint is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function mintAllowed(
        address cToken,
        address minter,
        uint mintAmount
    ) external view override returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!mintGuardianPaused[cToken], "mint is paused");

        // Shh - currently unused
        minter;
        mintAmount;

        if (!markets[cToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates mint and reverts on rejection. May emit logs.
     * @param cToken Asset being minted
     * @param minter The address minting the tokens
     * @param actualMintAmount The amount of the underlying asset being minted
     * @param mintTokens The number of tokens being minted
     */
    // function mintVerify(
    //     address cToken,
    //     address minter,
    //     uint actualMintAmount,
    //     uint mintTokens
    // ) external override {
    //     // Shh - currently unused
    //     cToken;
    //     minter;
    //     actualMintAmount;
    //     mintTokens;

    //     // Shh - we don't ever want this hook to be marked pure
    //     if (false) {
    //         maxAssets = maxAssets;
    //     }
    // }

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param cToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of cTokens to exchange for the underlying asset in the market
     * @return 0 if the redeem is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function redeemAllowed(
        address cToken,
        address redeemer,
        uint redeemTokens
    ) external view override returns (uint) {
        uint allowed = redeemAllowedInternal(cToken, redeemer, redeemTokens);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        return uint(Error.NO_ERROR);
    }

    function redeemAllowedInternal(
        address cToken,
        address redeemer,
        uint redeemTokens
    ) internal view returns (uint) {
        require(!redeemGuardianPaused, "redeem is paused");
        if (!markets[cToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        if (!markets[cToken].accountMembership[redeemer]) {
            return uint(Error.NO_ERROR);
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (
            Error err,
            ,
            uint shortfall,

        ) = getHypotheticalAccountLiquidityIsolateInternal(
                redeemer,
                CToken(cToken),
                redeemTokens,
                0
            );
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates redeem and reverts on rejection. May emit logs.
     * @param cToken Asset being redeemed
     * @param redeemer The address redeeming the tokens
     * @param redeemAmount The amount of the underlying asset being redeemed
     * @param redeemTokens The number of tokens being redeemed
     */
    function redeemVerify(
        address cToken,
        address redeemer,
        uint redeemAmount,
        uint redeemTokens
    ) external pure override {
        // Shh - currently unused
        cToken;
        redeemer;

        // Require tokens is zero or amount is also zero
        if (redeemTokens == 0 && redeemAmount > 0) {
            revert("redeemTokens zero");
        }
    }

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param cToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     * @return 0 if the borrow is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function borrowAllowed(
        address cToken,
        address borrower,
        uint borrowAmount
    ) external override returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!borrowGuardianPaused[cToken], "borrow is paused");

        if (!markets[cToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }
        Error err;
        if (!markets[cToken].accountMembership[borrower]) {
            // only cTokens may call borrowAllowed if borrower not in market
            require(msg.sender == cToken, "sender must be cToken");

            // attempt to add borrower to the market
            err = addToMarketInternal(CToken(msg.sender), borrower);
            if (err != Error.NO_ERROR) {
                return uint(err);
            }

            // it should be impossible to break the important invariant
            assert(markets[cToken].accountMembership[borrower]);
        }

        if (oracle.getUnderlyingPriceAsBorrowed(CNumaToken(cToken)) == 0) {
            return uint(Error.PRICE_ERROR);
        }

        uint borrowCap = borrowCaps[cToken];
        // Borrow cap of 0 corresponds to unlimited borrowing
        if (borrowCap != 0) {
            uint totalBorrows = CToken(cToken).totalBorrows();
            uint nextTotalBorrows = add_(totalBorrows, borrowAmount);
            require(nextTotalBorrows < borrowCap, "market borrow cap reached");
        }
        uint shortfall;
        (err, , shortfall, ) = getHypotheticalAccountLiquidityIsolateInternal(
            borrower,
            CToken(cToken),
            0,
            borrowAmount
        );
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        if (shortfall > 0) {
            return uint(Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates borrow and reverts on rejection. May emit logs.
     * @param cToken Asset whose underlying is being borrowed
     * @param borrower The address borrowing the underlying
     * @param borrowAmount The amount of the underlying asset requested to borrow
     */
    function borrowVerify(
        address cToken,
        address borrower,
        uint borrowAmount
    ) external override {
        // Shh - currently unused
        cToken;
        borrower;
        borrowAmount;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param cToken The market to verify the repay against
     * @param payer The account which would repay the asset
     * @param borrower The account which would borrowed the asset
     * @param repayAmount The amount of the underlying asset the account would repay
     * @return 0 if the repay is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function repayBorrowAllowed(
        address cToken,
        address payer,
        address borrower,
        uint repayAmount
    ) external view override returns (uint) {
        // Shh - currently unused
        payer;
        borrower;
        repayAmount;
        require(!repayGuardianPaused, "repay is paused");
        if (!markets[cToken].isListed) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates repayBorrow and reverts on rejection. May emit logs.
     * @param cToken Asset being repaid
     * @param payer The address repaying the borrow
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function repayBorrowVerify(
        address cToken,
        address payer,
        address borrower,
        uint actualRepayAmount,
        uint borrowerIndex
    ) external override {
        // Shh - currently unused
        cToken;
        payer;
        borrower;
        actualRepayAmount;
        borrowerIndex;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     * @return (error,baddebt,restOfDebt)
     */
    function liquidateBorrowAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address borrower,
        uint repayAmount
    ) external view override returns (uint,uint,uint) {
        require((cTokenBorrowed) != (cTokenCollateral), "not isolate");
        if (
            !markets[cTokenBorrowed].isListed ||
            !markets[cTokenCollateral].isListed
        ) {
            return (uint(Error.MARKET_NOT_LISTED),0,0);
        }

        uint borrowBalance = CToken(cTokenBorrowed).borrowBalanceStored(
            borrower
        );

        /* allow accounts to be liquidated if the market is deprecated */
             
        (
            Error err,
            ,
            uint shortfall,
            uint badDebt,
            uint ltv

        ) = getAccountLiquidityIsolateInternal(
                borrower,
                CNumaToken(cTokenCollateral),
                CNumaToken(cTokenBorrowed)
            );
        if (err != Error.NO_ERROR) {
            return (uint(err),0,0);
        }


        // sherlock 101 153 
        // min amount allowed for liquidations from vault
        uint minAmount = 0;
        bool badDebtLiquidationAllowed = false;
        
        // Min amount from vault. 
        // we should have a vault, if not, it will revert which is ok
        minAmount = CNumaToken(cTokenBorrowed).vault().getMinBorrowAmountAllowPartialLiquidation(cTokenBorrowed);

        // if ltv > ltvMinPartialLiquidations, partial liquidations are enabled
        if (ltv > ltvMinPartialLiquidations)
        {
             minAmount = 0;
             // if ltv > ltvMinPartialLiquidations, it means we are in bad debt
             // so we need to allow bad debt liquidation
             badDebtLiquidationAllowed = true;
        }
        
        if (borrowBalance < minAmount) minAmount = borrowBalance;
        
        require(repayAmount >= minAmount, "min liquidation");


        if (isDeprecated(CToken(cTokenBorrowed))) {
            require(
                borrowBalance >= repayAmount,
                "Can not repay more than the total borrow"
            );
            // sherlock issue 67. Even if deprecated we don't want that liquidation type if in bad debt
            if (badDebt > 0 && (!badDebtLiquidationAllowed)) {
                return (uint(Error.BAD_DEBT),badDebt,0);
            }
        } else {

            /* The borrower must have shortfall in order to be liquidatable */
            if (shortfall == 0) 
            {
                return (uint(Error.INSUFFICIENT_SHORTFALL),badDebt,0);
            }

            /* The liquidator may not repay more than what is allowed by the closeFactor */
            uint maxClose = mul_ScalarTruncate(
                Exp({mantissa: closeFactorMantissa}),
                borrowBalance
            );
            if (repayAmount > maxClose) {
                return (uint(Error.TOO_MUCH_REPAY),badDebt,0);
            }
            /* revert if there is bad debt, specific bad debt liquidations functions should be called */
            if (badDebt > 0 && (!badDebtLiquidationAllowed)) {
                return (uint(Error.BAD_DEBT),badDebt,0);
            }
        }
        // sherlock 101 153 returning badDebt and restOfDebt
        // because we want to know if liquidation is partial and not in baddebt to allow taking all collateral
        return (uint(Error.NO_ERROR),badDebt,borrowBalance - repayAmount);
    }

    function liquidateBadDebtAllowed(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint repayAmount
    ) external view override returns (uint) {
        // Shh - currently unused
        liquidator;

        require((cTokenBorrowed) != (cTokenCollateral), "not isolate");
        if (
            !markets[cTokenBorrowed].isListed ||
            !markets[cTokenCollateral].isListed
        ) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        uint borrowBalance = CToken(cTokenBorrowed).borrowBalanceStored(
            borrower
        );

        (
            Error err,
            ,
            uint shortfall,
            ,
            uint ltv

        ) = getAccountLiquidityIsolateInternal(
                borrower,
                CNumaToken(cTokenCollateral),
                CNumaToken(cTokenBorrowed)
            );
        if (err != Error.NO_ERROR) {
            return uint(err);
        }
        /* allow accounts to be liquidated if the market is deprecated */
        if (isDeprecated(CToken(cTokenBorrowed))) {
            require(
                borrowBalance >= repayAmount,
                "Can not repay more than the total borrow"
            );
            // sherlock issue 67. Even if deprecated some bad debt is needed 
             if (ltv < ltvMinBadDebtLiquidations) {
                return uint(Error.INSUFFICIENT_BADDEBT);
            }
        } else {
            /* The borrower must have shortfall in order to be liquidatable */
            if (shortfall == 0) {
                return uint(Error.INSUFFICIENT_SHORTFALL);
            }
            // bad debt liquidation allowed only above ltvMinBadDebtLiquidations
            if (ltv < ltvMinBadDebtLiquidations) {
                return uint(Error.INSUFFICIENT_BADDEBT);
            }
        }
        return uint(Error.NO_ERROR);
    }
    /**
     * @notice Validates liquidateBorrow and reverts on rejection. May emit logs.
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function liquidateBorrowVerify(
        address cTokenBorrowed,
        address cTokenCollateral,
        address liquidator,
        address borrower,
        uint actualRepayAmount,
        uint seizeTokens
    ) external override {
        // Shh - currently unused
        cTokenBorrowed;
        cTokenCollateral;
        liquidator;
        borrower;
        actualRepayAmount;
        seizeTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeAllowed(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external view override returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!seizeGuardianPaused, "seize is paused");

        // Shh - currently unused
        seizeTokens;

        if (
            !markets[cTokenCollateral].isListed ||
            !markets[cTokenBorrowed].isListed
        ) {
            return uint(Error.MARKET_NOT_LISTED);
        }

        if (
            CToken(cTokenCollateral).comptroller() !=
            CToken(cTokenBorrowed).comptroller()
        ) {
            return uint(Error.COMPTROLLER_MISMATCH);
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates seize and reverts on rejection. May emit logs.
     * @param cTokenCollateral Asset which was used as collateral and will be seized
     * @param cTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeVerify(
        address cTokenCollateral,
        address cTokenBorrowed,
        address liquidator,
        address borrower,
        uint seizeTokens
    ) external override {
        // Shh - currently unused
        cTokenCollateral;
        cTokenBorrowed;
        liquidator;
        borrower;
        seizeTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param cToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of cTokens to transfer
     * @return 0 if the transfer is allowed, otherwise a semi-opaque error code (See ErrorReporter.sol)
     */
    function transferAllowed(
        address cToken,
        address src,
        address dst,
        uint transferTokens
    ) external view override returns (uint) {
        // Pausing is a very serious situation - we revert to sound the alarms
        require(!transferGuardianPaused, "transfer is paused");

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        uint allowed = redeemAllowedInternal(cToken, src, transferTokens);
        if (allowed != uint(Error.NO_ERROR)) {
            return allowed;
        }

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Validates transfer and reverts on rejection. May emit logs.
     * @param cToken Asset being transferred
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of cTokens to transfer
     */
    function transferVerify(
        address cToken,
        address src,
        address dst,
        uint transferTokens
    ) external override {
        // Shh - currently unused
        cToken;
        src;
        dst;
        transferTokens;

        // Shh - we don't ever want this hook to be marked pure
        if (false) {
            maxAssets = maxAssets;
        }
    }

    /*** Liquidity/Liquidation Calculations ***/

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *  Note that `cTokenBalance` is the number of cTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountLiquidityLocalVars {
        uint sumCollateral;
        uint sumCollateralNoCollateralFactor;
        uint sumBorrowPlusEffects;
        uint cTokenBalance;
        uint borrowBalance;
        uint exchangeRateMantissa;
        uint oraclePriceMantissaCollateral;
        uint oraclePriceMantissaBorrowed;
        Exp collateralFactor;
        Exp exchangeRate;
        Exp oraclePriceCollateral;
        Exp oraclePriceBorrowed;
        Exp tokensToDenomCollateral;
        Exp tokensToDenomCollateralNoCollateralFactor;
        Exp tokensToDenomBorrowed;
    }

    // /**
    //  * @notice Determine the current account liquidity wrt collateral requirements
    //  * @return (possible error code (semi-opaque),
    //             account liquidity in excess of collateral requirements,
    //  *          account shortfall below collateral requirements)
    //  */
    // function getAccountLiquidity(address account) public view returns (uint, uint, uint,uint) {
    //     (Error err, uint liquidity, uint shortfall,uint badDebt) = getHypotheticalAccountLiquidityInternal(account, CToken(address(0)), 0, 0);

    //     return (uint(err), liquidity, shortfall,badDebt);
    // }

    function getAccountLiquidityIsolate(
        address account,
        CNumaToken collateral,
        CNumaToken borrow
    ) public view returns (uint, uint, uint, uint,uint) {
        (
            Error err,
            uint liquidity,
            uint shortfall,
            uint badDebt,
            uint ltv
        ) = getAccountLiquidityIsolateInternal(account, collateral, borrow);
        return (uint(err), liquidity, shortfall, badDebt,ltv);
    }

    // function getAccountLTVIsolate(
    //     address account,
    //     CNumaToken collateral,
    //     CNumaToken borrow
    // ) public view returns (uint, uint) {
    //     (Error err, uint ltv) = getAccountLTVIsolateInternal(
    //         account,
    //         collateral,
    //         borrow
    //     );
    //     return (uint(err), ltv);
    // }

    /**
     * @notice Determine the current account liquidity wrt collateral requirements
     * @return (possible error code,
                account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidityIsolateInternal(
        address account,
        CNumaToken collateral,
        CNumaToken borrow
    ) internal view returns (Error, uint, uint, uint,uint) {
        AccountLiquidityLocalVars memory vars; // Holds all our calculation results
        uint oErr;

        // Here we only consider only 2 tokens: collateral token and borrow token which should be different
        // collateral
        // Read the balances and exchange rate from the cToken
        (
            oErr,
            vars.cTokenBalance,
            vars.borrowBalance,
            vars.exchangeRateMantissa
        ) = collateral.getAccountSnapshot(account);
        if (oErr != 0) {
            // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
            return (Error.SNAPSHOT_ERROR, 0, 0, 0,0);
        }
        vars.collateralFactor = Exp({
            mantissa: markets[address(collateral)].collateralFactorMantissa
        });
        vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

        // Get the normalized price of the asset
        vars.oraclePriceMantissaCollateral = oracle
            .getUnderlyingPriceAsCollateral(collateral);
        if (vars.oraclePriceMantissaCollateral == 0) {
            return (Error.PRICE_ERROR, 0, 0, 0,0);
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

        // borrow
        // Read the balances and exchange rate from the cToken
        (
            oErr,
            vars.cTokenBalance,
            vars.borrowBalance,
            vars.exchangeRateMantissa
        ) = borrow.getAccountSnapshot(account);
        if (oErr != 0) {
            // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
            return (Error.SNAPSHOT_ERROR, 0, 0, 0,0);
        }
        // Get the normalized price of the asset
        vars.oraclePriceMantissaBorrowed = oracle.getUnderlyingPriceAsBorrowed(
            borrow
        );

        if (vars.oraclePriceMantissaBorrowed == 0) {
            return (Error.PRICE_ERROR, 0, 0, 0,0);
        }
        //vars.oraclePriceCollateral = Exp({mantissa: vars.oraclePriceMantissaCollateral});
        vars.oraclePriceBorrowed = Exp({
            mantissa: vars.oraclePriceMantissaBorrowed
        });

        // sumBorrowPlusEffects += oraclePrice * borrowBalance
        // NUMALENDING: use borrow price
        vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(
            vars.oraclePriceBorrowed,
            vars.borrowBalance,
            vars.sumBorrowPlusEffects
        );

        uint ltv;
        if (vars.sumCollateralNoCollateralFactor > 0)
        {
            ltv = (vars.sumBorrowPlusEffects * 1 ether) / vars.sumCollateralNoCollateralFactor;
        }
        else if (vars.sumBorrowPlusEffects > 0)
        {
            // no collateral but some borrow, ltv is infinite
            ltv = type(uint).max;

        }
        // These are safe, as the underflow condition is checked first
        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            return (
                Error.NO_ERROR,
                vars.sumCollateral - vars.sumBorrowPlusEffects,
                0,
                0,
                ltv
            );
        } else {
            if (
                vars.sumCollateralNoCollateralFactor > vars.sumBorrowPlusEffects
            )
                return (
                    Error.NO_ERROR,
                    0,
                    vars.sumBorrowPlusEffects - vars.sumCollateral,
                    0,
                    ltv
                );
            // returning bad debt
            else
                return (
                    Error.NO_ERROR,
                    0,
                    vars.sumBorrowPlusEffects - vars.sumCollateral,
                    vars.sumBorrowPlusEffects -
                        vars.sumCollateralNoCollateralFactor,
                        ltv
                );
        }
    }

    // function getAccountLTVIsolateInternal(
    //     address account,
    //     CNumaToken collateral,
    //     CNumaToken borrow
    // ) internal view returns (Error, uint) {
    //     AccountLiquidityLocalVars memory vars; // Holds all our calculation results
    //     uint oErr;

    //     // Here we only consider only 2 tokens: collateral token and borrow token which should be different
    //     // collateral
    //     // Read the balances and exchange rate from the cToken
    //     (
    //         oErr,
    //         vars.cTokenBalance,
    //         vars.borrowBalance,
    //         vars.exchangeRateMantissa
    //     ) = collateral.getAccountSnapshot(account);
    //     if (oErr != 0) {
    //         // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
    //         return (Error.SNAPSHOT_ERROR, 0);
    //     }
    //     vars.collateralFactor = Exp({
    //         mantissa: markets[address(collateral)].collateralFactorMantissa
    //     });
    //     vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

    //     // Get the normalized price of the asset
    //     vars.oraclePriceMantissaCollateral = oracle
    //         .getUnderlyingPriceAsCollateral(collateral);
    //     if (vars.oraclePriceMantissaCollateral == 0) {
    //         return (Error.PRICE_ERROR, 0);
    //     }
    //     vars.oraclePriceCollateral = Exp({
    //         mantissa: vars.oraclePriceMantissaCollateral
    //     });

    //     // Pre-compute a conversion factor from tokens -> ether (normalized price value)
    //     vars.tokensToDenomCollateral = mul_(
    //         mul_(vars.collateralFactor, vars.exchangeRate),
    //         vars.oraclePriceCollateral
    //     );
    //     vars.tokensToDenomCollateralNoCollateralFactor = mul_(
    //         vars.exchangeRate,
    //         vars.oraclePriceCollateral
    //     );
    //     // sumCollateral += tokensToDenom * cTokenBalance

    //     // NUMALENDING: use collateral price
    //     vars.sumCollateral = mul_ScalarTruncateAddUInt(
    //         vars.tokensToDenomCollateral,
    //         vars.cTokenBalance,
    //         vars.sumCollateral
    //     );
    //     vars.sumCollateralNoCollateralFactor = mul_ScalarTruncateAddUInt(
    //         vars.tokensToDenomCollateralNoCollateralFactor,
    //         vars.cTokenBalance,
    //         vars.sumCollateralNoCollateralFactor
    //     );

    //     // borrow
    //     // Read the balances and exchange rate from the cToken
    //     (
    //         oErr,
    //         vars.cTokenBalance,
    //         vars.borrowBalance,
    //         vars.exchangeRateMantissa
    //     ) = borrow.getAccountSnapshot(account);
    //     if (oErr != 0) {
    //         // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
    //         return (Error.SNAPSHOT_ERROR, 0);
    //     }
    //     // Get the normalized price of the asset
    //     vars.oraclePriceMantissaBorrowed = oracle.getUnderlyingPriceAsBorrowed(
    //         borrow
    //     );

    //     if (vars.oraclePriceMantissaBorrowed == 0) {
    //         return (Error.PRICE_ERROR, 0);
    //     }
    //     //vars.oraclePriceCollateral = Exp({mantissa: vars.oraclePriceMantissaCollateral});
    //     vars.oraclePriceBorrowed = Exp({
    //         mantissa: vars.oraclePriceMantissaBorrowed
    //     });

    //     // sumBorrowPlusEffects += oraclePrice * borrowBalance
    //     // NUMALENDING: use borrow price
    //     vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(
    //         vars.oraclePriceBorrowed,
    //         vars.borrowBalance,
    //         vars.sumBorrowPlusEffects
    //     );

    //     return (
    //         Error.NO_ERROR,
    //         (vars.sumBorrowPlusEffects * 1 ether) / vars.sumCollateral
    //     );
    // }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param cTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return (possible error code (semi-opaque),
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    // function getHypotheticalAccountLiquidity(
    //     address account,
    //     address cTokenModify,
    //     uint redeemTokens,
    //     uint borrowAmount) public view returns (uint, uint, uint) {
    //     (Error err, uint liquidity, uint shortfall,) = getHypotheticalAccountLiquidityInternal(account, CToken(cTokenModify), redeemTokens, borrowAmount);
    //     return (uint(err), liquidity, shortfall);
    // }

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param cTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @dev Note that we calculate the exchangeRateStored for each collateral cToken using stored data,
     *  without calculating accumulated interest.
     * @return (possible error code,
                hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    // function getHypotheticalAccountLiquidityInternal(
    //     address account,
    //     CToken cTokenModify,
    //     uint redeemTokens,
    //     uint borrowAmount) internal view returns (Error, uint, uint,uint) {

    //     AccountLiquidityLocalVars memory vars; // Holds all our calculation results
    //     uint oErr;

    //     // For each asset the account is in
    //     CToken[] memory assets = accountAssets[account];
    //     for (uint i = 0; i < assets.length; i++) {
    //         CToken asset = assets[i];

    //         // Read the balances and exchange rate from the cToken
    //         (oErr, vars.cTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = asset.getAccountSnapshot(account);
    //         if (oErr != 0)
    //         {
    //             // semi-opaque error code, we assume NO_ERROR == 0 is invariant between upgrades
    //             return (Error.SNAPSHOT_ERROR, 0, 0,0);
    //         }
    //         vars.collateralFactor = Exp({mantissa: markets[address(asset)].collateralFactorMantissa});
    //         vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

    //         // Get the normalized price of the asset
    //         vars.oraclePriceMantissaCollateral = oracle.getUnderlyingPriceAsCollateral(asset);
    //         vars.oraclePriceMantissaBorrowed = oracle.getUnderlyingPriceAsBorrowed(asset);

    //         if (vars.oraclePriceMantissaCollateral == 0) {
    //             return (Error.PRICE_ERROR, 0, 0,0);
    //         }
    //         vars.oraclePriceCollateral = Exp({mantissa: vars.oraclePriceMantissaCollateral});
    //         vars.oraclePriceBorrowed = Exp({mantissa: vars.oraclePriceMantissaBorrowed});

    //         // Pre-compute a conversion factor from tokens -> ether (normalized price value)
    //         vars.tokensToDenomCollateral = mul_(mul_(vars.collateralFactor, vars.exchangeRate), vars.oraclePriceCollateral);
    //         vars.tokensToDenomBorrowed = mul_(mul_(vars.collateralFactor, vars.exchangeRate), vars.oraclePriceBorrowed);
    //         vars.tokensToDenomCollateralNoCollateralFactor = mul_(vars.exchangeRate, vars.oraclePriceCollateral);
    //         // sumCollateral += tokensToDenom * cTokenBalance

    //         // NUMALENDING: use collateral price
    //         vars.sumCollateral = mul_ScalarTruncateAddUInt(vars.tokensToDenomCollateral, vars.cTokenBalance, vars.sumCollateral);
    //         vars.sumCollateralNoCollateralFactor = mul_ScalarTruncateAddUInt(vars.tokensToDenomCollateralNoCollateralFactor, vars.cTokenBalance, vars.sumCollateralNoCollateralFactor);

    //         // sumBorrowPlusEffects += oraclePrice * borrowBalance

    //         // NUMALENDING: use borrow price
    //         vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePriceBorrowed, vars.borrowBalance, vars.sumBorrowPlusEffects);

    //         // Calculate effects of interacting with cTokenModify
    //         if (asset == cTokenModify) {
    //             // redeem effect
    //             // sumBorrowPlusEffects += tokensToDenom * redeemTokens
    //             // NUMALENDING: use numa as collateral price
    //             vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.tokensToDenomCollateral, redeemTokens, vars.sumBorrowPlusEffects);

    //             // borrow effect
    //             // sumBorrowPlusEffects += oraclePrice * borrowAmount
    //             // NUMALENDING: use numa as borrowed price
    //             vars.sumBorrowPlusEffects = mul_ScalarTruncateAddUInt(vars.oraclePriceBorrowed, borrowAmount, vars.sumBorrowPlusEffects);
    //         }
    //     }

    //     // These are safe, as the underflow condition is checked first
    //     if (vars.sumCollateral > vars.sumBorrowPlusEffects)
    //     {
    //         return (Error.NO_ERROR, vars.sumCollateral - vars.sumBorrowPlusEffects, 0,0);
    //     }
    //     else
    //     {
    //         if (vars.sumCollateralNoCollateralFactor > vars.sumBorrowPlusEffects)
    //             return (Error.NO_ERROR, 0, vars.sumBorrowPlusEffects - vars.sumCollateral,0);
    //         else// returning bad debt
    //             return (Error.NO_ERROR, 0, vars.sumBorrowPlusEffects - vars.sumCollateral,vars.sumBorrowPlusEffects - vars.sumCollateralNoCollateralFactor);
    //     }
    // }

    function getHypotheticalAccountLiquidityIsolateInternal(
        address account,
        CToken cTokenModify,
        uint redeemTokens,
        uint borrowAmount
    ) internal view returns (Error, uint, uint, uint) {
        AccountLiquidityLocalVars memory vars; // Holds all our calculation results
        uint oErr;

        // this function is called from borrowallowed or redeemallowed so we should either have reddemTokens = 0 or
        // borrowAmount = 0
        require(
            ((redeemTokens == 0) || (borrowAmount == 0)),
            "redeem and borrow"
        );

        // cTokenModify = redeemed --> other token = borrowed
        // cTokenModify = borrowed --> other token = collateral
        CToken otherToken;
        CToken[] memory assets = accountAssets[account];
        for (uint i = 0; i < assets.length; i++) {
            CToken asset = assets[i];
            if (address(asset) != address(cTokenModify)) {
                otherToken = asset;
                break;
            }
        }

        CNumaToken collateral = CNumaToken(address(cTokenModify));
        CNumaToken borrow = CNumaToken(address(otherToken));

        if (borrowAmount > 0) {
            collateral = CNumaToken(address(otherToken));
            borrow = CNumaToken(address(cTokenModify));
        }

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
                return (Error.SNAPSHOT_ERROR, 0, 0, 0);
            }
            vars.collateralFactor = Exp({
                mantissa: markets[address(collateral)].collateralFactorMantissa
            });
            vars.exchangeRate = Exp({mantissa: vars.exchangeRateMantissa});

            // Get the normalized price of the asset
            vars.oraclePriceMantissaCollateral = oracle
                .getUnderlyingPriceAsCollateral(collateral);
            if (vars.oraclePriceMantissaCollateral == 0) {
                return (Error.PRICE_ERROR, 0, 0, 0);
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
                return (Error.SNAPSHOT_ERROR, 0, 0, 0);
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
                return (Error.PRICE_ERROR, 0, 0, 0);
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
                Error.NO_ERROR,
                vars.sumCollateral - vars.sumBorrowPlusEffects,
                0,
                0
            );
        } else {
            if (
                vars.sumCollateralNoCollateralFactor > vars.sumBorrowPlusEffects
            ) {
                return (
                    Error.NO_ERROR,
                    0,
                    vars.sumBorrowPlusEffects - vars.sumCollateral,
                    0
                );
            }
            // returning bad debt
            else
                return (
                    Error.NO_ERROR,
                    0,
                    vars.sumBorrowPlusEffects - vars.sumCollateral,
                    vars.sumBorrowPlusEffects -
                        vars.sumCollateralNoCollateralFactor
                );
        }
    }

    // function liquidateBadDebtCalculateSeizeTokens(
    //     address cTokenBorrowed,
    //     address cTokenCollateral,
    //     address borrower,
    //     uint actualRepayAmount
    // ) external view override returns (uint, uint) {
    //     /*
    //      * Get the exchange rate and calculate the number of collateral tokens to seize:
    //      * for bad debt liquidation, we take % of amount repaid as % of collateral seized
    //      *  seizeAmount = (repayAmount / borrowBalance) * collateralAmount
    //      *  seizeTokens = seizeAmount / exchangeRate
    //      *
    //      */
    //     //uint exchangeRateMantissa = CToken(cTokenCollateral).exchangeRateStored(); // Note: reverts on error
    //     uint seizeTokens;
    //     // Exp memory numerator;
    //     // Exp memory denominator;
    //     // Exp memory ratio;

    //     // uint borrowBalance = CToken(cTokenBorrowed).borrowBalanceStored(borrower);

    //     // uint collateralBalance = accountTokens[borrower];

    //     // Read the balances and exchange rate from the cToken
    //     //(oErr, vars.cTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = CToken(cTokenBorrowed).getAccountSnapshot(borrower);
    //     (, , uint amountOwed, ) = CToken(cTokenBorrowed).getAccountSnapshot(
    //         borrower
    //     );
    //     (, uint tokensHeld, , ) = CToken(cTokenCollateral).getAccountSnapshot(
    //         borrower
    //     );
    //     //numerator = mul_(Exp({mantissa: liquidationIncentiveMantissa}), Exp({mantissa: priceBorrowedMantissa}));
    //     // denominator = mul_(Exp({mantissa: priceCollateralMantissa}), Exp({mantissa: exchangeRateMantissa}));
    //     // ratio = div_(numerator, denominator);

    //     // ratio = div_(numerator, denominator);
    //     // // seizeTokens = mul_ScalarTruncate(ratio, actualRepayAmount);
    //     // // seizeTokens = (repayAmount / borrowBalance) * collateralAmount
    //     // seizeTokens = ratio.mantissa;

    //     // seizeTokens = (actualRepayAmount * exchangeRateMantissa*tokensHeld)/(amountOwed*expScale);
    //     // in CToken
    //     seizeTokens = (actualRepayAmount * tokensHeld) / (amountOwed);

    //     // TODO: should I use Exp to get more precision or not to overflow???
    //     // numerator = mul_(Exp({mantissa: exchangeRateMantissa}), Exp({mantissa: tokensHeld}));
    //     // denominator = mul_(Exp({mantissa: amountOwed}), Exp({mantissa: expScale}));

    //     // ratio = div_(numerator, denominator);
    //     // seizeTokens = mul_ScalarTruncate(ratio, actualRepayAmount);

    //     return (uint(Error.NO_ERROR), seizeTokens);
    // }

    function liquidateBadDebtCalculateSeizeTokensAfterRepay(
        address cTokenCollateral,
        address borrower,
        uint percentageToTake
    ) external view override returns (uint, uint) {
        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         * for bad debt liquidation, we take % of amount repaid as % of collateral seized
         *  seizeAmount = (repayAmount / borrowBalance) * collateralAmount
         *  seizeTokens = seizeAmount / exchangeRate
         *
         */

        (, uint tokensHeld, , ) = CToken(cTokenCollateral).getAccountSnapshot(
            borrower
        );
        uint seizeTokens = (percentageToTake * tokensHeld) / (1000);
        return (uint(Error.NO_ERROR), seizeTokens);
    }

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in cToken.liquidateBorrowFresh)
     * @param cTokenBorrowed The address of the borrowed cToken
     * @param cTokenCollateral The address of the collateral cToken
     * @param actualRepayAmount The amount of cTokenBorrowed underlying to convert into cTokenCollateral tokens
     * @return (errorCode, number of cTokenCollateral tokens to be seized in a liquidation)
     */
    function liquidateCalculateSeizeTokens(
        address cTokenBorrowed,
        address cTokenCollateral,
        uint actualRepayAmount
    ) external view override returns (uint, uint) {
        /* Read oracle prices for borrowed and collateral markets */
        // NUMALENDING: different oracle functions depending on the token is borrowed or collateral
        uint priceBorrowedMantissa = oracle.getUnderlyingPriceAsBorrowed(
            CNumaToken(cTokenBorrowed)
        );
        uint priceCollateralMantissa = oracle.getUnderlyingPriceAsCollateral(
            CNumaToken(cTokenCollateral)
        );
        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            return (uint(Error.PRICE_ERROR), 0);
        }

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint exchangeRateMantissa = CToken(cTokenCollateral)
            .exchangeRateStored(); // Note: reverts on error
        uint seizeTokens;
        Exp memory numerator;
        Exp memory denominator;
        Exp memory ratio;

        numerator = mul_(
            Exp({mantissa: liquidationIncentiveMantissa}),
            Exp({mantissa: priceBorrowedMantissa})
        );
        denominator = mul_(
            Exp({mantissa: priceCollateralMantissa}),
            Exp({mantissa: exchangeRateMantissa})
        );

        ratio = div_(numerator, denominator);
        seizeTokens = mul_ScalarTruncate(ratio, actualRepayAmount);
        return (uint(Error.NO_ERROR), seizeTokens);
    }

    /*** Admin Functions ***/

    /**
     * @notice Sets the ltv thresholds used when liquidating borrows
     * @dev Admin function to set ltv thresholds 
     * @param _ltvMinBadDebt min ltv to allow bad debt liquidation
     * @param _ltvMinPartialLiquidation min to allow partial liquidation
     * @return uint 0=success, otherwise a failure
     */
    function _setLtvThresholds(
        uint _ltvMinBadDebt,
        uint _ltvMinPartialLiquidation
    ) external returns (uint) {
        // Check caller is admin
        require(msg.sender == admin, "only admin");
        ltvMinBadDebtLiquidations = _ltvMinBadDebt;
        ltvMinPartialLiquidations = _ltvMinPartialLiquidation;

        return uint(Error.NO_ERROR);
    }


    /**
     * @notice Sets a new price oracle for the comptroller
     * @dev Admin function to set a new price oracle
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function _setPriceOracle(
        PriceOracleCollateralBorrow newOracle
    ) public returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_PRICE_ORACLE_OWNER_CHECK
                );
        }

        // Track the old oracle for the comptroller
        PriceOracleCollateralBorrow oldOracle = oracle;

        // Set comptroller's oracle to newOracle
        oracle = newOracle;

        // Emit NewPriceOracle(oldOracle, newOracle)
        emit NewPriceOracle(oldOracle, newOracle);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sets the closeFactor used when liquidating borrows
     * @dev Admin function to set closeFactor
     * @param newCloseFactorMantissa New close factor, scaled by 1e18
     * @return uint 0=success, otherwise a failure
     */
    function _setCloseFactor(
        uint newCloseFactorMantissa
    ) external returns (uint) {
        // Check caller is admin
        require(msg.sender == admin, "only admin can set close factor");

        uint oldCloseFactorMantissa = closeFactorMantissa;
        closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, closeFactorMantissa);

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sets the collateralFactor for a market
     * @dev Admin function to set per-market collateralFactor
     * @param cToken The market to set the factor on
     * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
     * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
     */
    function _setCollateralFactor(
        CNumaToken cToken,
        uint newCollateralFactorMantissa
    ) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_COLLATERAL_FACTOR_OWNER_CHECK
                );
        }

        // Verify market is listed
        Market storage market = markets[address(cToken)];
        if (!market.isListed) {
            return
                fail(
                    Error.MARKET_NOT_LISTED,
                    FailureInfo.SET_COLLATERAL_FACTOR_NO_EXISTS
                );
        }

        Exp memory newCollateralFactorExp = Exp({
            mantissa: newCollateralFactorMantissa
        });

        // Check collateral factor <= 0.9
        Exp memory highLimit = Exp({mantissa: collateralFactorMaxMantissa});
        if (lessThanExp(highLimit, newCollateralFactorExp)) {
            return
                fail(
                    Error.INVALID_COLLATERAL_FACTOR,
                    FailureInfo.SET_COLLATERAL_FACTOR_VALIDATION
                );
        }

        // If collateral factor != 0, fail if price == 0
        if (
            newCollateralFactorMantissa != 0 &&
            oracle.getUnderlyingPriceAsCollateral(cToken) == 0
        ) {
            return
                fail(
                    Error.PRICE_ERROR,
                    FailureInfo.SET_COLLATERAL_FACTOR_WITHOUT_PRICE
                );
        }

        // Set market's collateral factor to new collateral factor, remember old value
        uint oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(
            cToken,
            oldCollateralFactorMantissa,
            newCollateralFactorMantissa
        );

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Sets liquidationIncentive
     * @dev Admin function to set liquidationIncentive
     * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
     * @return uint 0=success, otherwise a failure. (See ErrorReporter for details)
     */
    function _setLiquidationIncentive(
        uint newLiquidationIncentiveMantissa
    ) external returns (uint) {
        // Check caller is admin
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_LIQUIDATION_INCENTIVE_OWNER_CHECK
                );
        }

        // Save current value for use in log
        uint oldLiquidationIncentiveMantissa = liquidationIncentiveMantissa;

        // Set liquidation incentive to new incentive
        liquidationIncentiveMantissa = newLiquidationIncentiveMantissa;

        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(
            oldLiquidationIncentiveMantissa,
            newLiquidationIncentiveMantissa
        );

        return uint(Error.NO_ERROR);
    }

    /**
     * @notice Add the market to the markets mapping and set it as listed
     * @dev Admin function to set isListed and add support for the market
     * @param cToken The address of the market (token) to list
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _supportMarket(CToken cToken) external returns (uint) {
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SUPPORT_MARKET_OWNER_CHECK
                );
        }

        if (markets[address(cToken)].isListed) {
            return
                fail(
                    Error.MARKET_ALREADY_LISTED,
                    FailureInfo.SUPPORT_MARKET_EXISTS
                );
        }

        cToken.isCToken(); // Sanity check to make sure its really a CToken

        Market storage newMarket = markets[address(cToken)];
        newMarket.isListed = true;
        newMarket.collateralFactorMantissa = 0;

        _addMarketInternal(address(cToken));
        _initializeMarket(address(cToken));

        emit MarketListed(cToken);

        return uint(Error.NO_ERROR);
    }

    function _addMarketInternal(address cToken) internal {
        for (uint i = 0; i < allMarkets.length; i++) {
            require(allMarkets[i] != CToken(cToken), "market already added");
        }
        allMarkets.push(CToken(cToken));
    }

    function _initializeMarket(address cToken) internal {
        uint32 blockNumber = safe32(
            getBlockNumber(),
            "block number exceeds 32 bits"
        );

        CompMarketState storage supplyState = compSupplyState[cToken];
        CompMarketState storage borrowState = compBorrowState[cToken];

        /*
         * Update market state indices
         */
        if (supplyState.index == 0) {
            // Initialize supply state index with default value
            supplyState.index = compInitialIndex;
        }

        if (borrowState.index == 0) {
            // Initialize borrow state index with default value
            borrowState.index = compInitialIndex;
        }

        /*
         * Update market state block numbers
         */
        supplyState.block = borrowState.block = blockNumber;
    }

    /**
     * @notice Set the given borrow caps for the given cToken markets. Borrowing that brings total borrows to or above borrow cap will revert.
     * @dev Admin or borrowCapGuardian function to set the borrow caps. A borrow cap of 0 corresponds to unlimited borrowing.
     * @param cTokens The addresses of the markets (tokens) to change the borrow caps for
     * @param newBorrowCaps The new borrow cap values in underlying to be set. A value of 0 corresponds to unlimited borrowing.
     */
    function _setMarketBorrowCaps(
        CToken[] calldata cTokens,
        uint[] calldata newBorrowCaps
    ) external {
        require(
            msg.sender == admin || msg.sender == borrowCapGuardian,
            "only admin or borrow cap guardian can set borrow caps"
        );

        uint numMarkets = cTokens.length;
        uint numBorrowCaps = newBorrowCaps.length;

        require(
            numMarkets != 0 && numMarkets == numBorrowCaps,
            "invalid input"
        );

        for (uint i = 0; i < numMarkets; i++) {
            borrowCaps[address(cTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(cTokens[i], newBorrowCaps[i]);
        }
    }

    /**
     * @notice Admin function to change the Borrow Cap Guardian
     * @param newBorrowCapGuardian The address of the new Borrow Cap Guardian
     */
    function _setBorrowCapGuardian(address newBorrowCapGuardian) external {
        require(msg.sender == admin, "only admin can set borrow cap guardian");

        // Save current value for inclusion in log
        address oldBorrowCapGuardian = borrowCapGuardian;

        // Store borrowCapGuardian with value newBorrowCapGuardian
        borrowCapGuardian = newBorrowCapGuardian;

        // Emit NewBorrowCapGuardian(OldBorrowCapGuardian, NewBorrowCapGuardian)
        emit NewBorrowCapGuardian(oldBorrowCapGuardian, newBorrowCapGuardian);
    }

    /**
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function _setPauseGuardian(address newPauseGuardian) public returns (uint) {
        if (msg.sender != admin) {
            return
                fail(
                    Error.UNAUTHORIZED,
                    FailureInfo.SET_PAUSE_GUARDIAN_OWNER_CHECK
                );
        }

        // Save current value for inclusion in log
        address oldPauseGuardian = pauseGuardian;

        // Store pauseGuardian with value newPauseGuardian
        pauseGuardian = newPauseGuardian;

        // Emit NewPauseGuardian(OldPauseGuardian, NewPauseGuardian)
        emit NewPauseGuardian(oldPauseGuardian, pauseGuardian);

        return uint(Error.NO_ERROR);
    }

    function _setMintPaused(CToken cToken, bool state) public returns (bool) {
        require(
            markets[address(cToken)].isListed,
            "cannot pause a market that is not listed"
        );
        require(
            msg.sender == pauseGuardian || msg.sender == admin,
            "only pause guardian and admin can pause"
        );
        require(msg.sender == admin || state == true, "only admin can unpause");

        mintGuardianPaused[address(cToken)] = state;
        emit ActionPaused(cToken, "Mint", state);
        return state;
    }

    function _setBorrowPaused(CToken cToken, bool state) public returns (bool) {
        require(
            markets[address(cToken)].isListed,
            "cannot pause a market that is not listed"
        );
        require(
            msg.sender == pauseGuardian || msg.sender == admin,
            "only pause guardian and admin can pause"
        );
        require(msg.sender == admin || state == true, "only admin can unpause");

        borrowGuardianPaused[address(cToken)] = state;
        emit ActionPaused(cToken, "Borrow", state);
        return state;
    }

    function _setTransferPaused(bool state) public returns (bool) {
        require(
            msg.sender == pauseGuardian || msg.sender == admin,
            "only pause guardian and admin can pause"
        );
        require(msg.sender == admin || state == true, "only admin can unpause");

        transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    function _setSeizePaused(bool state) public returns (bool) {
        require(
            msg.sender == pauseGuardian || msg.sender == admin,
            "only pause guardian and admin can pause"
        );
        require(msg.sender == admin || state == true, "only admin can unpause");

        seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    function _setRedeemPaused(bool state) public returns (bool) {
        require(
            msg.sender == pauseGuardian || msg.sender == admin,
            "only pause guardian and admin can pause"
        );
        require(msg.sender == admin || state == true, "only admin can unpause");

        redeemGuardianPaused = state;
        emit ActionPaused("Redeem", state);
        return state;
    }

    function _setRepayPaused(bool state) public returns (bool) {
        require(
            msg.sender == pauseGuardian || msg.sender == admin,
            "only pause guardian and admin can pause"
        );
        require(msg.sender == admin || state == true, "only admin can unpause");

        repayGuardianPaused = state;
        emit ActionPaused("Repay", state);
        return state;
    }

    function _become(Unitroller unitroller) public {
        require(
            msg.sender == unitroller.admin(),
            "only unitroller admin can change brains"
        );
        require(
            unitroller._acceptImplementation() == 0,
            "change not authorized"
        );
    }

    /**
     * @notice Checks caller is admin, or this contract is becoming the new implementation
     */
    function adminOrInitializing() internal view returns (bool) {
        return msg.sender == admin || msg.sender == comptrollerImplementation;
    }

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     * @return The list of market addresses
     */
    function getAllMarkets() public view returns (CToken[] memory) {
        return allMarkets;
    }

    /**
     * @notice Returns true if the given cToken market has been deprecated
     * @dev All borrows in a deprecated cToken market can be immediately liquidated
     * @param cToken The market to check if deprecated
     */
    function isDeprecated(CToken cToken) public view returns (bool) {
        return
            markets[address(cToken)].collateralFactorMantissa == 0 &&
            borrowGuardianPaused[address(cToken)] == true &&
            cToken.reserveFactorMantissa() == 1e18;
    }

    function getBlockNumber() public view virtual returns (uint) {
        return block.number;
    }
}
