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
import {NuAsset2} from "../../contracts/nuAssets/nuAsset2.sol";
import {USDToEthConverter} from "../../contracts/NumaProtocol/USDToEthConverter.sol";



import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";



contract DeployNuAsset is Script {


    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
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

    // nuasset parameters
    //  nuBTC
    string name = "nuBTC";
    string symbol = "nuBTC";
    bool isLeft = false;
    address pricefeedasset = 0x8Bcd59Cb7eEEea8e2Da3080C891609483dae53EF;// BTC/USD
    uint128 heartbeatasset = 86400;
    bool useconverter = true;

    // nuLINK
    // string name = "nuLINK";
    // string symbol = "nuLINK";
    // bool isLeft = false;
    // address pricefeedasset = 0x26e450ca14D7bF598C89f212010c691434486119;// LINK/USD
    // uint128 heartbeatasset = 86400;
    // bool useconverter = true;

    //

    address pricefeeds_usd = 0xc76dFb89fF298145b417d221B2c747d84952e01d;
    uint128 heartbeatconverter = 86400;
    

    // output
    NuAsset2 nuAsset;


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

        // read printer deployment data
        filename = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addressesPrinter_", vm.toString(block.chainid), ".json")
        );

        string memory deployedData2 = vm.readFile(filename);//"./scripts/DeploymentFoundry/deployed_addresses.json");
        
        address printerAddress = vm.parseJsonAddress(deployedData2, ".NumaPrinter");
      


        // uint256 deployerPrivateKey = vm.envUint("PKEYFoundry");
      
        // vm.startBroadcast(deployerPrivateKey);
        vm.startBroadcast();

        address deployer = msg.sender;
        console2.log("deployer",deployer);




        // deploy nuAsset
        nuAsset = new NuAsset2(name, symbol, deployer, deployer);

        // if pricefeed is in USD we need a converter to S
        address converter = address(0);


        USDToEthConverter converterUSDtoS = new USDToEthConverter(pricefeeds_usd,heartbeatconverter,UPTIME_FEED);       
        //USDToEthConverter converter = new USDToEthConverter(PRICEFEEDETHUSD_ARBI,HEART_BEAT_CUSTOM,UPTIME_FEED_ARBI);       
  
        if (useconverter)
        {
            converter = address(converterUSDtoS);
        }   

        // link nuasset
        nuAssetManager2(nuasset_manager_address).addNuAsset(
            address(nuAsset),
            pricefeedasset,
            heartbeatasset,
            isLeft,
            converter
        );


        // set printer as a NuUSD minter
        nuAsset.grantRole(MINTER_ROLE, printerAddress); // owner is NuUSD deployer



        // nuBTC = new NuAsset2("nuBTC", "NUBTC", deployer, deployer);

        // // link nuasset
        // nuAssetManager2(_nuAssetMgrAddress).addNuAsset(
        //     address(nuUSD),
        //     PRICEFEEDETHUSD_ARBI,
        //     HEART_BEAT_CUSTOM,
        //     true,
        //     address(0)
        // );
        // // set printer as a NuUSD minter
        // nuUSD.grantRole(MINTER_ROLE, _printerAddress); // owner is NuUSD deployer

        // // register nuAsset
        // nuAssetManager2(_nuAssetMgrAddress).addNuAsset(
        //     address(nuBTC),
        //     PRICEFEEDBTCETH_ARBI,
        //     HEART_BEAT,
        //     false,
        //     address(0)
        // );
        // // set printer as a NuUSD minter
        // nuBTC.grantRole(MINTER_ROLE, _printerAddress); // owner is NuUSD deployer



        // NuAsset2 nuBTC2 = new NuAsset2("nuBTC2", "nuBTC2", deployer, deployer);
        // nuAssetMgr.addNuAsset(
        //     address(nuBTC2),
        //     PRICEFEEDBTCUSD_ARBI,
        //     HEART_BEAT_CUSTOM,
        //     false,
        //     address(converter)
        // );

        // // set printer as a NuUSD minter
        // nuBTC2.grantRole(MINTER_ROLE, address(moneyPrinter)); 


        // Write the JSON to the specified path using writeJson
        string memory json = string(abi.encodePacked(
            '{"nuAsset": "', toAsciiString(address(nuAsset)), '", ',
            '"converter": "', toAsciiString( (converter)),  '"}'
        ));

        // Create the filename with the chain ID
        string memory filename2 = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addresses_",symbol, vm.toString(block.chainid), ".json")
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