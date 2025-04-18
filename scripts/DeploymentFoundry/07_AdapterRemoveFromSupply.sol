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


import {NumaComptroller} from "../../contracts/lending/NumaComptroller.sol";
import {Unitroller} from "../../contracts/lending/Unitroller.sol";
import {NumaPriceOracleNew} from "../../contracts/lending/NumaPriceOracleNew.sol";

import {JumpRateModelV4} from "../../contracts/lending/JumpRateModelV4.sol";

import {JumpRateModelVariable} from "../../contracts/lending/JumpRateModelVariable.sol";

import {CNumaLst} from "../../contracts/lending/CNumaLst.sol";

import {CNumaToken} from "../../contracts/lending/CNumaToken.sol";

import {NumaPrinter} from "../../contracts/NumaProtocol/NumaPrinter.sol";
import {NumaOracle} from "../../contracts/NumaProtocol/NumaOracle.sol";
import {INumaOracle} from "../../contracts/interfaces/INumaOracle.sol";
import {USDCToEthConverter} from "../../contracts/NumaProtocol/USDCToEthConverter.sol";


import {OFTBridgedSupplyManager} from "../../contracts/layerzero/OFTBridgedSupplyManager.sol";
import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";



contract AdapterRemoveFromSupply is Script {


   


    // out
    OFTBridgedSupplyManager public bridgeSupplyManager;




    function run() external {




        string memory configData = vm.readFile("./scripts/DeploymentFoundry/config.json");
        string memory path = string(abi.encodePacked(".", vm.toString(block.chainid)));

        address numaOFTAdapter_address = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".numaOFTAdapter")));
        address numa_address = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".numa_address")));

        // current deployment config
        string memory filename = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addresses_", vm.toString(block.chainid), ".json")
        );

        string memory deployedData = vm.readFile(filename);//"./scripts/DeploymentFoundry/deployed_addresses.json");
        

        // 
        address vaultManager_address = vm.parseJsonAddress(deployedData, ".vaultManager");

        vm.startBroadcast();
        address deployer = msg.sender;
        console2.log("deployer",deployer);

        bridgeSupplyManager = new OFTBridgedSupplyManager(numaOFTAdapter_address,numa_address);
        VaultManager vaultManager = VaultManager(vaultManager_address);
        vaultManager.setOftAdapterAddress(address(bridgeSupplyManager));

        string memory json = string(abi.encodePacked(
            '{"OFTBridgedSupplyManager": "', toAsciiString(address(bridgeSupplyManager)), '", ',
            '"numaOFTAdapter": "', toAsciiString( numaOFTAdapter_address), '"}'
        ));

        // Create the filename with the chain ID
       string memory filename2 = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addressesOFT_", vm.toString(block.chainid), ".json")
        );

        //string memory path2 = "./scripts/DeploymentFoundry/deployed_addresses.json";
        vm.writeJson(json, filename2);


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