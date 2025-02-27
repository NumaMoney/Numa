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


import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";



contract MigrateV1V2 is Script  {

    


    
  
    //
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");




    // out
    NumaMinter public numaMinter;
    nuAssetManager2 public nuAssetMgr; 
    VaultOracleSingle public vaultOracle;
    VaultManager public vaultManager;
    NumaVault public vault;

    //forge script --chain sepolia .\scripts\MigrateVaultV1V2.sol:MigrateV1V2 --rpc-url 'SEPOLIA_RPC' --broadcast -vv --verify

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
        uint256 debt = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".debt")));
        uint256 rwdFromDebt = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".rwdFromDebt")));



        uint256 deployerPrivateKey = vm.envUint("PKEYFoundry");



        vm.startBroadcast(deployerPrivateKey);

        // Tokens       
        ERC20 rEth = ERC20(lstAddress);

        // ****************** DEPLOY nuAssetManager ************************
        nuAssetMgr = new nuAssetManager2(uptime_feed);
        
        // ****************** DEPLOY numaMinter ************************
        numaMinter = new NumaMinter();
        numaMinter.setTokenAddress(numa_address);


        
        // ****************** DEPLOY vaultManager ************************
        vaultManager = new VaultManager(numa_address, address(nuAssetMgr));



        // ****************** DEPLOY vaultOracle ************************
        if (isTestNet)
        {
            VaultMockOracle vaultOracleDeploy = new VaultMockOracle(lstAddress);
            vaultOracle = VaultOracleSingle(address(vaultOracleDeploy));
        }
        else
        {
            vaultOracle = new VaultOracleSingle(lstAddress,price_feed,heartbeat,uptime_feed);
        }

        // ****************** DEPLOY vault ************************
        vault = new NumaVault(
            numa_address,
            lstAddress,
            1 ether,
            address(vaultOracle),
            address(numaMinter),
            debt,
            rwdFromDebt
        );

        // add vault as a numa minter
        numaMinter.addToMinters(address(vault));
        // link vault & vaultManager
        vaultManager.addVault(address(vault));
        vault.setVaultManager(address(vaultManager));
        // set fee&rwd addresses
        vault.setFeeAddress(feeReceiver, false);
        vault.setRwdAddress(rwdReceiver, false);


        // deployer needs to be numa_admin
        //INuma(numa_address).grantRole(MINTER_ROLE, address(numaMinter));


  

        // Write the JSON to the specified path using writeJson
        string memory json = string(abi.encodePacked(
            '{"Numa": "', toAsciiString(numa_address), '", ',
            '"Lst": "', toAsciiString( address(lstAddress)), '",',
            '"nuAssetManager": "', toAsciiString( address(nuAssetMgr)), '",',
            '"numaMinter": "', toAsciiString( address(numaMinter)), '",',
            '"vaultOracle": "', toAsciiString( address(vaultOracle)), '",',
            '"vaultManager": "', toAsciiString( address(vaultManager)), '",',
            '"vault": "', toAsciiString( address(vault)), '"}'
        ));

        // Create the filename with the chain ID
        string memory filename = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addresses_", vm.toString(block.chainid), ".json")
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