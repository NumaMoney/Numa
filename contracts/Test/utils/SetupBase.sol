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
import "./TickHelper.sol";
import "./Math.sol";
import {encodePriceSqrt} from "./Math.sol";
//
import {ExtendedTest} from "./ExtendedTest.sol";
import {ConstantsTest} from "./ConstantsTest.sol";
//
import {FakeNuma} from "../mocks/FakeNuma.sol";
import "../../interfaces/INuma.sol";

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
import "../../lending/JumpRateModelV4.sol";
import "../../lending/CNumaLst.sol";
import "../../lending/CNumaToken.sol";
import "../../lending/NumaPriceOracleNew.sol";
import "../../lending/ExponentialNoError.sol";
import "../../lending/ComptrollerStorage.sol";
import {NUMA} from "../../Numa.sol";

import "../../deployment/utils.sol";

// forge test --fork-url <your_rpc_url>
contract SetupBase is
    ExtendedTest,
    ConstantsTest,deployUtils {//, IEvents {

    // Contract instances that we will use repeatedly.
    // Tokens
    INuma numa;
    address numa_admin;
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
    JumpRateModelV4 rateModelV4;
    CNumaLst cReth;
    CNumaToken cNuma;

    // Addresses for different roles we will use repeatedly.
    address public deployer = makeAddr("deployer");

    address public feeAddressPrinter = makeAddr("feePrinterAddy");
    address public userA = makeAddr("userA");
    address public userB = makeAddr("userB");
    address public userC = makeAddr("userC");
    // uniswap
    INonfungiblePositionManager internal nonfungiblePositionManager;
    IUniswapV3Factory internal factory;
    ISwapRouter public swapRouter;

    //
    int ethusd;
    int btcusd;
    int btceth;
    int usdcusd;
    function _setUpTokens() internal virtual {
        //
        rEth = ERC20(RETH_ADDRESS_ARBI);
        usdc = ERC20(USDC_ARBI);
    }

    function _setupVaultAndAssetManager(
        uint128 _heartbeat,
        address _feereceiver,
        address _rwdreceiver,
        INuma _numa,
        uint _debt,
        uint _rwdfromDebt,
        address _existingAssetManager,
        address _existingNumaminter
    )
        internal
        returns (
            nuAssetManager nuAM,
            NumaMinter minter,
            VaultManager vaultm,
            VaultOracleSingle vo,
            NumaVault v
        )
    {
        deployUtils.deployVaultParameters memory parameters = deployUtils.deployVaultParameters(
            _heartbeat,
            UPTIME_FEED_ARBI,
            PRICEFEEDRETHETH_ARBI,
            _feereceiver,
            _rwdreceiver,
            _numa,
            _debt,
            _rwdfromDebt,
            _existingAssetManager,
            _existingNumaminter,
            address(0),// vaultOracle
            address(rEth)
        );

         nuAM = new nuAssetManager(UPTIME_FEED_ARBI);
        (nuAM, minter, vaultm, vo, v) = setupVaultAndAssetManager(parameters);

      
    }

    function _setupVault(
        VaultOracleSingle _vo,
        address _minter,
        address _vaultm,
        INuma _numa,
        uint _debt,
        uint _rwdfromDebt
    ) internal returns (NumaVault v) {
        // vault
        v = setupVault(_vo, _minter, _vaultm, _numa, _debt, _rwdfromDebt);
    }

    function _setupPrinter(
        address nuassetMgrAddress,
        address numaMinterAddress,
        address vaultManagerAddress
    ) internal returns (NumaOracle o, USDCToEthConverter c, NumaPrinter p) {
        //console2.log("pool address: ", NUMA_USDC_POOL_ADDRESS);
        o = new NumaOracle(
            USDC_ARBI,
            INTERVAL_SHORT,
            INTERVAL_LONG,
            deployer,
            //address(nuAssetMgr)
            nuassetMgrAddress
        );

        c = new USDCToEthConverter(
            PRICEFEEDUSDCUSD_ARBI,
            HEART_BEAT_CUSTOM,
            PRICEFEEDETHUSD_ARBI,
            HEART_BEAT_CUSTOM,
            UPTIME_FEED_ARBI //,
            //usdc.decimals()
        );

        p = new NumaPrinter(
            address(numa),
            //address(numaMinter),
            numaMinterAddress,
            NUMA_USDC_POOL_ADDRESS,
            address(c),
            INumaOracle(o),
            //address(vaultManager)
            vaultManagerAddress
        );
        p.setPrintAssetFeeBps(printFee);
        p.setBurnAssetFeeBps(burnFee);
        p.setSwapAssetFeeBps(swapFee);

        p.setFeeAddress(payable(feeAddressPrinter), 6000); //60%

        // add moneyPrinter as a numa minter
        NumaMinter(numaMinterAddress).addToMinters(address(p));

        // set printer to vaultManager
        VaultManager(vaultManagerAddress).setPrinter(address(p));
    }

    function _createNuAssets() internal {
        // nuAssets
        nuUSD = new NuAsset2("nuUSD", "NUSD", deployer, deployer);
        nuBTC = new NuAsset2("nuBTC", "NUBTC", deployer, deployer);
    }

    function _linkNuAssets(
        address _nuAssetMgrAddress,
        address _printerAddress
    ) internal {
        // register nuAsset
        nuAssetManager(_nuAssetMgrAddress).addNuAsset(
            address(nuUSD),
            PRICEFEEDETHUSD_ARBI,
            HEART_BEAT_CUSTOM
        );
        // set printer as a NuUSD minter
        nuUSD.grantRole(MINTER_ROLE, _printerAddress); // owner is NuUSD deployer

        // register nuAsset
        nuAssetManager(_nuAssetMgrAddress).addNuAsset(
            address(nuBTC),
            PRICEFEEDBTCETH_ARBI,
            HEART_BEAT
        );
        // set printer as a NuUSD minter
        nuBTC.grantRole(MINTER_ROLE, _printerAddress); // owner is NuUSD deployer
    }

    function _setupPool_Numa_Usdc() internal {
        uint USDCAmount = 200000;
        uint USDCAmountNumaPool = USDCAmount * 1000000; //6 decimals
        uint NumaAmountNumaPoolUSDC = USDTONUMA * USDCAmount * 1 ether; // 18 decimals

        NUMA_USDC_POOL_ADDRESS = _setupUniswapPool(
            usdc,
            ERC20(address(numa)),
            USDCAmountNumaPool,
            NumaAmountNumaPoolUSDC
        );

        // advance in time for avg prices to work
        skip(INTERVAL_LONG * 2);
        vm.roll(block.number + 1);
        IUniswapV3Pool(NUMA_USDC_POOL_ADDRESS)
            .increaseObservationCardinalityNext(100);
    }

    function _setupLending(NumaVault _vault) internal {
        // COMPTROLLER
        comptroller = new NumaComptroller();
        comptroller._setBorrowCapGuardian(deployer);
        comptroller._setPauseGuardian(deployer);
   

        // PRICE ORACLE
        numaPriceOracle = new NumaPriceOracleNew();
        //numaPriceOracle.setVault(address(vault));
        comptroller._setPriceOracle((numaPriceOracle));
        // INTEREST RATE MODEL
        uint maxUtilizationRatePerBlock = maxUtilizationRatePerYear /
            blocksPerYear;

        // standard jump rate model V4
        rateModelV4 = new JumpRateModelV4(
            blocksPerYear,
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink,
            deployer,
            "numaJumpRateModel"
        );

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
            address(_vault)
        );

        cNuma = new CNumaToken(
            address(numa),
            comptroller,
            rateModelV4,
            200000000000000000000000000,
            "numa CToken",
            "cNuma",
            8,
            maxUtilizationRatePerBlock,
            payable(deployer),
            address(_vault)
        );

        _vault.setMaxBorrow(1000 ether);
        _vault.setCTokens(address(cNuma), address(cReth));

        // add markets (has to be done before _setcollateralFactor)
        comptroller._supportMarket((cNuma));
        comptroller._supportMarket((cReth));

        // collateral factors
        comptroller._setCollateralFactor((cNuma), numaCollateralFactor);
        comptroller._setCollateralFactor((cReth), rEthCollateralFactor);

        //ExponentialNoError.Exp memory collateralFactor = ExponentialNoError.Exp({mantissa: markets[address(cNuma)].collateralFactorMantissa});
        uint collateralFactor = comptroller.collateralFactor(cNuma);
        //console2.log(collateralFactor);

        // 100% liquidation close factor
        comptroller._setCloseFactor(1 ether);
        comptroller._setLiquidationIncentive(1.02 ether);
        vault.setMaxLiquidationsProfit(10 ether);

        // strategies
        // deploy strategy
        NumaLeverageVaultSwap strat0 = new NumaLeverageVaultSwap(
            address(_vault)
        );
        cReth.addStrategy(address(strat0));
        cNuma.addStrategy(address(strat0));
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
            address tokentmp = token0;
            uint amounttmp = amount0ToMint;
            token0 = token1;
            token1 = tokentmp;
            amount0ToMint = amount1ToMint;
            amount1ToMint = amounttmp;
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

    function _setupUniswapPool(
        ERC20 token0,
        ERC20 token1,
        uint amount0,
        uint amount1
    ) internal returns (address) {
        nonfungiblePositionManager = INonfungiblePositionManager(
            POSITION_MANAGER_ARBI
        );
        factory = IUniswapV3Factory(FACTORY_ARBI);
        swapRouter = ISwapRouter(SWAPROUTER_ARBI);

        // Uniswap reverts pool initialization if you don't sort by address number, beware!
        address _token0 = address(token0);
        address _token1 = address(token1);

        uint _reserve0 = amount0;
        uint _reserve1 = amount1;

        if (_token0 >= _token1) {
            (_reserve0, _reserve1) = (_reserve1, _reserve0);
            (_token0, _token1) = (_token1, _token0);
        }
        // console.log("encoding price");
        // console2.log(_reserve0);
        // console2.log(_reserve1);

        uint160 sqrtPrice = encodePriceSqrt(_reserve1, _reserve0);
        //console.log("mint pool");

        mintNewPool(_token0, _token1, FEE_LOW, sqrtPrice);

        //console.log("mint position");
        // add liquidity
        mintNewPosition(
            _token0,
            _token1,
            FEE_LOW,
            getMinTick(TICK_MEDIUM),
            getMaxTick(TICK_MEDIUM),
            _reserve0,
            _reserve1
        );
        return factory.getPool(_token0, _token1, FEE_LOW);
    }
}
