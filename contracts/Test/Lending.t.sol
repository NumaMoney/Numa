// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/console2.sol";
import {Setup} from "./utils/SetupDeployNuma_Arbitrum.sol";
import "../lending/ExponentialNoError.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
//import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "./uniV3Interfaces/ISwapRouter.sol";
import {NumaLeverageLPSwap} from "../lending/NumaLeverageLPSwap.sol";
import "../lending/INumaLeverageStrategy.sol";

contract LendingTest is Setup, ExponentialNoError {
    uint providedAmount = 10 ether;
    uint leverageAmount = 40 ether;

    uint numaPoolReserve;
    uint rEthPoolReserve;
    function setUp() public virtual override {
        console2.log("LENDING TEST");
        super.setUp();

        // set reth vault balance so that 1 numa = 1 rEth
        deal({token: address(rEth), to: address(vault), give: numaSupply});
        // numa/reth pool reserves
        numaPoolReserve = numa.totalSupply() / 1000;
        rEthPoolReserve = rEth.balanceOf(address(vault)) / 1000;

        deal({token: address(rEth), to: deployer, give: 10000*rEthPoolReserve});
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
            numa,
            rEthAmountPool,
            NumaAmountPool
        );

        // check price
        //Spot price of the token
        (uint160 sqrtPriceX96Spot, , , , , , ) = IUniswapV3Pool(NUMA_RETH_POOL_ADDRESS)
            .slot0();

        uint256 numerator = sqrtPriceX96Spot;


        uint256 denominator = FixedPoint96.Q96;
        uint256 price = FullMath.mulDivRoundingUp(
                        numerator,
                        numerator * 10 ** 18,
                        denominator*denominator
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
        console2.log("vault balance",rEth.balanceOf(address(vault)));
        console2.log("vault debt",vault.getDebt());

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
        console2.log("vault balance 2",rEth.balanceOf(address(vault)));
        console2.log("vault debt 2",vault.getDebt());
       
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
        console2.log("vault balance 3",rEth.balanceOf(address(vault)));
        console2.log("vault debt 3",vault.getDebt());
       
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
        console2.log("vault balance 4",rEth.balanceOf(address(vault)));
        console2.log("vault debt 4",vault.getDebt());

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
        console2.log("vault balance 5",rEth.balanceOf(address(vault)));
        console2.log("vault debt 5",vault.getDebt());

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
                amountOut: numaPoolReserve/4,// 25% of reserve should be enough?
                amountInMaximum: type(uint).max,
                sqrtPriceLimitX96: 0
            });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        rEth.approve(address(swapRouter),type(uint).max);
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
        console2.log(cReth.getAmountIn(leverageAmount,false,0));
        console2.log(cReth.getAmountIn(leverageAmount,false,1));



        // call strategy
        uint strategyindex = 0;

        if (cReth.getAmountIn(leverageAmount,false,1) < cReth.getAmountIn(leverageAmount,false,0))
            strategyindex = 1;

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
                amountOut: numaPoolReserve/4,// 25% of reserve should be enough?
                amountInMaximum: type(uint).max,
                sqrtPriceLimitX96: 0
            });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        rEth.approve(address(swapRouter),type(uint).max);
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
        if (cReth.getAmountIn(borrowrEThBalance,true,1) < cReth.getAmountIn(borrowrEThBalance,true,0))
            strategyindex = 1;

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

        vaultManager.setBuyFee(0.996 ether);// 0.4%

        vm.startPrank(userA);

        console2.log("comparing strategies: amount to borrow");
        console2.log(cReth.getAmountIn(leverageAmount,false,0));
        console2.log(cReth.getAmountIn(leverageAmount,false,1));



        // call strategy
        uint strategyindex = 0;

        if (cReth.getAmountIn(leverageAmount,false,1) < cReth.getAmountIn(leverageAmount,false,0))
            strategyindex = 1;

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
                amountOut: numaPoolReserve/20,// 5% of reserve should be enough?
                amountInMaximum: type(uint).max,
                sqrtPriceLimitX96: 0
            });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        rEth.approve(address(swapRouter),type(uint).max);
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
        if (cReth.getAmountIn(borrowrEThBalance,true,1) < cReth.getAmountIn(borrowrEThBalance,true,0))
            strategyindex = 1;

        console2.log("strategy for close");
        console2.log(cReth.getAmountIn(borrowrEThBalance,true,0));
        console2.log(cReth.getAmountIn(borrowrEThBalance,true,1));
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
}
