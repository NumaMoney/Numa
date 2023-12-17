const { getPoolData, getPool, initPoolETH, addLiquidity, weth9, artifacts, swapOptions, buildTrade, SwapRouter, Token } = require("../scripts/Utils.js");
const { deployPrinterTestFixture, config } = require("./fixtures/NumaTestFixture.js");
const { time, loadFixture, takeSnapshot } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { upgrades } = require("hardhat");
// TODO: I should be able to get it from utils
const { Trade: V3Trade, Route: RouteV3 } = require('@uniswap/v3-sdk');
const { WETH_ADDRESS } = require("@uniswap/universal-router-sdk");

// ********************* Numa oracle test using sepolia fork for chainlink *************************


describe('NUMA VAULT', function () {
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
    testData = await loadFixture(deployPrinterTestFixture);

    signer = testData.signer;
    signer2 = testData.signer2;
    numaOwner = testData.numaOwner;
    numa = testData.numa;
    numaAmount = testData.numaAmount;

    numa_address = await numa.getAddress();
    NUMA_ETH_POOL_ADDRESS = testData.NUMA_ETH_POOL_ADDRESS;

    const Oracle = await ethers.getContractFactory('NumaOracle');
    oracle = await Oracle.attach(oracleAddress);
    cardinalityLaunch = testData.cardinality;
    
    // Deploy Numa Vault
    // TODO: move it in fixture if used by printer

    // add reth as supported token

    // send rEth and burn minted Numa (or just send)


    snapshot = await takeSnapshot();

  });

  it('Should have right initialization parameters', async function () 
  {

    // check numa price 

    // check supported input tokens

    // check fee values, fee addresses
  
    


  });
  



  describe('#buy/sell tests', () => {




    it('buy with rEth', async () => 
    {
      // check amount received, check balances of rETH, check fees
    });
    it('buy with wstEth', async () => 
    {
      // check amount received, check balances of rETH, check fees
    });

    it('sell with rEth', async () => 
    {
      // check amount received, check balances of rETH, check fees
    });
    it('sell with wstEth', async () => 
    {
      // check amount received, check balances of rETH, check fees
    });




  });


  it('Adding skipWallet', async function () {
  


  });

  it('Adding LST token', async function () {
  


  });




  it('Owner', async function () {
  


  });

  it('Pausable', async function () {
  


  });






});

