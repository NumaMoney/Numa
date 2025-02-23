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



contract MigrateV1V2 is Script {

    bool isTestNet = true;
    INuma numa;




    // SEPOLIA VALUES
    address uptime_feed = 0x0000000000000000000000000000000000000000;
    address price_feed = 0x0000000000000000000000000000000000000000;
    address numa_address = 0xf478F8dEDebe67cC095693A9d6778dEb3fb67FFe;
    address lstAddress = 0x1521c67fDFDb670fa21407ebDbBda5F41591646c;
    uint128 heartbeat = 100000;
    // deployer
    address feeReceiver = 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69;
    address rwdReceiver = 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69;
    

  
    uint debt = 0;
    uint rwdFromDebt = 0;

 

    // ARBITRUM
    // address constant VAULT_ADMIN = 0xFC4B72FD6309d2E68B595c56EAcb256D2fE9b881;
    // address constant NUMA_ADMIN = 0x7B224b19b2b26d1b329723712eC5f60C3f7877E3;


    // address uptime_feed = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;
    // address lstAddress = 0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8;
    // address numa_address = 0x7FB7EDe54259Cb3D4E1EaF230C7e2b1FfC951E9A;
    // address price_feed = 0xF3272CAfe65b190e76caAF483db13424a3e23dD2;
    // bool isTestNet = false;
    // uint debt = 0;
    // uint rwdFromDebt = 0;
    // address vaultManagerOldAddress = 0x7Fb6e0B7e1B34F86ecfC1E37C863Dd0B9D4a0B1F;
    // address vaultOldAddress = 0x78E88887d80451cB08FDc4b9046C9D01FB8d048D;

    
    // uint128 heartbeat = 86400;
    // address feeReceiver = 0xe5F8aA3f4000Bc6A0F07E9E3a1b9C9A3d48ed4a4;
    // address rwdReceiver = 0x52fAb8465f3ce229Fd104FD8155C02990A0E1326;


    // bool useForkedArbi = true;
    
    // 
    
  
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
        uint256 deployerPrivateKey = vm.envUint("PKEYFoundry");
        vm.startBroadcast(deployerPrivateKey);

        numa = INuma(numa_address);
        numaMinter = NumaMinter(0x72643674D8898D29f13A43f2c0C89E946f948739);
        // deployer needs to be numa_admin
        numa.grantRole(MINTER_ROLE, address(numaMinter));




        vm.stopBroadcast();
        
        
    }
}