const { getPoolData, initPoolETH, addLiquidity, weth9, artifacts } = require("../scripts/Utils.js");
const { deployPrinterTestFixture,config } = require("./NumaPrinterTestFixture.js");
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

    const Oracle = await ethers.getContractFactory('NumaOracle');
    oracle =  await Oracle.attach(oracleAddress);

  });
  
  it('Should have right initialization parameters', async function () 
  {
    expect(await oracle.intervalShort()).to.equal(config.INTERVAL_SHORT);
    expect(await oracle.intervalLong()).to.equal(config.INTERVAL_LONG);
    expect(await oracle.flexFeeThreshold()).to.equal(config.FLEXFEETHRESHOLD);

  });



  it('Should be able to call view functions with appropriate results', async function () {
   
  });

  it('Should be able to set parameters', async function () {
    

  });


  it('Others', async function () {
    // access control

  });







});

