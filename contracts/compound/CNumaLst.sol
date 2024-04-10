// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "./CErc20Immutable.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/INumaVault.sol";
import "hardhat/console.sol";
/**
 * @title Compound's CErc20 Contract
 * @notice CTokens which wrap an EIP-20 underlying
 * @author Compound
 */
contract CNumaLst is CErc20Immutable
{
    
    INumaVault vault;

    /// @notice set vault event
    event SetVault(address vaultAddress);
    
    constructor(address underlying_,
                ComptrollerInterface comptroller_,
                InterestRateModel interestRateModel_,
                uint initialExchangeRateMantissa_,
                string memory name_,
                string memory symbol_,
                uint8 decimals_,
                address payable admin_,address _vault)
                CErc20Immutable(underlying_,
                comptroller_,
                interestRateModel_,
                initialExchangeRateMantissa_,
                name_,
                symbol_,
                decimals_,
                 admin_)
    {
        vault = INumaVault(_vault);
    }

    function setVault(address _vault) external  
    {
        require(msg.sender == admin, "only admin can set vault");
        vault = INumaVault(_vault);
        emit SetVault(_vault);
    }


    /**
     * @notice Applies accrued interest to total borrows and reserves
     * @dev This calculates interest accrued from the last checkpointed block
     *   up to the current block and writes new checkpoint to storage.
     */
    function accrueInterest() virtual override public returns (uint) {
        /* Remember the initial block number */
        uint currentBlockNumber = getBlockNumber();
        uint accrualBlockNumberPrior = accrualBlockNumber;

        /* Short-circuit accumulating 0 interest */
        if (accrualBlockNumberPrior == currentBlockNumber) {
            return NO_ERROR;
        }

        /* Read the previous values out of storage */
        // NUMALENDING
        uint maxBorrowableAmountFromVault;
        if (address(vault) != address(0))
            maxBorrowableAmountFromVault = vault.GetMaxBorrow();

        uint cashPrior = getCashPrior();
        uint borrowsPrior = totalBorrows;
        uint reservesPrior = totalReserves;
        uint borrowIndexPrior = borrowIndex;

        /* Calculate the current borrow interest rate */
        uint borrowRateMantissa = interestRateModel.getBorrowRate(cashPrior+maxBorrowableAmountFromVault, borrowsPrior, reservesPrior);
        require(borrowRateMantissa <= borrowRateMaxMantissa, "borrow rate is absurdly high");

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

        Exp memory simpleInterestFactor = mul_(Exp({mantissa: borrowRateMantissa}), blockDelta);
        uint interestAccumulated = mul_ScalarTruncate(simpleInterestFactor, borrowsPrior);
        uint totalBorrowsNew = interestAccumulated + borrowsPrior;
        uint totalReservesNew = mul_ScalarTruncateAddUInt(Exp({mantissa: reserveFactorMantissa}), interestAccumulated, reservesPrior);
        uint borrowIndexNew = mul_ScalarTruncateAddUInt(simpleInterestFactor, borrowIndexPrior, borrowIndexPrior);

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        accrualBlockNumber = currentBlockNumber;
        borrowIndex = borrowIndexNew;
        totalBorrows = totalBorrowsNew;
        totalReserves = totalReservesNew;

        /* We emit an AccrueInterest event */
        emit AccrueInterest(cashPrior, interestAccumulated, borrowIndexNew, totalBorrowsNew);

        return NO_ERROR;
    }


// TODO: only for rETh!!!
     /**
      * @notice Users borrow assets from the protocol to their own address
      * @param borrowAmount The amount of the underlying asset to borrow
      */
    function borrowFresh(address payable borrower, uint borrowAmount) virtual override internal {
        /* Fail if borrow not allowed */
        uint allowed = comptroller.borrowAllowed(address(this), borrower, borrowAmount);
        if (allowed != 0) {
            revert BorrowComptrollerRejection(allowed);
        }

        /* Verify market's block number equals current block number */
        if (accrualBlockNumber != getBlockNumber()) {
            revert BorrowFreshnessCheck();
        }


        /* Fail gracefully if protocol has insufficient underlying cash */
        uint cashPrior = getCashPrior();
        if (cashPrior < borrowAmount)
        {
            // NUMALENDING
            // 
            if (address(vault) != address(0))
            {
                uint amountNeeded = borrowAmount - cashPrior;
                uint maxBorrowableAmountFromVault = vault.GetMaxBorrow();
                console.log("borrowfresh numalst");
                console.logUint(maxBorrowableAmountFromVault);
                console.logUint(amountNeeded);
                if (amountNeeded <= maxBorrowableAmountFromVault)
                {
                    // if ok, borrow from vault
            
                    // transferFromVault
                    // TODO vault function with whitelist! (because we can take money)
                    // uint currentDebt = vault.getDebt();
                    // //vault.SetDebt(currentDebt + amountNeeded);// careful onlyowner
                    // // TODO: approve
                    // SafeERC20.safeTransferFrom(
                    //     IERC20(underlying),
                    //     address(vault),
                    //     address(this),
                    // amountNeeded);

                    vault.borrow(amountNeeded);
                }
                else
                {
                    // TODO specific error
                    revert BorrowCashNotAvailable();
                }
            }
            else
            {
                console.log("no vault");
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

        /*
         * We invoke doTransferOut for the borrower and the borrowAmount.
         *  Note: The cToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the cToken borrowAmount less of cash.
         *  doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
         */
        doTransferOut(borrower, borrowAmount);

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
    function repayBorrowFresh(address payer, address borrower, uint repayAmount) internal override returns (uint) {
        /* Fail if repayBorrow not allowed */
        uint allowed = comptroller.repayBorrowAllowed(address(this), payer, borrower, repayAmount);
        if (allowed != 0) {
            revert RepayBorrowComptrollerRejection(allowed);
        }

        /* Verify market's block number equals current block number */
        if (accrualBlockNumber != getBlockNumber()) {
            revert RepayBorrowFreshnessCheck();
        }

        /* We fetch the amount the borrower owes, with accumulated interest */
        uint accountBorrowsPrev = borrowBalanceStoredInternal(borrower);

        /* If repayAmount == -1, repayAmount = accountBorrows */
        uint repayAmountFinal = repayAmount == type(uint).max ? accountBorrowsPrev : repayAmount;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We call doTransferIn for the payer and the repayAmount
         *  Note: The cToken must handle variations between ERC-20 and ETH underlying.
         *  On success, the cToken holds an additional repayAmount of cash.
         *  doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
         *   it returns the amount actually transferred, in case of a fee.
         */
        uint actualRepayAmount = doTransferIn(payer, repayAmountFinal);

        /*
         * We calculate the new borrower and total borrow balances, failing on underflow:
         *  accountBorrowsNew = accountBorrows - actualRepayAmount
         *  totalBorrowsNew = totalBorrows - actualRepayAmount
         */
        uint accountBorrowsNew = accountBorrowsPrev - actualRepayAmount;
        uint totalBorrowsNew = totalBorrows - actualRepayAmount;

        /* We write the previously calculated values into storage */
        accountBorrows[borrower].principal = accountBorrowsNew;
        accountBorrows[borrower].interestIndex = borrowIndex;
        totalBorrows = totalBorrowsNew;

        // NUMALENDING
        // TODO: only for crETH!!!
        uint vaultDebt = vault.getDebt();
        if (vaultDebt > 0)
        {
            // parameters: 
            // - URtarget: 80%
            // - vaultPercent: 80%
            // we keep what's needed to keep a X% Utilization rate
            uint URtarget = 0.8 ether;
            uint vaultPercent = 0.8 ether;

            // what is current UR (considering repayment)
            uint cashPrior = getCashPrior();
            uint borrowsPrior = totalBorrows;
            uint reservesPrior = totalReserves;

            uint realURAfterRepay = interestRateModel.utilizationRate(cashPrior, borrowsPrior, reservesPrior);
            console.log("real UR after repay");
            console.logUint(realURAfterRepay);
            if (realURAfterRepay < URtarget)
            {
                // how much cash do we need in the lending protocol to keep URTarget
                uint cashMin = (borrowsPrior * (1 ether - URtarget))/URtarget;
                console.log("compute");
                 console.logUint(borrowsPrior);
                 console.logUint(borrowsPrior * (1 ether - URtarget));
                 

                 console.logUint(cashMin);
                // how much can we keep after keeping this target UR
                uint remainingAmountAfterKeepingUR = cashPrior - cashMin;

                console.logUint(remainingAmountAfterKeepingUR);
                // only take from what was repaid, if it's above, it means we were already under targetUR
                if (remainingAmountAfterKeepingUR > actualRepayAmount)
                {
                    console.log("only take from what was repaid");
                    remainingAmountAfterKeepingUR = actualRepayAmount;
                }
                if (remainingAmountAfterKeepingUR > 0)
                {
                    console.log("send to vault");
                    // we have more than what was needed to keep target UR
                    // then 80% go to vault
                    console.logUint(remainingAmountAfterKeepingUR);
                    
                    uint amountToRepayToVault = (remainingAmountAfterKeepingUR *vaultPercent) / (1 ether);
                    console.logUint(amountToRepayToVault);
                    if (amountToRepayToVault > vaultDebt)
                    {
                        console.log("more than debt");
                        // if we have more than vault debt, cap it
                        amountToRepayToVault = vaultDebt;   
                        
                    }
                    EIP20Interface(underlying).approve(address(vault),amountToRepayToVault);
                    vault.repay(amountToRepayToVault);

                }
            }


        }

        /* We emit a RepayBorrow event */
        emit RepayBorrow(payer, borrower, actualRepayAmount, accountBorrowsNew, totalBorrowsNew);

        return actualRepayAmount;
    }


    /**
     * @notice Calculates the exchange rate from the underlying to the CToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return calculated exchange rate scaled by 1e18
     */
    function exchangeRateStoredInternal() override internal view returns (uint) {
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
            uint cashPlusBorrowsMinusReserves = totalCash + totalBorrows - vaultDebt - totalReserves;
            uint exchangeRate = cashPlusBorrowsMinusReserves * expScale / _totalSupply;

            return exchangeRate;
        }
    }

  
}
