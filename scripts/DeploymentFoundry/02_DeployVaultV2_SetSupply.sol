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
import {INumaOFT} from "../../contracts/interfaces/INumaOFT.sol";

import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";




contract DeployV2 is Script {




  

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
        console2.log("vaultManagerAddress",vaultManagerAddress);

        address vaultAddress = vm.parseJsonAddress(deployedData, ".vault");
        console2.log("vaultAddress",vaultAddress);

        // uint256 deployerPrivateKey = vm.envUint("PKEYFoundry");
        // vm.startBroadcast(deployerPrivateKey);
        vm.startBroadcast();
        // Tokens
        ERC20 rEth = ERC20(lstAddress);
        INumaOFT numa = INumaOFT(numa_address);

        vaultManager = VaultManager(vaultManagerAddress);
        vault = NumaVault(vaultAddress);
      

        vaultManager.setSellFee(sellfee);
        vaultManager.setBuyFee(buyfee);

        vault.setFee(fees,maxFeePct);
        vault.setMaxBorrow(maxBorrowVault);
        vault.setMaxLiquidationsProfit(maxLstProfitForLiquidations);
        vault.setMinBorrowAmountAllowPartialLiquidation(minBorrowAmountAllowPartialLiquidation);

        // initial supply that is removed from the vault
        // for this testnet test, LP supply will be bought
        // no initial mint 
        uint initialMint = 0;//500000 ether;
        vaultManager.setDecayValues(
            // diff / 2,
            // newPeriod,
            // diff / 2,
            // newPeriod,
            initialMint // same constant
        );


        // deployer can mint numa
        // sonic testnet: 1 sonic = 1 numa initial price
        numa.setMinter(msg.sender);
        numa.mint(msg.sender,1 ether);// could be vault or address(0), either this solution or the +1 thing

        //
        rEth.transfer(vaultAddress,1 ether);

        vm.stopBroadcast();
                
    }
}