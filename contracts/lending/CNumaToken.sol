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
contract CNumaToken is CErc20Immutable
{
    
    INumaVault vault;
    uint margin = 1;
    uint margin_base = 100000000000000;

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

    function setLeverageEpsilon(uint _margin,uint _marginbase) external  
    {
        require(msg.sender == admin, "only admin");
        margin = _margin;
        margin_base = _marginbase;
      
    }

    function setVault(address _vault) external  
    {
        require(msg.sender == admin, "only admin");
        vault = INumaVault(_vault);
        emit SetVault(_vault);
    }



    function borrowInternalNoTransfer(uint borrowAmount,address borrower) internal nonReentrant {
        accrueInterest();
        // borrowFresh emits borrow-specific logs on errors, so we don't need to
        borrowFreshNoTransfer(payable(borrower), borrowAmount);
    }

    // LTV will be _borrowAmount/(_borrowAmount+_suppliedAmount)
    function leverage(uint _suppliedAmount,uint _borrowAmount,CNumaToken _collateral) external 
    {
        address underlyingCollateral = _collateral.underlying();

        //
        //uint balBefore = EIP20Interface(underlyingCollateral).balanceOf(address(this));
        // borrow from vault
        uint totalAmount = _suppliedAmount + _borrowAmount;
        vault.borrowLeverage(_borrowAmount);

        // console.log("borrowed vault for leverage");
        // console.logUint(_borrowAmount);

        // get user tokens
        SafeERC20.safeTransferFrom(IERC20(underlyingCollateral),msg.sender,address(this),_suppliedAmount);
        //
        // uint balAfter = EIP20Interface(underlyingCollateral).balanceOf(address(this));

        // require((balAfter - balBefore) == totalAmount,"not enough collateral");

        // supply au niveau de l'autre ctoken
        uint balCtokenBefore = EIP20Interface(address(_collateral)).balanceOf(address(this));
        EIP20Interface(underlyingCollateral).approve(address(_collateral),totalAmount);
        _collateral.mint(totalAmount);
        uint balCtokenAfter = EIP20Interface(address(_collateral)).balanceOf(address(this));

        // send collateral to sender
        uint receivedtokens  = balCtokenAfter - balCtokenBefore;

        require(receivedtokens > 0, "no collateral");
        SafeERC20.safeTransfer(IERC20(address(_collateral)), msg.sender, receivedtokens);
       

       // borrow
       uint borrowAmount = vault.getAmountIn(_borrowAmount);
        // console.log("BORROW AMOUNT");
        // console.logUint(borrowAmount);
       // overestimate a little to be sure to be able to repay
       borrowAmount = borrowAmount + (borrowAmount * margin)/margin_base;
     // console.logUint(_borrowAmount);


        
        //uint balUnderlyingBefore = EIP20Interface(underlying).balanceOf(address(this));
        uint accountBorrowBefore = accountBorrows[msg.sender].principal;

       // console.log("vaultbalance 0");
               // uint balVault = EIP20Interface(address(underlying)).balanceOf(address(vault));
       // console.logUint(balVault);


        borrowInternalNoTransfer(borrowAmount,msg.sender);
        //uint balUnderlyingAfter = EIP20Interface(underlying).balanceOf(address(this));
        
          //      console.log("vaultbalance 1");
           //     balVault = EIP20Interface(address(underlying)).balanceOf(address(vault));
        //console.logUint(balVault);

        uint accountBorrowAfter = accountBorrows[msg.sender].principal;

        // console.log("BORROW");
        // console.logUint(accountBorrowBefore);
        // console.logUint(accountBorrowAfter);
        // just in case
        require((accountBorrowAfter - accountBorrowBefore) == borrowAmount,"borrow ko");



       EIP20Interface(underlying).approve(address(vault),borrowAmount);



       uint collateralReceived = vault.buyFromCToken(borrowAmount,_borrowAmount);
   
//                   console.log("vaultbalance 2");
        //         balVault = EIP20Interface(address(underlying)).balanceOf(address(vault));
        // console.logUint(balVault);



       // repay 
       EIP20Interface(underlyingCollateral).approve(address(vault),_borrowAmount);
       vault.repayLeverage();

       if (collateralReceived > _borrowAmount)
       {
            // send back the surplus
            SafeERC20.safeTransfer(IERC20(underlyingCollateral), msg.sender, collateralReceived - _borrowAmount);
        
       }
       
    }

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this cToken to be liquidated
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param cTokenCollateral The market in which to seize collateral from the borrower
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function liquidateBorrow(address borrower, uint repayAmount, CTokenInterface cTokenCollateral) override external returns (uint) {
        require(msg.sender == address(vault),"vault only");
        liquidateBorrowInternal(borrower, repayAmount, cTokenCollateral);
        return NO_ERROR;
    }

  
}
