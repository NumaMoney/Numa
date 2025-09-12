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
import {NumaPrinter} from "../../contracts/NumaProtocol/NumaPrinter.sol";

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

        address numa_address = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".numa_address")));
        address lstAddress = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".lstAddress")));
  
        address nuAssetManagerAddress = 0xF9832B3D082FBF45Ec737E2759AFf0A16Fb18bbf;
        address oldVaultManagerAddress = 0xf8021C37b20a0C5BaD67b67Cc79Dd98e7eF82f6B;

        address newVaultAddress = 0xEd84043CBA395bd3eacEc6B378e49cd66E94941d;
        address newPrinterAddress = 0xDBb8d14c5809D9346b2a85aeF919E53d4a246E03;


        vm.startBroadcast();
        // Tokens       
        ERC20 rEth = ERC20(lstAddress);

        // ****************** DEPLOY nuAssetManager ************************
        nuAssetMgr = nuAssetManager2(nuAssetManagerAddress);
        
 

        // ****************** DEPLOY vaultManager ************************
        vaultManager = new VaultManager(numa_address, address(nuAssetMgr));



 

        // ****************** DEPLOY vault ************************
        vault = NumaVault(newVaultAddress);
        VaultManager oldVM = VaultManager(oldVaultManagerAddress);
  
        // link vault & vaultManager
        vaultManager.addVault(address(vault));
        vault.setVaultManager(address(vaultManager));
       
        // unlink previous vaultmanager
        oldVM.removeVault(address(vault));

        // THE REST
        //vaultManager.setSellFee(0.95 ether);// no need it's default value
        //vaultManager.setBuyFee(0.95 ether);// no need it's default value

   
 
        //

        // set printer to vaultManager
        NumaPrinter printer = NumaPrinter(newPrinterAddress);
        vaultManager.setPrinter(newPrinterAddress);
        printer.setVaultManager(address(vaultManager));


        // report modified parameter
        vaultManager.setBuyFeeParameters(
            6000000000000000
            , 20
            , 3000000000000000
            , 100
            , 10
            , 16600000000000000 
            , 100000000000000000
            , 900
            , 60);
        vaultManager.setConstantRemovedSupply(300000000000000000000000);
                                              

        // Write the JSON to the specified path using writeJson
        string memory json = string(abi.encodePacked(
            '{"Numa": "', toAsciiString(numa_address), '", ',
            '"vaultManager": "', toAsciiString( address(vaultManager)), '"}'
        ));

        // Create the filename with the chain ID
        string memory filename = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addresses_migrated_vaultManager", vm.toString(block.chainid), ".json")
        );

        //string memory path2 = "./scripts/DeploymentFoundry/deployed_addresses.json";
        vm.writeJson(json, filename);

       


        vm.stopBroadcast();
        
        
    }

    function toAsciiString(address addr) internal pure returns (string memory) {
        bytes memory s = new bytes(42);
        s[0] = "0";
        s[1] = "x";
        for (uint i = 0; i < 20; i++) {
            uint8 b = uint8(uint160(addr) / (2**(8 * (19 - i))));
            s[2 + i * 2] = _char(b / 16);
            s[3 + i * 2] = _char(b % 16);
        }
        return string(s);
    }

    function _char(uint8 b) private pure returns (bytes1) {
        return b < 10 ? bytes1(b + 48) : bytes1(b + 87);
    }
}