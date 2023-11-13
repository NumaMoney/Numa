const { getPoolData,getPool, initPoolETH, addLiquidity, weth9, artifacts,swapOptions,buildTrade,SwapRouter,Token } = require("../scripts/Utils.js");
const { deployPrinterTestFixture,config } = require("./fixtures/NumaPrinterTestFixtureDeployNuma.js");
const { time, loadFixture, takeSnapshot} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { upgrades } = require("hardhat");
// TODO: I should be able to get it from utils
const {  Trade: V3Trade, Route: RouteV3  } = require('@uniswap/v3-sdk');
const { WETH_ADDRESS } = require("@uniswap/universal-router-sdk");

// ********************* Numa oracle test using sepolia fork for chainlink *************************


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
  let  cardinalityLaunch; // How many observations to save in a pool, at launch
  let factory;
  let snapshot;
  let swapRouter;
  let routerAddress;
  afterEach(async function() {
    console.log("reseting snapshot");
    await snapshot.restore();
    snapshot = await takeSnapshot();
  })

  before(async function () 
  {
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
    oracle =  await Oracle.attach(oracleAddress);
    cardinalityLaunch = testData.cardinality;
    factory = testData.factory;

    swapRouter = testData.swapRouter;
    routerAddress = await swapRouter.getAddress();
         
    snapshot = await takeSnapshot();

  });
  
  it('Should have right initialization parameters', async function () 
  {
    expect(await oracle.intervalShort()).to.equal(config.INTERVAL_SHORT);
    expect(await oracle.intervalLong()).to.equal(config.INTERVAL_LONG);
    expect(await oracle.flexFeeThreshold()).to.equal(config.FLEXFEETHRESHOLD);

  });

  describe('#pool check', () => {

    it('should work USD', async () => {
      let tokenPool = await moneyPrinter.tokenPool();
      let pool = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUUSD_ETH_POOL_ADDRESS);
      //let pool = await UniV3Pool.at(tokenPool);
     // console.log(pool);
      let cardinality = 100 + cardinalityLaunch;
      //let { logs } = await pool.increaseObservationCardinalityNext.sendTransaction(cardinality, {from: signer});
      let { logs } = await pool.increaseObservationCardinalityNext(cardinality);
      console.log(logs);
     
      const {sqrtPriceX96, unlocked} = await pool.slot0();

      expect(sqrtPriceX96).to.not.equal(BigInt(0));
      expect(unlocked).to.equal(true);


      // TODO?
      // logs[0].event.should.be.equal("IncreaseObservationCardinalityNext")
      // logs[0].args.observationCardinalityNextOld.should.be.eq.BN(cardinalityLaunch)
      // logs[0].args.observationCardinalityNextNew.should.be.eq.BN(cardinality)
    });
  });

 

 
  describe('#swap check nuUSD & tokenBelowThreshold', () => {
    it('should change after swapping nuUSD for 0.5 WETH', async () => {

      let chainlinkInstance = await hre.ethers.getContractAt(artifacts.AggregatorV3, config.PRICEFEEDETHUSD);
      let latestRoundData = await chainlinkInstance.latestRoundData();
      let latestRoundPrice = Number(latestRoundData.answer);
      let decimals = Number(await chainlinkInstance.decimals());
      let price = latestRoundPrice / 10**decimals;
     

      let sender = await signer2.getAddress();
      await nuUSD.mint(sender, BigInt(1e23));




 

      let tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96;
      tokenIn = NUUSD_ADDRESS;
      tokenOut = config.WETH_ADDRESS;
      fee = "500";
      // recipient = sender
      let offset = 3600*10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300+offset)).toString(); // Deadline five minutes from 'now'
      deadline+=1800; // Time advanced 30min in migration to allow for the long interval
      console.log(sender);

      // amount of ETH we want to get 
      amountOut = BigInt(5e17).toString(); // 0.5 ETH 
      amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
      sqrtPriceLimitX96 = "0x0";
      input = await nuUSD.balanceOf(sender);
      let ethBalance;
      let wethBalance;
      let nuusdcBalance;



      let threshold = config.FLEXFEETHRESHOLD;
      let intervalShort = 180;
      let intervalLong = 1800;

   
      let tokenBelowThreshold = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, config.WETH_ADDRESS);
      let uniSqrtPriceLow = await oracle.getV3SqrtLowestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let uniSqrtPriceHigh = await oracle.getV3SqrtHighestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);

      // uint256 numerator = (IUniswapV3Pool(_pool).token1() == _weth9 ? sqrtPriceX96 : FixedPoint96.Q96);
      // uint256 denominator = (numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96);
      // //ETH per Token, times 1e18
      // uint256 ethPerToken = FullMath.mulDiv(FullMath.mulDiv(numerator, numerator, denominator), 1e18, denominator);

      let uniPriceLow = BigInt(uniSqrtPriceLow.toString())*BigInt(uniSqrtPriceLow.toString())/BigInt(2**192);     
      let uniPriceHigh = BigInt(uniSqrtPriceHigh.toString())*BigInt(uniSqrtPriceHigh.toString())/BigInt(2**192);

      console.log(`Swap price low of pool before swap: ${hre.ethers.formatUnits(uniPriceLow,18)}`);
      console.log(`Swap price high of pool before swap: ${hre.ethers.formatUnits(uniPriceHigh,18)}`);
      console.log(`Token below threshold before swap: ${tokenBelowThreshold}`);


      if (NUUSD_ADDRESS > config.WETH_ADDRESS)
      {
        // change numerator/denominator
        uniPriceLow = 1.0/Number(uniPriceLow);
        uniPriceHigh =1.0/Number(uniPriceHigh); 
      }
  
      uniPriceLow = Number(uniPriceLow)*Math.pow(10, 18);
      uniPriceHigh = Number(uniPriceHigh)*Math.pow(10, 18);


     
      // TODO: what's this for?
      // let tokensForAmount = await oracle.getTokensForAmount(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, BigInt(1e18), config.WETH_ADDRESS);
      // tokensForAmount = tokensForAmount.toString()
      // let numaForAmount = await oracle.getTokensForAmount(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, BigInt(1e18), config.WETH_ADDRESS);
      // numaForAmount = numaForAmount.toString();

      // console.log(`Tokens for amount, NUMA for 1 nuUSD, in Wei: ${numaForAmount}`);
      // // TODO: fix this log
      // console.log(`Tokens for amount, ETH for 1 USD, in Wei: ${tokensForAmount}`);

      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      nuusdcBalance = await nuUSD.balanceOf(sender);

      console.log('---------------------------- BEFORE');
      console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));
      await nuUSD.connect(signer2).approve(routerAddress, amountInMaximum);

      // 
      let uniPriceBefore = uniPriceLow;
      console.log(uniPriceBefore);
      let ratio = (Number(uniPriceBefore)/(1.0/price));
      console.log(ratio);
      let priceBelowThresholdBefore = ( ratio < threshold);
      expect(priceBelowThresholdBefore).to.equal(false);
      expect(tokenBelowThreshold).to.equal(priceBelowThresholdBefore);
      

      // 
      // SWAP
      const paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];      
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);

      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      nuusdcBalance = await nuUSD.balanceOf(sender);

      console.log('---------------------------- AFTER');
      console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));



      let tokenBelowThresholdAfter = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, config.WETH_ADDRESS);

      uniSqrtPriceLow = await oracle.getV3SqrtLowestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      uniSqrtPriceHigh = await oracle.getV3SqrtHighestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);

      uniPriceLow = BigInt(uniSqrtPriceLow.toString())*BigInt(uniSqrtPriceLow.toString())/BigInt(2**192);
      uniPriceHigh = BigInt(uniSqrtPriceHigh.toString())*BigInt(uniSqrtPriceHigh.toString())/BigInt(2**192);
      console.log(`Swap price low of pool after swap: ${hre.ethers.formatUnits(uniPriceLow,18)}`);
      console.log(`Swap price high of pool after swap: ${hre.ethers.formatUnits(uniPriceHigh,18)}`);
      console.log(`Token below threshold, after swap: ${tokenBelowThresholdAfter}`);

      if (NUUSD_ADDRESS > config.WETH_ADDRESS)
      {
        // change numerator/denominator
        uniPriceLow = 1.0/Number(uniPriceLow);
        uniPriceHigh =1.0/Number(uniPriceHigh); 
      }
  
      uniPriceLow = Number(uniPriceLow)*Math.pow(10, 18);
      uniPriceHigh = Number(uniPriceHigh)*Math.pow(10, 18);


     

      // 
      let uniPriceAfter = uniPriceLow;
      console.log(uniPriceAfter);
      ratio = (Number(uniPriceAfter)/(1.0/price));
      console.log(ratio);
      let priceBelowThresholdAfter = (ratio < threshold);

      // Tests
      expect(priceBelowThresholdAfter).to.equal(true);
      expect(tokenBelowThresholdAfter).to.equal(priceBelowThresholdAfter);

    })
  })

 

  describe('#getCostSimpleShift nuUSD', () => {
    it('should return getTokensForAmount when at or above threshold', async () => {
     
      // mint some nuUSD
      let sender = await signer2.getAddress();
      await nuUSD.mint(sender, BigInt(1e23));


      let tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96;
      tokenIn = NUUSD_ADDRESS;
      tokenOut = config.WETH_ADDRESS;
      fee = "500";
      // recipient = sender
      let offset = 3600*10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300+offset)).toString(); // Deadline five minutes from 'now'
      deadline+=1800; // Time advanced 30min in migration to allow for the long interval
      console.log(sender);

      // amount of ETH we want to get 
      amountOut = BigInt(12e16).toString(); // 0.12 ETH 
      amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
      sqrtPriceLimitX96 = "0x0";
      input = await nuUSD.balanceOf(sender);
      let ethBalance;
      let wethBalance;
      let nuusdcBalance;



      let threshold = config.FLEXFEETHRESHOLD;
      let intervalShort = 180;
      let intervalLong = 1800;

  

      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      nuusdcBalance = await nuUSD.balanceOf(sender);

      console.log('---------------------------- BEFORE');
      console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));
      await nuUSD.connect(signer2).approve(routerAddress, amountInMaximum);


    
      // 
      // SWAP
      const paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];      
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);


      let tokenBelowThresholdAfter = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, config.WETH_ADDRESS);
      console.log(tokenBelowThresholdAfter);


      let amount = BigInt(1e18);
      let costSimpleShift = await oracle.getNbOfNumaFromAsset(amount, config.PRICEFEEDETHUSD, NUMA_ETH_POOL_ADDRESS, NUUSD_ETH_POOL_ADDRESS);
      costSimpleShift = costSimpleShift.toString()
      console.log(costSimpleShift);
      let costRaw = (await oracle.getNbOfNumaFromAssetUsingPools(NUMA_ETH_POOL_ADDRESS, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, amount, config.WETH_ADDRESS)).toString();

      let costAmount = (await oracle.getNbOfNumaFromAssetUsingOracle(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, amount, config.WETH_ADDRESS)).toString();

      belowThreshold = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, config.WETH_ADDRESS);
      let costRawLeqCostAmount = (BigInt(costRaw) <= BigInt(costAmount));

      // Tests
      expect(belowThreshold).to.equal(false);
      expect(costRawLeqCostAmount).to.equal(true);
      expect(costSimpleShift).to.equal(costAmount);

    })
  
    it('should return getTokensRaw when below threshold', async () => {
      // mint some nuUSD
      let sender = await signer2.getAddress();
      await nuUSD.mint(sender, BigInt(1e23));


      let tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96;
      tokenIn = NUUSD_ADDRESS;
      tokenOut = config.WETH_ADDRESS;
      fee = "500";
      // recipient = sender
      let offset = 3600*10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300+offset)).toString(); // Deadline five minutes from 'now'
      deadline+=1800; // Time advanced 30min in migration to allow for the long interval
      console.log(sender);

      // amount of ETH we want to get 
      amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
      amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
      sqrtPriceLimitX96 = "0x0";
      input = await nuUSD.balanceOf(sender);
      let ethBalance;
      let wethBalance;
      let nuusdcBalance;



      let threshold = config.FLEXFEETHRESHOLD;
      let intervalShort = 180;
      let intervalLong = 1800;

  

      // execute SWAP
      ethBalance = await ethers.provider.getBalance(sender);
      wethBalance = await wethContract.balanceOf(sender);
      nuusdcBalance = await nuUSD.balanceOf(sender);

      console.log('---------------------------- BEFORE');
      console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));
      await nuUSD.connect(signer2).approve(routerAddress, amountInMaximum);


    
      // 
      // SWAP
      const paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];      
      await swapRouter.connect(signer2).exactOutputSingle(paramsCall);


      let tokenBelowThresholdAfter = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, config.WETH_ADDRESS);
      console.log(tokenBelowThresholdAfter);


      let amount = BigInt(1e18);
      let costSimpleShift = await oracle.getNbOfNumaFromAsset(amount, config.PRICEFEEDETHUSD, NUMA_ETH_POOL_ADDRESS, NUUSD_ETH_POOL_ADDRESS);
      costSimpleShift = costSimpleShift.toString()
      console.log(costSimpleShift);
      let costRaw = (await oracle.getNbOfNumaFromAssetUsingPools(NUMA_ETH_POOL_ADDRESS, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, amount, config.WETH_ADDRESS)).toString();

      let costAmount = (await oracle.getNbOfNumaFromAssetUsingOracle(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, amount, config.WETH_ADDRESS)).toString();

      belowThreshold = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, config.WETH_ADDRESS);
      let costRawLeqCostAmount = (BigInt(costRaw) <= BigInt(costAmount));

      // Tests
      expect(belowThreshold).to.equal(true);
      expect(costRawLeqCostAmount).to.equal(true);
      expect(costSimpleShift).to.equal(costRaw);
    });
  })

  describe('#getV3SqrtPrice', () => {
    it('should give Spot Price when Lowest', async () => 
    {
       // mint some nuUSD
       let sender = await signer2.getAddress();
       await nuUSD.mint(sender, BigInt(1e23));
 
 
       let tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96;
       tokenIn = NUUSD_ADDRESS;
       tokenOut = config.WETH_ADDRESS;
       fee = "500";
       // recipient = sender
       let offset = 3600*10000000;// TODO 
       deadline = Math.round((Date.now() / 1000 + 300+offset)).toString(); // Deadline five minutes from 'now'
       deadline+=1800; // Time advanced 30min in migration to allow for the long interval
       console.log(sender);
 
       // amount of ETH we want to get 
       amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
       amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
       sqrtPriceLimitX96 = "0x0";
       input = await nuUSD.balanceOf(sender);
       let ethBalance;
       let wethBalance;
       let nuusdcBalance;
 
 
 
       let threshold = config.FLEXFEETHRESHOLD;
       let intervalShort = 180;
       let intervalLong = 1800;
 
   
 
       // execute SWAP
       ethBalance = await ethers.provider.getBalance(sender);
       wethBalance = await wethContract.balanceOf(sender);
       nuusdcBalance = await nuUSD.balanceOf(sender);
 
       console.log('---------------------------- BEFORE');
       console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
       console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
       console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));
       await nuUSD.connect(signer2).approve(routerAddress, amountInMaximum);
 
 
     
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
      
      console.log(await ETHPool.token0());
      console.log(await ETHPool.token1());
      console.log(getV3SqrtPriceLong);
      console.log(getV3SqrtPriceShort);
      console.log(sqrtPriceX96Spot);

      // Eth price for debug
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString())*BigInt(getV3SqrtPriceShort.toString())/BigInt(2**192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString())*BigInt(getV3SqrtPriceLong.toString())/BigInt(2**192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString())*BigInt(sqrtPriceX96Spot.toString())/BigInt(2**192);
     
      if (NUUSD_ADDRESS < config.WETH_ADDRESS)
      {
        // change numerator/denominator
        uniPriceShort = 1.0/Number(uniPriceShort);
        uniPriceLong = 1.0/Number(uniPriceLong);
        uniPriceSpot = 1.0/Number(uniPriceSpot);
       
      }

      
      console.log(uniPriceLong);
      console.log(uniPriceShort);
      console.log(uniPriceSpot);

      if (token0 === config.WETH_ADDRESS)
      {
        shortLeqLong = (getV3SqrtPriceShort >= getV3SqrtPriceLong);       
        spotLeqShort = (sqrtPriceX96Spot >= getV3SqrtPriceShort);
      } 
      else 
      {
        shortLeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong);
        spotLeqShort = (sqrtPriceX96Spot <= getV3SqrtPriceShort);
      }

      // Tests
      expect(shortLeqLong).to.equal(true);
      expect(spotLeqShort).to.equal(true);
      expect(getV3SqrtPrice).to.equal(sqrtPriceX96Spot);

  
    })
    it('should give Short Interval Price when Lowest', async () => 
    {
          // mint some nuUSD
          let sender = await signer2.getAddress();
          await nuUSD.mint(sender, BigInt(1e23));
    
    
          let tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96;
          tokenIn = NUUSD_ADDRESS;
          tokenOut = config.WETH_ADDRESS;
          fee = "500";
          // recipient = sender
          let offset = 3600*10000000;// TODO 
          deadline = Math.round((Date.now() / 1000 + 300+offset)).toString(); // Deadline five minutes from 'now'
          deadline+=1800; // Time advanced 30min in migration to allow for the long interval
          console.log(sender);
    
          // amount of ETH we want to get 
          amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
          amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
          sqrtPriceLimitX96 = "0x0";
          input = await nuUSD.balanceOf(sender);
          let ethBalance;
          let wethBalance;
          let nuusdcBalance;
    
    
    
          let threshold = config.FLEXFEETHRESHOLD;
          let intervalShort = 180;
          let intervalLong = 1800;
    
      
    
          // execute SWAP
          ethBalance = await ethers.provider.getBalance(sender);
          wethBalance = await wethContract.balanceOf(sender);
          nuusdcBalance = await nuUSD.balanceOf(sender);
    
          console.log('---------------------------- BEFORE');
          console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
          console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
          console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));
          await nuUSD.connect(signer2).approve(routerAddress, amountInMaximum);
    
    
        
          // 
          // SWAP
          let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];      
          await swapRouter.connect(signer2).exactOutputSingle(paramsCall);
    
          let ETHPool = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUUSD_ETH_POOL_ADDRESS);
   
          await time.increase(180);
   
          // swap again
          await wethContract.connect(signer2).approve(routerAddress, amountInMaximum);
          amountOut = BigInt(500e18).toString();// 500 dollars
          paramsCall = [tokenOut,tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];         
          await swapRouter.connect(signer2).exactOutputSingle(paramsCall);
   
         let slot0ETH = await ETHPool.slot0();
         let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96;
   
         let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalShort);
         let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalLong);
         let getV3SqrtPrice = await oracle.getV3SqrtLowestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);
         let shortLeqLong, spotLeqShort
         const token0 = await ETHPool.token0();
         
         console.log(await ETHPool.token0());
         console.log(await ETHPool.token1());
         console.log(getV3SqrtPriceLong);
         console.log(getV3SqrtPriceShort);
         console.log(sqrtPriceX96Spot);
   
         // Eth price for debug
         let uniPriceShort = BigInt(getV3SqrtPriceShort.toString())*BigInt(getV3SqrtPriceShort.toString())/BigInt(2**192);
         let uniPriceLong = BigInt(getV3SqrtPriceLong.toString())*BigInt(getV3SqrtPriceLong.toString())/BigInt(2**192);
         let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString())*BigInt(sqrtPriceX96Spot.toString())/BigInt(2**192);
        
         if (NUUSD_ADDRESS < config.WETH_ADDRESS)
         {
           // change numerator/denominator
           uniPriceShort = 1.0/Number(uniPriceShort);
           uniPriceLong = 1.0/Number(uniPriceLong);
           uniPriceSpot = 1.0/Number(uniPriceSpot);
          
         }
   
         
         console.log(uniPriceLong);
         console.log(uniPriceShort);
         console.log(uniPriceSpot);

         if (token0 === config.WETH_ADDRESS)
         {
          shortLeqLong = (getV3SqrtPriceShort >= getV3SqrtPriceLong);
          spotLeqShort = (sqrtPriceX96Spot >= getV3SqrtPriceShort);
         } 
         else 
         {
          shortLeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong);
          spotLeqShort = (sqrtPriceX96Spot <= getV3SqrtPriceShort);
         }
   
         // Tests
         expect(shortLeqLong).to.equal(true);
         expect(spotLeqShort).to.equal(false);
         expect(getV3SqrtPrice).to.equal(getV3SqrtPriceShort);

          
    })
    it('should give Long Interval Price when Lowest', async () => {
          // mint some nuUSD
          let sender = await signer2.getAddress();
          await nuUSD.mint(sender, BigInt(1e23));
    
    
          let tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96;
          tokenIn = NUUSD_ADDRESS;
          tokenOut = config.WETH_ADDRESS;
          fee = "500";
          // recipient = sender
          let offset = 3600*10000000;// TODO 
          deadline = Math.round((Date.now() / 1000 + 300+offset)).toString(); // Deadline five minutes from 'now'
          deadline+=1800; // Time advanced 30min in migration to allow for the long interval
          console.log(sender);
    
          // amount of ETH we want to get 
          amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
          amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
          sqrtPriceLimitX96 = "0x0";
          input = await nuUSD.balanceOf(sender);
          let ethBalance;
          let wethBalance;
          let nuusdcBalance;
    
    
    
          let threshold = config.FLEXFEETHRESHOLD;
          let intervalShort = 180;
          let intervalLong = 1800;
    
      
    
          // execute SWAP
          ethBalance = await ethers.provider.getBalance(sender);
          wethBalance = await wethContract.balanceOf(sender);
          nuusdcBalance = await nuUSD.balanceOf(sender);
    
          console.log('---------------------------- BEFORE');
          console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
          console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
          console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));
          await nuUSD.connect(signer2).approve(routerAddress, amountInMaximum);
    
    
        
          // 
          // SWAP
          let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];      
          await swapRouter.connect(signer2).exactOutputSingle(paramsCall);
    
          let ETHPool = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUUSD_ETH_POOL_ADDRESS);
   
          await time.increase(1800);
   
          // swap again
          await wethContract.connect(signer2).approve(routerAddress, amountInMaximum);
          amountOut = BigInt(500e18).toString();// 500 dollars
          paramsCall = [tokenOut,tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];         
          await swapRouter.connect(signer2).exactOutputSingle(paramsCall);
          await time.increase(180);
          // and swap again but less than first time
          amountOut = BigInt(1e17).toString();// 500 dollars
          paramsCall = [tokenIn,tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];         
          await swapRouter.connect(signer2).exactOutputSingle(paramsCall);
         let slot0ETH = await ETHPool.slot0();
         let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96;
   
         let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalShort);
         let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalLong);
         let getV3SqrtPrice = await oracle.getV3SqrtLowestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);
         let shortLeqLong, spotLeqShort
         const token0 = await ETHPool.token0();
         
         console.log(await ETHPool.token0());
         console.log(await ETHPool.token1());
         console.log(getV3SqrtPriceLong);
         console.log(getV3SqrtPriceShort);
         console.log(sqrtPriceX96Spot);
   
         // Eth price for debug
         let uniPriceShort = BigInt(getV3SqrtPriceShort.toString())*BigInt(getV3SqrtPriceShort.toString())/BigInt(2**192);
         let uniPriceLong = BigInt(getV3SqrtPriceLong.toString())*BigInt(getV3SqrtPriceLong.toString())/BigInt(2**192);
         let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString())*BigInt(sqrtPriceX96Spot.toString())/BigInt(2**192);
        
         if (NUUSD_ADDRESS < config.WETH_ADDRESS)
         {
           // change numerator/denominator
           uniPriceShort = 1.0/Number(uniPriceShort);
           uniPriceLong = 1.0/Number(uniPriceLong);
           uniPriceSpot = 1.0/Number(uniPriceSpot);
          
         }
   
         
         console.log(uniPriceLong);
         console.log(uniPriceShort);
         console.log(uniPriceSpot);

         if (token0 === config.WETH_ADDRESS)
         {
          shortLeqLong = (getV3SqrtPriceShort >= getV3SqrtPriceLong);
          spotLeqLong = (sqrtPriceX96Spot >= getV3SqrtPriceLong);
         } 
         else 
         {
          shortLeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong);
          spotLeqLong = (sqrtPriceX96Spot <= getV3SqrtPriceLong);
         }
   
         // Tests
         expect(shortLeqLong).to.equal(false);
         expect(spotLeqLong).to.equal(false);
         expect(getV3SqrtPrice).to.equal(getV3SqrtPriceLong);
    
    })
  })

  // describe('#getV3SqrtPriceSimpleShift', () => {
  //   it('should give Spot Price when Highest', async () => {
  //     await tokenETH.mint(sender, BigInt(1e22)) // 10,000 anonETH
  //     let routerAddress = uniswap.SwapRouter
  //     let router = await SwapRouter.at(routerAddress)
  //     let pool = await shifterETH.tokenPool()
  //     let ETHPool = await UniV3Pool.at(pool)
  //     let cardinality = 10
  //     await ETHPool.increaseObservationCardinalityNext.sendTransaction(cardinality, {from: sender})
  //     let tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96
  //     tokenOut = tokenETH.address
  //     tokenIn = weth9
  //     fee = "3000"
  //     recipient = sender
  //     deadline = Math.round((Date.now() / 1000 + 300)).toString() // Deadline five minutes from 'now'
  //     deadline+=1800 // Time advanced 30min in migration to allow for the long interval
  //     advanceTimeAndBlock(1800)
  //     amountOut = BigInt(5e18).toString() // 5 ETH
  //     amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  //     sqrtPriceLimitX96 = "0x0"
  //     input = await weth.balanceOf(sender)
  //     await weth.approve(routerAddress, amountInMaximum)
  //     let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, input, sqrtPriceLimitX96]
  //     // Swap anonETH -> WETH at the end of the interval to make spot price the lowest
  //     let amountCall = await router.exactOutputSingle.call(paramsCall, {from: sender})
  //     amountInMaximum = amountCall.toString()
  //     let intervalShort = 180
  //     let intervalLong = 1800
  //     deadline += 1800
  //     let params = [tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96]
  //     await router.exactOutputSingle.sendTransaction(params, {from: sender})
  //     let slot0ETH = await ETHPool.slot0()
  //     let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96
  //     let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg.call(pool, intervalShort, {from: sender})
  //     let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg.call(pool, intervalLong, {from: sender})
  //     let getV3SqrtPrice = await oracle.getV3SqrtPriceSimpleShift.call(pool, intervalShort, intervalLong, {from: sender})
  //     let shortGeqLong, spotGeqShort
  //     const token0 = await ETHPool.token0()
  //     if (token0 === weth9){
  //       shortGeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong)
  //       spotGeqShort = (sqrtPriceX96Spot <= getV3SqrtPriceShort)
  //     } else {
  //       shortGeqLong = (getV3SqrtPriceShort >= getV3SqrtPriceLong)
  //       spotGeqShort = (sqrtPriceX96Spot >= getV3SqrtPriceShort)
  //     }

  //     // Tests
  //     shortGeqLong.should.be.equal(true)
  //     spotGeqShort.should.be.equal(true)
  //     getV3SqrtPrice.should.be.eq.BN(sqrtPriceX96Spot)
  //   })
  //   it('should give Short Interval Price when Highest', async () => {
  //     await tokenETH.mint(sender, BigInt(1e22)) // 10,000 anonETH
  //     let routerAddress = uniswap.SwapRouter
  //     let router = await SwapRouter.at(routerAddress)
  //     let pool = await shifterETH.tokenPool()
  //     let ETHPool = await UniV3Pool.at(pool)
  //     let cardinality = 10
  //     await ETHPool.increaseObservationCardinalityNext.sendTransaction(cardinality, {from: sender})
  //     let tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96
  //     tokenOut = tokenETH.address
  //     tokenIn = weth9
  //     fee = "3000"
  //     recipient = sender
  //     deadline = Math.round((Date.now() / 1000 + 300)).toString() //Deadline five minutes from 'now'
  //     deadline += 3600 //add an hour
  //     amountOut = BigInt(5e18).toString() //5 ETH
  //     amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  //     sqrtPriceLimitX96 = "0x0"
  //     input = await weth.balanceOf(sender)
  //     await weth.approve(routerAddress, amountInMaximum)
  //     let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, input, sqrtPriceLimitX96]
  //     let amountCall = await router.exactOutputSingle.call(paramsCall, {from: sender})
  //     amountInMaximum = amountCall.toString()
  //     let intervalShort = 180
  //     let intervalLong = 1800
  //     advanceTimeAndBlock(intervalLong - intervalShort)
  //     deadline += intervalLong*2
  //     let params = [tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96]
  //     //Swap WETH -> anonUSD at (intervalLong - intervalShort) to make the short interval price lower than the long
  //     await router.exactOutputSingle.sendTransaction(params, {from: sender})
  //     advanceTimeAndBlock(intervalShort)
  //     //Swap tokenIn and tokenOut, anonETH in WETH out
  //     input = await tokenETH.balanceOf(sender)
  //     await tokenETH.approve.sendTransaction(routerAddress, amountInMaximum, {from: sender})
  //     paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, input, sqrtPriceLimitX96]
  //     amountCall = await router.exactOutputSingle.call(paramsCall, {from: sender})
  //     amountInMaximum = amountCall.toString()
  //     params = [tokenOut, tokenIn, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96]
  //     //Swap WETH -> anonETH to make short interval price lower than spot price
  //     await router.exactOutputSingle.sendTransaction(params, {from: sender})
  //     let slot0ETH = await ETHPool.slot0()
  //     let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96
  //     let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg.call(pool, intervalShort, {from: sender})
  //     let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg.call(pool, intervalLong, {from: sender})
  //     let getV3SqrtPrice = await oracle.getV3SqrtPriceSimpleShift.call(pool, intervalShort, intervalLong, {from: sender})
  //     let shortGeqLong, spotGeqShort
  //     const token0 = await ETHPool.token0()
  //     if (token0 === weth9){
  //       shortGeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong)
  //       spotGeqShort = (sqrtPriceX96Spot <= getV3SqrtPriceShort)
  //     } else {
  //       shortGeqLong = (getV3SqrtPriceShort >= getV3SqrtPriceLong)
  //       spotGeqShort = (sqrtPriceX96Spot >= getV3SqrtPriceShort)
  //     }

  //     // Tests
  //     shortGeqLong.should.be.equal(true)
  //     spotGeqShort.should.be.equal(false)
  //     getV3SqrtPrice.should.be.eq.BN(getV3SqrtPriceShort)
  //   })
  //   it('should give Long Interval Price when Highest', async () => {
  //     await tokenETH.mint(sender, BigInt(1e22)) // 10,000 anonETH
  //     let routerAddress = uniswap.SwapRouter
  //     let router = await SwapRouter.at(routerAddress)
  //     let pool = await shifterETH.tokenPool()
  //     let ETHPool = await UniV3Pool.at(pool)
  //     let cardinality = 10
  //     await ETHPool.increaseObservationCardinalityNext.sendTransaction(cardinality, {from: sender})
  //     let tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96
  //     tokenOut = tokenETH.address
  //     tokenIn = weth9
  //     fee = "3000"
  //     recipient = sender
  //     deadline = Math.round((Date.now() / 1000 + 300)).toString() // Deadline five minutes from 'now'
  //     deadline += 3600 //add an hour
  //     amountOut = BigInt(5e18).toString() //5 ETH
  //     amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  //     sqrtPriceLimitX96 = "0x0"
  //     input = await weth.balanceOf(sender)
  //     await weth.approve.sendTransaction(routerAddress, amountInMaximum, {from: sender})
  //     await tokenETH.approve(routerAddress, amountInMaximum)
  //     let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, input, sqrtPriceLimitX96]
  //     // Swap anonETH -> WETH at the beginning of the interval to make the long interval return the lowest price
  //     let amountCall = await router.exactOutputSingle.call(paramsCall, {from: sender})
  //     amountInMaximum = amountCall.toString()
  //     let intervalShort = 180
  //     let intervalLong = 1800
  //     deadline += intervalLong*2
  //     let params = [tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96]
  //     await router.exactOutputSingle.sendTransaction(params, {from: sender})
  //     advanceTimeAndBlock(intervalLong - intervalShort)
  //     // Swap tokenIn and tokenOut, WETH in anonETH out
  //     input = await tokenETH.balanceOf(sender)
  //     paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, input, sqrtPriceLimitX96]
  //     amountCall = await router.exactOutputSingle.call(paramsCall, {from: sender})
  //     amountInMaximum = amountCall.toString()
  //     params = [tokenOut, tokenIn, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96]
  //     // Swap WETH -> anonETH at the start of intervalShort to increase short interval and spot price
  //     await router.exactOutputSingle.sendTransaction(params, {from: sender})
  //     advanceTimeAndBlock(intervalShort)
  //     let slot0ETH = await ETHPool.slot0()
  //     let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96
  //     let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg.call(pool, intervalShort, {from: sender})
  //     let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg.call(pool, intervalLong, {from: sender})
  //     let getV3SqrtPrice = await oracle.getV3SqrtPriceSimpleShift.call(pool, intervalShort, intervalLong, {from: sender})
  //     let shortGeqLong, spotGeqLong
  //     const token0 = await ETHPool.token0()
  //     if (token0 === weth9){
  //       shortGeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong)
  //       spotGeqLong = (sqrtPriceX96Spot <= getV3SqrtPriceLong)
  //     } else {
  //       shortGeqLong = (getV3SqrtPriceShort >= getV3SqrtPriceLong)
  //       spotGeqLong = (sqrtPriceX96Spot >= getV3SqrtPriceLong)
  //     }

  //     // Tests
  //     shortGeqLong.should.be.equal(false)
  //     spotGeqLong.should.be.equal(false)
  //     getV3SqrtPrice.should.be.eq.BN(getV3SqrtPriceLong)
  //   })
  // })

  // describe('#getTokensForAmount', () => {
  //   // getTokensForAmountCeiling should always be higher than getTokensForAmount for all assets
  //   
  //   it('should be <= getTokensForAmountCeiling anonUSD', async () => {
  //     await token.mint(sender, BigInt(1e22)) // 10,000 anonUSD
  //     let xftPool = await shifter.tokenPool()
  //     let intervalShort = 180
  //     let intervalLong = 1800
  //     let linkFeed = tokenStyle.anonUSD.chainlink
  //     let amount = BigInt(1e18) // 1 anonUSD
  //     let tokensForAmount = await oracle.getTokensForAmount(xftPool, intervalShort, intervalLong, linkFeed, amount, weth9)
  //     let tokensForAmountCeiling = await oracle.getTokensForAmountCeiling(xftPool, intervalShort, intervalLong, linkFeed, amount, weth9)
  //     let amountLeqCeiling = (BigInt(tokensForAmount) <= BigInt(tokensForAmountCeiling))

  //     // Test
  //     amountLeqCeiling.should.be.equal(true)
  //   })
 
  // })

  // describe('#getTokensForAmountSimpleShift', () => {
  //   // getTokensForAmountCeiling should always be higher than getTokensForAmount for all assets
  
  //   it('should be <= getTokensForAmount anonUSD', async () => {
  //     await token.mint(sender, BigInt(1e22)) // 10,000 anonUSD
  //     let xftPool = await shifter.tokenPool()
  //     let intervalShort = 180
  //     let intervalLong = 1800
  //     let linkFeed = tokenStyle.anonUSD.chainlink
  //     let amount = BigInt(1e18) // 1 anonUSD
  //     let tokensForAmount = await oracle.getTokensForAmount(xftPool, intervalShort, intervalLong, linkFeed, amount, weth9)
  //     let tokensForAmountSimpleShift = await oracle.getTokensForAmountSimpleShift(xftPool, intervalShort, intervalLong, linkFeed, amount, weth9)
  //     let amountLeq = (BigInt(tokensForAmount) >= BigInt(tokensForAmountSimpleShift))

  //     // Test
  //     amountLeq.should.be.equal(true)
  //   })
  // })

  // TODO
  // it('Should be able to call view functions with appropriate results', async function () 
  // {
  //   // TODO: test, validate results and document usage

  //   // ***** chainlinkPrice
  //   // get price from chainlink USD/ETH PRICEFEEDETHUSD
  //   let chainlinkInstance = await hre.ethers.getContractAt(artifacts.AggregatorV3, config.PRICEFEEDETHUSD);
  //   let latestRoundData = await chainlinkInstance.latestRoundData();
  //   let latestRoundPrice = Number(latestRoundData.answer);
  //   let decimals = Number(await chainlinkInstance.decimals());
  //   let price = latestRoundPrice / 10**decimals;
  //   let OracleValue = await oracle.chainlinkPrice(config.PRICEFEEDETHUSD);
  //   expect(latestRoundData.answer).to.equal(OracleValue);
    
  //   // price = price * 10**18;
  //   // console.log(price);

  //   // // ***** getV3SqrtPriceAvg
  //   // // TODO: test avg value by making price move?
  //   // let OracleValue2 = await oracle.getV3SqrtPriceAvg(NUMA_ETH_POOL_ADDRESS,config.INTERVAL_SHORT);
  //   // console.log(OracleValue2);

  //   // OracleValue2 = await oracle.getV3SqrtPriceAvg(NUMA_ETH_POOL_ADDRESS,config.INTERVAL_LONG);
  //   // console.log(OracleValue2);

  //   // let EThPriceInNuma = price *(2);
  //   // let sqrtPrice = Math.sqrt(Number(EThPriceInNuma));
  //   // // attention: token0/token1 might be switched
  //   // let price1 = BigInt(sqrtPrice*2**96);
  //   // let price2 = BigInt(2**96/sqrtPrice);

  //   // // TODO: difference, check where it comes from (see comments in getV3SqrtPriceAvg?)
  //   // if (numa_address < config.WETH_ADDRESS)
  //   // {
  //   //   expect(price1).to.equal(OracleValue2);
  //   // }
  //   // else
  //   // {
  //   //   expect(price2).to.equal(OracleValue2);
  //   // }
  //   // // ***** getV3SqrtPrice
  //   // let OracleValue3 = await oracle.getV3SqrtPrice(NUMA_ETH_POOL_ADDRESS,config.INTERVAL_SHORT,config.INTERVAL_LONG);
  //   // console.log(OracleValue3);
  //   // if (numa_address < config.WETH_ADDRESS)
  //   // {
  //   //   expect(price1).to.equal(OracleValue3);
  //   // }
  //   // else
  //   // {
  //   //   expect(price2).to.equal(OracleValue3);
  //   // }
  //   // // TODO: test that we get the lowest value (see offshift tests)

  //   // // ***** getV3SqrtPriceSimpleShift
  //   // let OracleValue4 = await oracle.getV3SqrtPriceSimpleShift(NUMA_ETH_POOL_ADDRESS,config.INTERVAL_SHORT,config.INTERVAL_LONG);
  //   // console.log(OracleValue4);
  //   // if (numa_address < config.WETH_ADDRESS)
  //   // {
  //   //   expect(price1).to.equal(OracleValue4);
  //   // }
  //   // else
  //   // {
  //   //   expect(price2).to.equal(OracleValue4);
  //   // }

  //   // ***** isTokenBelowThreshold
  //   // TODO: check different cases: make pool price change, set different flex fee values
  //   let isBelowThres = await oracle.isTokenBelowThreshold(config.FLEXFEETHRESHOLD,NUUSD_ETH_POOL_ADDRESS,config.INTERVAL_SHORT,config.INTERVAL_LONG,config.PRICEFEEDETHUSD,config.WETH_ADDRESS);
  //   console.log(isBelowThres);
  //   expect(isBelowThres).to.equal(false);
  //   // 
  //   // ***** getTokensForAmountCeiling
  //   let amountn = 1000;
  //   let amount = ethers.parseEther(amountn.toString());
  //   let OracleValue5 = await oracle.getTokensForAmountCeiling(testData.NUMA_ETH_POOL_ADDRESS,config.INTERVAL_SHORT,config.INTERVAL_LONG,config.PRICEFEEDETHUSD,amount, config.WETH_ADDRESS);
  //   console.log(OracleValue5);
  //   // 1 numa is 50 cts, so we should need to burn 2000 NUMA to get 1000 nuUsd
  //   expect(OracleValue5).to.equal(ethers.parseEther("2000"));
  //   // TODO: 14 cts of diff

  //   // ***** getTokensRaw
  //   let OracleValue6 = await oracle.getTokensRaw(testData.NUMA_ETH_POOL_ADDRESS, NUUSD_ETH_POOL_ADDRESS, config.INTERVAL_SHORT,config.INTERVAL_LONG, amount, config.WETH_ADDRESS);
  //   console.log(OracleValue6);// TODO: check values
  //   // ***** getTokensForAmountSimpleShift
  //   let OracleValue7 = await oracle.getTokensForAmountSimpleShift(testData.NUMA_ETH_POOL_ADDRESS, config.INTERVAL_SHORT,config.INTERVAL_LONG, config.PRICEFEEDETHUSD, amount, config.WETH_ADDRESS);
  //   console.log(OracleValue7);// TODO: check values


  //   // ***** getCost --> same as getTokensForAmountCeiling, test it?
  //   // ***** getCostSimpleShift --> test logic
  //   // ***** getTokensForAmount --> see offshift if used?, add it?, test it?
    

   
  // });

  // it('Should be able to set parameters', async function ()
  // {
  //   let intervalShort = 360;
  //   let intervalLong = 3600;
  //   let flexFeeThreshold = "995000000000000";
  //   await expect(oracle.setIntervalShort(intervalShort)).to.emit(oracle, "IntervalShort").withArgs(intervalShort);
  //   await expect(oracle.setIntervalLong(intervalLong)).to.emit(oracle, "IntervalLong").withArgs(intervalLong);
  //   await expect(oracle.setFlexFeeThreshold(flexFeeThreshold)).to.emit(oracle, "FlexFeeThreshold").withArgs(flexFeeThreshold);
  //   // check values
  //   expect(await oracle.intervalShort()).to.equal(intervalShort);
  //   expect(await oracle.intervalLong()).to.equal(intervalLong);
  //   expect(await oracle.flexFeeThreshold()).to.equal(flexFeeThreshold);

  // });


  // it('Others', async function () {
  //   // access control

  // });







});

