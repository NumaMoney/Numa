// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import "../contracts/interfaces/INuma.sol";

import "../contracts/deployment/utils.sol";
import "@openzeppelin/contracts_5.0.2/token/ERC20/ERC20.sol";
import {nuAssetManager} from "../contracts/nuAssets/nuAssetManager.sol";
import {NumaMinter} from "../contracts/NumaProtocol/NumaMinter.sol";
import {VaultOracleSingle} from "../contracts/NumaProtocol/VaultOracleSingle.sol";
import {VaultManager} from "../contracts/NumaProtocol/VaultManager.sol";
import {NumaVault} from "../contracts/NumaProtocol/NumaVault.sol";

import {nuAssetManagerOld} from "../contracts/oldV1/nuAssetManagerOld.sol";
import {VaultManagerOld} from "../contracts/oldV1/VaultManagerOld.sol";
import {NumaVaultOld} from "../contracts/oldV1/NumaVaultOld.sol";

import {VaultMockOracle} from "../contracts/Test/mocks/VaultMockOracle.sol";
import {FakeNuma} from "../contracts/Test/mocks/FakeNuma.sol";



import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";


// TODO
// - test on sepolia, check price, check transactions
// - test on local arbitrum fork, check price, check transactions
contract MigrateV1V2 is Script {


    INuma numa;
    // SEPOLIA VALUES
    // address uptime_feed = 0x0000000000000000000000000000000000000000;
    // address price_feed = 0x0000000000000000000000000000000000000000;
    // address numa_address = 0xf478F8dEDebe67cC095693A9d6778dEb3fb67FFe;
    // address lstAddress = 0x1521c67fDFDb670fa21407ebDbBda5F41591646c;
    // uint128 heartbeat = 100000;
    // // deployer
    // address feeReceiver = 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69;
    // address rwdReceiver = 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69;
    

    // bool isTestNet = true;
    // uint debt = 0;
    // uint rwdFromDebt = 0;

    // address vaultOldAddress = 0xEf645cd04995980BD7fC8eF96463B10adA427f2D;
    // address vaultManagerOldAddress = 0xA8daF6640eAacf9194737020623BC5600af8BE13;

    // ARBITRUM
    address constant VAULT_ADMIN = 0xFC4B72FD6309d2E68B595c56EAcb256D2fE9b881;
    address constant NUMA_ADMIN = 0x7B224b19b2b26d1b329723712eC5f60C3f7877E3;


    address uptime_feed = 0xFdB631F5EE196F0ed6FAa767959853A9F217697D;
    address lstAddress = 0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8;
    address numa_address = 0x7FB7EDe54259Cb3D4E1EaF230C7e2b1FfC951E9A;
    address price_feed = 0xF3272CAfe65b190e76caAF483db13424a3e23dD2;
    bool isTestNet = false;
    uint debt = 0;
    uint rwdFromDebt = 0;
    address vaultManagerOldAddress = 0x7Fb6e0B7e1B34F86ecfC1E37C863Dd0B9D4a0B1F;
    address vaultOldAddress = 0x78E88887d80451cB08FDc4b9046C9D01FB8d048D;

    
    uint128 heartbeat = 86400;
    address feeReceiver = 0xe5F8aA3f4000Bc6A0F07E9E3a1b9C9A3d48ed4a4;
    address rwdReceiver = 0x52fAb8465f3ce229Fd104FD8155C02990A0E1326;


    bool useForkedArbi = true;
    
    // 
    
  
    //
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");




    // out
    NumaMinter public numaMinter;
    nuAssetManager public nuAssetMgr; 
    VaultOracleSingle public vaultOracle;
    VaultManager public vaultManager;
    NumaVault public vault;

    //forge script --chain sepolia .\scripts\MigrateVaultV1V2.sol:MigrateV1V2 --rpc-url 'SEPOLIA_RPC' --broadcast -vv --verify

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PKEYFoundry");
      

        // vm.deal(deployer, 1000 ether);

        if (useForkedArbi)
        {
            vm.startPrank(VAULT_ADMIN);
        }
        else
        {
            vm.startBroadcast(deployerPrivateKey);
        }



        numa = INuma(numa_address);
        ERC20 rEth = ERC20(lstAddress);
        // nuAssetManager
        nuAssetMgr = new nuAssetManager(uptime_feed);
        
        // numaMinter
        numaMinter = new NumaMinter();
        numaMinter.setTokenAddress(address(numa));
        
        // vault manager
        vaultManager = new VaultManager(address(numa), address(nuAssetMgr));

        if (isTestNet)
        {
            VaultMockOracle vaultOracleDeploy = new VaultMockOracle(lstAddress);
            vaultOracle = VaultOracleSingle(address(vaultOracleDeploy));
        }
        else
        {
            vaultOracle = new VaultOracleSingle(lstAddress,price_feed,heartbeat,uptime_feed);
        }

        
       
        

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

        if (useForkedArbi)
        {
            vm.stopPrank();
            vm.startPrank(NUMA_ADMIN);
        }
        numa.grantRole(MINTER_ROLE, address(numaMinter));
        vm.startPrank(VAULT_ADMIN);
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

        
        vaultOld.withdrawToken(
            lstAddress,
            rEth.balanceOf(address(vaultOld)),
            address(vault)
        );
        //vm.prank(VAULT_ADMIN);
        // add pause too?

        // set buy/sell fees to match old price
        vaultManager.setSellFee((uint(vaultOld.sell_fee()) * 1 ether) / 1000);
        vaultManager.setBuyFee((uint(vaultOld.buy_fee()) * 1 ether) / 1000);

        // first we need to match numa supply
        uint numaSupplyOld = vaultManagerOld.getNumaSupply();
        uint numaSupplyNew = vaultManager.getNumaSupply();
      

        uint diff = numaSupplyNew -
            numaSupplyOld -
            vaultManagerOld.constantRemovedSupply();

        // keep same period
        uint newPeriod = vaultManagerOld.decayPeriod() -
            (block.timestamp - vaultManagerOld.startTime());

        vaultManager.setDecayValues(
            diff / 2,
            newPeriod,
            diff / 2,
            newPeriod,
            vaultManagerOld.constantRemovedSupply() // same constant
        );
        vaultManager.startDecay();

        // unpause
        vault.unpause();

        uint amount5 = vault.lstToNuma(1 ether);
        uint amount6 = vault.numaToLst(1 ether);
   

        console2.log("numa supply",vaultManager.getNumaSupply());
        console2.log("vault balance",rEth.balanceOf(address(vault)));
        console2.log("lstToNuma",amount5);
        console2.log("numaToLst",amount6);


        if (useForkedArbi)
        {
            
        }
        else
        {
            vm.stopBroadcast();
        }
        
    }
}