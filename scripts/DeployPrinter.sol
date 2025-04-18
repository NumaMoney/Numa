// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import "../contracts/interfaces/INuma.sol";

import "../contracts/deployment/utils.sol";
import "@openzeppelin/contracts_5.0.2/token/ERC20/ERC20.sol";
import {nuAssetManager} from "../contracts/nuAssets/nuAssetManager.sol";
import {NumaMinter} from "../contracts/NumaProtocol/NumaMinter.sol";
import {VaultOracleSingle} from "../contracts/NumaProtocol/VaultOracleSingle.sol";
import {VaultManager} from "../contracts/NumaProtocol/VaultManager.sol";
//import {NumaVault} from "../contracts/NumaProtocol/NumaVault.sol";
import {NumaPrinter} from "../contracts/NumaProtocol/NumaPrinter.sol";
import {NumaOracle} from "../contracts/NumaProtocol/NumaOracle.sol";
import {INumaOracle} from "../contracts/interfaces/INumaOracle.sol";
import {USDCToEthConverter} from "../contracts/NumaProtocol/USDCToEthConverter.sol";







import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";


// TODO
// - test on sepolia, check transactions
// - test on local arbitrum fork, make some tests
contract DeployPrinter is Script {




    // // ARBITRUM
    // address constant VAULT_ADMIN = 0xFC4B72FD6309d2E68B595c56EAcb256D2fE9b881;
    // address constant NUMA_ADMIN = 0x7B224b19b2b26d1b329723712eC5f60C3f7877E3;

    // // input
    // address numa_address;
    // address reth_address;
    // address vault_address;
    // address vaultManager_address;
    // address minter_address;
    // address nuasset_manager_address;
    // address pool_address;
    // address usdc_address;
    // uint32 INTERVAL_SHORT;
    // uint32 INTERVAL_LONG;
    // address PRICEFEEDUSDCUSD;
    // uint128 HEART_BEAT1;
    // uint128 HEART_BEAT2;
    // address PRICEFEEDETHUSD;
    // address UPTIME_FEED;
    // uint printFee;
    // uint burnFee;
    // uint swapFee;
    // uint feePct;
    // address feeAddressPrinter;

    // SEPOLIA
    address constant VAULT_ADMIN = 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69;
    address constant NUMA_ADMIN = 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69;
    // input
    address numa_address = 0xf478F8dEDebe67cC095693A9d6778dEb3fb67FFe;
    address reth_address = 0x1521c67fDFDb670fa21407ebDbBda5F41591646c;
    //address vault_address = 0xf24a7F6ae5dA1BdBA8A24D7555Fc966f2f42f007;
    address vaultManager_address = 0xdDbFb7514499C0e6cf08582363CD1Eb963b90B77;
    address minter_address = 0x66D90DEB8f9f8e6fA8C2f2B980EF00084403C70B;
    address nuasset_manager_address = 0xa58a397A34BFCed7231023e44d95B7688b2E7A23;
    uint32 INTERVAL_SHORT = 180;
    uint32 INTERVAL_LONG = 1800;
    uint printFee = 500; //5%
    uint burnFee = 800; // 8%
    uint swapFee = 300; // 3%

    uint feePct = 5000;// 50% of fee
    address feeAddressPrinter = 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69;
   

    address PRICEFEEDUSDCUSD = 0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E;
    address PRICEFEEDETHUSD = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    address usdc_address = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    uint128 HEART_BEATUSDCUSD = 86400;
    uint128 HEART_BEATETHUSD = 3600;

    // no uptime feed on sepolia
    address UPTIME_FEED = address(0);


    address pool_address = 0x061aaa0BcBa548B10c7C7FC0d698f6ed52d5d62c;

 
    



    bool useForkedArbi = false;


    // output
    NumaPrinter printer;
    NumaOracle oracle;
    USDCToEthConverter converter;


    //forge script --chain sepolia .\scripts\MigrateVaultV1V2.sol:MigrateV1V2 --rpc-url 'SEPOLIA_RPC' --broadcast -vv --verify

    function run() external {

        uint256 deployerPrivateKey = vm.envUint("PKEYFoundry");
      
        if (useForkedArbi)
        {
            vm.startPrank(VAULT_ADMIN);
        }
        else
        {
            vm.startBroadcast(deployerPrivateKey);
        }

        address deployer = msg.sender;
        console2.log("deployer",deployer);

        //NumaVault vault = NumaVault(vault_address);


        console2.log("pool address: ", pool_address);
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

        if (useForkedArbi)
        {
            
        }
        else
        {
            vm.stopBroadcast();
        }
        
    }
}