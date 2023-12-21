const { getPoolData, getPool, initPoolETH, addLiquidity, weth9, artifacts, swapOptions, buildTrade, SwapRouter, Token } = require("../scripts/Utils.js");
const { deployPrinterTestFixtureSepo, config } = require("./fixtures/NumaTestFixture.js");
const { time, loadFixture, takeSnapshot } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { upgrades } = require("hardhat");
// TODO: I should be able to get it from utils
const { Trade: V3Trade, Route: RouteV3 } = require('@uniswap/v3-sdk');
const { WETH_ADDRESS } = require("@uniswap/universal-router-sdk");

// ********************* Numa oracle test using sepolia fork for chainlink *************************


describe('SYNTHETIC SWAPPER', function () {
  let signer, signer2;
  let numaOwner;
  let numa;
  let nuUSD;
  let NUUSD_ADDRESS;
  let NUUSD_ETH_POOL_ADDRESS;
  let moneyPrinter;
  let MONEY_PRINTER_ADDRESS;
  // uniswap
  let nonfungiblePositionManager;
  let wethContract;
  // oracle
  let oracleAddress;
  // amount to be transfered to signer
  let numaAmount;

  let testData;// TODO: use mocha context?
  let numa_address;
  let NUMA_ETH_POOL_ADDRESS;
  let oracle;
  let cardinalityLaunch; // How many observations to save in a pool, at launch
  let factory;
  let snapshot;
  let swapRouter;
  let routerAddress;
  //
  let price;
  let sender;
  let intervalShort;
  let intervalLong;
  let amountInMaximum;
  let tokenIn;
  let tokenOut;
  let fee;
  let sqrtPriceLimitX96;

  let syntheticsSwapper;
  afterEach(async function () {
    //console.log("reseting snapshot");
    await snapshot.restore();
    snapshot = await takeSnapshot();
  })

  beforeEach(async function () {
    //console.log("calling before each");
  })


  before(async function () {
    testData = await loadFixture(deployPrinterTestFixtureSepo);

    signer = testData.signer;
    signer2 = testData.signer2;
    numaOwner = testData.numaOwner;
    numa = testData.numa;
    nuUSD = testData.nuUSD;
    NUUSD_ADDRESS = testData.NUUSD_ADDRESS;
    NUUSD_ETH_POOL_ADDRESS = testData.NUUSD_ETH_POOL_ADDRESS;
    moneyPrinter = testData.moneyPrinter;
    MONEY_PRINTER_ADDRESS = testData.MONEY_PRINTER_ADDRESS;
    nonfungiblePositionManager = testData.nonfungiblePositionManager;
    wethContract = testData.wethContract;
    oracleAddress = testData.oracleAddress;
    numaAmount = testData.numaAmount;

    numa_address = await numa.getAddress();
    NUMA_ETH_POOL_ADDRESS = testData.NUMA_ETH_POOL_ADDRESS;

    const Oracle = await ethers.getContractFactory('NumaOracle');
    oracle = await Oracle.attach(oracleAddress);
    cardinalityLaunch = testData.cardinality;
    factory = testData.factory;

    swapRouter = testData.swapRouter;
    routerAddress = await swapRouter.getAddress();

    // code that could be put in beforeEach but as we snapshot and restore, we
    // can put it here
    intervalShort = config.INTERVAL_SHORT;
    intervalLong = config.INTERVAL_LONG;
    amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    tokenIn = NUUSD_ADDRESS;
    tokenOut = config.WETH_ADDRESS;
    fee = Number(config.FEE);
    sqrtPriceLimitX96 = "0x0";

    // chainlink price ETHUSD
    let chainlinkInstance = await hre.ethers.getContractAt(artifacts.AggregatorV3, config.PRICEFEEDETHUSD);
    let latestRoundData = await chainlinkInstance.latestRoundData();
    let latestRoundPrice = Number(latestRoundData.answer);
    let decimals = Number(await chainlinkInstance.decimals());
    price = latestRoundPrice / 10 ** decimals;

    // mint nuUSD
    sender = await signer2.getAddress();
    await nuUSD.mint(sender, BigInt(1e23));

    // get some weth
    await wethContract.connect(signer2).deposit({
      value: ethers.parseEther('10'),
    });

    // approve router
    await nuUSD.connect(signer2).approve(routerAddress, amountInMaximum);
    await wethContract.connect(signer2).approve(routerAddress, amountInMaximum);


    // Deploy Swapper
    syntheticsSwapper = await ethers.deployContract("SyntheticSwapper",
    [numa_address]);
    await syntheticsSwapper.waitForDeployment();
    let swapperAddress = await syntheticsSwapper.getAddress();
    console.log(`synthetics swapper deployed to: ${swapperAddress}`);

    await syntheticsSwapper.setPrinter(NUUSD_ADDRESS, MONEY_PRINTER_ADDRESS);
 
    // TODO: btc

    snapshot = await takeSnapshot();

  });

  it('Should have right initialization parameters', async function () {
  
    expect(await syntheticsSwapper.numa()).to.equal(numa_address);

    // test token/printers list

    // try to add a printer and check events

    // try to add wrong printer and check revert


  });
  



  describe('#swap tests', () => {

    it('without the right printer', async () => {
    });


    it('nuAsset 1 above threshold, nuAsset 2 above threshold', async () => {
    });
    it('nuAsset 1 above threshold, nuAsset 2 below threshold', async () => {
    });
    it('nuAsset 1 below threshold, nuAsset 2 above threshold', async () => {
    });
    it('nuAsset 1 below threshold, nuAsset 2 below threshold', async () => {
    });

    it('revert if min/max not respected', async () => {
    });

  });

  it('Owner', async function () {
  


  });

  it('Pausable', async function () {
  


  });






});

