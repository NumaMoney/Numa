// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import "../../contracts/interfaces/INuma.sol";

import "../../contracts/deployment/utils.sol";
import "@openzeppelin/contracts_5.0.2/token/ERC20/ERC20.sol";
import {nuAssetManager} from "../../contracts/nuAssets/nuAssetManager.sol";
import {NumaMinter} from "../../contracts/NumaProtocol/NumaMinter.sol";
import {VaultOracleSingle} from "../../contracts/NumaProtocol/VaultOracleSingle.sol";
import {VaultManager} from "../../contracts/NumaProtocol/VaultManager.sol";
import {NumaVault} from "../../contracts/NumaProtocol/NumaVault.sol";

import {nuAssetManagerOld} from "../../contracts/oldV1/nuAssetManagerOld.sol";
import {VaultManagerOld} from "../../contracts/oldV1/VaultManagerOld.sol";
import {NumaVaultOld} from "../../contracts/oldV1/NumaVaultOld.sol";

import {VaultMockOracle} from "../../contracts/Test/mocks/VaultMockOracle.sol";


import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";



// TODO: 
// - test on sepolia
// - test on arbitrum fork
contract MigrateV1V2 is Script {

  
 
    // out
    NumaMinter public numaMinter;
    nuAssetManager public nuAssetMgr; 
    VaultOracleSingle public vaultOracle;
    VaultManager public vaultManager;
    NumaVault public vault;

    //forge script --chain sepolia .\scripts\MigrateVaultV1V2.sol:MigrateV1V2 --rpc-url 'SEPOLIA_RPC' --broadcast -vv --verify

    function run() external {

        // input config        
        string memory configData = vm.readFile("./scripts/DeploymentFoundry/config.json");
        string memory path = string(abi.encodePacked(".", vm.toString(block.chainid)));

        
        address numa_address = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".numa_address")));
        address lstAddress = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".lstAddress")));
        
        address vaultOldAddress = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".vaultOldAddress")));
        address vaultManagerOldAddress = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".vaultManagerOldAddress")));

        // current deployment config
        string memory filename = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addresses_", vm.toString(block.chainid), ".json")
        );

        string memory deployedData = vm.readFile(filename);//"./scripts/DeploymentFoundry/deployed_addresses.json");
        
        address vaultManagerAddress = vm.parseJsonAddress(deployedData, ".vaultManager");
        address vaultAddress = vm.parseJsonAddress(deployedData, ".vault");




        uint256 deployerPrivateKey = vm.envUint("PKEYFoundry");
        vm.startBroadcast(deployerPrivateKey);

        // Tokens
        
        ERC20 rEth = ERC20(lstAddress);
        vault = NumaVault(vaultAddress);
        vaultManager = VaultManager(vaultManagerAddress);

        NumaVaultOld vaultOld = NumaVaultOld(vaultOldAddress);


        // NOTE: need to be vault_admin here
        vaultOld.pause();
        vaultOld.withdrawToken(
            lstAddress,
            rEth.balanceOf(address(vaultOld)),
            address(vault)
        );



        uint amount5 = vault.lstToNuma(1 ether);
        uint amount6 = vault.numaToLst(1 ether);
   

        console2.log("numa supply",vaultManager.getNumaSupply());
        console2.log("vault balance",rEth.balanceOf(address(vault)));
        console2.log("lstToNuma",amount5);
        console2.log("numaToLst",amount6);


        // unpause
        //vault.unpause();




        vm.stopBroadcast();
        
        
    }
}