// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/console2.sol";
import {Setup} from "./utils/SetupDeployNuma_Arbitrum.sol";
import "../lending/ExponentialNoError.sol";

contract LendingTest is Setup, ExponentialNoError {
    uint providedAmount = 10 ether;
    uint leverageAmount = 40 ether;

    function setUp() public virtual override {
        console2.log("LENDING TEST");
        super.setUp();
        // set reth vault balance so that 1 numa = 1 rEth
        deal({token: address(rEth), to: address(vault), give: numaSupply});

        // send some numa to userA
        vm.stopPrank();
        vm.prank(deployer);
        numa.transfer(userA, 1000 ether);
    }
    function test_CheckSetup() public {
        // test that numa price (without fees) is 1 reth
        uint numaPriceReth = vaultManager.numaToToken(
            1 ether,
            vault.last_lsttokenvalueWei(),
            vault.decimals(),
            1000
        );
        console2.log(numaPriceReth);
        assertEq(numaPriceReth, 1 ether);
        // TODO
        // check collateral factor

        // check fees
    }

    function test_LeverageAndCloseProfit() public {
        // user calls leverage x 5
        vm.startPrank(userA);
        address[] memory t = new address[](1);
        t[0] = address(cNuma);
        comptroller.enterMarkets(t);

        uint numaBalBefore = numa.balanceOf(userA);

        uint totalCollateral = providedAmount + leverageAmount;
        numa.approve(address(cReth), providedAmount);
        cReth.leverage(providedAmount, leverageAmount, cNuma);

        // check balances
        // cnuma position
        uint cNumaBal = cNuma.balanceOf(userA);
        console2.log(cNumaBal);

        //uint exchangeRate = cNuma.exchangeRateStored();
        Exp memory exchangeRate = Exp({mantissa: cNuma.exchangeRateStored()});

        uint mintTokens = div_(totalCollateral, exchangeRate);

        assertEq(cNumaBal, mintTokens);

        // numa stored in cnuma contract
        uint numaBal = numa.balanceOf(address(cNuma));
        assertEq(numaBal, totalCollateral);

        // borrow balance
        uint borrowrEThBalance = cReth.borrowBalanceCurrent(userA);

        console2.log(borrowrEThBalance);

        (, uint ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        console2.log("ltv before");
        console2.log(ltv);
        // vault borrow (should be the same)

        // numa price increase 20%
        uint newRethBalance = numaSupply + (20 * numaSupply) / 100;
        deal({token: address(rEth), to: address(vault), give: newRethBalance});

        // check states
        (, ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        console2.log("ltv after");
        console2.log(ltv);

        // close position
        // uint borrowrEThBalance2 = cReth.borrowBalanceCurrent(userA);
        //  console2.log("borrow balance");
        //  console2.log(borrowrEThBalance);
        //   console2.log(borrowrEThBalance2);

        (uint cnumaAmount, uint swapAmountIn) = cReth.closeLeverageAmount(
            cNuma,
            borrowrEThBalance
        );

        cNuma.approve(address(cReth), cnumaAmount);
        cReth.closeLeverage(cNuma, borrowrEThBalance);

        (, ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        console2.log("ltv after close");
        console2.log(ltv);

        // redeem

        cNuma.redeem(cNuma.balanceOf(userA));
        cNumaBal = cNuma.balanceOf(userA);
        console2.log("cnuma balance after close & redeem");
        console2.log(cNumaBal);
        // check balances
        uint numaBalAfter = numa.balanceOf(userA);
        if (numaBalAfter > numaBalBefore) {
            console2.log("profit");
            console2.log(numaBalAfter - numaBalBefore);
        } else {
            console2.log("loss");
            console2.log(numaBalBefore - numaBalAfter);
        }

        vm.stopPrank();
    }

    function test_LeverageAndCloseProfitStrategyStratVault() public {
        // user calls leverage x 5
        vm.startPrank(userA);
        address[] memory t = new address[](1);
        t[0] = address(cNuma);
        comptroller.enterMarkets(t);

        uint numaBalBefore = numa.balanceOf(userA);

        uint totalCollateral = providedAmount + leverageAmount;
        numa.approve(address(cReth), providedAmount);

        // call strategy
        uint strategyindex = 0;
        cReth.leverageStrategy(
            providedAmount,
            leverageAmount,
            cNuma,
            strategyindex
        );

        // check balances
        // cnuma position
        uint cNumaBal = cNuma.balanceOf(userA);
        console2.log(cNumaBal);

        //uint exchangeRate = cNuma.exchangeRateStored();
        Exp memory exchangeRate = Exp({mantissa: cNuma.exchangeRateStored()});

        uint mintTokens = div_(totalCollateral, exchangeRate);

        assertEq(cNumaBal, mintTokens);

        // numa stored in cnuma contract
        uint numaBal = numa.balanceOf(address(cNuma));
        assertEq(numaBal, totalCollateral);

        // borrow balance
        uint borrowrEThBalance = cReth.borrowBalanceCurrent(userA);

        console2.log(borrowrEThBalance);

        (, uint ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        console2.log("ltv before");
        console2.log(ltv);
        // vault borrow (should be the same)

        // numa price increase 20%
        uint newRethBalance = numaSupply + (20 * numaSupply) / 100;
        deal({token: address(rEth), to: address(vault), give: newRethBalance});

        // check states
        (, ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        console2.log("ltv after");
        console2.log(ltv);

        // close position
        // uint borrowrEThBalance2 = cReth.borrowBalanceCurrent(userA);
        //  console2.log("borrow balance");
        //  console2.log(borrowrEThBalance);
        //   console2.log(borrowrEThBalance2);

        (uint cnumaAmount, uint swapAmountIn) = cReth.closeLeverageAmount(
            cNuma,
            borrowrEThBalance,
            strategyindex
        );

        cNuma.approve(address(cReth), cnumaAmount);
        cReth.closeLeverageStrategy(cNuma, borrowrEThBalance, strategyindex);

        (, ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        console2.log("ltv after close");
        console2.log(ltv);

        // redeem

        cNuma.redeem(cNuma.balanceOf(userA));
        cNumaBal = cNuma.balanceOf(userA);
        console2.log("cnuma balance after close & redeem");
        console2.log(cNumaBal);
        // check balances
        uint numaBalAfter = numa.balanceOf(userA);
        if (numaBalAfter > numaBalBefore) {
            console2.log("profit");
            console2.log(numaBalAfter - numaBalBefore);
        } else {
            console2.log("loss");
            console2.log(numaBalBefore - numaBalAfter);
        }

        vm.stopPrank();
    }

    function test_LeverageAndCloseProfitStrategyStratLP() public {
        // user calls leverage x 5
        vm.startPrank(userA);
        address[] memory t = new address[](1);
        t[0] = address(cNuma);
        comptroller.enterMarkets(t);

        uint numaBalBefore = numa.balanceOf(userA);

        uint totalCollateral = providedAmount + leverageAmount;
        numa.approve(address(cReth), providedAmount);

        // call strategy
        uint strategyindex = 1;
        cReth.leverageStrategy(
            providedAmount,
            leverageAmount,
            cNuma,
            strategyindex
        );

        // check balances
        // cnuma position
        uint cNumaBal = cNuma.balanceOf(userA);
        console2.log(cNumaBal);

        //uint exchangeRate = cNuma.exchangeRateStored();
        Exp memory exchangeRate = Exp({mantissa: cNuma.exchangeRateStored()});

        uint mintTokens = div_(totalCollateral, exchangeRate);

        assertEq(cNumaBal, mintTokens);

        // numa stored in cnuma contract
        uint numaBal = numa.balanceOf(address(cNuma));
        assertEq(numaBal, totalCollateral);

        // borrow balance
        uint borrowrEThBalance = cReth.borrowBalanceCurrent(userA);

        console2.log(borrowrEThBalance);

        (, uint ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        console2.log("ltv before");
        console2.log(ltv);
        // vault borrow (should be the same)

        // numa price increase 20%
        uint newRethBalance = numaSupply + (20 * numaSupply) / 100;
        deal({token: address(rEth), to: address(vault), give: newRethBalance});

        // check states
        (, ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        console2.log("ltv after");
        console2.log(ltv);

        // close position

        (uint cnumaAmount, uint swapAmountIn) = cReth.closeLeverageAmount(
            cNuma,
            borrowrEThBalance,
            strategyindex
        );

        cNuma.approve(address(cReth), cnumaAmount);
        cReth.closeLeverageStrategy(cNuma, borrowrEThBalance, strategyindex);

        (, ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        console2.log("ltv after close");
        console2.log(ltv);

        // redeem

        cNuma.redeem(cNuma.balanceOf(userA));
        cNumaBal = cNuma.balanceOf(userA);
        console2.log("cnuma balance after close & redeem");
        console2.log(cNumaBal);
        // check balances
        uint numaBalAfter = numa.balanceOf(userA);
        if (numaBalAfter > numaBalBefore) {
            console2.log("profit");
            console2.log(numaBalAfter - numaBalBefore);
        } else {
            console2.log("loss");
            console2.log(numaBalBefore - numaBalAfter);
        }

        vm.stopPrank();
    }
}
