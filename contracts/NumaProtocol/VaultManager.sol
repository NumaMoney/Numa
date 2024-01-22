// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/INumaVault.sol";


import "../Numa.sol";
import "../interfaces/IVaultOracle.sol";
import "../interfaces/INuAssetManager.sol";

contract VaultManager is IVaultManager, Ownable 
{   
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet vaultsList;

    // decay denominator variables
    uint256 public decayingDenominator;
    uint256 public decaytimestamp;
    bool public isdecaying;

    INuAssetManager public nuAssetManager;
    NUMA public immutable numa;
    EnumerableSet.AddressSet removedSupplyAddresses;

    IVaultOracle public oracle;

    uint16 public constant DECAY_BASE_100 = 100;
    uint constant max_vault = 50;
    uint constant max_addresses = 50;

    event SetNuAssetManager(address nuAssetManager);

    constructor(address _numaAddress,uint _decayingDenominator) Ownable(msg.sender)
    {
        numa = NUMA(_numaAddress);
        decayingDenominator = _decayingDenominator;
        isdecaying = false;
    }

    /**
     * @dev Starts the decaying period
     * @notice decayingDenominator will go from initial value to 1 in 90 days
     */
    function startDecaying() external onlyOwner
    {
        isdecaying = true;
        decaytimestamp = block.timestamp;
    }

    /**
     * @dev Current decaying denominator (from initial value to 1 at the end of the period)
     * @return {uint256} current decaying denominator 
     */
    function getDecayDenominator() internal view returns (uint256)
    {
        if (isdecaying)
        {
            uint256 currenttimestamp = block.timestamp;
            uint256 delta_s = currenttimestamp - decaytimestamp;
            // should go down to 1 during 90 days
            uint256 period = 90 * 1 days;
            uint256 decay_factor_1000 = (1000*delta_s) / period;

            if (decay_factor_1000 >= 1000)
            {
                return DECAY_BASE_100;
            }
            uint256 currentDecay_1000 = decay_factor_1000 * DECAY_BASE_100 + (1000 - decay_factor_1000) * decayingDenominator;
            return currentDecay_1000/1000;
        }
        else
        {
            return DECAY_BASE_100;
        }

    }

    /**
     * @dev set the INuAssetManager address (used to compute synth value in Eth)
     */
    function setNuAssetManager(address _nuAssetManager) external onlyOwner  
    {
        require(_nuAssetManager != address(0x0),"zero address");
        nuAssetManager = INuAssetManager(_nuAssetManager);
        emit SetNuAssetManager(_nuAssetManager);
    }

    /**
     * @dev How many Numas from lst token amount
     */
    function TokenToNuma(uint _inputAmount,uint _refValueWei,uint _decimals) external view returns (uint256) 
    {
        require(address(oracle) != address(0),"oracle not set");

        // using snapshot price instead of oracle price
        //uint256 EthValue = oracle.getTokenPrice(address(lstToken),_inputAmount);
        uint256 EthValue = FullMath.mulDiv(_refValueWei, _inputAmount, _decimals); 
        uint synthValueInEth = getTotalSynthValueEth();
        uint circulatingNuma = getNumaSupply();
      
        uint EthBalance = getTotalBalanceEth();
        require(EthBalance > synthValueInEth,"vault is empty or synth value is too big");
        uint256 decaydenom = getDecayDenominator();
        uint result = FullMath.mulDiv(EthValue, DECAY_BASE_100* circulatingNuma, decaydenom*(EthBalance - synthValueInEth));

        return result;
    }

    /**
     * @dev How many lst tokens from numa amount
     */
    function NumaToToken(uint _inputAmount,uint _refValueWei,uint _decimals) external view returns (uint256) 
    {
        require(address(oracle) != address(0),"oracle not set");
        //(uint256 price,uint256 decimalPrecision,bool ethLeftSide) = oracle.getTokenPrice(address(lstToken));

       
        uint synthValueInEth = getTotalSynthValueEth();
        uint circulatingNuma = getNumaSupply();
        uint EthBalance = getTotalBalanceEth();
  
        require(EthBalance > synthValueInEth,"vault is empty or synth value is too big");
        require(circulatingNuma > 0,"no numa in circulation");
        uint result;
        uint256 decaydenom = getDecayDenominator();

        // using snaphot price
        result = FullMath.mulDiv(FullMath.mulDiv(decaydenom*_inputAmount,EthBalance - synthValueInEth, DECAY_BASE_100*circulatingNuma),_decimals,_refValueWei);
        return result;
    }

  /**
     * @dev Total synth value in Eth
     */
    function getTotalSynthValueEth() internal view returns (uint256)
    {
        require(address(nuAssetManager) != address(0),"nuAssetManager not set");
        return nuAssetManager.getTotalSynthValueEth();
    }

    /**
     * @dev total numa supply without wallet's list balances
     * @notice for another vault, either we use this function from this vault, either we need to set list in the other vault too
     */
    function getNumaSupply() public view returns (uint)
    {
        uint circulatingNuma = numa.totalSupply(); 
      
        uint256 nbWalletsToRemove = removedSupplyAddresses.length();
        require(nbWalletsToRemove < max_addresses,"too many wallets to remove from supply");
        // remove wallets balances from numa supply
        for (uint256 i = 0;i < nbWalletsToRemove;i++)
        {
            uint bal = numa.balanceOf(removedSupplyAddresses.at(i));
            circulatingNuma -= bal;
        }
        return circulatingNuma;
    }

        /**
     * @dev list of wallets whose numa balance is removed from total supply
     */
    function getRemovedWalletsList() external view returns (address[] memory) {
        return removedSupplyAddresses.values();
    }

    /**
     * @dev adds a wallet to wallets whose numa balance is removed from total supply
     */
    function addToRemovedSupply(address _address) external onlyOwner  
    {
        require (removedSupplyAddresses.length() < max_addresses,"too many wallets in list");
        require(removedSupplyAddresses.add(_address), "already in list");    
    }


    /**
     * @dev removes a wallet to wallets whose numa balance is removed from total supply
     */
    function removeFromRemovedSupply(address _address) external onlyOwner  
    {
        require(removedSupplyAddresses.contains(_address), "not in list");
        removedSupplyAddresses.remove(_address);
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
    function addVault(address _vault) external onlyOwner  
    {
        require (vaultsList.length() < max_vault,"too many vaults");
        require(vaultsList.add(_vault), "already in list");
    }

    /**
     * @dev removes a vault from total balance
     */  
    function removeVault(address _vault) external onlyOwner  
    {
        require(vaultsList.contains(_vault), "not in list");
        vaultsList.remove(_vault);
    }


    /**
     * @dev sum of all vaults balances in Eth
     */  
    function getTotalBalanceEth() public view returns (uint256)
    {
        uint result;
        uint256 nbVaults = vaultsList.length();
        require(nbVaults <= max_vault,"too many vaults in list");

        for (uint256 i = 0;i < nbVaults;i++)
        {
            result += INumaVault(vaultsList.at(i)).getEthBalance();                                                                                                                                                                                                                                                                                    
        }
        return result;
    }


}