// TODO

// a chaque fois:
//  - match de prix
//  - buy/sells ok et même qtité
//  - buy ancien KO
// TESTS
// - test migration from old to current without lending/without printing
// - test migration from old to current with lending/with printing
// - test current without lending/printing, setup lending/printing
// - test current with/without lending/printing to new one current
//  ** with lending done and debt --> transfer test that lending works with new vault
//  **

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/console2.sol";
import {Setup} from "./utils/Setup_ArbitrumFork.sol";
import "../lending/ExponentialNoError.sol";
import "../interfaces/IVaultManager.sol";
import {nuAssetManager} from "./../nuAssets/nuAssetManager.sol";
import {NumaMinter} from "./../NumaProtocol/NumaMinter.sol";
import {VaultOracleSingle} from "./../NumaProtocol/VaultOracleSingle.sol";
import {VaultManager} from "./../NumaProtocol/VaultManager.sol";
import {NumaVault} from "./../NumaProtocol/NumaVault.sol";
import {INumaOracle} from "./../interfaces/INumaOracle.sol";
import {NumaOracle} from "./../NumaProtocol/NumaOracle.sol";
import {NumaPrinter} from "./../NumaProtocol/NumaPrinter.sol";
import "./../interfaces/INumaTokenToEthConverter.sol";
import "./../NumaProtocol/USDCToEthConverter.sol";
import "./../lending/NumaLeverageVaultSwap.sol";
contract VaultMigrationTest is Setup, ExponentialNoError {
    uint numaNominalPrice;
    uint numaBuyPrice;
    uint numaSellPrice;
    uint rEthRefPrice;
    // uint buyResult;
    // uint sellResult;

    //
    nuAssetManager nuAssetMgr2;
    NumaMinter numaMinter2;
    VaultOracleSingle vaultOracle2;
    VaultManager vaultManager2;
    NumaVault vault2;

    INumaOracle numaOracle2;
    NumaPrinter moneyPrinter2;
    INumaTokenToEthConverter usdcEthConverter2;

    function setUp() public virtual override {
        console2.log("VAULT TEST");
        
        super.setUp();

        // extracting rewards so that reth ref price will match
        // not mandatory for official migration, these "lost" rewards will back numa price
        vm.stopPrank();
        vm.startPrank(VAULT_ADMIN);
        vaultOld.extractRewards();
        vm.stopPrank();
    }
    function test_CheckSetup() public {
        deal({token: address(rEth), to: deployer, give: 1000 ether});
        vm.startPrank(deployer);
        rEth.approve(address(vaultOld), 10 ether);

        uint buyResult = vaultOld.buy(10 ether, 0, deployer);
        console2.log("bought numa: ", buyResult);
        numa.approve(address(vaultOld), buyResult);
        uint sellResult = vaultOld.sell(buyResult / 2, 0, deployer);
        console2.log("sold numa: ", sellResult);
    }

    function buyVault(
        uint _amountREth,
        INumaVault _vault
    ) public returns (uint buyResult, uint sellResult) {
        vm.stopPrank();
        vm.startPrank(deployer);
        deal({token: address(rEth), to: deployer, give: 1000 ether});
        rEth.approve(address(_vault), _amountREth);
        buyResult = _vault.buy(_amountREth, 0, deployer);
        numa.approve(address(_vault), buyResult);
        sellResult = _vault.sell(buyResult / 2, 0, deployer);
    }

    function deploy_NumaV2() public {
        numaNominalPrice = vaultManagerOld.numaToToken(
            1 ether,
            1 ether,
            1 ether
        );
        console2.log("numaNominalPrice", numaNominalPrice);
        numaBuyPrice = (numaNominalPrice * 1000) / vaultOld.buy_fee();
        console2.log("numaBuyPrice", numaBuyPrice);
        numaSellPrice = (numaNominalPrice * vaultOld.sell_fee()) / 1000;
        console2.log("numaSellPrice", numaSellPrice);
        rEthRefPrice = vaultOld.last_lsttokenvalueWei();
        console2.log("rEthRefPrice", rEthRefPrice);

        // deploy new vault V2
        vm.startPrank(deployer);
        address feereceiver = deployer;
        address rwdreceiver = deployer;
        (
            nuAssetMgr,
            numaMinter,
            vaultManager,
            vaultOracle,
            vault
        ) = _setupVaultAndAssetManager(
            402 * 86400,
            feereceiver,
            rwdreceiver,
            numa,
            0,
            0,
            address(0),
            address(0)
        );
        vm.startPrank(numa_admin);
        numa.grantRole(MINTER_ROLE, address(numaMinter));
        vm.stopPrank();

        // transfer rETh
        vm.startPrank(VAULT_ADMIN);
        vaultOld.withdrawToken(
            address(rEth),
            rEth.balanceOf(address(vaultOld)),
            address(vault)
        );
        vm.stopPrank();
        rEth.approve(address(vaultOld), 1000 ether);
        vm.expectRevert();
        uint buyAmount = vaultOld.buy(10 ether, 0, deployer);
        vm.expectRevert();
        buyAmount = vault.buy(10 ether, 0, deployer);

        // unpause
        vm.startPrank(deployer);
        // set buy/sell fees to match old price
        // console2.log(vaultOld.sell_fee());
        // console2.log((uint(vaultOld.sell_fee()) * 1 ether) / 1000);
        vaultManager.setSellFee((uint(vaultOld.sell_fee()) * 1 ether) / 1000);
        vaultManager.setBuyFee((uint(vaultOld.buy_fee()) * 1 ether) / 1000);

        // first we need to match numa supply
        uint numaSupplyOld = vaultManagerOld.getNumaSupply();
        uint numaSupplyNew = vaultManager.getNumaSupply();
        //console2.log(numaSupplyNew);

        uint diff = numaSupplyNew -
            numaSupplyOld -
            vaultManagerOld.constantRemovedSupply();
        // 29/10 diff in supply: 500 000 constant + 600 000 currently decaying
        // will put the decay half in LP, half in other --> 300 000
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
    }
    function deploy_NumaV2_2() public {
        // deploy new vault V2
        vm.startPrank(deployer);
        address feereceiver = deployer;
        address rwdreceiver = deployer;
        // redeploying nuAssetManager, minter, vaultOracle

        (
            nuAssetMgr2,
            numaMinter2,
            vaultManager2,
            vaultOracle2,
            vault2
        ) = _setupVaultAndAssetManager(
            402 * 86400,
            feereceiver,
            rwdreceiver,
            numa,
            0,
            0,
            address(0),
            address(0)
        );
        
        vm.startPrank(numa_admin);
        numa.grantRole(MINTER_ROLE, address(numaMinter2));
        vm.stopPrank();

       vm.startPrank(deployer);
        // transfer rETh
        vault.withdrawToken(
            address(rEth),
            rEth.balanceOf(address(vault)),
            address(vault2)
        );
        
        rEth.approve(address(vault), 1000 ether);
        rEth.approve(address(vault2), 1000 ether);
        vm.expectRevert();
        uint buyAmount = vault.buy(10 ether, 0, deployer);
        vm.expectRevert();
        buyAmount = vault2.buy(10 ether, 0, deployer);

        // unpause
        vm.startPrank(deployer);
        // set buy/sell fees to match old price

        vaultManager2.setSellFee(vaultManager.getSellFeeOriginal());
        vaultManager2.setBuyFee(vaultManager.getBuyFee());

        // first we need to match numa supply
        uint numaSupplyOld = vaultManager.getNumaSupply();
        uint numaSupplyNew = vaultManager2.getNumaSupply();

        uint diff = numaSupplyNew -
            numaSupplyOld -
            vaultManager.constantRemovedSupply();

        // keep same period
        uint newPeriod = vaultManager.decayPeriod() -
            (block.timestamp - vaultManager.startTime());

        vaultManager2.setDecayValues(
            diff / 2,
            newPeriod,
            diff / 2,
            newPeriod,
            vaultManager.constantRemovedSupply() // same constant
        );
        vaultManager2.startDecay();

        // check numa supply
        numaSupplyOld = vaultManager.getNumaSupply();
        numaSupplyNew = vaultManager2.getNumaSupply();
        assertEq(numaSupplyOld, numaSupplyNew, "numa supply ko");
      
    }

    function test_MigrateV1V2_Price() public {
        deploy_NumaV2();
        uint numaSupplyOld = vaultManagerOld.getNumaSupply();
        uint numaSupplyNew = vaultManager.getNumaSupply();
        console2.log("numa supply", numaSupplyNew);

        assertApproxEqAbs(numaSupplyNew, numaSupplyOld, 100);

        // check prices now that numa supply matches
        uint numaNominalPrice2 = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.NoFeePrice
        );
        console2.log("numaNominalPrice2", numaNominalPrice2);
        uint numaBuyPrice2 = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.BuyPrice
        );
        console2.log("numaBuyPrice2", numaBuyPrice2);
        uint numaSellPrice2 = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.SellPrice
        );
        console2.log("numaSellPrice2", numaSellPrice2);

        // check reference price
        uint rEthRefPrice2 = vault.last_lsttokenvalueWei();
        console2.log("rEthRefPrice2", rEthRefPrice2);

        assertEq(rEthRefPrice2, rEthRefPrice);
        assertEq(numaNominalPrice2, numaNominalPrice);
        assertEq(numaBuyPrice2, numaBuyPrice);
        assertEq(numaSellPrice2, numaSellPrice);

        // checking numa supply after some decay
        vm.warp(block.timestamp + 66 days);
        numaSupplyOld = vaultManagerOld.getNumaSupply();
        numaSupplyNew = vaultManager.getNumaSupply();
        assertApproxEqAbs(numaSupplyNew, numaSupplyOld, 100);
        console2.log("numa supply after 66 days", numaSupplyNew);

        vm.warp(block.timestamp + 3650 days);
        numaSupplyOld = vaultManagerOld.getNumaSupply();
        numaSupplyNew = vaultManager.getNumaSupply();
        assertApproxEqAbs(numaSupplyNew, numaSupplyOld, 100);
        console2.log("numa supply after 3650 days", numaSupplyNew);

        // checking that it stopped decaying
        vm.warp(block.timestamp + 3650 days);
        uint numaSupplyOldLast = vaultManagerOld.getNumaSupply();
        uint numaSupplyNewLast = vaultManager.getNumaSupply();
        assertApproxEqAbs(numaSupplyNewLast, numaSupplyOldLast, 100);
        assertEq(numaSupplyOldLast, numaSupplyOld);
        assertEq(numaSupplyNewLast, numaSupplyNew);
    }
    function test_MigrateV1V2_buysell() public {
        uint rethAmount = 1 ether;
        (uint buyResult, uint sellResult) = buyVault(
            rethAmount,
            INumaVault(address(vaultOld))
        );
        deploy_NumaV2();
        (uint buyAmount2, uint sellResult2) = buyVault(
            rethAmount,
            INumaVault(address(vault))
        );

        // 3 numa diff tolerated as two consecutive buys cannot have the same price (due to fees)
        assertApproxEqAbs(buyAmount2, buyResult, 3 ether, "buy not match");
        assertApproxEqAbs(
            sellResult2,
            sellResult,
            0.001 ether,
            "sell not match"
        );
    }

    function test_MigrateV2V2() public {
        uint rethAmount = 0.1 ether;
        // DEPLOY V2 1ST TIME
        deploy_NumaV2();
        // deploy printer for migration test
        // setup pool
        // deployer needs some numa and usdc to create the pool
        vm.stopPrank();
        vm.prank(0x03d283990Dcc7b6Ec59C442a0F7ff4B902A88769);
        numa.transfer(deployer, 500000 ether);
        deal({token: address(usdc), to: deployer, give: 1000000 ether});
        vm.startPrank(deployer);
        _setupPool_Numa_Usdc();
        (numaOracle, usdcEthConverter, moneyPrinter) = _setupPrinter(
            address(nuAssetMgr),
            address(numaMinter),
            address(vaultManager)
        );
        _createNuAssets();
        _linkNuAssets(address(nuAssetMgr), address(moneyPrinter));
        moneyPrinter.unpause();
        // deploy lending protocol for migration test
        _setupLending(vault);

        // USE
        // use printer, change CF, use lending, leverage, borrow from vault
        (uint buyResult, uint sellResult) = buyVault(
            rethAmount,
            INumaVault(address(vault))
        );

        // ref prices
        numaNominalPrice = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.NoFeePrice
        );
        numaBuyPrice = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.BuyPrice
        );
        numaSellPrice = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.SellPrice
        );
        rEthRefPrice = vault.last_lsttokenvalueWei();

       
        // *** V2_2 ***
        // pause printer
        moneyPrinter.pause();
        //pause lending
        // TODO

        deploy_NumaV2_2();
      
        // 1. Check prices
        uint numaSupplyOld = vaultManager.getNumaSupply();
        uint numaSupplyNew = vaultManager2.getNumaSupply();
        console2.log("numa supply", numaSupplyNew);

        assertApproxEqAbs(numaSupplyNew, numaSupplyOld, 100);

        // check prices now that numa supply matches
        uint numaNominalPrice2 = vaultManager2.numaToEth(
            1 ether,
            IVaultManager.PriceType.NoFeePrice
        );
        uint numaBuyPrice2 = vaultManager2.numaToEth(
            1 ether,
            IVaultManager.PriceType.BuyPrice
        );
        uint numaSellPrice2 = vaultManager2.numaToEth(
            1 ether,
            IVaultManager.PriceType.SellPrice
        );
        uint rEthRefPrice2 = vault2.last_lsttokenvalueWei();
        assertEq(rEthRefPrice2, rEthRefPrice);
        assertEq(numaNominalPrice2, numaNominalPrice);
        assertEq(numaBuyPrice2, numaBuyPrice);
        assertEq(numaSellPrice2, numaSellPrice);

        // ***** PRINTER MIGRATE
        //migrate printer: redeploy, printer, don't create nuassets again but link them to printer (cf createnuassets)
        (numaOracle2, usdcEthConverter2, moneyPrinter2) = _setupPrinter(
            address(nuAssetMgr2),
            address(numaMinter2),
            address(vaultManager2)
        );
        _linkNuAssets(address(nuAssetMgr2), address(moneyPrinter2));
        // ***** LENDING MIGRATE

        // ** migrate lending
        cReth.setVault(address(vault2));
        cNuma.setVault(address(vault2));

        // strategies
        address[] memory strategies1 = cReth.getLeverageStrategies();
        for (uint i = 0; i < strategies1.length; i++) {
            cReth.removeStrategy(strategies1[i]);
        }
        // deploy strategy
        NumaLeverageVaultSwap strat0 = new NumaLeverageVaultSwap(
            address(vault2)
        );
        cReth.addStrategy(address(strat0));
        // ** link to vault
        vault2.setMaxBorrow(1000 ether);
        vault2.setCTokens(address(cNuma), address(cReth));

        // unpause vault
        vault2.unpause();

        // unpause lending
        // unpause printer

        // - buy/sells
        console2.log("TEST BUY/SELL");
        (uint buyResult2, uint sellResult2) = buyVault(
            rethAmount,
            INumaVault(address(vault2))
        );

        // diff tolerated as we executed many transactions since the previous buy/sell
        assertApproxEqAbs(buyResult2, buyResult, 50 ether, "buy not match");
        assertApproxEqAbs(
            sellResult2,
            sellResult,
            0.001 ether,
            "sell not match"
        );

        // - debt from lending protocol
        // - lending positions: numa, reth, interest rates, maxborrow/interestrate whith liquidCF
        // - open leverage before, close after, open after
        // - liquidate
        // - check printer estim before after
        // - check cf (modified) before/after
        // - print before, burn after
    }
}
