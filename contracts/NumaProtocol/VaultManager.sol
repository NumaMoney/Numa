// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts_5.0.2/access/Ownable2Step.sol";
import "@openzeppelin/contracts_5.0.2/utils/structs/EnumerableSet.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/INumaVault.sol";

import "../Numa.sol";

import "../interfaces/INuAssetManager.sol";
import "../interfaces/INumaPrinter.sol";

import "../utils/constants.sol";

contract VaultManager is IVaultManager, Ownable2Step {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet vaultsList;

    INuAssetManager public nuAssetManager;
    INumaPrinter public printer;
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
    uint public sell_fee = 0.95 ether; // 5%
    uint sell_fee_withPID = 0.95 ether;

    // buy fee
    uint public buy_fee = 0.95 ether; // 5%
    // min numa price in Eth - extra security to prevent division by zero
    uint minNumaPriceEth = 0.0000000000001 ether;

    uint public cf_liquid_severe = 1500;
    uint public sell_fee_debaseValue = 0.01 ether;
    uint public sell_fee_rebaseValue = 0.01 ether;
    uint public sell_fee_minimum = 0.5 ether;
    uint public sell_fee_minimum_critical = 0.2 ether;
    uint public sell_fee_deltaRebase = 24 hours;
    uint public sell_fee_deltaDebase = 24 hours;
    uint public sell_fee_criticalMultiplier = 10000; // base 1000

    uint lastBlockTime_sell_fee;
    //uint public sell_fee_update_blocknumber;

    // synth minting/burning parameters
    uint public cf_critical = 1100;
    uint public cf_severe = 1500;
    uint public cf_warning = 1700;
    uint public debaseValue = 20; //base 1000
    uint public rebaseValue = 30; //base 1000
    uint public minimumScale = 500;
    uint public criticalDebaseMult = 1100; //base 1000
    uint public deltaRebase = 24 hours;
    uint public deltaDebase = 24 hours;
    uint lastSynthPID = BASE_1000;
    uint lastBlockTime;

    // the amount by which buyFee_PID increments/decrements at each event
    // uint public buyPID_decAmt = 0.000001 ether; //0.0001%
    // uint public buyPID_incAmt = 0.000001 ether; //0.0001%
    // using eth amounts
    uint public buyPID_decAmt = 0.006 ether; //0.0001%
    uint public buyPID_incAmt = 0.006 ether; //0.0001%

    uint public buyPID_decMultiplier = 10;

    // the maximum percent % differential that TWAP price must be from numa_buyPrice to trigger an increment event
    uint public buyPID_incTriggerPct = 20; // 2%

    //uint buyPID_decTriggerPct = 1.66%
    uint public buyPID_decTriggerPct = 25; //2.5%

    // is the maximum rate at which PID can increment in a xhr period. Default to the buyFee_base.
    uint public buyPID_incMaxRate = 0.0166 ether; //1.66%
    //
    uint public buyFee_max = 0.7 ether; //30%
    uint32 twapPID = 900; // 15min twp

    //
    uint public buy_fee_PID = 0;
    uint public buyPIDXhrAgo = 0;
    uint public nextCheckBlock;
    uint public nextCheckBlockWindowDelta = 4 hours;

    //
    event SetNuAssetManager(address nuAssetManager);
    event RemovedVault(address);
    event AddedVault(address);
    event SetMinimumNumaPriceEth(uint _minimumPriceEth);
    event SellFeeUpdated(uint sellFee);
    event BuyFeeUpdated(uint buyFee);
    event SetScalingParameters(
        uint cf_critical,
        uint cf_warning,
        uint cf_severe,
        uint debaseValue,
        uint rebaseValue,
        uint deltaDebase,
        uint deltaRebase,
        uint minimumScale,
        uint criticalDebaseMult
    );

    event SetSellFeeParameters(
        uint _cf_liquid_severe,
        uint _sell_fee_debaseValue,
        uint _sell_fee_rebaseValue,
        uint _sell_fee_deltaDebase,
        uint _sell_fee_deltaRebase,
        uint _sell_fee_minimum,
        uint _sell_fee_minimum_critical,
        uint _sell_fee_criticalMultiplier
    );

    constructor(
        address _numaAddress,
        address _nuAssetManagerAddress
    ) Ownable(msg.sender) {
        numa = NUMA(_numaAddress);
        nuAssetManager = INuAssetManager(_nuAssetManagerAddress);

        uint blocktime = block.timestamp;
        lastBlockTime_sell_fee = blocktime;
        lastBlockTime = blocktime;
        //sell_fee_update_blocknumber = blocknumber;
        //synth_scaling_update_blocknumber = blocknumber;
    }

    function getNuAssetManager() external view returns (INuAssetManager) {
        return nuAssetManager;
    }

    function startDecay() external onlyOwner {
        startTime = block.timestamp;
        isDecaying = true;
    }

    function setMinimumNumaPriceEth(uint _minimumPriceEth) external onlyOwner {
        minNumaPriceEth = _minimumPriceEth;
        emit SetMinimumNumaPriceEth(_minimumPriceEth);
    }

    function setConstantRemovedSupply(
        uint _constantRemovedSupply
    ) external onlyOwner {
        constantRemovedSupply = _constantRemovedSupply;
    }

    function setScalingParameters(
        uint _cf_critical,
        uint _cf_warning,
        uint _cf_severe,
        uint _debaseValue,
        uint _rebaseValue,
        uint _deltaDebase,
        uint _deltaRebase,
        uint _minimumScale,
        uint _criticalDebaseMult
    ) external onlyOwner {
        getSynthScalingUpdate();
        cf_critical = _cf_critical;
        cf_warning = _cf_warning;
        cf_severe = _cf_severe;
        debaseValue = _debaseValue;
        rebaseValue = _rebaseValue;
        deltaRebase = _deltaRebase;
        deltaDebase = _deltaDebase;
        minimumScale = _minimumScale;
        criticalDebaseMult = _criticalDebaseMult;
        emit SetScalingParameters(
            _cf_critical,
            _cf_warning,
            _cf_severe,
            _debaseValue,
            _rebaseValue,
            _deltaDebase,
            _deltaRebase,
            _minimumScale,
            _criticalDebaseMult
        );
    }

    function setBuyFeeParameters(
        uint _buyPID_incAmt,
        uint _buyPID_incTriggerPct,
        uint _buyPID_decAmt,
        uint _buyPID_decTriggerPct,
        uint _buyPID_decMultiplier,
        uint _buyPID_incMaxRate,
        uint _buyFee_max,
        uint32 _twapPID,
        uint _nextCheckBlockWindowDelta
    ) external onlyOwner {
        buyPID_incAmt = _buyPID_incAmt;
        buyPID_incTriggerPct = _buyPID_incTriggerPct;
        buyPID_decAmt = _buyPID_decAmt;
        buyPID_decTriggerPct = _buyPID_decTriggerPct;
        buyPID_decMultiplier = _buyPID_decMultiplier;
        buyPID_incMaxRate = _buyPID_incMaxRate;
        buyFee_max = _buyFee_max;
        twapPID = _twapPID;
        nextCheckBlockWindowDelta = _nextCheckBlockWindowDelta;
    }

    function setSellFeeParameters(
        uint _cf_liquid_severe,
        uint _sell_fee_debaseValue,
        uint _sell_fee_rebaseValue,
        uint _sell_fee_deltaDebase,
        uint _sell_fee_deltaRebase,
        uint _sell_fee_minimum,
        uint _sell_fee_minimum_critical,
        uint _sell_fee_criticalMultiplier
    ) external onlyOwner {
        getSellFeeScalingUpdate();
        cf_liquid_severe = _cf_liquid_severe;
        sell_fee_debaseValue = _sell_fee_debaseValue;
        sell_fee_rebaseValue = _sell_fee_rebaseValue;
        sell_fee_deltaDebase = _sell_fee_deltaDebase;
        sell_fee_deltaRebase = _sell_fee_deltaRebase;
        sell_fee_minimum = _sell_fee_minimum;
        sell_fee_minimum_critical = _sell_fee_minimum_critical;
        sell_fee_criticalMultiplier = _sell_fee_criticalMultiplier;

        emit SetSellFeeParameters(
            _cf_liquid_severe,
            _sell_fee_debaseValue,
            _sell_fee_rebaseValue,
            _sell_fee_deltaDebase,
            _sell_fee_deltaRebase,
            _sell_fee_minimum,
            _sell_fee_minimum_critical,
            _sell_fee_criticalMultiplier
        );
    }

    /**
     * @dev Set Sell fee percentage (exemple: 5% fee --> fee = 950)
     */
    function setSellFee(uint _fee) external onlyOwner {
        require(_fee <= 1 ether, "fee too high");
        sell_fee = _fee;

        // careful
        // changing sell fee will reset sell_fee scaling
        sell_fee_withPID = sell_fee;
        lastBlockTime_sell_fee = block.timestamp;
        //sell_fee_update_blocknumber = block.number;

        emit SellFeeUpdated(_fee);
    }

    /**
     * @dev Set Buy fee percentage (exemple: 5% fee --> fee = 950)
     */
    function setBuyFee(uint _fee) external onlyOwner {
        require(_fee <= 1 ether, "fee too high");
        // we do not reset PID, it will adapt on his own
        // but we need to ensure buy_fee stays in bounds
        require(_fee > (buyFee_max + buy_fee_PID), "fee too high");

        buy_fee = _fee;
        emit BuyFeeUpdated(_fee);
    }

    function getBuyFee() public view returns (uint) {
        return buy_fee - buy_fee_PID;
    }

    function getSellFeeOriginal() external view returns (uint) {
        return sell_fee;
    }

    function getWarningCF() external view returns (uint) {
        return cf_warning;
    }

    /**
     * @dev updates the buy_fee, only called from specific actions
     */
    function updateBuyFeePID(uint _numaAmount, bool _isVaultBuy) external {
        if (_numaAmount == 0) {
            return;
        }

        uint currentBlockts = block.timestamp;
        if (nextCheckBlock == 0) {
            nextCheckBlock = currentBlockts + nextCheckBlockWindowDelta;
        }
        // when delta time is reached or PID is below last reference we reset reference
        else if (currentBlockts > nextCheckBlock) {
            //reset the increment max rate params
            buyPIDXhrAgo = buy_fee_PID;
            //set new block height +xhrs from now
            nextCheckBlock = currentBlockts + nextCheckBlockWindowDelta;
        }

        if (address(printer) == address(0x0)) {
            buy_fee_PID = 0;
        } else {
            require(
                isVault(msg.sender) || (msg.sender == address(printer)),
                "only vault&printer"
            );
            uint _priceTWAP = printer.getTWAPPriceInEth(1 ether, twapPID);
            uint _vaultBuyPrice = numaToEth(1 ether, PriceType.BuyPrice);

            // we use amount in Eth
            uint ethAmount = (_numaAmount * _vaultBuyPrice) / (1 ether);

            uint pctFromBuyPrice;
            if (_priceTWAP < _vaultBuyPrice) {
                //percentage down from buyPrice  in base 1000
                pctFromBuyPrice = 1000 - (1000 * _priceTWAP) / _vaultBuyPrice;
            }

            if ((pctFromBuyPrice < buyPID_incTriggerPct) && _isVaultBuy) {
                //_price is within incTriggerPct% of buyPrice, and is a vault buy
                uint buyPID_adj = (ethAmount * buyPID_incAmt) / (1 ether);
                buy_fee_PID = buy_fee_PID + buyPID_adj; //increment buyPID

                if (buy_fee_PID > buyPIDXhrAgo) {
                    if (((buy_fee_PID - buyPIDXhrAgo) > buyPID_incMaxRate)) {
                        //does change exceed max rate over Xhrs?
                        buy_fee_PID = buyPIDXhrAgo + buyPID_incMaxRate; //cap to max rate over 4hrs
                    }
                }

                if (buy_fee < (buyFee_max + buy_fee_PID)) {
                    //buyFee above maximum allowable = clip
                    buy_fee_PID = buy_fee - buyFee_max;
                }
            } else if (
                (pctFromBuyPrice > buyPID_decTriggerPct) && (!_isVaultBuy)
            ) {
                //LP15minTWAP is below decTriggerPct% from buyPrice.

                // if pctFromBuyPrice is more than 2 x buyfee, we use our decrease multiplier
                uint basefee = 1 ether - buy_fee;
                uint buyPID_multTriggerPct = (2 * basefee * 1000) / 1 ether;
                uint buyPID_adj = (ethAmount * buyPID_decAmt) / (1 ether);

                if (pctFromBuyPrice > buyPID_multTriggerPct) {
                    // do bigger reduction
                    buyPID_adj = buyPID_adj * buyPID_decMultiplier;
                }
                if (buyPID_adj < buy_fee_PID) {
                    buy_fee_PID -= buyPID_adj;
                } else {
                    buy_fee_PID = 0;
                }
            }

            // if PID is below last reference we reset reference
            if ((buy_fee_PID < buyPIDXhrAgo)) {
                //reset the increment max rate params
                buyPIDXhrAgo = buy_fee_PID;
                nextCheckBlock = currentBlockts + nextCheckBlockWindowDelta; //set new block height +xhrs from now
            }
        }
    }

    /**
     * @dev updates the sell_fee, only called from specific actions
     */
    function getSellFeeScalingUpdate() public returns (uint sell_fee_result) {
        (
            uint result,
            uint blockTime,
            uint sell_fee_debase
        ) = getSellFeeScaling();
        // return
        sell_fee_result = result;

        // save current PID and blocktime
        sell_fee_withPID = sell_fee_debase;
        lastBlockTime_sell_fee = blockTime;
        //sell_fee_update_blocknumber = blockNumber;
    }

    /**
     * @dev returns the updated sell_fee
     */
    function getSellFeeScaling() public view returns (uint, uint, uint) {
        uint blockTime = block.timestamp;
        uint lastSellFee = sell_fee_withPID;
        // if PID/debase has already been updated in that block, no need to compute, we can use what's stored
        if (blockTime != lastBlockTime_sell_fee) {
            // synth scaling
            uint currentLiquidCF = getGlobalLiquidCF();
            if (currentLiquidCF < cf_liquid_severe) {
                // we need to debase
                // debase linearly
                uint ndebase = ((blockTime - lastBlockTime_sell_fee) *
                    sell_fee_debaseValue) / (sell_fee_deltaDebase);

                if (ndebase <= 0) {
                    // not enough time has passed to get some debase, so we reset our time reference
                    blockTime = lastBlockTime_sell_fee;
                } else {
                    if (lastSellFee > ndebase) {
                        lastSellFee = lastSellFee - ndebase;
                        // clip to minimum
                        if (lastSellFee < sell_fee_minimum)
                            lastSellFee = sell_fee_minimum;
                    } else lastSellFee = sell_fee_minimum;
                }
            } else {
                if (sell_fee_withPID < sell_fee) {
                    // we have debased so we need to rebase
                    uint nrebase = ((blockTime - lastBlockTime_sell_fee) *
                        sell_fee_rebaseValue) / (sell_fee_deltaRebase);
                    if (nrebase <= 0) {
                        // not enough time has passed to get some rebase, so we reset our time reference
                        blockTime = lastBlockTime_sell_fee;
                    } else {
                        lastSellFee = lastSellFee + nrebase;
                        if (lastSellFee > sell_fee) lastSellFee = sell_fee;
                    }
                }
            }
        }

        // Sell fee increase also considers synthetics critical scaling.
        // So, if synthetics are debased 4% in critical, then the sell fee should be 9% (5% + 4%)
        // Whichever sell fee is greater should be used at any given time
        // we use criticalScaleForNumaPriceAndSellFee because we want to use this scale in our sell_fee only when cf_critical is reached
        (, , uint criticalScaleForNumaPriceAndSellFee, ) = getSynthScaling();

        uint sell_fee_increaseCriticalCF = ((BASE_1000 -
            criticalScaleForNumaPriceAndSellFee) * 1 ether) / BASE_1000;
        // add a multiplier on top
        sell_fee_increaseCriticalCF =
            (sell_fee_increaseCriticalCF * sell_fee_criticalMultiplier) /
            1000;

        // here we use original fee value increase by this factor
        uint sell_fee_criticalCF;

        if (sell_fee > sell_fee_increaseCriticalCF)
            sell_fee_criticalCF = sell_fee - sell_fee_increaseCriticalCF;

        // clip it by min value
        if (sell_fee_criticalCF < sell_fee_minimum_critical)
            sell_fee_criticalCF = sell_fee_minimum_critical;

        uint sell_fee_result = lastSellFee;
        // Whichever sell fee is greater should be used at any given time
        if (sell_fee_criticalCF < sell_fee_result)
            sell_fee_result = sell_fee_criticalCF;

        return (sell_fee_result, blockTime, lastSellFee);
    }

   /**
     * @dev updates synth scaling only called from specific actions
     */
    function getSynthScalingUpdate()
        public
        returns (uint scaleSynthBurn, uint criticalScaleForNumaPriceAndSellFee)
    {
        uint scalePID;
        uint blockTime;
        (
            scaleSynthBurn,
            scalePID,
            criticalScaleForNumaPriceAndSellFee,
            blockTime
        ) = getSynthScaling();
        // save
        lastSynthPID = scalePID;
        lastBlockTime = blockTime;
    }


    function getSynthScaling()
        public
        view
        virtual
        returns (
            uint,
            uint,
            uint,
            uint // virtual for test&overrides
        )
    {
        uint blockTime = block.timestamp;
        uint syntheticsCurrentPID = lastSynthPID;
        uint currentCF = getGlobalCF();
        // if it has already been updated in that block, no need to compute, we can use what's stored
        if (blockTime != lastBlockTime) {
            // synth scaling
            if (currentCF < cf_severe) {
                // we need to debase

                // debase linearly
                uint ndebase = ((blockTime - lastBlockTime) * debaseValue) /
                    (deltaDebase);
                if (ndebase <= 0) {
                    // not enough time has passed to get some debase, so we reset our time reference
                    blockTime = lastBlockTime;
                } else {
                    if (syntheticsCurrentPID > ndebase) {
                        syntheticsCurrentPID = syntheticsCurrentPID - ndebase;
                        if (syntheticsCurrentPID < minimumScale)
                            syntheticsCurrentPID = minimumScale;
                    } else syntheticsCurrentPID = minimumScale;
                }
            } else {
                if (syntheticsCurrentPID < BASE_1000) {
                    // rebase linearly
                    uint nrebase = ((blockTime - lastBlockTime) * rebaseValue) /
                        (deltaRebase);

                    if (nrebase <= 0) {
                        // not enough time has passed to get some rebase, so we reset our time reference
                        blockTime = lastBlockTime;
                    } else {
                        syntheticsCurrentPID = syntheticsCurrentPID + nrebase;

                        if (syntheticsCurrentPID > BASE_1000)
                            syntheticsCurrentPID = BASE_1000;
                    }
                }
            }
        }
        // apply scale to synth burn price
        uint scaleSynthBurn = syntheticsCurrentPID; // PID
        uint criticalScaleForNumaPriceAndSellFee = BASE_1000;
        // CRITICAL_CF
        if (currentCF < cf_critical) {
            // scale such that currentCF = cf_critical
            uint criticalDebaseFactor = (currentCF * BASE_1000) / cf_critical;

            // when reaching CF_CRITICAL, we use that criticalDebaseFactor in numa price so that numa price is clipped by this lower limit
            criticalScaleForNumaPriceAndSellFee = criticalDebaseFactor;

            // we apply this multiplier on the factor for when it's used on synthetics burning price
            criticalDebaseFactor =
                (criticalDebaseFactor * BASE_1000) /
                criticalDebaseMult;

            // for burning price we take the min between PID and criticalDebaseFactor

            if (criticalDebaseFactor < scaleSynthBurn)
                scaleSynthBurn = criticalDebaseFactor;
        }
        return (
            scaleSynthBurn,
            syntheticsCurrentPID,
            criticalScaleForNumaPriceAndSellFee,
            blockTime
        );
    }

    /**
     * @dev updates sell fee and synth scaling only called from specific actions
     */
    function updateDebasings()
        public
        returns (
            uint scale,
            uint criticalScaleForNumaPriceAndSellFee,
            uint sell_fee_result
        )
    {
        (scale, criticalScaleForNumaPriceAndSellFee) = getSynthScalingUpdate();
        (sell_fee_result) = getSellFeeScalingUpdate();
    }

    /**
     * @notice lock numa supply in case of a flashloan so that numa price does not change
     */
    function lockSupplyFlashloan(bool _lock) external {
        require(isVault(msg.sender), "only vault");
        if (_lock) {
            lockedSupply = getNumaSupply();
        }
        islockedSupply = _lock;
    }

    function setDecayValues(
        uint _initialRemovedSupply,
        uint _decayPeriod,
        uint _initialRemovedSupplyLP,
        uint _decayPeriodLP,
        uint _constantRemovedSupply
    ) external onlyOwner {
        initialRemovedSupply = _initialRemovedSupply;
        initialLPRemovedSupply = _initialRemovedSupplyLP;
        constantRemovedSupply = _constantRemovedSupply;
        decayPeriod = _decayPeriod;
        decayPeriodLP = _decayPeriodLP;
        // start decay will have to be called again
        // CAREFUL: IF DECAYING, ALL VAULTS HAVE TO BE PAUSED WHEN CHANGING THESE VALUES, UNTIL startDecay IS CALLED
        isDecaying = false;
    }

    function isVault(address _addy) public view returns (bool) {
        return (vaultsList.contains(_addy));
    }

    /**
     * @dev set the INumaPrinter address (for TWAP prices)
     */
    function setPrinter(address _printerAddress) external onlyOwner {
        require(_printerAddress != address(0x0), "zero address");
        printer = INumaPrinter(_printerAddress);
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
     * @dev How many Numas from lst token amount using vault manager pricing
     */
    function tokenToNuma(
        uint _inputAmount,
        uint _refValueWei,
        uint _decimals,
        uint _synthScaling
    ) public view returns (uint256) {
        uint EthBalance = getTotalBalanceEth();
        require(EthBalance > 0, "empty vaults");
        uint256 EthValue = FullMath.mulDiv(
            _refValueWei,
            _inputAmount,
            _decimals
        );

        uint synthValueInEth = getTotalSynthValueEth();
        synthValueInEth = (synthValueInEth * _synthScaling) / BASE_1000;
        uint circulatingNuma = getNumaSupply();

        uint result;
        if (EthBalance <= synthValueInEth) {
            // extreme case use minim numa price in Eth
            result = FullMath.mulDiv(
                EthValue,
                1 ether, // 1 ether because numa has 18 decimals
                minNumaPriceEth
            );
        } else {
            uint numaPrice = FullMath.mulDiv(
                1 ether,
                EthBalance - synthValueInEth,
                circulatingNuma
            );

            if (numaPrice < minNumaPriceEth) {
                // extreme case use minim numa price in Eth
                result = FullMath.mulDiv(
                    EthValue,
                    1 ether, // 1 ether because numa has 18 decimals
                    minNumaPriceEth
                );
            } else {
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
     * @dev How many lst tokens from numa amount using vault manager pricing
     */
    function numaToToken(
        uint _inputAmount,
        uint _refValueWei,
        uint _decimals,
        uint _synthScaling
    ) public view returns (uint256) {
        uint EthBalance = getTotalBalanceEth();
        require(EthBalance > 0, "empty vaults");

        uint synthValueInEth = getTotalSynthValueEth();

        synthValueInEth = (synthValueInEth * _synthScaling) / BASE_1000;

        uint circulatingNuma = getNumaSupply();

        require(circulatingNuma > 0, "no numa in circulation");

        uint result;
        if (EthBalance <= synthValueInEth) {
            result = FullMath.mulDiv(
                FullMath.mulDiv(
                    _inputAmount,
                    minNumaPriceEth,
                    1 ether // 1 ether because numa has 18 decimals
                ),
                _decimals,
                _refValueWei
            );
        } else {
            uint numaPrice = FullMath.mulDiv(
                1 ether,
                EthBalance - synthValueInEth,
                circulatingNuma
            );

            if (numaPrice < minNumaPriceEth) {
                result = FullMath.mulDiv(
                    FullMath.mulDiv(
                        _inputAmount,
                        minNumaPriceEth,
                        1 ether // 1 ether because numa has 18 decimals
                    ),
                    _decimals,
                    _refValueWei
                );
            } else {
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

    /**
     * @dev numa to eth using vaultmanager pricing
     */

    function numaToEth(
        uint _inputAmount,
        PriceType _t
    ) public view returns (uint256) {
        (, , uint criticalScaleForNumaPriceAndSellFee, ) = getSynthScaling();
        uint result = numaToToken(
            _inputAmount,
            1 ether,
            1 ether,
            criticalScaleForNumaPriceAndSellFee
        );
        if (_t == PriceType.BuyPrice) {
            result = (result * 1 ether) / getBuyFee();
        } else if (_t == PriceType.SellPrice) {
            (uint sellfee, , ) = getSellFeeScaling();
            result = (result * sellfee) / 1 ether;
        }
        return result;
    }

    /**
     * @dev eth to numa using vaultmanager pricing
     */
    function ethToNuma(
        uint _inputAmount,
        PriceType _t
    ) external view returns (uint256) {
        (, , uint criticalScaleForNumaPriceAndSellFee, ) = getSynthScaling();
        uint result = tokenToNuma(
            _inputAmount,
            1 ether,
            1 ether,
            criticalScaleForNumaPriceAndSellFee
        );
        if (_t == PriceType.BuyPrice) {
            result = (result * getBuyFee()) / 1 ether;
        } else if (_t == PriceType.SellPrice) {
            (uint sellfee, , ) = getSellFeeScaling();
            result = (result * 1 ether) / sellfee;
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
        if (islockedSupply) return lockedSupply;

        uint circulatingNuma = numa.totalSupply();
        uint currentRemovedSupply = initialRemovedSupply;
        uint currentLPRemovedSupply = initialLPRemovedSupply;

        uint currentTime = block.timestamp;
        if (isDecaying && (currentTime > startTime)) {
            if (decayPeriod > 0) {
                if (currentTime >= startTime + decayPeriod) {
                    currentRemovedSupply = 0;
                } else {
                    uint delta = ((currentTime - startTime) *
                        initialRemovedSupply) / decayPeriod;
                    currentRemovedSupply -= (delta);
                }
            }
            if (decayPeriodLP > 0) {
                if (currentTime >= startTime + decayPeriodLP) {
                    currentLPRemovedSupply = 0;
                } else {
                    uint delta = ((currentTime - startTime) *
                        initialLPRemovedSupply) / decayPeriodLP;
                    currentLPRemovedSupply -= (delta);
                }
            }
        }

        circulatingNuma =
            circulatingNuma -
            currentRemovedSupply -
            currentLPRemovedSupply -
            constantRemovedSupply;
        return circulatingNuma;
    }

    /**
     * @dev returns vaults list
     */
    function getVaults() external view returns (address[] memory) {
        return vaultsList.values();
    }

    /**
     * @dev adds a vault to the list
     */
    function addVault(address _vault) external onlyOwner {
        require(vaultsList.length() < max_vault, "too many vaults");
        require(vaultsList.add(_vault), "already in list");
        emit AddedVault(_vault);
    }

    /**
     * @dev removes a vault from the list
     */
    function removeVault(address _vault) external onlyOwner {
        require(vaultsList.contains(_vault), "not in list");
        vaultsList.remove(_vault);
        emit RemovedVault(_vault);
    }

    /**
     * @dev sum of all vaults balances in Eth including debts
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

    /**
     * @dev update all vaults
     */
    function updateVaults() external {
        uint256 nbVaults = vaultsList.length();
        require(nbVaults <= max_vault, "too many vaults in list");

        for (uint256 i = 0; i < nbVaults; i++) {
            INumaVault(vaultsList.at(i)).updateVault();
        }
    }

    /**
     * @dev global CF considering all vaults
     */
    function getGlobalCF() public view returns (uint) {
        uint EthBalance = getTotalBalanceEth();
        uint synthValue = nuAssetManager.getTotalSynthValueEth();

        if (synthValue > 0) {
            return (EthBalance * BASE_1000) / synthValue;
        } else {
            return MAX_CF;
        }
    }

    /**
     * @dev liquid CF (liquid meaning excluding debt) considering all vaults
     */
    function getGlobalLiquidCF() public view returns (uint) {
        uint EthBalance = getTotalBalanceEthNoDebt();
        uint synthValue = nuAssetManager.getTotalSynthValueEth();

        if (synthValue > 0) {
            return (EthBalance * BASE_1000) / synthValue;
        } else {
            return MAX_CF;
        }
    }
}
