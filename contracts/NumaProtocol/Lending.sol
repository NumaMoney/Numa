// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.20;


// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import "@openzeppelin/contracts/access/Ownable2Step.sol";

// import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


// import "../interfaces/INumaVault.sol";

// // NEW PLAN
// // - supply/borrow numa, rEth compound fork
// // - gestion prices/oracles
// // - supply from vault
// // - limit rEth borrow from CF
// // - liquidations
// // - LST
// // - modifs vault using reth debt


// // NOTES:
// // - 2 approches possibles: write custom contract inspired by compound VS fork compound and modify
// //   2nd approach might be safer

// // - fork: remove rewards, remove governance
// // -  changing params by redeployment? --> just remove immutable and add set

// // - I think I will change structure because it's very complex use of factory, proxies, etc...and looks complex to deploy too


// // QUESTIONS:

// // - what happens if all numa are lend and someone wants to withdraw his deposits?
// // - how changing params work, what is redeployed, should we do the same 
// // - 2 instances???
// // - do we emit a cToken?

// // ROADMAP
// // - fork, compile, check code, check deployment, test deployment
// //           ** comment deployer tout le protocole
// //           ** comment deployer un comet (un marché)
// //           ** comment upgrader un comet (parameter change)
// //           ** comment un marché (comet) connait il tous les marchés (pour accéder aux deposits)
// //       ** deploy numa market, rEth market 
// //       ** test supply and borrow
// // - list modifs todo + code to be removed + files to be removed

// // - ESTIMATE
// // - start implem


// // ESTIMATE

// *********************************************************************************************************






// // 1. borrow rEth from Numa deposit

// // Q: could we have interest (doing as so for now)

// // 2. liquidations

// // 3. gestion rewards cf discussion

// // 4. gestion limitations en volume
// // + note perso, il faut assez d'rEth dans le vault pour payer les liquidations


// // CLEAN/REFACTO CODE - reflechir a comment gerer si:
// // - pas d'interest rate
// // - numa borrow possible


// // 5. numa borrow ? 
// // --> deposit LST 
// // --> + interest rate? --> pour numa et pour LST on a supplyInterestRate et borrowInterestRate

  
// // 6. clean and finalize code voir contrat de lending simple github pour m'inspirer, ou compound
// //https://github.com/BenSparksCode/simple-lending-protocol/tree/main/contracts

// // simplifier ou pas le code compound
// // si on peut deposit du reTH --> alors borrow peut devenir withdraw, et repay peut devenir deposit (+ gérer supply/borrow)

// // 7. events errors


// // Q/Notes:

// // - can we have interest on rEth, of never (if so I can remove all principal code!!!)
// // - borrow numa? if so
// //      - deposit rETh --> interest?
// //      - deposit Numa --> interest?
// // --> can you confirm borrow numa YES/NO
// // --> can you confirm interest rate 0 ALWAYS (even if borrow numa)


// // ****************************** 
// // NOTES
//     // TODO: interest rate, and how to handle if multiple borrows

//     // TODO: transfer token to/from the vault

//     // TODO: how to handle a vault replacement

//     // TODO: repay and withdraw in 1 tx


//     // TODO: liquidations mgt + make a bot for fun

//     // Q: liquidate --> get all collateral or a %? (cf compound 10%?) si liquidation penalty it has to be < calateral factor (ie si 110% liquidation price --> 10 % max)


//     // TODO: minimum borrow
//     //If the amount of collateral deposited is too low, then the liquidation penalty that goes to the liquidator might not pay for the gas of the transaction to liquidate the borrower

//     // TODO: large loans issue:
//     // Liquidating a large amount of collateral can lead to price impacts where the recovered amount is less than the borrowed amount.

//     // supply cap on collateral? or unneeded as selling numa should increase vault's price

//     // TODO make an arb bot for numa to see how it works and make some money


// // DEV NOTES

// // voir les uint chelou 104 etc, notamment dans les structs -6> c'est de loptim mais bon


// contract NumaLendingProtocol is Ownable2Step{


//     struct UserBasic {
//         int104 principal;// rEth borrow
//         uint256 numaBalance;
       
       
//     }


