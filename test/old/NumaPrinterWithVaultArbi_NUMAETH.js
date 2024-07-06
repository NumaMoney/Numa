const { getPoolData, initPoolETH, initPool, addLiquidity, weth9, artifacts, linkLibraries } = require("../../scripts/Utils.js");
const { deployNumaNumaPoolnuAssetsPrinters, configArbi } = require("../fixtures/NumaTestFixtureNew.js");

const { time, loadFixture, } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { upgrades } = require("hardhat");

// ********************* Numa printer test using arbitrum fork for chainlink *************************
const epsilon = ethers.parseEther('0.00000000001');


describe('NUMA NUASSET PRINTER', function () {
  let signer, signer2;
  let numaOwner;
  let numa;
  let nuUSD;
  let nuBTC;
  let NUUSD_ADDRESS;
  let NUBTC_ADDRESS;
  let moneyPrinter;
  let MONEY_PRINTER_ADDRESS;
  // uniswap
  let nonfungiblePositionManager;
  let wethContract;
  let oracle;
  let oracleAddress;
  // amount to be transfered to signer
  let numaAmount;
  let testData;
  let numa_address;
  let NUMA_ETH_POOL_ADDRESS;
  let snapshotGlobal;
  let minterAddress;
  let VaultManager;
  let moneyPrinterMock;
  after(async function () {
    await snapshotGlobal.restore();
  });


  before(async function () 
  {
    // Deploy numa, numa pool, nuAssets, printers
    testData = await loadFixture(deployNumaNumaPoolnuAssetsPrinters);
    snapshotGlobal = testData.snapshotGlobal;
    signer = testData.signer;
    signer2 = testData.signer2;
    signer3 = testData.signer3;
    numaOwner = testData.numaOwner;
    numa = testData.numa;
    nuUSD = testData.nuUSD;
    nuBTC = testData.NUBTC;
    NUUSD_ADDRESS = testData.NUUSD_ADDRESS;    
    NUBTC_ADDRESS = testData.NUBTC_ADDRESS;
    moneyPrinter = testData.moneyPrinter;
    MONEY_PRINTER_ADDRESS = testData.MONEY_PRINTER_ADDRESS;
    nonfungiblePositionManager = testData.nonfungiblePositionManager;
    wethContract = testData.wethContract;
    oracleAddress = testData.oracleAddress;
    numaAmount = testData.numaAmount;
    numa_address = await numa.getAddress();
    NUMA_ETH_POOL_ADDRESS = testData.NUMA_ETH_POOL_ADDRESS;
    minterAddress = testData.MINTER_ADDRESS;
    VaultManager = testData.VM;
    // deploy vault, vaultmanager
    const Oracle = await ethers.getContractFactory('NumaOracle');
    oracle = await Oracle.attach(oracleAddress);


    // SCALING

    moneyPrinterMock = await ethers.deployContract("NumaPrinterMock",
    [numa_address, minterAddress, NUMA_ETH_POOL_ADDRESS, oracleAddress, await VaultManager.getAddress()]);
    await moneyPrinterMock.waitForDeployment();
  
    let printFee = 500;
    await moneyPrinterMock.setPrintAssetFeeBps(printFee);
    //
    let burnFee = 800;
    await moneyPrinterMock.setBurnAssetFeeBps(burnFee);
    // add moneyPrinter as a minter
    const Minter = await ethers.getContractFactory('NumaMinter');
    let theMinter = await Minter.attach(minterAddress);
    theMinter.addToMinters(await moneyPrinterMock.getAddress());

  });
  
  it('getNbOfNuAssetFromNuma', async function () 
  {

    let numaAmount = ethers.parseEther("10000");
    // price from oracle
    let amountNuAssetOut = await moneyPrinter.getNbOfNuAssetFromNuma(NUUSD_ADDRESS,numaAmount);
    console.log(amountNuAssetOut);
    let feesPc = await moneyPrinter.printAssetFeeBps();

    let fees = (feesPc * numaAmount)/BigInt(10000);


    let amountFromOracle = await oracle.getNbOfNuAsset(
      numaAmount - fees,
      NUUSD_ADDRESS,
      NUMA_ETH_POOL_ADDRESS
    );


    expect(amountFromOracle).to.be.closeTo(amountNuAssetOut[0], epsilon);
    expect(fees).to.be.closeTo(amountNuAssetOut[1], epsilon);
    
  });


  it('getNbOfNumaNeededAndFee', async function () 
  {

    let nuassetAmount = ethers.parseEther("10000");
    // price from oracle
    let amountNumaIn = await moneyPrinter.getNbOfNumaNeededAndFee(NUUSD_ADDRESS,nuassetAmount);
    console.log(amountNumaIn);

    let feesPc = await moneyPrinter.printAssetFeeBps();
   


    let amountFromOracle = await oracle.getNbOfNumaNeeded(
      nuassetAmount,
      NUUSD_ADDRESS,
      NUMA_ETH_POOL_ADDRESS
    );
    amountFromOracle = (BigInt(10000)*amountFromOracle)/(BigInt(10000) - feesPc);
    console.log(amountFromOracle);
     
    let fees = (feesPc * amountFromOracle)/BigInt(10000);

    expect(amountFromOracle).to.be.closeTo(amountNumaIn[0], epsilon);
    expect(fees).to.be.closeTo(amountNumaIn[1], epsilon);
    
  });




  it('getNbOfnuAssetNeededForNuma', async function () 
  {

    let numaAmount = ethers.parseEther("10000");
    // NO SCALING
    let amountNuAssetInView = await moneyPrinter.getNbOfnuAssetNeededForNumaView(NUUSD_ADDRESS,numaAmount);
    console.log(amountNuAssetInView);

    let feesPc = await moneyPrinter.burnAssetFeeBps();
  
    let numaAmountInflated = (BigInt(10000)*numaAmount)/(BigInt(10000) - feesPc);

    console.log(numaAmountInflated);
    let amountFromOracle = await oracle.getNbOfAssetneeded(
      numaAmountInflated,
      NUUSD_ADDRESS,
      NUMA_ETH_POOL_ADDRESS
    );
    console.log(amountFromOracle);
     
    let fees = (numaAmountInflated *feesPc)/BigInt(10000);

    expect(amountFromOracle).to.be.closeTo(amountNuAssetInView[0], epsilon);
    expect(fees).to.be.closeTo(amountNuAssetInView[1], epsilon);

    // SCALING
    let amountNuAssetInView2 = await moneyPrinterMock.getNbOfnuAssetNeededForNumaView(NUUSD_ADDRESS,numaAmount);
    console.log(amountNuAssetInView);
    console.log(amountNuAssetInView2);

    // the mock printer descales 0.25
    amountFromOracle2 = amountFromOracle * BigInt(4);

    expect(amountFromOracle2).to.be.closeTo(amountNuAssetInView2[0], epsilon);
    expect(fees).to.be.closeTo(amountNuAssetInView2[1], epsilon);
     
    
  });

  
  it('getNbOfNumaFromAssetWithFeeView', async function () 
  {

    let nuassetAmount = ethers.parseEther("10000");
    // price from oracle
    // NO SCALING
    let amountNuma = await moneyPrinter.getNbOfNumaFromAssetWithFeeView(NUUSD_ADDRESS,nuassetAmount);
   


    let feesPc = await moneyPrinter.burnAssetFeeBps();
    let fees = (BigInt(feesPc) * amountNuma[0])/BigInt(10000);


    let amountFromOracle = await oracle.getNbOfNumaFromAsset(
      nuassetAmount,
      NUUSD_ADDRESS,
      NUMA_ETH_POOL_ADDRESS
    );
    console.log(amountFromOracle);
     
    expect(amountFromOracle).to.be.closeTo(amountNuma[0], epsilon);
    expect(fees).to.be.closeTo(amountNuma[1], epsilon);
    
    
    // SCALING
    let amountNuma2 = await moneyPrinterMock.getNbOfNumaFromAssetWithFeeView(NUUSD_ADDRESS,nuassetAmount);
   


    let feesPc2 = await moneyPrinterMock.burnAssetFeeBps();
    let fees2 = (BigInt(feesPc2) * amountNuma2[0])/BigInt(10000);


    let amountFromOracle2 = amountFromOracle/BigInt(4);

     console.log(fees2);
     console.log(fees);
    expect(amountFromOracle2).to.be.closeTo(amountNuma2[0], epsilon);
    expect(fees2).to.be.closeTo(amountNuma2[1], epsilon);
    expect(fees2).to.be.closeTo(fees/BigInt(4), epsilon);

        
    
  });
  it('mintAssetOutputFromNuma', async function () 
  {
    let nuassetAmount = ethers.parseEther("100000");

    let numaCostAndFee = await moneyPrinter.getNbOfNumaNeededAndFee(NUUSD_ADDRESS,nuassetAmount);
    let maxAmountReached = numaCostAndFee[0] - BigInt(1);
    await numa.approve(MONEY_PRINTER_ADDRESS,BigInt(10)*numaCostAndFee[0]);
    await expect(moneyPrinter.mintAssetOutputFromNuma(NUUSD_ADDRESS,nuassetAmount,
      maxAmountReached,await signer2.getAddress())).to.be.reverted;

    let numaBalBefore = await numa.balanceOf(await signer.getAddress());
    let nuUSDBefore = await nuUSD.balanceOf(await signer2.getAddress());
    await moneyPrinter.mintAssetOutputFromNuma(NUUSD_ADDRESS,nuassetAmount,
      numaCostAndFee[0],await signer2.getAddress());

    let numaBalAfter = await numa.balanceOf(await signer.getAddress());
    let nuUSDAfter = await nuUSD.balanceOf(await signer2.getAddress());
    expect(numaBalBefore - numaBalAfter).to.equal(numaCostAndFee[0]);
    expect(nuUSDAfter - nuUSDBefore).to.equal(nuassetAmount);

    let globalCF0 = await VaultManager.getGlobalCF();
    //console.log(globalCF0);

    // mint again check that it goes down
    await moneyPrinter.mintAssetOutputFromNuma(NUUSD_ADDRESS,nuassetAmount,
      numaCostAndFee[0],await signer2.getAddress());
    let globalCF1 = await VaultManager.getGlobalCF();
    //console.log(globalCF1);
    expect(globalCF1).to.be.below(globalCF0);

    // check that when < warning, we block minting
    // change parameters so that warning_cf is reached
    await moneyPrinter.setScalingParameters(0,globalCF1 + BigInt(1),0,0,0,0,0);
    //console.log(await moneyPrinter.cf_warning());
    // then should revert
    await expect(moneyPrinter.mintAssetOutputFromNuma(NUUSD_ADDRESS,nuassetAmount,
      numaCostAndFee[0],await signer2.getAddress())).to.be.reverted;
    

  });


  it('mintAssetFromNumaInput', async function () 
  {
    let numaAmount = ethers.parseEther("100000");

    let assetAmountAndFee = await moneyPrinter.getNbOfNuAssetFromNuma(NUUSD_ADDRESS,numaAmount);


    let minAmountReached = assetAmountAndFee[0] + BigInt(1);
    await numa.approve(MONEY_PRINTER_ADDRESS,BigInt(10)*numaAmount);

    await expect(moneyPrinter.mintAssetFromNumaInput(NUUSD_ADDRESS,numaAmount,
      minAmountReached,await signer2.getAddress())).to.be.reverted;

    let numaBalBefore = await numa.balanceOf(await signer.getAddress());
    let nuUSDBefore = await nuUSD.balanceOf(await signer2.getAddress());
    await moneyPrinter.mintAssetFromNumaInput(NUUSD_ADDRESS,numaAmount,
      assetAmountAndFee[0],await signer2.getAddress());

    let numaBalAfter = await numa.balanceOf(await signer.getAddress());
    let nuUSDAfter = await nuUSD.balanceOf(await signer2.getAddress());
    expect(numaBalBefore - numaBalAfter).to.equal(numaAmount);
    expect(nuUSDAfter - nuUSDBefore).to.equal(assetAmountAndFee[0]);

    let globalCF0 = await VaultManager.getGlobalCF();
    
    // mint again check that it goes down
    await moneyPrinter.mintAssetFromNumaInput(NUUSD_ADDRESS,numaAmount,
      assetAmountAndFee[0],await signer2.getAddress());

    let globalCF1 = await VaultManager.getGlobalCF();
    //console.log(globalCF1);
    expect(globalCF1).to.be.below(globalCF0);

    // check that when < warning, we block minting
    // change parameters so that warning_cf is reached
    await moneyPrinter.setScalingParameters(0,globalCF1 + BigInt(1),0,0,0,0,0);
    //console.log(await moneyPrinter.cf_warning());
    // then should revert
    await expect(moneyPrinter.mintAssetFromNumaInput(NUUSD_ADDRESS,numaAmount,
      assetAmountAndFee[0],await signer2.getAddress())).to.be.reverted;
    

  });


  it('burnAssetInputToNuma', async function () 
  {
    let nuAssetAmount = ethers.parseEther("100000");

    // mint some
    await nuUSD.mint(await signer.getAddress(),BigInt(10)*nuAssetAmount);

  
    let numaAmountAndFee = await moneyPrinter.getNbOfNumaFromAssetWithFeeView(NUUSD_ADDRESS,nuAssetAmount);
    console.log(numaAmountAndFee);
    let minAmountReached = BigInt(numaAmountAndFee[0])  - BigInt(numaAmountAndFee[1]) + BigInt(1);
    await nuUSD.approve(MONEY_PRINTER_ADDRESS,BigInt(10)*nuAssetAmount);

    await expect(moneyPrinter.burnAssetInputToNuma(NUUSD_ADDRESS,nuAssetAmount,
      minAmountReached,await signer2.getAddress())).to.be.reverted;

    let numaBalBefore = await numa.balanceOf(await signer2.getAddress());
    let nuUSDBefore = await nuUSD.balanceOf(await signer.getAddress());

    await moneyPrinter.burnAssetInputToNuma(NUUSD_ADDRESS,nuAssetAmount,
      numaAmountAndFee[0] - numaAmountAndFee[1],await signer2.getAddress());

    let numaBalAfter = await numa.balanceOf(await signer2.getAddress());
    let nuUSDAfter = await nuUSD.balanceOf(await signer.getAddress());

    let numaReceived = numaBalAfter-numaBalBefore;
    expect(numaReceived).to.equal(numaAmountAndFee[0] - numaAmountAndFee[1]);
    expect(nuUSDBefore-nuUSDAfter).to.equal(nuAssetAmount);

    // SCALING
    numaAmountAndFee = await moneyPrinterMock.getNbOfNumaFromAssetWithFeeView(NUUSD_ADDRESS,nuAssetAmount);
    numaBalBefore = await numa.balanceOf(await signer2.getAddress());
    nuUSDBefore = await nuUSD.balanceOf(await signer.getAddress());

    await nuUSD.approve(await moneyPrinterMock.getAddress(),BigInt(10)*nuAssetAmount);
    await moneyPrinterMock.burnAssetInputToNuma(NUUSD_ADDRESS,nuAssetAmount,
      numaAmountAndFee[0] - numaAmountAndFee[1],await signer2.getAddress());

    numaBalAfter = await numa.balanceOf(await signer2.getAddress());
    nuUSDAfter = await nuUSD.balanceOf(await signer.getAddress());
    let numaReceived2 = numaBalAfter-numaBalBefore;
    expect(numaReceived2).to.equal(numaAmountAndFee[0] - numaAmountAndFee[1]);
    expect(nuUSDBefore-nuUSDAfter).to.equal(nuAssetAmount);
    expect(numaReceived2).to.equal(numaReceived/BigInt(4));


  });

  it('burnAssetToNumaOutput', async function () 
  {
    let numaAmount = ethers.parseEther("100000");

    // mint some
    let nuAssetAmount = await moneyPrinter.getNbOfnuAssetNeededForNumaView(NUUSD_ADDRESS,numaAmount);
    await nuUSD.mint(await signer.getAddress(),BigInt(10)*nuAssetAmount[0]);

    let maxAmountReached = BigInt(nuAssetAmount[0]) - BigInt(1);
    await nuUSD.approve(MONEY_PRINTER_ADDRESS,BigInt(10)*nuAssetAmount[0]);

    await expect(moneyPrinter.burnAssetToNumaOutput(NUUSD_ADDRESS,numaAmount,
      maxAmountReached,await signer2.getAddress())).to.be.reverted;

    let numaBalBefore = await numa.balanceOf(await signer2.getAddress());
    let nuUSDBefore = await nuUSD.balanceOf(await signer.getAddress());

    await moneyPrinter.burnAssetToNumaOutput(NUUSD_ADDRESS,numaAmount,
      nuAssetAmount[0],await signer2.getAddress());

    let numaBalAfter = await numa.balanceOf(await signer2.getAddress());
    let nuUSDAfter = await nuUSD.balanceOf(await signer.getAddress());

    let numaReceived = numaBalAfter-numaBalBefore;
    let usdspent = nuUSDBefore-nuUSDAfter;
    expect(numaReceived).to.equal(numaAmount);
    expect(usdspent).to.equal(nuAssetAmount[0]);

    // SCALING
    nuAssetAmount = await moneyPrinterMock.getNbOfnuAssetNeededForNumaView(NUUSD_ADDRESS,numaAmount);
    numaBalBefore = await numa.balanceOf(await signer2.getAddress());
    nuUSDBefore = await nuUSD.balanceOf(await signer.getAddress());

    await nuUSD.approve(await moneyPrinterMock.getAddress(),BigInt(10)*nuAssetAmount[0]);
    await moneyPrinterMock.burnAssetToNumaOutput(NUUSD_ADDRESS,numaAmount,
      nuAssetAmount[0],await signer2.getAddress());

    numaBalAfter = await numa.balanceOf(await signer2.getAddress());
    nuUSDAfter = await nuUSD.balanceOf(await signer.getAddress());
    let numaReceived2 = numaBalAfter-numaBalBefore;
    let usdspent2 = nuUSDBefore-nuUSDAfter;
    expect(numaReceived).to.equal(numaAmount);
    expect(nuUSDBefore-nuUSDAfter).to.equal(nuAssetAmount[0]);
    expect(usdspent2).to.equal(usdspent*BigInt(4));
    

  });

  it('swapExactInput/swapExactOutput', async function () 
  {
    // swapExactInput
    let amountUSDIn = ethers.parseEther("67000");
    await nuUSD.mint(await signer.getAddress(),amountUSDIn);
    let amountBTCOut = await moneyPrinter.getNbOfNuAssetFromNuAsset(NUUSD_ADDRESS,NUBTC_ADDRESS,amountUSDIn);
    console.log(amountBTCOut);

    let minAmountReached = amountBTCOut[0] + BigInt(1);
    await nuUSD.approve(MONEY_PRINTER_ADDRESS,BigInt(10)*amountUSDIn);

    await expect(moneyPrinter.swapExactInput(NUUSD_ADDRESS,NUBTC_ADDRESS,
      await signer2.getAddress(),amountUSDIn,minAmountReached)).to.be.reverted;

      
    let nuBTCBefore = await nuBTC.balanceOf(await signer2.getAddress());
    let nuUSDBefore = await nuUSD.balanceOf(await signer.getAddress());
    await moneyPrinter.swapExactInput(NUUSD_ADDRESS,NUBTC_ADDRESS,
        await signer2.getAddress(),amountUSDIn,amountBTCOut[0]);

    let nuBTCAfter = await nuBTC.balanceOf(await signer2.getAddress());
    let nuUSDAfter = await nuUSD.balanceOf(await signer.getAddress());

    expect(nuBTCAfter - nuBTCBefore).to.equal(amountBTCOut[0]);
    expect(nuUSDBefore-nuUSDAfter).to.equal(amountUSDIn);

    // SwapExactOutput
    let amountUSDOut = ethers.parseEther("67000");
   
    let amountBTCin = await moneyPrinter.getNbOfNuAssetNeededForNuAsset(NUBTC_ADDRESS,NUUSD_ADDRESS,amountUSDOut);
    console.log(amountBTCin);

    let maxAmountReached = amountBTCin[0] - BigInt(1);

    await nuBTC.mint(await signer.getAddress(),amountBTCin[0]);
    await nuBTC.approve(MONEY_PRINTER_ADDRESS,BigInt(10)*amountBTCin[0]);

    await expect(moneyPrinter.swapExactOutput(NUBTC_ADDRESS,NUUSD_ADDRESS,
      await signer2.getAddress(),amountUSDOut,maxAmountReached)).to.be.reverted;

      
    nuBTCBefore = await nuBTC.balanceOf(await signer.getAddress());
    nuUSDBefore = await nuUSD.balanceOf(await signer2.getAddress());
    await moneyPrinter.swapExactOutput(NUBTC_ADDRESS,NUUSD_ADDRESS,
      await signer2.getAddress(),amountUSDOut,amountBTCin[0]);

    nuBTCAfter = await nuBTC.balanceOf(await signer.getAddress());
    nuUSDAfter = await nuUSD.balanceOf(await signer2.getAddress());

    expect(nuBTCBefore - nuBTCAfter).to.equal(amountBTCin[0]);
    expect(nuUSDAfter-nuUSDBefore).to.equal(amountUSDOut);




  });

  it('synth scaling', async function () 
  {
    await moneyPrinter.setScalingParameters(15000,
      1700,
      20,
      10,
      600,
      600,
      500) ;


    let nuAMAddy = await VaultManager.getNuAssetManager();
    const AssetMgr = await ethers.getContractFactory('nuAssetManager');
    let nuAM = await AssetMgr.attach(nuAMAddy);   
    // chainlink price ETHUSD
    // console.log(configArbi.PRICEFEEDETHUSD);
    // console.log(artifacts.AggregatorV3);
    let chainlinkInstance = await ethers.getContractAt(artifacts.AggregatorV3, configArbi.PRICEFEEDETHUSD);
    let latestRoundData = await chainlinkInstance.latestRoundData();
    let latestRoundPrice = Number(latestRoundData.answer);
    let decimals = Number(await chainlinkInstance.decimals());
    let price = latestRoundPrice;// / 10 ** decimals;

    console.log('ETHUSD price ',price);

    // base scaling
    let synthScalingBase = await moneyPrinter.getSynthScaling();
    expect(synthScalingBase[0]).to.equal(1000);

    let globCF = await VaultManager.getGlobalCF();
    let totalbalanceEth = await VaultManager.getTotalBalanceEth();
    let totalSynthValue = await nuAM.getTotalSynthValueEth();

    console.log(globCF);
    console.log(ethers.formatEther(totalbalanceEth));
    console.log(ethers.formatEther(totalSynthValue));



    let mintUSDAmount = (totalbalanceEth * BigInt(price))/BigInt(10 ** Number(decimals));
    mintUSDAmount = mintUSDAmount / BigInt(14);
    //await nuUSD.mint(await signer.getAddress(),mintUSDAmount);
    let numaCostAndFee = await moneyPrinter.getNbOfNumaNeededAndFee(NUUSD_ADDRESS,mintUSDAmount);
    await numa.approve(MONEY_PRINTER_ADDRESS,numaCostAndFee[0]);
    await moneyPrinter.mintAssetOutputFromNuma(NUUSD_ADDRESS,mintUSDAmount,
      numaCostAndFee[0],await signer.getAddress());

    globCF = await VaultManager.getGlobalCF();
    totalbalanceEth = await VaultManager.getTotalBalanceEth();
    totalSynthValue = await nuAM.getTotalSynthValueEth();

    console.log(globCF);
    console.log(ethers.formatEther(totalbalanceEth));
    console.log(ethers.formatEther(totalSynthValue));


    // start debasing
    synthScalingBase = await moneyPrinter.getSynthScaling();
    console.log(synthScalingBase);
    expect(synthScalingBase[0]).to.equal(BigInt(1000));


    // continue debasing
    await time.increase(600*10);
    synthScalingBase = await moneyPrinter.getSynthScaling();
    console.log(synthScalingBase);
    expect(synthScalingBase[0]).to.equal(BigInt(1000) - BigInt(10)*await moneyPrinter.debaseValue());


    // reach minimum check that we don't debase anymore

    await time.increase(600*10);
    synthScalingBase = await moneyPrinter.getSynthScaling();
    console.log(synthScalingBase);
    expect(synthScalingBase[0]).to.equal(BigInt(1000) - BigInt(20)*await moneyPrinter.debaseValue());

    await time.increase(600*10);
    synthScalingBase = await moneyPrinter.getSynthScaling();
    console.log(synthScalingBase);
    expect(synthScalingBase[0]).to.equal(await moneyPrinter.minimumScale());


    // start rebasing
    let numaAmountAndFee = await moneyPrinter.getNbOfNumaFromAssetWithFeeView(NUUSD_ADDRESS,mintUSDAmount);
    await nuUSD.approve(MONEY_PRINTER_ADDRESS,BigInt(10)*mintUSDAmount);


    await moneyPrinter.burnAssetInputToNuma(NUUSD_ADDRESS,mintUSDAmount,
      numaAmountAndFee[0] - numaAmountAndFee[1],await signer.getAddress());

      // globCF = await VaultManager.getGlobalCF();
      // totalbalanceEth = await VaultManager.getTotalBalanceEth();
      // totalSynthValue = await nuAM.getTotalSynthValueEth();
  
      // console.log(globCF);
      // console.log(ethers.formatEther(totalbalanceEth));
      // console.log(ethers.formatEther(totalSynthValue));
  
    await time.increase(600*10);
    synthScalingBase = await moneyPrinter.getSynthScaling();
    console.log(synthScalingBase);
    expect(synthScalingBase[0]).to.equal(await moneyPrinter.minimumScale() + BigInt(10)*await moneyPrinter.rebaseValue());

    // continue rebasing
    await time.increase(600*10);
    synthScalingBase = await moneyPrinter.getSynthScaling();
    console.log(synthScalingBase);
    expect(synthScalingBase[0]).to.equal(await moneyPrinter.minimumScale() + BigInt(20)*await moneyPrinter.rebaseValue());

    // reach max rebase check that we don't rebase anymore
    await time.increase(600*50);
    synthScalingBase = await moneyPrinter.getSynthScaling();
    console.log(synthScalingBase);
    expect(synthScalingBase[0]).to.equal(BigInt(1000));

    // security debase
    // mint some
    // numaCostAndFee = await moneyPrinter.getNbOfNumaNeededAndFee(NUUSD_ADDRESS,mintUSDAmount);
    // await numa.approve(MONEY_PRINTER_ADDRESS,numaCostAndFee[0]);
    // await moneyPrinter.mintAssetOutputFromNuma(NUUSD_ADDRESS,mintUSDAmount,
    //   numaCostAndFee[0],await signer.getAddress());

    let mintUSDAmount2 = (totalbalanceEth * BigInt(price))/BigInt(10 ** Number(decimals));
    mintUSDAmount2 = BigInt(3)*mintUSDAmount2 / BigInt(2);
    //await nuUSD.mint(await signer.getAddress(),mintUSDAmount2);
    await numa.mint(await signer.getAddress(),mintUSDAmount2*BigInt(10));
    numaCostAndFee = await moneyPrinter.getNbOfNumaNeededAndFee(NUUSD_ADDRESS,mintUSDAmount2);
    await numa.approve(MONEY_PRINTER_ADDRESS,numaCostAndFee[0]);
    await moneyPrinter.mintAssetOutputFromNuma(NUUSD_ADDRESS,mintUSDAmount2,
      numaCostAndFee[0],await signer.getAddress());



    globCF = await VaultManager.getGlobalCF();
    totalbalanceEth = await VaultManager.getTotalBalanceEth();
    totalSynthValue = await nuAM.getTotalSynthValueEth();
  
    console.log(globCF);
    console.log(ethers.formatEther(totalbalanceEth));
    console.log(ethers.formatEther(totalSynthValue));

    synthScalingBase = await moneyPrinter.getSynthScaling();
    console.log(synthScalingBase);
    expect(synthScalingBase[0]).to.equal(BigInt(globCF));


  });


});

