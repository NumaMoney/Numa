// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/console2.sol";
//
import "../interfaces/IVaultManager.sol";
import "../NumaProtocol/NumaOracle.sol";
//
import "./uniV3Interfaces/ISwapRouter.sol";

//
import {Setup, FEE_LOW} from "./utils/SetupDeployNuma_Arbitrum.sol";


contract PrinterTest is Setup {
    uint numaPriceVault;
    uint numaPriceVaultS;
    uint numaPriceVaultB;
    uint numaPricePoolL;
    uint numaPricePoolH;
    uint numaPricePoolSpot;

    function setUp() public virtual override {
        console2.log("PRINTER TEST");
        super.setUp();

        // numa price from vault should equal price from pool
        numaPriceVault = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.NoFeePrice
        );
        numaPriceVaultS = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.SellPrice
        );
        numaPriceVaultB = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.BuyPrice
        );
        numaPricePoolL = NumaOracle(address(numaOracle)).getV3LowestPrice(
            NUMA_USDC_POOL_ADDRESS,
            1 ether
        );
        numaPricePoolH = NumaOracle(address(numaOracle)).getV3HighestPrice(
            NUMA_USDC_POOL_ADDRESS,
            1 ether
        );

        numaPricePoolSpot = NumaOracle(address(numaOracle)).getV3SpotPrice(
            NUMA_USDC_POOL_ADDRESS,
            1 ether
        );

        // pool price in USD 1e18
        numaPricePoolL = numaPricePoolL * 10 ** 12;
        numaPricePoolH = numaPricePoolH * 10 ** 12;
        numaPricePoolSpot = numaPricePoolSpot * 10 ** 12;
        console2.log("pool price HIGH", numaPricePoolH);
        console2.log("pool price LOW", numaPricePoolL);
        console2.log("pool price SPOT", numaPricePoolSpot);
        console2.log("vault price SELL", numaPriceVaultS);
        console2.log("vault price BUY", numaPriceVaultB);
        console2.log("vault price ", numaPriceVault);

        // coverage
        nuAssetMgr.changeSequencerUptimeFeedAddress(UPTIME_FEED_ARBI);
        //
        address[] memory nuAssets = nuAssetMgr.getNuAssetList();
        assertEq(nuAssets.length,2);
        address nuAsset1 = nuAssets[0];
        nuAssetMgr.removeNuAsset(nuAsset1);
        nuAssets = nuAssetMgr.getNuAssetList();
        assertEq(nuAssets.length,1);
        assertEq(nuAsset1,address(nuUSD));

        nuAssetMgr.addNuAsset(
            address(nuUSD),
            PRICEFEEDETHUSD_ARBI,
            HEART_BEAT_CUSTOM
        );
        nuAssets = nuAssetMgr.getNuAssetList();
        assertEq(nuAssets.length,2);
        nuAssetMgr.updateNuAsset(address(nuUSD),
            PRICEFEEDETHUSD_ARBI,
            HEART_BEAT_CUSTOM
        );
    }

    function test_CheckSetup() public view {
        //
        uint numaPriceVaultUSD = (numaPriceVault * uint(ethusd)) / 1e8;
        assertApproxEqAbs(numaPriceVaultUSD, 0.5 ether, 10000); // TODO why the diff
        // spot price is not equal to TWAPS...
        // assertEq(numaPricePoolL,numaPricePoolH,"pool price ko");
        assertApproxEqAbs(
            numaPricePoolL,
            numaPricePoolH,
            0.0001 ether,
            "pool price ko"
        );
        assertApproxEqAbs(
            numaPriceVaultUSD,
            numaPricePoolL,
            0.0001 ether,
            "vault & pool don't match"
        );

    }

    function test_getNbOfNuAssetFromNuma() external {
        vm.stopPrank();
        // vm.startPrank(deployer);
        // moneyPrinter.setPrintAssetFeeBps(0);
        //vm.stopPrank();
        vm.startPrank(userA);

        uint numaAmount = 100000000e18;

        // compare getNbOfNuAssetFromNuma
        (uint256 nuUSDAmount, uint fee) = moneyPrinter.getNbOfNuAssetFromNuma(
            address(nuUSD),
            numaAmount
        );

        uint feeEstim = (numaAmount * moneyPrinter.printAssetFeeBps()) / 10000;
        assertEq(fee, feeEstim, "fee ko");
        console2.log("nuUSD would be minted given NUMA: ", nuUSDAmount);
        uint nuUSDAmountEstim = (NumaOracle(address(numaOracle))
            .getV3LowestPrice(NUMA_USDC_POOL_ADDRESS, numaAmount - feeEstim) *
            1e12 *
            uint(usdcusd)) / (1e8);
        assertApproxEqAbs(
            nuUSDAmount,
            nuUSDAmountEstim,
            0.0001 ether,
            "amount ko"
        );

        // synth scaling
        forceSynthDebasing();
        (uint256 nuUSDAmount2, uint fee2) = moneyPrinter.getNbOfNuAssetFromNuma(
            address(nuUSD),
            numaAmount
        );
        // should not change anything
        assertEq(fee2, fee, "fee ko");
        assertEq(nuUSDAmount2, nuUSDAmount, "fee ko");

        // synth scaling critical debase
        forceSynthDebasingCritical();
        // should not change anything
        (nuUSDAmount2, fee2) = moneyPrinter.getNbOfNuAssetFromNuma(
            address(nuUSD),
            numaAmount
        );
        assertEq(fee2, fee, "fee ko");
        assertEq(nuUSDAmount2, nuUSDAmount, "fee ko");
    }

    function test_getNbOfNumaNeededAndFee() external {
        vm.stopPrank();
        vm.startPrank(userA);

        uint nuUsdAmount = 1000000000e18;

        // compare getNbOfNuAssetFromNuma
        (uint numaNeeded, uint fee) = moneyPrinter.getNbOfNumaNeededAndFee(
            address(nuUSD),
            nuUsdAmount
        );
        console2.log("numa needed: ", numaNeeded);

        uint feeEstim = (numaNeeded * moneyPrinter.printAssetFeeBps()) / 10000;
        assertEq(fee, feeEstim, "fee ko");

        (uint256 nuUSDAmount2, uint fee2) = moneyPrinter.getNbOfNuAssetFromNuma(
            address(nuUSD),
            numaNeeded
        );
        assertEq(fee, fee2, "fee ko");
        assertApproxEqAbs(nuUSDAmount2, nuUsdAmount, 0.001 ether, "amount ko");

        // synth scaling
        forceSynthDebasing();
        (uint numaNeeded2, uint fee3) = moneyPrinter.getNbOfNumaNeededAndFee(
            address(nuUSD),
            nuUsdAmount
        );
        // should not change anything
        assertEq(fee3, fee, "fee ko");
        assertEq(numaNeeded2, numaNeeded, "fee ko");

        // synth scaling critical debase
        forceSynthDebasingCritical();
        (numaNeeded2, fee3) = moneyPrinter.getNbOfNumaNeededAndFee(
            address(nuUSD),
            nuUsdAmount
        );
        // should not change anything
        assertEq(fee3, fee, "fee ko");
        assertEq(numaNeeded2, numaNeeded, "fee ko");
    }

    function test_getNbOfNumaFromAssetWithFee() external {
        vm.stopPrank();
        vm.startPrank(userA);

        uint nuUsdAmount = 1000000000e18;

        // compare getNbOfNuAssetFromNuma
        (uint numaOut, uint fee) = moneyPrinter.getNbOfNumaFromAssetWithFee(
            address(nuUSD),
            nuUsdAmount
        );
        console2.log("numa out: ", numaOut);

        uint numaOutNoFee = (numaOut * 10000) /
            (10000 - moneyPrinter.burnAssetFeeBps());
        uint feeEstim = numaOutNoFee - numaOut;
        assertEq(fee, feeEstim, "fee ko");

        console2.log("numa would be minted given nuasset: ", numaOut);
        uint nuUSDAmountEstim = (NumaOracle(address(numaOracle))
            .getV3HighestPrice(NUMA_USDC_POOL_ADDRESS, numaOutNoFee) *
            1e12 *
            uint(usdcusd)) / (1e8);
        assertApproxEqAbs(
            nuUsdAmount,
            nuUSDAmountEstim,
            0.0001 ether,
            "amount ko"
        );

        // synth scaling
        forceSynthDebasing();

        // as the mint made price from the vault increase, the burning price will change
        // for this test, I will artificially decrease price from the vault
        numa.mint(deployer, 10000000 ether);

        (uint numaOut2, uint fee2) = moneyPrinter.getNbOfNumaFromAssetWithFee(
            address(nuUSD),
            nuUsdAmount
        );

        // to compare, we scale amount with fees
        uint totalOut = numaOut + fee;
        totalOut = (totalOut * 800) / 1000;
        uint feeEstim2 = (totalOut * (moneyPrinter.burnAssetFeeBps())) / 10000;

        assertEq(numaOut2, totalOut - feeEstim2, "amount ko");
        assertEq(fee2, feeEstim2, "fee ko");

        // synth scaling critical debase
        forceSynthDebasingCritical();
        (numaOut2, fee2) = moneyPrinter.getNbOfNumaFromAssetWithFee(
            address(nuUSD),
            nuUsdAmount
        );

        // compute critical debase factor
        uint criticalDebaseFactor = (vaultManager.getGlobalCF() * 1000) /
            vaultManager.cf_critical();
        // we apply this multiplier on the factor for when it's used on synthetics burning price
        criticalDebaseFactor =
            (criticalDebaseFactor * 1000) /
            vaultManager.criticalDebaseMult();
        assertLt(criticalDebaseFactor, 1000);
        (uint scaleSynthBurn2, ) = vaultManager.getSynthScalingUpdate();
        assertEq(scaleSynthBurn2, criticalDebaseFactor);
        totalOut = numaOut + fee;
        totalOut = (criticalDebaseFactor * totalOut) / 1000;
        feeEstim2 = (totalOut * (moneyPrinter.burnAssetFeeBps())) / 10000;

        assertEq(numaOut2, totalOut - feeEstim2, "amount ko");
        assertEq(fee2, feeEstim2, "fee ko");
    }

    function test_getNbOfnuAssetNeededForNuma() external {
        vm.stopPrank();
        vm.startPrank(userA);

        uint numaAmount = 100000000e18;

        // compare getNbOfNuAssetFromNuma
        (uint256 nuUSDAmount, uint fee) = moneyPrinter
            .getNbOfnuAssetNeededForNuma(address(nuUSD), numaAmount);
        console2.log("nuUSD needed given NUMA: ", nuUSDAmount);

        uint numaOutNoFee = (numaAmount * 10000) /
            (10000 - moneyPrinter.burnAssetFeeBps());
        uint feeEstim = numaOutNoFee - numaAmount;
        assertEq(fee, feeEstim, "fee ko");

        (uint numaOut, uint fee2) = moneyPrinter.getNbOfNumaFromAssetWithFee(
            address(nuUSD),
            nuUSDAmount
        );
        assertApproxEqAbs(fee, fee2, 0.0001 ether, "fee ko");
        assertApproxEqAbs(numaOut, numaAmount, 0.001 ether, "amount ko");

        // synth scaling
        forceSynthDebasing();

        // as the mint made price from the vault increase, the burning price will change
        // for this test, I will artificially decrease price from the vault
        numa.mint(deployer, 10000000 ether);

        (uint256 nuUSDAmount2, ) = moneyPrinter.getNbOfnuAssetNeededForNuma(
            address(nuUSD),
            numaAmount
        );

        assertGt(nuUSDAmount2, nuUSDAmount, "amount ko 1");
        // synth scaling critical debase
        forceSynthDebasingCritical();
        (uint256 nuUSDAmount3, ) = moneyPrinter.getNbOfnuAssetNeededForNuma(
            address(nuUSD),
            numaAmount
        );

        assertGt(nuUSDAmount3, nuUSDAmount2, "amount ko 2");
    }

    function test_getNbOfNuAssetFromNuAsset() external {
        vm.stopPrank();
        vm.startPrank(userA);

        uint nuUsdAmount = 100000e18;

        // compare getNbOfNuAssetFromNuma
        (uint nuBTCOut, uint fee) = moneyPrinter.getNbOfNuAssetFromNuAsset(
            address(nuUSD),
            address(nuBTC),
            nuUsdAmount
        );
        console2.log("nuBTC out: ", nuBTCOut);

        uint feeEstim = (moneyPrinter.swapAssetFeeBps() * nuUsdAmount) / 10000;
        uint nuBtcEstim = ((nuUsdAmount - feeEstim) * 1e8) / uint(btcusd);

        console2.log(btcusd);
        console2.log(btceth);
        console2.log(ethusd);
        uint nuBtcEstim2 = ((nuUsdAmount - feeEstim) * 1e18 * 1e8) /
            (uint(btceth) * uint(ethusd));
        assertEq(fee, feeEstim, "fee nuusd ko");
        // KO
        //assertApproxEqAbs(nuBTCOut,nuBtcEstim,0.001 ether);
        assertApproxEqAbs(nuBTCOut, nuBtcEstim2, 0.00001 ether);
    }

    function test_getNbOfNuAssetNeededForNuAsset() external {
        vm.stopPrank();
        vm.startPrank(userA);

        uint nuBTCAmount = 100e18;

        // compare getNbOfNuAssetFromNuma
        (uint256 nuUSDAmount, uint fee0) = moneyPrinter
            .getNbOfNuAssetNeededForNuAsset(
                address(nuUSD),
                address(nuBTC),
                nuBTCAmount
            );

        (uint nuBTCOut, uint fee1) = moneyPrinter.getNbOfNuAssetFromNuAsset(
            address(nuUSD),
            address(nuBTC),
            nuUSDAmount
        );

        assertApproxEqAbs(nuBTCOut, nuBTCAmount, 0.000000001 ether);
        assertEq(fee0, fee1);
    }

    function test_mintAssetFromNumaInput() public {
        uint numaAmount = 1000001e18;

        vm.startPrank(deployer);
        numa.transfer(userA, numaAmount);

        vm.stopPrank();
        // vm.startPrank(deployer);
        // moneyPrinter.setPrintAssetFeeBps(0);
        //vm.stopPrank();
        vm.startPrank(userA);

        // compare getNbOfNuAssetFromNuma
        (uint256 nuUSDAmount, uint fee) = moneyPrinter.getNbOfNuAssetFromNuma(
            address(nuUSD),
            numaAmount
        );
        numa.approve(address(moneyPrinter), numaAmount);

        // warning cf test block mint
        uint globalCF = vaultManager.getGlobalCF();

        vm.startPrank(deployer);
        vaultManager.setScalingParameters(
            vaultManager.cf_critical(),
            globalCF + 1,
            vaultManager.cf_severe(),
            vaultManager.debaseValue(),
            vaultManager.rebaseValue(),
            1 hours,
            2 hours,
            vaultManager.minimumScale(),
            vaultManager.criticalDebaseMult()
        );
        vm.startPrank(userA);
        vm.expectRevert("minting forbidden");
        moneyPrinter.mintAssetFromNumaInput(
            address(nuUSD),
            numaAmount,
            nuUSDAmount,
            userA
        );
        // put back warning cf
        vm.startPrank(deployer);
        vaultManager.setScalingParameters(
            vaultManager.cf_critical(),
            globalCF - 1,
            vaultManager.cf_severe(),
            vaultManager.debaseValue(),
            vaultManager.rebaseValue(),
            1 hours,
            2 hours,
            vaultManager.minimumScale(),
            vaultManager.criticalDebaseMult()
        );
        vm.startPrank(userA);
        // slippage test
        vm.expectRevert("min amount");
        moneyPrinter.mintAssetFromNumaInput(
            address(nuUSD),
            numaAmount,
            nuUSDAmount + 1,
            userA
        );

        // pause test
        vm.stopPrank();
        vm.startPrank(deployer);
        moneyPrinter.pause();
        vm.stopPrank();
        vm.startPrank(userA);
        vm.expectRevert(bytes4(0xd93c0665));
        moneyPrinter.mintAssetFromNumaInput(
            address(nuUSD),
            numaAmount,
            nuUSDAmount,
            userA
        );
        vm.stopPrank();
        vm.startPrank(deployer);
        moneyPrinter.unpause();
        vm.stopPrank();
        vm.startPrank(userA);

        // slippage ok
        uint balnuUSD = nuUSD.balanceOf(userA);
        uint balnuma = numa.balanceOf(userA);

        moneyPrinter.mintAssetFromNumaInput(
            address(nuUSD),
            numaAmount,
            nuUSDAmount,
            userA
        );
        uint balnuUSDAfter = nuUSD.balanceOf(userA);
        uint balnumaAfter = numa.balanceOf(userA);
        assertEq(balnuUSDAfter - balnuUSD, nuUSDAmount);
        assertEq(balnuma - balnumaAfter, numaAmount);

        // 60% of the fees sent to fee address
        uint feeSentEstim = (fee * 6000) / 10000;

        // 40% burn
        uint burntAmount = numaAmount;

        uint numaBal = numa.balanceOf(feeAddressPrinter);
        assertEq(numaBal, feeSentEstim);
        assertEq(numa.totalSupply(), numaSupply - burntAmount + feeSentEstim);
    }

    function test_mintAssetOutputFromNuma() public {
        vm.startPrank(deployer);
        numa.transfer(userA, 500000 ether);

        uint nuAssetamount = 100001 ether;
        vm.stopPrank();
        // vm.startPrank(deployer);
        // moneyPrinter.setPrintAssetFeeBps(0);
        //vm.stopPrank();
        vm.startPrank(userA);
        // how much numa should we burn to get this nuAsset amount
        uint256 numaCost;
        uint256 numaFee;
        (numaCost, numaFee) = moneyPrinter.getNbOfNumaNeededAndFee(
            address(nuUSD),
            nuAssetamount
        );

        numa.approve(address(moneyPrinter), numaCost);

        // warning cf test block mint
        uint globalCF = vaultManager.getGlobalCF();

        vm.startPrank(deployer);
        vaultManager.setScalingParameters(
            vaultManager.cf_critical(),
            globalCF + 1,
            vaultManager.cf_severe(),
            vaultManager.debaseValue(),
            vaultManager.rebaseValue(),
            1 hours,
            2 hours,
            vaultManager.minimumScale(),
            vaultManager.criticalDebaseMult()
        );
        vm.startPrank(userA);
        vm.expectRevert("minting forbidden");
        moneyPrinter.mintAssetOutputFromNuma(
            address(nuUSD),
            nuAssetamount,
            numaCost,
            userA
        );
        // put back warning level
        vm.startPrank(deployer);
        vaultManager.setScalingParameters(
            vaultManager.cf_critical(),
            globalCF - 1,
            vaultManager.cf_severe(),
            vaultManager.debaseValue(),
            vaultManager.rebaseValue(),
            1 hours,
            2 hours,
            vaultManager.minimumScale(),
            vaultManager.criticalDebaseMult()
        );
        vm.startPrank(userA);
        // slippage test
        vm.expectRevert("max numa");
        moneyPrinter.mintAssetOutputFromNuma(
            address(nuUSD),
            nuAssetamount,
            numaCost - 1,
            userA
        );
        // slippage ok
        uint balnuUSD = nuUSD.balanceOf(userA);
        uint balnuma = numa.balanceOf(userA);
        moneyPrinter.mintAssetOutputFromNuma(
            address(nuUSD),
            nuAssetamount,
            numaCost,
            userA
        );
        uint balnuUSDAfter = nuUSD.balanceOf(userA);
        uint balnumaAfter = numa.balanceOf(userA);
        assertEq(balnuUSDAfter - balnuUSD, nuAssetamount);
        assertEq(balnuma - balnumaAfter, numaCost);

        // 60% of the fees sent to fee address
        uint feeSentEstim = (numaFee * 6000) / 10000;

        // 40% burn
        uint burntAmount = numaCost;

        uint numaBal = numa.balanceOf(feeAddressPrinter);
        assertEq(numaBal, feeSentEstim);
        assertEq(numa.totalSupply(), numaSupply - burntAmount + feeSentEstim);
    }

    function test_burnAssetInputToNuma() public {
        vm.startPrank(deployer);
        numa.transfer(userA, 500000 ether);

        uint nuAssetAmount = 10001 ether;
        vm.stopPrank();
        // vm.startPrank(deployer);
        // moneyPrinter.setPrintAssetFeeBps(0);
        //vm.stopPrank();
        vm.startPrank(userA);
        // mint some to be able to burn
        numa.approve(address(moneyPrinter), 500000 ether);
        moneyPrinter.mintAssetOutputFromNuma(
            address(nuUSD),
            nuAssetAmount,
            500000 ether,
            userA
        );

        uint256 _output;
        uint256 amountToBurn;
        (_output, amountToBurn) = moneyPrinter.getNbOfNumaFromAssetWithFee(
            address(nuUSD),
            nuAssetAmount
        );
        nuUSD.approve(address(moneyPrinter), nuAssetAmount);

        // warning cf test not blocking burn
        uint globalCF = vaultManager.getGlobalCF();

        vm.startPrank(deployer);
        vaultManager.setScalingParameters(
            vaultManager.cf_critical(),
            globalCF + 1,
            vaultManager.cf_severe(),
            vaultManager.debaseValue(),
            vaultManager.rebaseValue(),
            1 hours,
            2 hours,
            vaultManager.minimumScale(),
            vaultManager.criticalDebaseMult()
        );
        vm.startPrank(userA);

        // slippage test
        vm.expectRevert("minimum amount");
        moneyPrinter.burnAssetInputToNuma(
            address(nuUSD),
            nuAssetAmount,
            _output + 1,
            userA
        );
        // slippage ok
        uint balnuUSD = nuUSD.balanceOf(userA);
        uint balnuma = numa.balanceOf(userA);
        uint numaBalBefore = numa.balanceOf(feeAddressPrinter);
        uint supplyBefore = numa.totalSupply();
        moneyPrinter.burnAssetInputToNuma(
            address(nuUSD),
            nuAssetAmount,
            _output,
            userA
        );
        uint balnuUSDAfter = nuUSD.balanceOf(userA);
        uint balnumaAfter = numa.balanceOf(userA);
        assertEq(balnuUSD - balnuUSDAfter, nuAssetAmount);
        assertEq(balnumaAfter - balnuma, _output);

        // 60% of the fees sent to fee address
        uint feeSentEstim = (amountToBurn * 6000) / 10000;

        uint numaBal = numa.balanceOf(feeAddressPrinter);
        assertEq(numaBal - numaBalBefore, feeSentEstim, "fee sent ko");
        assertEq(
            numa.totalSupply(),
            supplyBefore + _output + feeSentEstim,
            "supply ko"
        );
    }

    function test_burnAssetToNumaOutput() public {
        vm.startPrank(deployer);
        numa.transfer(userA, 500000 ether);

        uint numaAmount = 10001 ether;
        vm.stopPrank();
        // vm.startPrank(deployer);
        // moneyPrinter.setPrintAssetFeeBps(0);
        //vm.stopPrank();
        vm.startPrank(userA);
        // mint some to be able to burn
        numa.approve(address(moneyPrinter), 500000 ether);
        moneyPrinter.mintAssetOutputFromNuma(
            address(nuUSD),
            numaAmount * 3,
            500000 ether,
            userA
        );

        (uint256 nuUSDAmount, uint fee) = moneyPrinter
            .getNbOfnuAssetNeededForNuma(address(nuUSD), numaAmount);

        nuUSD.approve(address(moneyPrinter), nuUSDAmount);

        // warning cf test not blocking burn
        uint globalCF = vaultManager.getGlobalCF();

        vm.startPrank(deployer);
        vaultManager.setScalingParameters(
            vaultManager.cf_critical(),
            globalCF + 1,
            vaultManager.cf_severe(),
            vaultManager.debaseValue(),
            vaultManager.rebaseValue(),
            1 hours,
            2 hours,
            vaultManager.minimumScale(),
            vaultManager.criticalDebaseMult()
        );
        vm.startPrank(userA);

        // slippage test
        vm.expectRevert("max amount");
        moneyPrinter.burnAssetToNumaOutput(
            address(nuUSD),
            numaAmount,
            nuUSDAmount - 1,
            userA
        );
        // slippage ok
        uint balnuUSD = nuUSD.balanceOf(userA);
        uint balnuma = numa.balanceOf(userA);
        uint numaBalBefore = numa.balanceOf(feeAddressPrinter);
        uint supplyBefore = numa.totalSupply();
        moneyPrinter.burnAssetToNumaOutput(
            address(nuUSD),
            numaAmount,
            nuUSDAmount,
            userA
        );

        uint balnuUSDAfter = nuUSD.balanceOf(userA);
        uint balnumaAfter = numa.balanceOf(userA);
        assertEq(balnuUSD - balnuUSDAfter, nuUSDAmount);
        assertEq(balnumaAfter - balnuma, numaAmount);

        // 60% of the fees sent to fee address
        uint feeSentEstim = (fee * 6000) / 10000;

        uint numaBal = numa.balanceOf(feeAddressPrinter);
        assertEq(numaBal - numaBalBefore, feeSentEstim, "fee sent ko");
        assertEq(
            numa.totalSupply(),
            supplyBefore + numaAmount + feeSentEstim,
            "supply ko"
        );
    }

    function test_swapExactInput() public {
        uint numaAmount = 1000001e18;
        uint nuUSDAmount = 40001e18;

        vm.startPrank(deployer);
        numa.transfer(userA, numaAmount);

        vm.stopPrank();
        vm.startPrank(userA);
        // get some nuUSD
        numa.approve(address(moneyPrinter), numaAmount);
        moneyPrinter.mintAssetOutputFromNuma(
            address(nuUSD),
            nuUSDAmount,
            numaAmount,
            userA
        );

        (uint256 nuBTCAmount, uint fee) = moneyPrinter
            .getNbOfNuAssetFromNuAsset(
                address(nuUSD),
                address(nuBTC),
                nuUSDAmount
            );
        nuUSD.approve(address(moneyPrinter), nuUSDAmount);

        // warning cf test block swaps
        uint globalCF = vaultManager.getGlobalCF();
        vm.startPrank(deployer);
        vaultManager.setScalingParameters(
            vaultManager.cf_critical(),
            globalCF + 1,
            vaultManager.cf_severe(),
            vaultManager.debaseValue(),
            vaultManager.rebaseValue(),
            1 hours,
            2 hours,
            vaultManager.minimumScale(),
            vaultManager.criticalDebaseMult()
        );
        vm.startPrank(userA);
        vm.expectRevert("minting forbidden");
        moneyPrinter.swapExactInput(
            address(nuUSD),
            address(nuBTC),
            userA,
            nuUSDAmount,
            nuBTCAmount
        );
        // put back warning cf
        vm.startPrank(deployer);
        vaultManager.setScalingParameters(
            vaultManager.cf_critical(),
            globalCF - 1,
            vaultManager.cf_severe(),
            vaultManager.debaseValue(),
            vaultManager.rebaseValue(),
            1 hours,
            2 hours,
            vaultManager.minimumScale(),
            vaultManager.criticalDebaseMult()
        );
        vm.startPrank(userA);
        // slippage test
        vm.expectRevert("min output");
        moneyPrinter.swapExactInput(
            address(nuUSD),
            address(nuBTC),
            userA,
            nuUSDAmount,
            nuBTCAmount + 1
        );

        // pause test
        vm.stopPrank();
        vm.startPrank(deployer);
        moneyPrinter.pause();
        vm.stopPrank();
        vm.startPrank(userA);
        vm.expectRevert(bytes4(0xd93c0665));
        moneyPrinter.swapExactInput(
            address(nuUSD),
            address(nuBTC),
            userA,
            nuUSDAmount,
            nuBTCAmount
        );
        vm.stopPrank();
        vm.startPrank(deployer);
        moneyPrinter.unpause();
        vm.stopPrank();
        vm.startPrank(userA);

        // slippage ok
        uint balnuUSD = nuUSD.balanceOf(userA);
        uint balnuBTC = nuBTC.balanceOf(userA);
        uint supplynuUSD = nuUSD.totalSupply();
        uint supplynuBTC = nuBTC.totalSupply();
        moneyPrinter.swapExactInput(
            address(nuUSD),
            address(nuBTC),
            userA,
            nuUSDAmount,
            nuBTCAmount
        );
        assertEq(balnuUSD - nuUSD.balanceOf(userA), nuUSDAmount);
        assertEq(nuBTC.balanceOf(userA) - balnuBTC, nuBTCAmount);
        assertEq(supplynuUSD + fee - nuUSD.totalSupply(), nuUSDAmount);
        assertEq(nuBTC.totalSupply() - supplynuBTC, nuBTCAmount);
        assertEq(nuUSD.balanceOf(feeAddressPrinter), fee);
    }

    function test_swapExactOutput() public {
        uint numaAmount = 3000000e18;
        uint nuBTCAmount = 11e18;

        vm.startPrank(deployer);
        numa.transfer(userA, numaAmount);

        vm.stopPrank();
        vm.startPrank(userA);

        (uint256 nuUSDAmount, uint fee) = moneyPrinter
            .getNbOfNuAssetNeededForNuAsset(
                address(nuUSD),
                address(nuBTC),
                nuBTCAmount
            );

        // get some nuUSD
        numa.approve(address(moneyPrinter), numaAmount);
        moneyPrinter.mintAssetFromNumaInput(
            address(nuUSD),
            numaAmount,
            nuUSDAmount,
            userA
        );

        // nuUSD.approve(address(moneyPrinter), nuUSDAmount);

        // // warning cf test block swaps
        // uint globalCF = vaultManager.getGlobalCF();
        // vm.startPrank(deployer);
        // vaultManager.setScalingParameters(
        //     vaultManager.cf_critical(),
        //     globalCF + 1,
        //     vaultManager.cf_severe(),
        //     vaultManager.debaseValue(),
        //     vaultManager.rebaseValue(),
        //     1 hours,
        //     2 hours,
        //     vaultManager.minimumScale(),
        //     vaultManager.criticalDebaseMult()
        // );
        // vm.startPrank(userA);
        // vm.expectRevert("minting forbidden");
        // moneyPrinter.swapExactOutput(
        //     address(nuUSD),
        //     address(nuBTC),
        //     userA,
        //     nuBTCAmount,
        //     nuUSDAmount
        // );
        // // put back warning cf
        // vm.startPrank(deployer);
        // vaultManager.setScalingParameters(
        //     vaultManager.cf_critical(),
        //     globalCF - 1,
        //     vaultManager.cf_severe(),
        //     vaultManager.debaseValue(),
        //     vaultManager.rebaseValue(),
        //     1 hours,
        //     2 hours,
        //     vaultManager.minimumScale(),
        //     vaultManager.criticalDebaseMult()
        // );
        // vm.startPrank(userA);
        // // slippage test
        // vm.expectRevert("maximum input reached");
        // moneyPrinter.swapExactOutput(
        //     address(nuUSD),
        //     address(nuBTC),
        //     userA,
        //     nuBTCAmount,
        //     nuUSDAmount - 1
        // );

        // // pause test
        // vm.stopPrank();
        // vm.startPrank(deployer);
        // moneyPrinter.pause();
        // vm.stopPrank();
        // vm.startPrank(userA);
        // vm.expectRevert(0xd93c0665);
        // moneyPrinter.swapExactOutput(
        //     address(nuUSD),
        //     address(nuBTC),
        //     userA,
        //     nuBTCAmount,
        //     nuUSDAmount
        // );
        // vm.stopPrank();
        // vm.startPrank(deployer);
        // moneyPrinter.unpause();
        // vm.stopPrank();
        // vm.startPrank(userA);

        // slippage ok
        // uint balnuUSD = nuUSD.balanceOf(userA);
        // uint balnuBTC = nuBTC.balanceOf(userA);
        // uint supplynuUSD = nuUSD.totalSupply();
        // uint supplynuBTC = nuBTC.totalSupply();
        // moneyPrinter.swapExactOutput(
        //     address(nuUSD),
        //     address(nuBTC),
        //     userA,
        //     nuBTCAmount,
        //     nuUSDAmount
        // );
        // assertEq(balnuUSD - nuUSD.balanceOf(userA), nuUSDAmount);
        // assertEq(nuBTC.balanceOf(userA) - balnuBTC, nuBTCAmount);
        // assertEq(supplynuUSD + fee - nuUSD.totalSupply(), nuUSDAmount);
        // assertEq(nuBTC.totalSupply() - supplynuBTC, nuBTCAmount);
        // assertEq(nuUSD.balanceOf(feeAddressPrinter), fee);
    }

    function test_PricesLowHigh() external {
        uint numaAmount = 100000000e18;
        uint nuAssetAmount = 100000000e18;

        // remove fees as we want to check twaps here
        vm.stopPrank();
        vm.startPrank(deployer);
        moneyPrinter.setPrintAssetFeeBps(0);
        moneyPrinter.setBurnAssetFeeBps(0);

        // Modify twaps
        // buy numa
        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams({
                tokenIn: address(usdc),
                tokenOut: address(numa),
                fee: 500,
                recipient: deployer,
                deadline: block.timestamp,
                amountOut: 100000 ether,
                amountInMaximum: type(uint).max,
                sqrtPriceLimitX96: 0
            });

        // Executes the swap returning the amountIn needed to spend to receive the desired amountOut.
        usdc.approve(address(swapRouter), type(uint).max);
        // ERC20InsufficientAllowance(0xE592427A0AEce92De3Edee1F18E0157C05861564, 36934311772498674553 [3.693e19], 2548408988412747955903073076714761369303 [2.548e39])
        swapRouter.exactOutputSingle(params);

        vm.stopPrank();
        vm.startPrank(userA);

        // checking prices
        numaPricePoolL = NumaOracle(address(numaOracle)).getV3LowestPrice(
            NUMA_USDC_POOL_ADDRESS,
            1 ether
        );
        numaPricePoolH = NumaOracle(address(numaOracle)).getV3HighestPrice(
            NUMA_USDC_POOL_ADDRESS,
            1 ether
        );

        numaPricePoolSpot = NumaOracle(address(numaOracle)).getV3SpotPrice(
            NUMA_USDC_POOL_ADDRESS,
            1 ether
        );

        // pool price in USD 1e18
        numaPricePoolL = numaPricePoolL * 10 ** 12;
        numaPricePoolH = numaPricePoolH * 10 ** 12;
        numaPricePoolSpot = numaPricePoolSpot * 10 ** 12;
        console2.log("pool price HIGH", numaPricePoolH);
        console2.log("pool price LOW", numaPricePoolL);
        console2.log("pool price SPOT", numaPricePoolSpot);

        // should use lowest price
        (uint256 nuUSDAmount, ) = moneyPrinter.getNbOfNuAssetFromNuma(
            address(nuUSD),
            numaAmount
        );

        // should use highest price
        (uint256 nuUSDAmount2, ) = moneyPrinter.getNbOfnuAssetNeededForNuma(
            address(nuUSD),
            numaAmount
        );
        assertGt(nuUSDAmount2, nuUSDAmount);

        // should use highest price from LP
        (uint numaOut, ) = moneyPrinter.getNbOfNumaFromAssetWithFee(
            address(nuUSD),
            nuAssetAmount
        );

        // should use lowest price from LP
        (uint numaNeeded, ) = moneyPrinter.getNbOfNumaNeededAndFee(
            address(nuUSD),
            nuAssetAmount
        );

        assertGt(numaNeeded, numaOut);
    }

    function test_PricesClippedByVault1() external {
        uint numaAmount = 100000000e18;
        uint nuAssetAmount = 100000000e18;
        // remove fees as we want to check twaps here
        vm.stopPrank();
        vm.startPrank(deployer);
        moneyPrinter.setPrintAssetFeeBps(0);
        moneyPrinter.setBurnAssetFeeBps(0);

        vm.stopPrank();
        vm.startPrank(userA);

        // checking prices

        // minting will take lowest(LPprice, vaultbuyprice)

        (uint256 nuUSDAmount, ) = moneyPrinter.getNbOfNuAssetFromNuma(
            address(nuUSD),
            numaAmount
        );

        (uint256 nuUSDAmount2, ) = moneyPrinter.getNbOfnuAssetNeededForNuma(
            address(nuUSD),
            numaAmount
        );
        assertApproxEqAbs(nuUSDAmount, nuUSDAmount2, 0.001 ether, "amount ko");
        (uint numaOut, ) = moneyPrinter.getNbOfNumaFromAssetWithFee(
            address(nuUSD),
            nuAssetAmount
        );

        (uint numaNeeded, ) = moneyPrinter.getNbOfNumaNeededAndFee(
            address(nuUSD),
            nuAssetAmount
        );
        console2.log("numa", numaOut);
        console2.log("numa", numaNeeded);
        assertApproxEqAbs(numaOut, numaNeeded, 0.001 ether, "amount ko");
        // doubling vault balance
        deal({
            token: address(rEth),
            to: address(vault),
            give: (2 * rEth.balanceOf(address(vault)))
        });

        (uint256 nuUSDAmount3, ) = moneyPrinter.getNbOfNuAssetFromNuma(
            address(nuUSD),
            numaAmount
        );

        (uint256 nuUSDAmount4, ) = moneyPrinter.getNbOfnuAssetNeededForNuma(
            address(nuUSD),
            numaAmount
        );
        // adding some scale to be sure
        assertGt(nuUSDAmount4, (nuUSDAmount3 * 15) / 10, "amount ko");

        deal({
            token: address(rEth),
            to: address(vault),
            give: (rEth.balanceOf(address(vault)) / 4)
        });

        (uint numaOut2, ) = moneyPrinter.getNbOfNumaFromAssetWithFee(
            address(nuUSD),
            nuAssetAmount
        );

        (uint numaNeeded2, ) = moneyPrinter.getNbOfNumaNeededAndFee(
            address(nuUSD),
            nuAssetAmount
        );
        console2.log("numa", numaOut2);
        console2.log("numa", numaNeeded2);
        assertGt(numaNeeded2, (numaOut2 * 15) / 10, "amount ko");
    }

    // function test_Converter() external {
    //     //uint usdcAmountIn = 1000000;
    //     uint usdcAmountIn = 100000000;
    //     uint ethAmount = usdcEthConverter.convertTokenToEth(usdcAmountIn);
    //     console2.log(ethAmount);

    //     uint usdcAmount = usdcEthConverter.convertEthToToken(ethAmount);
    //     console2.log(usdcAmount);

    //     // TODOTEST
    //     //assertEq(usdcAmountIn, usdcAmount); // it will fail because the code logic is not correct
    // }

    // function test_Mint_Estimations() external {
    //     uint numaAmount = 1000e18;

    //     // with 1000 NUMA "nuUSDAmount" will be minted
    //     (uint256 nuUSDAmount, uint fee) = moneyPrinter.getNbOfNuAssetFromNuma(
    //         address(nuUSD),
    //         numaAmount
    //     );

    //     // plug in the above numa amount to see they are identical!
    //     (uint numaNeeded, uint fee2) = moneyPrinter.getNbOfNumaNeededAndFee(
    //         address(nuUSD),
    //         nuUSDAmount
    //     );

    //     console2.log("nuUSD would be minted given NUMA: ", nuUSDAmount);

    //     console2.log(
    //         "If the same nuUSD would be the input for reverse trade the NUMA amount: ",
    //         numaNeeded
    //     );

    //     // TODOTEST
    //     // refacto test
    //     // assertEq(numaAmount, numaNeeded); // it will fail because the code logic is not correct
    //     // assertEq(fee, fee2); // same as above.
    // }

    // function test_Mint_EstimationsRefacto() external {
    //     // removing fees for now to see if it matches better
    //     vm.stopPrank();
    //     vm.startPrank(deployer);
    //     moneyPrinter.setPrintAssetFeeBps(0);
    //     vm.stopPrank();
    //     vm.startPrank(userA);

    //     uint numaAmount = 1000e18;

    //     (uint256 nuUSDAmount4, uint fee4) = moneyPrinter.getNbOfNuAssetFromNuma(
    //         address(nuUSD),
    //         numaAmount
    //     );
    //     console2.log(
    //         "nuUSD would be minted given NUMA new fct: ",
    //         nuUSDAmount4
    //     );

    //     (uint numaNeeded3, uint fee3) = moneyPrinter.getNbOfNumaNeededAndFee(
    //         address(nuUSD),
    //         nuUSDAmount4
    //     );

    //     console2.log(
    //         "If the same nuUSD would be the input for reverse trade the NUMA amount new fct: ",
    //         numaNeeded3
    //     );

    //     // TODOTEST
    //     // refacto test
    //     // assertEq(numaAmount, numaNeeded3); // it will fail because the code logic is not correct
    //     // assertEq(fee4, fee3); // same as above.
    // }

    // function test_Burn() external {
    //     numa.approve(address(moneyPrinter), type(uint).max);

    //     uint numaAmount = 10_000e18;

    //     uint nuUSDMinted = moneyPrinter.mintAssetFromNumaInput(
    //         address(nuUSD),
    //         numaAmount,
    //         0,
    //         deployer
    //     );

    //     console2.log("nuUSD minted", nuUSDMinted);

    //     nuUSD.approve(address(moneyPrinter), type(uint).max);

    //     uint numaMinted = moneyPrinter.burnAssetInputToNuma(
    //         address(nuUSD),
    //         nuUSDMinted,
    //         0,
    //         deployer
    //     );

    //     console2.log("Numa minted", numaMinted);
    // }

    // // gets
    // function testFuzz_mintAssetEstimations(uint nuAssetAmount) public view {
    //     // we have 10000000 numa so we can not get more than 5000000 nuUSD
    //     // and there is a 5% print fee, so max is 4750000
    //     vm.assume(nuAssetAmount <= 4750000 ether);

    //     //vm.assume(nuAssetAmount == 16334);// KO

    //     // test only reasonnable amounts
    //     vm.assume(nuAssetAmount > 0.000001 ether);

    //     (uint cost, uint fee) = moneyPrinter.getNbOfNumaNeededAndFee(
    //         address(nuUSD),
    //         nuAssetAmount
    //     );

    //     // check the numbers
    //     uint256 amountToBurn = (cost * moneyPrinter.printAssetFeeBps()) / 10000;
    //     uint costWithoutFee = cost - amountToBurn;
    //     uint estimatedOutput = costWithoutFee;

    //     console.log(cost);
    //     console.log(amountToBurn);
    //     assertEq(fee, amountToBurn, "fees estim ko");
    //     assertApproxEqAbs(
    //         estimatedOutput,
    //         (nuAssetAmount * 1e18) / numaPricePoolL,
    //         0.01 ether,
    //         "output estim ko"
    //     ); // epsilon is big...

    //     // other direction
    //     (uint outAmount, uint fee2) = moneyPrinter.getNbOfNuAssetFromNuma(
    //         address(nuUSD),
    //         cost
    //     );
    //     assertApproxEqAbs(
    //         outAmount,
    //         nuAssetAmount,
    //         0.0000000001 ether,
    //         "nuAsset amount ko"
    //     );
    //     assertEq(fee2, fee, "fee matching ko");
    // }

    // function testFuzz_mintAssetEstimationsVaultClipped(uint nuAssetAmount) public  {

    //     // we have 10000000 numa so we can not get more than 5000000 nuUSD
    //     // and there is a 5% print fee, so max is 4750000
    //     vm.assume(nuAssetAmount <= 4750000 ether);

    //     // as we use pool lowest price here, to be clipped by vault, we need to set vault price inferior
    //     // to do that we can mint some numa
    //     numa.mint(deployer,numaSupply/2);

    //     uint numaPriceVault2 = vaultManager.numaToEth(1 ether,IVaultManager.PriceType.NoFeePrice);
    //     assertLt(numaPriceVault2,numaPriceVault,"new price ko");
    //     assertLt(numaPriceVault2,numaPricePoolL,"new price ko");

    //     (uint cost,uint fee) = moneyPrinter.getNbOfNumaNeededAndFee(address(nuUSD),nuAssetAmount);

    //     // check the numbers
    //     uint256 amountToBurn = (cost * moneyPrinter.printAssetFeeBps()) / 10000;
    //     uint costWithoutFee = cost - amountToBurn;
    //     uint estimatedOutput = costWithoutFee;
    //     assertEq(fee,amountToBurn,"fees estim ko");
    //     assertEq(estimatedOutput,(nuAssetAmount*1e18)/numaPriceVault2,"output estim ko");

    //     // other direction
    //     (uint outAmount,uint fee2) = moneyPrinter.getNbOfNuAssetFromNuma(address(nuUSD),cost);
    //     assertEq(outAmount,nuAssetAmount,"nuAsset amount ko");
    //     assertEq(fee2,fee,"fee matching ko");
    // }

    function forceSynthDebasing() public {
        uint globalCF = vaultManager.getGlobalCF();

        vm.startPrank(deployer);
        vaultManager.setScalingParameters(
            vaultManager.cf_critical(),
            vaultManager.cf_warning(),
            vaultManager.cf_severe(),
            vaultManager.debaseValue(),
            vaultManager.rebaseValue(),
            1 hours,
            2 hours,
            vaultManager.minimumScale(),
            vaultManager.criticalDebaseMult()
        );

        numa.approve(address(moneyPrinter), 10000000 ether);

        // checking numa price
        uint p1 = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.NoFeePrice
        );
        console2.log("p1", p1);
        moneyPrinter.mintAssetOutputFromNuma(
            address(nuUSD),
            4500000 ether,
            10000000 ether,
            deployer
        );
        p1 = vaultManager.numaToEth(
            1 ether,
            IVaultManager.PriceType.NoFeePrice
        );
        console2.log("p1", p1);

        // test debase
        vm.warp(block.timestamp + 10 hours);
        (
            uint scaleSynthBurn2,
            uint criticalScaleForNumaPriceAndSellFee2
        ) = vaultManager.getSynthScalingUpdate();
        assertEq(scaleSynthBurn2, 800);
    }

    function forceSynthDebasingCritical() public {
        vm.startPrank(deployer);
        //  vaultManager.setScalingParameters(
        //     vaultManager.cf_critical(),
        //     vaultManager.cf_warning(),
        //     vaultManager.cf_severe(),
        //     vaultManager.debaseValue(),
        //     vaultManager.rebaseValue(),
        //     1 hours,
        //     2 hours,
        //     vaultManager.minimumScale(),
        //     vaultManager.criticalDebaseMult()
        // );

        // numa.approve(address(moneyPrinter), 10000000 ether);

        // moneyPrinter.mintAssetOutputFromNuma(
        //     address(nuUSD),
        //     4500000 ether,
        //     10000000 ether,
        //     deployer
        // );

        //  // test debase
        //  vm.warp(block.timestamp + 10 hours);
        //  (uint scaleSynthBurn2,uint criticalScaleForNumaPriceAndSellFee2) = vaultManager.getSynthScalingUpdate();
        // //assertEq(scaleSynthBurn2,800);

        uint globalCF2 = vaultManager.getGlobalCF();
        console2.log(globalCF2);

        // critical_cf
        vaultManager.setScalingParameters(
            globalCF2 * 2,
            vaultManager.cf_warning(),
            vaultManager.cf_severe(),
            vaultManager.debaseValue(),
            vaultManager.rebaseValue(),
            1 hours,
            2 hours,
            vaultManager.minimumScale(),
            vaultManager.criticalDebaseMult()
        );
    }

    //     function test_SynthScaling() public {
    //         uint globalCF = vaultManager.getGlobalCF();
    //         assertGt(globalCF, vaultManager.cf_critical());
    //         console2.log(globalCF);
    //         vm.startPrank(deployer);
    //          vaultManager.setScalingParameters(
    //             vaultManager.cf_critical(),
    //             vaultManager.cf_warning(),
    //             vaultManager.cf_severe(),
    //             vaultManager.debaseValue(),
    //             vaultManager.rebaseValue(),
    //             1 hours,
    //             2 hours,
    //             vaultManager.minimumScale(),
    //             vaultManager.criticalDebaseMult()
    //         );

    //         numa.approve(address(moneyPrinter), 10000000 ether);

    //         moneyPrinter.mintAssetOutputFromNuma(
    //             address(nuUSD),
    //             4500000 ether,
    //             10000000 ether,
    //             deployer
    //         );

    //         uint globalCF2 = vaultManager.getGlobalCF();
    //         console2.log(globalCF2);
    //         assertLt(globalCF2, globalCF);

    //         (uint scaleSynthBurn,uint criticalScaleForNumaPriceAndSellFee) = vaultManager.getSynthScalingUpdate();
    //          console2.log(scaleSynthBurn);
    //          console2.log(criticalScaleForNumaPriceAndSellFee);
    //          assertEq(scaleSynthBurn,1000);
    //          assertEq(criticalScaleForNumaPriceAndSellFee,1000);
    //          // test debase
    //          vm.warp(block.timestamp + 10 hours);
    //          (uint scaleSynthBurn2,uint criticalScaleForNumaPriceAndSellFee2) = vaultManager.getSynthScalingUpdate();
    //          console2.log(scaleSynthBurn2);
    //          console2.log(criticalScaleForNumaPriceAndSellFee2);
    //         assertEq(scaleSynthBurn2,800);
    //         assertEq(criticalScaleForNumaPriceAndSellFee2,criticalScaleForNumaPriceAndSellFee);

    //          vm.warp(block.timestamp + 10 hours);
    //          (scaleSynthBurn2,criticalScaleForNumaPriceAndSellFee2) = vaultManager.getSynthScalingUpdate();
    //          console2.log(scaleSynthBurn2);
    //          console2.log(criticalScaleForNumaPriceAndSellFee2);
    //         assertEq(scaleSynthBurn2,600);
    //         assertEq(criticalScaleForNumaPriceAndSellFee2,criticalScaleForNumaPriceAndSellFee);

    //         // min reached
    //          vm.warp(block.timestamp + 10 hours);
    //          (scaleSynthBurn2,criticalScaleForNumaPriceAndSellFee2) = vaultManager.getSynthScalingUpdate();
    //          console2.log(scaleSynthBurn2);
    //          console2.log(criticalScaleForNumaPriceAndSellFee2);
    //         assertEq(scaleSynthBurn2,vaultManager.minimumScale());
    //         assertEq(criticalScaleForNumaPriceAndSellFee2,criticalScaleForNumaPriceAndSellFee);

    //         globalCF2 = vaultManager.getGlobalCF();
    //         console2.log(globalCF2);

    //         // critical_cf
    //         vaultManager.setScalingParameters(
    //             globalCF2 + 1,
    //             vaultManager.cf_warning(),
    //             vaultManager.cf_severe(),
    //             vaultManager.debaseValue(),
    //             vaultManager.rebaseValue(),
    //             1 hours,
    //             2 hours,
    //             vaultManager.minimumScale(),
    //             vaultManager.criticalDebaseMult()
    //         );
    //         (uint scaleSynthBurn3,uint criticalScaleForNumaPriceAndSellFee3) = vaultManager.getSynthScalingUpdate();
    //          console2.log(scaleSynthBurn3);
    //          console2.log(criticalScaleForNumaPriceAndSellFee3);

    //          uint criticalDebaseFactor = (globalCF2 * 1000) / vaultManager.cf_critical();
    //        console2.log("criticalDebaseFactor",criticalDebaseFactor);

    //         uint scalePriceFee = criticalDebaseFactor;

    //             // we apply this multiplier on the factor for when it's used on synthetics burning price
    //             criticalDebaseFactor =
    //                 (criticalDebaseFactor * 1000) /
    //                 vaultManager.criticalDebaseMult();

    //          console2.log("criticalDebaseFactorMult",criticalDebaseFactor);

    // console2.log("criticalScaleForNumaPriceAndSellFee",scalePriceFee);

    //         // test that we use min for scaling
    //         assertEq(scaleSynthBurn3,vaultManager.minimumScale());
    //         // for price and sell fee we use critical debase factor
    //         assertEq(criticalScaleForNumaPriceAndSellFee3,scalePriceFee);

    //         // check critical scale value
    //         vaultManager.setScalingParameters(
    //             globalCF2 *3,
    //             vaultManager.cf_warning(),
    //             vaultManager.cf_severe(),
    //             vaultManager.debaseValue(),
    //             vaultManager.rebaseValue(),
    //             1 hours,
    //             2 hours,
    //             vaultManager.minimumScale(),
    //             vaultManager.criticalDebaseMult()
    //         );
    //         (scaleSynthBurn3,criticalScaleForNumaPriceAndSellFee3) = vaultManager.getSynthScalingUpdate();
    //         console2.log(scaleSynthBurn3);
    //         console2.log(criticalScaleForNumaPriceAndSellFee3);

    //         criticalDebaseFactor = (globalCF2 * 1000) / vaultManager.cf_critical();
    //        console2.log("criticalDebaseFactor",criticalDebaseFactor);

    //         scalePriceFee = criticalDebaseFactor;

    //             // we apply this multiplier on the factor for when it's used on synthetics burning price
    //             criticalDebaseFactor =
    //                 (criticalDebaseFactor * 1000) /
    //                 vaultManager.criticalDebaseMult();

    //          console2.log("criticalDebaseFactorMult",criticalDebaseFactor);

    //         console2.log("criticalScaleForNumaPriceAndSellFee",scalePriceFee);

    //          // test rebase
    //         vaultManager.setScalingParameters(
    //             1100,
    //             vaultManager.cf_warning(),
    //             vaultManager.cf_severe(),
    //             vaultManager.debaseValue(),
    //             vaultManager.rebaseValue(),
    //             1 hours,
    //             2 hours,
    //             vaultManager.minimumScale(),
    //             vaultManager.criticalDebaseMult()
    //         );

    //         nuUSD.approve(address(moneyPrinter), 4500000 ether);

    //         moneyPrinter.burnAssetInputToNuma(
    //             address(nuUSD),
    //             4500000 ether,
    //             0,
    //             userA
    //         );
    //          (scaleSynthBurn2,criticalScaleForNumaPriceAndSellFee2) = vaultManager.getSynthScalingUpdate();
    //         assertEq(scaleSynthBurn2,vaultManager.minimumScale());
    //         assertEq(criticalScaleForNumaPriceAndSellFee2,criticalScaleForNumaPriceAndSellFee);

    //         // rebase
    //         vm.warp(block.timestamp + 10 hours);
    //          (scaleSynthBurn2,criticalScaleForNumaPriceAndSellFee2) = vaultManager.getSynthScalingUpdate();
    //         assertEq(scaleSynthBurn2,vaultManager.minimumScale()+150);
    //         assertEq(criticalScaleForNumaPriceAndSellFee2,criticalScaleForNumaPriceAndSellFee);
    //         // rebase again
    //          vm.warp(block.timestamp + 10 hours);
    //          (scaleSynthBurn2,criticalScaleForNumaPriceAndSellFee2) = vaultManager.getSynthScalingUpdate();
    //         assertEq(scaleSynthBurn2,vaultManager.minimumScale()+300);
    //         assertEq(criticalScaleForNumaPriceAndSellFee2,criticalScaleForNumaPriceAndSellFee);

    //          // test max
    //         vm.warp(block.timestamp + 30 hours);
    //         (scaleSynthBurn2,criticalScaleForNumaPriceAndSellFee2) = vaultManager.getSynthScalingUpdate();
    //         assertEq(scaleSynthBurn2,1000);
    //         assertEq(criticalScaleForNumaPriceAndSellFee2,criticalScaleForNumaPriceAndSellFee);

    //     }
    // function testFuzz_mintAssetEstimationsSynthScaled(
    //     uint nuAssetAmount
    // ) public {
    //     // we have 10000000 numa so we can not get more than 5000000 nuUSD
    //     // and there is a 5% print fee, so max is 4750000
    //     vm.assume(nuAssetAmount <= 4750000 ether);

    //     //

    //     uint numaPriceVault2 = vaultManager.numaToEth(
    //         1 ether,
    //         IVaultManager.PriceType.NoFeePrice
    //     );
    //     assertLt(numaPriceVault2, numaPriceVault, "new price ko");
    //     assertLt(numaPriceVault2, numaPricePoolL, "new price ko");

    //     (uint cost, uint fee) = moneyPrinter.getNbOfNumaNeededAndFee(
    //         address(nuUSD),
    //         nuAssetAmount
    //     );

    //     // check the numbers
    //     uint256 amountToBurn = (cost * moneyPrinter.printAssetFeeBps()) / 10000;
    //     uint costWithoutFee = cost - amountToBurn;
    //     uint estimatedOutput = costWithoutFee;
    //     assertEq(fee, amountToBurn, "fees estim ko");
    //     assertEq(
    //         estimatedOutput,
    //         (nuAssetAmount * 1e18) / numaPriceVault2,
    //         "output estim ko"
    //     );

    //     // other direction
    //     (uint outAmount, uint fee2) = moneyPrinter.getNbOfNuAssetFromNuma(
    //         address(nuUSD),
    //         cost
    //     );
    //     assertEq(outAmount, nuAssetAmount, "nuAsset amount ko");
    //     assertEq(fee2, fee, "fee matching ko");
    // }

    // numa.approve(address(moneyPrinter),type(uint).max);

    // // check slippage test
    // vm.expectRevert("min amount");
    // uint maxAmountReached = cost - 1;
    // moneyPrinter.mintAssetOutputFromNuma(address(nuUSD),nuAssetAmount,maxAmountReached,deployer);

    // // check print
    // uint numaBalBefore = numa.balanceOf(deployer);
    // uint nuUSDBefore = nuUSD.balanceOf(deployer);

    // moneyPrinter.mintAssetOutputFromNuma(address(nuUSD),nuAssetAmount,cost,deployer);
    // uint numaBalAfter = numa.balanceOf(deployer);
    // uint nuUSDAfter = nuUSD.balanceOf(deployer);

    // assertEq(numaBalBefore - numaBalAfter,cost,"input amount ko");
    // assertEq(nuUSDAfter - nuUSDBefore,nuAssetAmount,"output amount ko");

    //  function testFuzz_SwapEstimations(uint nuUSDAmountIn) public {

    //     //
    //     (uint nuBTCAmountOut,uint swapFee1) = moneyPrinter.getNbOfNuAssetFromNuAsset(address(nuUSD),address(nuBTC),nuUSDAmountIn);
    //     // check fee
    //     assertEq(swapFee1,(nuUSDAmountIn * moneyPrinter.swapAssetFeeBps()) / 10000);
    //     //
    //     (uint nuUSDCIn,uint swapFee2) = moneyPrinter.getNbOfNuAssetNeededForNuAsset(address(nuUSD),address(nuBTC),nuBTCAmountOut);

    //     // check matching
    //     assertEq(nuUSDCIn,nuUSDAmountIn);
    //     // check fee
    //     assertEq(swapFee1,swapFee2);
    // }
}