//     // The ratio of collateral tokens required per lending token borrowed
//     uint256 public collateralRatio = 8695;


//     IERC20 public immutable numa;
//     IERC20 public immutable lstToken;

//     INumaVault vault;



//     // BORROW LSTTOKEN WITH NUMA COLLATERAL
//     uint64 tokenBorrowPerSecondInterestRateBase = 317097919;// 1% APY
//     uint64 tokenBaseBorrowIndex;
//     uint40 tokenLastAccrualTime;
//     uint104 tokenTotalBorrowBase;

//     /// @notice The minimum base amount required to initiate a borrow
//     uint public immutable tokenBaseBorrowMin;
 

//     // userinfo: TODO put all of them in a struct
//     mapping (address => UserBasic) userBasic;
//     uint256 numaLiquidity;

//     /// @dev The scale for factors
//     uint64 internal constant FACTOR_SCALE = 1e18;
//     uint64 internal constant BASE_INDEX_SCALE = 1e15;
//     uint64 internal constant COLLATERAL_SCALE = 10000;


//     /// @dev 365 days * 24 hours * 60 minutes * 60 seconds
//     uint64 internal constant SECONDS_PER_YEAR = 31_536_000;



//     error BorrowTooSmall();
//     error NotCollateralized();
//     error TimestampTooLarge();

//     error InvalidUInt64();
//     error InvalidUInt104();
//     error InvalidUInt128();
//     error InvalidInt104();
//     error InvalidInt256();
//     error NegativeNumber();

//     constructor(address _numa,address _lstToken,address _vaultAdress) Ownable(msg.sender)
//     {
         
//         numa = IERC20(_numa);
//         lstToken = IERC20(_lstToken);
//         vault = INumaVault(_vaultAdress);
//     }


//     function getTokenBorrowRate()public view returns (uint64) 
//     {
//         // not using utilization & kink
//         // interestRateBase + interestRateSlopeLow * kink + interestRateSlopeHigh * (utilization - kink)
//         return (tokenBorrowPerSecondInterestRateBase);
//     }
    


//     function getTokenRates() external returns (uint64) 
//     {
// 		// these are 18 decimal fixed point numbers
// 		// measuring interest per second	
// 		uint64 borrowRate = getTokenBorrowRate();
// 		// return them as APR
// 		return (borrowRate * SECONDS_PER_YEAR);
// 	}

//     // Function to deposit numa tokens into the contract
//     function depositNuma(uint256 _amount) external 
//     {
//         require(_amount > 0, "must be greater then zero");

//         // Transfer the collateral tokens from the user to the contract
//         SafeERC20.safeTransferFrom(numa,  msg.sender, address(this), _amount);

//         // Add the collateral tokens to the contract's liquidity
//         numaLiquidity += _amount;
//         userBasic[msg.sender].numaBalance += _amount;
       
//     }


//    /**
//      * @dev The positive principal if positive or the negative principal if negative
//      */
//     function principalValue(int256 presentValue_) internal view returns (int104) 
//     {
//         return -signed104(principalValueBorrow(tokenBaseBorrowIndex,uint256(-presentValue_)));
//     }

//       /**
//      * @dev The present value projected backward by the borrow index (rounded up)
//      *  Note: This will overflow (revert) at 2^104/1e18=~20 trillion principal for assets with 18 decimals.
//      */
//     function principalValueBorrow(uint64 baseBorrowIndex_, uint256 presentValue_) internal pure returns (uint104) 
//     {
//         return safe104((presentValue_ * BASE_INDEX_SCALE + baseBorrowIndex_ - 1) / baseBorrowIndex_);
//     }
    



//     /**
//      * @dev Withdraw an amount of base asset from src to `to`, borrowing if possible/necessary
//      */
//     function borrowLst(uint256 _amount) external 
//     {
//         // accrue interests
//         accrueInternal();

//         UserBasic memory srcUser = userBasic[msg.sender];
//         int104 srcPrincipal = srcUser.principal;
//         require(srcPrincipal <= 0,"only borrow allowed");

