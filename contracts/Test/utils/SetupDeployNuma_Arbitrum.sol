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
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
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

import {NumaComptroller} from "../../lending/NumaComptroller.sol";
import "../../lending/JumpRateModelVariable.sol";
import "../../lending/CNumaLst.sol";
import "../../lending/CNumaToken.sol";
import "../../lending/NumaPriceOracleNew.sol";
import "../../lending/ExponentialNoError.sol";
import "../../lending/ComptrollerStorage.sol";

// forge test --fork-url <your_rpc_url>
contract Setup is
    ExtendedTest,
    ConstantsTest //, IEvents {
{
    // Contract instances that we will use repeatedly.
    // Tokens
    FakeNuma numa;
    ERC20 rEth;
    ERC20 usdc;
    // Vault
    nuAssetManager nuAssetMgr;
    NumaMinter numaMinter;
    VaultOracleSingle vaultOracle;
    VaultManager vaultManager;
    NumaVault vault;
    // Printer
    address NUMA_USDC_POOL_ADDRESS;
    INumaOracle numaOracle;
    NumaPrinter moneyPrinter;
    INumaTokenToEthConverter usdcEthConverter;

    NuAsset2 nuUSD;
    NuAsset2 nuBTC;

    // Lending
    NumaComptroller comptroller;
    NumaPriceOracleNew numaPriceOracle;
    JumpRateModelVariable rateModel;
    CNumaLst cReth;
    CNumaToken cNuma;

    // Addresses for different roles we will use repeatedly.
    address public deployer = makeAddr("deployer");
    address public userA = makeAddr("userA");
    address public vaultFeeReceiver = makeAddr("vaultFeeReceiver");

    // uniswap
    INonfungiblePositionManager internal nonfungiblePositionManager;
    IUniswapV3Factory internal factory;
    //
    int ethusd;
    function setUp() public virtual {
        // setup fork
        string memory ARBI_RPC_URL = vm.envString("URL5");
        uint256 arbitrumFork = vm.createFork(ARBI_RPC_URL);
        vm.selectFork(arbitrumFork);
        // prank deployer
        vm.startPrank(deployer);
        // setups
        _setUpTokens();
        _setupVaultAndAssetManager();
        _setupUniswapPool();
        _setupPrinter();
        _setupLending();
    }

    function _setUpTokens() internal {
        // Numa
        numa = new FakeNuma(deployer, deployer, deployer); // admin, pauser, minter
        numa.mint(deployer, numaSupply);

        //
        rEth = ERC20(RETH_ADDRESS_ARBI);
        usdc = ERC20(USDC_ARBI);
    }

    function _setupVaultAndAssetManager() internal {
        // nuAssetManager
        nuAssetMgr = new nuAssetManager(UPTIME_FEED_ARBI);

        // numaMinter
        numaMinter = new NumaMinter();
        numaMinter.setTokenAddress(address(numa));

        numa.grantRole(MINTER_ROLE, address(numaMinter));

        // vault manager
        vaultManager = new VaultManager(address(numa), address(nuAssetMgr));
        // custom heartbeat to support advance in time
        vaultOracle = new VaultOracleSingle(
            address(rEth),
            PRICEFEEDRETHETH_ARBI,
            402 * 86400,
            UPTIME_FEED_NULL
        );
        // vault
        vault = new NumaVault(
            address(numa),
            address(rEth),
            1 ether,
            address(vaultOracle),
            address(numaMinter)
        );
        vaultManager.addVault(address(vault));
        vault.setVaultManager(address(vaultManager));
        vault.setFeeAddress(vaultFeeReceiver, false);

        // // setup V2 decay to match V1
        // // TODO

        // get reth and send to vault
        deal({token: address(rEth), to: deployer, give: 10000 ether});
        deal({token: USDC_ARBI, to: deployer, give: 100000000000000});

        // need to setup vault price same as pool price: 1 numa = 0.5 usd
        // ETHUSD
        AggregatorV2V3Interface dataFeedETHUSD = AggregatorV2V3Interface(
            PRICEFEEDETHUSD_ARBI
        );
        (, ethusd, , , ) = dataFeedETHUSD.latestRoundData();
        //console.log(ethusd);
        // RETHETH
        AggregatorV2V3Interface dataFeedRETHETH = AggregatorV2V3Interface(
            PRICEFEEDRETHETH_ARBI
        );
        (, int answerRETHETH, , , ) = dataFeedRETHETH.latestRoundData();
        //console.log(answerRETHETH);

        // 1e8 to account for decimals in chainlink prices
        uint amountReth = (1 ether * numaSupply * 1e8) /
            (USDTONUMA * uint(ethusd) * uint(answerRETHETH));
        //console.log(amountReth);

        // transfer rEth to vault to initialize price
        rEth.transfer(address(vault), amountReth);
        // unpause V2
        vault.unpause();
    }

    function _setupUniswapPool() internal {
        nonfungiblePositionManager = INonfungiblePositionManager(
            POSITION_MANAGER_ARBI
        );
        factory = IUniswapV3Factory(FACTORY_ARBI);
        //uint USDCPriceInNuma = 2000000000000;// 12 decimals because USDC has 6 decimals

        // Uniswap reverts pool initialization if you don't sort by address number, beware!
        address _token0 = USDC_ARBI;
        address _token1 = address(numa);
        uint _reserve0 = 1 * 1000000; //6 decimals
        uint _reserve1 = USDTONUMA * 1 ether; // 18 decimals
        if (_token0 >= _token1) {
            (_reserve0, _reserve1) = (_reserve1, _reserve0);
        }

        uint160 sqrtPrice = encodePriceSqrt(_reserve0, _reserve1);

        // create USDC/NUMA pool
        mintNewPool(_token0, _token1, FEE_LOW, sqrtPrice);

        // add liquidity
        uint USDCAmount = 200000;
        uint USDCAmountNumaPool = USDCAmount * 1000000; //6 decimals
        uint NumaAmountNumaPoolUSDC = USDTONUMA * USDCAmount * 1 ether; // 18 decimals
        mintNewPosition(
            _token0,
            _token1,
            FEE_LOW,
            getMinTick(TICK_MEDIUM),
            getMaxTick(TICK_MEDIUM),
            USDCAmountNumaPool,
            NumaAmountNumaPoolUSDC
        );
        NUMA_USDC_POOL_ADDRESS = factory.getPool(_token0, _token1, FEE_LOW);
        //console.log(NUMA_USDC_POOL_ADDRESS);

        // advance in time for avg prices to work
        skip(INTERVAL_LONG);
        IUniswapV3Pool(NUMA_USDC_POOL_ADDRESS)
            .increaseObservationCardinalityNext(10);
    }
    function _setupPrinter() internal {
        numaOracle = new NumaOracle(
            USDC_ARBI,
            INTERVAL_SHORT,
            INTERVAL_LONG,
            deployer,
            address(nuAssetMgr)
        );

        usdcEthConverter = new USDCToEthConverter(
            PRICEFEEDUSDCUDC_ARBI,
            HEART_BEAT_CUSTOM,
            PRICEFEEDETHUSD_ARBI,
            HEART_BEAT_CUSTOM,
            UPTIME_FEED_ARBI
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
    }

    function mintNewPool(
        address token0,
        address token1,
        uint24 fee,
        uint160 currentPrice
    ) internal virtual returns (address) {
        (token0, token1) = token0 < token1
            ? (token0, token1)
            : (token1, token0);
        return
            nonfungiblePositionManager.createAndInitializePoolIfNecessary(
                token0,
                token1,
                fee,
                currentPrice
            );
    }
    function mintNewPosition(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0ToMint,
        uint256 amount1ToMint
    )
        internal
        virtual
        returns (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        )
    {
        if (token0 >= token1) {
            address t0 = token0;
            uint amount0 = amount0ToMint;
            token0 = token1;
            token1 = t0;
            amount0ToMint = amount1ToMint;
            amount1ToMint = amount0;
        }

        uint dl = vm.getBlockTimestamp() + 3600000000000;
        INonfungiblePositionManager.MintParams
            memory liquidityParams = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                recipient: deployer,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                deadline: dl
            });
        ERC20(token0).approve(POSITION_MANAGER_ARBI, type(uint256).max);
        ERC20(token1).approve(POSITION_MANAGER_ARBI, type(uint256).max);
        nonfungiblePositionManager.mint(liquidityParams);
    }
}
