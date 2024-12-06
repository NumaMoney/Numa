//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts_5.0.2/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts_5.0.2/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts_5.0.2/utils/Pausable.sol";
import "@openzeppelin/contracts_5.0.2/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts_5.0.2/utils/structs/EnumerableSet.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "../Numa.sol";
import "../interfaces/IVaultOracleSingle.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/INumaVault.sol";

import "./NumaMinter.sol";
import "../lending/CNumaToken.sol";

import "@openzeppelin/contracts_5.0.2/utils/structs/EnumerableSet.sol";
import "../utils/constants.sol";

/// @title Numa vault to mint/burn Numa to lst token
contract NumaVault is Ownable2Step, ReentrancyGuard, Pausable, INumaVault {
    using EnumerableSet for EnumerableSet.AddressSet;

    // address that receives fees
    address payable private fee_address;
    // address that receives REWARDS (extracted from lst token rebase)
    address payable private rwd_address;

    bool private isFeeReceiver;
    bool private isRwdReceiver;

    // fee that is sent to fee_address
    // percentage of buy/sell fee in base 1000
    uint16 public fees = 200; //20%
    // amount percentage limit sent to fee_address
    uint16 public feesMaxAmountPct = 50; //5%

    mapping(address => bool) feeWhitelisted;

    uint16 public max_percent = 100; //10%

    // threshold for reward extraction
    uint public rwd_threshold = 0;

    //
    NUMA public immutable numa;
    NumaMinter public immutable minterContract;
    IERC20 public immutable lstToken;
    IVaultOracleSingle public oracle;

    IVaultManager public vaultManager;

    // reward extraction variables
    uint256 public last_extracttimestamp;
    uint256 public last_lsttokenvalueWei;

    // constants
    // minimum input amount for buy/sell
    uint256 public constant MIN = 1000;

    // decimals of lst token
    uint256 public immutable decimals;

    bool isWithdrawRevoked = false;

    // lending parameters
    uint public maxBorrow;
    uint public cf_liquid_warning = 2000; // 200%
    uint debt;
    uint public rewardsFromDebt;
    uint maxLstProfitForLiquidations;

    bool buyPaused = false;

    bool isLiquidityLocked;
    uint lstLockedBalance;
    uint lstLockedBalanceRaw;

    CNumaToken public cLstToken;
    CNumaToken public cNuma;
    uint leverageDebt;

    // for reth borrowers only
    uint public minBorrowAmountAllowPartialLiquidation = 10 ether;
    // Events
    event SetOracle(address oracle);
    event SetVaultManager(address vaultManager);
    event Buy(uint256 received, uint256 sent, address receiver);
    event Sell(uint256 sent, uint256 received, address receiver);
    event Fee(uint256 fee, address feeReceiver);
    event FeeUpdated(uint16 Fee, uint16 MaxPctAmount);
    event MaxPercentUpdated(uint16 NewValue);
    event ThresholdUpdated(uint256 newThreshold);
    event FeeAddressUpdated(address feeAddress);
    event RwdAddressUpdated(address rwdAddress);
    event AddedToRemovedSupply(address _address);
    event RemovedFromRemoveSupply(address _address);
    event RewardsExtracted(uint _rwd, uint _currentvalueWei);
    event RewardsDebtExtracted(uint _rwd);
    event SetCTokens(address cNuma, address crEth);
    event SetMaxBorrow(uint _maxBorrow);
    event BorrowedVault(uint _amount);
    event RepaidVault(uint _amount);
    event SetMaxProfit(uint _maxProfit);
    event SetCFLiquidWarning(uint _cfLiquidWarning);
    event Whitelisted(address _addy, bool _wl);

    // AUDITV2FIX: added in liquidation functions
    modifier notBorrower(address _borrower) {
        require(msg.sender != _borrower, "cant liquidate your own position");
        _;
    }
    constructor(
        address _numaAddress,
        address _tokenAddress,
        uint256 _decimals,
        address _oracleAddress,
        address _minterAddress,
        uint _existingDebt, // in case of migration
        uint _existingRwdFromDebt // in case of migration
    ) Ownable(msg.sender) {
        minterContract = NumaMinter(_minterAddress);
        numa = NUMA(_numaAddress);
        oracle = IVaultOracleSingle(_oracleAddress);
        lstToken = IERC20(_tokenAddress);
        decimals = _decimals;

        // lst rewards
        last_extracttimestamp = block.timestamp;
        last_lsttokenvalueWei = oracle.getTokenPrice(decimals);

        // debt for migration
        debt = _existingDebt;
        rewardsFromDebt = _existingRwdFromDebt;
        // paused by default because might be empty
        _pause();
    }

    /**
     * @dev pause vault
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev unpause vault
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    // buys can be paused if we want to force people to buy from other vaults

    /**
     * @dev unpause buying and selling from vault
     */
    function pauseBuy(bool _buyPaused) external onlyOwner {
        buyPaused = _buyPaused;
    }

    /**
     * @dev adds an address as fee whitelisted
     */
    function setFeeWhitelist(
        address _addy,
        bool _whitelisted
    ) external onlyOwner {
        feeWhitelisted[_addy] = _whitelisted;
        emit Whitelisted(_addy, _whitelisted);
    }

    /**
     * @dev minimum reth borrow balance needed to allow partial liquidations
     */
    function setMinBorrowAmountAllowPartialLiquidation(
        uint _minBorrowAmountAllowPartialLiquidation
    ) external onlyOwner {
        minBorrowAmountAllowPartialLiquidation = _minBorrowAmountAllowPartialLiquidation;
    }

    /**
     * @dev set the IVaultOracle address (used to compute token price in Eth)
     */
    function setCTokens(address _cNuma, address _clstToken) external onlyOwner {
        cNuma = CNumaToken(_cNuma);
        cLstToken = CNumaToken(_clstToken);
        emit SetCTokens(_cNuma, _clstToken);
    }

    function getcNumaAddress() external view returns (address) {
        return address(cNuma);
    }
    function getcLstAddress() external view returns (address) {
        return address(cLstToken);
    }

    /**
     * @dev set the cf_liquid_warning
     */
    function setCFLiquidWarning(uint _cFLiquidWarning) external onlyOwner {
        // CF will change so we need to update interest rates
        updateVault();

        cf_liquid_warning = _cFLiquidWarning;
        emit SetCFLiquidWarning(_cFLiquidWarning);
    }

    /**
     * @dev set the max borrow amount from vault
     */
    function setMaxBorrow(uint _maxBorrow) external onlyOwner {
        // CF will change so we need to update interest rates
        updateVault();

        maxBorrow = _maxBorrow;
        emit SetMaxBorrow(_maxBorrow);
    }

    /**
     * @dev max profit (in reth) for liquidators
     */
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
    function setRwdAddress(
        address _address,
        bool _isRwdReceiver
    ) external onlyOwner {
        rwd_address = payable(_address);
        isRwdReceiver = _isRwdReceiver;
        emit RwdAddressUpdated(_address);
    }

    /**
     * @dev Set Fee address
     */
    function setFeeAddress(
        address _address,
        bool _isFeeReceiver
    ) external onlyOwner {
        fee_address = payable(_address);
        isFeeReceiver = _isFeeReceiver;
        emit FeeAddressUpdated(_address);
    }

    /**
     * @dev Set Fee percentage (exemple: 1% fee --> fee = 10)
     */
    function setFee(uint16 _fees, uint16 _feesMaxAmountPct) external onlyOwner {
        require(_fees <= BASE_1000, "above 1000");
        require(_feesMaxAmountPct <= BASE_1000, "above 1000");
        fees = _fees;
        feesMaxAmountPct = _feesMaxAmountPct;
        emit FeeUpdated(_fees, _feesMaxAmountPct);
    }

    /**
     * @dev max buy amount in percentage of vault's balance
     */
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

    /**
     * @dev vault balance including debt from lending protocol
     */
    function getVaultBalance() internal view returns (uint) {
        if (isLiquidityLocked) {
            return lstLockedBalance;
        } else {
            uint balance = lstToken.balanceOf(address(this));
            balance += (debt - rewardsFromDebt); // debt is owned by us but rewards will be sent so not ours anymore
            return balance;
        }
    }

    /**
     * @dev vault balance excluding debt from lending protocol
     */
    function getVaultBalanceNoDebt() internal view returns (uint) {
        if (isLiquidityLocked) {
            return lstLockedBalanceRaw;
        } else {
            return lstToken.balanceOf(address(this));
        }
    }

    /**
     * @dev returns the estimated rewards value of lst token
     */
    function rewardsValue() public view returns (uint256, uint256, uint256) {
        require(address(oracle) != address(0), "oracle not set");
        uint currentvalueWei = oracle.getTokenPrice(decimals);
        if (currentvalueWei <= last_lsttokenvalueWei) {
            return (0, currentvalueWei, 0);
        }
        uint diff = (currentvalueWei - last_lsttokenvalueWei);
        uint balance = getVaultBalanceNoDebt();
        uint rwd = FullMath.mulDiv(balance, diff, currentvalueWei);
        // extract from debt. Substract rewardsFromDebt as it's not supposed to be in the vault anymore
        uint debtRwd = FullMath.mulDiv(
            (debt - rewardsFromDebt),
            diff,
            currentvalueWei
        );
        return (rwd, currentvalueWei, debtRwd);
    }

    /**
     * @dev lst rewards extraction
     */
    function extractInternal(
        uint rwd,
        uint currentvalueWei,
        uint rwdDebt
    ) internal {
        last_extracttimestamp = block.timestamp;
        last_lsttokenvalueWei = currentvalueWei;

        // rewards from debt are not sent, they are accumulated to be sent when there's a repay
        rewardsFromDebt += rwdDebt;
        if (rwd_address != address(0)) {
            SafeERC20.safeTransfer(IERC20(lstToken), rwd_address, rwd);
            if (isContract(rwd_address) && isRwdReceiver) {
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
     * @notice no require as it will be called from buy/sell function and we only want to skip this step if
     * conditions are not filled
     */
    function extractRewardsNoRequire() internal {
        if (block.timestamp >= (last_extracttimestamp + 24 hours)) {
            (
                uint256 rwd,
                uint256 currentvalueWei,
                uint256 rwdDebt
            ) = rewardsValue();
            if (rwd > rwd_threshold) {
                extractInternal(rwd, currentvalueWei, rwdDebt);
            }
        }
    }

    /**
     * @dev vaults' balance in Eth including debt
     */
    function getEthBalance() external view returns (uint256) {
        require(address(oracle) != address(0), "oracle not set");
        uint balanceLst = getVaultBalance();

        // we use last reference value for balance computation
        uint resultEth = FullMath.mulDiv(
            last_lsttokenvalueWei,
            balanceLst,
            decimals
        );
        return resultEth;
    }

    /**
     * @dev vaults' balance in Eth excluding debt
     */
    function getEthBalanceNoDebt() public view returns (uint256) {
        require(address(oracle) != address(0), "oracle not set");
        uint balanceLst = getVaultBalanceNoDebt();

        // we use last reference value for balance computation
        uint resultEth = FullMath.mulDiv(
            last_lsttokenvalueWei,
            balanceLst,
            decimals
        );
        return resultEth;
    }

    /**
     * @dev Buy numa from token (token approval needed)
     */
    function buy(
        uint _inputAmount,
        uint _minNumaAmount,
        address _receiver
    ) external whenNotPaused returns (uint _numaOut) {
        // CF will change so we need to update interest rates
        // Note that we call that function from vault and not vaultManager, because in multi vault case, we don't need to accrue interest on
        // other vaults as we use a "local CF"

        // rEth balance will change so we need to update debasing factors
        (
            ,
            uint criticalScaleForNumaPriceAndSellFee,

        ) = updateVaultAndUpdateDebasing();

        uint256 vaultsBalance = getVaultBalance();
        uint256 MAX = (max_percent * vaultsBalance) / BASE_1000;

        require(_inputAmount <= MAX, "must trade under max");

        _numaOut = buyNoMax(
            _inputAmount,
            _minNumaAmount,
            _receiver,
            criticalScaleForNumaPriceAndSellFee,
            true
        );
    }

    /**
     * @dev Buy numa from token (token approval needed), no max check
     */
    function buyNoMax(
        uint _inputAmount,
        uint _minNumaAmount,
        address _receiver,
        uint _criticalScaleForNumaPriceAndSellFee,
        bool _transferREth
    ) internal nonReentrant whenNotPaused returns (uint _numaOut) {
        // SAME CODE AS buy() but no max amount (used for liquidations)
        // buys can be paused if we want to force people to buy from other vaults
        require(!buyPaused, "buy paused");
        require(_inputAmount > MIN, "must trade over min");

        // execute buy
        uint256 numaAmount = vaultManager.tokenToNuma(
            _inputAmount,
            last_lsttokenvalueWei,
            decimals,
            _criticalScaleForNumaPriceAndSellFee
        );

        require(numaAmount > 0, "amount of numa is <= 0");

        if (_transferREth) {
            SafeERC20.safeTransferFrom(
                lstToken,
                msg.sender,
                address(this),
                _inputAmount
            );
        }

        uint fee = vaultManager.getBuyFee();
        if (feeWhitelisted[msg.sender]) {
            fee = 1 ether; // max percent (= no fee)
        }

        _numaOut = (numaAmount * fee) / 1 ether;

        require(_numaOut >= _minNumaAmount, "Min NUMA");

        // mint numa
        minterContract.mint(_receiver, _numaOut);

        emit Buy(_numaOut, _inputAmount, _receiver);
        // fee
        if (fee_address != address(0x0)) {
            // fee to be transfered is a percentage of buy/sell fee
            uint feeTransferNum = uint(fees) * (1 ether - fee);
            uint feeTransferDen = uint(BASE_1000) * 1 ether;
            uint256 feeAmount = (feeTransferNum * _inputAmount) /
                (feeTransferDen);

            // clip sent fees
            uint256 feeAmountMax = (feesMaxAmountPct * _inputAmount) /
                BASE_1000;
            if (feeAmount > feeAmountMax) feeAmount = feeAmountMax;

            SafeERC20.safeTransfer(lstToken, fee_address, feeAmount);

            if (isContract(fee_address) && isFeeReceiver) {
                // we don't check result as contract might not implement the deposit function (if multi sig for example)
                fee_address.call(
                    abi.encodeWithSignature(
                        "DepositFromVault(uint256)",
                        feeAmount
                    )
                );
            }
            emit Fee(feeAmount, fee_address);
        }
        vaultManager.updateBuyFeePID(numaAmount, true);
    }

   /**
    * @dev extract rewards and accruInterests on lst ctoken
    */
    function updateVault() public {
        // extract rewards if any
        extractRewardsNoRequire();

        // accrue interest
        if (address(cLstToken) != address(0)) cLstToken.accrueInterest();
    }

   /**
    * @dev update vault and debasings (synth scaling, sell fee pid, scale applied in numa price when critical_cf is reached)
    */
    function updateVaultAndUpdateDebasing()
        public
        returns (
            uint scale,
            uint criticalScaleForNumaPriceAndSellFee,
            uint sell_fee_result
        )
    {
        // accrue interest
        updateVault();
        // update scaling and sell_fee
        (
            scale,
            criticalScaleForNumaPriceAndSellFee,
            sell_fee_result
        ) = vaultManager.updateDebasings();
    }
    /**
     * @dev Sell numa (burn) to token (numa approval needed)
     */
    function sell(
        uint256 _numaAmount,
        uint256 _minTokenAmount,
        address _receiver
    ) external nonReentrant whenNotPaused returns (uint _tokenOut) {
        require(_numaAmount > MIN, "must trade over min");
        // CF will change so we need to update interest rates
        // Note that we call that function from vault and not vaultManager, because in multi vault case, we don't need to accrue interest on
        // other vaults as we use a "local CF"
        // rEth balance will change so we need to update debasing factors
        (
            ,
            uint criticalScaleForNumaPriceAndSellFee,
            uint fee
        ) = updateVaultAndUpdateDebasing();

        // execute sell
        // Total Eth to be sent
        uint256 tokenAmount = vaultManager.numaToToken(
            _numaAmount,
            last_lsttokenvalueWei,
            decimals,
            criticalScaleForNumaPriceAndSellFee
        );
        require(tokenAmount > 0, "amount of token is <=0");
        require(
            lstToken.balanceOf(address(this)) >= tokenAmount,
            "not enough liquidity in vault"
        );

        if (feeWhitelisted[msg.sender]) {
            fee = 1 ether;
        }
        _tokenOut = (tokenAmount * fee) / 1 ether;
        require(_tokenOut >= _minTokenAmount, "Min Token");

        // burning numa tokens

        if (msg.sender != address(this)) {
            numa.burnFrom(msg.sender, _numaAmount);
        } else {
            numa.burn(_numaAmount);
        }
        // don't transfer to ourselves
        if (msg.sender != address(this)) {
            // transfer lst tokens to receiver
            SafeERC20.safeTransfer(lstToken, _receiver, _tokenOut);
        }
        emit Sell(_numaAmount, _tokenOut, _receiver);
        // fee
        if (fee_address != address(0x0)) {
            // fee to be transfered is a percentage of buy/sell fee
            uint feeTransferNum = fees * (1 ether - fee);
            uint feeTransferDen = uint(BASE_1000) * 1 ether;
            uint256 feeAmount = (feeTransferNum * tokenAmount) /
                (feeTransferDen);

            // clip sent fees
            uint256 feeAmountMax = (feesMaxAmountPct * tokenAmount) / BASE_1000;
            if (feeAmount > feeAmountMax) feeAmount = feeAmountMax;

            SafeERC20.safeTransfer(IERC20(lstToken), fee_address, feeAmount);

            if (isContract(fee_address) && isFeeReceiver) {
                // we don't check result as contract might not implement the deposit function (if multi sig for example)
                fee_address.call(
                    abi.encodeWithSignature(
                        "DepositFromVault(uint256)",
                        feeAmount
                    )
                );
            }

            emit Fee(feeAmount, fee_address);
        }

        vaultManager.updateBuyFeePID(_numaAmount, false);
    }

    /**
     * @dev Estimate number of tokens needed to get an amount of numa
     * no need to simulate rwd extraction as extractrewards is called when borrowing from vault
     */
    function getBuyNumaAmountIn(uint256 _amount) public view returns (uint256) {
        // how many numa from 1 lstToken
        (, , uint criticalScaleForNumaPriceAndSellFee, ) = vaultManager
            .getSynthScaling();

        uint256 numaAmount = vaultManager.tokenToNuma(
            decimals,
            last_lsttokenvalueWei,
            decimals,
            criticalScaleForNumaPriceAndSellFee
        );
        numaAmount = (numaAmount * vaultManager.getBuyFee()) / 1 ether;
        // using 1 ether here because numa token has 18 decimals
        uint result = FullMath.mulDivRoundingUp(_amount, 1 ether, numaAmount);
        return result;
    }

    /**
     * @dev Estimate number of numas needed to get an amount of token
     * no need to simulate rwd extraction as extractrewards is called when borrowing from vault
     */
    function getSellNumaAmountIn(
        uint256 _amount
    ) public view returns (uint256) {
        (, , uint criticalScaleForNumaPriceAndSellFee, ) = vaultManager
            .getSynthScaling();

        // how many tokens for 1 numa
        // using 1 ether here because numa token has 18 decimals
        uint256 tokenAmount = vaultManager.numaToToken(
            1 ether,
            last_lsttokenvalueWei,
            decimals,
            criticalScaleForNumaPriceAndSellFee
        );
        (uint sellFee, , ) = vaultManager.getSellFeeScaling();
        tokenAmount = (tokenAmount * sellFee) / 1 ether;
        uint result = FullMath.mulDivRoundingUp(_amount, decimals, tokenAmount);
        return result;
    }

    /**
     * @dev Estimate number of Numas from an amount of token with extraction simulation
     */
    function lstToNuma(uint256 _amount) external view returns (uint256) {
        (, , uint criticalScaleForNumaPriceAndSellFee, ) = vaultManager
            .getSynthScaling();

        uint256 refValue = last_lsttokenvalueWei;
        (uint256 rwd, uint256 currentvalueWei, ) = rewardsValue();
        if (rwd > rwd_threshold) {
            refValue = currentvalueWei;
        }

        uint256 numaAmount = vaultManager.tokenToNuma(
            _amount,
            refValue,
            decimals,
            criticalScaleForNumaPriceAndSellFee
        );
        return (numaAmount * vaultManager.getBuyFee()) / 1 ether;
    }

    /**
     * @dev Estimate number of tokens from an amount of numa with extraction simulation
     */
    function numaToLst(uint256 _amount) external view returns (uint256) {
        (, , uint criticalScaleForNumaPriceAndSellFee, ) = vaultManager
            .getSynthScaling();

        uint256 refValue = last_lsttokenvalueWei;
        (uint256 rwd, uint256 currentvalueWei, ) = rewardsValue();
        if (rwd > rwd_threshold) {
            refValue = currentvalueWei;
        }

        uint256 tokenAmount = vaultManager.numaToToken(
            _amount,
            refValue,
            decimals,
            criticalScaleForNumaPriceAndSellFee
        );

        (uint sellFee, , ) = vaultManager.getSellFeeScaling();
        return (tokenAmount * sellFee) / 1 ether;
    }

    /**
     * @dev max borrowable amount from vault, will also impact utilization rate of lending protocol
     */
    function getMaxBorrow() public view returns (uint256) {
        uint synthValueInEth = vaultManager.getTotalSynthValueEth();

        // single vault balance
        uint EthBalance = getEthBalanceNoDebt();

        uint synthValueWithCF = FullMath.mulDiv(
            synthValueInEth,
            cf_liquid_warning,
            BASE_1000
        );
        if (EthBalance < synthValueWithCF) return 0;
        else {
            uint resultEth = EthBalance - synthValueWithCF;
            uint resultToken = FullMath.mulDiv(
                resultEth,
                decimals,
                last_lsttokenvalueWei
            );

            // clamp it with our parameter
            uint maxBorrowLeft = 0;
            if (maxBorrow > debt)
                maxBorrowLeft = maxBorrow - debt;
            if (resultToken > maxBorrowLeft) resultToken = maxBorrowLeft;

            return resultToken;
        }
    }

    /**
     * @dev lending protocol debt
     */
    function getDebt() external view returns (uint) {
        return debt;
    }

    /**
     * @dev repay from lending protocol
     */
    function repay(uint _amount) external {
        require(msg.sender == address(cLstToken));
        require(_amount > 0, "amount <= 0");
        require(_amount <= debt, "repay more than debt");

        updateVaultAndUpdateDebasing();

        // repay
        SafeERC20.safeTransferFrom(
            lstToken,
            msg.sender,
            address(this),
            _amount
        );
        // we will use some repaid amount as rewards from our accumulated virtual rewards from debt
        uint extractedRwdFromDebt = FullMath.mulDiv(
            rewardsFromDebt,
            _amount,
            debt
        );

        if ((extractedRwdFromDebt > 0) && (rwd_address != address(0))) {
            rewardsFromDebt -= extractedRwdFromDebt;
            SafeERC20.safeTransfer(
                IERC20(lstToken),
                rwd_address,
                extractedRwdFromDebt
            );
            if (isContract(rwd_address) && isRwdReceiver) {
                // we don't check result as contract might not implement the deposit function (if multi sig for example)
                rwd_address.call(
                    abi.encodeWithSignature(
                        "DepositFromVault(uint256)",
                        extractedRwdFromDebt
                    )
                );
            }
            emit RewardsDebtExtracted(extractedRwdFromDebt);
        }

        debt = debt - _amount;
        emit RepaidVault(_amount);
    }

    /**
     * @dev borrow from lending protocol
     */
    function borrow(uint _amount) external {
        require(msg.sender == address(cLstToken));
        updateVaultAndUpdateDebasing();
        uint maxAmount = getMaxBorrow();
        require(_amount <= maxAmount, "max borrow");

        debt = debt + _amount;
        SafeERC20.safeTransfer(lstToken, msg.sender, _amount);
        emit BorrowedVault(_amount);
    }

    /**
     * @notice locks numa supply so that price stays the same during a flashloan
     * @param _lock true or false
     */
    function lockNumaSupply(bool _lock) internal {
        vaultManager.lockSupplyFlashloan(_lock);
    }


    /**
     * @notice locks lst balance so that price stays the same during a flashloan
     * @param _lock true or false
     */
    function lockLstBalance(bool _lock) internal {
        if (_lock) {
            lstLockedBalance = getVaultBalance();
            lstLockedBalanceRaw = getVaultBalanceNoDebt();
        }
        isLiquidityLocked = _lock;
    }

    function startLiquidation()
        internal
        returns (uint criticalScaleForNumaPriceAndSellFee)
    {
        (
            ,
            criticalScaleForNumaPriceAndSellFee,

        ) = updateVaultAndUpdateDebasing();
        // lock numa supply
        lockNumaSupply(true);
        // lock lst balance for pricing
        lockLstBalance(true);
    }

    function endLiquidation() internal {
        // unlock numa supply
        lockNumaSupply(false);
        // unlock use real balance for price
        lockLstBalance(false);
    }

    /**
     * @notice bad debt liquidation 
     * @param _borrower borrower address
     * @param _percentagePosition1000 prcentage of position to be liquidated
     * @param collateralToken collateral token 
     */
    function liquidateBadDebt(
        address _borrower,
        uint _percentagePosition1000,
        CNumaToken collateralToken
    ) external whenNotPaused notBorrower(_borrower) {
        require(
            (_percentagePosition1000 > 0 && _percentagePosition1000 <= 1000),
            "percentage"
        );
        require(
            (address(collateralToken) == address(cNuma)) ||
                (address(collateralToken) == address(cLstToken)),
            "bad token"
        );

        startLiquidation();

        IERC20 underlyingCollateral;
        IERC20 underlyingBorrow;
        CNumaToken borrowToken;

        if (address(collateralToken) == address(cLstToken)) {
            underlyingCollateral = IERC20(lstToken);
            underlyingBorrow = IERC20(address(numa));
            borrowToken = cNuma;
        } else {
            underlyingCollateral = IERC20(address(numa));
            underlyingBorrow = IERC20(lstToken);
            borrowToken = cLstToken;
        }

        // AUDITV2FIX using borrowBalanceCurrent to get an up to date debt
        //uint borrowAmountFull = borrowToken.borrowBalanceStored(_borrower);
        uint borrowAmountFull = borrowToken.borrowBalanceCurrent(_borrower);
        require(borrowAmountFull > 0, "no borrow");

        uint repayAmount = (borrowAmountFull * _percentagePosition1000) / 1000;

        // user supplied funds
        SafeERC20.safeTransferFrom(
            underlyingBorrow,
            msg.sender,
            address(this),
            repayAmount
        );

        // liquidate
        underlyingBorrow.approve(address(borrowToken), repayAmount);

        borrowToken.liquidateBadDebt(
            _borrower,
            repayAmount,
            _percentagePosition1000,
            CTokenInterface(address(collateralToken))
        );

        // redeem
        uint balcToken = IERC20(address(collateralToken)).balanceOf(
            address(this)
        );

        uint balBefore = IERC20(underlyingCollateral).balanceOf(address(this));
        collateralToken.redeem(balcToken);
        uint balAfter = IERC20(underlyingCollateral).balanceOf(address(this));
        uint received = balAfter - balBefore;
        // send to liquidator
        SafeERC20.safeTransfer(
            IERC20(address(underlyingCollateral)),
            msg.sender,
            received
        );

        endLiquidation();
    }

    /**
     * @notice numa borrower liquidation 
     * @param _borrower borrower address
     * @param _numaAmount amount to use for liquidation
     * @param _swapToInput boolean, do we swap seized tokens to numa
     * @param _flashloan boolean do we use a flashloan or do we provide the liquidity
     */
    function liquidateNumaBorrower(
        address _borrower,
        uint _numaAmount,
        bool _swapToInput,
        bool _flashloan
    ) external whenNotPaused notBorrower(_borrower) {
        // if using flashloan, you have to swap collateral seized to repay flashloan
        require(
            ((_flashloan && _swapToInput) || (!_flashloan)),
            "invalid param"
        );

        uint criticalScaleForNumaPriceAndSellFee = startLiquidation();

        uint numaAmount = _numaAmount;

        // minimum liquidation amount
        uint borrowAmount = cNuma.borrowBalanceCurrent(_borrower);

        // AUDITV2FIX: handle max liquidations
        if (_numaAmount == type(uint256).max) {
            numaAmount = borrowAmount;
        } else {
            // min liquidation amount
            // convert minimum amount for partial liquidations in numa
            uint minBorrowAmountAllowPartialLiquidationNuma = vaultManager
                .tokenToNuma(
                    minBorrowAmountAllowPartialLiquidation,
                    last_lsttokenvalueWei,
                    decimals,
                    criticalScaleForNumaPriceAndSellFee
                );
            uint minAmount = minBorrowAmountAllowPartialLiquidationNuma;
            if (borrowAmount < minAmount) minAmount = borrowAmount;
            require(numaAmount >= minAmount, "min liquidation");
        }

        if (_flashloan) {
            // mint
            minterContract.mint(address(this), numaAmount);
        } else {
            // user supplied funds
            SafeERC20.safeTransferFrom(
                IERC20(address(numa)),
                msg.sender,
                address(this),
                numaAmount
            );
        }

        // liquidate
        numa.approve(address(cNuma), numaAmount);
        cNuma.liquidateBorrow(
            _borrower,
            numaAmount,
            CTokenInterface(address(cLstToken))
        );

        // we should have received crEth with discount
        // redeem rEth
        uint balcToken = IERC20(address(cLstToken)).balanceOf(address(this));

        uint balBefore = IERC20(lstToken).balanceOf(address(this));
        cLstToken.redeem(balcToken);
        uint balAfter = IERC20(lstToken).balanceOf(address(this));
        uint receivedlst = balAfter - balBefore;

        if (_swapToInput) {
            // sell rEth to numa
            uint numaReceived = buyNoMax(
                receivedlst,
                numaAmount,
                address(this),
                criticalScaleForNumaPriceAndSellFee,
                false
            );

            // liquidation profit
            uint numaLiquidatorProfit = numaReceived - numaAmount;

            // compute max profit in numa

            uint maxNumaProfitForLiquidations = vaultManager.tokenToNuma(
                maxLstProfitForLiquidations,
                last_lsttokenvalueWei,
                decimals,
                criticalScaleForNumaPriceAndSellFee
            );

            // cap profit
            if (numaLiquidatorProfit > maxNumaProfitForLiquidations)
                numaLiquidatorProfit = maxNumaProfitForLiquidations;

            uint numaToSend = numaLiquidatorProfit;
            if (!_flashloan) {
                // send liquidator his profit + his provided amount
                numaToSend += numaAmount;
            }
            // send to liquidator
            SafeERC20.safeTransfer(
                IERC20(address(numa)),
                msg.sender,
                numaToSend
            );

            // burn the rest
            uint numaToBurn = numaReceived - numaToSend;
            numa.burn(numaToBurn);
        } else {
            uint lstProvidedEstimate = vaultManager.numaToToken(
                numaAmount,
                last_lsttokenvalueWei,
                decimals,
                criticalScaleForNumaPriceAndSellFee
            );

            uint lstLiquidatorProfit;
            // we don't revert if liquidation is not profitable because it might be profitable
            // by selling lst to numa using uniswap pool
            if (receivedlst > lstProvidedEstimate) {
                lstLiquidatorProfit = receivedlst - lstProvidedEstimate;
            }

            uint vaultProfit;
            if (lstLiquidatorProfit > maxLstProfitForLiquidations) {
                vaultProfit = lstLiquidatorProfit - maxLstProfitForLiquidations;
            }

            uint lstToSend = receivedlst - vaultProfit;
            // send to liquidator
            SafeERC20.safeTransfer(
                IERC20(address(lstToken)),
                msg.sender,
                lstToSend
            );
        }

        endLiquidation();
    }

    /**
     * @notice lst borrower liquidation 
     * @param _borrower borrower address
     * @param _lstAmount amount to use for liquidation
     * @param _swapToInput boolean, do we swap seized tokens to numa
     * @param _flashloan boolean do we use a flashloan or do we provide the liquidity
     */
    function liquidateLstBorrower(
        address _borrower,
        uint _lstAmount,
        bool _swapToInput,
        bool _flashloan
    ) external whenNotPaused notBorrower(_borrower) {
        // if using flashloan, you have to swap colletral seized to repay flashloan
        require(
            ((_flashloan && _swapToInput) || (!_flashloan)),
            "invalid param"
        );

        uint lstAmount = _lstAmount;

        // min liquidation amount
        uint borrowAmount = cLstToken.borrowBalanceCurrent(_borrower);

        // AUDITV2FIX: handle max liquidations
        if (_lstAmount == type(uint256).max) {
            lstAmount = borrowAmount;
        }

        uint minAmount = minBorrowAmountAllowPartialLiquidation;
        if (borrowAmount < minAmount) minAmount = borrowAmount;

        require(lstAmount >= minAmount, "min liquidation");

        uint criticalScaleForNumaPriceAndSellFee = startLiquidation();

        if (!_flashloan) {
            // user supplied funds
            SafeERC20.safeTransferFrom(
                IERC20(address(lstToken)),
                msg.sender,
                address(this),
                lstAmount
            );
        }

        // liquidate
        IERC20(lstToken).approve(address(cLstToken), lstAmount);
        cLstToken.liquidateBorrow(
            _borrower,
            lstAmount,
            CTokenInterface(address(cNuma))
        );

        // we should have received cNuma with discount
        // redeem numa
        uint balcToken = IERC20(address(cNuma)).balanceOf(address(this));
        uint balBefore = numa.balanceOf(address(this));
        cNuma.redeem(balcToken);
        uint balAfter = numa.balanceOf(address(this));
        uint receivedNuma = balAfter - balBefore;

        if (_swapToInput) {
            // sell numa to lst
            uint lstReceived = NumaVault(address(this)).sell(
                receivedNuma,
                lstAmount,
                address(this)
            );

            uint lstLiquidatorProfit = lstReceived - lstAmount;

            // cap profit
            if (lstLiquidatorProfit > maxLstProfitForLiquidations)
                lstLiquidatorProfit = maxLstProfitForLiquidations;

            uint lstToSend = lstLiquidatorProfit;
            if (!_flashloan) {
                // send profit + input amount
                lstToSend += lstAmount;
            }
            // send profit
            SafeERC20.safeTransfer(IERC20(lstToken), msg.sender, lstToSend);
        } else {
            uint numaProvidedEstimate = vaultManager.tokenToNuma(
                lstAmount,
                last_lsttokenvalueWei,
                decimals,
                criticalScaleForNumaPriceAndSellFee
            );
            uint maxNumaProfitForLiquidations = vaultManager.tokenToNuma(
                maxLstProfitForLiquidations,
                last_lsttokenvalueWei,
                decimals,
                criticalScaleForNumaPriceAndSellFee
            );

            uint numaLiquidatorProfit;
            // we don't revert if liquidation is not profitable because it might be profitable
            // by selling lst to numa using uniswap pool
            if (receivedNuma > numaProvidedEstimate) {
                numaLiquidatorProfit = receivedNuma - numaProvidedEstimate;
            }

            uint vaultProfit;
            if (numaLiquidatorProfit > maxNumaProfitForLiquidations) {
                vaultProfit =
                    numaLiquidatorProfit -
                    maxNumaProfitForLiquidations;
            }

            uint numaToSend = receivedNuma - vaultProfit;
            // send to liquidator
            SafeERC20.safeTransfer(
                IERC20(address(numa)),
                msg.sender,
                numaToSend
            );

            // AUDITV2FIX: excess vault profit numa is burnt
            if (vaultProfit > 0) numa.burn(vaultProfit);
        }
        endLiquidation();
    }

    /**
     * @dev called from CNumaToken leverage function
     * borrow from vault to deposit as collateral
     */
    function borrowLeverage(
        uint _amount,
        bool _closePosition
    ) external whenNotPaused {
        updateVaultAndUpdateDebasing();
        if (
            ((msg.sender == address(cLstToken)) && (!_closePosition)) ||
            ((msg.sender == address(cNuma)) && (_closePosition))
        ) {
            // lock numa supply
            lockNumaSupply(true);
            // borrow numa
            minterContract.mint(msg.sender, _amount);
            leverageDebt = _amount;
        } else if (
            ((msg.sender == address(cNuma)) && (!_closePosition)) ||
            ((msg.sender == address(cLstToken)) && (_closePosition))
        ) {
            // lock lst balance
            lockLstBalance(true);
            // borrow lst
            SafeERC20.safeTransfer(lstToken, msg.sender, _amount);
            leverageDebt = _amount;
        } else {
            revert("not allowed");
        }
    }

    /**
     * @dev called from CNumaToken leverage function
     * repay to vault using borrowed amount from CNumaToken (converted to collateral token)
     */
    function repayLeverage(bool _closePosition) external whenNotPaused {
        if (
            ((msg.sender == address(cLstToken)) && (!_closePosition)) ||
            ((msg.sender == address(cNuma)) && (_closePosition))
        ) {
            // repay numa
            numa.burnFrom(msg.sender, leverageDebt);
            leverageDebt = 0;
            // unlock numa supply
            lockNumaSupply(false);
        } else if (
            ((msg.sender == address(cNuma)) && (!_closePosition)) ||
            ((msg.sender == address(cLstToken)) && (_closePosition))
        ) {
            // repay lst
            SafeERC20.safeTransferFrom(
                IERC20(lstToken),
                msg.sender,
                address(this),
                leverageDebt
            );
            leverageDebt = 0;
            // unlock lst balance
            lockLstBalance(false);
        } else {
            revert("not allowed");
        }
    }

    /**
     * @dev Withdraw any ERC20 from vault
     */
    function withdrawToken(
        address _tokenAddress,
        uint256 _amount,
        address _receiver
    ) external onlyOwner {
        require(!isWithdrawRevoked);
        SafeERC20.safeTransfer(IERC20(_tokenAddress), _receiver, _amount);
    }

    function revokeWithdraw() external onlyOwner {
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