//         // real balance after borrow
//         int256 srcBalance = presentValue(srcPrincipal) - signed256(_amount);

//         // new principal using current interest rate
//         int104 srcPrincipalNew = principalValue(srcBalance);
        
//         uint104 borrowAmount = uint104(srcPrincipal - srcPrincipalNew);

//         tokenTotalBorrowBase += borrowAmount;

//         updateBasePrincipal(msg.sender, srcUser, srcPrincipalNew);

//         if (srcBalance < 0) {
//             if (uint256(-srcBalance) < tokenBaseBorrowMin) revert BorrowTooSmall();
//             if (!isBorrowCollateralized(msg.sender)) revert NotCollateralized();
//         }

//         SafeERC20.safeTransferFrom(lstToken,  address(vault), msg.sender, _amount);
   
//     }




//     /**
//      * @return The current timestamp
//      **/
//     function getNowInternal() virtual internal view returns (uint40) {
//         if (block.timestamp >= 2**40) revert TimestampTooLarge();
//         return uint40(block.timestamp);
//     }

//     /**
//      * @dev Calculate accrued interest indices for base token supply and borrows
//      **/
//     function accruedInterestIndices(uint timeElapsed) internal view returns (uint64) {
   
//         uint64 baseBorrowIndex_ = tokenBaseBorrowIndex;
//         if (timeElapsed > 0) 
//         {
//             uint borrowRate = getTokenBorrowRate();
//             baseBorrowIndex_ += safe64(mulFactor(baseBorrowIndex_, borrowRate * timeElapsed));
//         }
//         return (baseBorrowIndex_);
//     }

    
//     /**
//      * @dev Accrue interest (and rewards) in base token supply and borrows
//      **/
//     function accrueInternal() internal {
//         uint40 now_ = getNowInternal();
//         uint timeElapsed = uint256(now_ - tokenLastAccrualTime);

//         if (timeElapsed > 0) 
//         {
//             tokenBaseBorrowIndex = accruedInterestIndices(timeElapsed);
//             tokenLastAccrualTime = now_;
//         }
//     }


//     /**
//      * @dev The principal amount projected forward by the borrow index
//      */
//     function presentValueBorrow(uint64 baseBorrowIndex_, uint104 principalValue_) internal pure returns (uint256) {
//         return uint256(principalValue_) * baseBorrowIndex_ / BASE_INDEX_SCALE;
//     }


//     /**
//      * @dev The positive present supply balance if positive or the negative borrow balance if negative
//      */
//     function presentValue(int104 principalValue_) internal view returns (int256) 
//     {
//         return -signed256(presentValueBorrow(tokenBaseBorrowIndex, uint104(-principalValue_)));
//     }




//      /**
//      * @dev Write updated principal to store and tracking participation
//      */
//     function updateBasePrincipal(address account, UserBasic memory basic, int104 principalNew) internal
//     {       
//         basic.principal = principalNew;
//         userBasic[account] = basic;
//     }



//     /**
//      * @notice Check whether an account has enough collateral to borrow
//      * @param account The address to check
//      * @return Whether the account is minimally collateralized enough to borrow
//      */
//     function isBorrowCollateralized(address account) public view returns (bool) 
//     {

//         int104 principal = userBasic[account].principal;

//         // no debt
//         if (principal >= 0) {
//             return true;
//         }
        
        
//         uint nbtokensAllowedToBorrow = vault.getSellNumaSimulateExtract(userBasic[msg.sender].numaBalance);
//         nbtokensAllowedToBorrow = (nbtokensAllowedToBorrow*collateralRatio) / COLLATERAL_SCALE;

//        return (-presentValue(principal) <= nbtokensAllowedToBorrow);


//     }


//     function liquidate(address account) external 
//     {
//           // accrue interests
//         accrueInternal();

//         require(!isBorrowCollateralized(account));

//         // how much is due
//         UserBasic memory srcUser = userBasic[msg.sender];
//         int104 srcPrincipal = srcUser.principal;

//         require(srcPrincipal <= 0,"only borrow allowed");

//         // real balance after borrow
//         int256 realBorrow = -presentValue(srcPrincipal);
//         tokenTotalBorrowBase -= realBorrow;

