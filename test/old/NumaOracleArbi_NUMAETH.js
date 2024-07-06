const { getPoolData, getPool, initPoolETH, addLiquidity, weth9, artifacts, swapOptions, buildTrade, SwapRouter, Token } = require("../../scripts/Utils.js");
const { deployNumaNumaPoolnuAssetsPrinters, configArbi } = require("../fixtures/NumaTestFixtureNew.js");
const { time, loadFixture, takeSnapshot } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { upgrades } = require("hardhat");


// ********************* Numa oracle test using arbitrum fork for chainlink *************************
const epsilon = ethers.parseEther('0.00000000001');

describe('NUMA ORACLE', function () {
  let signer, signer2;
  let sender;
  let numaOwner;
  let numa;
  let nuUSD;
  let NUUSD_ADDRESS;
  let NUBTC_ADDRESS;
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
  let decimals;
 
  let intervalShort;
  let intervalLong;
  let amountInMaximum;
  let tokenIn;
  let tokenOut;
  let fee;
  let sqrtPriceLimitX96;
  let VaultManager;
  let snapshotGlobal;
  afterEach(async function () {
    //console.log("reseting snapshot");
    await snapshot.restore();
    snapshot = await takeSnapshot();
  })

  beforeEach(async function () {
    //console.log("calling before each");
  })

  after(async function () {
    await snapshotGlobal.restore();
  });


  before(async function () {
    testData = await loadFixture(deployNumaNumaPoolnuAssetsPrinters);

    snapshotGlobal = testData.snapshotGlobal;
    signer = testData.signer;
    sender = await signer.getAddress();
    signer2 = testData.signer2;
    numaOwner = testData.numaOwner;
    numa = testData.numa;
    nuUSD = testData.nuUSD;
    NUUSD_ADDRESS = testData.NUUSD_ADDRESS;
    NUBTC_ADDRESS = testData.NUBTC_ADDRESS;
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
    VaultManager = testData.VM;

    // code that could be put in beforeEach but as we snapshot and restore, we
    // can put it here
    intervalShort = configArbi.INTERVAL_SHORT;
    intervalLong = configArbi.INTERVAL_LONG;
    amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    tokenIn = numa_address;
    tokenOut = configArbi.WETH_ADDRESS;
    fee = Number(configArbi.FEE);
    sqrtPriceLimitX96 = "0x0";

    // chainlink price ETHUSD
    let chainlinkInstance = await hre.ethers.getContractAt(artifacts.AggregatorV3, configArbi.PRICEFEEDETHUSD);
    let latestRoundData = await chainlinkInstance.latestRoundData();
    let latestRoundPrice = Number(latestRoundData.answer);
    decimals = Number(await chainlinkInstance.decimals());
    price = latestRoundPrice;// / 10 ** decimals;

    console.log('ETHUSD price ',price);

    // get some weth
    await wethContract.connect(signer).deposit({
      value: ethers.parseEther('10'),
    });

    // approve router
    await numa.connect(signer).approve(routerAddress, amountInMaximum);
    await wethContract.connect(signer).approve(routerAddress, amountInMaximum);



    snapshot = await takeSnapshot();

  });

  it('Should have right initialization parameters', async function () {
    expect(await oracle.intervalShort()).to.equal(configArbi.INTERVAL_SHORT);
    expect(await oracle.intervalLong()).to.equal(configArbi.INTERVAL_LONG);    
  });

  describe('#getV3SqrtLowestPrice', () => {
    it('should give Spot Price when Lowest', async () => {

      let deadline, amountOut;

      // recipient = sender
      
      let offset = 3600 * 10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
      deadline += 1800; // Time advanced 30min in migration to allow for the long interval

      // amount of ETH we want to get 
      amountOut = BigInt(5e17).toString(); //0.5 ETH 
      
      let ethBalance;
      let wethBalance;
      let numaBalance;

      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      numaBalance = await numa.balanceOf(sender);

       console.log('---------------------------- BEFORE');
       console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
       console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
       console.log('numaBalance', hre.ethers.formatUnits(numaBalance, 18));


      // 
      // SWAP
      let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);

      let ETHPool = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUMA_ETH_POOL_ADDRESS);

      await time.increase(180);

      // swap again the other way to get spot higher than short
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);



      let slot0ETH = await ETHPool.slot0();
      let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96;

      let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg(NUMA_ETH_POOL_ADDRESS, intervalShort);
      let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg(NUMA_ETH_POOL_ADDRESS, intervalLong);
      let getV3SqrtPrice = await oracle.getV3SqrtLowestPrice(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let shortLeqLong, spotLeqShort
      const token0 = await ETHPool.token0();



      // Eth price for debug
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString()) * BigInt(getV3SqrtPriceShort.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString()) * BigInt(getV3SqrtPriceLong.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString()) * BigInt(sqrtPriceX96Spot.toString()) * BigInt(1e18) / BigInt(2 ** 192);

      if (numa_address > configArbi.WETH_ADDRESS) {
        // change numerator/denominator
        uniPriceShort = Math.pow(10, 36) / Number(uniPriceShort);
        uniPriceLong = Math.pow(10, 36) / Number(uniPriceLong);
        uniPriceSpot = Math.pow(10, 36) / Number(uniPriceSpot);
      }
      else {
        // do nothing
      }




      console.log(uniPriceLong);
      console.log(uniPriceShort);
      console.log(uniPriceSpot);

      if (token0 === configArbi.WETH_ADDRESS) {
        shortLeqLong = (getV3SqrtPriceShort >= getV3SqrtPriceLong);
        spotLeqShort = (sqrtPriceX96Spot >= getV3SqrtPriceShort);
      }
      else {
        shortLeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong);
        spotLeqShort = (sqrtPriceX96Spot <= getV3SqrtPriceShort);
      }

      // Tests
      expect(shortLeqLong).to.equal(true);
      expect(spotLeqShort).to.equal(true);
      expect(getV3SqrtPrice).to.equal(sqrtPriceX96Spot);


    })
    it('should give Short Interval Price when Lowest', async () => {

      let deadline, amountOut;

      // recipient = sender
      let offset = 3600 * 10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
      deadline += 1800; // Time advanced 30min in migration to allow for the long interval


      // amount of ETH we want to get 
      amountOut = BigInt(5e17).toString(); 
    
      let ethBalance;
      let wethBalance;
      let numabalance;



      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      numabalance = await numa.balanceOf(sender);

      console.log('---------------------------- BEFORE');
      console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      console.log('numabalance', hre.ethers.formatUnits(numabalance, 18));

      // 
      // SWAP
      let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);

      let ETHPool = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUMA_ETH_POOL_ADDRESS);

      await time.increase(180);

      // swap again
      amountOut = BigInt(500e18).toString();// 500 numa
      paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);

      let slot0ETH = await ETHPool.slot0();
      let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96;

      let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg(NUMA_ETH_POOL_ADDRESS, intervalShort);
      let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg(NUMA_ETH_POOL_ADDRESS, intervalLong);
      let getV3SqrtPrice = await oracle.getV3SqrtLowestPrice(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let shortLeqLong, spotLeqShort
      const token0 = await ETHPool.token0();



      // Eth price for debug
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString()) * BigInt(getV3SqrtPriceShort.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString()) * BigInt(getV3SqrtPriceLong.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString()) * BigInt(sqrtPriceX96Spot.toString()) * BigInt(1e18) / BigInt(2 ** 192);

      if (numa_address > configArbi.WETH_ADDRESS) {
        // change numerator/denominator
        uniPriceShort = Math.pow(10, 36) / Number(uniPriceShort);
        uniPriceLong = Math.pow(10, 36) / Number(uniPriceLong);
        uniPriceSpot = Math.pow(10, 36) / Number(uniPriceSpot);
      }
      else {
        // do nothing
      }


      console.log(uniPriceLong);
      console.log(uniPriceShort);
      console.log(uniPriceSpot);

      if (token0 === configArbi.WETH_ADDRESS) {
        shortLeqLong = (getV3SqrtPriceShort >= getV3SqrtPriceLong);
        spotLeqShort = (sqrtPriceX96Spot >= getV3SqrtPriceShort);
      }
      else {
        shortLeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong);
        spotLeqShort = (sqrtPriceX96Spot <= getV3SqrtPriceShort);
      }

      // Tests
      expect(shortLeqLong).to.equal(true);
      expect(spotLeqShort).to.equal(false);
      expect(getV3SqrtPrice).to.equal(getV3SqrtPriceShort);


    })
    it('should give Long Interval Price when Lowest', async () => {

      let deadline, amountOut;

      // recipient = sender
      let offset = 3600 * 10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
      deadline += 1800; // Time advanced 30min in migration to allow for the long interval


      // amount of ETH we want to get 
      amountOut = BigInt(5e17).toString(); //0.5 ETH 
     
      let ethBalance;
      let wethBalance;
      let numabalance;

      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      numabalance = await numa.balanceOf(sender);

      console.log('---------------------------- BEFORE');
      console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      console.log('numabalance', hre.ethers.formatUnits(numabalance, 18));


      // 
      // SWAP
      let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);

      let ETHPool = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUMA_ETH_POOL_ADDRESS);

      await time.increase(1800);

      // swap again
      amountOut = BigInt(1000e18).toString();// 1000 numa
      paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);
      await time.increase(180);
      // and swap again but less than first time
      amountOut = BigInt(1e17).toString();// 0.1 eth
      paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);
      let slot0ETH = await ETHPool.slot0();
      let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96;

      let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg(NUMA_ETH_POOL_ADDRESS, intervalShort);
      let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg(NUMA_ETH_POOL_ADDRESS, intervalLong);
      let getV3SqrtPrice = await oracle.getV3SqrtLowestPrice(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let shortLeqLong, spotLeqShort
      const token0 = await ETHPool.token0();


      // Eth price for debug
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString()) * BigInt(getV3SqrtPriceShort.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString()) * BigInt(getV3SqrtPriceLong.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString()) * BigInt(sqrtPriceX96Spot.toString()) * BigInt(1e18) / BigInt(2 ** 192);

      if (numa_address > configArbi.WETH_ADDRESS) {
        // change numerator/denominator
        uniPriceShort = Math.pow(10, 36) / Number(uniPriceShort);
        uniPriceLong = Math.pow(10, 36) / Number(uniPriceLong);
        uniPriceSpot = Math.pow(10, 36) / Number(uniPriceSpot);
      }
      else {
        // do nothing
      }



      console.log(uniPriceLong);
      console.log(uniPriceShort);
      console.log(uniPriceSpot);

      if (token0 === configArbi.WETH_ADDRESS) {
        shortLeqLong = (getV3SqrtPriceShort >= getV3SqrtPriceLong);
        spotLeqLong = (sqrtPriceX96Spot >= getV3SqrtPriceLong);
      }
      else {
        shortLeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong);
        spotLeqLong = (sqrtPriceX96Spot <= getV3SqrtPriceLong);
      }

      // Tests
      expect(shortLeqLong).to.equal(false);
      expect(spotLeqLong).to.equal(false);
      expect(getV3SqrtPrice).to.equal(getV3SqrtPriceLong);

    })
  })

  describe('#getV3SqrtHighestPrice', () => {
    it('should give Spot Price when Highest', async () => {

      let deadline, amountOut;

      // recipient = sender
      let offset = 3600 * 10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
      deadline += 1800; // Time advanced 30min in migration to allow for the long interval


      // amount of ETH we want to get 
      amountOut = BigInt(5e17).toString(); //0.5 ETH 

      let ethBalance;
      let wethBalance;
      let numabalance;


      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      numabalance = await numa.balanceOf(sender);

      console.log('---------------------------- BEFORE');
      console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      console.log('numabalance', hre.ethers.formatUnits(numabalance, 18));


      // 
      // SWAP

      amountOut = BigInt(500e18).toString();// 500 numa
      let paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);
      let ETHPool = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUMA_ETH_POOL_ADDRESS);

      let slot0ETH = await ETHPool.slot0();
      let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96;

      let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg(NUMA_ETH_POOL_ADDRESS, intervalShort);
      let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg(NUMA_ETH_POOL_ADDRESS, intervalLong);
      let getV3SqrtPrice = await oracle.getV3SqrtHighestPrice(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong);


      let shortLeqLong, spotLeqShort
      const token0 = await ETHPool.token0();



      // Eth price for debug
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString()) * BigInt(getV3SqrtPriceShort.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString()) * BigInt(getV3SqrtPriceLong.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString()) * BigInt(sqrtPriceX96Spot.toString()) * BigInt(1e18) / BigInt(2 ** 192);

      if (numa_address > configArbi.WETH_ADDRESS) {
        // change numerator/denominator
        uniPriceShort = Math.pow(10, 36) / Number(uniPriceShort);
        uniPriceLong = Math.pow(10, 36) / Number(uniPriceLong);
        uniPriceSpot = Math.pow(10, 36) / Number(uniPriceSpot);
      }
      else {
        // do nothing
      }




      console.log(uniPriceLong);
      console.log(uniPriceShort);
      console.log(uniPriceSpot);

      if (token0 === configArbi.WETH_ADDRESS) {
        shortGeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong);
        spotGeqShort = (sqrtPriceX96Spot <= getV3SqrtPriceShort);
      }
      else {
        shortGeqLong = (getV3SqrtPriceShort >= getV3SqrtPriceLong);
        spotGeqShort = (sqrtPriceX96Spot >= getV3SqrtPriceShort);
      }

      // Tests
      expect(shortGeqLong).to.equal(true);
      expect(spotGeqShort).to.equal(true);
      expect(getV3SqrtPrice).to.equal(sqrtPriceX96Spot);

    })

    it('should give Short Interval Price when Highest', async () => {

      let deadline, amountOut;

      // recipient = sender
      let offset = 3600 * 10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
      deadline += 1800; // Time advanced 30min in migration to allow for the long interval

      // amount of ETH we want to get 
      amountOut = BigInt(5e17).toString(); //0.5 ETH 
     
      let ethBalance;
      let wethBalance;
      let numabalance;

      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      numabalance = await nuUSD.balanceOf(sender);

       console.log('---------------------------- BEFORE');
       console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
       console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
       console.log('numabalance', hre.ethers.formatUnits(numabalance, 18));

      // 
      // SWAP
      let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);

      let ETHPool = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUMA_ETH_POOL_ADDRESS);

      await time.increase(1800);

      // swap again
      amountOut = BigInt(500e18).toString();// 500 numa
      paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);
      await time.increase(180);
      // and swap again but less than first time
      amountOut = BigInt(1e17).toString();// 500 numa
      paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);
      let slot0ETH = await ETHPool.slot0();
      let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96;

      let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg(NUMA_ETH_POOL_ADDRESS, intervalShort);
      let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg(NUMA_ETH_POOL_ADDRESS, intervalLong);
      let getV3SqrtPrice = await oracle.getV3SqrtHighestPrice(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let shortGeqLong, spotGeqShort
      const token0 = await ETHPool.token0();



      // Eth price for debug
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString()) * BigInt(getV3SqrtPriceShort.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString()) * BigInt(getV3SqrtPriceLong.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString()) * BigInt(sqrtPriceX96Spot.toString()) * BigInt(1e18) / BigInt(2 ** 192);

      if (numa_address > configArbi.WETH_ADDRESS) {
        // change numerator/denominator
        uniPriceShort = Math.pow(10, 36) / Number(uniPriceShort);
        uniPriceLong = Math.pow(10, 36) / Number(uniPriceLong);
        uniPriceSpot = Math.pow(10, 36) / Number(uniPriceSpot);
      }
      else {
        // do nothing
      }




      console.log(uniPriceLong);
      console.log(uniPriceShort);
      console.log(uniPriceSpot);

      if (token0 === configArbi.WETH_ADDRESS) {
        shortGeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong)
        spotGeqShort = (sqrtPriceX96Spot <= getV3SqrtPriceShort)
      }
      else {
        shortGeqLong = (getV3SqrtPriceShort >= getV3SqrtPriceLong)
        spotGeqShort = (sqrtPriceX96Spot >= getV3SqrtPriceShort)
      }

      // Tests
      expect(shortGeqLong).to.equal(true);
      expect(spotGeqShort).to.equal(false);
      expect(getV3SqrtPrice).to.equal(getV3SqrtPriceShort);


    })
    it('should give Long Interval Price when Highest', async () => {

      let deadline, amountOut;

      // recipient = sender
      let offset = 3600 * 10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
      deadline += 1800; // Time advanced 30min in migration to allow for the long interval


      // amount of ETH we want to get 
      amountOut = BigInt(500e18).toString(); //500 numa
    
      let ethBalance;
      let wethBalance;
      let numabalance;


      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      numabalance = await numa.balanceOf(sender);

       console.log('---------------------------- BEFORE');
       console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
       console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
       console.log('numabalance', hre.ethers.formatUnits(numabalance, 18));

      // 
      // SWAP
      let paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);

      let ETHPool = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUMA_ETH_POOL_ADDRESS);

      await time.increase(1800);

      // swap again the other way
      amountOut = BigInt(1e17).toString();// 0.1 ETH
      paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);
      await time.increase(180);
      // and swap again
      amountOut = BigInt(100e18).toString();// 100 dollars
      paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);
      let slot0ETH = await ETHPool.slot0();
      let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96;

      let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg(NUMA_ETH_POOL_ADDRESS, intervalShort);
      let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg(NUMA_ETH_POOL_ADDRESS, intervalLong);
      let getV3SqrtPrice = await oracle.getV3SqrtHighestPrice(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let shortGeqLong, spotGeqShort
      const token0 = await ETHPool.token0();



      // Eth price for debug
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString()) * BigInt(getV3SqrtPriceShort.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString()) * BigInt(getV3SqrtPriceLong.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString()) * BigInt(sqrtPriceX96Spot.toString()) * BigInt(1e18) / BigInt(2 ** 192);

      if (numa_address > configArbi.WETH_ADDRESS) {
        // change numerator/denominator
        uniPriceShort = Math.pow(10, 36) / Number(uniPriceShort);
        uniPriceLong = Math.pow(10, 36) / Number(uniPriceLong);
        uniPriceSpot = Math.pow(10, 36) / Number(uniPriceSpot);
      }
      else {
        // do nothing
      }




      console.log(uniPriceLong);
      console.log(uniPriceShort);
      console.log(uniPriceSpot);

      if (token0 === configArbi.WETH_ADDRESS) {
        shortGeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong)
        spotGeqLong = (sqrtPriceX96Spot <= getV3SqrtPriceLong)
      }
      else {
        shortGeqLong = (getV3SqrtPriceShort >= getV3SqrtPriceLong)
        spotGeqLong = (sqrtPriceX96Spot >= getV3SqrtPriceLong)
      }

      // Tests
      expect(shortGeqLong).to.equal(false);
      expect(spotGeqLong).to.equal(false);
      expect(getV3SqrtPrice).to.equal(getV3SqrtPriceLong);


    })
  })

  describe('#getNbOfNuAsset', () => {
    it('should use lowest price from pool', async () => {
      // 3 different price spot/low/high
      let deadline, amountOut;

      // recipient = sender
      let offset = 3600 * 10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
      deadline += 1800; // Time advanced 30min in migration to allow for the long interval

      // amount of ETH we want to get 
      amountOut = BigInt(5e17).toString(); //0.5 ETH 
     
      // 
      // SWAP
      let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);

      await time.increase(1800);

      // swap again
      amountOut = BigInt(1000e18).toString();// 1000 numa
      paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);
      await time.increase(180);
      // and swap again but less than first time
      amountOut = BigInt(1e17).toString();// 0.1 eth
      paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer).exactOutputSingle(paramsCall);
      
      // compute lowest price

      // numa price
      let getV3SqrtPrice = await oracle.getV3SqrtLowestPrice(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let uniPrice = BigInt(getV3SqrtPrice.toString()) * BigInt(getV3SqrtPrice.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      
      if (numa_address > configArbi.WETH_ADDRESS) {
        // change numerator/denominator
        uniPrice = BigInt(Math.pow(10, 36)) / (uniPrice);
       
      }
      else {
        // do nothing
        //uniPrice = Number(uniPrice);
      }

      console.log(uniPrice);
      console.log(price);
      let numaPriceUsd = uniPrice * BigInt(price);
      console.log(numaPriceUsd);

      let inputAmount = BigInt(100);
      let amountEstimate = (inputAmount*numaPriceUsd)/BigInt(10**decimals);
      // price from oracle
      let amountFromOracle = await oracle.getNbOfNuAsset(
        ethers.parseEther(inputAmount.toString()),
        NUUSD_ADDRESS,
        NUMA_ETH_POOL_ADDRESS
      );
      console.log(amountFromOracle);
      console.log(amountEstimate);
      // not exact because solidity code is more precise (input amount factorized before division)
      expect(amountFromOracle).to.be.closeTo(amountEstimate, epsilon);




    })
    it('should be clipped by vault price', async () => {

      let inputAmount = BigInt(100);
      // numa price
      let getV3SqrtPrice = await oracle.getV3SqrtLowestPrice(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let uniPrice = BigInt(getV3SqrtPrice.toString()) * BigInt(getV3SqrtPrice.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      
      if (numa_address > configArbi.WETH_ADDRESS) {
        // change numerator/denominator
        uniPrice = BigInt(Math.pow(10, 36)) / (uniPrice);
       
      }
      else {
        // do nothing
        //uniPrice = Number(uniPrice);
      }
     
      console.log(uniPrice);
      let numaPriceUsd = uniPrice * BigInt(price);
      //console.log(numaPriceUsd);

      
      let amountEstimate = (inputAmount*numaPriceUsd)/BigInt(10**decimals);
      //console.log(amountEstimate);
      // 1. vault price same as pool price
      await oracle.setNumaPrice(await VaultManager.getAddress());
      
      //let amountEstimate = (inputAmount*numaPriceUsd)/BigInt(10**decimals);
      // price from oracle
      let amountFromOracle = await oracle.getNbOfNuAsset(
        ethers.parseEther(inputAmount.toString()),
        NUUSD_ADDRESS,
        NUMA_ETH_POOL_ADDRESS
      );
      //console.log(amountFromOracle);
      let vaultPrice = await VaultManager.GetNumaPriceEth(ethers.parseEther(inputAmount.toString()));
      console.log(vaultPrice);

      // 2. validate
      expect(amountFromOracle).to.be.closeTo(amountEstimate, epsilon);
      // 3. make vault price + tolerance lower than pool price 
      // double numa supply
      await numa.mint(
        signer.getAddress(),
        ethers.parseEther("10000000.0")
      );
      vaultPrice = await VaultManager.GetNumaPriceEth(ethers.parseEther(inputAmount.toString()));
      console.log(vaultPrice);

      // 4. validate that we clipped by vault price
      amountFromOracle = await oracle.getNbOfNuAsset(
        ethers.parseEther(inputAmount.toString()),
        NUUSD_ADDRESS,
        NUMA_ETH_POOL_ADDRESS
      );

      numaPriceUsd = (vaultPrice *BigInt(105)* BigInt(price))/BigInt(100);
      //console.log(numaPriceUsd);

      
      amountEstimate = (numaPriceUsd)/BigInt(10**decimals);

      expect(amountFromOracle).to.be.closeTo(amountEstimate, epsilon);
      
    })

  })

  describe('#getNbOfNumaNeeded', () => {
    it('should use lowest price from pool', async () => {
       // 3 different price spot/low/high
       let deadline, amountOut;

       // recipient = sender
       let offset = 3600 * 10000000;// TODO 
       deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
       deadline += 1800; // Time advanced 30min in migration to allow for the long interval
 
       // amount of ETH we want to get 
       amountOut = BigInt(5e17).toString(); //0.5 ETH 
      
       // 
       // SWAP
       let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
       await swapRouter.connect(signer).exactOutputSingle(paramsCall);
 
       await time.increase(1800);
 
       // swap again
       amountOut = BigInt(1000e18).toString();// 1000 numa
       paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
       await swapRouter.connect(signer).exactOutputSingle(paramsCall);
       await time.increase(180);
       // and swap again but less than first time
       amountOut = BigInt(1e17).toString();// 0.1 eth
       paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
       await swapRouter.connect(signer).exactOutputSingle(paramsCall);
       
       // compute lowest price
 
       // numa price
       let getV3SqrtPrice = await oracle.getV3SqrtLowestPrice(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong);
       let uniPrice = BigInt(getV3SqrtPrice.toString()) * BigInt(getV3SqrtPrice.toString()) * BigInt(1e18) / BigInt(2 ** 192);
       
       if (numa_address > configArbi.WETH_ADDRESS) {
         // change numerator/denominator
         uniPrice = BigInt(Math.pow(10, 36)) / (uniPrice);
        
       }
       else {
         // do nothing
         //uniPrice = Number(uniPrice);
       }
 
      //  console.log(uniPrice);
      //  console.log(price);
       let numaPriceUsd = uniPrice * BigInt(price);
       console.log(Number(numaPriceUsd)/10**decimals);


       // we want 100 nuUSD
       let outputAmount = BigInt(100);
       outputAmount = ethers.parseEther(outputAmount.toString());

       let amountEstimate = (outputAmount*BigInt(10**decimals)*ethers.parseEther("1"))/numaPriceUsd;


       // price from oracle
       let amountFromOracle = await oracle.getNbOfNumaNeeded(
        outputAmount,
         NUUSD_ADDRESS,
         NUMA_ETH_POOL_ADDRESS
       );
       console.log(amountFromOracle);
       console.log(amountEstimate);
      //  console.log((outputAmount*BigInt(10**decimals)));
      //  console.log(numaPriceUsd);
       // not exact because solidity code is more precise (input amount factorized before division)
       expect(amountFromOracle).to.be.closeTo(amountEstimate, epsilon);

     
    })

    it('should be clipped by vault price', async () => {
      let outputAmount = BigInt(100);
      // numa price
      let getV3SqrtPrice = await oracle.getV3SqrtLowestPrice(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let uniPrice = BigInt(getV3SqrtPrice.toString()) * BigInt(getV3SqrtPrice.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      
      if (numa_address > configArbi.WETH_ADDRESS) {
        // change numerator/denominator
        uniPrice = BigInt(Math.pow(10, 36)) / (uniPrice);
       
      }
      else {
        // do nothing
        //uniPrice = Number(uniPrice);
      }
     
      console.log(uniPrice);
      let numaPriceUsd = uniPrice * BigInt(price);
      //console.log(numaPriceUsd);
      outputAmount = ethers.parseEther(outputAmount.toString());

      let amountEstimate = (outputAmount*BigInt(10**decimals)*ethers.parseEther("1"))/numaPriceUsd;

      
    
      //console.log(amountEstimate);
      // 1. vault price same as pool price
      await oracle.setNumaPrice(await VaultManager.getAddress());
      
      //let amountEstimate = (inputAmount*numaPriceUsd)/BigInt(10**decimals);
      // price from oracle
      let amountFromOracle = await oracle.getNbOfNumaNeeded(
        outputAmount,
        NUUSD_ADDRESS,
        NUMA_ETH_POOL_ADDRESS
      );
      console.log(amountFromOracle);
      console.log(amountEstimate);
      // not exact because solidity code is more precise (input amount factorized before division)
      expect(amountFromOracle).to.be.closeTo(amountEstimate, epsilon);


      // 3. make vault price + tolerance lower than pool price 
      // double numa supply
      await numa.mint(
        signer.getAddress(),
        ethers.parseEther("10000000.0")
      );

      // 4. validate that we clipped by vault price
      amountFromOracle = await oracle.getNbOfNumaNeeded(
        outputAmount,
        NUUSD_ADDRESS,
        NUMA_ETH_POOL_ADDRESS
      );
      console.log(amountFromOracle);
      console.log(amountEstimate);
   
   
      let numaPerEth = await VaultManager.GetNumaPerEth(outputAmount);
     

      let numaPerUsd = (numaPerEth * BigInt(100) *BigInt(10**decimals))/(BigInt(price)*BigInt(105));
      console.log(numaPerEth);
      console.log(numaPerUsd);
      amountEstimate = (numaPerUsd);
      console.log(amountFromOracle);
      console.log(amountEstimate);
      // not exact because solidity code is more precise (input amount factorized before division)
      expect(amountFromOracle).to.be.closeTo(amountEstimate, epsilon);
    })
  })

  describe('#getNbOfNumaFromAsset', () => {
    it('should use highest price from pool', async () => {
        // 3 different price spot/low/high
        let deadline, amountOut;

        // recipient = sender
        let offset = 3600 * 10000000;// TODO 
        deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
        deadline += 1800; // Time advanced 30min in migration to allow for the long interval
  
        // amount of ETH we want to get 
        amountOut = BigInt(5e17).toString(); //0.5 ETH 
       
        // 
        // SWAP
        let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
        await swapRouter.connect(signer).exactOutputSingle(paramsCall);
  
        await time.increase(1800);
  
        // swap again
        amountOut = BigInt(1000e18).toString();// 1000 numa
        paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
        await swapRouter.connect(signer).exactOutputSingle(paramsCall);
        await time.increase(180);
        // and swap again but less than first time
        amountOut = BigInt(1e17).toString();// 0.1 eth
        paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
        await swapRouter.connect(signer).exactOutputSingle(paramsCall);
        
        // compute lowest price
  
        // numa price
        let getV3SqrtPrice = await oracle.getV3SqrtHighestPrice(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong);
        let uniPrice = BigInt(getV3SqrtPrice.toString()) * BigInt(getV3SqrtPrice.toString()) * BigInt(1e18) / BigInt(2 ** 192);
        
        if (numa_address > configArbi.WETH_ADDRESS) {
          // change numerator/denominator
          uniPrice = BigInt(Math.pow(10, 36)) / (uniPrice);
         
        }
        else {
          // do nothing
          //uniPrice = Number(uniPrice);
        }
  
        console.log(uniPrice);
        console.log(price);
        let numaPriceUsd = uniPrice * BigInt(price);
        console.log(numaPriceUsd);
  
        let inputAmount = BigInt(100);
       
        let amountEstimate = (ethers.parseEther(inputAmount.toString())*BigInt(10**decimals)*ethers.parseEther("1"))/numaPriceUsd;
        // price from oracle
        let amountFromOracle = await oracle.getNbOfNumaFromAsset(
          ethers.parseEther(inputAmount.toString()),
          NUUSD_ADDRESS,
          NUMA_ETH_POOL_ADDRESS
        );
        console.log(amountFromOracle);
        console.log(amountEstimate);
        // not exact because solidity code is more precise (input amount factorized before division)
        expect(amountFromOracle).to.be.closeTo(amountEstimate, epsilon);

    })

    it('should be clipped by vault price', async () => {
      let inputAmount = BigInt(100);
      // numa price
      let getV3SqrtPrice = await oracle.getV3SqrtHighestPrice(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let uniPrice = BigInt(getV3SqrtPrice.toString()) * BigInt(getV3SqrtPrice.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      
      if (numa_address > configArbi.WETH_ADDRESS) {
        // change numerator/denominator
        uniPrice = BigInt(Math.pow(10, 36)) / (uniPrice);
       
      }
      else {
        // do nothing
        //uniPrice = Number(uniPrice);
      }
     
      console.log(uniPrice);
      let numaPriceUsd = uniPrice * BigInt(price);
      //console.log(numaPriceUsd);


      let amountEstimate = (ethers.parseEther(inputAmount.toString())*ethers.parseEther("1")*BigInt(10**decimals))/numaPriceUsd;

      
    
      //console.log(amountEstimate);
      // 1. vault price same as pool price
      await oracle.setNumaPrice(await VaultManager.getAddress());
      
      //let amountEstimate = (inputAmount*numaPriceUsd)/BigInt(10**decimals);
      // price from oracle
      let amountFromOracle = await oracle.getNbOfNumaFromAsset(
        ethers.parseEther(inputAmount.toString()),
        NUUSD_ADDRESS,
        NUMA_ETH_POOL_ADDRESS
      );
      console.log(amountFromOracle);
      console.log(amountEstimate);
      // not exact because solidity code is more precise (input amount factorized before division)
      expect(amountFromOracle).to.be.closeTo(amountEstimate, epsilon);


      // 3. make vault price + tolerance higher than pool price 
      await numa.burn(        
        ethers.parseEther("5000000.0")
      );

      // 4. validate that we clipped by vault price
      amountFromOracle = await oracle.getNbOfNumaFromAsset(
        ethers.parseEther(inputAmount.toString()),
        NUUSD_ADDRESS,
        NUMA_ETH_POOL_ADDRESS
      );
      console.log(amountFromOracle);
      console.log(amountEstimate);
   
   
      let numaPerEth = await VaultManager.GetNumaPerEth(ethers.parseEther(inputAmount.toString()));
     
      amountEstimate = (BigInt(100)*numaPerEth*BigInt(10**decimals))/(BigInt(price)*BigInt(95));

      

      // let numaPerUsd = (numaPerEth * BigInt(95) *BigInt(10**decimals))/(BigInt(price)*BigInt(100));
      // console.log(numaPerEth);
      // console.log(numaPerUsd);
      // amountEstimate = (numaPerUsd);
      console.log(amountFromOracle);
      console.log(amountEstimate);
      // not exact because solidity code is more precise (input amount factorized before division)
      expect(amountFromOracle).to.be.closeTo(amountEstimate, epsilon);
    })

  })

  describe('#getNbOfAssetneeded', () => {
    it('should use highest price from pool', async function () {

       // 3 different price spot/low/high
       let deadline, amountOut;

       // recipient = sender
       let offset = 3600 * 10000000;// TODO 
       deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
       deadline += 1800; // Time advanced 30min in migration to allow for the long interval
 
       // amount of ETH we want to get 
       amountOut = BigInt(5e17).toString(); //0.5 ETH 
      
       // 
       // SWAP
       let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
       await swapRouter.connect(signer).exactOutputSingle(paramsCall);
 
       await time.increase(1800);
 
       // swap again
       amountOut = BigInt(1000e18).toString();// 1000 numa
       paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
       await swapRouter.connect(signer).exactOutputSingle(paramsCall);
       await time.increase(180);
       // and swap again but less than first time
       amountOut = BigInt(1e17).toString();// 0.1 eth
       paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
       await swapRouter.connect(signer).exactOutputSingle(paramsCall);
       
       // compute lowest price
 
       // numa price
       let getV3SqrtPrice = await oracle.getV3SqrtHighestPrice(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong);
       let uniPrice = BigInt(getV3SqrtPrice.toString()) * BigInt(getV3SqrtPrice.toString()) * BigInt(1e18) / BigInt(2 ** 192);
       
       if (numa_address > configArbi.WETH_ADDRESS) {
         // change numerator/denominator
         uniPrice = BigInt(Math.pow(10, 36)) / (uniPrice);
        
       }
       else {
         // do nothing
         //uniPrice = Number(uniPrice);
       }
 
       console.log(uniPrice);
       console.log(price);
       let numaPriceUsd = uniPrice * BigInt(price);
       console.log(numaPriceUsd);
 
       let outputAmount = BigInt(100);
      
       let amountEstimate = (outputAmount*numaPriceUsd)/BigInt(10**decimals);
       // price from oracle
       let amountFromOracle = await oracle.getNbOfAssetneeded(
         ethers.parseEther(outputAmount.toString()),
         NUUSD_ADDRESS,
         NUMA_ETH_POOL_ADDRESS
       );
       console.log(amountFromOracle);
       console.log(amountEstimate);
       // not exact because solidity code is more precise (input amount factorized before division)
       expect(amountFromOracle).to.be.closeTo(amountEstimate, epsilon);

    })

    it('should be clipped by vault price', async function () {

      let outputAmount = BigInt(100);
      // numa price
      let getV3SqrtPrice = await oracle.getV3SqrtHighestPrice(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let uniPrice = BigInt(getV3SqrtPrice.toString()) * BigInt(getV3SqrtPrice.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      
      if (numa_address > configArbi.WETH_ADDRESS) {
        // change numerator/denominator
        uniPrice = BigInt(Math.pow(10, 36)) / (uniPrice);
       
      }
      else {
        // do nothing
        //uniPrice = Number(uniPrice);
      }
     
      console.log(uniPrice);
      let numaPriceUsd = uniPrice * BigInt(price);
      //console.log(numaPriceUsd);

      let amountEstimate = (outputAmount*numaPriceUsd)/BigInt(10**decimals);
     
    
      //console.log(amountEstimate);
      // 1. vault price same as pool price
      await oracle.setNumaPrice(await VaultManager.getAddress());
      
      //let amountEstimate = (inputAmount*numaPriceUsd)/BigInt(10**decimals);
      // price from oracle

      let amountFromOracle = await oracle.getNbOfAssetneeded(  
        ethers.parseEther(outputAmount.toString()),
        NUUSD_ADDRESS,
        NUMA_ETH_POOL_ADDRESS
      );
      console.log(amountFromOracle);
      console.log(amountEstimate);
      // not exact because solidity code is more precise (input amount factorized before division)
      expect(amountFromOracle).to.be.closeTo(amountEstimate, epsilon);


      // 3. make vault price + tolerance higher than pool price 
      await numa.burn(        
        ethers.parseEther("5000000.0")
      );

      // 4. validate that we clipped by vault price
      amountFromOracle = await oracle.getNbOfAssetneeded(
        ethers.parseEther(outputAmount.toString()),
        NUUSD_ADDRESS,
        NUMA_ETH_POOL_ADDRESS
      );
      console.log(amountFromOracle);
      console.log(amountEstimate);
   
   
      let numaPrice = await VaultManager.GetNumaPriceEth(ethers.parseEther(outputAmount.toString()));
     
      amountEstimate = (BigInt(95)*numaPrice*BigInt(price))/(BigInt(10**decimals)*BigInt(100));

      

      // let numaPerUsd = (numaPerEth * BigInt(95) *BigInt(10**decimals))/(BigInt(price)*BigInt(100));
      // console.log(numaPerEth);
      // console.log(numaPerUsd);
      // amountEstimate = (numaPerUsd);
      console.log(amountFromOracle);
      console.log(amountEstimate);
      // not exact because solidity code is more precise (input amount factorized before division)
      expect(amountFromOracle).to.be.closeTo(amountEstimate, epsilon);
  

    })
  })

  describe('#getNbOfNuAssetFromNuAsset', () => {
    it('should convert nuasset to nuasset', async () => 
    {
      let chainlinkInstanceBTC = await hre.ethers.getContractAt(artifacts.AggregatorV3, configArbi.PRICEFEEDBTCETH);
      let latestRoundDataBTC = await chainlinkInstanceBTC.latestRoundData();
      let latestRoundPriceBTC = (latestRoundDataBTC.answer);
      let decimalsBTC = Number(await chainlinkInstanceBTC.decimals());

      //let priceBTC = latestRoundPriceBTC/ 10 ** decimalsBTC;

      // nuUSD --> nuBTC
      let usdAmountIn = 67000;
      let btcAmountOut = await oracle.getNbOfNuAssetFromNuAsset(ethers.parseEther(usdAmountIn.toString()),NUUSD_ADDRESS,NUBTC_ADDRESS);
      let btcAmountOutEstimate = (ethers.parseEther(usdAmountIn.toString())* BigInt(10**decimals)*BigInt(10**decimalsBTC))/(latestRoundPriceBTC * BigInt(price));
      //btcAmountOutEstimate = BigInt(btcAmountOutEstimate);
      console.log(btcAmountOutEstimate);
      console.log(btcAmountOut);

      expect(btcAmountOut).to.be.closeTo(btcAmountOutEstimate, epsilon);

    })
  })




 
  // describe('#set parameters', () => {
  //   it('Should be able to set parameters', async function () {
  //     let intervalShortNew = 360;
  //     let intervalLongNew = 3600;
    
  //     await expect(oracle.setIntervalShort(intervalShortNew)).to.emit(oracle, "IntervalShort").withArgs(intervalShortNew);
  //     await expect(oracle.setIntervalLong(intervalLongNew)).to.emit(oracle, "IntervalLong").withArgs(intervalLongNew);
  //     // check values
  //     expect(await oracle.intervalShort()).to.equal(intervalShortNew);
  //     expect(await oracle.intervalLong()).to.equal(intervalLongNew);
     

  //   });
  // })

  // describe('#ownable', () => {
  //   it('Should implement Ownable', async function () {
  //     let intervalShortNew = 360;
  //     let intervalLongNew = 3600;

  //     expect(await oracle.owner()).to.equal(await signer.getAddress());
  //     //
  //     await expect(oracle.connect(signer2).setIntervalShort(intervalShortNew)).to.be.revertedWithCustomError(oracle, "OwnableUnauthorizedAccount",)
  //       .withArgs(await signer2.getAddress());
  //     await expect(oracle.connect(signer2).setIntervalLong(intervalLongNew)).to.be.revertedWithCustomError(oracle, "OwnableUnauthorizedAccount",)
  //       .withArgs(await signer2.getAddress());

  //     //
  //     await oracle.connect(signer).transferOwnership(await signer2.getAddress());
  //     await expect(oracle.connect(signer2).setIntervalShort(intervalShortNew)).to.not.be.reverted;
  //   });

  //});





});

