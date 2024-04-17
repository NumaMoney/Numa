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
        uint balBefore = EIP20Interface(underlyingCollateral).balanceOf(address(this));
        // borrow from vault
        uint totalAmount = _suppliedAmount + _borrowAmount;
        vault.borrowLeverage(_borrowAmount);

        // get user tokens
        SafeERC20.safeTransferFrom(IERC20(underlyingCollateral),msg.sender,address(this),_suppliedAmount);
        //
        uint balAfter = EIP20Interface(underlyingCollateral).balanceOf(address(this));

        require((balAfter - balBefore) == totalAmount,"not enough collateral");

        // supply au niveau de l'autre ctoken
        uint balCtokenBefore = EIP20Interface(address(_collateral)).balanceOf(address(this));
        EIP20Interface(underlyingCollateral).approve(address(_collateral),totalAmount);
        _collateral.mint(totalAmount);
        uint balCtokenAfter = EIP20Interface(address(_collateral)).balanceOf(address(this));

        // send collateral to sender
        uint receivedCtokens  = balCtokenAfter - balCtokenBefore;

        require(receivedCtokens > 0, "no collateral");
        SafeERC20.safeTransfer(IERC20(address(_collateral)), msg.sender, receivedCtokens);
       

       // borrow
       uint borrowAmount = vault.getAmountIn(_borrowAmount);
       // add 1 wei because of potential rounding down
       borrowAmount += 1;


       borrowInternalNoTransfer(borrowAmount,msg.sender);

       EIP20Interface(underlying).approve(address(vault),borrowAmount);
       uint buyAmount = vault.buyFromCToken(borrowAmount,_borrowAmount,address(this));
   
       // repay 
       EIP20Interface(underlyingCollateral).approve(address(vault),_borrowAmount);
       vault.repayLeverage();
       
    }


  
}
