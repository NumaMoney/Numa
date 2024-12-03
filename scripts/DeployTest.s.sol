// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import "../contracts/interfaces/INuma.sol";

import "../contracts/deployment/utils.sol";

import {nuAssetManager} from "../contracts/nuAssets/nuAssetManager.sol";
import {NumaMinter} from "../contracts/NumaProtocol/NumaMinter.sol";
import {VaultOracleSingle} from "../contracts/NumaProtocol/VaultOracleSingle.sol";
import {VaultManager} from "../contracts/NumaProtocol/VaultManager.sol";
import {NumaVault} from "../contracts/NumaProtocol/NumaVault.sol";
import {VaultMockOracle} from "../contracts/Test/mocks/VaultMockOracle.sol";
import {Script} from "forge-std/Script.sol";

contract DeploySepolia is Script {


    INuma numa;
    address uptime_feed = 0x0000000000000000000000000000000000000000;
    address price_feed = 0x0000000000000000000000000000000000000000;
    address numa_address = 0x2e4a312577A78786051052c28D5f1132d93c557A;
    address lstAddress = 0x1521c67fDFDb670fa21407ebDbBda5F41591646c;
    uint debt = 0;
    uint rwdFromDebt = 0;
    // deployer
    address feeReceiver = 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69;
    address rwdReceiver = 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69;


    //
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");


    // out
    nuAssetManager public nuAssetMgr;
    NumaMinter public numaMinter;
    VaultOracleSingle public vaultOracle;
    VaultManager public vaultManager;
    NumaVault public vault;


    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PKEYFoundry");
        vm.startBroadcast(deployerPrivateKey);

        numa = INuma(numa_address);
    
        // nuAssetManager
        nuAssetMgr = new nuAssetManager(uptime_feed);
        
        // numaMinter
        numaMinter = new NumaMinter();
        numaMinter.setTokenAddress(address(numa));
        
        // vault manager
        vaultManager = new VaultManager(address(numa), address(nuAssetMgr));

        
        vaultOracle = VaultOracleSingle(address(vaultOracleDeploy));
            // vo = new VaultOracleSingle(
            //     _parameters._lst,
            //     _parameters._pricefeed,
            //     _parameters._heartbeat,
            //     _parameters._uptimefeed
            // );
        

        vault = new NumaVault(
            address(numa),
            lstAddress,
            1 ether,
            address(vaultOracle),
            address(numaMinter),
            debt,
            rwdFromDebt
        );
        // add vault as a numa minter
        numaMinter.addToMinters(address(vault));
        vaultManager.addVault(address(vault));
        vault.setVaultManager(address(vaultManager));
        vault.setFeeAddress(feeReceiver, false);
        vault.setRwdAddress(rwdReceiver, false);


        numa.grantRole(MINTER_ROLE, address(numaMinter));
        vm.stopBroadcast();
    }
}