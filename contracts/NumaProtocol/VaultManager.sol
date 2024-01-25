// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/INumaVault.sol";



contract VaultManager is IVaultManager, Ownable2Step 
{   
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet vaultsList;

    uint constant max_vault = 50;

    event AddedVault(address _vaultAddress);
    event RemovedVault(address _vaultAddress);

    constructor() Ownable(msg.sender)
    {

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
        emit AddedVault(_vault);
    }

    /**
     * @dev removes a vault from total balance
     */  
    function removeVault(address _vault) external onlyOwner  
    {
        require(vaultsList.contains(_vault), "not in list");
        vaultsList.remove(_vault);
        emit RemovedVault(_vault);
    }


    /**
     * @dev sum of all vaults balances in Eth
     */  
    function getTotalBalanceEth() external view returns (uint256)
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