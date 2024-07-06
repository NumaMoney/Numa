// what to test

// - staking LP, staker owns LP token
// - unstaking OK, user gets all his tokens back
// - addpool, set infos
// - pendingSushi
// - claim
// - emergency withdraw
// - ownable


const { getPoolData, getPool, initPoolETH, addLiquidity, weth9, artifacts, swapOptions, buildTrade, SwapRouter, Token } = require("../../scripts/Utils.js");
const { deployPrinterTestFixture, config } = require("./fixtures/NumaPrinterTestFixtureDeployNuma.js");
const { time, loadFixture, takeSnapshot } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { upgrades } = require("hardhat");
// TODO: I should be able to get it from utils
const { Trade: V3Trade, Route: RouteV3 } = require('@uniswap/v3-sdk');
const { WETH_ADDRESS } = require("@uniswap/universal-router-sdk");

// ********************* Numa oracle test using sepolia fork for chainlink *************************


describe('NUMA STAKING', function () {
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
  let masterChef;
  let numaPerBlock = 1000;
  let startBlock;
  let poolAllocPoint = 10;
  afterEach(async function () 
  {
    await snapshot.restore();
    snapshot = await takeSnapshot();
  })

  beforeEach(async function () 
  {
    //console.log("calling before each");
  })


  before(async function () {
    testData = await loadFixture(deployPrinterTestFixture);

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
    intervalShort = 180;
    intervalLong = 1800;
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

    // deploy masterchef 
    // NUMA _numa,
    // uint256 _sushiPerBlock,
    // uint256 _startBlock,
    // uint256 _bonusEndBlock,address initialOwner


    const latestBlock = await hre.ethers.provider.getBlockNumber();
    startBlock = latestBlock;
   
    console.log(startBlock);
    masterChef = await ethers.deployContract("MasterChef",
    [numa_address,numaPerBlock, startBlock, await signer.getAddress()]);
    await masterChef.waitForDeployment();

  
    // add pool NUMA/ETH
    await masterChef.add(poolAllocPoint,NUMA_ETH_POOL_ADDRESS,false);

    snapshot = await takeSnapshot();

    

  });

  it('Should have right initialization parameters', async function () 
  {
    await masterChef.add(poolAllocPoint,NUUSD_ETH_POOL_ADDRESS,false);
    expect(await masterChef.numa()).to.equal(numa_address);
    expect(await masterChef.numaPerBlock()).to.equal(numaPerBlock);
    expect(await masterChef.totalAllocPoint()).to.equal(20);
    expect(await masterChef.startBlock()).to.equal(startBlock);
    expect(await masterChef.poolLength()).to.equal(2);
   
  });

 

  describe('#set parameters', () => {
    it('Should be able to set parameters', async function () {
        // uint256 public sushiPerBlock;
        // add pool
        // remove pool?
        // change alloc points
        

    });
  })

  describe('#stake&claim', () => {
    it('Should be able to stake LP', async function () 
    {
      // signer2 adds liquidity
      let offset = 3600 * 10000000;// TODO 
      let timestamp = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
      timestamp += 1800; // Time advanced 30min in migration to allow for the long interval

      //
      let EthPriceInNuma = price * 2;

      // add 10 ethers so that we own half the liquidity
      // 10 ethers
      let nbEthers = 10;
      let EthAmountNumaPool = ethers.parseEther(nbEthers.toString());
      let NumaAmountNumaPool = ethers.parseEther((nbEthers * EthPriceInNuma).toString());

      // log lp balance
      let bal = await nuUSD.balanceOf(sender);

      await addLiquidity(
        config.WETH_ADDRESS,
        numa_address,
        wethContract,
        numa,
        config.FEE,
        config.TICKMIN,
        config.TICKMAX,
        EthAmountNumaPool,
        NumaAmountNumaPool,
        BigInt(0),
        BigInt(0),
        signer2,
        timestamp,
        nonfungiblePositionManager
      );
    
      // stake

      // check
        

    });
    it('Should be able to claim', async function () {
        

    });

  })

  describe('#stake&unstake', () => {
    it('Should be able to stake LP', async function () {
        

    });
    it('Should be able to unstake and claim', async function () {
        

    });
  })

  describe('#stake&emergencyWithdraw', () => {
    it('Should be able to stake LP', async function () {
        

    });
    it('Should be able to emergency withdraw', async function () {
        

    });

  })



  describe('#ownable', () => {
    it('Should implement Ownable', async function () {

    });

  })





});

