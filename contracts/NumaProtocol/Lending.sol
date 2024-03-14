// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Import the ERC20 interface from OpenZeppelin contracts to interact with the collateral token
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LendingProtocol {

    // The ratio of collateral tokens required per lending token borrowed
    uint256 public collateralRatio;



    // The address of the owner of the contract
    address public owner;// TODO: onlyOwner

    IERC20 collateralToken;
    IERC20 token; 

    /// @dev 365 days * 24 hours * 60 minutes * 60 seconds
    uint64 internal constant SECONDS_PER_YEAR = 31_536_000;
    uint256 borrowPerSecondInterestRateBase = 317097919;// 1% APY

     /// @dev The scale for factors
    uint64 internal constant FACTOR_SCALE = 1e18;

    mapping(address => uint256) borrow_amount;
    mapping(address => uint256) balance;


    INumaVault vault;

    event LiquidityAdded(address indexed depositor, uint256 amount);
    event Borrow(address indexed borrower, uint256 amount);
    event Repay(address indexed borrower, uint256 amount);
    event Withdrawal(address indexed owner, uint256 amount);

    // Constructor function, sets the collateral ratio and collateral token address
    constructor(uint256 _collateralRatio, address _collateralToken,address _token,address _vaultAdress) {
        collateralRatio = _collateralRatio;
        
        owner = msg.sender;
        collateralToken = IERC20(_collateralToken);
        token = IERC20(_token);
        vault = INumaVault(_vaultAdress);
    }


    function getBorrowRate()public view returns (uint64) {
            // not using utilization & kink
            // interestRateBase + interestRateSlopeLow * kink + interestRateSlopeHigh * (utilization - kink)
            return (borrowPerSecondInterestRateBase);
        }
    }


    function getRates()
		external
		returns (uint64) 
        {

		
		// these are 18 decimal fixed point numbers
		// measuring interest per second
	
		uint64 borrowRate = getBorrowRate();

		// return them as APR
		return (borrowRate * SECONDS_PER_YEAR);
	}

    // Function to deposit collateral tokens into the contract
    function addLiquidity(uint256 _amount) public {
        require(_amount > 0, "must be greater then zero");

        // Transfer the collateral tokens from the user to the contract

        collateralToken.transferFrom(msg.sender, address(this), _amount);

        // Add the collateral tokens to the contract's liquidity
        liquidity += _amount;
        balance[msg.sender] += _amount;
        emit LiquidityAdded(msg.sender, _amount);
    }

    // TODO: interest rate, and how to handle if multiple borrows

    // TODO: transfer token to/from the vault

    // TODO: how to handle a vault replacement

    // TODO: repay and withdraw in 1 tx


    // TODO: liquidations mgt


    function withdrawInternal(address operator, address src, address to, address asset, uint amount) internal {
        // TODO
        // if (isWithdrawPaused()) revert Paused();
        // if (!hasPermission(src, operator)) revert Unauthorized();

// TODO
        // if (asset == baseToken) {
        //     if (amount == type(uint256).max) {
        //         amount = balanceOf(src);
        //     }
            return withdrawBase(src, to, amount);

            // TODO
        // } else {
        //     return withdrawCollateral(src, to, asset, safe128(amount));
        // }
    }




    // TODO: 
    // - accrue
    // - borrow
    // - multi borrow
    // - repay
    // - rename functions by "borrow" (cf my function) and simplify

    /**
     * @dev Withdraw an amount of base asset from src to `to`, borrowing if possible/necessary
     */
    function withdrawBase(address src, address to, uint256 amount) internal {
        accrueInternal();

        // UserBasic memory srcUser = userBasic[src];
        // int104 srcPrincipal = srcUser.principal;
        // int256 srcBalance = presentValue(srcPrincipal) - signed256(amount);
        // int104 srcPrincipalNew = principalValue(srcBalance);

        // (uint104 withdrawAmount, uint104 borrowAmount) = withdrawAndBorrowAmount(srcPrincipal, srcPrincipalNew);

        // totalSupplyBase -= withdrawAmount;
        // totalBorrowBase += borrowAmount;

        // updateBasePrincipal(src, srcUser, srcPrincipalNew);

        // if (srcBalance < 0) {
        //     if (uint256(-srcBalance) < baseBorrowMin) revert BorrowTooSmall();
        //     if (!isBorrowCollateralized(src)) revert NotCollateralized();
        // }

        // doTransferOut(baseToken, to, amount);

        // emit Withdraw(src, to, amount);

        // if (withdrawAmount > 0) {
        //     emit Transfer(src, address(0), presentValueSupply(baseSupplyIndex, withdrawAmount));
        // }
    }


    // // Function to borrow lending tokens, using collateral tokens as collateral
    // function borrow(uint256 _amount) public payable {
    //     require(_amount > 0, "must be greater then zero");

    //     // Calculate the required collateral amount based on the collateral ratio and lending token amount
    //     // how many rEth can we borrow with our collateral
    //     uint nbtokensAllowedToBorrow = vault.getSellNumaSimulateExtract(balance[msg.sender]);

    //     nbtokensAllowedToBorrow = (nbtokensAllowedToBorrow*collateralRatio) / 10000;//115% --> collateralRatio = 8695

    //     // do we have enough collateral to borrow
    //     require((borrow_amount[msg.sender] + _amount) <= nbtokensAllowedToBorrow, "collateral amount is lower");

    //     // Transfer the lending tokens to the user
    //     // TODO: transfer from vault
    //     token.transfer(msg.sender, _amount);
      
    //     borrow_amount[msg.sender] += _amount;
    //     emit Borrow(msg.sender, _amount);
    // }

    // Function to repay borrowed lending tokens and retrieve collateral tokens
    function repay(uint256 _amount) public {
        require(_amount > 0, "must be greater then zero");
        require(borrow_amount[msg.sender] >= _amount, "not enough balance");
        // Transfer the lending tokens from the user to the contract
        token.transferFrom(msg.sender, address(this), _amount);
        borrow_amount[msg.sender] -= _amount;
        emit Repay(msg.sender, _amount);
    }

    // Function to withdraw collateral tokens from the contract
    function withdraw(uint256 _amount) public {
        require(_amount > 0, "must be greater then zero");
        require(balance[msg.sender] >= _amount, "not enough balance");
        
        balance[msg.sender] -= _amount;


        // only allow withdraw if no risk of liquidation
        uint nbtokensAllowedToBorrow = vault.getSellNumaSimulateExtract(balance[msg.sender]);

        nbtokensAllowedToBorrow = (nbtokensAllowedToBorrow*collateralRatio) / 10000;//115% --> collateralRatio = 8695

        // do we have enough collateral to borrow

        require((borrow_amount[msg.sender]) <= nbtokensAllowedToBorrow, "collateral amount is lower");

       


        // Transfer the collateral tokens from the contract to the owner
        collateralToken.transfer(msg.sender, _amount);


        emit Withdrawal(msg.sender, _amount);
    }


    // Function to get the contract's collateral ratio
    function getCollateralRatio() public view returns (uint256) {
        return collateralRatio;
    }

    // Function to get the contract's collateral token
    function getCollateralToken() public view returns (address) {
        return collateralToken;
    }

    // Function to get the contract's owner
    function getOwner() public view returns (address) {
        return owner;
    }

    //funcation to borrow amount of user
    function getBorrowAmount(address _user) public view returns (uint256) {
        return borrow_amount[_user];
    }

    //funcation to get balance of liquidity provider
    function getBalance(address _user) public view returns (uint256) {
        return balance[_user];
    }
}