// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;

import "forge-std/console.sol";
import "forge-std/console2.sol";
import "forge-std/StdCheats.sol";
//
import "@openzeppelin/contracts_5.0.2/token/ERC20/ERC20.sol";
//
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
//
import {INonfungiblePositionManager} from "../uniV3Interfaces/INonfungiblePositionManager.sol";
import "../uniV3Interfaces/ISwapRouter.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "./TickHelper.sol";
import "./Math.sol";
import {encodePriceSqrt} from "./Math.sol";
//
import {ExtendedTest} from "./ExtendedTest.sol";
import {ConstantsTest} from "./ConstantsTest.sol";
//
import {FakeNuma} from "../mocks/FakeNuma.sol";
import {LstTokenMock} from "../mocks/LstTokenMock.sol";
import {nuAssetManager} from "../../nuAssets/nuAssetManager.sol";
import {NumaMinter} from "../../NumaProtocol/NumaMinter.sol";
import {VaultOracleSingle} from "../../NumaProtocol/VaultOracleSingle.sol";
import {VaultManager} from "../../NumaProtocol/VaultManager.sol";
import {NumaVault} from "../../NumaProtocol/NumaVault.sol";
import {NuAsset2} from "../../nuAssets/nuAsset2.sol";
import {INumaOracle} from "../../interfaces/INumaOracle.sol";
import {NumaOracle} from "../../NumaProtocol/NumaOracle.sol";
import {NumaPrinter} from "../../NumaProtocol/NumaPrinter.sol";
import "../../interfaces/INumaTokenToEthConverter.sol";
import "../../NumaProtocol/USDCToEthConverter.sol";
import {NumaLeverageVaultSwap} from "../../lending/NumaLeverageVaultSwap.sol";

import {NumaComptroller} from "../../lending/NumaComptroller.sol";
import "../../lending/JumpRateModelVariable.sol";
import "../../lending/CNumaLst.sol";
import "../../lending/CNumaToken.sol";
import "../../lending/NumaPriceOracleNew.sol";
import "../../lending/ExponentialNoError.sol";
import "../../lending/ComptrollerStorage.sol";
import "./SetupBase.sol";

