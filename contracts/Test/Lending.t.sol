// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/console2.sol";
import "@openzeppelin/contracts_5.0.2/token/ERC20/ERC20.sol";

import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
//import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./uniV3Interfaces/ISwapRouter.sol";

import {NumaLeverageLPSwap} from "../Test/mocks/NumaLeverageLPSwap.sol";

import "../lending/ExponentialNoError.sol";
import "../lending/INumaLeverageStrategy.sol";
import {Setup} from "./utils/SetupDeployNuma_Arbitrum.sol";
contract LendingTest is Setup, ExponentialNoError {
    uint providedAmount = 10 ether;
    uint leverageAmount = 40 ether;

    uint numaPoolReserve;
    uint rEthPoolReserve;

    uint numaPriceCollateral;
    uint numaPriceBorrow;

    function setUp() public virtual override {
        console2.log("LENDING TEST");
        super.setUp();
        // set reth vault balance so that 1 numa = 1 rEth
        deal({token: address(rEth), to: address(vault), give: numaSupply});
        // numa/reth pool reserves
        numaPoolReserve = numa.totalSupply() / 1000;
        rEthPoolReserve = rEth.balanceOf(address(vault)) / 1000;

        deal({
            token: address(rEth),
            to: deployer,
            give: 10000 * rEthPoolReserve
        });
        // send some numa to userA
        vm.stopPrank();
        vm.startPrank(deployer);
        numa.transfer(userA, 9000000 ether);

        // create pool Reth/numa and strategy
        uint NumaAmountPool = numaPoolReserve;
        uint rEthAmountPool = rEthPoolReserve;
        // which one is xceeding balance

        console2.log(NumaAmountPool);
        console2.log(rEthAmountPool);

        address NUMA_RETH_POOL_ADDRESS = _setupUniswapPool(
            rEth,
            ERC20(address(numa)),
            rEthAmountPool,
            NumaAmountPool
        );

        // check price
        //Spot price of the token
        (uint160 sqrtPriceX96Spot, , , , , , ) = IUniswapV3Pool(
            NUMA_RETH_POOL_ADDRESS
        ).slot0();

        uint256 numerator = sqrtPriceX96Spot;

        uint256 denominator = FixedPoint96.Q96;
        uint256 price = FullMath.mulDivRoundingUp(
            numerator,
            numerator * 10 ** 18,
            denominator * denominator
        );

        console2.log("price reth/numa");
        console2.log(price);

        // deploy and add strategy
        NumaLeverageLPSwap strat1 = new NumaLeverageLPSwap(
            address(swapRouter),
            NUMA_RETH_POOL_ADDRESS,
            address(vault)
        );
        cReth.addStrategy(address(strat1));
        vm.stopPrank();
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

    function test_LeverageStratVaultDrainBug() public {
        vm.prank(deployer);
        vault.setMaxBorrow(1000000000 ether);

        vm.prank(deployer);
        vault.setMaxPercent(1000);

        // user calls leverage x 5
        vm.startPrank(userA);
        address[] memory t = new address[](1);
        t[0] = address(cNuma);
        comptroller.enterMarkets(t);

        uint numaBalBefore = numa.balanceOf(userA);

        uint providedAmount2 = 2000000 ether;
        uint leverageAmount2 = 8000000 ether;

        uint totalCollateral = providedAmount2 + leverageAmount2;
        numa.approve(address(cReth), providedAmount2);

        // call strategy
        uint strategyindex = 0;
        cReth.leverageStrategy(
            providedAmount2,
            leverageAmount2,
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
        console2.log("ltv");
        console2.log(ltv);

        // vault balance
        console2.log("vault balance", rEth.balanceOf(address(vault)));
        console2.log("vault debt", vault.getDebt());
        console2.log("lst borrow rate per block", cReth.borrowRatePerBlock());
        // 2nd time
        numa.approve(address(cReth), providedAmount2);

        // call strategy
        cReth.leverageStrategy(
            providedAmount2,
            leverageAmount2,
            cNuma,
            strategyindex
        );

        // check balances
        // cnuma position
        cNumaBal = cNuma.balanceOf(userA);
        console2.log(cNumaBal);

        // borrow balance
        borrowrEThBalance = cReth.borrowBalanceCurrent(userA);

        console2.log(borrowrEThBalance);

        (, ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        console2.log("ltv");
        console2.log(ltv);

        // vault balance
        console2.log("vault balance 2", rEth.balanceOf(address(vault)));
        console2.log("vault debt 2", vault.getDebt());
        console2.log("lst borrow rate per block 2", cReth.borrowRatePerBlock());

        numa.approve(address(cReth), providedAmount2);

        // call strategy
        cReth.leverageStrategy(
            providedAmount2,
            leverageAmount2,
            cNuma,
            strategyindex
        );

        // check balances
        // cnuma position
        cNumaBal = cNuma.balanceOf(userA);
        console2.log(cNumaBal);

        // borrow balance
        borrowrEThBalance = cReth.borrowBalanceCurrent(userA);

        console2.log(borrowrEThBalance);

        (, ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        console2.log("ltv");
        console2.log(ltv);

        // vault balance
        console2.log("vault balance 3", rEth.balanceOf(address(vault)));
        console2.log("vault debt 3", vault.getDebt());
        console2.log("lst borrow rate per block 3", cReth.borrowRatePerBlock());

        numa.approve(address(cReth), providedAmount2);

        // call strategy
        cReth.leverageStrategy(
            providedAmount2,
            leverageAmount2,
            cNuma,
            strategyindex
        );

        // check balances
        // cnuma position
        cNumaBal = cNuma.balanceOf(userA);
        console2.log(cNumaBal);

        // borrow balance
        borrowrEThBalance = cReth.borrowBalanceCurrent(userA);

        console2.log(borrowrEThBalance);

        (, ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        console2.log("ltv");
        console2.log(ltv);

        // vault balance
        console2.log("vault balance 4", rEth.balanceOf(address(vault)));
        console2.log("vault debt 4", vault.getDebt());
        console2.log("lst borrow rate per block 4", cReth.borrowRatePerBlock());

        providedAmount2 = 1000000 ether;
        leverageAmount2 = 4000000 ether;
        numa.approve(address(cReth), providedAmount2);

        // call strategy
        cReth.leverageStrategy(
            providedAmount2,
            leverageAmount2,
            cNuma,
            strategyindex
        );

        // check balances
        // cnuma position
        cNumaBal = cNuma.balanceOf(userA);
        console2.log(cNumaBal);

        // borrow balance
        borrowrEThBalance = cReth.borrowBalanceCurrent(userA);

        console2.log(borrowrEThBalance);

        (, ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        console2.log("ltv");
        console2.log(ltv);

        // vault balance
        console2.log("vault balance 5", rEth.balanceOf(address(vault)));
        console2.log("vault debt 5", vault.getDebt());
        console2.log("lst borrow rate per block 5", cReth.borrowRatePerBlock());
        (, uint liquidity, uint shortfall, uint badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log("liquidity:", liquidity);
        console2.log("shortfall:", shortfall);
        console2.log("badDebt:", badDebt);

        // make it liquiditable
        // 2 years later (NOT ENOUGH)
        // vm.roll(block.number + blocksPerYear*2);
        // cReth.accrueInterest();
        vm.startPrank(deployer);
        vaultManager.setSellFee(0.85 ether);

        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log("liquidity:", liquidity);
        console2.log("shortfall:", shortfall);
        console2.log("badDebt:", badDebt);

        // liquidate
        vm.startPrank(userC);
        uint balC = rEth.balanceOf(userC);
        // should revert as we don't have enough reth in the vault
        vault.liquidateLstBorrower(userA, 500 ether, true, true);
        console2.log("liquidator profit:", rEth.balanceOf(userC) - balC);
        balC = rEth.balanceOf(userC);
        vault.liquidateLstBorrower(userA, 500 ether, true, true);
        console2.log("liquidator profit:", rEth.balanceOf(userC) - balC);

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
        //vault borrow (should be the same)

        //numa price increase 20%
        uint newRethBalance = numaSupply + (20 * numaSupply) / 100;
        deal({token: address(rEth), to: address(vault), give: newRethBalance});
        // make a swap to increase price
        vm.stopPrank();
        vm.startPrank(deployer);
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams({
                tokenIn: address(rEth),
                tokenOut: address(numa),
                fee: 500,
                recipient: deployer,
                deadline: block.timestamp,
                amountOut: numaPoolReserve / 4, // 25% of reserve should be enough?
                amountInMaximum: type(uint).max,
                sqrtPriceLimitX96: 0
            });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        rEth.approve(address(swapRouter), type(uint).max);
        // ERC20InsufficientAllowance(0xE592427A0AEce92De3Edee1F18E0157C05861564, 36934311772498674553 [3.693e19], 2548408988412747955903073076714761369303 [2.548e39])
        swapRouter.exactOutputSingle(params);
        vm.stopPrank();
        vm.startPrank(userA);
        // check states
        (, ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        console2.log("ltv after");
        console2.log(ltv);

        //close position

        (uint cnumaAmount, uint swapAmountIn) = cReth.closeLeverageAmount(
            cNuma,
            borrowrEThBalance,
            strategyindex
        );

        cNuma.approve(address(cReth), cnumaAmount);
        cReth.closeLeverageStrategy(cNuma, borrowrEThBalance, strategyindex);

        borrowrEThBalance = cReth.borrowBalanceCurrent(userA);
        console2.log("borrow amount after");
        console2.log(borrowrEThBalance);
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

    function test_LeverageAndCloseProfitStrategyChoice1() public {
        // user calls leverage x 5
        vm.startPrank(userA);
        address[] memory t = new address[](1);
        t[0] = address(cNuma);
        comptroller.enterMarkets(t);

        uint numaBalBefore = numa.balanceOf(userA);

        uint totalCollateral = providedAmount + leverageAmount;
        numa.approve(address(cReth), providedAmount);

        // choose strategy
        //address[] memory strategies = cReth.getLeverageStrategies();

        console2.log("comparing strategies: amount to borrow");
        console2.log(cReth.getAmountIn(leverageAmount, false, 0));
        console2.log(cReth.getAmountIn(leverageAmount, false, 1));

        // call strategy
        uint strategyindex = 0;

        if (
            cReth.getAmountIn(leverageAmount, false, 1) <
            cReth.getAmountIn(leverageAmount, false, 0)
        ) strategyindex = 1;

        console2.log("strategy for open");
        console2.log(strategyindex);
        assertEq(strategyindex, 1);
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
        //vault borrow (should be the same)

        //numa price increase 20%
        uint newRethBalance = numaSupply + (20 * numaSupply) / 100;
        deal({token: address(rEth), to: address(vault), give: newRethBalance});
        // make a swap to increase price
        vm.stopPrank();
        vm.startPrank(deployer);
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams({
                tokenIn: address(rEth),
                tokenOut: address(numa),
                fee: 500,
                recipient: deployer,
                deadline: block.timestamp,
                amountOut: numaPoolReserve / 4, // 25% of reserve should be enough?
                amountInMaximum: type(uint).max,
                sqrtPriceLimitX96: 0
            });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        rEth.approve(address(swapRouter), type(uint).max);
        // ERC20InsufficientAllowance(0xE592427A0AEce92De3Edee1F18E0157C05861564, 36934311772498674553 [3.693e19], 2548408988412747955903073076714761369303 [2.548e39])
        swapRouter.exactOutputSingle(params);
        vm.stopPrank();
        vm.startPrank(userA);
        // check states
        (, ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        console2.log("ltv after");
        console2.log(ltv);

        //close position

        strategyindex = 0;
        if (
            cReth.getAmountIn(borrowrEThBalance, true, 1) <
            cReth.getAmountIn(borrowrEThBalance, true, 0)
        ) strategyindex = 1;

        console2.log("strategy for close");
        console2.log(strategyindex);
        assertEq(strategyindex, 1);
        (uint cnumaAmount, uint swapAmountIn) = cReth.closeLeverageAmount(
            cNuma,
            borrowrEThBalance,
            strategyindex
        );

        cNuma.approve(address(cReth), cnumaAmount);
        cReth.closeLeverageStrategy(cNuma, borrowrEThBalance, strategyindex);

        borrowrEThBalance = cReth.borrowBalanceCurrent(userA);
        console2.log("borrow amount after");
        console2.log(borrowrEThBalance);
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

    function test_LeverageAndCloseProfitStrategyChoice0() public {
        // user calls leverage x 5
        vm.startPrank(userA);
        address[] memory t = new address[](1);
        t[0] = address(cNuma);
        comptroller.enterMarkets(t);

        uint numaBalBefore = numa.balanceOf(userA);

        uint totalCollateral = providedAmount + leverageAmount;
        numa.approve(address(cReth), providedAmount);

        // choose strategy
        //address[] memory strategies = cReth.getLeverageStrategies();

        // reduce buyfee so that swapping through vault is more profitable
        vm.stopPrank();
        vm.prank(deployer);

        vaultManager.setBuyFee(0.996 ether); // 0.4%

        vm.startPrank(userA);

        console2.log("comparing strategies: amount to borrow");
        console2.log(cReth.getAmountIn(leverageAmount, false, 0));
        console2.log(cReth.getAmountIn(leverageAmount, false, 1));

        // call strategy
        uint strategyindex = 0;

        if (
            cReth.getAmountIn(leverageAmount, false, 1) <
            cReth.getAmountIn(leverageAmount, false, 0)
        ) strategyindex = 1;

        console2.log("strategy for open");
        console2.log(strategyindex);
        assertEq(strategyindex, 0);
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
        //vault borrow (should be the same)

        //numa price increase 20%
        uint newRethBalance = numaSupply + (20 * numaSupply) / 100;
        deal({token: address(rEth), to: address(vault), give: newRethBalance});
        // make a swap to increase price
        vm.stopPrank();
        vm.startPrank(deployer);
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams({
                tokenIn: address(rEth),
                tokenOut: address(numa),
                fee: 500,
                recipient: deployer,
                deadline: block.timestamp,
                amountOut: numaPoolReserve / 20, // 5% of reserve should be enough?
                amountInMaximum: type(uint).max,
                sqrtPriceLimitX96: 0
            });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        rEth.approve(address(swapRouter), type(uint).max);
        // ERC20InsufficientAllowance(0xE592427A0AEce92De3Edee1F18E0157C05861564, 36934311772498674553 [3.693e19], 2548408988412747955903073076714761369303 [2.548e39])
        swapRouter.exactOutputSingle(params);
        vm.stopPrank();
        vm.startPrank(userA);
        // check states
        (, ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        console2.log("ltv after");
        console2.log(ltv);

        //close position

        strategyindex = 0;
        if (
            cReth.getAmountIn(borrowrEThBalance, true, 1) <
            cReth.getAmountIn(borrowrEThBalance, true, 0)
        ) strategyindex = 1;

        console2.log("strategy for close");
        console2.log(cReth.getAmountIn(borrowrEThBalance, true, 0));
        console2.log(cReth.getAmountIn(borrowrEThBalance, true, 1));
        console2.log(strategyindex);
        assertEq(strategyindex, 0);
        (uint cnumaAmount, uint swapAmountIn) = cReth.closeLeverageAmount(
            cNuma,
            borrowrEThBalance,
            strategyindex
        );

        cNuma.approve(address(cReth), cnumaAmount);
        cReth.closeLeverageStrategy(cNuma, borrowrEThBalance, strategyindex);

        borrowrEThBalance = cReth.borrowBalanceCurrent(userA);
        console2.log("borrow amount after");
        console2.log(borrowrEThBalance);
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

    function test_LeverageAndCloseProfitStrategyStratVault2() public {
        // user calls leverage x 5
        vm.startPrank(userA);
        address[] memory t = new address[](2);
        t[0] = address(cReth);
        t[1] = address(cNuma);
        comptroller.enterMarkets(t);

        // mint numa so that we can borrow for leverahe
        uint depositAmount = 1000 ether;
        numa.approve(address(cNuma), depositAmount);
        cNuma.mint(depositAmount);

        uint rethBalBefore = rEth.balanceOf(userA);

        uint totalCollateral = providedAmount + leverageAmount;
        rEth.approve(address(cNuma), providedAmount);

        // call strategy
        uint strategyindex = 0;
        cNuma.leverageStrategy(
            providedAmount,
            leverageAmount,
            cReth,
            strategyindex
        );

        // check balances
        // cnuma position
        uint cRethBal = cReth.balanceOf(userA);
        console2.log(cRethBal);

        // //uint exchangeRate = cNuma.exchangeRateStored();
        // Exp memory exchangeRate = Exp({mantissa: cNuma.exchangeRateStored()});

        // uint mintTokens = div_(totalCollateral, exchangeRate);

        // assertEq(cNumaBal, mintTokens);

        // // numa stored in cnuma contract
        // uint numaBal = numa.balanceOf(address(cNuma));
        // assertEq(numaBal, totalCollateral);

        // // borrow balance
        // uint borrowrEThBalance = cReth.borrowBalanceCurrent(userA);

        // console2.log(borrowrEThBalance);

        // (, uint ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        // console2.log("ltv before");
        // console2.log(ltv);
        // // vault borrow (should be the same)

        // // numa price increase 20%
        // uint newRethBalance = numaSupply + (20 * numaSupply) / 100;
        // deal({token: address(rEth), to: address(vault), give: newRethBalance});

        // // check states
        // (, ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        // console2.log("ltv after");
        // console2.log(ltv);

        // // close position
        // // uint borrowrEThBalance2 = cReth.borrowBalanceCurrent(userA);
        // //  console2.log("borrow balance");
        // //  console2.log(borrowrEThBalance);
        // //   console2.log(borrowrEThBalance2);

        // (uint cnumaAmount, uint swapAmountIn) = cReth.closeLeverageAmount(
        //     cNuma,
        //     borrowrEThBalance,
        //     strategyindex
        // );

        // cNuma.approve(address(cReth), cnumaAmount);
        // cReth.closeLeverageStrategy(cNuma, borrowrEThBalance, strategyindex);

        // (, ltv) = comptroller.getAccountLTVIsolate(userA, cNuma, cReth);
        // console2.log("ltv after close");
        // console2.log(ltv);

        // // redeem

        // cNuma.redeem(cNuma.balanceOf(userA));
        // cNumaBal = cNuma.balanceOf(userA);
        // console2.log("cnuma balance after close & redeem");
        // console2.log(cNumaBal);
        // // check balances
        // uint numaBalAfter = numa.balanceOf(userA);
        // if (numaBalAfter > numaBalBefore) {
        //     console2.log("profit");
        //     console2.log(numaBalAfter - numaBalBefore);
        // } else {
        //     console2.log("loss");
        //     console2.log(numaBalBefore - numaBalAfter);
        // }

        vm.stopPrank();
    }

    function prepare_LstBorrowSuppliedLst_JRV4() public {
        vm.startPrank(deployer);
        vault.setMaxBorrow(0);

        cReth._setInterestRateModel(rateModelV4);
        vm.startPrank(userB);
        uint rethAmount = 1000 ether;
        rEth.approve(address(cReth), rethAmount);
        cReth.mint(rethAmount);

        // deposit collateral
        uint depositAmount = 1000 ether;
        vm.startPrank(userA);
        address[] memory t = new address[](1);
        t[0] = address(cNuma);
        comptroller.enterMarkets(t);

        uint numaBalBefore = numa.balanceOf(userA);
        uint rethBalBefore = rEth.balanceOf(userA);
        numa.approve(address(cNuma), depositAmount);
        cNuma.mint(depositAmount);
        assertEq(numaBalBefore - numa.balanceOf(userA), depositAmount);
        assertEq(cNuma.balanceOf(userA), (depositAmount * 50 * 1e8) / 1 ether);

        // borrow reth
        // should revert
        vm.expectRevert();
        cReth.borrow(depositAmount);
        // needs a delta because of pricings (price as colateral vs price as borrow)
        //uint borrowAmount = (depositAmount * (numaCollateralFactor - 0.05 ether))/ 1 ether;
        // around 50% UR
        uint borrowAmount = (depositAmount * numaCollateralFactor) /
            (2 * 1 ether);
        cReth.borrow(borrowAmount);
        assertEq(rEth.balanceOf(userA) - rethBalBefore, borrowAmount);

        // check interest rate
        // per block
        uint estimateBR = rateModelV4.baseRatePerBlock() +
            (borrowAmount * rateModelV4.multiplierPerBlock()) /
            rethAmount;
        assertEq(cReth.borrowRatePerBlock(), estimateBR);

        // todo kink
        // check balances after 1 year to compare per year values
        //vm.warp(block.timestamp + 365* 1 days);
        vm.roll(block.number + blocksPerYear);
        //console2.log(borrowAmount);
        uint borrowBalanceAfter = cReth.borrowBalanceCurrent(userA);

        // not exact because of compounding interests
        //assertApproxEqAbs(borrowBalanceAfter - borrowAmount,((baseRatePerYear+ (borrowAmount*multiplierPerYear)/rethAmount)*borrowAmount)/1 ether,0.0000001 ether);

        // make it liquiditable, check shortfall
        (, uint liquidity, uint shortfall, uint badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
        cReth.borrow((borrowAmount * 8) / 10);
        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
    }

    function test_LstBorrowSuppliedLst_JRV4_liquidateFL() public {
        prepare_LstBorrowSuppliedLst_JRV4();
        vm.roll(block.number + blocksPerYear / 4);
        cReth.accrueInterest();
        (, uint liquidity, uint shortfall, uint badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
        // liquidate

        vm.startPrank(userC);
        uint balC = rEth.balanceOf(userC);
        vault.liquidateLstBorrower(userA, type(uint256).max, true, true);
        console2.log("liquidator profit:", rEth.balanceOf(userC) - balC);

        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
    }

    function test_LstBorrowSuppliedLst_JRV4_liquidateSwap() public {
        prepare_LstBorrowSuppliedLst_JRV4();
        //vm.roll(block.number + blocksPerYear/4);
        //cReth.accrueInterest();
        // make it liquiditable by changing vault fees
        vm.startPrank(deployer);
        vaultManager.setSellFee(0.90 ether);
        (, uint liquidity, uint shortfall, uint badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
        // liquidate

        vm.startPrank(userC);
        rEth.approve(address(vault), rEth.balanceOf(userC));
        uint balC = rEth.balanceOf(userC);
        vault.liquidateLstBorrower(userA, type(uint256).max, true, false);
        console2.log("liquidator profit:", rEth.balanceOf(userC) - balC);

        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
    }

    function test_LstBorrowSuppliedLst_JRV4_liquidateNoSwap() public {
        prepare_LstBorrowSuppliedLst_JRV4();
        //vm.roll(block.number + blocksPerYear/4);
        //cReth.accrueInterest();
        // make it liquiditable by changing vault fees
        vm.startPrank(deployer);
        vaultManager.setSellFee(0.90 ether);
        (, uint liquidity, uint shortfall, uint badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
        // liquidate

        vm.startPrank(userC);
        rEth.approve(address(vault), rEth.balanceOf(userC));
        vault.liquidateLstBorrower(userA, type(uint256).max, false, false);
        console2.log("liquidator profit + input:", numa.balanceOf(userC));

        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
    }

    function test_LstBorrowSuppliedLst_JRV4_liquidateBadDebt() public {
        prepare_LstBorrowSuppliedLst_JRV4();
        //vm.roll(block.number + blocksPerYear/4);
        //cReth.accrueInterest();
        // make it liquiditable by changing vault fees
        vm.startPrank(deployer);
        vaultManager.setSellFee(0.85 ether);
        (, uint liquidity, uint shortfall, uint badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
        // liquidate

        vm.startPrank(userC);
        rEth.approve(address(vault), rEth.balanceOf(userC));
        // bad debt
        vm.expectRevert();
        vault.liquidateLstBorrower(userA, type(uint256).max, false, false);
        vault.liquidateBadDebt(userA, 500, cNuma);

        assertEq(numa.balanceOf(userC), 500 ether);

        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
    }

    function prepare_numaBorrow_JRV4() public {
        vm.startPrank(deployer);
        vault.setMaxBorrow(0);

        vm.startPrank(userB);
        // buy numa
        uint numaAmount = 1000 ether;
        rEth.approve(address(vault), 2 * numaAmount);
        vault.buy(2 * numaAmount, numaAmount, userB);

        numa.approve(address(cNuma), numaAmount);
        cNuma.mint(numaAmount);

        // deposit collateral
        uint depositAmount = 1000 ether;
        vm.startPrank(userA);
        address[] memory t = new address[](1);
        t[0] = address(cReth);
        comptroller.enterMarkets(t);

        uint rethBalBefore = rEth.balanceOf(userA);
        uint numaBalBefore = numa.balanceOf(userA);
        rEth.approve(address(cReth), depositAmount);
        cReth.mint(depositAmount);
        assertEq(rethBalBefore - rEth.balanceOf(userA), depositAmount);
        assertEq(cReth.balanceOf(userA), (depositAmount * 50 * 1e8) / 1 ether);

        // borrow numa
        // should revert
        vm.expectRevert();
        cNuma.borrow(depositAmount);
        // needs a delta because of pricings (price as colateral vs price as borrow)
        //uint borrowAmount = (depositAmount * (numaCollateralFactor - 0.05 ether))/ 1 ether;
        // around 50% UR
        uint borrowAmount = (depositAmount * rEthCollateralFactor) /
            (2 * 1 ether);
        cNuma.borrow(borrowAmount);
        assertEq(numa.balanceOf(userA) - numaBalBefore, borrowAmount);

        // check interest rate
        // per block
        uint estimateBR = rateModelV4.baseRatePerBlock() +
            (borrowAmount * rateModelV4.multiplierPerBlock()) /
            numaAmount;
        assertEq(cNuma.borrowRatePerBlock(), estimateBR);

        // todo kink
        // check balances after 1 year to compare per year values
        //vm.warp(block.timestamp + 365* 1 days);
        vm.roll(block.number + blocksPerYear);
        //console2.log(borrowAmount);
        uint borrowBalanceAfter = cNuma.borrowBalanceCurrent(userA);

        // not exact because of compounding interests
        //assertApproxEqAbs(borrowBalanceAfter - borrowAmount,((baseRatePerYear+ (borrowAmount*multiplierPerYear)/rethAmount)*borrowAmount)/1 ether,0.0000001 ether);

        // make it liquiditable, check shortfall
        (, uint liquidity, uint shortfall, uint badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cReth, cNuma);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
        cNuma.borrow((borrowAmount * 8) / 10);
        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cReth, cNuma);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
    }

    function test_NumaBorrow_JRV4_liquidateFL() public {
        prepare_numaBorrow_JRV4();
        vm.roll(block.number + blocksPerYear / 4);
        cNuma.accrueInterest();
        (, uint liquidity, uint shortfall, uint badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cReth, cNuma);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
        // liquidate

        vm.startPrank(userC);
        uint balC = numa.balanceOf(userC);

        vault.liquidateNumaBorrower(userA, type(uint256).max, true, true);
        console2.log("liquidator profit:", numa.balanceOf(userC) - balC);

        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cReth, cNuma);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
    }

    function test_NumaBorrow_JRV4_liquidateSwap() public {
        prepare_numaBorrow_JRV4();
        vm.roll(block.number + blocksPerYear / 4);
        cNuma.accrueInterest();
        (, uint liquidity, uint shortfall, uint badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cReth, cNuma);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
        // liquidate

        vm.startPrank(userC);
        uint balC = numa.balanceOf(userC);

        uint numaAmountBuy = 1000 ether;
        rEth.approve(address(vault), 2 * numaAmountBuy);
        vault.buy(2 * numaAmountBuy, numaAmountBuy, userC);

        numa.approve(address(vault), numa.balanceOf(userC));
        vault.liquidateNumaBorrower(userA, type(uint256).max, true, false);
        console2.log("liquidator profit:", numa.balanceOf(userC) - balC);

        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cReth, cNuma);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
    }

    function test_NumaBorrow_JRV4_liquidateNoSwap() public {
        prepare_numaBorrow_JRV4();
        vm.roll(block.number + blocksPerYear / 4);
        cNuma.accrueInterest();
        (, uint liquidity, uint shortfall, uint badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cReth, cNuma);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
        // liquidate

        vm.startPrank(userC);

        uint numaAmountBuy = 1000 ether;
        rEth.approve(address(vault), 2 * numaAmountBuy);
        vault.buy(2 * numaAmountBuy, numaAmountBuy, userC);

        uint balC = rEth.balanceOf(userC);
        numa.approve(address(vault), numa.balanceOf(userC));
        vault.liquidateNumaBorrower(userA, type(uint256).max, false, false);
        console2.log("liquidator profit:", rEth.balanceOf(userC) - balC);

        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cReth, cNuma);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
    }

    function test_NumaBorrow_JRV4_liquidateBadDebt() public {
        prepare_numaBorrow_JRV4();
        // make it bad debt
        // vm.roll(block.number + blocksPerYear/4);
        // cNuma.accrueInterest();
        vm.startPrank(deployer);
        vaultManager.setBuyFee(0.85 ether);

        (, uint liquidity, uint shortfall, uint badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cReth, cNuma);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
        // liquidate

        vm.startPrank(userC);

        uint numaAmountBuy = 1000 ether;
        rEth.approve(address(vault), 2 * numaAmountBuy);
        vault.buy(2 * numaAmountBuy, numaAmountBuy, userC);

        uint balC = rEth.balanceOf(userC);
        numa.approve(address(vault), numa.balanceOf(userC));
        vm.expectRevert();
        vault.liquidateNumaBorrower(userA, type(uint256).max, false, false);

        vault.liquidateBadDebt(userA, 1000, cReth);
        console2.log("liquidator profit:", rEth.balanceOf(userC) - balC);

        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cReth, cNuma);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
    }

    function prepare_LstBorrowLstVault_JRV4() public {
        vm.startPrank(deployer);
        vault.setMaxBorrow(0);
        cReth._setInterestRateModel(rateModelV4);

        // deposit collateral
        uint depositAmount = 1000 ether;
        vm.startPrank(userA);
        address[] memory t = new address[](1);
        t[0] = address(cNuma);
        comptroller.enterMarkets(t);

        uint numaBalBefore = numa.balanceOf(userA);
        uint rethBalBefore = rEth.balanceOf(userA);
        numa.approve(address(cNuma), depositAmount);
        cNuma.mint(depositAmount);
        assertEq(numaBalBefore - numa.balanceOf(userA), depositAmount);
        assertEq(cNuma.balanceOf(userA), (depositAmount * 50 * 1e8) / 1 ether);

        // borrow reth
        // should revert not enough collat
        vm.expectRevert();
        cReth.borrow(depositAmount);
        // needs a delta because of pricings (price as colateral vs price as borrow)
        //uint borrowAmount = (depositAmount * (numaCollateralFactor - 0.05 ether))/ 1 ether;
        // around 50% UR
        uint borrowAmount = (depositAmount * numaCollateralFactor) /
            (2 * 1 ether);
        // should revert because maxborrow = 0
        vm.expectRevert();
        cReth.borrow(borrowAmount);

        vm.startPrank(deployer);
        vault.setMaxBorrow(100000000 ether);

        vm.startPrank(userA);
        cReth.borrow(borrowAmount);
        assertEq(rEth.balanceOf(userA) - rethBalBefore, borrowAmount);

        // check interest rate
        // per block
        console2.log("TEST");
        console2.log(borrowAmount);
        console2.log(borrowAmount + rEth.balanceOf(address(vault)));

        console2.log("multiplierPerBlock2", rateModelV4.multiplierPerBlock());
        console2.log("baseRatePerBlock2", rateModelV4.baseRatePerBlock());
        uint util = (borrowAmount * 1 ether) /
            (borrowAmount + rEth.balanceOf(address(vault)));

        console2.log("util2", util);
        uint estimateBR = rateModelV4.baseRatePerBlock() +
            (borrowAmount * rateModelV4.multiplierPerBlock()) /
            (borrowAmount + rEth.balanceOf(address(vault)));
        assertEq(cReth.borrowRatePerBlock(), estimateBR);

        // todo kink
        // check balances after 1 year to compare per year values
        //vm.warp(block.timestamp + 365* 1 days);
        vm.roll(block.number + blocksPerYear);
        //console2.log(borrowAmount);
        uint borrowBalanceAfter = cReth.borrowBalanceCurrent(userA);

        // not exact because of compounding interests
        //assertApproxEqAbs(borrowBalanceAfter - borrowAmount,((baseRatePerYear+ (borrowAmount*multiplierPerYear)/rethAmount)*borrowAmount)/1 ether,0.0000001 ether);

        // make it liquiditable, check shortfall
        (, uint liquidity, uint shortfall, uint badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
        cReth.borrow((borrowAmount * 8) / 10);
        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
    }

    function test_LstBorrowLstVault_JRV4_liquidateFL() public {
        prepare_LstBorrowLstVault_JRV4();
        vm.startPrank(deployer);

        // not liquiditable
        //vault.setMaxBorrow(200 ether);
        // bad debt
        //vault.setMaxBorrow(100 ether);
        // TODO: confirm these 3 values
        vault.setMaxBorrow(150 ether);

        vm.roll(block.number + blocksPerYear / 4);
        cReth.accrueInterest();
        (, uint liquidity, uint shortfall, uint badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
        // liquidate

        vm.startPrank(userC);
        uint balC = rEth.balanceOf(userC);
        vault.liquidateLstBorrower(userA, type(uint256).max, true, true);
        console2.log("liquidator profit:", rEth.balanceOf(userC) - balC);

        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
    }

    function test_LstBorrowLstVault_JRV4_liquidateSwap() public {
        prepare_LstBorrowLstVault_JRV4();
        //vm.roll(block.number + blocksPerYear/4);
        //cReth.accrueInterest();
        // make it liquiditable by changing vault fees
        vm.startPrank(deployer);
        vaultManager.setSellFee(0.90 ether);
        (, uint liquidity, uint shortfall, uint badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
        // liquidate

        vm.startPrank(userC);
        rEth.approve(address(vault), rEth.balanceOf(userC));
        uint balC = rEth.balanceOf(userC);
        vault.liquidateLstBorrower(userA, type(uint256).max, true, false);
        console2.log("liquidator profit:", rEth.balanceOf(userC) - balC);

        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
    }

    function test_LstBorrowLstVault_JRV4_liquidateNoSwap() public {
        prepare_LstBorrowLstVault_JRV4();
        //vm.roll(block.number + blocksPerYear/4);
        //cReth.accrueInterest();
        // make it liquiditable by changing vault fees
        vm.startPrank(deployer);
        vaultManager.setSellFee(0.90 ether);
        (, uint liquidity, uint shortfall, uint badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
        // liquidate

        vm.startPrank(userC);
        rEth.approve(address(vault), rEth.balanceOf(userC));
        vault.liquidateLstBorrower(userA, type(uint256).max, false, false);
        console2.log("liquidator profit + input:", numa.balanceOf(userC));

        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
    }

    function test_LstBorrowLstVault_JRV4_liquidateBadDebt() public {
        prepare_LstBorrowLstVault_JRV4();
        //vm.roll(block.number + blocksPerYear/4);
        //cReth.accrueInterest();
        // make it liquiditable by changing vault fees
        vm.startPrank(deployer);
        vaultManager.setSellFee(0.85 ether);
        (, uint liquidity, uint shortfall, uint badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
        // liquidate

        vm.startPrank(userC);
        rEth.approve(address(vault), rEth.balanceOf(userC));
        // bad debt
        vm.expectRevert();
        vault.liquidateLstBorrower(userA, type(uint256).max, false, false);
        vault.liquidateBadDebt(userA, 500, cNuma);

        assertEq(numa.balanceOf(userC), 500 ether);

        (, liquidity, shortfall, badDebt) = comptroller
            .getAccountLiquidityIsolate(userA, cNuma, cReth);
        console2.log(liquidity);
        console2.log(shortfall);
        console2.log(badDebt);
    }
}
