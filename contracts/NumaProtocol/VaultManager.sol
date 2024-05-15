// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/INumaVault.sol";

import "../Numa.sol";

import "../interfaces/INuAssetManager.sol";


contract VaultManager is IVaultManager, Ownable2Step {

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet vaultsList;

    INuAssetManager public nuAssetManager;
    NUMA public immutable numa;
  

    uint public initialRemovedSupply;
    uint public constantRemovedSupply;
  
    bool public islockedSupply;
    uint public lockedSupply;

    uint public decayPeriod;
    uint public startTime;
    bool public isDecaying;
   

    uint constant max_vault = 50;
    uint16 public constant BASE_1000 = 1000;
    uint16 public constant MAX_CF = 10000;

    uint minNumaPriceEth = 0.000001 ether;
    // 
    event SetNuAssetManager(address nuAssetManager);
    event RemovedVault(address);
    event AddedVault(address);
    event SetMinimumNumaPriceEth(uint _minimumPriceEth);




    constructor(
        address _numaAddress,
        address _nuAssetManagerAddress     
    ) Ownable(msg.sender) {
        numa = NUMA(_numaAddress);       
        nuAssetManager = INuAssetManager(_nuAssetManagerAddress);
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

    function setDecayValues(uint _initialRemovedSupply, uint _decayPeriod,uint _constantRemovedSupply) external onlyOwner
    {
        initialRemovedSupply = _initialRemovedSupply;
        constantRemovedSupply = _constantRemovedSupply;
        decayPeriod = _decayPeriod;
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
        uint _decimals
    ) external view returns (uint256) {
        uint256 EthValue = FullMath.mulDiv(
            _refValueWei,
            _inputAmount,
            _decimals
        );
        uint synthValueInEth = getTotalSynthValueEth();
        uint circulatingNuma = getNumaSupply();

        uint EthBalance = getTotalBalanceEth();

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
        uint _decimals
    ) external view returns (uint256) {
        uint synthValueInEth = getTotalSynthValueEth();
        uint circulatingNuma = getNumaSupply();
        uint EthBalance = getTotalBalanceEth();

 
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
        uint synthValueInEth = getTotalSynthValueEth();
        uint circulatingNuma = getNumaSupply();
        uint EthBalance = getTotalBalanceEth();


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
        uint synthValueInEth = getTotalSynthValueEth();
        uint circulatingNuma = getNumaSupply();
        uint EthBalance = getTotalBalanceEth();

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

        uint currentTime = block.timestamp;
        if (isDecaying && (currentTime > startTime) && (decayPeriod > 0))
        {
            
            uint delta = ((currentTime - startTime) * initialRemovedSupply)/decayPeriod;
            if (delta >= (initialRemovedSupply))
            {
                currentRemovedSupply = 0;
            }
            else {
                currentRemovedSupply -= (delta);                
            }

        }


        circulatingNuma = circulatingNuma - currentRemovedSupply - constantRemovedSupply;

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

    function getGlobalCF() external view returns (uint)
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

    function getGlobalCFWithoutDebt() external view returns (uint)
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
