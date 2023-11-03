const { getPoolData, initPoolETH, addLiquidity, weth9, artifacts } = require("../scripts/Utils.js");
const { deployPrinterTestFixture,config } = require("./fixtures/NumaPrinterTestFixtureDeployNuma.js");
const { time, loadFixture, } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { upgrades } = require("hardhat");

// ********************* Numa oracle test using sepolia fork for chainlink & numa/ETH univ3 pool *************************



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

  });
  
  it('Should have right initialization parameters', async function () 
  {
    expect(await oracle.intervalShort()).to.equal(config.INTERVAL_SHORT);
    expect(await oracle.intervalLong()).to.equal(config.INTERVAL_LONG);
    expect(await oracle.flexFeeThreshold()).to.equal(config.FLEXFEETHRESHOLD);

  });



  it('Should be able to call view functions with appropriate results', async function () 
  {
    // TODO: test, validate results and document usage

    // ***** chainlinkPrice
    // get price from chainlink USD/ETH PRICEFEEDETHUSD
    let chainlinkInstance = await hre.ethers.getContractAt(artifacts.AggregatorV3, config.PRICEFEEDETHUSD);
    let latestRoundData = await chainlinkInstance.latestRoundData();
    let latestRoundPrice = Number(latestRoundData.answer);
    let decimals = Number(await chainlinkInstance.decimals());
    let price = latestRoundPrice / 10**decimals;
    let OracleValue = await oracle.chainlinkPrice(config.PRICEFEEDETHUSD);
    expect(latestRoundData.answer).to.equal(OracleValue);
    
    // price = price * 10**18;
    // console.log(price);

    // // ***** getV3SqrtPriceAvg
    // // TODO: test avg value by making price move?
    // let OracleValue2 = await oracle.getV3SqrtPriceAvg(NUMA_ETH_POOL_ADDRESS,config.INTERVAL_SHORT);
    // console.log(OracleValue2);

    // OracleValue2 = await oracle.getV3SqrtPriceAvg(NUMA_ETH_POOL_ADDRESS,config.INTERVAL_LONG);
    // console.log(OracleValue2);

    // let EThPriceInNuma = price *(2);
    // let sqrtPrice = Math.sqrt(Number(EThPriceInNuma));
    // // attention: token0/token1 might be switched
    // let price1 = BigInt(sqrtPrice*2**96);
    // let price2 = BigInt(2**96/sqrtPrice);

    // // TODO: difference, check where it comes from (see comments in getV3SqrtPriceAvg?)
    // if (numa_address < config.WETH_ADDRESS)
    // {
    //   expect(price1).to.equal(OracleValue2);
    // }
    // else
    // {
    //   expect(price2).to.equal(OracleValue2);
    // }
    // // ***** getV3SqrtPrice
    // let OracleValue3 = await oracle.getV3SqrtPrice(NUMA_ETH_POOL_ADDRESS,config.INTERVAL_SHORT,config.INTERVAL_LONG);
    // console.log(OracleValue3);
    // if (numa_address < config.WETH_ADDRESS)
    // {
    //   expect(price1).to.equal(OracleValue3);
    // }
    // else
    // {
    //   expect(price2).to.equal(OracleValue3);
    // }
    // // TODO: test that we get the lowest value (see offshift tests)

    // // ***** getV3SqrtPriceSimpleShift
    // let OracleValue4 = await oracle.getV3SqrtPriceSimpleShift(NUMA_ETH_POOL_ADDRESS,config.INTERVAL_SHORT,config.INTERVAL_LONG);
    // console.log(OracleValue4);
    // if (numa_address < config.WETH_ADDRESS)
    // {
    //   expect(price1).to.equal(OracleValue4);
    // }
    // else
    // {
    //   expect(price2).to.equal(OracleValue4);
    // }

    // ***** isTokenBelowThreshold
    // TODO: check different cases: make pool price change, set different flex fee values
    let isBelowThres = await oracle.isTokenBelowThreshold(config.FLEXFEETHRESHOLD,NUUSD_ETH_POOL_ADDRESS,config.INTERVAL_SHORT,config.INTERVAL_LONG,config.PRICEFEEDETHUSD,config.WETH_ADDRESS);
    console.log(isBelowThres);
    expect(isBelowThres).to.equal(false);
    // 
    // ***** getTokensForAmountCeiling
    let amountn = 1000;
    let amount = ethers.parseEther(amountn.toString());
    let OracleValue5 = await oracle.getTokensForAmountCeiling(testData.NUMA_ETH_POOL_ADDRESS,config.INTERVAL_SHORT,config.INTERVAL_LONG,config.PRICEFEEDETHUSD,amount, config.WETH_ADDRESS);
    console.log(OracleValue5);
    // 1 numa is 50 cts, so we should need to burn 2000 NUMA to get 1000 nuUsd
    expect(OracleValue5).to.equal(ethers.parseEther("2000"));
    // TODO: 14 cts of diff

    // ***** getTokensRaw
    let OracleValue6 = await oracle.getTokensRaw(testData.NUMA_ETH_POOL_ADDRESS, NUUSD_ETH_POOL_ADDRESS, config.INTERVAL_SHORT,config.INTERVAL_LONG, amount, config.WETH_ADDRESS);
    console.log(OracleValue6);// TODO: check values
    // ***** getTokensForAmountSimpleShift
    let OracleValue7 = await oracle.getTokensForAmountSimpleShift(testData.NUMA_ETH_POOL_ADDRESS, config.INTERVAL_SHORT,config.INTERVAL_LONG, config.PRICEFEEDETHUSD, amount, config.WETH_ADDRESS);
    console.log(OracleValue7);// TODO: check values


    // ***** getCost --> same as getTokensForAmountCeiling, test it?
    // ***** getCostSimpleShift --> test logic
    // ***** getTokensForAmount --> see offshift if used?, add it?, test it?
    

   
  });

  it('Should be able to set parameters', async function ()
  {
    let intervalShort = 360;
    let intervalLong = 3600;
    let flexFeeThreshold = "995000000000000";
    await expect(oracle.setIntervalShort(intervalShort)).to.emit(oracle, "IntervalShort").withArgs(intervalShort);
    await expect(oracle.setIntervalLong(intervalLong)).to.emit(oracle, "IntervalLong").withArgs(intervalLong);
    await expect(oracle.setFlexFeeThreshold(flexFeeThreshold)).to.emit(oracle, "FlexFeeThreshold").withArgs(flexFeeThreshold);
    // check values
    expect(await oracle.intervalShort()).to.equal(intervalShort);
    expect(await oracle.intervalLong()).to.equal(intervalLong);
    expect(await oracle.flexFeeThreshold()).to.equal(flexFeeThreshold);

  });


  it('Others', async function () {
    // access control

  });







});

