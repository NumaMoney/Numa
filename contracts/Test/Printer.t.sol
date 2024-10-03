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
// TODO
// estim mint nuasset from numa, compare in/out param
// estim burn nuasset to numa, compare in/out param
// estim swap nuasset, compare in/out param

// transactions & compare res with estimations
// synthscaling, clipped by vault
// mint& burn 2 x fees
// 
// Debase synthetics pricing feed based on CF. Block minting new sythethics, block swaps
// invariants: vault price, vault accounting balance, other?

// updateVaultAndInterest, 
// check updates are done, validate synth balance impacts maxborrow & debasing factors, etc...

contract PrinterTest is Setup {
    uint numaPriceVault;
    uint numaPriceVaultS;
    uint numaPriceVaultB;
    uint numaPricePoolL;
    uint numaPricePoolH;

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

        console.log("pool price HIGH",numaPricePoolH);
        console.log("pool price LOW",numaPricePoolL);
        console.log("vault price SELL",numaPriceVaultS);
        console.log("vault price BUY",numaPriceVaultB);
        console.log("vault price ",numaPriceVault);
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

    function test_Mint_Estimations() external {
        uint numaAmount = 1000e18;

        // with 1000 NUMA "nuUSDAmount" will be minted
        (uint256 nuUSDAmount, uint fee) = moneyPrinter.getNbOfNuAssetFromNuma(
            address(nuUSD),
            numaAmount
        );

        // plug in the above numa amount to see they are identical!
        (uint numaNeeded, uint fee2) = moneyPrinter.getNbOfNumaNeededAndFee(
            address(nuUSD),
            nuUSDAmount
        );

        console2.log("nuUSD would be minted given NUMA: ", nuUSDAmount);
        console2.log(
            "If the same nuUSD would be the input for reverse trade the NUMA amount: ",
            numaNeeded
        );

        console2.log("fee1: ", fee);
        console2.log("fee2: ", fee2);

        assertEq(numaNeeded, numaAmount); // it will fail because the code logic is not correct
        assertEq(fee, fee2); // same as above.


    }
    function test_Burn() external {
        numa.approve(address(moneyPrinter), type(uint).max);

        uint numaAmount = 10_000e18;

        uint nuUSDMinted = moneyPrinter.mintAssetFromNumaInput(address(nuUSD), numaAmount, 0, deployer);

        console2.log("nuUSD minted", nuUSDMinted);

        nuUSD.approve(address(moneyPrinter), type(uint).max);

        uint numaMinted = moneyPrinter.burnAssetInputToNuma(address(nuUSD), nuUSDMinted, 0, deployer);


        console2.log("Numa minted", numaMinted);

    }


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

    function ForceSynthScaling() public {
        // our eth balance is equivalent to 5 millions usd
        // so if we mint 4 millions nuusd, we should be > cf_severe
        // mint
        // check cf
        // by default we debase 20 every 24h, so if we want synth debase by 200, we need to wait 10 x 24h
        // wait
        // check scale
    }
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
