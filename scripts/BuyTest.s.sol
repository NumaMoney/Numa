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
import {VaultMockOracle} from "../contracts/Test/mocks/VaultMockOracle.sol";
import {Script} from "forge-std/Script.sol";

contract BuySepolia is Script {


    // INuma numa;
    // address uptime_feed = 0x0000000000000000000000000000000000000000;
    // address price_feed = 0x0000000000000000000000000000000000000000;
    // address numa_address = 0x2e4a312577A78786051052c28D5f1132d93c557A;
    address lstAddress = 0x1521c67fDFDb670fa21407ebDbBda5F41591646c;


    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PKEYFoundry");
        vm.startBroadcast(deployerPrivateKey);

        // Buy test  
        // NumaVault vault = NumaVault(0xe494468dA7938039B858f260B01CA268ab024C9a);
        // ERC20 lst = ERC20(lstAddress);
        // lst.approve(address(vault),1000000 ether);
        // vault.buy(1 ether,0,msg.sender);
        // vm.stopBroadcast();

        // // Leverage test
        // vm.startPrank(0xB0D3221A1844950b74C4ac7af1fF934182E2c67d);
        // CNumaToken clst = CNumaToken(0x035e59E8124B2E77B621207D2343e0d0101E0437);
        // CNumaToken cnuma = CNumaToken(0xBc5117cbe75CBB64D78aF8dA55caAd69D97D7987);
        // clst.leverageStrategy(10000000000000000000,	1000000000000000000,0xBc5117cbe75CBB64D78aF8dA55caAd69D97D7987);

    }
}