//         updateBasePrincipal(msg.sender, account, 0);


//         SafeERC20.safeTransferFrom(lstToken,  msg.sender,address(vault), realBorrow);
     
//         // When collateral is lower than the max collateral factor, anyone can call public liquidation
//         //  function which will flashloan rETH, 

//         // sell numa to vault
//         uint numaBalance = userBasic[account].numaBalance;
//         userBasic[account].numaBalance = 0;
//         // for now slippage equals minimum value to repay liquidator but should be more (or liquidator will never liquidate)
       
//         uint minAmount = (realBorrow*COLLATERAL_SCALE)/collateralRatio;


//         vault.sell(numaBalance,minAmount,address(this));

//         // TODO: I should have the value from return of sell 
//         uint receivedrEth = lstToken.balanceOf(address(this));
    
//         uint profit = receivedrEth - realBorrow;
//         uint liquidatorProfit = (profit * 5) / 100;

//         uint vaultProfit = profit - liquidatorProfit;

//         SafeERC20.safeTransfer(lstToken,address(vault), vaultProfit);
//         SafeERC20.safeTransfer(lstToken,msg.sender, liquidatorProfit+realBorrow);

//         // unlock the Numa, sell the Numa to vault (why its always priced at sell price), then use proceeds to repay Flashloan. 

//         //  The user that called the function keeps 5% of the remaining rETH, with the rest of the proceeds (95%) going back into vault.
//         //  Any interest goes back into vault too.





//     }



//     // Function to repay borrowed lending tokens and retrieve collateral tokens
//     function repayLst(uint256 _amount) external
//     {
//         require(_amount > 0, "must be greater then zero");

//          // accrue interests
//         accrueInternal();

//         UserBasic memory srcUser = userBasic[msg.sender];
//         int104 srcPrincipal = srcUser.principal;

//         require(srcPrincipal <= 0,"only borrow allowed");

//         // real balance after borrow
//         int256 realBorrow = presentValue(srcPrincipal);
//         // can not repay more than what's borrowed 
//         require((-realBorrow) >= _amount, "repaying too much");



//         int256 srcBalance = realBorrow + signed256(_amount);
  
//         // new principal using current interest rate
//         int104 srcPrincipalNew = principalValue(srcBalance);
        
//         uint104 repaidAmount = uint104(srcPrincipalNew - srcPrincipal);

//         tokenTotalBorrowBase -= repaidAmount;

//         updateBasePrincipal(msg.sender, srcUser, srcPrincipalNew);

//         SafeERC20.safeTransferFrom(lstToken,  msg.sender,address(vault), _amount);

//     }

//     // Function to withdraw collateral tokens from the contract
//     function withdrawNuma(uint256 _amount) public 
//     {


//         require(_amount > 0, "must be greater then zero");
//         require(userBasic[msg.sender].numaBalance >= _amount, "not enough balance");

        
//         // accrue interests
//         accrueInternal();
        
     
//         // TODO replace by isborrowcollateralized
//         // only allow withdraw if no risk of liquidation
//         userBasic[msg.sender].numaBalance -= _amount;
//         require(isBorrowCollateralized(msg.sender));
//         SafeERC20.safeTransfer(numa, msg.sender, _amount);
//     }





//     // Maths and helpers

//     function signed256(uint256 n) internal pure returns (int256) {
//         if (n > uint256(type(int256).max)) revert InvalidInt256();
//         return int256(n);
//     }

//     function safe104(uint n) internal pure returns (uint104) {
//         if (n > type(uint104).max) revert InvalidUInt104();
//         return uint104(n);
//     }

//     function signed104(uint104 n) internal pure returns (int104) {
//         if (n > uint104(type(int104).max)) revert InvalidInt104();
//         return int104(n);
//     }
//     function safe64(uint n) internal pure returns (uint64) {
//         if (n > type(uint64).max) revert InvalidUInt64();
//         return uint64(n);
//     }

//     function mulFactor(uint256 n, uint256 factor) internal pure returns (uint256) {
//         return n * factor / FACTOR_SCALE;
//     }

// }