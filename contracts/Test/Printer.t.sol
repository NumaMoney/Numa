// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/console2.sol";
import {Setup} from "./utils/SetupDeployNuma_Arbitrum.sol";

contract PrinterTest is Setup 
{
    function setUp() public virtual override {
        console2.log("PRINTER TEST");
        super.setUp();
    }
    function test_CheckSetup() public 
    {
        // numa price from vault should equal price from pool
        uint numaPriceVault = vaultManager.GetNumaPriceEth(1 ether);
        uint numaPriceVaultUSD = (numaPriceVault*uint(ethusd))/1e8;
                console2.log(numaPriceVault);
         console2.log(numaPriceVaultUSD);
                console2.log(ethusd);
                
        assertApproxEqAbs(numaPriceVaultUSD,0.5 ether,10000);// TODO why the diff


    }

    function testFuzz_mintAssetOutputFromNuma(uint nuAssetAmount) public {
        // we have 10000000 numa so we can not get more than 5000000 nuUSD
        // and there is a 5% print fee, so max is 4750000
        vm.assume(nuAssetAmount <= 4750000 ether);
        //
        uint256 numaPerEthVault = vaultManager.GetNumaPerEth(nuAssetAmount);
        numaPerEthVault = (numaPerEthVault * 1000) / (1000 + (1000-vaultManager.getBuyFee()));
        (uint cost,uint fee) = moneyPrinter.getNbOfNumaNeededAndFee(address(nuUSD),nuAssetAmount);

        // check the numbers
        uint256 amountToBurn = (cost * moneyPrinter.printAssetFeeBps()) / 10000;
        uint costWithoutFee = cost - amountToBurn;
        uint estimatedOutput = costWithoutFee*USDTONUMA;
        assertEq(estimatedOutput,nuAssetAmount);
        assertEq(fee,amountToBurn);
        //
        numa.approve(address(moneyPrinter),type(uint).max);

        // check slippage test
        vm.expectRevert("min amount");
        uint maxAmountReached = cost - 1;
        moneyPrinter.mintAssetOutputFromNuma(address(nuUSD),nuAssetAmount,maxAmountReached,deployer);
       
        // check print
        uint numaBalBefore = numa.balanceOf(deployer);
        uint nuUSDBefore = nuUSD.balanceOf(deployer);       
        moneyPrinter.mintAssetOutputFromNuma(address(nuUSD),nuAssetAmount,cost,deployer);
        uint numaBalAfter = numa.balanceOf(deployer);
        uint nuUSDAfter = nuUSD.balanceOf(deployer); 
        assertEq(numaBalBefore - numaBalAfter,cost);    
        assertEq(nuUSDAfter - nuUSDBefore,nuAssetAmount);
    }

     function testFuzz_SwapEstimations(uint nuUSDAmountIn) public {

        //
        (uint nuBTCAmountOut,uint swapFee1) = moneyPrinter.getNbOfNuAssetFromNuAsset(address(nuUSD),address(nuBTC),nuUSDAmountIn);
        // check fee 
        assertEq(swapFee1,(nuUSDAmountIn * moneyPrinter.swapAssetFeeBps()) / 10000);
        // 
        (uint nuUSDCIn,uint swapFee2) = moneyPrinter.getNbOfNuAssetNeededForNuAsset(address(nuUSD),address(nuBTC),nuBTCAmountOut);

        // check matching
        assertEq(nuUSDCIn,nuUSDAmountIn);
        // check fee
        assertEq(swapFee1,swapFee2);
    }

   
}