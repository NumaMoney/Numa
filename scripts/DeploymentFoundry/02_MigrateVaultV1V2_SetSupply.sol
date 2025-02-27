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

        uint buyfee = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".buy_fee")));
        uint sellfee = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".sell_fee")));
        uint16 fees = uint16(vm.parseJsonUint(configData, string(abi.encodePacked(path, ".fees"))));
        uint16 maxFeePct = uint16(vm.parseJsonUint(configData, string(abi.encodePacked(path, ".maxFeePct"))));

        uint maxBorrowVault = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".maxBorrowVault")));
        uint maxLstProfitForLiquidations = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".maxLstProfitForLiquidations")));
        uint minBorrowAmountAllowPartialLiquidation = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".minBorrowAmountAllowPartialLiquidation")));









        // current deployment config
        // Create the filename with the chain ID
        string memory filename = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addresses_", vm.toString(block.chainid), ".json")
        );

        string memory deployedData = vm.readFile(filename);//"./scripts/DeploymentFoundry/deployed_addresses.json");
        address vaultManagerAddress = vm.parseJsonAddress(deployedData, ".vaultManager");





        uint256 deployerPrivateKey = vm.envUint("PKEYFoundry");
        vm.startBroadcast(deployerPrivateKey);

        // Tokens
        ERC20 rEth = ERC20(lstAddress);

        vaultManager = VaultManager(vaultManagerAddress);
        NumaVaultOld vaultOld = NumaVaultOld(vaultOldAddress);
        VaultManagerOld vaultManagerOld = VaultManagerOld(vaultManagerOldAddress);
       

        uint amount1 = vaultOld.getBuyNuma(1 ether);
        uint amount2 = vaultOld.getBuyNumaSimulateExtract(1 ether);
        uint amount3 = vaultOld.getSellNuma(1 ether);
        uint amount4 = vaultOld.getSellNumaSimulateExtract(1 ether);

        console2.log("numa supply",vaultManagerOld.getNumaSupply());
        console2.log("vault balance",rEth.balanceOf(address(vaultOld)));
        console2.log("getBuyNuma",amount1);
        console2.log("getBuyNumaSimulateExtract",amount2);
        console2.log("getSellNuma",amount3);
        console2.log("getSellNumaSimulateExtract",amount4);
        console2.log("***********************************");


        // set buy/sell fees to match old price
        // vaultManager.setSellFee((uint(vaultOld.sell_fee()) * 1 ether) / 1000);
        // vaultManager.setBuyFee((uint(vaultOld.buy_fee()) * 1 ether) / 1000);

        vaultManager.setSellFee(sellfee);
        vaultManager.setBuyFee(buyfee);

        vault.setFee(fees,maxFeePct);
        vault.setMaxBorrow(maxBorrowVault);
        vault.setMaxLiquidationsProfit(maxLstProfitForLiquidations);
        vault.setMinBorrowAmountAllowPartialLiquidation(minBorrowAmountAllowPartialLiquidation);



        // // first we need to match numa supply
        // uint numaSupplyOld = vaultManagerOld.getNumaSupply();
        // uint numaSupplyNew = vaultManager.getNumaSupply();
      

        // uint diff = numaSupplyNew -
        //     numaSupplyOld -
        //     vaultManagerOld.constantRemovedSupply();

        // // keep same period
        // uint newPeriod = vaultManagerOld.decayPeriod() -
        //     (block.timestamp - vaultManagerOld.startTime());

        vaultManager.setDecayValues(
            // diff / 2,
            // newPeriod,
            // diff / 2,
            // newPeriod,
            vaultManagerOld.constantRemovedSupply() // same constant
        );
        //vaultManager.startDecay();

        vm.stopBroadcast();
                
    }
}