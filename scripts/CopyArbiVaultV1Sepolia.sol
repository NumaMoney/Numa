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
//import {FakeNuma} from "../contracts/Test/mocks/FakeNuma.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import  "../contracts/Numa.sol";


import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";

// copy arbitrum v1 vault to sepolia to fully test migration
contract CopySepolia is Script {


    INuma numa;
    address uptime_feed = 0x0000000000000000000000000000000000000000;
    address price_feed = 0x0000000000000000000000000000000000000000;
    address numa_address;// = 0x2e4a312577A78786051052c28D5f1132d93c557A;
    address lstAddress = 0x1521c67fDFDb670fa21407ebDbBda5F41591646c;

    // deployer
    address feeReceiver = 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69;
    address rwdReceiver = 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69;
    address deployer = 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69;

    // arbitrum parameters to copy
    uint16 buyfee = 800;
    uint16 sellfee = 950;
    uint16 fee = 10;
    

    uint constantRemovedSupplyVM = 500000000000000000000000;
    uint startTime = 1709676055;
    uint decayPeriod = 31536000;

    // to be updated before call
    uint vaultBalance = 630785542569605001191;
    uint numaSupplyVM = 6682082258562412163649488;
    uint numaSupply = 7695731573630905300000000;
  
    //
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");




    // out
    nuAssetManagerOld public nuAssetMgr; 
    VaultOracleSingle public vaultOracle;
    VaultManagerOld public vaultManager;
    NumaVaultOld public vault;

    // forge script --chain sepolia .\scripts\CopyArbiVaultV1Sepolia.sol:CopySepolia --rpc-url 'SEPOLIA_RPC' --broadcast -vv --verify
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PKEYFoundry");
      
        // vm.deal(deployer, 1000 ether);

        vm.startBroadcast(deployerPrivateKey);

        //numa = INuma(numa_address);

        // numa = new FakeNuma(deployer, deployer, deployer); 
        // numa.mint(deployer, numaSupply);

        // Deploy the implementation contract
        address implementation = address(new NUMA());

        // Initialize data for the proxy
        bytes memory initData = abi.encodeWithSignature("initialize()");

        // Deploy the proxy pointing to the implementation
        ERC1967Proxy proxy = new ERC1967Proxy(implementation, initData);


        numa = INuma(address(proxy));
        numa.mint(deployer, numaSupply);
        numa_address = address(proxy);



        // *********************** nuAssetManager **********************************
        // nuAssetManager
        nuAssetMgr = new nuAssetManagerOld(uptime_feed);
 
        // *********************** vaultManager **********************************
        // vault manager
        vaultManager = new VaultManagerOld(address(numa), address(nuAssetMgr));


        // vault oracle
        VaultMockOracle vaultOracleDeploy = new VaultMockOracle(lstAddress);
        vaultOracle = VaultOracleSingle(address(vaultOracleDeploy));


        // vault1 rETH
        vault = new NumaVaultOld(numa_address,lstAddress,1 ether ,address(vaultOracle));

        vaultManager.addVault(address(vault));
        vault.setVaultManager(address(vaultManager));
        vault.setFeeAddress(feeReceiver, false);
        vault.setRwdAddress(rwdReceiver, false);
        
        // allow vault to mint numa
        numa.grantRole(MINTER_ROLE, address(vault));

        // first we need to match numa supply        
        uint numaSupplyNew = numa.totalSupply();

        
        uint diff = numaSupplyNew - numaSupplyVM - constantRemovedSupplyVM;
        // keep same period
        uint newPeriod = decayPeriod -
            (block.timestamp - startTime);


        console2.log("sellfee",sellfee);
        console2.log("buyfee",buyfee);
        console2.log("fee",fee);
        console2.log("diff",diff);
        console2.log("newPeriod",newPeriod);
  
        vault.setSellFee(sellfee);
        vault.setBuyFee(buyfee);
        vault.setFee(fee);



        vaultManager.setDecayValues(
            diff,
            newPeriod,
            constantRemovedSupplyVM
        );
        vaultManager.startDecay();
        ERC20 rEth = ERC20(lstAddress);
        rEth.transfer(address(vault), vaultBalance);
        // unpause
        vault.unpause();

        uint amount1 = vault.getBuyNuma(1 ether);
        uint amount2 = vault.getBuyNumaSimulateExtract(1 ether);
        uint amount3 = vault.getSellNuma(1 ether);
        uint amount4 = vault.getSellNumaSimulateExtract(1 ether);

        console2.log("numa supply",vaultManager.getNumaSupply());
        console2.log("vault balance",rEth.balanceOf(address(vault)));
        console2.log("getBuyNuma",amount1);
        console2.log("getBuyNumaSimulateExtract",amount2);
        console2.log("getSellNuma",amount3);
        console2.log("getSellNumaSimulateExtract",amount4);

        // try a buy
        rEth.approve(address(vault),1000 ether);
        vault.buy(1 ether,0,deployer);


        vm.stopBroadcast();
    }
}