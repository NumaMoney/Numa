const { getPoolData, initPoolETH, addLiquidity, weth9, artifacts } = require("../../scripts/Utils.js");
const { deployPrinterTestFixture,config } = require("../fixtures/old/NumaPrinterTestFixture.js");
const { time, loadFixture, } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { upgrades } = require("hardhat");

// ********************* Numa printer test using sepolia fork for chainlink & numa/ETH univ3 pool *************************



describe('NUMA NUASSET PRINTER', function () {
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
  });
  
  it('Should have right initialization parameters', async function () {
    expect(await moneyPrinter.numa()).to.equal(config.NUMA_ADDRESS);
    expect(await moneyPrinter.nuAsset()).to.equal(NUUSD_ADDRESS);

    expect(await moneyPrinter.numaPool()).to.equal(config.UNIV3_NUMAETH_ADDRESS);
    expect(await moneyPrinter.tokenPool()).to.equal(NUUSD_ETH_POOL_ADDRESS);

    let oracleContract = await moneyPrinter.oracle();
    expect(await oracleContract).to.equal(oracleAddress);
    expect(await moneyPrinter.chainlinkFeed()).to.equal(config.PRICEFEEDETHUSD);

    expect(await moneyPrinter.printAssetFeeBps()).to.equal(500);
    expect(await moneyPrinter.burnAssetFeeBps()).to.equal(800);

  });



  it('Should be able to request amounts', async function () {
    // Minting nuUSD
    // how many numa should be burnt to get 1000 dollars
    let amount = ethers.parseEther('1000');
    let costs = await moneyPrinter.getCost(amount);

    // TODO: how to check the values
    // we can setup our price on our local NUMA/ETH pool
    // but for we will need to handle complex cases also (avg, lower tick, etc...)
    // we need to compute it manually and check results to be sure (cf oracle tests and oracle documentation)

    // Burning nuUSD, how many numas would we get back
    let numaQuantity = await moneyPrinter.getNumaFromAsset(amount);
  });


  it('Should be able to mint nuUSD with fee', async function () {
    // Minting nuUSD       
    let amount = ethers.parseEther('1000');
    let costs = await moneyPrinter.getCost(amount);

    // transfer numa to signer
    await numa.connect(numaOwner).transfer(signer.getAddress(), numaAmount);

    let balanceNuma = await numa.balanceOf(signer.getAddress());
    expect(balanceNuma).to.equal(numaAmount);

    // signer has to approve Numa to be burnt
    let approvalAmount = ethers.parseEther(numaAmount.toString());

    await numa.connect(signer).approve(MONEY_PRINTER_ADDRESS, approvalAmount);

    await expect(moneyPrinter.mintAssetFromNuma(amount, signer2.getAddress()))
      .to.emit(moneyPrinter, "AssetMint").withArgs(await nuUSD.getAddress(), amount)
      .to.emit(moneyPrinter, "PrintFee").withArgs(costs[1]);

    balanceNuma = await numa.balanceOf(signer.getAddress());
    let balanceNuUSD = await nuUSD.balanceOf(signer2.getAddress());

    expect(balanceNuma).to.equal(numaAmount - costs[0] - costs[1]);
    expect(balanceNuUSD).to.equal(amount);
  });

  it('Should be able to burn nuUSD with fee', async function () {
    let balanceNumaBefore = await numa.balanceOf(signer.getAddress());

    // burning nuUSD
    let amount = ethers.parseEther('1000');
    let numaToBeRedeemed = await moneyPrinter.getNumaFromAsset(amount);

    // signer has to approve nuUSD to be burnt
    let approvalAmount = ethers.parseEther(amount.toString());
    await nuUSD.connect(signer2).approve(MONEY_PRINTER_ADDRESS, approvalAmount);

    await expect(moneyPrinter.connect(signer2).burnAssetToNuma(amount, signer.getAddress()))
      .to.emit(moneyPrinter, "AssetBurn").withArgs(await nuUSD.getAddress(), amount)
      .to.emit(moneyPrinter, "BurntFee").withArgs(numaToBeRedeemed[1]);

    balanceNuma = await numa.balanceOf(signer.getAddress());
    let balanceNuUSD = await nuUSD.balanceOf(signer2.getAddress());

    expect(balanceNuma).to.equal(balanceNumaBefore + numaToBeRedeemed[0] - numaToBeRedeemed[1]);
    expect(balanceNuUSD).to.equal(0);
  });

  it('Should be able to change parameters', async function () {
    // check events
    const oracle2 = await ethers.deployContract("NumaOracle",
     [config.WETH_ADDRESS, config.INTERVAL_SHORT, config.INTERVAL_LONG, config.FLEXFEETHRESHOLD, signer.getAddress()]);
    await oracle2.waitForDeployment();
    let oracle2Address = await oracle2.getAddress();
    await expect(moneyPrinter.setOracle(oracle2)).to.emit(moneyPrinter, "SetOracle").withArgs(oracle2Address);
    //
    let addy1 = "0x0000000000000000000000000000000000000001";
    await expect(moneyPrinter.setNumaPool(addy1)).to.emit(moneyPrinter, "SetNumaPool").withArgs(addy1);
    // 
    let addy2 = "0x0000000000000000000000000000000000000002";
    await expect(moneyPrinter.setTokenPool(addy2)).to.emit(moneyPrinter, "SetTokenPool").withArgs(addy2);
    //
    let printFee = 300;
    await expect(moneyPrinter.setPrintAssetFeeBps(printFee)).to.emit(moneyPrinter, "PrintAssetFeeBps").withArgs(printFee);
    //
    let burnFee = 500;
    await expect(moneyPrinter.setBurnAssetFeeBps(burnFee)).to.emit(moneyPrinter, "BurnAssetFeeBps").withArgs(burnFee);
    //
    let addy3 = "0x0000000000000000000000000000000000000003";
    await expect(moneyPrinter.setChainlinkFeed(addy3)).to.emit(moneyPrinter, "SetChainlinkFeed").withArgs(addy3);

    // check values
    expect(await moneyPrinter.numaPool()).to.equal(addy1);
    expect(await moneyPrinter.tokenPool()).to.equal(addy2);
    let oracleContract = await moneyPrinter.oracle();
    expect(await oracleContract).to.equal(oracle2Address);
    expect(await moneyPrinter.chainlinkFeed()).to.equal(addy3);
    expect(await moneyPrinter.printAssetFeeBps()).to.equal(printFee);
    expect(await moneyPrinter.burnAssetFeeBps()).to.equal(burnFee);

  });

  it('Others', async function () {
    // TODO
    // access control
    // oracle values
    // pausable
    // insufficient balance
    // recipients
    // etc...

  });







});

