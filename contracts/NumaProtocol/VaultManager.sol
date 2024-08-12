// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/INumaVault.sol";

import "../Numa.sol";

import "../interfaces/INuAssetManager.sol";
import "../utils/constants.sol";
import "hardhat/console.sol";

contract VaultManager is IVaultManager, Ownable2Step {

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet vaultsList;

    INuAssetManager public nuAssetManager;
    NUMA public immutable numa;
  

    uint public initialRemovedSupply;
    uint public initialLPRemovedSupply;

    uint public constantRemovedSupply;
  
    bool public islockedSupply;
    uint public lockedSupply;

    uint public decayPeriod;
    uint public decayPeriodLP;

    uint public startTime;
    bool public isDecaying;


   

    uint constant max_vault = 50;

    // sell fee
    uint16 public sell_fee = 950; // 5%
    uint16 last_sell_fee = 950;

    // buy fee
    uint16 public buy_fee = 950; // 5%
    // min numa price in Eth
    uint minNumaPriceEth = 0.000001 ether;



    uint public cf_liquid_severe = 1500; 
    uint16 public sell_fee_debaseValue = 10;
    uint16 public sell_fee_rebaseValue = 10;
    uint16 public sell_fee_minimum = 500;
    uint public sell_fee_deltaRebase = 24 hours;
    uint public sell_fee_deltaDebase = 24 hours;
  
    uint lastBlockTime_sell_fee;   
    uint public sell_fee_update_blocknumber;


    // synth minting/burning parameters
    uint public cf_critical = 1100;
    uint public cf_severe = 1500;
    uint public cf_warning = 1700;
    uint public debaseValue = 20;//base 1000
    uint public rebaseValue = 30;//base 1000
    uint public minimumScale = 500;
    uint public deltaRebase = 24 hours;
    uint public deltaDebase = 24 hours;
    uint lastScale = 1000;
    uint lastScaleOverride = 1000;
    uint lastBlockTime;
    uint public synth_scaling_update_blocknumber;



    // 
    event SetNuAssetManager(address nuAssetManager);
    event RemovedVault(address);
    event AddedVault(address);
    event SetMinimumNumaPriceEth(uint _minimumPriceEth);
    event SellFeeUpdated(uint16 sellFee);
    event BuyFeeUpdated(uint16 buyFee);
    event SetScalingParameters(
        uint cf_critical,
        uint cf_warning,
        uint cf_severe,
        uint debaseValue,
        uint rebaseValue,
        uint deltaDebase,
        uint deltaRebase,
        uint minimumScale);

    event SetSellFeeParameters(
        uint _cf_liquid_severe,
        uint16 _sell_fee_debaseValue,
        uint16 _sell_fee_rebaseValue,
        uint _sell_fee_deltaDebase,
        uint _sell_fee_deltaRebase,      
        uint16 _sell_fee_minimum );

    constructor(
        address _numaAddress,
        address _nuAssetManagerAddress     
    ) Ownable(msg.sender) {
        numa = NUMA(_numaAddress);       
        nuAssetManager = INuAssetManager(_nuAssetManagerAddress);
        
        uint blocktime = block.timestamp;
        uint blocknumber = block.number;
        lastBlockTime_sell_fee = blocktime;
        lastBlockTime = blocktime;
        sell_fee_update_blocknumber = blocknumber;
        synth_scaling_update_blocknumber = blocknumber;

    }

    function getNuAssetManager() external view returns (INuAssetManager)
    {
        return nuAssetManager;

    }

    function startDecay() external onlyOwner
    {
        startTime = block.timestamp;
        isDecaying = true;
    }

    function setMinimumNumaPriceEth(uint _minimumPriceEth) external onlyOwner
    {
        minNumaPriceEth = _minimumPriceEth;
        emit SetMinimumNumaPriceEth(_minimumPriceEth);
    }

    function setConstantRemovedSupply(uint _constantRemovedSupply) external onlyOwner
    {
        constantRemovedSupply = _constantRemovedSupply;
    }

  function setScalingParameters(uint _cf_critical,
        uint _cf_warning,
        uint _cf_severe,
        uint _debaseValue,
        uint _rebaseValue,
        uint _deltaDebase,
        uint _deltaRebase,
        uint _minimumScale) external onlyOwner
    {

        getSynthScalingUpdate();
        cf_critical = _cf_critical;
        cf_warning = _cf_warning;
        cf_severe = _cf_severe;
        debaseValue = _debaseValue;
        rebaseValue = _rebaseValue;
        deltaRebase = _deltaRebase;
        deltaDebase = _deltaDebase;
        minimumScale = _minimumScale;
        emit SetScalingParameters(
            _cf_critical,
            _cf_warning,
            _cf_severe,
            _debaseValue,
            _rebaseValue,
            _deltaDebase,
            _deltaRebase,
            _minimumScale
            );
    }


  function setSellFeeParameters(uint _cf_liquid_severe,
        uint16 _sell_fee_debaseValue,
        uint16 _sell_fee_rebaseValue,
        uint _sell_fee_deltaDebase,
        uint _sell_fee_deltaRebase,      
        uint16 _sell_fee_minimum ) external onlyOwner
    {

        getSellFeeScalingUpdate();
        cf_liquid_severe = _cf_liquid_severe;
        sell_fee_debaseValue = _sell_fee_debaseValue;
        sell_fee_rebaseValue = _sell_fee_rebaseValue;
        sell_fee_deltaDebase = _sell_fee_deltaDebase;
        sell_fee_deltaRebase = _sell_fee_deltaRebase;
        sell_fee_minimum = _sell_fee_minimum;

        emit SetSellFeeParameters(
           _cf_liquid_severe,
           _sell_fee_debaseValue,
           _sell_fee_rebaseValue,
           _sell_fee_deltaDebase,
           _sell_fee_deltaRebase,      
           _sell_fee_minimum
           );
    }



    /**
     * @dev Set Sell fee percentage (exemple: 5% fee --> fee = 950)
     */
    function setSellFee(uint16 _fee) external onlyOwner {
        require(_fee <= BASE_1000, "fee above 1000");
        sell_fee = _fee;

        // careful
        // changing sell fee will reset sell_fee scaling
        last_sell_fee = sell_fee;
        lastBlockTime_sell_fee = block.timestamp;   
        sell_fee_update_blocknumber = block.number;

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

    function getBuyFee() external view returns (uint16)
    {
        return buy_fee;
    }

    function getSellFeeOriginal() external view returns (uint16)
    {
        return sell_fee;
    }

    function getWarningCF() external view returns (uint)
    {
        return cf_warning;
    }

    function getSellFeeScalingUpdate() public returns (uint16 sell_fee_memory,uint blockTime)
    {  
        uint currentBlock = block.number;
        if (currentBlock == sell_fee_update_blocknumber)
        {
            (sell_fee_memory, blockTime) = (last_sell_fee,lastBlockTime_sell_fee);
         
        }
        else {
            (sell_fee_memory,blockTime) = getSellFeeScaling();
            // save 
            last_sell_fee = sell_fee_memory;
            lastBlockTime_sell_fee = blockTime;
            sell_fee_update_blocknumber = currentBlock;
        }
    }

    function getSellFeeScaling() public view returns (uint16,uint)
    {  
        uint lastSellFee = last_sell_fee;
        // synth scaling
        uint currentLiquidCF = getGlobalLiquidCF();
        uint blockTime = block.timestamp;
        if (currentLiquidCF < cf_liquid_severe)
        {        
            // we need to debase
            if (blockTime > (lastBlockTime_sell_fee + sell_fee_deltaDebase))
            {
                // debase again
                uint ndebase = (blockTime - lastBlockTime_sell_fee)/(sell_fee_deltaDebase);
                ndebase = ndebase * sell_fee_debaseValue;

                    if (lastSellFee > ndebase)
                    {
                        lastSellFee = lastSellFee - ndebase;
                        if (lastSellFee < sell_fee_minimum)
                            lastSellFee = sell_fee_minimum;
                    }
                    else
                        lastSellFee = sell_fee_minimum;
            } 

        }
        else
        {
            if (last_sell_fee < sell_fee)
            {

                // need to rebase
                if (blockTime > (lastBlockTime_sell_fee + sell_fee_deltaRebase))
                {
                    // rebase
                    uint nrebase = (blockTime - lastBlockTime_sell_fee)/(sell_fee_deltaRebase);
                  
                    nrebase = nrebase * sell_fee_rebaseValue;
                  
                    lastSellFee = lastSellFee + nrebase;
                  
                    if (lastSellFee > sell_fee)
                        lastSellFee = sell_fee;
                } 
               

            }
        }

        return (uint16(lastSellFee),blockTime);
    }
 
    function updateAll() public returns (uint scale,uint16 sell_fee_res)
    {
        (scale,,) = getSynthScalingUpdate();
        (sell_fee_res,) = getSellFeeScalingUpdate();
    }

    function getSynthScalingUpdate() public returns (uint scaleOverride, uint scaleMemory,uint blockTime)
    {  
        uint currentBlock = block.number;
        if (currentBlock == synth_scaling_update_blocknumber)
        {
            (scaleOverride, scaleMemory,blockTime) = (lastScaleOverride,lastScale,lastBlockTime);
         
        }
        else {
            (scaleOverride, scaleMemory,blockTime) = getSynthScaling();
            // save 
            lastScaleOverride = scaleOverride;
            lastScale = scaleMemory;
            lastBlockTime = blockTime;
            synth_scaling_update_blocknumber = currentBlock;
            
        }
    }

    function getSynthScaling() public virtual view returns (uint,uint,uint)// virtual for test&overrides
    {
        
        uint lastScaleMemory = lastScale;
        // synth scaling
        uint currentCF = getGlobalCF();
        uint blockTime = block.timestamp;
        if (currentCF < cf_severe)
        {        
            // we need to debase

            //if (lastScaleMemory < BASE_1000)
            {
                // we are currently in debase/rebase mode

                if (blockTime > (lastBlockTime + deltaDebase))
                {
                    // debase again
                    uint ndebase = (blockTime - lastBlockTime)/(deltaDebase);

                    ndebase = ndebase * debaseValue;

                    if (lastScaleMemory > ndebase)
                    {
                        lastScaleMemory = lastScaleMemory - ndebase;
                        if (lastScaleMemory < minimumScale)
                            lastScaleMemory = minimumScale;
                    }
                    else
                        lastScaleMemory = minimumScale;
                } 

            }
            // else
            // {
            //     // start debase
            //     lastScaleMemory = lastScaleMemory - debaseValue;
            // }
        }
        else
        {
            if (lastScaleMemory < BASE_1000)
            {

                // need to rebase
                if (blockTime > (lastBlockTime + deltaRebase))
                {
                    // rebase
                    uint nrebase = (blockTime - lastBlockTime)/(deltaRebase);
                  
                    nrebase = nrebase * rebaseValue;
                  
                    lastScaleMemory = lastScaleMemory + nrebase;
                  
                    if (lastScaleMemory > BASE_1000)
                        lastScaleMemory = BASE_1000;
                } 
               

            }
        }

        // apply scale to synth burn price
        uint scale1000 = lastScaleMemory;

        // CRITICAL_CF
        if (currentCF < cf_critical)
        {
            // scale such that currentCF = cf_critical
            // DBG
            console.logUint(currentCF);
                        console.logUint(cf_critical);
            console.log("critical reached");
            
            uint scaleSecure = (currentCF*BASE_1000)/cf_critical;
            if (scaleSecure < scale1000)
                scale1000 = scaleSecure;
        }
        return (scale1000,lastScaleMemory,blockTime);

    }


    /**
     * @notice lock numa supply in case of a flashloan so that numa price does not change
     */
    function lockSupplyFlashloan(bool _lock) external 
     {
        require(isVault(msg.sender),"only vault");      
        if (_lock)
        {
            lockedSupply = getNumaSupply();
        }
        islockedSupply = _lock;
    }

    function setDecayValues(uint _initialRemovedSupply, uint _decayPeriod,uint _initialRemovedSupplyLP, uint _decayPeriodLP,uint _constantRemovedSupply) external onlyOwner
    {
        initialRemovedSupply = _initialRemovedSupply;
        initialLPRemovedSupply = _initialRemovedSupplyLP;
        constantRemovedSupply = _constantRemovedSupply;
        decayPeriod = _decayPeriod;
        decayPeriodLP = _decayPeriodLP;
        // start decay will have to be called again
        // CAREFUL: IF DECAYING, ALL VAULTS HAVE TO BE PAUSED WHEN CHANGING THESE VALUES, UNTIL startDecay IS CALLED
        isDecaying = false;

    }


    function isVault(address _addy) public view returns (bool)
    {
        return (vaultsList.contains(_addy));
    }

    /**
     * @dev set the INuAssetManager address (used to compute synth value in Eth)
     */
    function setNuAssetManager(address _nuAssetManager) external onlyOwner {
        require(_nuAssetManager != address(0x0), "zero address");
        nuAssetManager = INuAssetManager(_nuAssetManager);
        emit SetNuAssetManager(_nuAssetManager);
    }

    /**
     * @dev How many Numas from lst token amount
     */
    function tokenToNuma(
        uint _inputAmount,
        uint _refValueWei,
        uint _decimals,
        uint _synthScaling
    ) external view returns (uint256) {
        uint EthBalance = getTotalBalanceEth();
        require(EthBalance > 0,"empty vaults");
        uint256 EthValue = FullMath.mulDiv(
            _refValueWei,
            _inputAmount,
            _decimals
        );
        


        uint synthValueInEth = getTotalSynthValueEth();
        synthValueInEth = (synthValueInEth*BASE_1000)/_synthScaling;
        uint circulatingNuma = getNumaSupply();

      
        uint result;
        if (EthBalance <= synthValueInEth)
        {
            // extreme case use minim numa price in Eth
            result = FullMath.mulDiv(
                EthValue,
                 1 ether,// 1 ether because numa has 18 decimals
                 minNumaPriceEth
            );

        }
        else
        {
            uint numaPrice = FullMath.mulDiv(
            1 ether,
            EthBalance - synthValueInEth,
            circulatingNuma
            );

            if (numaPrice < minNumaPriceEth)
            {
                // extreme case use minim numa price in Eth
                result = FullMath.mulDiv(
                    EthValue,
                     1 ether,// 1 ether because numa has 18 decimals
                     minNumaPriceEth
                );
            }
            else {
                result = FullMath.mulDiv(
                    EthValue,
                    circulatingNuma,
                    (EthBalance - synthValueInEth)
                );
            }
        }
        return result;
    }

    /**
     * @dev How many lst tokens from numa amount
     */
    function numaToToken(
        uint _inputAmount,
        uint _refValueWei,
        uint _decimals,
        uint _synthScaling
    ) external view returns (uint256) {
        uint EthBalance = getTotalBalanceEth();
        require(EthBalance > 0,"empty vaults");

        uint synthValueInEth = getTotalSynthValueEth();

        synthValueInEth = (synthValueInEth*BASE_1000)/_synthScaling;


        uint circulatingNuma = getNumaSupply();
        

 
        require(circulatingNuma > 0, "no numa in circulation");

        uint result;
        if (EthBalance <= synthValueInEth)
        {
            result = FullMath.mulDiv(
                FullMath.mulDiv(
                    _inputAmount,
                    minNumaPriceEth,
                    1 ether// 1 ether because numa has 18 decimals
                ),
                _decimals,
                _refValueWei
            );
            
        }
        else
        {
            uint numaPrice = FullMath.mulDiv(
            1 ether,
            EthBalance - synthValueInEth,
            circulatingNuma
            );

            if (numaPrice < minNumaPriceEth)
            {
                result = FullMath.mulDiv(
                   FullMath.mulDiv(
                        _inputAmount,
                        minNumaPriceEth,
                        1 ether// 1 ether because numa has 18 decimals
                    ),
                    _decimals,
                    _refValueWei
                );
            }
            else {
                
            
                // using snaphot price
                result = FullMath.mulDiv(
                    FullMath.mulDiv(
                        _inputAmount,
                        EthBalance - synthValueInEth,
                        circulatingNuma
                    ),
                    _decimals,
                    _refValueWei
                );
            }
            
        }
        return result;
    }



   


    function GetNumaPriceEth(uint _inputAmount) external view returns (uint256)
    {
        uint EthBalance = getTotalBalanceEth();
        require(EthBalance > 0,"empty vaults");

        uint synthValueInEth = getTotalSynthValueEth();
        (uint scaling,,) = getSynthScaling();  
        synthValueInEth = (synthValueInEth*BASE_1000)/scaling;
        uint circulatingNuma = getNumaSupply();

        require(circulatingNuma > 0, "no numa in circulation");
        uint result;
       
        if (EthBalance <= synthValueInEth)
        {
            result = FullMath.mulDiv(
                        _inputAmount,
                        minNumaPriceEth,
                        1 ether// 1 ether because numa has 18 decimals
                    );
        }
        else
        {
            uint numaPrice = FullMath.mulDiv(
                1 ether,
                EthBalance - synthValueInEth,
                circulatingNuma
                );

            if (numaPrice < minNumaPriceEth)
            {
                result = FullMath.mulDiv(
                        _inputAmount,
                        minNumaPriceEth,
                        1 ether// 1 ether because numa has 18 decimals
                    );
            }
            else {                
                result = FullMath.mulDiv(
                    _inputAmount,
                    EthBalance - synthValueInEth,
                    circulatingNuma
                );
            }
        }
        return result;

    }

    function GetNumaPerEth(
        uint _inputAmount
    ) external view returns (uint256)
    {
        uint EthBalance = getTotalBalanceEth();
        require(EthBalance > 0,"empty vaults");

        uint synthValueInEth = getTotalSynthValueEth();
        (uint scaling,,) = getSynthScaling();  
        synthValueInEth = (synthValueInEth*BASE_1000)/scaling;
        uint circulatingNuma = getNumaSupply();

        require(circulatingNuma > 0, "no numa in circulation");
        uint result;
        
        if (EthBalance <= synthValueInEth)
        {
            // extreme case use minim numa price in Eth
            result = FullMath.mulDiv(
                _inputAmount,
                 1 ether,// 1 ether because numa has 18 decimals
                 minNumaPriceEth
            );

            
        }
        else
        {
            uint numaPrice = FullMath.mulDiv(
                1 ether,
                EthBalance - synthValueInEth,
                circulatingNuma
                );

            if (numaPrice < minNumaPriceEth)
            {
                result = FullMath.mulDiv(
                    _inputAmount,
                     1 ether,// 1 ether because numa has 18 decimals
                     minNumaPriceEth
                     );
            }
            else 
            {
                    
                // using snaphot price
                result = FullMath.mulDiv(_inputAmount,circulatingNuma,
                    EthBalance - synthValueInEth                
                );
            }
        }
        return result;

    }



    /**
     * @dev Total synth value in Eth
     */
    function getTotalSynthValueEth() public view returns (uint256) {
        require(
            address(nuAssetManager) != address(0),
            "nuAssetManager not set"
        );
        return nuAssetManager.getTotalSynthValueEth();
    }

    /**
     * @dev total numa supply without wallet's list balances
     * @notice for another vault, either we use this function from this vault, either we need to set list in the other vault too
     */
    function getNumaSupply() public view returns (uint) {
        if (islockedSupply)
            return lockedSupply;

        uint circulatingNuma = numa.totalSupply();
        uint currentRemovedSupply = initialRemovedSupply;
        uint currentLPRemovedSupply = initialLPRemovedSupply;

        uint currentTime = block.timestamp;
        if (isDecaying && (currentTime > startTime))
        {
            if (decayPeriod > 0)
            {
                if (currentTime >= startTime+decayPeriod)
                {
                    currentRemovedSupply = 0;
                }
                else 
                {
                    uint delta = ((currentTime - startTime) * initialRemovedSupply)/decayPeriod;
                    currentRemovedSupply -= (delta);                
                }
            }
            if (decayPeriodLP > 0)
            {
                if (currentTime >= startTime+decayPeriodLP)
                {
                    currentLPRemovedSupply = 0;
                }
                else 
                {
                    uint delta = ((currentTime - startTime) * initialLPRemovedSupply)/decayPeriodLP;
                    currentLPRemovedSupply -= (delta);                
                }
            } 
        }

        circulatingNuma = circulatingNuma - currentRemovedSupply - currentLPRemovedSupply - constantRemovedSupply;
        return circulatingNuma;
    }


    /**
     * @dev returns vaults list
     */
    function getVaults() external view returns (address[] memory) {
        return vaultsList.values();
    }

    /**
     * @dev adds a vault to the total balance
     */
    function addVault(address _vault) external onlyOwner {
        require(vaultsList.length() < max_vault, "too many vaults");
        require(vaultsList.add(_vault), "already in list");
        emit AddedVault(_vault);
    }

    /**
     * @dev removes a vault from total balance
     */
    function removeVault(address _vault) external onlyOwner {
        require(vaultsList.contains(_vault), "not in list");
        vaultsList.remove(_vault);
        emit RemovedVault(_vault);
    }

    /**
     * @dev sum of all vaults balances in Eth
     */
    function getTotalBalanceEth() public view returns (uint256) {
        uint result;
        uint256 nbVaults = vaultsList.length();
        require(nbVaults <= max_vault, "too many vaults in list");

        for (uint256 i = 0; i < nbVaults; i++) {
            result += INumaVault(vaultsList.at(i)).getEthBalance();
        }
        return result;
    }

    /**
     * @dev sum of all vaults balances in Eth excluding debts
     */
    function getTotalBalanceEthNoDebt() public view returns (uint256) {
        uint result;
        uint256 nbVaults = vaultsList.length();
        require(nbVaults <= max_vault, "too many vaults in list");

        for (uint256 i = 0; i < nbVaults; i++) {
            result += INumaVault(vaultsList.at(i)).getEthBalanceNoDebt();
        }
        return result;
    }

    function accrueInterests() external 
    {
        uint256 nbVaults = vaultsList.length();
        require(nbVaults <= max_vault, "too many vaults in list");

        for (uint256 i = 0; i < nbVaults; i++) 
        {            
            INumaVault(vaultsList.at(i)).accrueInterestLending();
        }
    }

    function getGlobalCF() public view returns (uint)
    {
        uint EthBalance = getTotalBalanceEth();
        uint synthValue = nuAssetManager.getTotalSynthValueEth();

        if (synthValue > 0)
        {
            return (EthBalance*BASE_1000)/synthValue;
        }
        else
        {
            return MAX_CF;
        }
    }

    function getGlobalLiquidCF() public view returns (uint)
    {
        uint EthBalance = getTotalBalanceEthNoDebt();
        uint synthValue = nuAssetManager.getTotalSynthValueEth();

        if (synthValue > 0)
        {
            return (EthBalance*BASE_1000)/synthValue;
        }
        else
        {
            return MAX_CF;
        }
    }
}
