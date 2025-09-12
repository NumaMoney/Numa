// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import "../../contracts/interfaces/INuma.sol";

import "../../contracts/deployment/utils.sol";
import "@openzeppelin/contracts_5.0.2/token/ERC20/ERC20.sol";
import {nuAssetManager2} from "../../contracts/nuAssets/nuAssetManager2.sol";
import {NumaMinter} from "../../contracts/NumaProtocol/NumaMinter.sol";
import {VaultOracleSingle} from "../../contracts/NumaProtocol/VaultOracleSingle.sol";
import {VaultManager} from "../../contracts/NumaProtocol/VaultManager.sol";
import {NumaVault} from "../../contracts/NumaProtocol/NumaVault.sol";

import {nuAssetManagerOld} from "../../contracts/oldV1/nuAssetManagerOld.sol";
import {VaultManagerOld} from "../../contracts/oldV1/VaultManagerOld.sol";
import {NumaVaultOld} from "../../contracts/oldV1/NumaVaultOld.sol";

import {VaultMockOracle} from "../../contracts/Test/mocks/VaultMockOracle.sol";
import {CNumaToken} from "../../contracts/lending/CNumaToken.sol";
import {NumaPrinter} from "../../contracts/NumaProtocol/NumaPrinter.sol";
import {NumaOracle} from "../../contracts/NumaProtocol/NumaOracle.sol";
import {INumaOracle} from "../../contracts/interfaces/INumaOracle.sol";
import {USDCToEthConverter} from "../../contracts/NumaProtocol/USDCToEthConverter.sol";




import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";


// used on satellite chains using numa OFT
contract MigrateSonicVault3 is Script  {

    
    //
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");




    // out
    NumaMinter public numaMinter;
    nuAssetManager2 public nuAssetMgr; 
    VaultOracleSingle public vaultOracle;
    VaultManager public vaultManager;
    NumaVault public vault;

    //forge script --chain 421614 .\scripts\DeploymentFoundry\01_DeployVaultV2_Core.sol:DeployVaultV2 --rpc-url 'https://arbitrum-sepolia.infura.io/v3/530deb6300b14ec095b8f6bbbab6a187' --broadcast -vv --verify --sender 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69 --private-key 0xe71401816181e3dfaf484d06034b23349a5cd63b22fc4df2c10184e0b622d65b --etherscan-api-key "7QJ5HEMUC13QIS29HDZGVMXYSW17EF56VK" 
    function run() external {

        string memory configData = vm.readFile("./scripts/DeploymentFoundry/config.json");
        string memory path = string(abi.encodePacked(".", vm.toString(block.chainid)));

        bool isTestNet = vm.parseJsonBool(configData, string(abi.encodePacked(path, ".isTestNet")));

        address uptime_feed = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".uptime_feed")));
        address price_feed = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".price_feed")));
        address numa_address = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".numa_address")));
        address lstAddress = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".lstAddress")));
        uint128 heartbeat = uint128(vm.parseJsonUint(configData, string(abi.encodePacked(path, ".heartbeat"))));
        address feeReceiver = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".feeReceiver")));
        address rwdReceiver = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".rwdReceiver")));
        address pool_address = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".pool_address")));
     
        // uint256 debt = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".debt")));
        // uint256 rwdFromDebt = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".rwdFromDebt")));

        // set supply parameters
        uint16 fees = uint16(vm.parseJsonUint(configData, string(abi.encodePacked(path, ".fees"))));
        uint16 maxFeePct = uint16(vm.parseJsonUint(configData, string(abi.encodePacked(path, ".maxFeePct"))));

        uint maxBorrowVault = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".maxBorrowVault")));
        uint maxLstProfitForLiquidations = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".maxLstProfitForLiquidations")));
        uint minBorrowAmountAllowPartialLiquidation = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".minBorrowAmountAllowPartialLiquidation")));

  

        // Existing addresses
        string memory filename = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addresses_", vm.toString(block.chainid), ".json")
        );

 

        address cNumaAddy = 0x16d4b53DE6abA4B68480C7A3B6711DF25fcb12D7;
        address cRethAddy = 0xb2a43445B97cd6A179033788D763B8d0c0487E36;

  
        address newVaultAddress = 0xEd84043CBA395bd3eacEc6B378e49cd66E94941d;
        // uint256 deployerPrivateKey = vm.envUint("PKEYFoundry");
        // vm.startBroadcast(deployerPrivateKey);
        vm.startBroadcast();
      // ****************** DEPLOY vault ************************
        vault = NumaVault(newVaultAddress);


        // link lending
        CNumaToken cNuma = CNumaToken(cNumaAddy);
        CNumaToken cReth = CNumaToken(cRethAddy);
        cNuma.setVault(address(vault));       
        cReth.setVault(address(vault));
        vault.setCTokens(address(cNuma), address(cReth));
        
     

        vm.stopBroadcast();
        
        
    }


}