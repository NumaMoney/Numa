const { getPoolData, initPoolETH, addLiquidity, weth9, artifacts } = require("../scripts/Utils.js");
const { deployPrinterTestFixture,config } = require("./fixtures/NumaPrinterTestFixtureDeployNuma.js");
const { time, loadFixture, } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { upgrades } = require("hardhat");

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

 

  describe('#swap check anonUSD', () => {
    it('should work', async () => {
      // Using the same setup as anonETH for anonUSD
      let routerAddress = uniswap.SwapRouter
      let router = await SwapRouter.at(routerAddress)
      let anonUSDPool = await shifter.tokenPool()
      let xftPool = await shifter.xftPool()

      await token.mint(sender, BigInt(1e22))
      let tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96
      tokenIn = token.address
      tokenOut = weth9
      fee = "3000"
      recipient = sender
      deadline = Math.round((Date.now() / 1000 + 300)).toString() // Deadline five minutes from 'now'
      deadline+=1800 // Time advanced 30min in migration to allow for the long interval
      amountOut = BigInt(5e17).toString() // 0.5 ETH
      amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
      sqrtPriceLimitX96 = "0x0"
      input = await token.balanceOf(sender)
      await token.approve(routerAddress, amountInMaximum)
      const paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, input, sqrtPriceLimitX96]
      let amountCall = await router.exactOutputSingle.call(paramsCall, {from: sender})
      amountInMaximum = amountCall.toString()
      console.log(`Amount of anonUSD to swap for 0.5 WETH, in Wei: ${amountInMaximum}`)
      let threshold = tokenStyle.anonUSD.threshold
      let intervalShort = 180
      let intervalLong = 1800
      let chainlinkFeed = tokenStyle.anonUSD.chainlink
      let tokenBelowThreshold = await oracle.isTokenBelowThreshold.call(threshold, anonUSDPool, intervalShort, intervalLong, chainlinkFeed, weth9, {from: sender})
      let uniSqrtPrice = await oracle.getV3SqrtPrice.call(anonUSDPool, intervalShort, intervalLong, {from: sender})
      let uniPrice = BigInt(uniSqrtPrice.toString())*BigInt(uniSqrtPrice.toString())*BigInt(1e18)/BigInt(2**192)
      console.log(`Swap price of pool, in Wei: ${uniPrice.toString()}`)
      console.log(`Token below threshold before swap: ${tokenBelowThreshold}`)
      let tokensForAmount = await oracle.getTokensForAmount.call(anonUSDPool, intervalShort, intervalLong, chainlinkFeed, BigInt(1e18), weth9)
      tokensForAmount = tokensForAmount.toString()
      let xftForAmount = await oracle.getTokensForAmount.call(xftPool, intervalShort, intervalLong, chainlinkFeed, BigInt(1e18), weth9)
      xftForAmount = xftForAmount.toString()
      console.log(`Tokens for amount, XFT for 1 anonUSD, in Wei: ${xftForAmount}`)
      console.log(`Tokens for amount, ETH for 1 USD, in Wei: ${tokensForAmount}`)
      let params = [tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96]
      await router.exactOutputSingle.sendTransaction(params, {from: sender})
      let tokenBelowThresholdAfter = await oracle.isTokenBelowThreshold.call(threshold, anonUSDPool, intervalShort, intervalLong, chainlinkFeed, weth9, {from: sender})
      let uniSqrtPriceAfter = await oracle.getV3SqrtPrice.call(anonUSDPool, intervalShort, intervalLong, {from: sender})
      let uniPriceAfter = BigInt(uniSqrtPriceAfter.toString())*BigInt(uniSqrtPriceAfter.toString())*BigInt(1e18)/BigInt(2**192)
      console.log(`Swap price of pool after swap, in Wei: ${uniPriceAfter.toString()}`)
      console.log(`Token below threshold, after swap: ${tokenBelowThresholdAfter}`)
    })
  })

 

  // describe('#tokenBelowThreshold', () => {
  //   it('should change after swapping 5 anonETH for WETH', async () => {
  //     let routerAddress = uniswap.SwapRouter
  //     let router = await SwapRouter.at(routerAddress)
  //     let pool = await shifterETH.tokenPool()
  //     await tokenETH.mint(sender, BigInt(1e22))
  //     let tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96
  //     tokenIn = tokenETH.address
  //     tokenOut = weth9
  //     fee = "3000"
  //     recipient = sender
  //     deadline = Math.round((Date.now() / 1000 + 300)).toString() // Deadline five minutes from 'now'
  //     deadline+=1800 // Time advanced 30min in migration to allow for the long interval
  //     amountOut = BigInt(5e18).toString() // 5 ETH
  //     amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" //
  //     sqrtPriceLimitX96 = "0x0"
  //     input = await tokenETH.balanceOf(sender)
  //     await tokenETH.approve(routerAddress, amountInMaximum)
  //     const paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, input, sqrtPriceLimitX96]
  //     let amountCall = await router.exactOutputSingle.call(paramsCall, {from: sender})
  //     amountInMaximum = amountCall.toString()
  //     let threshold = tokenStyle.anonETH.threshold
  //     let intervalShort = 180
  //     let intervalLong = 1800
  //     let chainlinkFeed = tokenStyle.anonETH.chainlink
  //     let tokenBelowThresholdBefore = await oracle.isTokenBelowThreshold.call(
  //       threshold, pool, intervalShort, intervalLong, chainlinkFeed, weth9, {from: sender}
  //     )
  //     let uniSqrtPriceBefore = await oracle.getV3SqrtPrice.call(pool, intervalShort, intervalLong, {from: sender})
  //     let uniPriceBefore = BigInt(uniSqrtPriceBefore.toString())*BigInt(uniSqrtPriceBefore.toString())*BigInt(1e18)/BigInt(2**192)
  //     let priceBelowThresholdBefore = (uniPriceBefore < threshold)
  //     priceBelowThresholdBefore.should.be.equal(false)
  //     tokenBelowThresholdBefore.should.be.equal(priceBelowThresholdBefore)
  //     let params = [tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96]
  //     await router.exactOutputSingle.sendTransaction(params, {from: sender})
  //     let tokenBelowThresholdAfter = await oracle.isTokenBelowThreshold.call(
  //       threshold, pool, intervalShort, intervalLong, chainlinkFeed, weth9, {from: sender}
  //     )
  //     let uniSqrtPriceAfter = await oracle.getV3SqrtPrice.call(pool, intervalShort, intervalLong, {from: sender})
  //     let uniPriceAfter = BigInt(uniSqrtPriceAfter.toString())*BigInt(uniSqrtPriceAfter.toString())/BigInt(2**192)
  //     let priceBelowThresholdAfter = (uniPriceAfter < threshold)

  //     // Tests
  //     priceBelowThresholdAfter.should.be.equal(true)
  //     tokenBelowThresholdAfter.should.be.equal(priceBelowThresholdAfter)
  //   })
  // })

  // describe('#getCostSimpleShift anonETH', () => {
  //   it('should return getTokensForAmount when at or above threshold', async () => {
  //     let routerAddress = uniswap.SwapRouter
  //     let router = await SwapRouter.at(routerAddress)
  //     let pool = await shifterETH.tokenPool()
  //     let xftPool = await shifterETH.xftPool()
  //     let threshold = tokenStyle.anonETH.threshold
  //     let linkFeed = tokenStyle.anonETH.chainlink
  //     await tokenETH.mint(sender, BigInt(1e22)) // 10,000 anonETH
  //     await oracle.setIntervalShort.sendTransaction(180, {from: sender})
  //     await oracle.setIntervalLong.sendTransaction(1800, {from: sender})
  //     let tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96
  //     tokenIn = tokenETH.address
  //     tokenOut = weth9
  //     fee = "3000"
  //     recipient = sender
  //     deadline = Math.round((Date.now() / 1000 + 300)).toString() // Deadline five minutes from 'now'
  //     deadline += 1800 // Time advanced 30min in migration to allow for the long interval
  //     amountOut = BigInt(1e18).toString() // 1 ETH, enough to lower pool price, but to remain above threshold
  //     amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  //     sqrtPriceLimitX96 = "0x0"
  //     input = await tokenETH.balanceOf(sender)
  //     await tokenETH.approve(routerAddress, amountInMaximum)
  //     let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, input, sqrtPriceLimitX96]
  //     let amountCall = await router.exactOutputSingle.call(paramsCall, {from: sender})
  //     amountInMaximum = amountCall.toString()
  //     let intervalShort = 180
  //     let intervalLong = 1800
  //     let params = [tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96]
  //     await router.exactOutputSingle.sendTransaction(params, {from: sender})
  //     let amount = BigInt(1e18)
  //     let costSimpleShift = await oracle.getCostSimpleShift(amount, linkFeed, xftPool, pool)
  //     costSimpleShift = costSimpleShift.toString()
  //     let costRaw = (await oracle.getTokensRaw(xftPool, pool, intervalShort, intervalLong, amount, weth9)).toString()
  //     let costAmount = (await oracle.getTokensForAmountSimpleShift(xftPool, intervalShort, intervalLong, linkFeed, amount, weth9)).toString()
  //     let belowThreshold = await oracle.isTokenBelowThreshold(threshold, pool, intervalShort, intervalLong, linkFeed, weth9)
  //     let costRawLeqCostAmount = (BigInt(costRaw) <= BigInt(costAmount))

  //     // Tests
  //     belowThreshold.should.be.equal(false)
  //     costRawLeqCostAmount.should.be.equal(true)
  //     costSimpleShift.should.be.equal(costAmount)
  //   });
  //   it('should return getTokensRaw when below threshold', async () => {
  //     let routerAddress = uniswap.SwapRouter
  //     let router = await SwapRouter.at(routerAddress)
  //     let pool = await shifterETH.tokenPool()
  //     let xftPool = await shifterETH.xftPool()
  //     let threshold = tokenStyle.anonETH.threshold
  //     let linkFeed = tokenStyle.anonETH.chainlink
  //     await tokenETH.mint(sender, BigInt(1e22)) // 10,000 anonETH
  //     await oracle.setIntervalShort.sendTransaction(180, {from: sender})
  //     await oracle.setIntervalLong.sendTransaction(1800, {from: sender})
  //     let tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96
  //     tokenIn = tokenETH.address
  //     tokenOut = weth9
  //     fee = "3000"
  //     recipient = sender
  //     deadline = Math.round((Date.now() / 1000 + 300)).toString() // Deadline five minutes from 'now'
  //     deadline+=1800 // Time advanced 30min in migration to allow for the long interval
  //     amountOut = BigInt(5e18).toString() // 5 ETH, enough to put price below threshold
  //     amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  //     sqrtPriceLimitX96 = "0x0"
  //     input = await tokenETH.balanceOf(sender)
  //     await tokenETH.approve(routerAddress, amountInMaximum)
  //     let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, input, sqrtPriceLimitX96]
  //     let amountCall = await router.exactOutputSingle.call(paramsCall, {from: sender})
  //     amountInMaximum = amountCall.toString()
  //     let intervalShort = 180
  //     let intervalLong = 1800
  //     let params = [tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96]
  //     await router.exactOutputSingle.sendTransaction(params, {from: sender})
  //     let amount = BigInt(1e18)
  //     let costSimpleShift = await oracle.getCostSimpleShift(amount, linkFeed, xftPool, pool)
  //     let costRaw = await oracle.getTokensRaw(xftPool, pool, intervalShort, intervalLong, amount, weth9)
  //     let costAmount = await oracle.getTokensForAmount(xftPool, intervalShort, intervalLong, linkFeed, amount, weth9)
  //     let belowThreshold = await oracle.isTokenBelowThreshold(threshold, pool, intervalShort, intervalLong, linkFeed, weth9)
  //     let costRawLeqCostAmount_ = (BigInt(costRaw) <= BigInt(costAmount))

  //     // Tests
  //     belowThreshold.should.be.equal(true)
  //     costRawLeqCostAmount_.should.be.equal(true)
  //     costSimpleShift.toString().should.be.equal(costRaw.toString())
  //   });
  // })

  // describe('#getV3SqrtPrice', () => {
  //   it('should give Spot Price when Lowest', async () => {
  //     await tokenETH.mint(sender, BigInt(1e22)) // 10,000 anonETH
  //     let routerAddress = uniswap.SwapRouter
  //     let router = await SwapRouter.at(routerAddress)
  //     let pool = await shifterETH.tokenPool()
  //     let ETHPool = await UniV3Pool.at(pool)
  //     let cardinality = 10
  //     await ETHPool.increaseObservationCardinalityNext.sendTransaction(cardinality, {from: sender})
  //     let tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96
  //     tokenIn = tokenETH.address
  //     tokenOut = weth9
  //     fee = "3000"
  //     recipient = sender
  //     deadline = Math.round((Date.now() / 1000 + 300)).toString() // Deadline five minutes from 'now'
  //     deadline+=1800 // Time advanced 30min in migration to allow for the long interval
  //     advanceTimeAndBlock(1800)
  //     amountOut = BigInt(5e18).toString() // 5 ETH
  //     amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  //     sqrtPriceLimitX96 = "0x0"
  //     input = await tokenETH.balanceOf(sender)
  //     await tokenETH.approve(routerAddress, amountInMaximum)
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
  //     let getV3SqrtPrice = await oracle.getV3SqrtPrice.call(pool, intervalShort, intervalLong, {from: sender})
  //     let shortLeqLong, spotLeqShort
  //     const token0 = await ETHPool.token0()
  //     if (token0 === weth9){
  //       shortLeqLong = (getV3SqrtPriceShort >= getV3SqrtPriceLong)
  //       spotLeqShort = (sqrtPriceX96Spot >= getV3SqrtPriceShort)
  //     } else {
  //       shortLeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong)
  //       spotLeqShort = (sqrtPriceX96Spot <= getV3SqrtPriceShort)
  //     }

  //     // Tests
  //     shortLeqLong.should.be.equal(true)
  //     spotLeqShort.should.be.equal(true)
  //     getV3SqrtPrice.should.be.eq.BN(sqrtPriceX96Spot)
  //   })
  //   it('should give Short Interval Price when Lowest', async () => {
  //     await tokenETH.mint(sender, BigInt(1e22)) // 10,000 anonETH
  //     let routerAddress = uniswap.SwapRouter
  //     let router = await SwapRouter.at(routerAddress)
  //     let pool = await shifterETH.tokenPool()
  //     let ETHPool = await UniV3Pool.at(pool)
  //     let cardinality = 10
  //     await ETHPool.increaseObservationCardinalityNext.sendTransaction(cardinality, {from: sender})
  //     let tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96
  //     tokenIn = tokenETH.address
  //     tokenOut = weth9
  //     fee = "3000"
  //     recipient = sender
  //     deadline = Math.round((Date.now() / 1000 + 300)).toString() // Deadline five minutes from 'now'
  //     deadline += 3600 // add an hour
  //     amountOut = BigInt(5e18).toString() // 5 ETH
  //     amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  //     sqrtPriceLimitX96 = "0x0"
  //     input = await tokenETH.balanceOf(sender)
  //     await tokenETH.approve(routerAddress, amountInMaximum)
  //     let paramsCall = [tokenIn, tokenOut, fee, sender, deadline, amountOut, input, sqrtPriceLimitX96]
  //     let amountCall = await router.exactOutputSingle.call(paramsCall, {from: sender})
  //     amountInMaximum = amountCall.toString()
  //     let intervalShort = 180
  //     let intervalLong = 1800
  //     advanceTimeAndBlock(intervalLong - intervalShort)
  //     deadline += intervalLong*2
  //     let params = [tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96]
  //     // Swap anonETH -> WETH at (intervalLong - intervalShort) to make the short interval price lower than the long
  //     await router.exactOutputSingle.sendTransaction(params, {from: sender})
  //     advanceTimeAndBlock(intervalShort)
  //     // Swap tokenIn and tokenOut, WETH in anonETH out
  //     input = await weth.balanceOf(sender)
  //     await weth.approve.sendTransaction(routerAddress, amountInMaximum, {from: sender})
  //     paramsCall = [tokenOut, tokenIn, fee, sender, deadline, amountOut, input, sqrtPriceLimitX96]
  //     amountCall = await router.exactOutputSingle.call(paramsCall, {from: sender})
  //     amountInMaximum = amountCall.toString()
  //     params = [tokenOut, tokenIn, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96]
  //     // Swap WETH -> anonETH to make short interval price lower than spot price
  //     await router.exactOutputSingle.sendTransaction(params, {from: sender})
  //     let slot0ETH = await ETHPool.slot0()
  //     let sqrtPriceX96Spot = slot0ETH.sqrtPriceX96
  //     let getV3SqrtPriceShort = await oracle.getV3SqrtPriceAvg.call(pool, intervalShort, {from: sender})
  //     let getV3SqrtPriceLong = await oracle.getV3SqrtPriceAvg.call(pool, intervalLong, {from: sender})
  //     let getV3SqrtPrice = await oracle.getV3SqrtPrice.call(pool, intervalShort, intervalLong, {from: sender})
  //     let shortLeqLong, spotLeqShort
  //     const token0 = await ETHPool.token0()
  //     if (token0 === weth9){
  //       shortLeqLong = (getV3SqrtPriceShort >= getV3SqrtPriceLong)
  //       spotLeqShort = (sqrtPriceX96Spot >= getV3SqrtPriceShort)
  //     } else {
  //       shortLeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong)
  //       spotLeqShort = (sqrtPriceX96Spot <= getV3SqrtPriceShort)
  //     }

  //     // Tests
  //     shortLeqLong.should.be.equal(true)
  //     spotLeqShort.should.be.equal(false)
  //     getV3SqrtPrice.should.be.eq.BN(getV3SqrtPriceShort)
  //   })
  //   it('should give Long Interval Price when Lowest', async () => {
  //     await tokenETH.mint(sender, BigInt(1e22)) // 10,000 anonETH
  //     let routerAddress = uniswap.SwapRouter
  //     let router = await SwapRouter.at(routerAddress)
  //     let pool = await shifterETH.tokenPool()
  //     let ETHPool = await UniV3Pool.at(pool)
  //     let cardinality = 10
  //     await ETHPool.increaseObservationCardinalityNext.sendTransaction(cardinality, {from: sender})
  //     let tokenIn, tokenOut, fee, recipient, deadline, amountOut, amountInMaximum, sqrtPriceLimitX96
  //     tokenIn = tokenETH.address
  //     tokenOut = weth9
  //     fee = "3000"
  //     recipient = sender
  //     deadline = Math.round((Date.now() / 1000 + 300)).toString() // Deadline five minutes from 'now'
  //     deadline += 3600 // add an hour
  //     amountOut = BigInt(5e18).toString() // 5 ETH
  //     amountInMaximum = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
  //     sqrtPriceLimitX96 = "0x0"
  //     input = await tokenETH.balanceOf(sender)
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
  //     input = await weth.balanceOf(sender)
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
  //     let getV3SqrtPrice = await oracle.getV3SqrtPrice.call(pool, intervalShort, intervalLong, {from: sender})
  //     let shortLeqLong, spotLeqLong
  //     const token0 = await ETHPool.token0()
  //     if (token0 === weth9){
  //       shortLeqLong = (getV3SqrtPriceShort >= getV3SqrtPriceLong)
  //       spotLeqLong = (sqrtPriceX96Spot >= getV3SqrtPriceLong)
  //     } else {
  //       shortLeqLong = (getV3SqrtPriceShort <= getV3SqrtPriceLong)
  //       spotLeqLong = (sqrtPriceX96Spot <= getV3SqrtPriceLong)
  //     }

  //     // Tests
  //     shortLeqLong.should.be.equal(false)
  //     spotLeqLong.should.be.equal(false)
  //     getV3SqrtPrice.should.be.eq.BN(getV3SqrtPriceLong)
  //   })
  // })

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

