const { deployNumaNumaPoolnuAssetsPrinters,configArbi } = require("./fixtures/NumaTestFixture.js");
const { time, loadFixture, } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { upgrades } = require("hardhat");

// ********************* Numa printer test using arbitrum fork for chainlink *************************



describe('NUMA NUASSET PRINTER', function () {
  let signer, signer2;
  let numaOwner;
  let numa;
  let nuUSD;
  let NUUSD_ADDRESS;
  
  let moneyPrinter;
  let MONEY_PRINTER_ADDRESS;
  // uniswap
  let nonfungiblePositionManager;
  let wethContract;
  // oracle
  let oracleAddress;
  // amount to be transfered to signer
  let numaAmount;
  let testData;
  let numa_address;
  let NUMA_ETH_POOL_ADDRESS;


  before(async function () 
  {
    // Deploy numa, numa pool, nuAssets, printers
    testData = await loadFixture(deployNumaNumaPoolnuAssetsPrinters);
  
    signer = testData.signer;
    signer2 = testData.signer2;
    signer3 = testData.signer3;
    numaOwner = testData.numaOwner;
    numa = testData.numa;
    nuUSD = testData.nuUSD;
    NUUSD_ADDRESS = testData.NUUSD_ADDRESS;    
    moneyPrinter = testData.moneyPrinter;
    MONEY_PRINTER_ADDRESS = testData.MONEY_PRINTER_ADDRESS;
    nonfungiblePositionManager = testData.nonfungiblePositionManager;
    wethContract = testData.wethContract;
    oracleAddress = testData.oracleAddress;
    numaAmount = testData.numaAmount;
    numa_address = await numa.getAddress();
    NUMA_ETH_POOL_ADDRESS = testData.NUMA_ETH_POOL_ADDRESS;

    // deploy vault, vaultmanager



  });
  
  it('Printer price should stay in vault bounds', async function () {
    // Minting nuUSD
    // how many numa should be burnt to get 1000 dollars
    let amount = ethers.parseEther('1000');
    let costs = await moneyPrinter.getNbOfNumaNeededWithFee(amount);
    console.log(costs);

    // 1 Numa epsilon as Numa is 50 cts for our tests
    const epsilon = ethers.parseEther('1');//BigInt(1); 
    const epsilonFee = ethers.parseEther('0.01');//BigInt(1);

    // Now, compare the result with a tolerance (epsilon)
    const expectedValue =  ethers.parseEther('2000');
    expect(costs[0]).to.be.closeTo(expectedValue, epsilon);

    const expectedValueFee =  costs[0]*BigInt(500)/BigInt(10000);
    expect(costs[1]).to.be.closeTo(expectedValueFee, epsilonFee);

    // Burning nuUSD, how many numas would we get back
    let numaQuantity = await moneyPrinter.getNbOfNumaFromAssetWithFee(amount);
    console.log(numaQuantity);

    // 1 Numa epsilon as Numa is 50 cts for our tests
    const epsilon2 = ethers.parseEther('1');//BigInt(1); 
    const epsilon2Fee = ethers.parseEther('0.01');//BigInt(1);

    // Now, compare the result with a tolerance (epsilon)
    const expectedValue2 =  costs[0];
    expect(numaQuantity[0]).to.be.closeTo(expectedValue2, epsilon2);

    const expectedValueFee2 =  numaQuantity[0]*BigInt(800)/BigInt(10000);
    expect(numaQuantity[1]).to.be.closeTo(expectedValueFee2, epsilon2Fee);
  });

});

