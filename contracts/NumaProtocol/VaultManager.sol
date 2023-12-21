// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/INumaVault.sol";

import "hardhat/console.sol";

contract vaultManager is IVaultManager, Ownable 
{   
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet vaultsList;

    uint constant max_vault = 50;

    constructor() Ownable(msg.sender)
    {

    }
    
    function getVaults() external view returns (address[] memory) {
        return vaultsList.values();
    }

    function addVault(address _vault) external onlyOwner  
    {
        require (vaultsList.length() < max_vault,"too many vaults");
        require(vaultsList.add(_vault), "already in list");
    }

    function removeVault(address _vault) external onlyOwner  
    {
        require(vaultsList.contains(_vault), "not in list");
        vaultsList.remove(_vault);
    }


    function getTotalBalanceEth() external view returns (uint256)
    {
        uint result;
        uint256 nbVaults = vaultsList.length();
        require(nbVaults <= max_vault,"too many vaults in list");
        console.log("nb vaults");
        console.logUint(nbVaults);
        for (uint256 i = 0;i < nbVaults;i++)
        {
            result += INumaVault(vaultsList.at(i)).getEthBalance();
            console.log("adding vault value");
            console.logUint(result);                                                                                                                                                                                                                                                                                      
        }
        return result;
    }
}