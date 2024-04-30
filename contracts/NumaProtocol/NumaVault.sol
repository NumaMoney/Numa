//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "../Numa.sol";
import "../interfaces/IVaultOracleSingle.sol";
import "../interfaces/INuAssetManager.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/INumaVault.sol";
import "../interfaces/IRewardFeeReceiver.sol";
import "./NumaMinter.sol";
import "../lending/CNumaToken.sol";

/// @title Numa vault to mint/burn Numa to lst token
contract NumaVault is Ownable2Step, ReentrancyGuard, Pausable, INumaVault {
    using EnumerableSet for EnumerableSet.AddressSet;

    // address that receives fees
    address payable private fee_address;
    // address that receives REWARDS (extracted from lst token rebase)
    address payable private rwd_address;

    bool private isFeeReceiver;
    bool private isRwdReceiver;

    // sell fee
    uint16 public sell_fee = 950; // 5%
    // buy fee
    uint16 public buy_fee = 950; // 5%
    // fee that is sent to fee_address
    uint16 public fees = 10; //1%



    uint16 public max_percent = 100; //10%

    // threshold for reward extraction
    uint public rwd_threshold = 0;

    //
    NUMA public immutable numa;
    NumaMinter public immutable minterContract;
    IERC20 public immutable lstToken;
    IVaultOracleSingle public oracle;
    //INuAssetManager public nuAssetManager;
    IVaultManager public vaultManager;

    // reward extraction variables
    uint256 public last_extracttimestamp;
    uint256 public last_lsttokenvalueWei;

    // constants
    // minimum input amount for buy/sell
    uint256 public constant MIN = 1000;
    uint16 public constant BASE_1000 = 1000;

    // decimals of lst token
    uint256 immutable decimals;

    bool isWithdrawRevoked = false;

    // lending parameters
    uint public maxBorrow;
    uint public maxCF = 2000;// 200%
    uint debt;
    uint public rewardsFromDebt;
    uint maxLstProfitForLiquidations;
   
   
    bool isLiquidityLocked;
    uint lstLockedBalance;

    CNumaToken cLstToken;
    CNumaToken cNuma;
    uint leverageDebt;


    // Events
    event SetOracle(address oracle);
    event SetVaultManager(address vaultManager);
    event Buy(uint256 received, uint256 sent, address receiver);
    event Sell(uint256 sent, uint256 received, address receiver);
    event Fee(uint256 fee, address feeReceiver);
    event SellFeeUpdated(uint16 sellFee);
    event BuyFeeUpdated(uint16 buyFee);
    event FeeUpdated(uint16 Fee);
    event MaxPercentUpdated(uint16 NewValue);
    event ThresholdUpdated(uint256 newThreshold);
    event FeeAddressUpdated(address feeAddress);
    event RwdAddressUpdated(address rwdAddress);
    event AddedToRemovedSupply(address _address);
    event RemovedFromRemoveSupply(address _address);
    event RewardsExtracted(uint _rwd, uint _currentvalueWei);
    event RewardsDebtExtracted(uint _rwd);
    event SetCTokens(address cNuma,address crEth);
    event SetMaxBorrow(uint _maxBorrow);
    event BorrowedVault(uint _amount);
    event RepaidVault(uint _amount);
    event SetMaxProfit(uint _maxProfit);
    event SetMaxCF(uint _maxCF);

    constructor(
        address _numaAddress,
        address _tokenAddress,
        uint256 _decimals,
        address _oracleAddress,
        address _minterAddress)
        Ownable(msg.sender) {
        minterContract = NumaMinter(_minterAddress);
        numa = NUMA(_numaAddress);
        oracle = IVaultOracleSingle(_oracleAddress);
        lstToken = IERC20(_tokenAddress);
        decimals = _decimals;

        // lst rewards
        last_extracttimestamp = block.timestamp;
        //last_lsttokenvalueWei = oracle.getTokenPrice(address(lstToken),decimals);
        last_lsttokenvalueWei = oracle.getTokenPrice(decimals);

        // paused by default because might be empty
        _pause();
    }

    /**
     * @dev pause buying and selling from vault
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev unpause buying and selling from vault
     */
    function unpause() external onlyOwner {
        _unpause();
    }


    /**
     * @dev set the IVaultOracle address (used to compute token price in Eth)
     */
    function setCTokens(address _cNuma, address _clstToken) external onlyOwner {

        cNuma = CNumaToken(_cNuma);
        cLstToken = CNumaToken(_clstToken);
        emit SetCTokens(_cNuma,_clstToken);
        
    }


    function setMaxCF(uint _maxCF) external onlyOwner 
    {
        // CF will change so we need to update interest rates
        accrueInterestLending();

        maxCF = _maxCF;
        emit SetMaxCF(_maxCF);   
    }

    function setMaxBorrow(uint _maxBorrow) external onlyOwner {
        maxBorrow = _maxBorrow;
        emit SetMaxBorrow(_maxBorrow);   
    }

    function setMaxLiquidationsProfit(uint _maxProfit) external onlyOwner {
        maxLstProfitForLiquidations = _maxProfit;
        emit SetMaxProfit(_maxProfit);   
    }

    /**
     * @dev set the IVaultOracle address (used to compute token price in Eth)
     */
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0x0), "zero address");
        oracle = IVaultOracleSingle(_oracle);
        emit SetOracle(address(_oracle));
    }

    /**
     * @dev set the IVaultManager address (used to total Eth balance of all vaults)
     */
    function setVaultManager(address _vaultManager) external onlyOwner {
        require(_vaultManager != address(0x0), "zero address");
        vaultManager = IVaultManager(_vaultManager);
        // vault have to be registered before
        require(vaultManager.isVault(address(this)), "not a registered vault");
        emit SetVaultManager(_vaultManager);
    }

    /**
     * @dev Set Rwd address
     */
    function setRwdAddress(address _address,bool _isRwdReceiver) external onlyOwner 
    {        
        rwd_address = payable(_address);
        isRwdReceiver = _isRwdReceiver;
        emit RwdAddressUpdated(_address);
    }

    /**
     * @dev Set Fee address
     */
    function setFeeAddress(address _address,bool _isFeeReceiver) external onlyOwner 
    {        
        fee_address = payable(_address);
        isFeeReceiver = _isFeeReceiver;
        emit FeeAddressUpdated(_address);
    }

    /**
     * @dev Set Sell fee percentage (exemple: 5% fee --> fee = 950)
     */
    function setSellFee(uint16 _fee) external onlyOwner {
        require(_fee <= BASE_1000, "fee above 1000");
        sell_fee = _fee;
        emit SellFeeUpdated(_fee);
    }

    /**
     * @dev Set Buy fee percentage (exemple: 5% fee --> fee = 950)
     */
    function setBuyFee(uint16 _fee) external onlyOwner {
        require(_fee <= BASE_1000, "fee above 1000");
        buy_fee = _fee;
        emit BuyFeeUpdated(_fee);
    }

    /**
     * @dev Set Fee percentage (exemple: 1% fee --> fee = 10)
     */
    function setFee(uint16 _fees) external onlyOwner {
        // fees have to be  <= buy/sell fee
        require(
            ((_fees <= (BASE_1000 - buy_fee)) &&
                (_fees <= (BASE_1000 - sell_fee))),
            "fees above buy/sell fee"
        );
        fees = _fees;
        emit FeeUpdated(_fees);
    }

    function setMaxPercent(uint16 _maxPercent) external onlyOwner {
        require(max_percent <= BASE_1000, "Percent above 100");
        max_percent = _maxPercent;
        emit MaxPercentUpdated(_maxPercent);
    }

    /**
     * @dev Set rewards threshold
     */
    function setRewardsThreshold(uint256 _threshold) external onlyOwner {
        rwd_threshold = _threshold;
        emit ThresholdUpdated(_threshold);
    }

 

    function getVaultBalance() internal view returns (uint)
    {
        if (isLiquidityLocked)
        {
            return lstLockedBalance;
        }
        else
        {
            uint balance = lstToken.balanceOf(address(this));
            balance += (debt - rewardsFromDebt);// debt is owned by us but rewards will be sent
            return balance;
        }
    }
    function getVaultBalanceNoDebt() internal view returns (uint)
    {
        if (isLiquidityLocked)
        {
            return lstLockedBalance;
        }
        else
        {
            return lstToken.balanceOf(address(this));
        }
    }


    /**
     * @dev returns the estimated rewards value of lst token
     */
    function rewardsValue() public view returns (uint256, uint256,uint256) {
        require(address(oracle) != address(0), "oracle not set");
        //uint currentvalueWei = oracle.getTokenPrice(address(lstToken),decimals);
        uint currentvalueWei = oracle.getTokenPrice(decimals);
        if (currentvalueWei <= last_lsttokenvalueWei) {
            return (0, currentvalueWei,0);
        }
        uint diff = (currentvalueWei - last_lsttokenvalueWei);
        uint balance = getVaultBalanceNoDebt();
        uint rwd = FullMath.mulDiv(balance, diff, currentvalueWei);
        // extract from debt. Substract rewardsFromDebt as it's not supposed to be in the vault anymore
        uint debtRwd = FullMath.mulDiv((debt - rewardsFromDebt), diff, currentvalueWei);
        return (rwd, currentvalueWei,debtRwd);
    }

    function extractInternal(uint rwd, uint currentvalueWei,uint rwdDebt) internal {
        last_extracttimestamp = block.timestamp;
        last_lsttokenvalueWei = currentvalueWei;

        rewardsFromDebt += rwdDebt;
        if (rwd_address != address(0))
        {
            SafeERC20.safeTransfer(IERC20(lstToken), rwd_address, rwd);
            if (isContract(rwd_address) && isRwdReceiver) 
            {
                // we don't check result as contract might not implement the deposit function (if multi sig for example)
                rwd_address.call(
                    abi.encodeWithSignature("DepositFromVault(uint256)", rwd)
                    );
            }
        }
        emit RewardsExtracted(rwd, currentvalueWei);
    }

    /**
     * @dev transfers rewards to rwd_address and updates reference price
     */
    function extractRewards() virtual external 
    {    
        require(
            block.timestamp >= (last_extracttimestamp + 24 hours),
            "reward already extracted"
        );

        (uint256 rwd, uint256 currentvalueWei,uint256 rwdDebt) = rewardsValue();
        require(rwd > rwd_threshold, "not enough rewards to collect");
        extractInternal(rwd, currentvalueWei,rwdDebt);
    }

    /**
     * @dev transfers rewards to rwd_address and updates reference price
     * @notice no require as it will be called from buy/sell function and we only want to skip this step if
     * conditions are not filled
     */
    function extractRewardsNoRequire() internal {
        if (block.timestamp >= (last_extracttimestamp + 24 hours)) 
        {
            (uint256 rwd, uint256 currentvalueWei,uint256 rwdDebt) = rewardsValue();
            if (rwd > rwd_threshold) 
            {
                extractInternal(rwd, currentvalueWei,rwdDebt);
            }
            
        }
    }

    /**
     * @dev vaults' balance in Eth
     */
    function getEthBalance() external view returns (uint256) {
        require(address(oracle) != address(0), "oracle not set");
        uint balance = getVaultBalance();
        
        //balance += (debt - rewardsFromDebt);// debt is owned by us but rewards will be sent
        // we use last reference value for balance computation
        uint result = FullMath.mulDiv(last_lsttokenvalueWei, balance, decimals);
        return result;
    }

    /**
     * @dev vaults' balance in Eth
     */
    function getEthBalanceNoDebt() public view returns (uint256) {
        require(address(oracle) != address(0), "oracle not set");
        uint balance = getVaultBalanceNoDebt();
        
        // we use last reference value for balance computation
        uint result = FullMath.mulDiv(last_lsttokenvalueWei, balance, decimals);
        return result;
    }

    /**
     * @dev Buy numa from token (token approval needed)
     */
    function buy(
        uint _inputAmount,uint _minNumaAmount,
        address _receiver
    ) public nonReentrant whenNotPaused returns (uint _numaOut)
    {
        require(_inputAmount > MIN, "must trade over min");
    
        // CF will change so we need to update interest rates
        accrueInterestLending();


        // extract rewards if any
        extractRewardsNoRequire();

        uint256 vaultsBalance = getVaultBalance();
        uint256 MAX = (max_percent * vaultsBalance) / BASE_1000;
        require(_inputAmount <= MAX, "must trade under max");

      
        // execute buy
        uint256 numaAmount = vaultManager.tokenToNuma(
            _inputAmount,
            last_lsttokenvalueWei,
            decimals
        );
        
        require(numaAmount > 0, "amount of numa is <= 0");

        // don't transfer to ourselves
        if (msg.sender != address(this))
        {
            SafeERC20.safeTransferFrom(
                lstToken,
                msg.sender,
                address(this),
                _inputAmount
            );
        }

        _numaOut =  (numaAmount * buy_fee) / BASE_1000;
        require(_numaOut >= _minNumaAmount, "Min NUMA");

        // mint numa
        minterContract.mint(_receiver, _numaOut);
        //numa.mint(_receiver, _numaOut);
        emit Buy(
            _numaOut,
            _inputAmount,
            _receiver
        );
        // fee
        if (fee_address != address(0x0)) {
            console.log("FEES");
        
            uint256 feeAmount = (fees * _inputAmount) / BASE_1000;
                console.logUint(feeAmount);
            SafeERC20.safeTransfer(lstToken, fee_address, feeAmount);
            
            if (isContract(fee_address) && isFeeReceiver) 
            {
                // we don't check result as contract might not implement the deposit function (if multi sig for example)
                fee_address.call(
                    abi.encodeWithSignature("DepositFromVault(uint256)", feeAmount)
                    );
            }
            emit Fee(feeAmount, fee_address);
        }

    }

    function accrueInterestLending() internal
    {
         // accrue interest
        // if (address(cNuma) != address(0))
        //     cNuma.accrueInterest();
        if (address(cLstToken) != address(0))
            cLstToken.accrueInterest();
    }
    /**
     * @dev Sell numa (burn) to token (numa approval needed)
     */
    function sell(
        uint256 _numaAmount,uint256 _minTokenAmount,
        address _receiver
    ) public nonReentrant whenNotPaused returns (uint _tokenOut)
    {
        require(_numaAmount > MIN, "must trade over min");
        // CF will change so we need to update interest rates
        accrueInterestLending();

        // extract rewards if any
        extractRewardsNoRequire();
        // execute sell
        // Total Eth to be sent
        uint256 tokenAmount = vaultManager.numaToToken(
            _numaAmount,
            last_lsttokenvalueWei,
            decimals
        );
        require(tokenAmount > 0, "amount of token is <=0");
        require(
            lstToken.balanceOf(address(this)) >= tokenAmount,
            "not enough liquidity in vault"
        );

        _tokenOut = (tokenAmount * sell_fee) / BASE_1000;
        require(_tokenOut >= _minTokenAmount, "Min Token");

        // burning numa tokens


        if (msg.sender != address(this))
        {
            numa.burnFrom(msg.sender, _numaAmount);
        }
        else
        {
            numa.burn(_numaAmount);
        }
        // don't transfer to ourselves
        if (msg.sender != address(this))
        {
            // transfer lst tokens to receiver
            SafeERC20.safeTransfer(
                lstToken,
                _receiver,
                _tokenOut
            );
        }
        emit Sell(
            _numaAmount,
            _tokenOut,
            _receiver
        );
        // fee
        if (fee_address != address(0x0)) {
            uint256 feeAmount = (fees * tokenAmount) / BASE_1000;
            SafeERC20.safeTransfer(IERC20(lstToken), fee_address, feeAmount);

            if (isContract(fee_address) && isFeeReceiver) 
            {
                // we don't check result as contract might not implement the deposit function (if multi sig for example)
                fee_address.call(
                    abi.encodeWithSignature("DepositFromVault(uint256)", feeAmount)
                    );
            }

            emit Fee(feeAmount, fee_address);
        }


    }

    function buyFromCToken( uint _inputAmount,uint _minAmount) external returns (uint256) 
    {
        if (msg.sender == address(cLstToken))
        {
            uint result = buy(_inputAmount,_minAmount,msg.sender);
            return result;
        

        }
        else if (msg.sender == address(cNuma))
        {
            uint result = sell(_inputAmount,_minAmount,msg.sender);
            return result;
        }
        else
        {
            revert("not allowed");
        }
    }



    /**
     * @dev Estimate number of Numas from an amount of token
     */
    function getBuyNuma(uint256 _amount) public view returns (uint256) {
        uint256 numaAmount = vaultManager.tokenToNuma(
            _amount,
            last_lsttokenvalueWei,
            decimals
        );
        return (numaAmount * buy_fee) / BASE_1000;
    }





    /**
     * @dev Estimate number of tokens needed to get an amount of numa
     */
    function getBuyNumaAmountIn(uint256 _amount) public view returns (uint256) 
    {
        // how many numa from 1 lstToken
        uint256 numaAmount = vaultManager.tokenToNuma(
            decimals,
            last_lsttokenvalueWei,
            decimals
        );
        numaAmount = (numaAmount * buy_fee) / BASE_1000;
        uint result = FullMath.mulDiv(_amount, 1 ether, numaAmount);
        return result;
    }


    function getSellNumaAmountIn(uint256 _amount) public view returns (uint256) 
    {
        // how many tokens for 1 numa
        uint256 tokenAmount = vaultManager.numaToToken(
            1 ether,
            last_lsttokenvalueWei,
            decimals
        );
        tokenAmount =  (tokenAmount * sell_fee) / BASE_1000;

        uint result = FullMath.mulDiv(_amount, decimals, tokenAmount);

        return result;
    }

    /**
     * @dev Estimate number of tokens from an amount of numa
     */
    function getSellNuma(uint256 _amount) public view returns (uint256) {
        uint256 tokenAmount = vaultManager.numaToToken(
            _amount,
            last_lsttokenvalueWei,
            decimals
        );
        return (tokenAmount * sell_fee) / BASE_1000;
    }

    function getAmountIn(uint256 _amount) external view returns (uint256) 
    {
         if (msg.sender == address(cLstToken))
        {
            return getBuyNumaAmountIn(_amount);
        }
        else if (msg.sender == address(cNuma))
        {
            return getSellNumaAmountIn(_amount);
        }
        else
        {
            revert("not allowed");
        }
    }


    /**
     * @dev Estimate number of Numas from an amount of token with extraction simulation
     */
    function getBuyNumaSimulateExtract(
        uint256 _amount
    ) external view returns (uint256) {
        uint256 refValue = last_lsttokenvalueWei;
        (uint256 rwd, uint256 currentvalueWei,uint256 rwdDebt) = rewardsValue();
        if (rwd > rwd_threshold) {
            refValue = currentvalueWei;
        }

        uint256 numaAmount = vaultManager.tokenToNuma(
            _amount,
            refValue,
            decimals
        );
        return (numaAmount * buy_fee) / BASE_1000;
    }

    /**
     * @dev Estimate number of tokens from an amount of numa with extraction simulation
     */
    function getSellNumaSimulateExtract(
        uint256 _amount
    ) external view returns (uint256) {
        uint256 refValue = last_lsttokenvalueWei;
        (uint256 rwd, uint256 currentvalueWei,uint256 rwdDebt) = rewardsValue();
        if (rwd > rwd_threshold) {
            refValue = currentvalueWei;
        }

        uint256 tokenAmount = vaultManager.numaToToken(
            _amount,
            refValue,
            decimals
        );
        return (tokenAmount * sell_fee) / BASE_1000;
    }

    
    function GetMaxBorrow() public view returns (uint256)
    { 
        uint synthValueInEth = vaultManager.getTotalSynthValueEth();
        uint EthBalance = getEthBalanceNoDebt();

        require(
            EthBalance > synthValueInEth,
            "vault is empty or synth value is too big"
        );
        uint synthValueWithCF = FullMath.mulDiv(synthValueInEth,maxCF,BASE_1000);
        if (EthBalance < synthValueWithCF)
            return 0;
        else
        {
            uint resultEth = EthBalance - synthValueWithCF;  
            uint resultToken = FullMath.mulDiv(resultEth, decimals, last_lsttokenvalueWei);
            if (resultToken > maxBorrow)
                resultToken = maxBorrow;
            return resultToken;
        }
    }

    function getDebt() external view returns (uint)
    {
        return debt;
    }

    function repay(uint _amount) external 
    {
        require(msg.sender == address(cLstToken));
        // extract rewards if any
        extractRewardsNoRequire();

      
        require(_amount > 0,"can not repay 0");
        require(_amount <= debt,"repay more than debt");
        // repay
        SafeERC20.safeTransferFrom(lstToken,msg.sender, address(this), _amount);
        // extract from repaid debt
        uint extractedRwdFromDebt = FullMath.mulDiv(rewardsFromDebt, _amount, debt);

        if ((extractedRwdFromDebt > 0) && (rwd_address != address(0)))
        {
            rewardsFromDebt -= extractedRwdFromDebt;
            SafeERC20.safeTransfer(IERC20(lstToken), rwd_address, extractedRwdFromDebt);
            if (isContract(rwd_address) && isRwdReceiver) 
            {
                // we don't check result as contract might not implement the deposit function (if multi sig for example)
                rwd_address.call(
                    abi.encodeWithSignature("DepositFromVault(uint256)", extractedRwdFromDebt)
                    );
            }
            emit RewardsDebtExtracted(extractedRwdFromDebt);
        }
      
        debt = debt - _amount;
       
        emit RepaidVault(_amount);

    }

    function borrow(uint _amount) external 
    {
        require(msg.sender == address(cLstToken));

        uint maxAmount = GetMaxBorrow();
        require (_amount <= maxAmount,"max borrow");

        // extract rewards if any
        extractRewardsNoRequire();
 
        debt = debt + _amount;
        SafeERC20.safeTransfer(lstToken,msg.sender,_amount);
        emit BorrowedVault(_amount);
    }


    function lockNumaSupply(bool _lock) internal
    {
        vaultManager.lockSupplyFlashloan(_lock);
    }

    function lockLstBalance(bool _lock) internal
    {
        if (_lock)
        {
            uint bal = getVaultBalance();
            lstLockedBalance = bal;
        }
        isLiquidityLocked = _lock;        
    }


    function liquidateNumaBorrowerFlashloan(address _borrower,uint _numaAmount) external whenNotPaused
    {
        // extract rewards if any
        extractRewardsNoRequire();
           
        
        // lock numa supply
        lockNumaSupply(true);
        
        // lock lst balance for pricing
        lockLstBalance(true);
        // mint 
        minterContract.mint(address(this),_numaAmount);


        // liquidate
        numa.approve(address(cNuma),_numaAmount);
        cNuma.liquidateBorrow(_borrower, _numaAmount,CTokenInterface(address(cLstToken))) ;

        // we should have received crEth with discount
        // redeem rEth
        uint balcToken = IERC20(address(cLstToken)).balanceOf(address(this));

        uint balBefore = IERC20(lstToken).balanceOf(address(this));
        cLstToken.redeem(balcToken); 
        uint balAfter = IERC20(lstToken).balanceOf(address(this));
        uint receivedlst = balAfter - balBefore;

        // sell rEth to numa
        uint numaReceived = NumaVault(address(this)).buy(receivedlst, _numaAmount,address(this));

        uint numaLiquidatorProfit = numaReceived - _numaAmount;

        uint maxNumaProfitForLiquidations = vaultManager.tokenToNuma(maxLstProfitForLiquidations,
            last_lsttokenvalueWei,
            decimals);
        // cap profit
        if (numaLiquidatorProfit > maxNumaProfitForLiquidations)
            numaLiquidatorProfit = maxNumaProfitForLiquidations;



        uint numaBurn = numaReceived - numaLiquidatorProfit;
        SafeERC20.safeTransfer(IERC20(address(numa)), msg.sender, numaLiquidatorProfit);
       
        // burn the rest
        numa.burn(numaBurn);
        // unlock numa supply
        lockNumaSupply(false);        
        // unlock use real balance for price
        lockLstBalance(false);

    }

    function liquidateNumaBorrower(address _borrower,uint _numaAmount) external whenNotPaused
    {
        // extract rewards if any
        extractRewardsNoRequire();

        // lock numa supply
        lockNumaSupply(true);

        // lock lst balance for pricing
        lockLstBalance(true);

        // user supplied funds
        SafeERC20.safeTransferFrom(
            IERC20(address(numa)),
            msg.sender,
            address(this),
            _numaAmount
            ); 

        // liquidate
        numa.approve(address(cNuma),_numaAmount);
        cNuma.liquidateBorrow(_borrower, _numaAmount,CTokenInterface(address(cLstToken))) ;

        // we should have received crEth with discount
        // redeem rEth
        uint balcToken = IERC20(address(cLstToken)).balanceOf(address(this));

        uint balBefore = IERC20(lstToken).balanceOf(address(this));
        cLstToken.redeem(balcToken); 
        uint balAfter = IERC20(lstToken).balanceOf(address(this));
        uint receivedlst = balAfter - balBefore;

        // sell rEth to numa
        uint numaReceived = NumaVault(address(this)).buy(receivedlst, _numaAmount,address(this));
        uint numaLiquidatorProfit = numaReceived - _numaAmount;

        uint maxNumaProfitForLiquidations = vaultManager.tokenToNuma(maxLstProfitForLiquidations,
            last_lsttokenvalueWei,
            decimals);

        if (numaLiquidatorProfit > maxNumaProfitForLiquidations)
            numaLiquidatorProfit = maxNumaProfitForLiquidations;

        uint numaToSend = numaLiquidatorProfit + _numaAmount;
        uint numaToBurn = numaReceived - numaToSend;
        SafeERC20.safeTransfer(IERC20(address(numa)), msg.sender, numaToSend);


        // burn the rest
        numa.burn(numaToBurn);

        // unlock numa supply
        lockNumaSupply(false);

        // unlock use real balance for price
        lockLstBalance(false);

    }

    function liquidateLstBorrowerFlashloan(address _borrower,uint _lstAmount) external whenNotPaused
    {
        // extract rewards if any
        extractRewardsNoRequire();
       
    
        // lock numa supply
        lockNumaSupply(true);
        // lock price from liquidity
        lockLstBalance(true);
        // lstLockedBalance = bal;
        // isLiquidityLocked = true;

        // liquidate
        IERC20(lstToken).approve(address(cLstToken),_lstAmount);
        cLstToken.liquidateBorrow(_borrower, _lstAmount,CTokenInterface(address(cNuma))) ;

        // we should have received crEth with discount
        // redeem rEth
        uint balcToken = IERC20(address(cNuma)).balanceOf(address(this));       
        uint balBefore = numa.balanceOf(address(this));
        cNuma.redeem(balcToken); 
        uint balAfter = numa.balanceOf(address(this));
        uint receivedNuma = balAfter - balBefore;

        // sell numa to lst        
        uint lstReceived = NumaVault(address(this)).sell(receivedNuma, _lstAmount,address(this));
        uint lstLiquidatorProfit = lstReceived - _lstAmount;
       
        if (lstLiquidatorProfit > maxLstProfitForLiquidations)
            lstLiquidatorProfit = maxLstProfitForLiquidations;

        // send profit
        uint lstToSend = lstLiquidatorProfit;
        SafeERC20.safeTransfer(
                IERC20(lstToken),
                msg.sender,
                lstToSend
                
        );
        // keep the rest

        // unlock use real balance for price
        lockLstBalance(false);
        // unlock numa supply
        lockNumaSupply(false);
    }


    function liquidateLstBorrower(address _borrower,uint _lstAmount) external whenNotPaused
    {
        // extract rewards if any
        extractRewardsNoRequire();

        // lock numa supply
        lockNumaSupply(true);

        // lock price from liquidity
       lockLstBalance(true);


        // user supplied funds
         SafeERC20.safeTransferFrom(
                IERC20(address(lstToken)),
                msg.sender,
                address(this),
                _lstAmount
            ); 


        // liquidate
        IERC20(lstToken).approve(address(cLstToken),_lstAmount);
        cLstToken.liquidateBorrow(_borrower, _lstAmount,CTokenInterface(address(cNuma))) ;

        // we should have received crEth with discount
        // redeem rEth
        uint balcToken = IERC20(address(cNuma)).balanceOf(address(this));
        uint balBefore = numa.balanceOf(address(this));
        cNuma.redeem(balcToken); // cereful here our balance or rEth will change --> numa price change
        uint balAfter = numa.balanceOf(address(this));
        uint receivedNuma = balAfter - balBefore;
        // sell numa to lst        
        uint lstReceived = NumaVault(address(this)).sell(receivedNuma, _lstAmount,address(this));


        uint lstLiquidatorProfit = lstReceived - _lstAmount;
       
        // cap profit
        if (lstLiquidatorProfit > maxLstProfitForLiquidations)
            lstLiquidatorProfit = maxLstProfitForLiquidations;

        // send profit + input amount
        uint lstToSend = lstLiquidatorProfit + _lstAmount;
        SafeERC20.safeTransfer(
                IERC20(lstToken),
                msg.sender,
                lstToSend
                
        );
        // and keep the rest
    
        // unlock use real balance for price
        lockLstBalance(false);
        // unlock numa supply
        lockNumaSupply(false);
    }

    function borrowLeverage(uint _amount) external whenNotPaused
    {
        // extract rewards if any
        extractRewardsNoRequire();
        if (msg.sender == address(cLstToken))
        {
            // send numa token   
            lockNumaSupply(true);
            //numa.mint(msg.sender,_amount);
            minterContract.mint(msg.sender,_amount);
            leverageDebt = _amount; 


        }
        else if (msg.sender == address(cNuma))
        {
            // send lst
            lockLstBalance(true);
            SafeERC20.safeTransfer(
                IERC20(lstToken),
                msg.sender,
                _amount
                
            );
            leverageDebt = _amount;

        }
        else
        {
            revert("not allowed");
        }

    }


    function repayLeverage() external whenNotPaused
    {
        if (msg.sender == address(cLstToken))
        {
            // we borrowed numa
            // SafeERC20.safeTransferFrom(
            //     IERC20(address(numa)),
            //     msg.sender,
            //     address(this),
            //     leverageDebt
            // );
            
            // numa.burn(leverageDebt);
            numa.burnFrom(msg.sender,leverageDebt);
            leverageDebt = 0;
            lockNumaSupply(false);
        

        }
        else if (msg.sender == address(cNuma))
        {
            // send lst
            SafeERC20.safeTransferFrom(
                IERC20(lstToken),
                msg.sender,
                address(this),
                leverageDebt
            );
            leverageDebt = 0;
            lockLstBalance(false);
        }
        else
        {
            revert("not allowed");
        }
        
    }


    /**
     * @dev Withdraw any ERC20 from vault
     */
    function withdrawToken(address _tokenAddress,uint256 _amount,address _receiver) external onlyOwner
    {
        require(!isWithdrawRevoked);
        SafeERC20.safeTransfer(IERC20(_tokenAddress),_receiver,_amount);
    }

    function revokeWithdraw() external onlyOwner
    {
        isWithdrawRevoked = true;
    }

    function isContract(address addr) internal view returns (bool) {
        uint extSize;
        assembly {
            extSize := extcodesize(addr) // returns 0 if EOA, >0 if smart contract
        }
        return (extSize > 0);
    }
}
