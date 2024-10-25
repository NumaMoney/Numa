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
    FakeNuma numa;
    address public vaultFeeReceiver = makeAddr("vaultFeeReceiver");
    address public vaultRwdReceiver = makeAddr("vaultRwdReceiver");

    function setUp() public virtual {

        // setup fork
        //string memory ARBI_RPC_URL = vm.envString("URL7");
        string memory ARBI_RPC_URL = vm.envString("URL6");
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

        
        //console.log(ethusd);
        // RETHETH
        AggregatorV2V3Interface dataFeedRETHETH = AggregatorV2V3Interface(
            PRICEFEEDRETHETH_ARBI
        );
        (, int answerRETHETH, , , ) = dataFeedRETHETH.latestRoundData();
        // 1e8 to account for decimals in chainlink prices
        uint amountReth = (1 ether * numaSupply * 1e8) /
            (USDTONUMA * uint(ethusd) * uint(answerRETHETH));
        _setupVaultAndAssetManager(
            HEART_BEAT_CUSTOM,
            vaultFeeReceiver,
            vaultRwdReceiver,
            amountReth,
            NUMA(address(numa))
        );
        _setupPool_Numa_Usdc();
        _setupPrinter();
        _setupLending();
    }

    function _setUpTokens() internal override {
        SetupBase._setUpTokens();
        // Numa
        numa = new FakeNuma(deployer, deployer, deployer); // admin, pauser, minter
        numa.mint(deployer, numaSupply);
    }

    function _setupPool_Numa_Usdc() internal {
        uint USDCAmount = 200000;
        uint USDCAmountNumaPool = USDCAmount * 1000000; //6 decimals
        uint NumaAmountNumaPoolUSDC = USDTONUMA * USDCAmount * 1 ether; // 18 decimals

        NUMA_USDC_POOL_ADDRESS = _setupUniswapPool(
            usdc,
            numa,
            USDCAmountNumaPool,
            NumaAmountNumaPoolUSDC
        );

        // advance in time for avg prices to work
        skip(INTERVAL_LONG*2);
        vm.roll(block.number + 1);
        IUniswapV3Pool(NUMA_USDC_POOL_ADDRESS)
            .increaseObservationCardinalityNext(100);
    }

    // function _setupUniswapPool() internal
    // {
    //     // WORKS
    //     nonfungiblePositionManager = INonfungiblePositionManager(POSITION_MANAGER_ARBI);
    //     factory = IUniswapV3Factory(FACTORY_ARBI);
    //     swapRouter = ISwapRouter(SWAPROUTER_ARBI);
    //     //uint USDCPriceInNuma = 2000000000000;// 12 decimals because USDC has 6 decimals

    //     // Uniswap reverts pool initialization if you don't sort by address number, beware!
    //     address _token0 = address(usdc);
    //     address _token1 = address(numa);
    //     // uint _reserve0 = 1*1000000;//6 decimals
    //     // uint _reserve1 = USDTONUMA * 1 ether;// 18 decimals
    //     uint USDCAmount = 200000;
    //     uint USDCAmountNumaPool = USDCAmount*1000000;//6 decimals
    //     uint NumaAmountNumaPoolUSDC = USDTONUMA * USDCAmount*1 ether;// 18 decimals

    //     uint _reserve0 = USDCAmountNumaPool;
    //     uint _reserve1 = NumaAmountNumaPoolUSDC;

    //     if (_token0 >= _token1)
    //     {
    //         (_reserve0,_reserve1) = (_reserve1,_reserve0);
    //         (_token0,_token1) = (_token1,_token0);
    //     }

    //     console.log(_reserve0);
    //     console.log(_reserve1);
    //     uint160 sqrtPrice = encodePriceSqrt(_reserve1,_reserve0);
    //     console.log("mint pool");
    //     // create USDC/NUMA pool
    //     mintNewPool(_token0, _token1, FEE_LOW, sqrtPrice);

    //     console.log("mint position");
    //     // add liquidity
    //     mintNewPosition(
    //         _token0, _token1, FEE_LOW, getMinTick(TICK_MEDIUM), getMaxTick(TICK_MEDIUM), _reserve0, _reserve1
    //     );

    //     NUMA_USDC_POOL_ADDRESS = factory.getPool(_token0,_token1,FEE_LOW);
    //     console.log(NUMA_USDC_POOL_ADDRESS);

    //     // advance in time for avg prices to work
    //     skip(INTERVAL_LONG);
    //     IUniswapV3Pool(NUMA_USDC_POOL_ADDRESS).increaseObservationCardinalityNext(10);
    // }
    function _setupPrinter() internal {
        numaOracle = new NumaOracle(
            USDC_ARBI,
            INTERVAL_SHORT,
            INTERVAL_LONG,
            deployer,
            address(nuAssetMgr)
        );

        usdcEthConverter = new USDCToEthConverter(
            PRICEFEEDUSDCUSD_ARBI,
            HEART_BEAT_CUSTOM,
            PRICEFEEDETHUSD_ARBI,
            HEART_BEAT_CUSTOM,
            UPTIME_FEED_ARBI,
            usdc.decimals()
        );

        moneyPrinter = new NumaPrinter(
            address(numa),
            address(numaMinter),
            NUMA_USDC_POOL_ADDRESS,
            address(usdcEthConverter),
            INumaOracle(numaOracle),
            address(vaultManager)
        );
        moneyPrinter.setPrintAssetFeeBps(printFee);
        moneyPrinter.setBurnAssetFeeBps(burnFee);
        moneyPrinter.setSwapAssetFeeBps(swapFee);

        // add moneyPrinter as a numa minter
        numaMinter.addToMinters(address(moneyPrinter));
        // add vault as a numa minter
        numaMinter.addToMinters(address(vault));

        // nuAssets
        nuUSD = new NuAsset2("nuUSD", "NUSD", deployer, deployer);
        // register nuAsset
        nuAssetMgr.addNuAsset(address(nuUSD), PRICEFEEDETHUSD_ARBI, HEART_BEAT);
        // set printer as a NuUSD minter
        nuUSD.grantRole(MINTER_ROLE, address(moneyPrinter)); // owner is NuUSD deployer

        nuBTC = new NuAsset2("nuBTC", "NUBTC", deployer, deployer);
        // register nuAsset
        nuAssetMgr.addNuAsset(address(nuBTC), PRICEFEEDBTCETH_ARBI, HEART_BEAT);
        // set printer as a NuUSD minter
        nuBTC.grantRole(MINTER_ROLE, address(moneyPrinter)); // owner is NuUSD deployer

        // set printer to vaultManager
        vaultManager.setPrinter(address(moneyPrinter));
    }

    function _setupLending() internal {
        // COMPTROLLER
        comptroller = new NumaComptroller();

        // PRICE ORACLE
        numaPriceOracle = new NumaPriceOracleNew();
        numaPriceOracle.setVault(address(vault));
        comptroller._setPriceOracle((numaPriceOracle));
        // INTEREST RATE MODEL
        uint maxUtilizationRatePerBlock = maxUtilizationRatePerYear /
            blocksPerYear;

        // perblock
        uint _zeroUtilizationRatePerBlock = (_zeroUtilizationRate /
            blocksPerYear);
        uint _minFullUtilizationRatePerBlock = (_minFullUtilizationRate /
            blocksPerYear);
        uint _maxFullUtilizationRatePerBlock = (_maxFullUtilizationRate /
            blocksPerYear);

        rateModel = new JumpRateModelVariable(
            "numaRateModel",
            _vertexUtilization,
            _vertexRatePercentOfDelta,
            _minUtil,
            _maxUtil,
            _zeroUtilizationRatePerBlock,
            _minFullUtilizationRatePerBlock,
            _maxFullUtilizationRatePerBlock,
            _rateHalfLife,
            deployer
        );

        // CTOKENS
        cReth = new CNumaLst(
            address(rEth),
            comptroller,
            rateModel,
            200000000000000000000000000,
            "rEth CToken",
            "crEth",
            8,
            maxUtilizationRatePerBlock,
            payable(deployer),
            address(vault)
        );

        cNuma = new CNumaToken(
            address(numa),
            comptroller,
            rateModel,
            200000000000000000000000000,
            "numa CToken",
            "cNuma",
            8,
            maxUtilizationRatePerBlock,
            payable(deployer),
            address(vault)
        );

        vault.setMaxBorrow(1000 ether);
        vault.setCTokens(address(cNuma), address(cReth));
        vault.setMinLiquidationsPc(250); //25% min
        // add markets (has to be done before _setcollateralFactor)
        comptroller._supportMarket((cNuma));
        comptroller._supportMarket((cReth));

        // collateral factors
        comptroller._setCollateralFactor((cNuma), numaCollateralFactor);
        comptroller._setCollateralFactor((cReth), rEthCollateralFactor);

        // DBG
        console2.log("**********************");

        //ExponentialNoError.Exp memory collateralFactor = ExponentialNoError.Exp({mantissa: markets[address(cNuma)].collateralFactorMantissa});
        uint collateralFactor = comptroller.collateralFactor(cNuma);
        console2.log(collateralFactor);

        // 50% liquidation close factor
        comptroller._setCloseFactor(0.5 ether);

        // strategies
        // deploy strategy
        NumaLeverageVaultSwap strat0 = new NumaLeverageVaultSwap(
            address(vault)
        );
        cReth.addStrategy(address(strat0));

      
    }

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