// forge test --fork-url <your_rpc_url>
contract Setup is SetupBase {
    // Contract instances that we will use repeatedly.
    // Tokens
    //FakeNuma numa;
    address public vaultFeeReceiver = makeAddr("vaultFeeReceiver");
    address public vaultRwdReceiver = makeAddr("vaultRwdReceiver");

    function setUp() public virtual {
        // setup fork
        string memory ARBI_RPC_URL = vm.envString("URLARBI");
        uint256 arbitrumFork = vm.createFork(ARBI_RPC_URL);
        vm.selectFork(arbitrumFork);
        numa_admin = deployer;
 
        // prank deployer
        vm.startPrank(deployer);

        // setups
        _setUpTokens();

        // get tokens
        deal({token: address(rEth), to: deployer, give: 10000 ether});
        deal({token: USDC_ARBI, to: deployer, give: 100000000000000});
        deal({token: address(rEth), to: userA, give: 100000 ether});
        deal({token: address(rEth), to: userB, give: 100000 ether});
        deal({token: address(rEth), to: userC, give: 100000 ether});

        // need to setup vault price same as pool price: 1 numa = 0.5 usd
        // ETHUSD
        AggregatorV2V3Interface dataFeedETHUSD = AggregatorV2V3Interface(
            PRICEFEEDETHUSD_ARBI
        );
        (, ethusd, , , ) = dataFeedETHUSD.latestRoundData();

        AggregatorV2V3Interface dataFeedUSDCUSD = AggregatorV2V3Interface(
            PRICEFEEDUSDCUSD_ARBI
        );
        (, usdcusd, , , ) = dataFeedUSDCUSD.latestRoundData();

        AggregatorV2V3Interface dataFeedBTCUSD = AggregatorV2V3Interface(
            PRICEFEEDBTCUSD_ARBI
        );
        (, btcusd, , , ) = dataFeedBTCUSD.latestRoundData();

        AggregatorV2V3Interface dataFeedBTCETH = AggregatorV2V3Interface(
            PRICEFEEDBTCETH_ARBI
        );
        (, btceth, , , ) = dataFeedBTCETH.latestRoundData();

        //console.log(ethusd);
        // RETHETH
        AggregatorV2V3Interface dataFeedRETHETH = AggregatorV2V3Interface(
            PRICEFEEDRETHETH_ARBI
        );
        (, int answerRETHETH, , , ) = dataFeedRETHETH.latestRoundData();
        // 1e8 to account for decimals in chainlink prices
        uint amountReth = (1 ether * numaSupply * 1e8) /
            (USDTONUMA * uint(ethusd) * uint(answerRETHETH));


        
        (
            nuAssetMgr,
            numaMinter,
            vaultManager,
            vaultOracle,
            vault
        ) = _setupVaultAndAssetManager(
            HEART_BEAT_CUSTOM,
            vaultFeeReceiver,
            vaultRwdReceiver,
            INuma(address(numa)),
            0,
            0,
            address(0),
            address(0)
        );
        vm.startPrank(numa_admin);
        numa.grantRole(MINTER_ROLE, address(numaMinter));
        vm.stopPrank();

        vm.startPrank(deployer);
        // transfer rEth to vault to initialize price
        if (amountReth > 0) {
            rEth.transfer(address(vault), amountReth);
            // unpause V2
            vault.unpause();
        }

        _setupPool_Numa_Usdc();
        (numaOracle, usdcEthConverter, moneyPrinter) = _setupPrinter(
            address(nuAssetMgr),
            address(numaMinter),
            address(vaultManager)
        );
        _createNuAssets();
        _linkNuAssets(address(nuAssetMgr), address(moneyPrinter));
        moneyPrinter.unpause();
        _setupLending(NumaVault(address(vault)));
    }

    function _setUpTokens() internal override {
        SetupBase._setUpTokens();
        // Numa
        numa = new FakeNuma(deployer, deployer, deployer); // admin, pauser, minter
        numa.mint(deployer, numaSupply);
    }

    // function _setupPool_Numa_Usdc() internal {
    //     uint USDCAmount = 200000;
    //     uint USDCAmountNumaPool = USDCAmount * 1000000; //6 decimals
    //     uint NumaAmountNumaPoolUSDC = USDTONUMA * USDCAmount * 1 ether; // 18 decimals

    //     NUMA_USDC_POOL_ADDRESS = _setupUniswapPool(
    //         usdc,
    //         ERC20(address(numa)),
    //         USDCAmountNumaPool,
    //         NumaAmountNumaPoolUSDC
    //     );

    //     // advance in time for avg prices to work
    //     skip(INTERVAL_LONG * 2);
    //     vm.roll(block.number + 1);
    //     IUniswapV3Pool(NUMA_USDC_POOL_ADDRESS)
    //         .increaseObservationCardinalityNext(100);
    // }

    // function _setupPrinter(address nuassetMgrAddress,address numaMinterAddress,address vaultManagerAddress) internal {
    //     numaOracle = new NumaOracle(
    //         USDC_ARBI,
    //         INTERVAL_SHORT,
    //         INTERVAL_LONG,
    //         deployer,
    //         //address(nuAssetMgr)
    //         nuassetMgrAddress
    //     );

    //     usdcEthConverter = new USDCToEthConverter(
    //         PRICEFEEDUSDCUSD_ARBI,
    //         HEART_BEAT_CUSTOM,
    //         PRICEFEEDETHUSD_ARBI,
    //         HEART_BEAT_CUSTOM,
    //         UPTIME_FEED_ARBI,
    //         usdc.decimals()
    //     );

    //     moneyPrinter = new NumaPrinter(
    //         address(numa),
    //         //address(numaMinter),
    //         numaMinterAddress,
    //         NUMA_USDC_POOL_ADDRESS,
    //         address(usdcEthConverter),
    //         INumaOracle(numaOracle),
    //         //address(vaultManager)
    //         vaultManagerAddress
    //     );
    //     moneyPrinter.setPrintAssetFeeBps(printFee);
    //     moneyPrinter.setBurnAssetFeeBps(burnFee);
    //     moneyPrinter.setSwapAssetFeeBps(swapFee);

    //     moneyPrinter.setFeeAddress(payable(feeAddressPrinter),6000);//60%

    //     // add moneyPrinter as a numa minter
    //     NumaMinter(numaMinterAddress).addToMinters(address(moneyPrinter));

    //     // nuAssets
    //     nuUSD = new NuAsset2("nuUSD", "NUSD", deployer, deployer);
    //     // register nuAsset
    //     nuAssetManager(nuassetMgrAddress).addNuAsset(address(nuUSD), PRICEFEEDETHUSD_ARBI, HEART_BEAT_CUSTOM);
    //     // set printer as a NuUSD minter
    //     nuUSD.grantRole(MINTER_ROLE, address(moneyPrinter)); // owner is NuUSD deployer

    //     nuBTC = new NuAsset2("nuBTC", "NUBTC", deployer, deployer);
    //     // register nuAsset
    //     nuAssetManager(nuassetMgrAddress).addNuAsset(address(nuBTC), PRICEFEEDBTCETH_ARBI, HEART_BEAT);
    //     // set printer as a NuUSD minter
    //     nuBTC.grantRole(MINTER_ROLE, address(moneyPrinter)); // owner is NuUSD deployer

    //     // set printer to vaultManager
    //     VaultManager(vaultManagerAddress).setPrinter(address(moneyPrinter));
    // }

    function SwapNumaToUSDC() public {
        // // testing a swap to get a quote
        // numa.approve(address(swapRouter), type(uint).max);
        // usdc.approve(address(swapRouter), type(uint).max);
        // // swap 1000 numa
        // // swap 1 numa
        // // Naively set amountOutMinimum to 0. In production, use an oracle or other data source to choose a safer value for amountOutMinimum.
        // // We also set the sqrtPriceLimitx96 to be 0 to ensure we swap our exact input amount.
        // ISwapRouter.ExactInputSingleParams memory params =
        //     ISwapRouter.ExactInputSingleParams({
        //         tokenIn: address(numa),
        //         tokenOut: address(usdc),
        //         fee: FEE_LOW,
        //         recipient: deployer,
        //         deadline: block.timestamp,
        //         amountIn: 1000 ether,
        //         amountOutMinimum: 0,
        //         sqrtPriceLimitX96: 0
        //     });
        // // The call to `exactInputSingle` executes the swap.
        // uint amountOut = swapRouter.exactInputSingle(params);
        // console.log("swapping 1000 numa to");
        // console.log(amountOut);
        // ISwapRouter.ExactInputSingleParams memory params2 =
        //     ISwapRouter.ExactInputSingleParams({
        //         tokenIn: address(numa),
        //         tokenOut: address(usdc),
        //         fee: FEE_LOW,
        //         recipient: deployer,
        //         deadline: block.timestamp,
        //         amountIn: 1 ether,
        //         amountOutMinimum: 0,
        //         sqrtPriceLimitX96: 0
        //     });
        // // The call to `exactInputSingle` executes the swap.
        // uint amountOut2 = swapRouter.exactInputSingle(params2);
        // console.log("swapping 1 numa to");
        // console.log(amountOut2);
    }
}
