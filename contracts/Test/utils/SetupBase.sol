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
import {NUMA} from "../../Numa.sol";

// forge test --fork-url <your_rpc_url>
contract SetupBase is
    ExtendedTest,
    ConstantsTest //, IEvents {
{
    // Contract instances that we will use repeatedly.
    // Tokens

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

    // uniswap
    INonfungiblePositionManager internal nonfungiblePositionManager;
    IUniswapV3Factory internal factory;
    ISwapRouter public swapRouter;

    //
    int ethusd;

    function _setUpTokens() internal virtual {
        //
        rEth = ERC20(RETH_ADDRESS_ARBI);
        usdc = ERC20(USDC_ARBI);
    }

    function _setupVaultAndAssetManager(
        uint128 _heartbeat,
        address _feereceiver,
        address _rwdreceiver,
        uint _rethAmount,
        NUMA numa
    ) internal {
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
            _heartbeat,
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
        vault.setFeeAddress(_feereceiver, false);
        vault.setRwdAddress(_rwdreceiver, false);

        // // setup V2 decay to match V1
        // // TODO

        // transfer rEth to vault to initialize price
        rEth.transfer(address(vault), _rethAmount);
        // unpause V2
        vault.unpause();
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
        console.log("encoding price");
        console2.log(_reserve0);
        console2.log(_reserve1);

        uint160 sqrtPrice = encodePriceSqrt(_reserve1, _reserve0);
        console.log("mint pool");

        mintNewPool(_token0, _token1, FEE_LOW, sqrtPrice);

        console.log("mint position");
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
