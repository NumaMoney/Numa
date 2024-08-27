// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.20;

import "./CErc20Immutable.sol";

import "@openzeppelin/contracts_5.0.2/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/INumaVault.sol";

/**
 * @title CNumaToken
 * @notice CTokens used with numa vault
 * @author 
 */
contract CNumaToken is CErc20Immutable
{
    
    INumaVault vault;
    uint margin = 1;
    uint margin_base = 100000000000000;

    /// @notice set vault event
    event SetVault(address vaultAddress);
    /// @notice open leverage event
    event LeverageOpen(CNumaToken indexed _collateral,uint _suppliedAmount,uint _borrowAmountVault,uint _borrowAmount);
    /// @notice close leverage event
    event LeverageClose(CNumaToken indexed _collateral,uint _borrowtorepay);

    constructor(address underlying_,
                ComptrollerInterface comptroller_,
                InterestRateModel interestRateModel_,
                uint initialExchangeRateMantissa_,
                string memory name_,
                string memory symbol_,
                uint8 decimals_,
                uint fullUtilizationRate_,
                address payable admin_,address _vault)
                CErc20Immutable(underlying_,
                comptroller_,
                interestRateModel_,
                initialExchangeRateMantissa_,
                name_,
                symbol_,
                decimals_,
                fullUtilizationRate_,
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
    /**
     * @notice leverage by depositing and borrowing
     * LTV will be _borrowAmount/(_borrowAmount+_suppliedAmount)
     * 1) flash borrow _collateral.underlying from vault (will be repaid at the end of the function)
     * 2) deposit as collateral (mint input CNumaToken), send minted Ctoken to sender
     * 3) borrow other token using collateral
     * 4) convert to other token using vault
     * 5) flash repay vault
     * 
     */
    function leverage(uint _suppliedAmount,uint _borrowAmount,CNumaToken _collateral) external 
    {
        address underlyingCollateral = _collateral.underlying();

        // borrow from vault
        vault.borrowLeverage(_borrowAmount,false);
        // get user tokens
        SafeERC20.safeTransferFrom(IERC20(underlyingCollateral),msg.sender,address(this),_suppliedAmount);
        uint totalAmount = _suppliedAmount + _borrowAmount;

        // supply (mint collateral)
        uint balCtokenBefore = EIP20Interface(address(_collateral)).balanceOf(address(this));
        EIP20Interface(underlyingCollateral).approve(address(_collateral),totalAmount);
        _collateral.mint(totalAmount);
        uint balCtokenAfter = EIP20Interface(address(_collateral)).balanceOf(address(this));

        // send collateral to sender
        uint receivedtokens  = balCtokenAfter - balCtokenBefore;
        require(receivedtokens > 0, "no collateral");

        // transfer collateral to sender
        SafeERC20.safeTransfer(IERC20(address(_collateral)), msg.sender, receivedtokens);
       
       // how much to we need to borrow to repay vault
       uint borrowAmount = vault.getAmountIn(_borrowAmount,false);
       // overestimate a little to be sure to be able to repay
       borrowAmount = borrowAmount + (borrowAmount * margin)/margin_base;
       uint accountBorrowBefore = accountBorrows[msg.sender].principal;
       // borrow but do not transfer borrowed tokens
       borrowInternalNoTransfer(borrowAmount,msg.sender);
       uint accountBorrowAfter = accountBorrows[msg.sender].principal;
       require((accountBorrowAfter - accountBorrowBefore) == borrowAmount,"borrow ko");

       // buy/sell from the vault
       EIP20Interface(underlying).approve(address(vault),borrowAmount);
       uint collateralReceived = vault.buyFromCToken(borrowAmount,_borrowAmount,false);

       // repay vault
       EIP20Interface(underlyingCollateral).approve(address(vault),_borrowAmount);
       vault.repayLeverage(false);

       // refund if needed
       if (collateralReceived > _borrowAmount)
       {
           // send back the surplus
           SafeERC20.safeTransfer(IERC20(underlyingCollateral), msg.sender, collateralReceived - _borrowAmount);
       }
       emit LeverageOpen( _collateral,_suppliedAmount,_borrowAmount,borrowAmount);
    }

    // estimate amount needed to approve to close leverage
    // TODO: might not be up to date, is there way to estimate up to date value?
    function closeLeverageAmount(CNumaToken _collateral,uint _borrowtorepay) external view returns (uint) 
    {
        // amount of underlying needed
        uint swapAmountIn = vault.getAmountIn(_borrowtorepay,true);

        // amount of ctokens to redeem this amount
        uint cTokenAmount = div_(swapAmountIn, _collateral.exchangeRateStored());
        return cTokenAmount;
    }
    // _collateral: collateral token
    // 1) flashloan from vault
    // 2) repay borrow
    // 3) redeem collateral
    // 4) swap for flashloaned amount
    // 5) repay flashloan
    function closeLeverage(CNumaToken _collateral,uint _borrowtorepay) external 
    {
        address underlyingCollateral = _collateral.underlying();
        // get borrowed amount
        accrueInterest();
        uint borrowAmountFull = borrowBalanceStored(msg.sender);
        require(borrowAmountFull > _borrowtorepay,"no borrow");

        // flashloan               
        vault.borrowLeverage(_borrowtorepay,true);

        // repay borrow
        repayBorrowBehalfInternal(msg.sender,_borrowtorepay) ;



        // transfer ctoken (collateral)
        // amount of underlying needed
        uint swapAmountIn = vault.getAmountIn(_borrowtorepay,true);

        // amount of ctokens to redeem this amount
        uint cTokenAmount = div_(swapAmountIn, _collateral.exchangeRateCurrent());

        // todo function to estimate cTokenAmount so that users know how much to approve
        SafeERC20.safeTransferFrom(IERC20(address(_collateral)),msg.sender,address(this),cTokenAmount);
        // redeem to underlying
        uint balBefore = IERC20(underlyingCollateral).balanceOf(address(this));
        _collateral.redeem(cTokenAmount);
        uint balAfter = IERC20(underlyingCollateral).balanceOf(address(this));
        uint received = balAfter - balBefore;
        require(received >= swapAmountIn,"not enough redeem");
        // swap to get enough token to repay flashlon

        EIP20Interface(underlyingCollateral).approve(address(vault),swapAmountIn);
        uint bought = vault.buyFromCToken(swapAmountIn,_borrowtorepay,true);

        // repay FLASHLOAN
       EIP20Interface(underlying).approve(address(vault),_borrowtorepay);
       vault.repayLeverage(true);

      // send what has not been swapped to msg.sender (surplus)
       if (bought > _borrowtorepay)
       {
           // send back the surplus
           SafeERC20.safeTransfer(IERC20(underlying), msg.sender, bought - _borrowtorepay);
       }
       emit LeverageClose(_collateral,_borrowtorepay);

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
        // only vault can liquidate
        require(msg.sender == address(vault),"vault only");
        liquidateBorrowInternal(borrower, repayAmount, cTokenCollateral);
        return NO_ERROR;
    }

    function liquidateBadDebt(address borrower, uint repayAmount,uint percentageToTake, CTokenInterface cTokenCollateral) override external returns (uint) {
        // only vault can liquidate        
        require(msg.sender == address(vault),"vault only");
        liquidateBadDebtInternal(borrower, repayAmount, percentageToTake, cTokenCollateral);
        return NO_ERROR;
    }

  
}
