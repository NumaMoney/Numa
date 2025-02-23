// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import "../../contracts/interfaces/INuma.sol";

import "../../contracts/deployment/utils.sol";
import "@openzeppelin/contracts_5.0.2/token/ERC20/ERC20.sol";
import {nuAssetManager} from "../../contracts/nuAssets/nuAssetManager.sol";
import {NumaMinter} from "../../contracts/NumaProtocol/NumaMinter.sol";
import {VaultOracleSingle} from "../../contracts/NumaProtocol/VaultOracleSingle.sol";
import {VaultManager} from "../../contracts/NumaProtocol/VaultManager.sol";
//import {NumaVault} from "../contracts/NumaProtocol/NumaVault.sol";
import {NumaPrinter} from "../../contracts/NumaProtocol/NumaPrinter.sol";
import {NumaOracle} from "../../contracts/NumaProtocol/NumaOracle.sol";
import {INumaOracle} from "../../contracts/interfaces/INumaOracle.sol";
import {USDCToEthConverter} from "../../contracts/NumaProtocol/USDCToEthConverter.sol";







import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";



contract DeployPrinter is Script {


    // config
    address numa_address;
    address usdc_address;
    uint32 INTERVAL_SHORT;
    uint32 INTERVAL_LONG;
    address PRICEFEEDUSDCUSD;
    address PRICEFEEDETHUSD;
    uint128 HEART_BEATUSDCUSD;
    uint128 HEART_BEATETHUSD;
    address UPTIME_FEED;
    address pool_address;
    uint printFee;
    uint burnFee;
    uint swapFee;
    uint feePct;
    address feeAddressPrinter;

    // output
    NumaPrinter printer;
    NumaOracle oracle;
    USDCToEthConverter converter;


    function run() external {


        // read config
        string memory configData = vm.readFile("./scripts/DeploymentFoundry/config.json");
        string memory path = string(abi.encodePacked(".", vm.toString(block.chainid)));

        numa_address = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".numa_address")));
        usdc_address = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".usdc_address")));
        PRICEFEEDUSDCUSD = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".PRICEFEEDUSDCUSD")));
        PRICEFEEDETHUSD = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".PRICEFEEDETHUSD")));
        UPTIME_FEED = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".uptime_feed")));
        pool_address = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".pool_address")));
        feeAddressPrinter = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".feeAddressPrinter")));

        // lending parameters
        INTERVAL_SHORT =  uint32(vm.parseJsonUint(configData, string(abi.encodePacked(path, ".INTERVAL_SHORT"))));
        INTERVAL_LONG =  uint32(vm.parseJsonUint(configData, string(abi.encodePacked(path, ".INTERVAL_LONG"))));
        HEART_BEATUSDCUSD = uint128(vm.parseJsonUint(configData, string(abi.encodePacked(path, ".HEART_BEATUSDCUSD"))));
        HEART_BEATETHUSD = uint128(vm.parseJsonUint(configData, string(abi.encodePacked(path, ".HEART_BEATETHUSD"))));
        printFee = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".printFee")));
        burnFee = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".burnFee")));
        swapFee = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".swapFee")));
        feePct = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".feePct")));
    
        // current deployment config
        string memory filename = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addresses_", vm.toString(block.chainid), ".json")
        );

        string memory deployedData = vm.readFile(filename);//"./scripts/DeploymentFoundry/deployed_addresses.json");
        
        address vaultManager_address = vm.parseJsonAddress(deployedData, ".vaultManager");
        address minter_address = vm.parseJsonAddress(deployedData, ".numaMinter");
        address nuasset_manager_address = vm.parseJsonAddress(deployedData, ".nuAssetManager");



        uint256 deployerPrivateKey = vm.envUint("PKEYFoundry");
      
        vm.startBroadcast(deployerPrivateKey);


        address deployer = msg.sender;
        console2.log("deployer",deployer);


        oracle = new NumaOracle(
            usdc_address,
            INTERVAL_SHORT,
            INTERVAL_LONG,
            deployer,      
            nuasset_manager_address
        );

        converter = new USDCToEthConverter(
            PRICEFEEDUSDCUSD,
            HEART_BEATUSDCUSD,
            PRICEFEEDETHUSD,
            HEART_BEATETHUSD,
            UPTIME_FEED
        );

        printer = new NumaPrinter(
            numa_address,     
            minter_address,
            pool_address,
            address(converter),
            INumaOracle(oracle),
            vaultManager_address
        );
        printer.setPrintAssetFeeBps(printFee);
        printer.setBurnAssetFeeBps(burnFee);
        printer.setSwapAssetFeeBps(swapFee);

        printer.setFeeAddress(payable(feeAddressPrinter), feePct); 

        // add moneyPrinter as a numa minter
        NumaMinter(minter_address).addToMinters(address(printer));

        // set printer to vaultManager
        VaultManager(vaultManager_address).setPrinter(address(printer));

        // unneeded, paused by default
        //printer.pause();

        // Write the JSON to the specified path using writeJson
        string memory json = string(abi.encodePacked(
            '{"NumaOracle": "', toAsciiString(address(oracle)), '", ',
            '"USDCToEthConverter": "', toAsciiString( address(converter)), '",',
            '"NumaPrinter": "', toAsciiString( address(printer)), '"}'
        ));

        // Create the filename with the chain ID
        string memory filename2 = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addressesPrinter_", vm.toString(block.chainid), ".json")
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