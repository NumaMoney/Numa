const { getPoolData, getPool, initPoolETH, addLiquidity, weth9, artifacts, swapOptions, buildTrade, SwapRouter, Token } = require("../../scripts/Utils.js");
const { deployNumaNumaPoolnuAssetsPrinters, configArbi } = require("../fixtures/NumaTestFixture.js");
const { time, loadFixture, takeSnapshot } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { upgrades } = require("hardhat");


// ********************* Numa oracle test using arbitrum fork for chainlink *************************


describe('NUMA ORACLE', function () {
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

  afterEach(async function () {
    //console.log("reseting snapshot");
    await snapshot.restore();
    snapshot = await takeSnapshot();
  })

  beforeEach(async function () {
    //console.log("calling before each");
  })


  before(async function () {
    testData = await loadFixture(deployNumaNumaPoolnuAssetsPrinters);

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
    intervalShort = configArbi.INTERVAL_SHORT;
    intervalLong = configArbi.INTERVAL_LONG;
    amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    tokenIn = NUUSD_ADDRESS;
    tokenOut = configArbi.WETH_ADDRESS;
    fee = Number(configArbi.FEE);
    sqrtPriceLimitX96 = "0x0";

    // chainlink price ETHUSD
    let chainlinkInstance = await hre.ethers.getContractAt(artifacts.AggregatorV3, configArbi.PRICEFEEDETHUSD);
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



    snapshot = await takeSnapshot();

  });

  it('Should have right initialization parameters', async function () {
    expect(await oracle.intervalShort()).to.equal(configArbi.INTERVAL_SHORT);
    expect(await oracle.intervalLong()).to.equal(configArbi.INTERVAL_LONG);    
  });



  describe('#swap check nuUSD & tokenBelowThreshold', () => {
    it('should change after swapping nuUSD for 0.5 WETH', async () => {

      let deadline, amountOut;

      // recipient = sender
      let offset = 3600 * 10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
      deadline += 1800; // Time advanced 30min in migration to allow for the long interval

      // amount of ETH we want to get 
      amountOut = BigInt(5e17).toString(); // 0.5 ETH 
      input = await nuUSD.balanceOf(sender);




      //let tokenBelowThreshold = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, configArbi.PRICEFEEDETHUSD, configArbi.WETH_ADDRESS);
      let uniSqrtPriceLow = await oracle.getV3SqrtLowestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let uniSqrtPriceHigh = await oracle.getV3SqrtHighestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);

      // uint256 numerator = (IUniswapV3Pool(_pool).token1() == _weth9 ? sqrtPriceX96 : FixedPoint96.Q96);
      // uint256 denominator = (numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96);
      // //ETH per Token, times 1e18
      // uint256 ethPerToken = FullMath.mulDiv(FullMath.mulDiv(numerator, numerator, denominator), 1e18, denominator);

      let uniPriceLow = BigInt(uniSqrtPriceLow.toString()) * BigInt(uniSqrtPriceLow.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceHigh = BigInt(uniSqrtPriceHigh.toString()) * BigInt(uniSqrtPriceHigh.toString()) * BigInt(1e18) / BigInt(2 ** 192);


      // console.log(`Swap price low of pool before swap: ${hre.ethers.formatUnits(uniPriceLow,18)}`);
      // console.log(`Swap price high of pool before swap: ${hre.ethers.formatUnits(uniPriceHigh,18)}`);
      // console.log(`Token below threshold before swap: ${tokenBelowThreshold}`);


      if (NUUSD_ADDRESS > configArbi.WETH_ADDRESS) {
        // change numerator/denominator
        uniPriceLow = Math.pow(10, 36) / Number(uniPriceLow);
        uniPriceHigh = Math.pow(10, 36) / Number(uniPriceHigh);
      }
      else {
        // do nothing
      }


      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      nuusdcBalance = await nuUSD.balanceOf(sender);

      // console.log('---------------------------- BEFORE');
      // console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      // console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      // console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));

      // 
      let uniPriceBefore = uniPriceLow;
      let ratio = (Number(uniPriceBefore) / (1.0 / price));
      let priceBelowThresholdBefore = (ratio < threshold);


      expect(priceBelowThresholdBefore).to.equal(false);
      //expect(tokenBelowThreshold).to.equal(priceBelowThresholdBefore);



      // 
      // SWAP
      const paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);

      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      nuusdcBalance = await nuUSD.balanceOf(sender);

      // console.log('---------------------------- AFTER');
      // console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      // console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      // console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));



      //let tokenBelowThresholdAfter = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, configArbi.PRICEFEEDETHUSD, configArbi.WETH_ADDRESS);

      uniSqrtPriceLow = await oracle.getV3SqrtLowestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      uniSqrtPriceHigh = await oracle.getV3SqrtHighestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);

      uniPriceLow = BigInt(uniSqrtPriceLow.toString()) * BigInt(uniSqrtPriceLow.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      uniPriceHigh = BigInt(uniSqrtPriceHigh.toString()) * BigInt(uniSqrtPriceHigh.toString()) * BigInt(1e18) / BigInt(2 ** 192);


      // console.log(`Swap price low of pool before swap: ${hre.ethers.formatUnits(uniPriceLow,18)}`);
      // console.log(`Swap price high of pool before swap: ${hre.ethers.formatUnits(uniPriceHigh,18)}`);
      // console.log(`Token below threshold before swap: ${tokenBelowThreshold}`);


      if (NUUSD_ADDRESS > configArbi.WETH_ADDRESS) {
        // change numerator/denominator
        uniPriceLow = Math.pow(10, 36) / Number(uniPriceLow);
        uniPriceHigh = Math.pow(10, 36) / Number(uniPriceHigh);
      }
      else {
        // do nothing
      }

      // 
      let uniPriceAfter = uniPriceLow;
      ratio = (Number(uniPriceAfter) / (1.0 / price));
      let priceBelowThresholdAfter = (ratio < threshold);

      // Tests
      expect(priceBelowThresholdAfter).to.equal(true);
      //expect(tokenBelowThresholdAfter).to.equal(priceBelowThresholdAfter);

    })
  })



  describe('#getCostSimpleShift nuUSD', () => {
    it('should return getTokensForAmount when at or above threshold', async () => {


      let deadline, amountOut;

      // recipient = sender
      let offset = 3600 * 10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
      deadline += 1800; // Time advanced 30min in migration to allow for the long interval


      // amount of ETH we want to get 
      amountOut = BigInt(12e16).toString(); // 0.12 ETH 
      input = await nuUSD.balanceOf(sender);
      let ethBalance;
      let wethBalance;
      let nuusdcBalance;




      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      nuusdcBalance = await nuUSD.balanceOf(sender);

      // console.log('---------------------------- BEFORE');
      // console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      // console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      // console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));

      // 
      // SWAP
      const paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);


      //let tokenBelowThresholdAfter = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, configArbi.PRICEFEEDETHUSD, configArbi.WETH_ADDRESS);



      let amount = BigInt(1e18);
      let costSimpleShift = await oracle.getNbOfNumaFromAsset(amount, configArbi.PRICEFEEDETHUSD, NUMA_ETH_POOL_ADDRESS);
      costSimpleShift = costSimpleShift.toString()

      //let costRaw = (await oracle.getNbOfNumaFromAssetUsingPools(NUMA_ETH_POOL_ADDRESS, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, amount, configArbi.WETH_ADDRESS)).toString();

      let costAmount = (await oracle.getNbOfNumaFromAssetUsingOracle(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong, configArbi.PRICEFEEDETHUSD, amount, configArbi.WETH_ADDRESS)).toString();

      //belowThreshold = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, configArbi.PRICEFEEDETHUSD, configArbi.WETH_ADDRESS);
      //let costRawLeqCostAmount = (BigInt(costRaw) <= BigInt(costAmount));

      // Tests
      //expect(belowThreshold).to.equal(false);
      //expect(costRawLeqCostAmount).to.equal(true);
      expect(costSimpleShift).to.equal(costAmount);

    })

    it('should return getTokensRaw when below threshold', async () => {

      let deadline, amountOut;

      // recipient = sender
      let offset = 3600 * 10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
      deadline += 1800; // Time advanced 30min in migration to allow for the long interval


      // amount of ETH we want to get 
      amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
      input = await nuUSD.balanceOf(sender);
      let ethBalance;
      let wethBalance;
      let nuusdcBalance;


      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      nuusdcBalance = await nuUSD.balanceOf(sender);

      // console.log('---------------------------- BEFORE');
      // console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      // console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      // console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));

      // 
      // SWAP
      const paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);


      //let tokenBelowThresholdAfter = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, configArbi.PRICEFEEDETHUSD, configArbi.WETH_ADDRESS);


      let amount = BigInt(1e18);
      let costSimpleShift = await oracle.getNbOfNumaFromAsset(amount, configArbi.PRICEFEEDETHUSD, NUMA_ETH_POOL_ADDRESS);
      costSimpleShift = costSimpleShift.toString()

      //let costRaw = (await oracle.getNbOfNumaFromAssetUsingPools(NUMA_ETH_POOL_ADDRESS, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, amount, configArbi.WETH_ADDRESS)).toString();

      let costAmount = (await oracle.getNbOfNumaFromAssetUsingOracle(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong, configArbi.PRICEFEEDETHUSD, amount, configArbi.WETH_ADDRESS)).toString();

      // belowThreshold = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, configArbi.PRICEFEEDETHUSD, configArbi.WETH_ADDRESS);
      // let costRawLeqCostAmount = (BigInt(costRaw) <= BigInt(costAmount));

      // Tests
      //expect(belowThreshold).to.equal(true);
      //expect(costRawLeqCostAmount).to.equal(true);
      //expect(costSimpleShift).to.equal(costRaw);
      expect(costSimpleShift).to.equal(costAmount);
    });
  })

  describe('#getV3SqrtPrice', () => {
    it('should give Spot Price when Lowest', async () => {

      let deadline, amountOut;

      // recipient = sender
      let offset = 3600 * 10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
      deadline += 1800; // Time advanced 30min in migration to allow for the long interval

      // amount of ETH we want to get 
      amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
      input = await nuUSD.balanceOf(sender);
      let ethBalance;
      let wethBalance;
      let nuusdcBalance;

      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      nuusdcBalance = await nuUSD.balanceOf(sender);

      //  console.log('---------------------------- BEFORE');
      //  console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      //  console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      //  console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));


      // 
      // SWAP
      let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);

      let ETHPool = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUUSD_ETH_POOL_ADDRESS);

      await time.increase(180);

      // swap again the other way to get spot higher than short
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);



      let slot0ETH = await ETHPool.slot0();
      let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96;

      let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalShort);
      let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalLong);
      let getV3SqrtPrice = await oracle.getV3SqrtLowestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let shortLeqLong, spotLeqShort
      const token0 = await ETHPool.token0();



      // Eth price for debug
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString()) * BigInt(getV3SqrtPriceShort.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString()) * BigInt(getV3SqrtPriceLong.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString()) * BigInt(sqrtPriceX96Spot.toString()) * BigInt(1e18) / BigInt(2 ** 192);

      if (NUUSD_ADDRESS > configArbi.WETH_ADDRESS) {
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
      amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
      input = await nuUSD.balanceOf(sender);
      let ethBalance;
      let wethBalance;
      let nuusdcBalance;



      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      nuusdcBalance = await nuUSD.balanceOf(sender);

      // console.log('---------------------------- BEFORE');
      // console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      // console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      // console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));

      // 
      // SWAP
      let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);

      let ETHPool = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUUSD_ETH_POOL_ADDRESS);

      await time.increase(180);

      // swap again
      amountOut = BigInt(500e18).toString();// 500 dollars
      paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);

      let slot0ETH = await ETHPool.slot0();
      let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96;

      let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalShort);
      let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalLong);
      let getV3SqrtPrice = await oracle.getV3SqrtLowestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let shortLeqLong, spotLeqShort
      const token0 = await ETHPool.token0();



      // Eth price for debug
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString()) * BigInt(getV3SqrtPriceShort.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString()) * BigInt(getV3SqrtPriceLong.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString()) * BigInt(sqrtPriceX96Spot.toString()) * BigInt(1e18) / BigInt(2 ** 192);

      if (NUUSD_ADDRESS > configArbi.WETH_ADDRESS) {
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
      amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
      input = await nuUSD.balanceOf(sender);
      let ethBalance;
      let wethBalance;
      let nuusdcBalance;

      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      nuusdcBalance = await nuUSD.balanceOf(sender);

      // console.log('---------------------------- BEFORE');
      // console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      // console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      // console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));


      // 
      // SWAP
      let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);

      let ETHPool = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUUSD_ETH_POOL_ADDRESS);

      await time.increase(1800);

      // swap again
      amountOut = BigInt(500e18).toString();// 500 dollars
      paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);
      await time.increase(180);
      // and swap again but less than first time
      amountOut = BigInt(1e17).toString();// 500 dollars
      paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);
      let slot0ETH = await ETHPool.slot0();
      let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96;

      let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalShort);
      let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalLong);
      let getV3SqrtPrice = await oracle.getV3SqrtLowestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let shortLeqLong, spotLeqShort
      const token0 = await ETHPool.token0();


      // Eth price for debug
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString()) * BigInt(getV3SqrtPriceShort.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString()) * BigInt(getV3SqrtPriceLong.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString()) * BigInt(sqrtPriceX96Spot.toString()) * BigInt(1e18) / BigInt(2 ** 192);

      if (NUUSD_ADDRESS > configArbi.WETH_ADDRESS) {
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

  describe('#getV3SqrtPriceSimpleShift', () => {
    it('should give Spot Price when Highest', async () => {

      let deadline, amountOut;

      // recipient = sender
      let offset = 3600 * 10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
      deadline += 1800; // Time advanced 30min in migration to allow for the long interval


      // amount of ETH we want to get 
      amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
      input = await nuUSD.balanceOf(sender);
      let ethBalance;
      let wethBalance;
      let nuusdcBalance;


      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      nuusdcBalance = await nuUSD.balanceOf(sender);

      // console.log('---------------------------- BEFORE');
      // console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      // console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      // console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));


      // 
      // SWAP

      amountOut = BigInt(500e18).toString();// 500 dollars
      let paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);
      let ETHPool = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUUSD_ETH_POOL_ADDRESS);

      let slot0ETH = await ETHPool.slot0();
      let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96;

      let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalShort);
      let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalLong);
      let getV3SqrtPrice = await oracle.getV3SqrtHighestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);


      let shortLeqLong, spotLeqShort
      const token0 = await ETHPool.token0();



      // Eth price for debug
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString()) * BigInt(getV3SqrtPriceShort.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString()) * BigInt(getV3SqrtPriceLong.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString()) * BigInt(sqrtPriceX96Spot.toString()) * BigInt(1e18) / BigInt(2 ** 192);

      if (NUUSD_ADDRESS > configArbi.WETH_ADDRESS) {
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
      amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
      input = await nuUSD.balanceOf(sender);
      let ethBalance;
      let wethBalance;
      let nuusdcBalance;

      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      nuusdcBalance = await nuUSD.balanceOf(sender);

      //  console.log('---------------------------- BEFORE');
      //  console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      //  console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      //  console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));

      // 
      // SWAP
      let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);

      let ETHPool = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUUSD_ETH_POOL_ADDRESS);

      await time.increase(1800);

      // swap again
      amountOut = BigInt(500e18).toString();// 500 dollars
      paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);
      await time.increase(180);
      // and swap again but less than first time
      amountOut = BigInt(1e17).toString();// 500 dollars
      paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);
      let slot0ETH = await ETHPool.slot0();
      let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96;

      let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalShort);
      let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalLong);
      let getV3SqrtPrice = await oracle.getV3SqrtHighestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let shortGeqLong, spotGeqShort
      const token0 = await ETHPool.token0();



      // Eth price for debug
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString()) * BigInt(getV3SqrtPriceShort.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString()) * BigInt(getV3SqrtPriceLong.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString()) * BigInt(sqrtPriceX96Spot.toString()) * BigInt(1e18) / BigInt(2 ** 192);

      if (NUUSD_ADDRESS > configArbi.WETH_ADDRESS) {
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
      amountOut = BigInt(500e18).toString(); //500 dollars
      input = await nuUSD.balanceOf(sender);
      let ethBalance;
      let wethBalance;
      let nuusdcBalance;


      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      nuusdcBalance = await nuUSD.balanceOf(sender);

      //  console.log('---------------------------- BEFORE');
      //  console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      //  console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      //  console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));

      // 
      // SWAP
      let paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);

      let ETHPool = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUUSD_ETH_POOL_ADDRESS);

      await time.increase(1800);

      // swap again the other way
      amountOut = BigInt(1e17).toString();// 0.1 ETH
      paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);
      await time.increase(180);
      // and swap again
      amountOut = BigInt(100e18).toString();// 100 dollars
      paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);
      let slot0ETH = await ETHPool.slot0();
      let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96;

      let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalShort);
      let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalLong);
      let getV3SqrtPrice = await oracle.getV3SqrtHighestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let shortGeqLong, spotGeqShort
      const token0 = await ETHPool.token0();



      // Eth price for debug
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString()) * BigInt(getV3SqrtPriceShort.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString()) * BigInt(getV3SqrtPriceLong.toString()) * BigInt(1e18) / BigInt(2 ** 192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString()) * BigInt(sqrtPriceX96Spot.toString()) * BigInt(1e18) / BigInt(2 ** 192);

      if (NUUSD_ADDRESS > configArbi.WETH_ADDRESS) {
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

  describe('#getTokensForAmount', () => {
    // getTokensForAmountCeiling should always be higher than getTokensForAmount for all assets

    it('should be <= getTokensForAmountCeiling anonUSD', async () => {



      let amount = BigInt(1e18) // 1 nuUSD
      let tokensForAmount = await oracle.getTokensForAmount(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong, configArbi.PRICEFEEDETHUSD, amount, configArbi.WETH_ADDRESS);
      let tokensForAmountCeiling = await oracle.getTokensForAmountCeiling(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong, configArbi.PRICEFEEDETHUSD, amount, configArbi.WETH_ADDRESS);
      let amountLeqCeiling = (BigInt(tokensForAmount) <= BigInt(tokensForAmountCeiling))
      console.log(tokensForAmount);
      console.log(tokensForAmountCeiling);

      // Test
      expect(amountLeqCeiling).to.equal(true);
    })

  })

  describe('#getTokensForAmountSimpleShift', () => {
    // getTokensForAmountCeiling should always be higher than getTokensForAmount for all assets

    it('should be <= getTokensForAmount anonUSD', async () => {


      let amount = BigInt(1e18) // 1 nuUSD
      let tokensForAmount = await oracle.getTokensForAmount(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong, configArbi.PRICEFEEDETHUSD, amount, configArbi.WETH_ADDRESS);
      let tokensForAmountSimpleShift = await oracle.getNbOfNumaFromAssetUsingOracle(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong, configArbi.PRICEFEEDETHUSD, amount, configArbi.WETH_ADDRESS);
      let amountLeq = (BigInt(tokensForAmount) >= BigInt(tokensForAmountSimpleShift));
      console.log(tokensForAmount);
      console.log(tokensForAmountSimpleShift);
      // Test
      expect(amountLeq).to.equal(true);

    })
  })


  describe('#nbOfNuAssetFromNuma', () => {


    it('nbOfNuAssetFromNuma matches getNbOfNumaNeeded', async () => {

      // how many nu asset do we get by burning N Numas
      let amount = BigInt(1000e18) // 1000 numa
      let output = await oracle.nbOfNuAssetFromNuma(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong, configArbi.PRICEFEEDETHUSD, amount, configArbi.WETH_ADDRESS);
      console.log(output);
      // how many numas are need to get this amount
      let output2 = await oracle.getNbOfNumaNeeded(output, configArbi.PRICEFEEDETHUSD, NUMA_ETH_POOL_ADDRESS);
      console.log(output2);
      const epsilon = ethers.parseEther('0.000000000001');
      expect(output2).to.be.closeTo(amount, epsilon);// TODO: we have a diff is this normal?

    })
  })
  describe('#getNbOfAssetneeded', () => {


    it('getNbOfAssetneeded matches getNbOfNumaFromAsset at or above threshold', async () => {


      let deadline, amountOut;

      // recipient = sender
      let offset = 3600 * 10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
      deadline += 1800; // Time advanced 30min in migration to allow for the long interval


      // amount of ETH we want to get 
      amountOut = BigInt(12e16).toString(); // 0.12 ETH 
      input = await nuUSD.balanceOf(sender);
      let ethBalance;
      let wethBalance;
      let nuusdcBalance;



      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      nuusdcBalance = await nuUSD.balanceOf(sender);


      // SWAP
      const paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);


      //let tokenBelowThresholdAfter = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, configArbi.PRICEFEEDETHUSD, configArbi.WETH_ADDRESS);



      let amount = BigInt(1e18);
      let costSimpleShift = await oracle.getNbOfNumaFromAsset(amount, configArbi.PRICEFEEDETHUSD, NUMA_ETH_POOL_ADDRESS);
      console.log(costSimpleShift);
      // 
      let assetNeeded = await oracle.getNbOfAssetneeded(costSimpleShift, configArbi.PRICEFEEDETHUSD, NUMA_ETH_POOL_ADDRESS);
      const epsilon = ethers.parseEther('0.000000000001');

      expect(amount).to.be.closeTo(assetNeeded, epsilon);


    })

    it('getNbOfAssetneeded matches getNbOfNumaFromAsset below threshold', async () => {

      let deadline, amountOut;

      // recipient = sender
      let offset = 3600 * 10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300 + offset)).toString(); // Deadline five minutes from 'now'
      deadline += 1800; // Time advanced 30min in migration to allow for the long interval


      // amount of ETH we want to get 
      amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
      input = await nuUSD.balanceOf(sender);
      let ethBalance;
      let wethBalance;
      let nuusdcBalance;


      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      nuusdcBalance = await nuUSD.balanceOf(sender);

      // SWAP
      const paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);


      //let tokenBelowThresholdAfter = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, configArbi.PRICEFEEDETHUSD, configArbi.WETH_ADDRESS);


      let amount = BigInt(1e18);
      let costSimpleShift = await oracle.getNbOfNumaFromAsset(amount, configArbi.PRICEFEEDETHUSD,NUMA_ETH_POOL_ADDRESS);
      console.log(costSimpleShift);
      let assetNeeded = await oracle.getNbOfAssetneeded(costSimpleShift, configArbi.PRICEFEEDETHUSD,NUMA_ETH_POOL_ADDRESS);
      const epsilon = ethers.parseEther('0.000000000001');
      expect(amount).to.be.closeTo(assetNeeded, epsilon);

    });


  })


  describe('#view function results', () => {
    it('Should be able to call view functions with appropriate results', async function () {
      // get price from chainlink USD/ETH PRICEFEEDETHUSD
      let chainlinkInstance = await hre.ethers.getContractAt(artifacts.AggregatorV3, configArbi.PRICEFEEDETHUSD);
      let latestRoundData = await chainlinkInstance.latestRoundData();
      let latestRoundPrice = Number(latestRoundData.answer);
      let decimals = Number(await chainlinkInstance.decimals());
      let price = latestRoundPrice / 10 ** decimals;
      let OracleValue = await oracle.chainlinkPrice(configArbi.PRICEFEEDETHUSD);
      expect(latestRoundData.answer).to.equal(OracleValue);
      // TODO; check values of other functions

    });
  })

  describe('#set parameters', () => {
    it('Should be able to set parameters', async function () {
      let intervalShortNew = 360;
      let intervalLongNew = 3600;
    
      await expect(oracle.setIntervalShort(intervalShortNew)).to.emit(oracle, "IntervalShort").withArgs(intervalShortNew);
      await expect(oracle.setIntervalLong(intervalLongNew)).to.emit(oracle, "IntervalLong").withArgs(intervalLongNew);
      // check values
      expect(await oracle.intervalShort()).to.equal(intervalShortNew);
      expect(await oracle.intervalLong()).to.equal(intervalLongNew);
     

    });
  })

  describe('#ownable', () => {
    it('Should implement Ownable', async function () {
      let intervalShortNew = 360;
      let intervalLongNew = 3600;

      expect(await oracle.owner()).to.equal(await signer.getAddress());
      //
      await expect(oracle.connect(signer2).setIntervalShort(intervalShortNew)).to.be.revertedWithCustomError(oracle, "OwnableUnauthorizedAccount",)
        .withArgs(await signer2.getAddress());
      await expect(oracle.connect(signer2).setIntervalLong(intervalLongNew)).to.be.revertedWithCustomError(oracle, "OwnableUnauthorizedAccount",)
        .withArgs(await signer2.getAddress());

      //
      await oracle.connect(signer).transferOwnership(await signer2.getAddress());
      await expect(oracle.connect(signer2).setIntervalShort(intervalShortNew)).to.not.be.reverted;
    });

  })





});

