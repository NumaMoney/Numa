// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/console2.sol";
import {Setup} from "./utils/SetupDeployNuma_Arbitrum.sol";
import "../lending/ExponentialNoError.sol";
import "../interfaces/IVaultManager.sol";

contract VaultBuySellFeeTest is Setup, ExponentialNoError {
    uint buy_fee_PID;
    function setUp() public virtual override {
        console2.log("VAULT BUY/SELL FEES TEST");
        super.setUp();
        // send some rEth to userA
        vm.stopPrank();
        vm.prank(deployer);
        rEth.transfer(userA, 1000 ether);
    }
    function test_CheckSetup() public {}

    function test_Buy_IncBuyFeePID() public {
        vm.startPrank(userA);

        uint numaAmount = 200 ether;
        // check that TWAP price is < 2% buyprice

        // check pid is 0
        uint pidBefore = vaultManager.buy_fee_PID();
        assertEq(pidBefore, 0);

        uint numaPriceVault = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.NoFeePrice
        );
        uint numaPriceVaultBuy = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.BuyPrice
        );

        uint TWAPPrice = moneyPrinter.getTWAPPriceInEth(1 ether, 900);
        uint pctFromBuyPrice = 1000 - (1000 * TWAPPrice) / numaPriceVaultBuy; //percentage down from buyPrice

        uint RethInputAmount = vault.getBuyNumaAmountIn(numaAmount);

        rEth.approve(address(vault), RethInputAmount);
        // slippage = 0.1% = 1/1000
        uint realBuy = vault.buy(
            RethInputAmount,
            (numaAmount * (999)) / 1000,
            userA
        );

        buy_fee_PID = vaultManager.buy_fee_PID();
        assertEq(buy_fee_PID, 0);

        vm.stopPrank();
        vm.prank(deployer);

        vaultManager.setBuyFee(0.99 ether);

        vm.startPrank(userA);
        numaPriceVault = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.NoFeePrice
        );
        numaPriceVaultBuy = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.BuyPrice
        );

        TWAPPrice = moneyPrinter.getTWAPPriceInEth(1 ether, 900);
        pctFromBuyPrice = 1000 - (1000 * TWAPPrice) / numaPriceVaultBuy; //percentage down from buyPrice
        RethInputAmount = vault.getBuyNumaAmountIn(numaAmount);

        rEth.approve(address(vault), RethInputAmount);

        // this would be in Eth, we need it in numa (using buyprice as in our function)
        // using buy price before buy so that we get buyPrice used before updating PID
        uint _vaultBuyPrice = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.BuyPrice
        );

        // slippage = 0.1% = 1/1000
        uint buyFeeBefore = vaultManager.getBuyFee();
        realBuy = vault.buy(
            RethInputAmount,
            (numaAmount * (999)) / 1000,
            userA
        );
        // do as if there were no buy fee because this is the amount used to compute PID
        realBuy = (realBuy * 1 ether) / buyFeeBefore;

        buy_fee_PID = vaultManager.buy_fee_PID();

        // we use amount in Eth
        realBuy = (realBuy * _vaultBuyPrice) / 1 ether;

        // assertEq(
        //     buy_fee_PID,
        //     (realBuy * vaultManager.buyPID_incAmt()) / (1 ether)
        // );

        assertApproxEqAbs(
            buy_fee_PID,
            (realBuy * vaultManager.buyPID_incAmt()) / (1 ether),
            0.00001 ether,
            "increment ko"
        );

        uint newBuyFee = vaultManager.getBuyFee();
        assertEq(newBuyFee, buyFeeBefore - buy_fee_PID);

        vm.stopPrank();
    }

    function test_Buy_IncBuyFeePIDMaxRate() public {
        vm.prank(deployer);
        vaultManager.setBuyFee(0.99 ether);
        vm.startPrank(userA);

        uint maxDeltaxHours = vaultManager.buyPID_incMaxRate();
        uint incAmount = vaultManager.buyPID_incAmt();

        uint maxAmountNumaIncreasePID = (maxDeltaxHours * 1 ether) / incAmount;
        // this would be in Eth, we need it in numa (using buyprice as in our function)
        uint _vaultBuyPrice = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.BuyPrice
        );
        // we use amount in Eth
        maxAmountNumaIncreasePID =
            (maxAmountNumaIncreasePID * 1 ether) /
            _vaultBuyPrice;

        // these 2 buys should go beyond maxrate
        uint firstBuy = maxAmountNumaIncreasePID / 2;
        uint secondBuy = maxAmountNumaIncreasePID - firstBuy + 200 ether;

        // 1st buy
        //uint numaAmount = 200 ether;
        uint RethInputAmount = vault.getBuyNumaAmountIn(firstBuy);
        rEth.approve(address(vault), RethInputAmount);
        // slippage = 0.1% = 1/1000
        vault.buy(RethInputAmount, (firstBuy * (999)) / 1000, userA);

        buy_fee_PID = vaultManager.buy_fee_PID();
        assertGt(buy_fee_PID, 0);

        //2d buy
        RethInputAmount = vault.getBuyNumaAmountIn(secondBuy);
        rEth.approve(address(vault), RethInputAmount);
        // slippage = 0.1% = 1/1000
        vault.buy(RethInputAmount, (secondBuy * (999)) / 1000, userA);

        buy_fee_PID = vaultManager.buy_fee_PID();
        assertEq(buy_fee_PID, maxDeltaxHours);

        // start a new period
        skip(vaultManager.nextCheckBlockWindowDelta() + 1);
        // change buy fee so that it's nearer from TWAP
        vm.stopPrank();
        vm.prank(deployer);

        vaultManager.setBuyFee(0.999 ether);
        vm.startPrank(userA);

        // should increase PID???? BUG???
        RethInputAmount = vault.getBuyNumaAmountIn(secondBuy);
        rEth.approve(address(vault), RethInputAmount);
        // slippage = 0.1% = 1/1000
        vault.buy(RethInputAmount, (secondBuy * (999)) / 1000, userA);

        buy_fee_PID = vaultManager.buy_fee_PID();
        assertGt(buy_fee_PID, maxDeltaxHours);
    }
    function test_Buy_IncBuyFeePIDResetIfbelow() public {
        // get a PID > 0
        vm.prank(deployer);
        vaultManager.setBuyFee(0.99 ether);
        vm.startPrank(userA);

        uint maxDeltaxHours = vaultManager.buyPID_incMaxRate();
        uint incAmount = vaultManager.buyPID_incAmt();

        uint maxAmountNumaIncreasePID = (maxDeltaxHours * 1 ether) / incAmount;
        // this would be in Eth, we need it in numa (using buyprice as in our function)
        uint _vaultBuyPrice = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.BuyPrice
        );
        // we use amount in Eth
        maxAmountNumaIncreasePID =
            (maxAmountNumaIncreasePID * 1 ether) /
            _vaultBuyPrice;

        // these 2 buys should go beyond maxrate
        uint firstBuy = maxAmountNumaIncreasePID / 2;
        uint secondBuy = maxAmountNumaIncreasePID - firstBuy + 200 ether;

        // 1st buy
        //uint numaAmount = 200 ether;
        uint RethInputAmount = vault.getBuyNumaAmountIn(firstBuy);
        rEth.approve(address(vault), RethInputAmount);
        // slippage = 0.1% = 1/1000
        vault.buy(RethInputAmount, (firstBuy * (999)) / 1000, userA);

        buy_fee_PID = vaultManager.buy_fee_PID();
        assertGt(buy_fee_PID, 0);

        // start a new period to update ref
        skip(vaultManager.nextCheckBlockWindowDelta() + 1);

        // need a new buy will update ref. very small so that we don't change PID too much
        rEth.approve(address(vault), RethInputAmount / 10000);
        // slippage = 0.1% = 1/1000
        vault.buy(RethInputAmount / 10000, 0, userA);

        assertEq(vaultManager.buyPIDXhrAgo(), buy_fee_PID);
        buy_fee_PID = vaultManager.buy_fee_PID();
        assertGt(buy_fee_PID, vaultManager.buyPIDXhrAgo());
        uint timeref = vaultManager.nextCheckBlock();
        // get a PID below pID of starting period
        vm.stopPrank();
        vm.prank(deployer);
        vaultManager.setBuyFee(0.98 ether);
        vm.startPrank(userA);

        // sell to decrease PID
        numa.approve(address(vault), firstBuy);
        vault.sell(firstBuy, 0, userA);
        assertLt(vaultManager.buy_fee_PID(), buy_fee_PID);
        // we went down so reference should be updated
        assertEq(vaultManager.buyPIDXhrAgo(), vaultManager.buy_fee_PID());
        assertEq(vaultManager.nextCheckBlock(), timeref);
    }

    function test_BuyFee_Limit() public {
        // 1% buy fee
        vm.startPrank(deployer);
        vaultManager.setBuyFee(0.99 ether);

        // max buy fee 2%
        uint maxBuyFee = 0.98 ether;
        // max rate 5% so that we can reach the limit
        uint maxRate = 0.05 ether;
        // incamount so that 100 numa buy increases to 4%
        uint incAmount = 0.0004 ether * 6000; // 6000 to be in Eth

        vaultManager.setBuyFeeParameters(
            incAmount,
            vaultManager.buyPID_incTriggerPct(),
            vaultManager.buyPID_decAmt(),
            vaultManager.buyPID_decTriggerPct(),
            vaultManager.buyPID_decMultiplier(),
            maxRate,
            maxBuyFee,
            900,
            4 hours
        );

        vm.stopPrank();
        vm.startPrank(userA);
        uint RethInputAmount = vault.getBuyNumaAmountIn(100 ether);
        rEth.approve(address(vault), RethInputAmount);
        // slippage = 0.1% = 1/1000
        vault.buy(RethInputAmount, 0, userA);
        buy_fee_PID = vaultManager.buy_fee_PID();
        assertEq(buy_fee_PID, 0.01 ether); // 1% because maxbuyfee is 2% and buyfeebase is 1%
        assertEq(vaultManager.getBuyFee(), vaultManager.buyFee_max()); // 1% because maxbuyfee is 2% and buyfeebase is 1%
    }

    function test_BuyFee_DecreaseAndClippedBy0() public {
        // get a pid at maxrate
        vm.startPrank(deployer);
        vaultManager.setBuyFee(0.99 ether);
        // set multiplier to 1 so that we don't have to worry about it
        vaultManager.setBuyFeeParameters(
            vaultManager.buyPID_incAmt(),
            vaultManager.buyPID_incTriggerPct(),
            vaultManager.buyPID_decAmt(),
            vaultManager.buyPID_decTriggerPct(),
            1,
            vaultManager.buyPID_incMaxRate(),
            vaultManager.buyFee_max(),
            900,
            4 hours
        );
        vm.stopPrank();
        vm.startPrank(userA);

        uint maxDeltaxHours = vaultManager.buyPID_incMaxRate();
        uint incAmount = vaultManager.buyPID_incAmt();

        uint maxAmountNumaIncreasePID = (maxDeltaxHours * 1 ether) / incAmount;

        // this would be in Eth, we need it in numa (using buyprice as in our function)
        uint _vaultBuyPrice = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.BuyPrice
        );

        // we use amount in Eth
        maxAmountNumaIncreasePID =
            (maxAmountNumaIncreasePID * 1 ether) /
            _vaultBuyPrice;

        // these 2 buys should go beyond maxrate
        uint firstBuy = maxAmountNumaIncreasePID / 2;
        uint secondBuy = maxAmountNumaIncreasePID - firstBuy + 200 ether;

        // 1st buy
        //uint numaAmount = 200 ether;
        uint RethInputAmount = vault.getBuyNumaAmountIn(firstBuy);
        rEth.approve(address(vault), RethInputAmount);
        // slippage = 0.1% = 1/1000
        vault.buy(RethInputAmount, (firstBuy * (999)) / 1000, userA);

        buy_fee_PID = vaultManager.buy_fee_PID();
        assertGt(buy_fee_PID, 0);

        //2d buy
        RethInputAmount = vault.getBuyNumaAmountIn(secondBuy);
        rEth.approve(address(vault), RethInputAmount);
        // slippage = 0.1% = 1/1000
        vault.buy(RethInputAmount, (secondBuy * (999)) / 1000, userA);

        buy_fee_PID = vaultManager.buy_fee_PID();
        assertEq(buy_fee_PID, maxDeltaxHours);

        // sell - check decreases PID , check decrease value/amount
        // decrease 1/4 of maxrate
        uint decAmount = vaultManager.buyPID_decAmt();
        // amount of numa needed to reach maxDeltaxHours
        uint amountNumaDecreasePID = (maxDeltaxHours * 1 ether) / decAmount;
        amountNumaDecreasePID = amountNumaDecreasePID / 4;

        // we use amount in Eth
        _vaultBuyPrice = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.BuyPrice
        );
        amountNumaDecreasePID =
            (amountNumaDecreasePID * 1 ether) /
            _vaultBuyPrice;

        numa.approve(address(vault), amountNumaDecreasePID);

        vault.sell(amountNumaDecreasePID, 0, userA);
        buy_fee_PID = vaultManager.buy_fee_PID();

        assertLt(buy_fee_PID, maxDeltaxHours);
        //assertEq(maxDeltaxHours - buy_fee_PID, maxDeltaxHours / 4);

        assertApproxEqAbs(
            maxDeltaxHours - buy_fee_PID,
            maxDeltaxHours / 4,
            0.00001 ether,
            "decrement 1 ko"
        );

        // synth burn/mint - decreases PID
        vm.stopPrank();
        vm.prank(deployer);
        vaultManager.setBuyFee(0.98 ether);
        vm.startPrank(userA);

        // need to recompute it as our buyprice has changed
        amountNumaDecreasePID = (maxDeltaxHours * 1 ether) / decAmount;
        amountNumaDecreasePID = amountNumaDecreasePID / 4;

        // we use amount in Eth
        _vaultBuyPrice = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.BuyPrice
        );
        amountNumaDecreasePID =
            (amountNumaDecreasePID * 1 ether) /
            _vaultBuyPrice;

        // mint nuUSD
        numa.approve(address(moneyPrinter), amountNumaDecreasePID);

        moneyPrinter.mintAssetFromNumaInput(
            address(nuUSD),
            amountNumaDecreasePID,
            0,
            userA
        );
        buy_fee_PID = vaultManager.buy_fee_PID();
        //assertEq(maxDeltaxHours - buy_fee_PID, maxDeltaxHours / 2);
        assertApproxEqAbs(
            maxDeltaxHours - buy_fee_PID,
            maxDeltaxHours / 2,
            0.00001 ether,
            "decrement 2 ko"
        );

        // burn
        //(uint256 nuAssetAmount,uint256 numaFee) = moneyPrinter.getNbOfnuAssetNeededForNuma(address(nuUSD),amountNumaDecreasePID);

        // compute numaAmount so that outputting this amount uses the equivalent of amountNumaDecreasePID
        // amountNumaDecreasePID = numaAmount + computeFeeAmountOut(numaAmount)
        // amountNumaDecreasePID = numaAmount + numaAmount x fee / (10000 - fee)
        // amountNumaDecreasePID = numaAmount x 10000 / 10000 - fee
        // numaAmount = amountNumaDecreasePID x (10000 - fee)/10000

        // need to recompute it as our buyprice has changed
        amountNumaDecreasePID = (maxDeltaxHours * 1 ether) / decAmount;
        amountNumaDecreasePID = amountNumaDecreasePID / 4;

        // we use amount in Eth
        _vaultBuyPrice = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.BuyPrice
        );
        amountNumaDecreasePID =
            (amountNumaDecreasePID * 1 ether) /
            _vaultBuyPrice;

        uint numaAmount = (amountNumaDecreasePID *
            (10000 - moneyPrinter.burnAssetFeeBps())) / 10000;

        (uint256 nuAssetAmount, ) = moneyPrinter.getNbOfnuAssetNeededForNuma(
            address(nuUSD),
            numaAmount
        );
        // need some more nuUSD
        vm.stopPrank();
        vm.prank(deployer);
        nuUSD.mint(userA, nuAssetAmount);
        vm.startPrank(userA);

        nuUSD.approve(address(moneyPrinter), nuAssetAmount);
        moneyPrinter.burnAssetToNumaOutput(
            address(nuUSD),
            numaAmount,
            nuAssetAmount + 1,
            userA
        );

        buy_fee_PID = vaultManager.buy_fee_PID();
        //assertEq(maxDeltaxHours - buy_fee_PID, (3 * maxDeltaxHours) / 4);
        assertApproxEqAbs(
            maxDeltaxHours - buy_fee_PID,
            (3 * maxDeltaxHours) / 4,
            0.00001 ether,
            "decrement 3 ko"
        );

        // 1 more time with twice the amount, we should have PID = 0

        numaAmount =
            (2 *
                amountNumaDecreasePID *
                (10000 - moneyPrinter.burnAssetFeeBps())) /
            10000;

        (nuAssetAmount, ) = moneyPrinter.getNbOfnuAssetNeededForNuma(
            address(nuUSD),
            numaAmount
        );
        // need some more nuUSD
        vm.stopPrank();
        vm.prank(deployer);
        nuUSD.mint(userA, nuAssetAmount);
        vm.prank(deployer);
        // change buyfee to be in range
        vaultManager.setBuyFee(0.97 ether);

        vm.startPrank(userA);

        nuUSD.approve(address(moneyPrinter), nuAssetAmount);
        moneyPrinter.burnAssetToNumaOutput(
            address(nuUSD),
            numaAmount,
            nuAssetAmount + 1,
            userA
        );

        buy_fee_PID = vaultManager.buy_fee_PID();
        assertEq(buy_fee_PID, 0);
    }

    function test_BuyFee_DecreaseMultiplier() public {
        // get a pid at maxrate
        vm.prank(deployer);
        vaultManager.setBuyFee(0.99 ether);
        vm.startPrank(userA);

        uint maxDeltaxHours = vaultManager.buyPID_incMaxRate();
        uint incAmount = vaultManager.buyPID_incAmt();

        uint maxAmountNumaIncreasePID = (maxDeltaxHours * 1 ether) / incAmount;
        // this would be in Eth, we need it in numa (using buyprice as in our function)
        uint _vaultBuyPrice = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.BuyPrice
        );

        // we use amount in Eth
        maxAmountNumaIncreasePID =
            (maxAmountNumaIncreasePID * 1 ether) /
            _vaultBuyPrice;

        // these 2 buys should go beyond maxrate
        uint firstBuy = maxAmountNumaIncreasePID / 2;
        uint secondBuy = maxAmountNumaIncreasePID - firstBuy + 200 ether;

        // 1st buy
        //uint numaAmount = 200 ether;
        uint RethInputAmount = vault.getBuyNumaAmountIn(firstBuy);
        rEth.approve(address(vault), RethInputAmount);
        // slippage = 0.1% = 1/1000
        vault.buy(RethInputAmount, (firstBuy * (999)) / 1000, userA);

        buy_fee_PID = vaultManager.buy_fee_PID();
        assertGt(buy_fee_PID, 0);

        //2d buy
        RethInputAmount = vault.getBuyNumaAmountIn(secondBuy);
        rEth.approve(address(vault), RethInputAmount);
        // slippage = 0.1% = 1/1000
        vault.buy(RethInputAmount, (secondBuy * (999)) / 1000, userA);

        buy_fee_PID = vaultManager.buy_fee_PID();
        assertEq(buy_fee_PID, maxDeltaxHours);

        // sell - check decreases PID , check decrease value/amount
        // check if should apply multiplier

        uint numaPriceVaultBuy = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.BuyPrice
        );

        uint TWAPPrice = moneyPrinter.getTWAPPriceInEth(1 ether, 900);
        uint pctFromBuyPrice = 1000 - (1000 * TWAPPrice) / numaPriceVaultBuy; //percentage down from buyPrice

        uint mult = vaultManager.buyPID_decMultiplier();



        //if (pctFromBuyPrice <= ((buy_fee_PID * 1000) / 1 ether)) mult = 1;
        if (
            pctFromBuyPrice <=
            ((2 * (1 ether - vaultManager.buy_fee()) * 1000) / 1 ether)
        ) mult = 1;

        // decrease 1/4 of maxrate
        uint decAmount = vaultManager.buyPID_decAmt();
        // amount of numa needed to reach maxDeltaxHours
        uint amountNumaDecreasePID = (maxDeltaxHours * 1 ether) / decAmount;

        amountNumaDecreasePID = amountNumaDecreasePID / 4;

        // this would be in Eth, we need it in numa (using buyprice as in our function)
        _vaultBuyPrice = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.BuyPrice
        );

        // we use amount in Eth
        amountNumaDecreasePID =
            (amountNumaDecreasePID * 1 ether) /
            _vaultBuyPrice;

        numa.approve(address(vault), amountNumaDecreasePID);
        vault.sell(amountNumaDecreasePID, 0, userA);
        buy_fee_PID = vaultManager.buy_fee_PID();

        assertLt(buy_fee_PID, maxDeltaxHours);
        if (((mult * maxDeltaxHours) / 4) <= maxDeltaxHours) {
            console2.log("not reaching maxdelta");
            assertEq(maxDeltaxHours - buy_fee_PID, (mult * maxDeltaxHours) / 4);
        } else {
            console2.log("reaching maxdelta");
            assertEq(maxDeltaxHours - buy_fee_PID, maxDeltaxHours);
        }
    }

    function test_SellFee_Debase() public {
        (uint sell_feePID, , ) = vaultManager.getSellFeeScaling();
        assertEq(vaultManager.getSellFeeOriginal(), sell_feePID);

        uint sellPrice = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.SellPrice
        );

        // setting cf_liquid_severe as 100001 so that we are below it at MAX_CF (= 100000)
        vm.prank(deployer);
        vaultManager.setSellFeeParameters(
            100001,
            0.01 ether, // 1%
            0.03 ether, // 3%
            600,
            1200,
            0.5 ether, // 50%
            0.2 ether, // 80%
            10000 //10
        );
        //vm.warp(block.timestamp + 600*10);
        // should debase by 10%
    
        (sell_feePID, , ) = vaultManager.getSellFeeScaling();
        //assertEq(sell_feePID, vaultManager.getSellFeeOriginal()-0.1 ether);
        // should not have changed since no delta time
        assertEq(sell_feePID, vaultManager.getSellFeeOriginal());
        vm.warp(block.timestamp + 600 * 10);
        // we need to simulate a new block too because we check the update_block_number
        vm.roll(block.number + 1);
        (sell_feePID, , ) = vaultManager.getSellFeeScaling();
        // should debase by 10%
        assertEq(sell_feePID, vaultManager.getSellFeeOriginal() - 0.1 ether);

        uint sellPrice2 = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.SellPrice
        );
        // sell price should be lower
        assertLt(sellPrice2, sellPrice);

        // reach min
        vm.warp(block.timestamp + 600 * 41);
        // we need to simulate a new block too because we check the update_block_number
        vm.roll(block.number + 1);
        (sell_feePID, , ) = vaultManager.getSellFeeScaling();
        // should debase by 50% because it's the max
        assertEq(sell_feePID, vaultManager.sell_fee_minimum());

        uint sellPrice3 = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.SellPrice
        );
        // sell price should be lower
        assertLt(sellPrice3, sellPrice2);

        // rebase
        vm.prank(deployer);
        vaultManager.setSellFeeParameters(
            19000,
            0.01 ether, // 1%
            0.03 ether, // 3%
            600,
            1200,
            0.5 ether, // 50%
            0.1 ether, // 90%
            10000 //10
        );
        vm.warp(block.timestamp + 1200 * 10);
        // we need to simulate a new block too because we check the update_block_number
        vm.roll(block.number + 1);

        (sell_feePID, , ) = vaultManager.getSellFeeScaling();
        assertEq(sell_feePID, vaultManager.sell_fee_minimum() + 0.3 ether);

        uint sellPrice4 = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.SellPrice
        );
        // sell price should be higher
        assertGt(sellPrice4, sellPrice3);

        // 30% again
        vm.warp(block.timestamp + 1200 * 10);
        // we need to simulate a new block too because we check the update_block_number
        vm.roll(block.number + 1);

        (sell_feePID, , ) = vaultManager.getSellFeeScaling();

        assertEq(sell_feePID, vaultManager.getSellFeeOriginal());

        uint sellPrice5 = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.SellPrice
        );
        // sell price should be higher
        assertGt(sellPrice5, sellPrice4);

     
        uint globalCF = vaultManager.getGlobalCF();
        assertGt(globalCF, vaultManager.cf_critical());
     
        vm.prank(deployer);
        numa.approve(address(moneyPrinter), 10000000 ether);
        //     function mintAssetOutputFromNuma(
        vm.prank(deployer);
        moneyPrinter.mintAssetOutputFromNuma(
            address(nuUSD),
            4500000 ether,
            10000000 ether,
            userA
        );

        uint globalCF2 = vaultManager.getGlobalCF();       
        assertLt(globalCF2, globalCF);


        vm.stopPrank();
        vm.startPrank(deployer);
        vaultManager.setScalingParameters(
            1200,
            vaultManager.cf_warning(),
            vaultManager.cf_severe(),
            vaultManager.debaseValue(),
            vaultManager.rebaseValue(),
            vaultManager.deltaDebase(),
            vaultManager.deltaRebase(),
            vaultManager.minimumScale(),
            vaultManager.criticalDebaseMult()
        );

        uint criticalScaleForNumaPriceAndSellFee = (1000 * globalCF2) /
            vaultManager.cf_critical();
       

        uint sell_fee_increaseCriticalCF = ((1000 -
            criticalScaleForNumaPriceAndSellFee) * 1 ether) / 1000;
        // add a multiplier on top
        sell_fee_increaseCriticalCF =
            (sell_fee_increaseCriticalCF *
                vaultManager.sell_fee_criticalMultiplier()) /
            1000;
       
        uint sell_fee_criticalCF;

        if (vaultManager.getSellFeeOriginal() > sell_fee_increaseCriticalCF)
            sell_fee_criticalCF =
                vaultManager.getSellFeeOriginal() -
                sell_fee_increaseCriticalCF;

        if (sell_fee_criticalCF < vaultManager.sell_fee_minimum_critical())
            sell_fee_criticalCF = vaultManager.sell_fee_minimum_critical();
        (sell_feePID, , ) = vaultManager.getSellFeeScaling();
     

        assertEq(sell_feePID, sell_fee_criticalCF);
    }
}
