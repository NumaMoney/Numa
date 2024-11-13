// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "./CNumaToken.sol";

import "@openzeppelin/contracts_5.0.2/token/ERC20/utils/SafeERC20.sol";

/**
 * @title CNumaLst
 * @notice CTokens used with numa vault
 * @author
 */
contract CNumaLst is CNumaToken {
    constructor(
        address underlying_,
        ComptrollerInterface comptroller_,
        InterestRateModel interestRateModel_,
        uint initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint fullUtilizationRate_,
        address payable admin_,
        address _vault
    )
        CNumaToken(
            underlying_,
            comptroller_,
            interestRateModel_,
            initialExchangeRateMantissa_,
            name_,
            symbol_,
            decimals_,
            fullUtilizationRate_,
            admin_,
            _vault
        )
    {}

    /**
     * @notice Returns the current per-block borrow interest rate for this cToken
     * @return The borrow interest rate per block, scaled by 1e18
     */
    function borrowRatePerBlock() external view override returns (uint) {
        // NUMALENDING
        // borrow rate is based on lending contract cash & vault available to borrow
        uint maxBorrowableAmountFromVault;
        if (address(vault) != address(0))
            maxBorrowableAmountFromVault = vault.getMaxBorrow();

        uint currentTimestamp = block.timestamp;
        uint timestampPrior = accrualBlockTimestamp;
        uint deltaTime = currentTimestamp - timestampPrior;

        (uint ratePerBlock, ) = interestRateModel.getBorrowRate(
            getCashPrior() + maxBorrowableAmountFromVault,
            totalBorrows,
            totalReserves,
            deltaTime,
            fullUtilizationRate
        );
        return ratePerBlock;
    }

    /**
     * @notice Returns the current per-block supply interest rate for this cToken
     * @return The supply interest rate per block, scaled by 1e18
     */
    function supplyRatePerBlock() external view override returns (uint) {
        // NUMALENDING
        // supply rate is based on lending contract cash & vault available to borrow
        uint maxBorrowableAmountFromVault;
        if (address(vault) != address(0))
            maxBorrowableAmountFromVault = vault.getMaxBorrow();

        uint currentTimestamp = block.timestamp;
        uint timestampPrior = accrualBlockTimestamp;
        uint deltaTime = currentTimestamp - timestampPrior;

        return
            interestRateModel.getSupplyRate(
                getCashPrior() + maxBorrowableAmountFromVault,
                totalBorrows,
                totalReserves,
                reserveFactorMantissa,
                deltaTime,
                fullUtilizationRate
            );
    }

    /**
     * @notice Applies accrued interest to total borrows and reserves
     * @dev This calculates interest accrued from the last checkpointed block
     *   up to the current block and writes new checkpoint to storage.
     */
    function accrueInterest() public virtual override returns (uint) {
        /* Remember the initial block number */
        uint currentBlockNumber = getBlockNumber();
        uint accrualBlockNumberPrior = accrualBlockNumber;
        /* Short-circuit accumulating 0 interest */
        if (accrualBlockNumberPrior == currentBlockNumber) {
            return NO_ERROR;
        }

        /* Read the previous values out of storage */
        // NUMALENDING
        // interest rate is based on lending contract cash & vault available to borrow
        uint maxBorrowableAmountFromVault;
        if (address(vault) != address(0))
            maxBorrowableAmountFromVault = vault.getMaxBorrow();

        uint cashPrior = getCashPrior() + maxBorrowableAmountFromVault;
        uint borrowsPrior = totalBorrows;
        uint reservesPrior = totalReserves;
        uint borrowIndexPrior = borrowIndex;

        /* Calculate the current borrow interest rate */
        (
            uint borrowRateMantissa,
            uint newfullUtilizationRate
        ) = interestRateModel.getBorrowRate(
                cashPrior,
                borrowsPrior,
                reservesPrior,
                block.timestamp - accrualBlockTimestamp,
                fullUtilizationRate
            );
        require(
            borrowRateMantissa <= borrowRateMaxMantissa,
            "borrow rate is absurdly high"
        );

        /* Calculate the number of blocks elapsed since the last accrual */
        uint blockDelta = currentBlockNumber - accrualBlockNumberPrior;

        /*
         * Calculate the interest accumulated into borrows and reserves and the new index:
         *  simpleInterestFactor = borrowRate * blockDelta
         *  interestAccumulated = simpleInterestFactor * totalBorrows
         *  totalBorrowsNew = interestAccumulated + totalBorrows
         *  totalReservesNew = interestAccumulated * reserveFactor + totalReserves
         *  borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex
         */

        Exp memory simpleInterestFactor = mul_(
            Exp({mantissa: borrowRateMantissa}),
            blockDelta
        );
        uint interestAccumulated = mul_ScalarTruncate(
            simpleInterestFactor,
            borrowsPrior
        );
        uint totalBorrowsNew = interestAccumulated + borrowsPrior;
        uint totalReservesNew = mul_ScalarTruncateAddUInt(
            Exp({mantissa: reserveFactorMantissa}),
            interestAccumulated,
            reservesPrior
        );
        uint borrowIndexNew = mul_ScalarTruncateAddUInt(
            simpleInterestFactor,
            borrowIndexPrior,
            borrowIndexPrior
        );

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        accrualBlockNumber = currentBlockNumber;
        accrualBlockTimestamp = block.timestamp;
        borrowIndex = borrowIndexNew;
        totalBorrows = totalBorrowsNew;
        totalReserves = totalReservesNew;

        if (fullUtilizationRate != newfullUtilizationRate) {
            emit UpdateRate(fullUtilizationRate, newfullUtilizationRate);
            fullUtilizationRate = newfullUtilizationRate;
        }

        /* We emit an AccrueInterest event */
        emit AccrueInterest(
            cashPrior,
            interestAccumulated,
            borrowIndexNew,
            totalBorrowsNew
        );

        return NO_ERROR;
    }

    function borrowFreshNoTransfer(
        address payable borrower,
        uint borrowAmount
    ) internal virtual override {
        /* Fail if borrow not allowed */
        uint allowed = comptroller.borrowAllowed(
            address(this),
            borrower,
            borrowAmount
        );
        if (allowed != 0) {
            revert BorrowComptrollerRejection(allowed);
        }

        /* Verify market's block number equals current block number */
        if (accrualBlockNumber != getBlockNumber()) {
            revert BorrowFreshnessCheck();
        }

        /* Fail gracefully if protocol has insufficient underlying cash */
        uint cashPrior = getCashPrior();
        if (cashPrior < borrowAmount) {
            // not enough cash in lending contract, check if we can get some from the vault
            // NUMALENDING
            //
            if (address(vault) != address(0)) {
                uint amountNeeded = borrowAmount - cashPrior;
                uint maxBorrowableAmountFromVault = vault.getMaxBorrow();
                if (amountNeeded <= maxBorrowableAmountFromVault) {
                    // if ok, borrow from vault
                    vault.borrow(amountNeeded);
                } else {
                    // not enough in vault
                    revert BorrowCashNotAvailable();
                }
            } else {
                revert BorrowCashNotAvailable();
            }
        }

        /*
         * We calculate the new borrower and total borrow balances, failing on overflow:
         *  accountBorrowNew = accountBorrow + borrowAmount
         *  totalBorrowsNew = totalBorrows + borrowAmount
         */
        uint accountBorrowsPrev = borrowBalanceStoredInternal(borrower);
        uint accountBorrowsNew = accountBorrowsPrev + borrowAmount;
        uint totalBorrowsNew = totalBorrows + borrowAmount;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We write the previously calculated values into storage.
         *  Note: Avoid token reentrancy attacks by writing increased borrow before external transfer.
        `*/
        accountBorrows[borrower].principal = accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = totalBorrowsNew;

        /* We emit a Borrow event */
        emit Borrow(borrower, borrowAmount, accountBorrowsNew, totalBorrowsNew);
    }

    /**
     * @notice Borrows are repaid by another user (possibly the borrower).
     * @param payer the account paying off the borrow
     * @param borrower the account with the debt being payed off
     * @param repayAmount the amount of underlying tokens being returned, or -1 for the full outstanding amount
     * @return (uint) the actual repayment amount.
     */
    function repayBorrowFresh(
        address payer,
        address borrower,
        uint repayAmount
    ) internal override returns (uint) {
        uint actualRepayAmount = CToken.repayBorrowFresh(
            payer,
            borrower,
            repayAmount
        );
        // NUMALENDING
        // if we have debt from the vault, repay vault first
        uint vaultDebt = vault.getDebt();
        if (vaultDebt > 0) {
            uint repayToVault = vaultDebt;
            if (actualRepayAmount <= vaultDebt) {
                repayToVault = actualRepayAmount;
            }
            // repay vault debt
            EIP20Interface(underlying).approve(address(vault), repayToVault);
            vault.repay(repayToVault);
        }

        return actualRepayAmount;
    }

    /**
     * @notice User redeems cTokens in exchange for the underlying asset
     * @dev Assumes interest has already been accrued up to the current block
     * @param redeemer The address of the account which is redeeming the tokens
     * @param redeemTokensIn The number of cTokens to redeem into underlying (only one of redeemTokensIn or redeemAmountIn may be non-zero)
     * @param redeemAmountIn The number of underlying tokens to receive from redeeming cTokens (only one of redeemTokensIn or redeemAmountIn may be non-zero)
     */
    function redeemFresh(
        address payable redeemer,
        uint redeemTokensIn,
        uint redeemAmountIn
    ) internal override {
        require(
            redeemTokensIn == 0 || redeemAmountIn == 0,
            "one of redeemTokensIn or redeemAmountIn must be zero"
        );

        /* exchangeRate = invoke Exchange Rate Stored() */
        Exp memory exchangeRate = Exp({mantissa: exchangeRateStoredInternal()});

        uint redeemTokens;
        uint redeemAmount;

        /* If redeemTokensIn > 0: */
        if (redeemTokensIn > 0) {
            /*
             * We calculate the exchange rate and the amount of underlying to be redeemed:
             *  redeemTokens = redeemTokensIn
             *  redeemAmount = redeemTokensIn x exchangeRateCurrent
             */
            redeemTokens = redeemTokensIn;
            redeemAmount = mul_ScalarTruncate(exchangeRate, redeemTokensIn);
        } else {
            /*
             * We get the current exchange rate and calculate the amount to be redeemed:
             *  redeemTokens = redeemAmountIn / exchangeRate
             *  redeemAmount = redeemAmountIn
             */

            redeemTokens = div_(redeemAmountIn, exchangeRate);
            redeemAmount = redeemAmountIn;
            // // NUMALENDING
            // // this was not in original compound code but I think it's necessary
            // // because due to exchange rate we might ask for more underlying tokens than equvalent in cTokens
            // // for example X + 500 000 000 wei is equivalent to X
            // redeemAmount = mul_ScalarTruncate(exchangeRate, redeemTokens);
        }

        /* Fail if redeem not allowed */
        uint allowed = comptroller.redeemAllowed(
            address(this),
            redeemer,
            redeemTokens
        );
        if (allowed != 0) {
            revert RedeemComptrollerRejection(allowed);
        }

        /* Verify market's block number equals current block number */
        if (accrualBlockNumber != getBlockNumber()) {
            revert RedeemFreshnessCheck();
        }

        if (getCashPrior() < redeemAmount) {
            // NUMALENDING
            // try to redeem from vault
            uint amountNeeded = redeemAmount - getCashPrior();
            uint maxBorrowableAmountFromVault;
            if (address(vault) != address(0))
                maxBorrowableAmountFromVault = vault.getMaxBorrow();
            if (amountNeeded <= maxBorrowableAmountFromVault) {
                // if ok, borrow from vault
                vault.borrow(amountNeeded);
            } else {
                revert RedeemTransferOutNotPossible();
            }
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We write the previously calculated values into storage.
         *  Note: Avoid token reentrancy attacks by writing reduced supply before external transfer.
         */
        totalSupply = totalSupply - redeemTokens;
        accountTokens[redeemer] = accountTokens[redeemer] - redeemTokens;

        /*
         * We invoke doTransferOut for the redeemer and the redeemAmount.
         *  Note: The cToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the cToken has redeemAmount less of cash.
         *  doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
         */
        doTransferOut(redeemer, redeemAmount);

        /* We emit a Transfer event, and a Redeem event */
        emit Transfer(redeemer, address(this), redeemTokens);
        emit Redeem(redeemer, redeemAmount, redeemTokens);

        /* We call the defense hook */
        comptroller.redeemVerify(
            address(this),
            redeemer,
            redeemAmount,
            redeemTokens
        );
    }

    /**
     * @notice Calculates the exchange rate from the underlying to the CToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return calculated exchange rate scaled by 1e18
     */
    function exchangeRateStoredInternal()
        internal
        view
        override
        returns (uint)
    {
        uint _totalSupply = totalSupply;
        if (_totalSupply == 0) {
            /*
             * If there are no tokens minted:
             *  exchangeRate = initialExchangeRate
             */
            return initialExchangeRateMantissa;
        } else {
            /*
             * Otherwise:
             *  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
             */
            uint totalCash = getCashPrior();
            // NUMALENDING
            // vault debt does not count for exchange rate
            uint vaultDebt = vault.getDebt();
            uint cashPlusBorrowsMinusReserves = totalCash +
                totalBorrows -
                vaultDebt -
                totalReserves;
            uint exchangeRate = (cashPlusBorrowsMinusReserves * expScale) /
                _totalSupply;

            return exchangeRate;
        }
    }
}
