    // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;








import {vaultV1V2Deployer} from "../contracts/deployment/vaultV1V2Deployer.sol";
import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";


contract DeployV1V2Deployer is Script {

    // SEPOLIA
    address public numa_address = 0xbF4f074AAC296407ec84B8137d4fb433Ed380Ac7;
    address public lst_Address = 0x1521c67fDFDb670fa21407ebDbBda5F41591646c;

    address public uptimefeed_address = 0x0000000000000000000000000000000000000000;
    uint128 public lstHeartbeat = 100000;
    address public pricefeed = 0x0000000000000000000000000000000000000000;
    address public vaultFeeReceiver = 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69;
    address public vaultRwdReceiver = 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69;
    

    // V1
    address vaultOldAddress = 0x975fd4FFF9FEb5d1b466aF355b6209585663eBcb;
    address vaultManagerOldAddress = 0x14901B9E7c85cF21D2933442ec549325B8b7F78F;


    //forge script --chain sepolia .\scripts\MigrateVaultV1V2.sol:MigrateV1V2 --rpc-url 'SEPOLIA_RPC' --broadcast -vv --verify

    function run() external {
        vm.startBroadcast();
        vaultV1V2Deployer _vaultV1V2Deployer = new vaultV1V2Deployer( numa_address,
        lst_Address,       
        pricefeed,
        uptimefeed_address,
        lstHeartbeat,
        vaultFeeReceiver,
        vaultRwdReceiver,
        vaultOldAddress,
        vaultManagerOldAddress);
        vm.stopBroadcast();

    }
}
    
