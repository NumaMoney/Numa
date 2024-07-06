const { deployPrinterTestFixtureSepo,configSepo } = require("../fixtures/NumaTestFixture.js");
const { time, loadFixture, } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { upgrades } = require("hardhat");

// ********************* Numa printer test using sepolia fork for chainlink *************************



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
  let testData;
  let numa_address;
  let NUMA_ETH_POOL_ADDRESS;


  before(async function () 
  {
    testData = await loadFixture(deployPrinterTestFixtureSepo);
  
    signer = testData.signer;
    signer2 = testData.signer2;
    signer3 = testData.signer3;
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
  });
  
  it('Should have right initialization parameters', async function () {
    expect(await moneyPrinter.numa()).to.equal(numa_address);
    expect(await moneyPrinter.nuAsset()).to.equal(NUUSD_ADDRESS);

    expect(await moneyPrinter.numaPool()).to.equal(NUMA_ETH_POOL_ADDRESS);
   

    let oracleContract = await moneyPrinter.oracle();
    expect(await oracleContract).to.equal(oracleAddress);
    expect(await moneyPrinter.chainlinkFeed()).to.equal(configSepo.PRICEFEEDETHUSD);

    expect(await moneyPrinter.printAssetFeeBps()).to.equal(500);
    expect(await moneyPrinter.burnAssetFeeBps()).to.equal(800);

  });



  it('Should be able to request amounts', async function () {
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


  it('Should be able to mint nuUSD with fee', async function () {
    // Minting nuUSD       
    let amount = ethers.parseEther('1000');
    let costs = await moneyPrinter.getNbOfNumaNeededWithFee(amount);

    await expect(moneyPrinter.connect(signer2).mintAssetFromNuma(amount, signer2.getAddress()))
    .to.be.reverted;// insufficient balance


    // transfer numa to signer
    await numa.connect(numaOwner).transfer(signer2.getAddress(), numaAmount);

    let balanceNumaBefore = await numa.balanceOf(signer2.getAddress());
    expect(balanceNumaBefore).to.equal(numaAmount);

    await expect(moneyPrinter.connect(signer2).mintAssetFromNuma(amount, signer2.getAddress()))
    .to.be.reverted;// insufficient allowance

    // signer has to approve Numa to be burnt
    let approvalAmount = ethers.parseEther(numaAmount.toString());
    await numa.connect(signer2).approve(MONEY_PRINTER_ADDRESS, approvalAmount);

    await expect(moneyPrinter.connect(signer2).mintAssetFromNuma(amount, signer2.getAddress()))
      .to.emit(moneyPrinter, "AssetMint").withArgs(await nuUSD.getAddress(), amount)
      .to.emit(moneyPrinter, "PrintFee").withArgs(costs[1]);

    balanceNuma = await numa.balanceOf(signer2.getAddress());
    let balanceNuUSD = await nuUSD.balanceOf(signer2.getAddress());

    expect(balanceNuma).to.equal(balanceNumaBefore - costs[0] - costs[1]);
    expect(balanceNuUSD).to.equal(amount);
  });

  it('Should be able to burn nuUSD with fee', async function () 
  {
    let amount = ethers.parseEther('1000');
    let approvalAmount = ethers.parseEther(amount.toString());
    let balanceNumaBefore = await numa.balanceOf(signer.getAddress());

    // burning nuUSD
    let numaToBeRedeemed = await moneyPrinter.getNbOfNumaFromAssetWithFee(amount);

    // testing insufficient balance with signer3
    await nuUSD.connect(signer3).approve(MONEY_PRINTER_ADDRESS, approvalAmount);
    await expect(moneyPrinter.connect(signer3).mintAssetFromNuma(amount, signer3.getAddress()))
    .to.be.reverted;// insufficient balance


    await expect(moneyPrinter.connect(signer2).burnAssetToNuma(amount, signer.getAddress()))
    .to.be.reverted;// insufficient allowance
    // signer has to approve nuUSD to be burnt
    
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
     [configSepo.WETH_ADDRESS, configSepo.INTERVAL_SHORT, configSepo.INTERVAL_LONG, signer.getAddress()]);
    await oracle2.waitForDeployment();
    let oracle2Address = await oracle2.getAddress();
    await expect(moneyPrinter.setOracle(oracle2)).to.emit(moneyPrinter, "SetOracle").withArgs(oracle2Address);
    //
    let addy1 = "0x0000000000000000000000000000000000000001";
    await expect(moneyPrinter.setNumaPool(addy1)).to.emit(moneyPrinter, "SetNumaPool").withArgs(addy1);
    // 
    let printFee = 300;
    await expect(moneyPrinter.setPrintAssetFeeBps(printFee)).to.emit(moneyPrinter, "PrintAssetFeeBps").withArgs(printFee);
    //
    let burnFee = 500;
    await expect(moneyPrinter.setBurnAssetFeeBps(burnFee)).to.emit(moneyPrinter, "BurnAssetFeeBps").withArgs(burnFee);
    //
    let addy3 = "0x0000000000000000000000000000000000000003";
    await expect(moneyPrinter.setChainlinkFeed(addy3,86400)).to.emit(moneyPrinter, "SetChainlinkFeed").withArgs(addy3);

    // check values
    expect(await moneyPrinter.numaPool()).to.equal(addy1);
    let oracleContract = await moneyPrinter.oracle();
    expect(await oracleContract).to.equal(oracle2Address);
    expect(await moneyPrinter.chainlinkFeed()).to.equal(addy3);
    expect(await moneyPrinter.printAssetFeeBps()).to.equal(printFee);
    expect(await moneyPrinter.burnAssetFeeBps()).to.equal(burnFee);

  });

  it('Should implement Pausable', async function () 
  {
    // pause
    await expect( moneyPrinter.connect(signer).pause()).to.not.be.reverted;
    
    // test mint
    let amount = ethers.parseEther('1000');
    await expect(moneyPrinter.mintAssetFromNuma(amount, signer2.getAddress()))
    .to.be.revertedWithCustomError(moneyPrinter,"EnforcedPause");
    // test burn
    await expect(moneyPrinter.connect(signer2).burnAssetToNuma(amount, signer2.getAddress()))
    .to.be.revertedWithCustomError(moneyPrinter,"EnforcedPause");

    // unpause
    await expect( moneyPrinter.connect(signer).unpause()).to.not.be.reverted;
    await expect(moneyPrinter.mintAssetFromNuma(amount, signer2.getAddress()));
  });

  it('Should implement Ownable', async function () 
  {
    let addy4 = "0x0000000000000000000000000000000000000004";
    expect(await moneyPrinter.owner()).to.equal(await signer.getAddress());  
    //
    await expect( moneyPrinter.connect(signer2).pause()).to.be.revertedWithCustomError(moneyPrinter,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());
     
    await expect( moneyPrinter.connect(signer2).unpause()).to.be.revertedWithCustomError(moneyPrinter,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( moneyPrinter.connect(signer2).setChainlinkFeed(addy4,86400)).to.be.revertedWithCustomError(moneyPrinter,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( moneyPrinter.connect(signer2).setOracle(addy4)).to.be.revertedWithCustomError(moneyPrinter,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( moneyPrinter.connect(signer2).setNumaPool(addy4)).to.be.revertedWithCustomError(moneyPrinter,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( moneyPrinter.connect(signer2).setPrintAssetFeeBps(0)).to.be.revertedWithCustomError(moneyPrinter,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( moneyPrinter.connect(signer2).setBurnAssetFeeBps(0)).to.be.revertedWithCustomError(moneyPrinter,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());
    //
    await moneyPrinter.connect(signer).transferOwnership(await signer2.getAddress());
    await moneyPrinter.connect(signer2).acceptOwnership();


    await expect( moneyPrinter.connect(signer2).setBurnAssetFeeBps(0)).to.not.be.reverted;


  });







});

