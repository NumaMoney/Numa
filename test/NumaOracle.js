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
  afterEach(async function() {
    //console.log("reseting snapshot");
    await snapshot.restore();
    snapshot = await takeSnapshot();
  })

  beforeEach(async function() {
    //console.log("calling before each");
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
        
    // code that could be put in beforeEach but as we snapshot and restore, we
    // can put it here
    intervalShort = 180;
    intervalLong = 1800;
    amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
    tokenIn = NUUSD_ADDRESS;
    tokenOut = config.WETH_ADDRESS;
    fee = "500";// TODO: put it in config
    sqrtPriceLimitX96 = "0x0";

    // chainlink price ETHUSD
    let chainlinkInstance = await hre.ethers.getContractAt(artifacts.AggregatorV3, config.PRICEFEEDETHUSD);
    let latestRoundData = await chainlinkInstance.latestRoundData();
    let latestRoundPrice = Number(latestRoundData.answer);
    let decimals = Number(await chainlinkInstance.decimals());
    price = latestRoundPrice / 10**decimals;

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
      //console.log(logs);
     
      const {sqrtPriceX96, unlocked} = await pool.slot0();

      expect(sqrtPriceX96).to.not.equal(BigInt(0));
      expect(unlocked).to.equal(true);

    });
  });

 

 
  describe('#swap check nuUSD & tokenBelowThreshold', () => {
    it('should change after swapping nuUSD for 0.5 WETH', async () => {

      let deadline, amountOut;

      // recipient = sender
      let offset = 3600*10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300+offset)).toString(); // Deadline five minutes from 'now'
      deadline+=1800; // Time advanced 30min in migration to allow for the long interval
     
      // amount of ETH we want to get 
      amountOut = BigInt(5e17).toString(); // 0.5 ETH 
      input = await nuUSD.balanceOf(sender);


      let threshold = config.FLEXFEETHRESHOLD;


   
      let tokenBelowThreshold = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, config.WETH_ADDRESS);
      let uniSqrtPriceLow = await oracle.getV3SqrtLowestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let uniSqrtPriceHigh = await oracle.getV3SqrtHighestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);

      // uint256 numerator = (IUniswapV3Pool(_pool).token1() == _weth9 ? sqrtPriceX96 : FixedPoint96.Q96);
      // uint256 denominator = (numerator == sqrtPriceX96 ? FixedPoint96.Q96 : sqrtPriceX96);
      // //ETH per Token, times 1e18
      // uint256 ethPerToken = FullMath.mulDiv(FullMath.mulDiv(numerator, numerator, denominator), 1e18, denominator);

      let uniPriceLow = BigInt(uniSqrtPriceLow.toString())*BigInt(uniSqrtPriceLow.toString())*BigInt(1e18)/BigInt(2**192);     
      let uniPriceHigh = BigInt(uniSqrtPriceHigh.toString())*BigInt(uniSqrtPriceHigh.toString())*BigInt(1e18)/BigInt(2**192);


      // console.log(`Swap price low of pool before swap: ${hre.ethers.formatUnits(uniPriceLow,18)}`);
      // console.log(`Swap price high of pool before swap: ${hre.ethers.formatUnits(uniPriceHigh,18)}`);
      // console.log(`Token below threshold before swap: ${tokenBelowThreshold}`);


      if (NUUSD_ADDRESS > config.WETH_ADDRESS)
      {
        // change numerator/denominator
        uniPriceLow = Math.pow(10, 36)/Number(uniPriceLow);
        uniPriceHigh =Math.pow(10, 36)/Number(uniPriceHigh); 
      }
      else
      {
        // do nothing
      }
  


     
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

      // console.log('---------------------------- BEFORE');
      // console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      // console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      // console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));
      
      // 
      let uniPriceBefore = uniPriceLow;
      let ratio = (Number(uniPriceBefore)/(1.0/price));
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

      // console.log('---------------------------- AFTER');
      // console.log('ethBalance', hre.ethers.formatUnits(ethBalance, 18));
      // console.log('wethBalance', hre.ethers.formatUnits(wethBalance, 18));
      // console.log('usdcBalance', hre.ethers.formatUnits(nuusdcBalance, 18));



      let tokenBelowThresholdAfter = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, config.WETH_ADDRESS);

      uniSqrtPriceLow = await oracle.getV3SqrtLowestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      uniSqrtPriceHigh = await oracle.getV3SqrtHighestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);

      uniPriceLow = BigInt(uniSqrtPriceLow.toString())*BigInt(uniSqrtPriceLow.toString())*BigInt(1e18)/BigInt(2**192);     
      uniPriceHigh = BigInt(uniSqrtPriceHigh.toString())*BigInt(uniSqrtPriceHigh.toString())*BigInt(1e18)/BigInt(2**192);


      // console.log(`Swap price low of pool before swap: ${hre.ethers.formatUnits(uniPriceLow,18)}`);
      // console.log(`Swap price high of pool before swap: ${hre.ethers.formatUnits(uniPriceHigh,18)}`);
      // console.log(`Token below threshold before swap: ${tokenBelowThreshold}`);


      if (NUUSD_ADDRESS > config.WETH_ADDRESS)
      {
        // change numerator/denominator
        uniPriceLow = Math.pow(10, 36)/Number(uniPriceLow);
        uniPriceHigh =Math.pow(10, 36)/Number(uniPriceHigh); 
      }
      else
      {
        // do nothing
      }

      // 
      let uniPriceAfter = uniPriceLow;
      ratio = (Number(uniPriceAfter)/(1.0/price));
      let priceBelowThresholdAfter = (ratio < threshold);

      // Tests
      expect(priceBelowThresholdAfter).to.equal(true);
      expect(tokenBelowThresholdAfter).to.equal(priceBelowThresholdAfter);

    })
  })

 

  describe('#getCostSimpleShift nuUSD', () => {
    it('should return getTokensForAmount when at or above threshold', async () => {
     

      let deadline, amountOut;

      // recipient = sender
      let offset = 3600*10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300+offset)).toString(); // Deadline five minutes from 'now'
      deadline+=1800; // Time advanced 30min in migration to allow for the long interval
    

      // amount of ETH we want to get 
      amountOut = BigInt(12e16).toString(); // 0.12 ETH 
      input = await nuUSD.balanceOf(sender);
      let ethBalance;
      let wethBalance;
      let nuusdcBalance;



      let threshold = config.FLEXFEETHRESHOLD;


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


      let tokenBelowThresholdAfter = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, config.WETH_ADDRESS);



      let amount = BigInt(1e18);
      let costSimpleShift = await oracle.getNbOfNumaFromAsset(amount, config.PRICEFEEDETHUSD, NUMA_ETH_POOL_ADDRESS, NUUSD_ETH_POOL_ADDRESS);
      costSimpleShift = costSimpleShift.toString()

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

      let deadline, amountOut;

      // recipient = sender
      let offset = 3600*10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300+offset)).toString(); // Deadline five minutes from 'now'
      deadline+=1800; // Time advanced 30min in migration to allow for the long interval
    

      // amount of ETH we want to get 
      amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
      input = await nuUSD.balanceOf(sender);
      let ethBalance;
      let wethBalance;
      let nuusdcBalance;



      let threshold = config.FLEXFEETHRESHOLD;
  

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


      let tokenBelowThresholdAfter = await oracle.isTokenBelowThreshold(threshold, NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, config.WETH_ADDRESS);
     

      let amount = BigInt(1e18);
      let costSimpleShift = await oracle.getNbOfNumaFromAsset(amount, config.PRICEFEEDETHUSD, NUMA_ETH_POOL_ADDRESS, NUUSD_ETH_POOL_ADDRESS);
      costSimpleShift = costSimpleShift.toString()
     
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

       let deadline, amountOut;

       // recipient = sender
       let offset = 3600*10000000;// TODO 
       deadline = Math.round((Date.now() / 1000 + 300+offset)).toString(); // Deadline five minutes from 'now'
       deadline+=1800; // Time advanced 30min in migration to allow for the long interval
     
       // amount of ETH we want to get 
       amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
       input = await nuUSD.balanceOf(sender);
       let ethBalance;
       let wethBalance;
       let nuusdcBalance;
 
 
 
       let threshold = config.FLEXFEETHRESHOLD;

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
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString())*BigInt(getV3SqrtPriceShort.toString())*BigInt(1e18)/BigInt(2**192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString())*BigInt(getV3SqrtPriceLong.toString())*BigInt(1e18)/BigInt(2**192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString())*BigInt(sqrtPriceX96Spot.toString())*BigInt(1e18)/BigInt(2**192);
     
      if (NUUSD_ADDRESS > config.WETH_ADDRESS)
      {
        // change numerator/denominator
        uniPriceShort = Math.pow(10, 36)/Number(uniPriceShort);
        uniPriceLong =Math.pow(10, 36)/Number(uniPriceLong); 
        uniPriceSpot =Math.pow(10, 36)/Number(uniPriceSpot); 
      }
      else
      {
        // do nothing
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

          let deadline, amountOut;

          // recipient = sender
          let offset = 3600*10000000;// TODO 
          deadline = Math.round((Date.now() / 1000 + 300+offset)).toString(); // Deadline five minutes from 'now'
          deadline+=1800; // Time advanced 30min in migration to allow for the long interval
          
    
          // amount of ETH we want to get 
          amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
          input = await nuUSD.balanceOf(sender);
          let ethBalance;
          let wethBalance;
          let nuusdcBalance;
    
    
    
          let threshold = config.FLEXFEETHRESHOLD;

    
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
          paramsCall = [tokenOut,tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];         
          await swapRouter.connect(signer2).exactOutputSingle(paramsCall);
   
         let slot0ETH = await ETHPool.slot0();
         let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96;
   
         let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalShort);
         let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalLong);
         let getV3SqrtPrice = await oracle.getV3SqrtLowestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);
         let shortLeqLong, spotLeqShort
         const token0 = await ETHPool.token0();
         

   
         // Eth price for debug
         let uniPriceShort = BigInt(getV3SqrtPriceShort.toString())*BigInt(getV3SqrtPriceShort.toString())*BigInt(1e18)/BigInt(2**192);
         let uniPriceLong = BigInt(getV3SqrtPriceLong.toString())*BigInt(getV3SqrtPriceLong.toString())*BigInt(1e18)/BigInt(2**192);
         let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString())*BigInt(sqrtPriceX96Spot.toString())*BigInt(1e18)/BigInt(2**192);
        
         if (NUUSD_ADDRESS > config.WETH_ADDRESS)
         {
           // change numerator/denominator
           uniPriceShort = Math.pow(10, 36)/Number(uniPriceShort);
           uniPriceLong =Math.pow(10, 36)/Number(uniPriceLong); 
           uniPriceSpot =Math.pow(10, 36)/Number(uniPriceSpot); 
         }
         else
         {
           // do nothing
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

          let deadline, amountOut;

          // recipient = sender
          let offset = 3600*10000000;// TODO 
          deadline = Math.round((Date.now() / 1000 + 300+offset)).toString(); // Deadline five minutes from 'now'
          deadline+=1800; // Time advanced 30min in migration to allow for the long interval
       
    
          // amount of ETH we want to get 
          amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
          input = await nuUSD.balanceOf(sender);
          let ethBalance;
          let wethBalance;
          let nuusdcBalance;
    
    
    
          let threshold = config.FLEXFEETHRESHOLD;
      
    
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
         

         // Eth price for debug
         let uniPriceShort = BigInt(getV3SqrtPriceShort.toString())*BigInt(getV3SqrtPriceShort.toString())*BigInt(1e18)/BigInt(2**192);
         let uniPriceLong = BigInt(getV3SqrtPriceLong.toString())*BigInt(getV3SqrtPriceLong.toString())*BigInt(1e18)/BigInt(2**192);
         let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString())*BigInt(sqrtPriceX96Spot.toString())*BigInt(1e18)/BigInt(2**192);
        
         if (NUUSD_ADDRESS > config.WETH_ADDRESS)
         {
           // change numerator/denominator
           uniPriceShort = Math.pow(10, 36)/Number(uniPriceShort);
           uniPriceLong =Math.pow(10, 36)/Number(uniPriceLong); 
           uniPriceSpot =Math.pow(10, 36)/Number(uniPriceSpot); 
         }
         else
         {
           // do nothing
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

  describe('#getV3SqrtPriceSimpleShift', () => {
    it('should give Spot Price when Highest', async () => {

      let deadline, amountOut;

      // recipient = sender
      let offset = 3600*10000000;// TODO 
      deadline = Math.round((Date.now() / 1000 + 300+offset)).toString(); // Deadline five minutes from 'now'
      deadline+=1800; // Time advanced 30min in migration to allow for the long interval
  

      // amount of ETH we want to get 
      amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
      input = await nuUSD.balanceOf(sender);
      let ethBalance;
      let wethBalance;
      let nuusdcBalance;



      let threshold = config.FLEXFEETHRESHOLD;
 
  

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
      let paramsCall = [tokenOut,tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];         
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
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString())*BigInt(getV3SqrtPriceShort.toString())*BigInt(1e18)/BigInt(2**192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString())*BigInt(getV3SqrtPriceLong.toString())*BigInt(1e18)/BigInt(2**192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString())*BigInt(sqrtPriceX96Spot.toString())*BigInt(1e18)/BigInt(2**192);
     
      if (NUUSD_ADDRESS > config.WETH_ADDRESS)
      {
        // change numerator/denominator
        uniPriceShort = Math.pow(10, 36)/Number(uniPriceShort);
        uniPriceLong =Math.pow(10, 36)/Number(uniPriceLong); 
        uniPriceSpot =Math.pow(10, 36)/Number(uniPriceSpot); 
      }
      else
      {
        // do nothing
      }
  


      
      console.log(uniPriceLong);
      console.log(uniPriceShort);
      console.log(uniPriceSpot);

      if (token0 === config.WETH_ADDRESS)
      {
        shortGeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong);
        spotGeqShort = (sqrtPriceX96Spot <= getV3SqrtPriceShort);
      } 
      else 
      {
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
       let offset = 3600*10000000;// TODO 
       deadline = Math.round((Date.now() / 1000 + 300+offset)).toString(); // Deadline five minutes from 'now'
       deadline+=1800; // Time advanced 30min in migration to allow for the long interval
   
       // amount of ETH we want to get 
       amountOut = BigInt(5e17).toString(); //0.5 ETH --> below threshold
       input = await nuUSD.balanceOf(sender);
       let ethBalance;
       let wethBalance;
       let nuusdcBalance;
    
    
    
       let threshold = config.FLEXFEETHRESHOLD;
  
    
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
      let getV3SqrtPrice = await oracle.getV3SqrtHighestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let shortGeqLong, spotGeqShort
      const token0 = await ETHPool.token0();
     

   
      // Eth price for debug
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString())*BigInt(getV3SqrtPriceShort.toString())*BigInt(1e18)/BigInt(2**192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString())*BigInt(getV3SqrtPriceLong.toString())*BigInt(1e18)/BigInt(2**192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString())*BigInt(sqrtPriceX96Spot.toString())*BigInt(1e18)/BigInt(2**192);
        
      if (NUUSD_ADDRESS > config.WETH_ADDRESS)
      {
        // change numerator/denominator
        uniPriceShort = Math.pow(10, 36)/Number(uniPriceShort);
        uniPriceLong =Math.pow(10, 36)/Number(uniPriceLong); 
        uniPriceSpot =Math.pow(10, 36)/Number(uniPriceSpot); 
      }
      else
      {
        // do nothing
      }
  

   
     
      console.log(uniPriceLong);
      console.log(uniPriceShort);
      console.log(uniPriceSpot);

      if (token0 === config.WETH_ADDRESS)
      {
       shortGeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong)
       spotGeqShort = (sqrtPriceX96Spot <= getV3SqrtPriceShort)
      } 
      else 
      {
       shortGeqLong = (getV3SqrtPriceShort >= getV3SqrtPriceLong)
       spotGeqShort = (sqrtPriceX96Spot >= getV3SqrtPriceShort)
      }
   
      // Tests
      expect(shortGeqLong).to.equal(true);
      expect(spotGeqShort).to.equal(false);
      expect(getV3SqrtPrice).to.equal(getV3SqrtPriceShort);
     
     
    })
    it('should give Long Interval Price when Highest', async () => 
    {
    
       let deadline, amountOut;

       // recipient = sender
       let offset = 3600*10000000;// TODO 
       deadline = Math.round((Date.now() / 1000 + 300+offset)).toString(); // Deadline five minutes from 'now'
       deadline+=1800; // Time advanced 30min in migration to allow for the long interval

    
       // amount of ETH we want to get 
       amountOut = BigInt(500e18).toString(); //500 dollars
       input = await nuUSD.balanceOf(sender);
       let ethBalance;
       let wethBalance;
       let nuusdcBalance;
    
    
    
       let threshold = config.FLEXFEETHRESHOLD;

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
       let paramsCall = [tokenOut,tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];      
       await swapRouter.connect(signer2).exactOutputSingle(paramsCall);
    
       let ETHPool = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUUSD_ETH_POOL_ADDRESS);
   
       await time.increase(1800);
   
       // swap again the other way
       amountOut = BigInt(1e17).toString();// 0.1 ETH
       paramsCall = [tokenIn,tokenOut, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];         
       await swapRouter.connect(signer2).exactOutputSingle(paramsCall);
       await time.increase(180);
       // and swap again
       amountOut = BigInt(100e18).toString();// 100 dollars
       paramsCall = [tokenOut,tokenIn, fee, sender, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96];         
       await swapRouter.connect(signer2).exactOutputSingle(paramsCall);
      let slot0ETH = await ETHPool.slot0();
      let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96;
   
      let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalShort);
      let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg(NUUSD_ETH_POOL_ADDRESS, intervalLong);
      let getV3SqrtPrice = await oracle.getV3SqrtHighestPrice(NUUSD_ETH_POOL_ADDRESS, intervalShort, intervalLong);
      let shortGeqLong, spotGeqShort
      const token0 = await ETHPool.token0();
     

   
      // Eth price for debug
      let uniPriceShort = BigInt(getV3SqrtPriceShort.toString())*BigInt(getV3SqrtPriceShort.toString())*BigInt(1e18)/BigInt(2**192);
      let uniPriceLong = BigInt(getV3SqrtPriceLong.toString())*BigInt(getV3SqrtPriceLong.toString())*BigInt(1e18)/BigInt(2**192);
      let uniPriceSpot = BigInt(sqrtPriceX96Spot.toString())*BigInt(sqrtPriceX96Spot.toString())*BigInt(1e18)/BigInt(2**192);
        
      if (NUUSD_ADDRESS > config.WETH_ADDRESS)
      {
        // change numerator/denominator
        uniPriceShort = Math.pow(10, 36)/Number(uniPriceShort);
        uniPriceLong =Math.pow(10, 36)/Number(uniPriceLong); 
        uniPriceSpot =Math.pow(10, 36)/Number(uniPriceSpot); 
      }
      else
      {
        // do nothing
      }
  

   
     
      console.log(uniPriceLong);
      console.log(uniPriceShort);
      console.log(uniPriceSpot);

      if (token0 === config.WETH_ADDRESS)
      {
        shortGeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong)
        spotGeqLong = (sqrtPriceX96Spot <= getV3SqrtPriceLong)
      } 
      else 
      {
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
      let tokensForAmount = await oracle.getTokensForAmount(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, amount, config.WETH_ADDRESS);
      let tokensForAmountCeiling = await oracle.getTokensForAmountCeiling(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, amount, config.WETH_ADDRESS);
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
      let tokensForAmount = await oracle.getTokensForAmount(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, amount, config.WETH_ADDRESS);
      let tokensForAmountSimpleShift = await oracle.getNbOfNumaFromAssetUsingOracle(NUMA_ETH_POOL_ADDRESS, intervalShort, intervalLong, config.PRICEFEEDETHUSD, amount, config.WETH_ADDRESS);
      let amountLeq = (BigInt(tokensForAmount) >= BigInt(tokensForAmountSimpleShift));
      console.log(tokensForAmount);
      console.log(tokensForAmountSimpleShift);
      // Test
      expect(amountLeq).to.equal(true);
    
    })
  })

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

  it('Should be able to set parameters', async function ()
  {
    let intervalShortNew = 360;
    let intervalLongNew = 3600;
    let flexFeeThreshold = "995000000000000";
    await expect(oracle.setIntervalShort(intervalShortNew)).to.emit(oracle, "IntervalShort").withArgs(intervalShortNew);
    await expect(oracle.setIntervalLong(intervalLongNew)).to.emit(oracle, "IntervalLong").withArgs(intervalLongNew);
    await expect(oracle.setFlexFeeThreshold(flexFeeThreshold)).to.emit(oracle, "FlexFeeThreshold").withArgs(flexFeeThreshold);
    // check values
    expect(await oracle.intervalShort()).to.equal(intervalShortNew);
    expect(await oracle.intervalLong()).to.equal(intervalLongNew);
    expect(await oracle.flexFeeThreshold()).to.equal(flexFeeThreshold);

  });


  it('Should implement Ownable', async function () 
  {
    let intervalShortNew = 360;
    let intervalLongNew = 3600;
    let flexFeeThreshold = "995000000000000";
   
    expect(await oracle.owner()).to.equal(await signer.getAddress());  
    //
    await expect( oracle.connect(signer2).setIntervalShort(intervalShortNew)).to.be.revertedWithCustomError(oracle,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());
    await expect( oracle.connect(signer2).setIntervalLong(intervalLongNew)).to.be.revertedWithCustomError(oracle,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());
    await expect( oracle.connect(signer2).setFlexFeeThreshold(flexFeeThreshold)).to.be.revertedWithCustomError(oracle,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    //
    await oracle.connect(signer).transferOwnership(await signer2.getAddress());
    await expect( oracle.connect(signer2).setIntervalShort(intervalShortNew)).to.not.be.reverted;
  });







});

