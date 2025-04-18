


const { getPoolData, getPool, initPoolETH, addLiquidity, weth9, artifacts, swapOptions, buildTrade, SwapRouter, Token } = require("../scripts/Utils.js");
const { deployNumaNumaPoolnuAssetsPrinters, configArbi } = require("./fixtures/NumaTestFixtureNew.js");
const { time, loadFixture, takeSnapshot } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");

const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { upgrades, ethers } = require("hardhat");
const ERC20abi = [
  "function balanceOf(address owner) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function transfer(address to, uint amount) returns (bool)",
  "function approve(address spender, uint amount)",
  "event Transfer(address indexed from, address indexed to, uint amount)"
];

let rETH_ADDRESS = configArbi.RETH_ADDRESS;
let wstETH_ADDRESS = configArbi.WSTETH_ADDRESS;
let RETH_FEED = configArbi.RETH_FEED;
let wstETH_FEED = configArbi.WSTETH_FEED;
let ETH_FEED = configArbi.PRICEFEEDETHUSD;

let UPTIME_FEED = "0xFdB631F5EE196F0ed6FAa767959853A9F217697D";

const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
//const epsilon = ethers.parseEther('0.000000000000000001');
const epsilon = ethers.parseEther('0.000001');
const epsilon2 = ethers.parseEther('0.00001');
const epsilon3 = ethers.parseEther('0.00005');
const epsilon4 = ethers.parseEther('0.0001');
//let blocksPerYear = "2628000";// 12/sec to be confirmed
const blocksPerYear = "2102400";// eth values for test
let maxUtilizationRatePerYear = '1000000000000000000';//100%
let useVariableIRM = true;
 // DBGBADDEBT
 //useVariableIRM = false;

// ********************* Numa lending test using arbitrum fork for chainlink *************************
// TODO:

// - check interest rate in different situations
//https://docs.onyx.org/getting-started/protocol-math/calculating-the-apy-using-rate-per-block

// - test CFs with synthetics 

// - test borrow amount is up n% after x days



describe('NUMA LENDING', function () {
  let owner, userA,userB,userC;
  let numa;
  let testData;
  let numa_address;
  let snapshot;
  let snapshotGlobal;

  let Vault1;
  let VAULT1_ADDRESS;
  let defaultAdmin;
  let nuAM;
  let nuUSD;
  let nuBTC;
  let rEth_contract;
  let VO;
  let VO_ADDRESS;
  let VOcustomHeartbeat;
  let VO_ADDRESScustomHeartbeat;
  
  let VO2;
  let VO_ADDRESS2;
  let VM;
  let NUAM_ADDRESS;
  let VM_ADDRESS;
  let NUUSD_ADDRESS;
  let NUBTC_ADDRESS;
  
  // no more decay
  let decaydenom = 100;

  // lending
  let comptroller;
  let COMPTROLLER_ADDRESS;

  let numaPriceOracle;
  let NUMA_PRICEORACLE_ADDRESS;
  //let fakePriceOracle;
  let FAKE_PRICEORACLE_ADDRESS;

  let rateModel;
  let JUMPRATEMODELV2_ADDRESS;

  let cReth;
  let CRETH_ADDRESS;

  let cNuma;
  let CNUMA_ADDRESS;

  let rEthCollateralFactor = 0.6;
  let numaCollateralFactor = 0.8;

  let vaultInitialBalance = ethers.parseEther("100");
  let usersInitialBalance = ethers.parseEther("10");



   // ************** sends rETH to the vault and to users ******************
  let sendrEthAndNuma = async function () {
   
    // rETH arbitrum whale
    const address = "0x8Eb270e296023E9D92081fdF967dDd7878724424";
    await helpers.impersonateAccount(address);
    const impersonatedSigner = await ethers.getSigner(address);
    await helpers.setBalance(address, ethers.parseEther("10"));
    // transfer to signer, users so that it can buy numa
    await rEth_contract.connect(impersonatedSigner).transfer(defaultAdmin, usersInitialBalance);
    await rEth_contract.connect(impersonatedSigner).transfer(await userA.getAddress(),usersInitialBalance);
    await rEth_contract.connect(impersonatedSigner).transfer(await userB.getAddress(), usersInitialBalance);
    await rEth_contract.connect(impersonatedSigner).transfer(await userC.getAddress(), usersInitialBalance);
    // transfer to vault to initialize price
    await rEth_contract.connect(impersonatedSigner).transfer(VAULT1_ADDRESS, vaultInitialBalance);

    // numa transfer
    await numa.transfer(await userA.getAddress(),ethers.parseEther("1000000"));
    await numa.transfer(await userB.getAddress(),ethers.parseEther("1000000"));
    await numa.transfer(await userC.getAddress(),ethers.parseEther("1000000"));

    console.log("***************** send rEth and Numa ********************")


  };

  

  async function initContracts() 
  {
    snapshotGlobal = await takeSnapshot();
    testData = await loadFixture(deployNumaNumaPoolnuAssetsPrinters);

    owner = testData.signer;
    userA = testData.signer2;
    userB = testData.signer3;
    userC = testData.signer4;
    numa = testData.numa;
    numa_address = await numa.getAddress();


    // Deploy contracts

    // *********************** NUUSD TOKEN **********************************
    const NuUSD = await ethers.getContractFactory('nuAsset');
    defaultAdmin = await owner.getAddress();
    let minter = await owner.getAddress();
    let upgrader = await owner.getAddress();
    nuUSD = await upgrades.deployProxy(
      NuUSD,
      ["NuUSD", "NUSD",defaultAdmin,minter,upgrader],
      {
        initializer: 'initialize',
        kind:'uups'
      }
    );
    await nuUSD.waitForDeployment();
    NUUSD_ADDRESS = await nuUSD.getAddress();
    console.log('nuUSD address: ', NUUSD_ADDRESS);


    // *********************** NUBTC TOKEN **********************************
    const NuBTC = await ethers.getContractFactory('nuAsset');
    
    nuBTC = await upgrades.deployProxy(
      NuBTC,
      ["NuBTC", "NBTC",defaultAdmin,minter,upgrader],
      {
        initializer: 'initialize',
        kind:'uups'
      }
    );
    await nuBTC.waitForDeployment();
    NUBTC_ADDRESS = await nuBTC.getAddress();
    console.log('nuBTC address: ', NUBTC_ADDRESS);


    // *********************** nuAssetManager **********************************
    nuAM = await ethers.deployContract("nuAssetManager",
    [UPTIME_FEED]
    );
    await nuAM.waitForDeployment();
    NUAM_ADDRESS = await nuAM.getAddress();
    console.log('nuAssetManager address: ', NUAM_ADDRESS);

    // register nuAsset
    await nuAM.addNuAsset(NUUSD_ADDRESS,configArbi.PRICEFEEDETHUSD,16*86400);// 16 days for test
    await nuAM.addNuAsset(NUBTC_ADDRESS,configArbi.PRICEFEEDBTCETH,16*86400);// 16 days for test


    // *********************** vaultManager **********************************
    VM = await ethers.deployContract("VaultManager",
    [numa_address,NUAM_ADDRESS]);
    await VM.waitForDeployment();
    VM_ADDRESS = await VM.getAddress();
    console.log('vault manager address: ', VM_ADDRESS);

    // *********************** VaultOracle **********************************
    VO = await ethers.deployContract("VaultOracleSingle",
    [rETH_ADDRESS,RETH_FEED,16*86400,UPTIME_FEED]);
    await VO.waitForDeployment();
    VO_ADDRESS= await VO.getAddress();
    console.log('vault 1 oracle address: ', VO_ADDRESS);


    VOcustomHeartbeat = await ethers.deployContract("VaultOracleSingle",
    [rETH_ADDRESS,RETH_FEED,402*86400,UPTIME_FEED]);
    await VOcustomHeartbeat.waitForDeployment();
    VO_ADDRESScustomHeartbeat= await VOcustomHeartbeat.getAddress();
    console.log('vault 1 oracle heartbeat address: ', VO_ADDRESScustomHeartbeat);

    // *********************** minter contract **********************************
    let theMinter = await ethers.deployContract("NumaMinter", []);
    await theMinter.waitForDeployment();
    await numa.grantRole(roleMinter, await theMinter.getAddress());
    await theMinter.setTokenAddress(numa_address);
   

    // *********************** NumaVault rEth **********************************
    Vault1 = await ethers.deployContract("NumaVaultMock",
    [numa_address,rETH_ADDRESS,ethers.parseEther("1"),VO_ADDRESS,await theMinter.getAddress()]);
    await Vault1.waitForDeployment();
    VAULT1_ADDRESS = await Vault1.getAddress();
    console.log('vault rETH address: ', VAULT1_ADDRESS);

    // add vault as a minter
    theMinter.addToMinters(VAULT1_ADDRESS);

    await VM.addVault(VAULT1_ADDRESS);
    await Vault1.setVaultManager(VM_ADDRESS);

    // fee address
    await Vault1.setFeeAddress(await signer3.getAddress(),false);
   

    // vault has to be allowed to mint Numa
    //await numa.grantRole(roleMinter, VAULT1_ADDRESS);

    // get rEth contract 
    rEth_contract = await hre.ethers.getContractAt(ERC20abi, rETH_ADDRESS);
    
    await sendrEthAndNuma();
    await Vault1.setMaxBorrow(vaultInitialBalance);
    await Vault1.unpause();

    // *********************** Deploy lending **********************************
    // COMPTROLLER
    comptroller = await ethers.deployContract("NumaComptroller",
    []);
    await comptroller.waitForDeployment();
    COMPTROLLER_ADDRESS = await comptroller.getAddress();
    console.log('numa comptroller address: ', COMPTROLLER_ADDRESS);
   
    // PRICE ORACLE 
    numaPriceOracle = await ethers.deployContract("NumaPriceOracleNew",
    []);
    await numaPriceOracle.waitForDeployment();
    NUMA_PRICEORACLE_ADDRESS = await numaPriceOracle.getAddress();
    console.log('numa price oracle address: ', NUMA_PRICEORACLE_ADDRESS);
  
    await numaPriceOracle.setVault(VAULT1_ADDRESS);
    console.log('numaPriceOracle.setVault Done');
    await comptroller._setPriceOracle(await numaPriceOracle.getAddress());
    console.log('comptroller._setPriceOracle Done');

    // INTEREST RATE MODEL
    let maxUtilizationRatePerBlock = Math.floor(maxUtilizationRatePerYear/blocksPerYear);

    if (useVariableIRM)
    {
      let _vertexUtilization = '800000000000000000';// 80%
      // no interest rate by default, tested specifically
      //let _vertexRatePercentOfDelta = '500000000000000000';// 50%
      let _vertexRatePercentOfDelta = '000000000000000000';// 50%
      let _minUtil = '400000000000000000';// 40%
      let _maxUtil ='600000000000000000';// 60%
      // no interest rate by default, tested specifically
      //let _zeroUtilizationRate = '20000000000000000';//2%
      let _zeroUtilizationRate = '00000000000000000';//2%
      let _minFullUtilizationRate = '1000000000000000000';//100%
      let _maxFullUtilizationRate = '5000000000000000000';//500%
      // 
      // Interest Rate Half-Life: The time it takes for the interest to halve when Utilization is 0%.
      // This is the speed at which the interest rate adjusts.
      // In the currently available Rate Calculator, the Interest Rate Half-Life is 12 hours.

      let _rateHalfLife = 12*3600;
      // perblock
      let _zeroUtilizationRatePerBlock = Math.floor(_zeroUtilizationRate/blocksPerYear);
      let _minFullUtilizationRatePerBlock = Math.floor(_minFullUtilizationRate/blocksPerYear);
      let _maxFullUtilizationRatePerBlock = Math.floor(_maxFullUtilizationRate/blocksPerYear);


      rateModel = await ethers.deployContract("JumpRateModelVariable",
      ["numaRateModel",_vertexUtilization,_vertexRatePercentOfDelta,_minUtil,_maxUtil,
      _zeroUtilizationRatePerBlock,_minFullUtilizationRatePerBlock,_maxFullUtilizationRatePerBlock,
      _rateHalfLife,await owner.getAddress()]);


    }
    else
    {
      let baseRatePerYear = '20000000000000000';
      let multiplierPerYear = '180000000000000000';
      let jumpMultiplierPerYear = '4000000000000000000';
      let kink = '800000000000000000';
      rateModel = await ethers.deployContract("JumpRateModelV4",
      [blocksPerYear,baseRatePerYear,multiplierPerYear,jumpMultiplierPerYear,kink,await owner.getAddress(),"numaRateModel"]);
    }

    await rateModel.waitForDeployment();
    JUMPRATEMODELV2_ADDRESS = await rateModel.getAddress();
    console.log('rate model address: ', JUMPRATEMODELV2_ADDRESS);

    
    // CTOKENS
    cReth = await ethers.deployContract("CNumaLst",
    [rETH_ADDRESS,comptroller,rateModel,'200000000000000000000000000',
    'rEth CToken','crEth',8,maxUtilizationRatePerBlock,await owner.getAddress(),VAULT1_ADDRESS]);
    await cReth.waitForDeployment();
    CRETH_ADDRESS = await cReth.getAddress();
    console.log('crEth address: ', CRETH_ADDRESS);

    cNuma = await ethers.deployContract("CNumaToken",
    [numa_address,comptroller,rateModel,'200000000000000000000000000',
    'numa CToken','cNuma',8,maxUtilizationRatePerBlock,await owner.getAddress(),VAULT1_ADDRESS]);
    await cNuma.waitForDeployment();
    CNUMA_ADDRESS = await cNuma.getAddress();
    console.log('cNuma address: ', CNUMA_ADDRESS);

    
    await Vault1.setCTokens(CNUMA_ADDRESS,CRETH_ADDRESS);
    await Vault1.setMinLiquidationsPc(250);//25% min
    // add markets (has to be done before _setcollateralFactor)
    await comptroller._supportMarket(await cNuma.getAddress());
    await comptroller._supportMarket(await cReth.getAddress());

    console.log("setting collateral factor");

    // 80% for numa as collateral
    await comptroller._setCollateralFactor(await cNuma.getAddress(), ethers.parseEther(numaCollateralFactor.toString()).toString());
    // 60% for rEth as collateral
    await comptroller._setCollateralFactor(await cReth.getAddress(), ethers.parseEther(rEthCollateralFactor.toString()).toString());
    
    // 50% liquidation close factor
    console.log("set close factor");
    await comptroller._setCloseFactor(ethers.parseEther("0.5").toString());
  
    

    
  }

  async function supplyReth(
    account,
    rethsupplyamount
  ) 
  {
   
     await rEth_contract.connect(account).approve(await cReth.getAddress(),rethsupplyamount);
     await cReth.connect(account).mint(rethsupplyamount);
     // accept rEth as collateral
     await comptroller.connect(account).enterMarkets([cReth.getAddress()]);
  }

  async function supplyNuma(
    account,
    numasupplyamount
  ) 
  {
    await numa.connect(account).approve(await cNuma.getAddress(),numasupplyamount);
    await cNuma.connect(account).mint(numasupplyamount);
     // accept numa as collateral
     await comptroller.connect(account).enterMarkets([cNuma.getAddress()]);
  }


  async function getMaxBorrowNuma(rethsupplyamount)
  {
    // how many numas for 1 rEth
    let numaFromREth = await Vault1.getBuyNumaSimulateExtract(ethers.parseEther("1"));
    //console.log("how many numa with 1 rEth (wei)"+ numaFromREth);

    let numaBuyPriceInReth = (ethers.parseEther("1")*ethers.parseEther("1")) / numaFromREth;
    //console.log("numa buy price in rEth (wei)"+ numaBuyPriceInReth);
    // add 1 because we round up division 
    numaBuyPriceInReth = numaBuyPriceInReth +BigInt(1);
    //console.log("numa buy price in rEth (wei)"+ numaBuyPriceInReth);
    // max borrow
    let collateralValueInNumaWei =  (ethers.parseEther(rEthCollateralFactor.toString())*rethsupplyamount) / (numaBuyPriceInReth);
    // console.log(rethsupplyamount);
    // console.log(collateralValueInNumaWei);
    return collateralValueInNumaWei;
  }

  async function getMaxBorrowReth(numasupplyamount)
  {
    let sellPrice = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("1"));
    let collateralValueInrEthWei =  ((ethers.parseEther(numaCollateralFactor.toString())*numasupplyamount) * sellPrice)/(ethers.parseEther("1")*ethers.parseEther("1"));
    return collateralValueInrEthWei;
  }

  async function getNumaCollateralValue(numasupplyamount)
  {
    let sellPrice = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("1"));
    let collateralValueInrEthWei =  (numasupplyamount * sellPrice)/(ethers.parseEther("1"));
    return collateralValueInrEthWei;
  }

  async function getRethCollateralValue(rEthAmount)
  {
    return rEthAmount;
  }



  after(async function () {
    await snapshotGlobal.restore();
  });


  afterEach(async function () 
  {
    await snapshot.restore();
    snapshot = await takeSnapshot();
  })



  before(async function () 
  {
    await initContracts();  
    snapshot = await takeSnapshot();
  });

  describe('#Supply & Borrow', () => 
  {
      // getting prices should revert if vault is empty 
      it('Supply rEth, Borrow numa with vault prices', async () => 
      {  

        let rethsupplyamount = ethers.parseEther("2");
        let numasupplyamount = ethers.parseEther("500000");

        await supplyReth(userA,rethsupplyamount);
        await supplyNuma(userB,numasupplyamount);

        // check balance, total supply,
        let balcrEth = await cReth.balanceOf(await userA.getAddress());
        let totalSupply = await cReth.totalSupply();

        expect(totalSupply).to.equal(balcrEth);
        
        // ******************* userA borrow numa ************************
        let notTooMuchNuma = await getMaxBorrowNuma(rethsupplyamount);        
        let tooMuchNuma = notTooMuchNuma + epsilon;


        // should revert
        await expect(cNuma.connect(userA).borrow(tooMuchNuma)).to.be.reverted;
       
        // should not revert
        let numaBal = await numa.balanceOf(await userA.getAddress());
        await cNuma.connect(userA).borrow(notTooMuchNuma);
        let numaBalAfter = await numa.balanceOf(await userA.getAddress());

        expect(numaBalAfter - numaBal).to.equal(notTooMuchNuma);

      });




      it('Supply Numa, Borrow rEth from vault only', async () => 
      {
        
        let numaPriceBefore = await VM.numaToEth(ethers.parseEther("1"),0);

        
        let numasupplyamount = ethers.parseEther("200000");
        // userB supply numa      
        await supplyNuma(userB,numasupplyamount);


        // max borrow
        let collateralValueInrEthWei = await getMaxBorrowReth(numasupplyamount);

    
        // verify toomuch/nottoomuch (x2: collat and available from vault)
        let notTooMuchrEth = collateralValueInrEthWei;
        let tooMuchrEth = notTooMuchrEth+BigInt(1);
        
        await expect(cReth.connect(userB).borrow(tooMuchrEth)).to.be.reverted;
        await cReth.connect(userB).borrow(notTooMuchrEth);

      
        let balanceUserB = await rEth_contract.balanceOf(await userB.getAddress());
        expect(balanceUserB).to.equal(usersInitialBalance+notTooMuchrEth);

       
        let vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
       
        expect(vaultBalance).to.equal(vaultInitialBalance - notTooMuchrEth);
        let debt = await Vault1.getDebt();
        expect(debt).to.equal(notTooMuchrEth);

        let numaPriceAfter = await VM.numaToEth(ethers.parseEther("1"),0);

        // price
        expect(numaPriceAfter).to.equal(numaPriceBefore);


      });

      it('Supply Numa, Borrow rEth from lenders', async () => 
      {
        // supply reth
        let rethsupplyamount = ethers.parseEther("2");
        let numasupplyamount = ethers.parseEther("200000");

        await supplyReth(userA,rethsupplyamount);
        await supplyNuma(userB,numasupplyamount);

        let collateralValueInrEthWei = await getMaxBorrowReth(numasupplyamount);


        let balLending = await rEth_contract.balanceOf(await cReth.getAddress());
        expect(balLending).to.equal(rethsupplyamount);


        // verify toomuch/nottoomuch (x2: collat and available from vault)
        let notTooMuchrEth = collateralValueInrEthWei;
        let tooMuchrEth = notTooMuchrEth+BigInt(1);
        //
        await expect(cReth.connect(userB).borrow(tooMuchrEth)).to.be.reverted;
        await cReth.connect(userB).borrow(notTooMuchrEth);

        let balanceUserB = await rEth_contract.balanceOf(await userB.getAddress());
        expect(balanceUserB).to.equal(usersInitialBalance+notTooMuchrEth);
        let vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
       
        expect(vaultBalance).to.equal(vaultInitialBalance);

        let debt = await Vault1.getDebt();
        expect(debt).to.equal(BigInt(0));

  
        let balLendingAfter = await rEth_contract.balanceOf(await cReth.getAddress());
        expect(balLendingAfter).to.equal(balLending - notTooMuchrEth);

          
      });

      it('Supply Numa, Borrow rEth from vault and lenders', async () => 
      {
        let balanceUserBInitial = await rEth_contract.balanceOf(await userB.getAddress());
      
        // not enough lenders, we take from vault
        let rethsupplyamount = ethers.parseEther("1");   
        let numasupplyamount = ethers.parseEther("200000");
       
        await supplyReth(userA,rethsupplyamount);
        await supplyNuma(userB,numasupplyamount);

        let collateralValueInrEthWei = await getMaxBorrowReth(numasupplyamount);


        // compute how much should be borrowable from vault
        let maxBorrow = await Vault1.GetMaxBorrow();
        console.log("max rEth borrow from vault "+ethers.formatEther(maxBorrow));

        // verify toomuch/nottoomuch (x2: collat and available from vault)
        let notTooMuchrEth = collateralValueInrEthWei;
        let tooMuchrEth = notTooMuchrEth+BigInt(1);
        await expect(cReth.connect(userB).borrow(tooMuchrEth)).to.be.reverted;


        // BORROW
        await cReth.connect(userB).borrow(notTooMuchrEth);

        let balanceUserB = await rEth_contract.balanceOf(await userB.getAddress());

        
        expect(balanceUserB).to.equal(usersInitialBalance+notTooMuchrEth);
        let vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
        expect(vaultBalance).to.equal(vaultInitialBalance - notTooMuchrEth+rethsupplyamount);
        let debt = await Vault1.getDebt();
        expect(debt).to.equal(notTooMuchrEth - rethsupplyamount); 
        
        // we borrowed from vault so lending protocol should be empty
        let balLendingAfter = await rEth_contract.balanceOf(await cReth.getAddress());
        expect(balLendingAfter).to.equal(0);


      });

    });

    describe('#Repay', () => 
    {
        it('Borrow numa, repay numa', async () => 
        {

          let rethsupplyamount = ethers.parseEther("2");
          let numasupplyamount = ethers.parseEther("200000");

          await supplyReth(userA,rethsupplyamount);
          await supplyNuma(userB,numasupplyamount);


          // max borrow
          let collateralValueInNumaWei = await getMaxBorrowNuma(rethsupplyamount);
          let notTooMuchNuma = collateralValueInNumaWei;
  
          await expect(cNuma.connect(userA).borrow(notTooMuchNuma)).to.not.be.reverted;


          let [_, collateral, shortfall,badDebt] = await comptroller.getAccountLiquidityIsolate(
              await userA.getAddress(),cReth,cNuma
            );

          // getAccountLiquidityIsolate(address account,CToken collateral,CToken borrow)

          
          expect(shortfall).to.equal(0);  
          expect(collateral).to.be.closeTo(0,epsilon);
      
          let halfBorrow = notTooMuchNuma/BigInt(2);

          await numa.connect(userA).approve(await cNuma.getAddress(),halfBorrow);


          await cNuma.connect(userA).repayBorrow(halfBorrow);
          [_, collateral, shortfall] =await comptroller.getAccountLiquidityIsolate(
            await userA.getAddress(),cReth,cNuma
          );

         

          expect(shortfall).to.equal(0);  
          let collateralValueInrEthWei = (ethers.parseEther(rEthCollateralFactor.toString())*rethsupplyamount)/ethers.parseEther("1");

          let halfCollat = collateralValueInrEthWei/BigInt(2);
          expect(collateral).to.be.closeTo(halfCollat,epsilon);

        
        });


        it('Borrow rEth, repay rEth to lenders (no vault debt)', async () => 
        {
          // no vault debt --> repay lenders fully
          let rethsupplyamount = ethers.parseEther("2");
          let numasupplyamount = ethers.parseEther("200000");
          await supplyReth(userA,rethsupplyamount);
          await supplyNuma(userB,numasupplyamount);

          // max borrow
          let collateralValueInrEthWei =  await getMaxBorrowReth(numasupplyamount);
        

          // verify toomuch/nottoomuch (x2: collat and available from vault)
          let notTooMuchrEth = collateralValueInrEthWei;
    
          let lendingBalanceInitial = await rEth_contract.balanceOf(await CRETH_ADDRESS);

          await expect(cReth.connect(userB).borrow(notTooMuchrEth)).to.not.be.reverted;

          let lendingBalanceAfterBorrow = await rEth_contract.balanceOf(await CRETH_ADDRESS);
          expect(lendingBalanceAfterBorrow).to.equal(lendingBalanceInitial - notTooMuchrEth);  
          
          // repay
          let [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
            await userB.getAddress(),cNuma,cReth
          );
          
          expect(shortfall).to.equal(0);  
          expect(collateral).to.be.closeTo(0,epsilon);
      
          let halfBorrow = notTooMuchrEth/BigInt(2);
          await rEth_contract.connect(userB).approve(await cReth.getAddress(),halfBorrow);


          await cReth.connect(userB).repayBorrow(halfBorrow);
          [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
            await userB.getAddress(),cNuma,cReth
          );
          
          expect(shortfall).to.equal(0);  
          let halfCollat = collateralValueInrEthWei/BigInt(2);
          expect(collateral).to.be.closeTo(halfCollat,epsilon);
          let lendingBalanceAfterRepay = await rEth_contract.balanceOf(await CRETH_ADDRESS);
          expect(lendingBalanceAfterRepay).to.equal(lendingBalanceAfterBorrow + halfBorrow);  
        
        });

        it('Borrow rEth, repay rEth to lenders and vault', async () => 
        {
          let rethsupplyamount = ethers.parseEther("1");
          let numasupplyamount = ethers.parseEther("200000");
          await supplyReth(userA,rethsupplyamount);
          await supplyNuma(userB,numasupplyamount);

          // max borrow
          let collateralValueInrEthWei =  await getMaxBorrowReth(numasupplyamount);

          // verify toomuch/nottoomuch (x2: collat and available from vault)
          let notTooMuchrEth = collateralValueInrEthWei;
          console.log("borrowing "+notTooMuchrEth);
          let lendingBalanceInitial = await rEth_contract.balanceOf(await CRETH_ADDRESS);

          // we should borrow 1rEth from lenders and 1 rEth from vault
          await expect(cReth.connect(userB).borrow(notTooMuchrEth)).to.not.be.reverted;

          let lendingBalanceAfterBorrow = await rEth_contract.balanceOf(await CRETH_ADDRESS);
          // should be empty
          expect(lendingBalanceAfterBorrow).to.equal(0);  
          let borrowedFromVault = notTooMuchrEth - rethsupplyamount;

          let vaultBalanceAfterBorrow = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
          
          expect(vaultBalanceAfterBorrow).to.equal(vaultInitialBalance - borrowedFromVault);

          let debtAfterBorrow = await Vault1.getDebt();
          expect(debtAfterBorrow).to.equal(borrowedFromVault);


          let [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
            await userB.getAddress(),cNuma,cReth
          );
          
          expect(shortfall).to.equal(0);  
          expect(collateral).to.be.closeTo(0,epsilon);
      
          let halfBorrow = notTooMuchrEth/BigInt(2);
          await rEth_contract.connect(userB).approve(await cReth.getAddress(),halfBorrow);
          await cReth.connect(userB).repayBorrow(halfBorrow);

         
          // validate repay
          [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
            await userB.getAddress(),cNuma,cReth
          );
        
          expect(shortfall).to.equal(0);  
          let halfCollat = collateralValueInrEthWei/BigInt(2);
          expect(collateral).to.be.closeTo(halfCollat,epsilon);

         
          let [error,tokenbalance, borrowbalance, exchangerate] = await cReth.getAccountSnapshot(await userB.getAddress());
         
        
          let repaidTovault = halfBorrow;
          if (repaidTovault > debtAfterBorrow)
            repaidTovault = debtAfterBorrow;
          let repaidToLending = halfBorrow - repaidTovault;
       
          let lendingBalanceAfterRepay = await rEth_contract.balanceOf(await CRETH_ADDRESS);
          expect(lendingBalanceAfterRepay).to.equal(lendingBalanceAfterBorrow + repaidToLending);  

          // check vault
          let vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
        
          expect(vaultBalance).to.equal(vaultBalanceAfterBorrow + repaidTovault);
  
          let debt = await Vault1.getDebt();
          expect(debt).to.equal(debtAfterBorrow - repaidTovault);        

        
        });
        it('Borrow rEth, repay rEth to lenders', async () => 
        {
           
            let rethsupplyamount = ethers.parseEther("1");
            let numasupplyamount = ethers.parseEther("200000");

            await supplyReth(userA,rethsupplyamount);
            await supplyNuma(userB,numasupplyamount);
  
            // max borrow
            let collateralValueInrEthWei =  await getMaxBorrowReth(numasupplyamount);
  
            // verify toomuch/nottoomuch (x2: collat and available from vault)
            let notTooMuchrEth = collateralValueInrEthWei;
          
            let lendingBalanceInitial = await rEth_contract.balanceOf(await CRETH_ADDRESS);
  
            // we should borrow 1rEth from lenders and 1 rEth from vault
            await expect(cReth.connect(userB).borrow(notTooMuchrEth)).to.not.be.reverted;
  
            let lendingBalanceAfterBorrow = await rEth_contract.balanceOf(await CRETH_ADDRESS);
            // should be empty
            expect(lendingBalanceAfterBorrow).to.equal(0);  
  
            let vaultBalanceAfterBorrow = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
          
            expect(vaultBalanceAfterBorrow).to.equal(vaultInitialBalance +rethsupplyamount - notTooMuchrEth);
  
            let debtAfterBorrow = await Vault1.getDebt();
            expect(debtAfterBorrow).to.equal(notTooMuchrEth - rethsupplyamount);
  
  
            let [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
              await userB.getAddress(),cNuma,cReth
            );
            
            expect(shortfall).to.equal(0);  
            expect(collateral).to.be.closeTo(0,epsilon);
        
            let repayBorrow = notTooMuchrEth/BigInt(8);
            await rEth_contract.connect(userB).approve(await cReth.getAddress(),repayBorrow);
            await cReth.connect(userB).repayBorrow(repayBorrow);
  
            
            let repaidTovault = repayBorrow;
            if (repaidTovault > debtAfterBorrow)
              repaidTovault = debtAfterBorrow;
            let repaidToLending = repayBorrow - repaidTovault;
         
            let lendingBalanceAfterRepay = await rEth_contract.balanceOf(await CRETH_ADDRESS);
            expect(lendingBalanceAfterRepay).to.equal(lendingBalanceAfterBorrow + repaidToLending);  
  
            // check vault
            let vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
          
            expect(vaultBalance).to.equal(vaultBalanceAfterBorrow + repaidTovault);
    
            let debt = await Vault1.getDebt();
            expect(debt).to.equal(debtAfterBorrow - repaidTovault);        
   
        });

        it('Borrow rEth, repay rEth to lenders and vault x 2', async () => 
        {
            // supply reth
            let rethsupplyamount = ethers.parseEther("1");          
            let numasupplyamount = ethers.parseEther("200000");
            
            await supplyReth(userA,rethsupplyamount);
            await supplyNuma(userB,numasupplyamount);
  
            // max borrow
            let collateralValueInrEthWei =  await getMaxBorrowReth(numasupplyamount);
  
            // verify toomuch/nottoomuch (x2: collat and available from vault)
            let notTooMuchrEth = collateralValueInrEthWei;
           
            let lendingBalanceInitial = await rEth_contract.balanceOf(await CRETH_ADDRESS);
  
            // we should borrow 1rEth from lenders and 1 rEth from vault
            await expect(cReth.connect(userB).borrow(notTooMuchrEth)).to.not.be.reverted;
  
            let lendingBalanceAfterBorrow = await rEth_contract.balanceOf(await CRETH_ADDRESS);
            // should be empty
            expect(lendingBalanceAfterBorrow).to.equal(0);  
  
            let vaultBalanceAfterBorrow = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
          
            expect(vaultBalanceAfterBorrow).to.equal(vaultInitialBalance +rethsupplyamount - notTooMuchrEth);
  
            let debtAfterBorrow = await Vault1.getDebt();
            expect(debtAfterBorrow).to.equal(notTooMuchrEth - rethsupplyamount);
  
  
            let [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
              await userB.getAddress(),cNuma,cReth
            );
            
            expect(shortfall).to.equal(0);  
            expect(collateral).to.be.closeTo(0,epsilon);
        
            let halfBorrow = notTooMuchrEth/BigInt(2);
            await rEth_contract.connect(userB).approve(await cReth.getAddress(),halfBorrow);
            await cReth.connect(userB).repayBorrow(halfBorrow);
  
           
            // validate repay
            [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
              await userB.getAddress(),cNuma,cReth
            );
           
            expect(shortfall).to.equal(0);  
            let halfCollat = collateralValueInrEthWei/BigInt(2);
            expect(collateral).to.be.closeTo(halfCollat,epsilon);
  
            // if target UR = 80%
            let [error,tokenbalance, borrowbalance, exchangerate] = await cReth.getAccountSnapshot(await userB.getAddress());

            let repaidTovault = halfBorrow;
            if (repaidTovault > debtAfterBorrow)
              repaidTovault = debtAfterBorrow;
            let repaidToLending = halfBorrow - repaidTovault;
         
            let lendingBalanceAfterRepay = await rEth_contract.balanceOf(await CRETH_ADDRESS);
            expect(lendingBalanceAfterRepay).to.equal(lendingBalanceAfterBorrow + repaidToLending);  
  
            // check vault
            let vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
          
            expect(vaultBalance).to.equal(vaultBalanceAfterBorrow + repaidTovault);
    
            let debt = await Vault1.getDebt();
            expect(debt).to.equal(debtAfterBorrow - repaidTovault);   



            // repay again we should have 80/20 because already at 80%UR
            
            let repayBorrow = notTooMuchrEth/BigInt(4);
            await rEth_contract.connect(userB).approve(await cReth.getAddress(),repayBorrow);
            await cReth.connect(userB).repayBorrow(repayBorrow);
            // test again
            let debtAfterBorrow2 = debt;
            repaidTovault = repayBorrow;
            if (repaidTovault > debtAfterBorrow2)
              repaidTovault = debtAfterBorrow2;
            repaidToLending = repayBorrow - repaidTovault;
         
            let lendingBalanceAfterRepay2 = await rEth_contract.balanceOf(await CRETH_ADDRESS);
            expect(lendingBalanceAfterRepay2).to.equal(lendingBalanceAfterRepay + repaidToLending);  
  
            // check vault
            let vaultBalance2 = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
          
            expect(vaultBalance2).to.equal(vaultBalance + repaidTovault);
    
            let debt2 = await Vault1.getDebt();
            expect(debt2).to.equal(debtAfterBorrow2 - repaidTovault);   

        });
    });

    describe('#Redeem', () => 
    {   
        it('Supply&redeem numa', async () => 
        {
          let numaBalanceBefore = await numa.balanceOf(await userB.getAddress());
          let cnumaBalanceBefore = await cNuma.balanceOf(await userB.getAddress());
          let numasupplyamount = ethers.parseEther("200000");
          await supplyNuma(userB,numasupplyamount);



          let numaBalanceAfter = await numa.balanceOf(await userB.getAddress());
          let cnumaBalanceAfter = await cNuma.balanceOf(await userB.getAddress());



          expect(numaBalanceAfter).to.equal(numaBalanceBefore - numasupplyamount); 

          
          // TODO: add again
          expect(cNuma.connect(userB).redeemUnderlying(numasupplyamount + BigInt(1))).to.be.reverted;
          await cNuma.connect(userB).redeemUnderlying(numasupplyamount - BigInt(1));



          let numaBalanceAfterRedeem = await numa.balanceOf(await userB.getAddress());
          let cnumaBalanceAfterRedeem = await cNuma.balanceOf(await userB.getAddress());



          expect(cnumaBalanceAfterRedeem).to.be.closeTo(0,epsilon); 
          expect(numaBalanceAfterRedeem).to.be.closeTo(numaBalanceBefore,epsilon); 

        });

        it('Supply&redeem rEth', async () => 
        {
          let rethBalanceBefore = await rEth_contract.balanceOf(await userA.getAddress());
          let crethBalanceBefore = await cReth.balanceOf(await userA.getAddress());
          let rethSupplyAmount = ethers.parseEther("3");

          await supplyReth(userA,rethSupplyAmount);
          // test
          //await supplyReth(userB,ethers.parseEther("0.0001"));

          let rethBalanceAfter = await rEth_contract.balanceOf(await userA.getAddress());
          let crethBalanceAfter = await cReth.balanceOf(await userA.getAddress());
          let rethBalancecreth = await rEth_contract.balanceOf(CRETH_ADDRESS);

          expect(rethBalanceAfter).to.equal(rethBalanceBefore - rethSupplyAmount); 

          
          await expect(cReth.connect(userA).redeemUnderlying(rethSupplyAmount + BigInt(500000000))).to.be.reverted;
               
          await cReth.connect(userA).redeemUnderlying(rethSupplyAmount + BigInt(50000000));
    
         
          let rethBalanceAfterRedeem = await rEth_contract.balanceOf(await userA.getAddress());
          let crethBalanceAfterRedeem = await cReth.balanceOf(await userA.getAddress());

          expect(crethBalanceAfterRedeem).to.be.closeTo(0,epsilon); 
          expect(rethBalanceAfterRedeem).to.be.closeTo(rethBalanceBefore,epsilon); 

        });

        it('Supply&redeem rEth from vault', async () => 
        {
          let rethBalanceBefore = await rEth_contract.balanceOf(await userA.getAddress());
          
          let rethSupplyAmount = ethers.parseEther("9");
          let numasupplyamount = ethers.parseEther("200000");

          await supplyNuma(userB,numasupplyamount);
          await supplyReth(userA,rethSupplyAmount);

          let rethBalanceAfter = await rEth_contract.balanceOf(await userA.getAddress());
           

          expect(rethBalanceAfter).to.equal(rethBalanceBefore - rethSupplyAmount); 

            
          // max borrow
          let collateralValueInrEthWei = await getMaxBorrowReth(numasupplyamount);
  
          // compute how much should be borrowable from vault
          let maxBorrow = await Vault1.GetMaxBorrow();
          console.log("max rEth borrow from vault "+ethers.formatEther(maxBorrow));
  
          // verify toomuch/nottoomuch (x2: collat and available from vault)
          let borrowrEth = collateralValueInrEthWei;
  
          await cReth.connect(userB).borrow(borrowrEth);
          let rethBalancecreth = await rEth_contract.balanceOf(CRETH_ADDRESS);

          let vaultDebt = await Vault1.getDebt();
          expect(vaultDebt).to.equal(0); 
          
          let rethBalanceBeforeRedeem = await rEth_contract.balanceOf(await userA.getAddress());
          await cReth.connect(userA).redeemUnderlying(rethSupplyAmount);// + BigInt(50000000));
    
         
          let rethBalanceAfterRedeem = await rEth_contract.balanceOf(await userA.getAddress());
          expect(rethBalanceAfterRedeem - rethBalanceBeforeRedeem).to.be.closeTo(rethSupplyAmount,epsilon);

          let crethBalanceAfterRedeem = await cReth.balanceOf(await userA.getAddress());

          expect(crethBalanceAfterRedeem).to.be.closeTo(0,epsilon); 
          //expect(rethBalanceAfterRedeem).to.be.closeTo(rethBalanceBefore,epsilon); 

          //expect(rethBalanceAfterRedeem).to.equal(rethBalanceBefore); 
          vaultDebt = await Vault1.getDebt();
          expect(vaultDebt).to.equal((rethBalanceAfterRedeem - rethBalanceBeforeRedeem) - rethBalancecreth); 

        });

    });

    describe('#Vault collateral factor', () => 
    {
      it('Check available amount', async () => 
      {
        // compute how much should be borrowable from vault
        let maxBorrow = await Vault1.GetMaxBorrow();
        expect(maxBorrow).to.equal(vaultInitialBalance); 
      });

      it('Mint synth, change cf_liquid_warning', async () => 
      {
        
        let nuUSDamount = ethers.parseEther("50000");
        await nuUSD.connect(owner).mint(defaultAdmin,nuUSDamount);

        let synthValueEth = await nuAM.getTotalSynthValueEth();
        console.log("synth value eth: "+synthValueEth);

        let vaultvalueEth = await Vault1.getEthBalance();

        console.log("vault value eth: "+vaultvalueEth);


        let vaultCF = Number(vaultvalueEth) / Number(synthValueEth);

        console.log("vault CF: "+vaultCF);

        let maxBorrow = await Vault1.GetMaxBorrow();
        let maxcf = await Vault1.cf_liquid_warning();
        expect(maxcf).to.equal(2000); 
        let estimateMaxBorrowEth = vaultvalueEth - (maxcf * synthValueEth)/BigInt(1000);
        console.log("estimateMaxBorrowEth: "+estimateMaxBorrowEth);

        let rethPrice = await Vault1.last_lsttokenvalueWei();
        let estimateMaxBorrowrEth = (estimateMaxBorrowEth * ethers.parseEther("1"))/rethPrice;

        console.log("estimateMaxBorrow rEth: "+estimateMaxBorrowrEth);

        expect(maxBorrow).to.equal(estimateMaxBorrowrEth); 

        await Vault1.setCFLiquidWarning(4000);
        maxBorrow = await Vault1.GetMaxBorrow();

        let maxcfnew = await Vault1.cf_liquid_warning();

        expect(maxcfnew).to.equal(4000); 

        estimateMaxBorrowEth = vaultvalueEth - (maxcfnew * synthValueEth)/BigInt(1000);
        if (estimateMaxBorrowEth < 0)
          estimateMaxBorrowEth = BigInt(0);
        console.log("estimateMaxBorrowEth: "+estimateMaxBorrowEth);

        rethPrice = await Vault1.last_lsttokenvalueWei();
        estimateMaxBorrowrEth = (estimateMaxBorrowEth * ethers.parseEther("1"))/rethPrice;

        console.log("estimateMaxBorrow rEth: "+estimateMaxBorrowrEth);

        expect(maxBorrow).to.equal(estimateMaxBorrowrEth); 




      });

      it('Check that borrow from vault is limited', async () => 
      {
      });




    });


    
    describe('#Interest rates', () => 
    {
      it('IR supply&borrow numa borrowers', async () => 
      {
      });

      it('IR supply&borrow lst borrowers no lenders vault < CF', async () => 
      {
        let baseRatePerYear = ethers.parseEther('0');
        
        let multiplierPerYear = ethers.parseEther('0.02');
        
        let jumpMultiplierPerYear = ethers.parseEther('0');
        let kink = ethers.parseEther('1.0');

        if (useVariableIRM) 
        {
          let _vertexUtilization = '1000000000000000000';// 100%
          let _vertexRatePercentOfDelta = '1000000000000000000';// 100%
          let _minUtil = '0';// 0%
          let _maxUtil = '1000000000000000000';// 100%
          let _zeroUtilizationRate = '0';//0%
          let _minFullUtilizationRate = multiplierPerYear;//multiplierPerYear
          let _maxFullUtilizationRate = multiplierPerYear;//multiplierPerYear
          // 
          // Interest Rate Half-Life: The time it takes for the interest to halve when Utilization is 0%.
          // This is the speed at which the interest rate adjusts.
          // In the currently available Rate Calculator, the Interest Rate Half-Life is 12 hours.
    
          let _rateHalfLife = 12 * 3600;
          // perblock
          let _zeroUtilizationRatePerBlock = Math.floor(_zeroUtilizationRate / blocksPerYear);
          let _minFullUtilizationRatePerBlock = Math.floor(Number(_minFullUtilizationRate) / blocksPerYear);
          let _maxFullUtilizationRatePerBlock = Math.floor(Number(_maxFullUtilizationRate) / blocksPerYear);
    
    
          let rateModel2 = await ethers.deployContract("JumpRateModelVariable",
            ["numaRateModel", _vertexUtilization, _vertexRatePercentOfDelta, _minUtil, _maxUtil,
              _zeroUtilizationRatePerBlock, _minFullUtilizationRatePerBlock, _maxFullUtilizationRatePerBlock,
              _rateHalfLife, await owner.getAddress()]);
    
          await cReth._setInterestRateModel(rateModel2);
          await cNuma._setInterestRateModel(rateModel2);
    
        }
        else
        {
          let IM_address = await cReth.interestRateModel();
          let IMV2 = await ethers.getContractAt("JumpRateModelV4", IM_address);
          await IMV2.updateJumpRateModel(baseRatePerYear,multiplierPerYear
          ,jumpMultiplierPerYear,kink);

        }

        const ethMantissa = 1e18;
        const blocksPerDay = (4 * 60 * 24);
        const daysPerYear = (365);

        // let blocksPerYear = daysPerYear*blocksPerDay;
        
        let supplyRatePerBlock = Number(await cReth.supplyRatePerBlock());
        let borrowRatePerBlock = Number(await cReth.borrowRatePerBlock());

        let supplyApy = (((Math.pow(((supplyRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
        let borrowApy = (((Math.pow(((borrowRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
        console.log(`Supply APY for ETH ${supplyApy} %`);
        console.log(`Borrow APY for ETH ${borrowApy} %`);
        console.log("*************************");
        let numaPriceBefore = await VM.numaToEth(ethers.parseEther("1"),0);

        let numasupplyamount = ethers.parseEther("200000");
        // userB supply numa      
        await supplyNuma(userB,numasupplyamount);

        // max borrow
        let collateralValueInrEthWei = await getMaxBorrowReth(numasupplyamount);

        // verify toomuch/nottoomuch (x2: collat and available from vault)
        let notTooMuchrEth = collateralValueInrEthWei;
        let tooMuchrEth = notTooMuchrEth+BigInt(1);
        // 
        await cReth.connect(userB).borrow(notTooMuchrEth);

        // should be > 0
        supplyRatePerBlock = Number(await cReth.supplyRatePerBlock());
        borrowRatePerBlock = Number(await cReth.borrowRatePerBlock());


        let cashAvailable = await Vault1.GetMaxBorrow();
        let UR = Number(collateralValueInrEthWei) / Number(collateralValueInrEthWei + cashAvailable);

        let borrowRate = Number(baseRatePerYear)/blocksPerYear + UR * Number(multiplierPerYear)/blocksPerYear;
        let supplyRate = UR * borrowRate;
       
        
        console.log("borrow rate computed");
        console.log((borrowRate));
        console.log((supplyRate));


        console.log("borrow rate from contracts");
        console.log((borrowRatePerBlock));
        console.log((supplyRatePerBlock));
        expect(borrowRatePerBlock).to.equal(Math.floor(borrowRate));
        expect(supplyRatePerBlock).to.equal(Math.floor(supplyRate));
      
        supplyApy = (((Math.pow(((supplyRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
        borrowApy = (((Math.pow(((borrowRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
        console.log(`Supply APY for ETH ${supplyApy} %`);
        console.log(`Borrow APY for ETH ${borrowApy} %`);
        console.log(`Utilization rate ${UR*100} %`);
        console.log("*************************");
        // change UR
        await Vault1.setMaxBorrow(vaultInitialBalance/BigInt(2));

        supplyRatePerBlock = Number(await cReth.supplyRatePerBlock());
        borrowRatePerBlock = Number(await cReth.borrowRatePerBlock());


        cashAvailable = await Vault1.GetMaxBorrow();
        UR = Number(collateralValueInrEthWei) / Number(collateralValueInrEthWei + cashAvailable);

        borrowRate = Number(baseRatePerYear)/blocksPerYear + UR * Number(multiplierPerYear)/blocksPerYear;
        supplyRate = UR * borrowRate;
       
 
        expect(borrowRatePerBlock).to.equal(Math.floor(borrowRate));
        expect(supplyRatePerBlock).to.equal(Math.floor(supplyRate));
      
        supplyApy = (((Math.pow(((supplyRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
        borrowApy = (((Math.pow(((borrowRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
        console.log(`Supply APY for ETH ${supplyApy} %`);
        console.log(`Borrow APY for ETH ${borrowApy} %`);

        console.log(`Utilization rate ${UR*100} %`);

        console.log("*************************");
         // change UR
         await Vault1.setMaxBorrow(0);

         supplyRatePerBlock = Number(await cReth.supplyRatePerBlock());
         borrowRatePerBlock = Number(await cReth.borrowRatePerBlock());
 
 
         cashAvailable = await Vault1.GetMaxBorrow();
         UR = Number(collateralValueInrEthWei) / Number(collateralValueInrEthWei + cashAvailable);
 
         borrowRate = Number(baseRatePerYear)/blocksPerYear + UR * Number(multiplierPerYear)/blocksPerYear;
         supplyRate = UR * borrowRate;
        
  
         expect(borrowRatePerBlock).to.equal(Math.floor(borrowRate));
         expect(supplyRatePerBlock).to.equal(Math.floor(supplyRate));
       
         supplyApy = (((Math.pow(((supplyRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
         borrowApy = (((Math.pow(((borrowRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
         console.log(`Supply APY for ETH ${supplyApy} %`);
         console.log(`Borrow APY for ETH ${borrowApy} %`);
 
         console.log(`Utilization rate ${UR*100} %`);
         console.log("*************************");
          // change kink & jump
          jumpMultiplierPerYear = ethers.parseEther('3');
          kink = ethers.parseEther('0.01');
         if (useVariableIRM) 
         {
          let _vertexUtilization = kink;
          //let _vertexRatePercentOfDelta = kink * multiplierPerYear;// 100%
          let _minUtil = '0';// 0%
          let _maxUtil = '1000000000000000000';// 100%
          let _zeroUtilizationRate = '0';//0%
          //let maxRate = jumpMultiplierPerYear * (ethers.parseEther('1') - kink)/(ethers.parseEther('1') - _vertexRatePercentOfDelta);

          // to match jumpratemodelV2 and following test we divide multiplierPerYear by kink
          let multiplierPerYearModified = Number(multiplierPerYear)/ethers.formatEther(kink);

          let maxRate = (kink * BigInt(multiplierPerYearModified.toString()) + (ethers.parseEther('1') - kink) * jumpMultiplierPerYear)/ethers.parseEther('1');
          let _vertexRatePercentOfDelta = (kink * BigInt(multiplierPerYearModified.toString()))/maxRate;

          let _minFullUtilizationRate = maxRate;
          let _maxFullUtilizationRate = maxRate;
          // 
          // Interest Rate Half-Life: The time it takes for the interest to halve when Utilization is 0%.
          // This is the speed at which the interest rate adjusts.
          // In the currently available Rate Calculator, the Interest Rate Half-Life is 12 hours.
    
          let _rateHalfLife = 12 * 3600;
          // perblock
          let _zeroUtilizationRatePerBlock = Math.floor(_zeroUtilizationRate / blocksPerYear);
          let _minFullUtilizationRatePerBlock = Math.floor(Number(_minFullUtilizationRate) / blocksPerYear);
          let _maxFullUtilizationRatePerBlock = Math.floor(Number(_maxFullUtilizationRate) / blocksPerYear);
    
    
          let rateModel2 = await ethers.deployContract("JumpRateModelVariable",
            ["numaRateModel", _vertexUtilization, _vertexRatePercentOfDelta, _minUtil, _maxUtil,
              _zeroUtilizationRatePerBlock, _minFullUtilizationRatePerBlock, _maxFullUtilizationRatePerBlock,
              _rateHalfLife, await owner.getAddress()]);
    
          await cReth._setInterestRateModel(rateModel2);
          await cNuma._setInterestRateModel(rateModel2);
         }
         else
         {
          let IM_address = await cReth.interestRateModel();
          let IMV2 = await ethers.getContractAt("JumpRateModelV4", IM_address);
         
           await IMV2.updateJumpRateModel(baseRatePerYear,multiplierPerYear
           ,jumpMultiplierPerYear,kink);
         }
         // change UR
         await Vault1.setMaxBorrow(vaultInitialBalance/BigInt(8));
         supplyRatePerBlock = Number(await cReth.supplyRatePerBlock());
         borrowRatePerBlock = Number(await cReth.borrowRatePerBlock());
 
 
         cashAvailable = await Vault1.GetMaxBorrow();
         UR = Number(collateralValueInrEthWei) / Number(collateralValueInrEthWei + cashAvailable);

          // in V2 multiplierPerBlock = multiplierPerYear/(BlockPerYear*kink)
          let multiplierPerBlock =  Number(multiplierPerYear)/(blocksPerYear* ethers.formatEther(kink));
          let normalRate = Number(baseRatePerYear)/blocksPerYear + Number(ethers.formatEther(kink)) * multiplierPerBlock;
          let excessUtil = UR.toString() - ethers.formatEther(kink);
 
          borrowRate = normalRate  + Number(excessUtil) * Number(jumpMultiplierPerYear)/blocksPerYear;
           
  
         
       

         supplyRate = UR * borrowRate;
        
         // TODOTEST2
         expect(borrowRatePerBlock).to.be.closeTo(Math.floor(borrowRate),500000);
         expect(supplyRatePerBlock).to.be.closeTo(Math.floor(supplyRate),500000);
  
         supplyApy = (((Math.pow(((supplyRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
         borrowApy = (((Math.pow(((borrowRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
         let supplyApyExpected = (((Math.pow(((Math.floor(supplyRate) / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
         let borrowApyExpected = (((Math.pow(((Math.floor(borrowRate) / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
         console.log(`Supply APY for ETH ${supplyApy} %`);
         console.log(`Borrow APY for ETH ${borrowApy} %`);

         console.log(`Expected Supply APY for ETH ${supplyApyExpected} %`);
         console.log(`Expected Borrow APY for ETH ${borrowApyExpected} %`);
 
         console.log(`Utilization rate ${UR*100} %`);



      });

      it('IR supply&borrow lst borrowers no lenders vault > CF', async () => 
      {
      });

      it('IR supply&borrow lst borrowers lenders vault > CF', async () => 
      {
      });

    
      it('variable interest rates', async () => 
      {
        if (useVariableIRM) 
        {
          // 
          await Vault1.setOracle(VO_ADDRESScustomHeartbeat);
          let _vertexUtilization = '800000000000000000';// 80%
          let _vertexRatePercentOfDelta = '500000000000000000';// 50%
          let _minUtil = '500000000000000000';// 50%
          let _maxUtil = '700000000000000000';// 70%
          let _zeroUtilizationRate = '20000000000000000';//2%
          // for min we use same value as specified in token contracts
          // because I guess initial value should be minimum interest rate at max utilization
          let _minFullUtilizationRate = maxUtilizationRatePerYear;          
          let _maxFullUtilizationRate ='2000000000000000000';// 200 %
          // 
          // Interest Rate Half-Life: The time it takes for the interest to halve when Utilization is 0%.
          // This is the speed at which the interest rate adjusts.
          // In the currently available Rate Calculator, the Interest Rate Half-Life is 12 hours.
    
          let _rateHalfLife = 6 * 3600;
          // perblock
          let _zeroUtilizationRatePerBlock = Math.floor(_zeroUtilizationRate / blocksPerYear);
          let _minFullUtilizationRatePerBlock = Math.floor(Number(_minFullUtilizationRate) / blocksPerYear);
          let _maxFullUtilizationRatePerBlock = Math.floor(Number(_maxFullUtilizationRate) / blocksPerYear);
    
    
          let rateModel2 = await ethers.deployContract("JumpRateModelVariable",
            ["numaRateModel", _vertexUtilization, _vertexRatePercentOfDelta, _minUtil, _maxUtil,
              _zeroUtilizationRatePerBlock, _minFullUtilizationRatePerBlock, _maxFullUtilizationRatePerBlock,
              _rateHalfLife, await owner.getAddress()]);
    
          await cReth._setInterestRateModel(rateModel2);
          await cNuma._setInterestRateModel(rateModel2);
    
        

        // utilization in range --> interest rate is default
        const ethMantissa = 1e18;
        const blocksPerDay = (4 * 60 * 24);
        const daysPerYear = (365);

        // let blocksPerYear = daysPerYear*blocksPerDay;
        
        let supplyRatePerBlock = Number(await cReth.supplyRatePerBlock());
        let borrowRatePerBlock = Number(await cReth.borrowRatePerBlock());
        // console.log(borrowRatePerBlock);
        // console.log(supplyRatePerBlock);
        let supplyApy = (((Math.pow(((supplyRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
        let borrowApy = (((Math.pow(((borrowRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
        console.log(`Supply APY for ETH ${supplyApy} %`);
        console.log(`Borrow APY for ETH ${borrowApy} %`);
        console.log("*************************");
        let numaPriceBefore = await VM.numaToEth(ethers.parseEther("1"),0);

        let numasupplyamount = ethers.parseEther("200000");
        // userB supply numa      
        await supplyNuma(userB,numasupplyamount);

        // max borrow
        let collateralValueInrEthWei = await getMaxBorrowReth(numasupplyamount);

        // verify toomuch/nottoomuch (x2: collat and available from vault)
        let notTooMuchrEth = collateralValueInrEthWei;
        let tooMuchrEth = notTooMuchrEth+BigInt(1);
        // 
        await cReth.connect(userB).borrow(notTooMuchrEth);

        // should be > 0
        supplyRatePerBlock = Number(await cReth.supplyRatePerBlock());
        borrowRatePerBlock = Number(await cReth.borrowRatePerBlock());


        let cashAvailable = await Vault1.GetMaxBorrow();
        let UR = Number(collateralValueInrEthWei) / Number(collateralValueInrEthWei + cashAvailable);

        let maxUtilizationRatePerBlock = Math.floor(maxUtilizationRatePerYear/blocksPerYear);


        supplyApy = (((Math.pow(((supplyRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
        borrowApy = (((Math.pow(((borrowRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
        console.log(`Supply APY for ETH ${supplyApy} %`);
        console.log(`Borrow APY for ETH ${borrowApy} %`);
        console.log(`Utilization rate ${UR*100} %`);
        console.log(`maxUtilizationRate ${(100*maxUtilizationRatePerBlock*blocksPerYear)/1e18} %`);
        console.log("*************************");

        // check rates
        // _newRatePerBlock = (
        //   ZERO_UTIL_RATE + (_utilization * (_vertexInterest - ZERO_UTIL_RATE)) / VERTEX_UTILIZATION
        // );



        let _vertexInterest = _zeroUtilizationRatePerBlock + (_vertexRatePercentOfDelta * (maxUtilizationRatePerBlock - _zeroUtilizationRatePerBlock))/1e18;
        let borrowRate = _zeroUtilizationRatePerBlock  + ((UR*1e18) * (_vertexInterest - _zeroUtilizationRatePerBlock))/_vertexUtilization;
         

        let supplyRate = UR * borrowRate;
      

         expect(borrowRatePerBlock).to.be.closeTo(Math.floor(borrowRate),20000);
         expect(supplyRatePerBlock).to.be.closeTo(Math.floor(supplyRate),20000);

         // should not change as we are below range BUT our min is currentmaxrate
         await time.increase(3600*12);

         supplyRatePerBlock = Number(await cReth.supplyRatePerBlock());
         borrowRatePerBlock = Number(await cReth.borrowRatePerBlock());
         expect(borrowRatePerBlock).to.be.closeTo(Math.floor(borrowRate),20000);
         expect(supplyRatePerBlock).to.be.closeTo(Math.floor(supplyRate),20000);

         // change max borrow so that UR > 65% --> in range
         let maxBorrow = ((collateralValueInrEthWei)*(BigInt(1e18) - BigInt('650000000000000000')))/BigInt('650000000000000000');
        
         await Vault1.setMaxBorrow(maxBorrow);
         cashAvailable = await Vault1.GetMaxBorrow();
          UR = Number(collateralValueInrEthWei) / Number(collateralValueInrEthWei + cashAvailable);

          // should not change as we are in range
         await time.increase(3600*12);
         _vertexInterest = _zeroUtilizationRatePerBlock + (_vertexRatePercentOfDelta * (maxUtilizationRatePerBlock - _zeroUtilizationRatePerBlock))/1e18;
         borrowRate = _zeroUtilizationRatePerBlock  + ((UR*1e18) * (_vertexInterest - _zeroUtilizationRatePerBlock))/_vertexUtilization;
         supplyRate = UR * borrowRate;
         supplyRatePerBlock = Number(await cReth.supplyRatePerBlock());
         borrowRatePerBlock = Number(await cReth.borrowRatePerBlock());
         expect(borrowRatePerBlock).to.be.closeTo(Math.floor(borrowRate),20000);
         expect(supplyRatePerBlock).to.be.closeTo(Math.floor(supplyRate),20000);


         // change max borrow so that UR > 80% --> out of range and kink
         maxBorrow = ((collateralValueInrEthWei)*(BigInt(1e18) - BigInt('850000000000000000')))/BigInt('850000000000000000');
        
        await Vault1.setMaxBorrow(maxBorrow);
        cashAvailable = await Vault1.GetMaxBorrow();
         UR = Number(collateralValueInrEthWei) / Number(collateralValueInrEthWei + cashAvailable);
  
         _vertexInterest = _zeroUtilizationRatePerBlock + (_vertexRatePercentOfDelta * (maxUtilizationRatePerBlock - _zeroUtilizationRatePerBlock))/1e18;
         borrowRate = _vertexInterest  + ((UR*1e18 - _vertexUtilization) * (maxUtilizationRatePerBlock - _vertexInterest))/(1e18 - _vertexUtilization);

         supplyRate = UR * borrowRate;
         supplyRatePerBlock = Number(await cReth.supplyRatePerBlock());
         borrowRatePerBlock = Number(await cReth.borrowRatePerBlock());
         expect(borrowRatePerBlock).to.be.closeTo(Math.floor(borrowRate),200000);
         expect(supplyRatePerBlock).to.be.closeTo(Math.floor(supplyRate),200000);

         supplyApy = (((Math.pow(((supplyRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
         borrowApy = (((Math.pow(((borrowRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
         console.log(`Supply APY for ETH ${supplyApy} %`);
         console.log(`Borrow APY for ETH ${borrowApy} %`);
         console.log(`Utilization rate ${UR*100} %`);
         console.log(`maxUtilizationRate ${(100*maxUtilizationRatePerBlock*blocksPerYear)/1e18} %`);
         console.log("*************************");


         // advance in time maxrate should change
         let _deltaTime = 3600*12;
         await time.increase(_deltaTime);
         // half life is 6 hours
         let _deltaUtilization = ((UR*1e18 - _maxUtil) * 1e18) / (1e18 - _maxUtil);
         // 36 decimals

         let _decayGrowth = (6*3600 * 1e36) + (_deltaUtilization * _deltaUtilization * _deltaTime);
         // 18 decimals
         maxUtilizationRatePerBlock = ((maxUtilizationRatePerBlock * _decayGrowth) / (6*3600 * 1e36));
       
         // test
         _vertexInterest = _zeroUtilizationRatePerBlock + (_vertexRatePercentOfDelta * (maxUtilizationRatePerBlock - _zeroUtilizationRatePerBlock))/1e18;
         borrowRate = _vertexInterest  + ((UR*1e18 - _vertexUtilization) * (maxUtilizationRatePerBlock - _vertexInterest))/(1e18 - _vertexUtilization);

         supplyRate = UR * borrowRate;
         supplyRatePerBlock = Number(await cReth.supplyRatePerBlock());
         borrowRatePerBlock = Number(await cReth.borrowRatePerBlock());
         expect(borrowRatePerBlock).to.be.closeTo(Math.floor(borrowRate),500000);
         expect(supplyRatePerBlock).to.be.closeTo(Math.floor(supplyRate),500000);

         supplyApy = (((Math.pow(((supplyRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
         borrowApy = (((Math.pow(((borrowRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
         console.log(`Supply APY for ETH ${supplyApy} %`);
         console.log(`Borrow APY for ETH ${borrowApy} %`);
         console.log(`Utilization rate ${UR*100} %`);
         console.log(`maxUtilizationRate ${(100*maxUtilizationRatePerBlock*blocksPerYear)/1e18} %`);
         console.log("*************************");

          // advance again so that we test max maxRate clamping
          await time.increase(_deltaTime);
          // half life is 6 hours
          _deltaUtilization = ((UR*1e18 - _maxUtil) * 1e18) / (1e18 - _maxUtil);
          // 36 decimals
 
          _decayGrowth = (6*3600 * 1e36) + (_deltaUtilization * _deltaUtilization * _deltaTime);
          // 18 decimals
          maxUtilizationRatePerBlock = ((maxUtilizationRatePerBlock * _decayGrowth) / (6*3600 * 1e36));
          if (maxUtilizationRatePerBlock > _maxFullUtilizationRatePerBlock)
            maxUtilizationRatePerBlock = _maxFullUtilizationRatePerBlock;
        
          // test
          _vertexInterest = _zeroUtilizationRatePerBlock + (_vertexRatePercentOfDelta * (maxUtilizationRatePerBlock - _zeroUtilizationRatePerBlock))/1e18;
          borrowRate = _vertexInterest  + ((UR*1e18 - _vertexUtilization) * (maxUtilizationRatePerBlock - _vertexInterest))/(1e18 - _vertexUtilization);
 
          supplyRate = UR * borrowRate;
          supplyRatePerBlock = Number(await cReth.supplyRatePerBlock());
          borrowRatePerBlock = Number(await cReth.borrowRatePerBlock());
          expect(borrowRatePerBlock).to.be.closeTo(Math.floor(borrowRate),500000);
          expect(supplyRatePerBlock).to.be.closeTo(Math.floor(supplyRate),500000);
 
          supplyApy = (((Math.pow(((supplyRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
          borrowApy = (((Math.pow(((borrowRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
          console.log(`Supply APY for ETH ${supplyApy} %`);
          console.log(`Borrow APY for ETH ${borrowApy} %`);
          console.log(`Utilization rate ${UR*100} %`);
          console.log(`maxUtilizationRate ${(100*maxUtilizationRatePerBlock*blocksPerYear)/1e18} %`);
          console.log("*************************");


         // back in range 
          maxBorrow = ((collateralValueInrEthWei)*(BigInt(1e18) - BigInt('650000000000000000')))/BigInt('650000000000000000');
        
          await Vault1.setMaxBorrow(maxBorrow);
          cashAvailable = await Vault1.GetMaxBorrow();
           UR = Number(collateralValueInrEthWei) / Number(collateralValueInrEthWei + cashAvailable);

           // advance in time maxrate should change but not kinked anymore
           await time.increase(_deltaTime); 

           _vertexInterest = _zeroUtilizationRatePerBlock + (_vertexRatePercentOfDelta * (maxUtilizationRatePerBlock - _zeroUtilizationRatePerBlock))/1e18;
           borrowRate = _zeroUtilizationRatePerBlock  + ((UR*1e18) * (_vertexInterest - _zeroUtilizationRatePerBlock))/_vertexUtilization;
            supplyRate = UR * borrowRate;
         
            supplyRatePerBlock = Number(await cReth.supplyRatePerBlock());
            borrowRatePerBlock = Number(await cReth.borrowRatePerBlock());
            expect(borrowRatePerBlock).to.be.closeTo(Math.floor(borrowRate),3000000);
            expect(supplyRatePerBlock).to.be.closeTo(Math.floor(supplyRate),3000000);
            supplyApy = (((Math.pow(((supplyRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
            borrowApy = (((Math.pow(((borrowRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
            console.log(`Supply APY for ETH ${supplyApy} %`);
            console.log(`Borrow APY for ETH ${borrowApy} %`);
            console.log(`Utilization rate ${UR*100} %`);
            console.log(`maxUtilizationRate ${(100*maxUtilizationRatePerBlock*blocksPerYear)/1e18} %`);
            console.log("*************************");

            // below range
            maxBorrow = ((collateralValueInrEthWei)*(BigInt(1e18) - BigInt('250000000000000000')))/BigInt('250000000000000000');
        
            await Vault1.setMaxBorrow(maxBorrow);
            cashAvailable = await Vault1.GetMaxBorrow();
             UR = Number(collateralValueInrEthWei) / Number(collateralValueInrEthWei + cashAvailable);


             // no time change
             _vertexInterest = _zeroUtilizationRatePerBlock + (_vertexRatePercentOfDelta * (maxUtilizationRatePerBlock - _zeroUtilizationRatePerBlock))/1e18;
             borrowRate = _zeroUtilizationRatePerBlock  + ((UR*1e18) * (_vertexInterest - _zeroUtilizationRatePerBlock))/_vertexUtilization;
              supplyRate = UR * borrowRate;
           
              supplyRatePerBlock = Number(await cReth.supplyRatePerBlock());
              borrowRatePerBlock = Number(await cReth.borrowRatePerBlock());
              expect(borrowRatePerBlock).to.be.closeTo(Math.floor(borrowRate),3000000);
              expect(supplyRatePerBlock).to.be.closeTo(Math.floor(supplyRate),3000000);
              supplyApy = (((Math.pow(((supplyRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
              borrowApy = (((Math.pow(((borrowRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
              console.log(`Supply APY for ETH ${supplyApy} %`);
              console.log(`Borrow APY for ETH ${borrowApy} %`);
              console.log(`Utilization rate ${UR*100} %`);
              console.log(`maxUtilizationRate ${(100*maxUtilizationRatePerBlock*blocksPerYear)/1e18} %`);
              console.log("*************************");

  
             // advance in time maxrate should change 
             await time.increase(_deltaTime); 

              _deltaUtilization = ((_minUtil - UR*1e18 ) * 1e18) / (_minUtil);
             // 36 decimals
    
             _decayGrowth = (6*3600 * 1e36) + (_deltaUtilization * _deltaUtilization * _deltaTime);
             // 18 decimals
             maxUtilizationRatePerBlock = ((maxUtilizationRatePerBlock * (6*3600 * 1e36)) / (_decayGrowth));
           
  
             _vertexInterest = _zeroUtilizationRatePerBlock + (_vertexRatePercentOfDelta * (maxUtilizationRatePerBlock - _zeroUtilizationRatePerBlock))/1e18;
             borrowRate = _zeroUtilizationRatePerBlock  + ((UR*1e18) * (_vertexInterest - _zeroUtilizationRatePerBlock))/_vertexUtilization;
              supplyRate = UR * borrowRate;
           
              supplyRatePerBlock = Number(await cReth.supplyRatePerBlock());
              borrowRatePerBlock = Number(await cReth.borrowRatePerBlock());
              expect(borrowRatePerBlock).to.be.closeTo(Math.floor(borrowRate),3000000);
              expect(supplyRatePerBlock).to.be.closeTo(Math.floor(supplyRate),3000000);
              supplyApy = (((Math.pow(((supplyRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
              borrowApy = (((Math.pow(((borrowRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
              console.log(`Supply APY for ETH ${supplyApy} %`);
              console.log(`Borrow APY for ETH ${borrowApy} %`);
              console.log(`Utilization rate ${UR*100} %`);
              console.log(`maxUtilizationRate ${(100*maxUtilizationRatePerBlock*blocksPerYear)/1e18} %`);
              console.log("*************************");

              // again to check minimum maxRate
              await time.increase(_deltaTime); 

              _deltaUtilization = ((_minUtil - UR*1e18 ) * 1e18) / (_minUtil);
             // 36 decimals
    
             _decayGrowth = (6*3600 * 1e36) + (_deltaUtilization * _deltaUtilization * _deltaTime);
             // 18 decimals
             maxUtilizationRatePerBlock = ((maxUtilizationRatePerBlock * (6*3600 * 1e36)) / (_decayGrowth));
           

             if (maxUtilizationRatePerBlock < _minFullUtilizationRatePerBlock)
                maxUtilizationRatePerBlock = _minFullUtilizationRatePerBlock;

  
             _vertexInterest = _zeroUtilizationRatePerBlock + (_vertexRatePercentOfDelta * (maxUtilizationRatePerBlock - _zeroUtilizationRatePerBlock))/1e18;
             borrowRate = _zeroUtilizationRatePerBlock  + ((UR*1e18) * (_vertexInterest - _zeroUtilizationRatePerBlock))/_vertexUtilization;
              supplyRate = UR * borrowRate;
           
              supplyRatePerBlock = Number(await cReth.supplyRatePerBlock());
              borrowRatePerBlock = Number(await cReth.borrowRatePerBlock());
              expect(borrowRatePerBlock).to.be.closeTo(Math.floor(borrowRate),3000000);
              expect(supplyRatePerBlock).to.be.closeTo(Math.floor(supplyRate),3000000);
              supplyApy = (((Math.pow(((supplyRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
              borrowApy = (((Math.pow(((borrowRatePerBlock / ethMantissa * blocksPerDay) + (1)), daysPerYear))) - (1)) * (100);
              console.log(`Supply APY for ETH ${supplyApy} %`);
              console.log(`Borrow APY for ETH ${borrowApy} %`);
              console.log(`Utilization rate ${UR*100} %`);
              console.log(`maxUtilizationRate ${(100*maxUtilizationRatePerBlock*blocksPerYear)/1e18} %`);
              console.log("*************************");
        }


      });



    });

    describe('#Rewards extraction from debt', () => 
    {
      it('Extract from debt', async () => 
      {
        // set a mock rEth oracle to simulate rebase
        let VMO = await ethers.deployContract("VaultMockOracle",[]);
        await VMO.waitForDeployment();
        let VMO_ADDRESS= await VMO.getAddress();
        await Vault1.setOracle(VMO_ADDRESS);
        
        // set new price, simulate a 100% rebase
        let lastprice = await Vault1.last_lsttokenvalueWei();    
        await Vault1.setRwdAddress(await userC.getAddress(),false);

        //
        let numasupplyamount = ethers.parseEther("200000");
        // userB supply numa      
        await supplyNuma(userB,numasupplyamount);

       
                

        // max borrow
        let collateralValueInrEthWei = await getMaxBorrowReth(numasupplyamount);

        // compute how much should be borrowable from vault
        let maxBorrow = await Vault1.GetMaxBorrow();
        console.log("max rEth borrow from vault "+ethers.formatEther(maxBorrow));

        // verify toomuch/nottoomuch (x2: collat and available from vault)
        let borrowrEth = collateralValueInrEthWei;

        await cReth.connect(userB).borrow(borrowrEth);
        let vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS); 
        expect(vaultBalance).to.equal(vaultInitialBalance - borrowrEth);         


        let newprice = (BigInt(2)*lastprice);
        await VMO.setPrice(newprice);
      

        let debtBefore = await Vault1.getDebt();


        let rewardsFromDebt = await Vault1.rewardsFromDebt();

        await Vault1.extractRewards();
       
        rewardsFromDebt = await Vault1.rewardsFromDebt();

        expect(rewardsFromDebt).to.equal(debtBefore/BigInt(2));       
        let debtAfter = await Vault1.getDebt();
        expect(debtAfter).to.equal(debtBefore);
        expect(debtAfter).to.equal(borrowrEth);
        console.log("vault debt");
        console.log(debtAfter);

        let balanceUserB = await rEth_contract.balanceOf(await userB.getAddress());
        expect(balanceUserB).to.equal(usersInitialBalance+borrowrEth);
        vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS); 



        // repay, check that remaining rewards are extracted and that total reward is ok
        let halfBorrow = borrowrEth/BigInt(2);

        await rEth_contract.connect(userB).approve(await cReth.getAddress(),halfBorrow);
        await cReth.connect(userB).repayBorrow(halfBorrow);
        console.log("repaying");
        console.log(halfBorrow);

        debtAfter = await Vault1.getDebt();
        console.log("repdebt after repay");
        console.log(debtAfter);

      });


      // it('Extract from debt repro H11 + fix TODO', async () => 
      // {
      //   // set a mock rEth oracle to simulate rebase
      //   let VMO = await ethers.deployContract("VaultMockOracle",[]);
      //   await VMO.waitForDeployment();
      //   let VMO_ADDRESS= await VMO.getAddress();
      //   await Vault1.setOracle(VMO_ADDRESS);
        
      //   // set new price, simulate a 100% rebase
      //   let lastprice = await Vault1.last_lsttokenvalueWei();    
      //   await Vault1.setRwdAddress(await userC.getAddress(),false);
  
      //   //
      //   let numasupplyamount = ethers.parseEther("200000");
      //   // userB supply numa      
      //   await supplyNuma(userB,numasupplyamount);
  
       
                
  
      //   // max borrow
      //   let collateralValueInrEthWei = await getMaxBorrowReth(numasupplyamount);
  
      //   // compute how much should be borrowable from vault
      //   let maxBorrow = await Vault1.GetMaxBorrow();
      //   console.log("max rEth borrow from vault "+ethers.formatEther(maxBorrow));
  
      //   // verify toomuch/nottoomuch (x2: collat and available from vault)
      //   let borrowrEth = collateralValueInrEthWei;
  
      //   await cReth.connect(userB).borrow(borrowrEth);
      //   let vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS); 
      //   expect(vaultBalance).to.equal(vaultInitialBalance - borrowrEth);         
  
  
      //   let newprice = (BigInt(2)*lastprice);
      //   await VMO.setPrice(newprice);
      
      //   // debt & rewards from debt before extraction
      //   let debtBefore = await Vault1.getDebt();
      //   expect(debtBefore).to.equal(borrowrEth);  
      //   let rewardsFromDebt = await Vault1.rewardsFromDebt();
      //   expect(rewardsFromDebt).to.equal(0);  
  
      //   //
      //   await Vault1.extractRewards();
       
      //   rewardsFromDebt = await Vault1.rewardsFromDebt();  
      //   expect(rewardsFromDebt).to.equal(debtBefore/BigInt(2));       
      //   let debtAfter = await Vault1.getDebt();
      //   expect(debtAfter).to.equal(debtBefore);
      

      //   console.log("vault debt");
      //   console.log(debtAfter);
  
      //   let balanceUserB = await rEth_contract.balanceOf(await userB.getAddress());
      //   expect(balanceUserB).to.equal(usersInitialBalance+borrowrEth);
      //   vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS); 
  
  
  
      //   // repay, check that remaining rewards are extracted and that total reward is ok
      //   let halfBorrow = borrowrEth/BigInt(2);
  
      //   await rEth_contract.connect(userB).approve(await cReth.getAddress(),halfBorrow*BigInt(2));// x2 so that I need to call it only once
      //   await cReth.connect(userB).repayBorrow(halfBorrow);
      //   console.log("repaying");
      //   console.log(halfBorrow);
  
      //   debtAfter = await Vault1.getDebt();
      //   console.log("debt after repay");
      //   console.log(debtAfter);
       
      //   expect(debtAfter).to.equal(debtBefore - halfBorrow);
      //   // check reward from dbt
      //   rewardsFromDebt = await Vault1.rewardsFromDebt();
      //   expect(rewardsFromDebt).to.equal(debtBefore/BigInt(4));  


      //   console.log(rewardsFromDebt);
      //   // repro H11

      //   // repay debt - 2
      //   await cReth.connect(userB).repayBorrow(debtAfter - BigInt(2));
      //   debtAfter = await Vault1.getDebt();             
      //   expect(debtAfter).to.equal(2);
      //   rewardsFromDebt = await Vault1.rewardsFromDebt();
      //   expect(rewardsFromDebt).to.equal(1);  

      //   // BUY OK

      //   // repay 1
      //   await cReth.connect(userB).repayBorrow(1);
      //   debtAfter = await Vault1.getDebt();             
      //   expect(debtAfter).to.equal(1);
      //   rewardsFromDebt = await Vault1.rewardsFromDebt();
      //   expect(rewardsFromDebt).to.equal(1);

      //   // repay 1 again
      //   await cReth.connect(userB).repayBorrow(1);
      //   debtAfter = await Vault1.getDebt();             
      //   expect(debtAfter).to.equal(0);
      //   rewardsFromDebt = await Vault1.rewardsFromDebt();
      //   expect(rewardsFromDebt).to.equal(1);


      //   // buy KO

      //   // TODO check total reward balance
  
  
 
      // });

    });

    describe('#Liquidations', () => 
    {
      // Add liquidation function.
      it('Borrow numa, change price, liquidate simple', async () => 
      {
        // standart liquidate numa borrowers
        // remove fees for checks
        await VM.setBuyFee(ethers.parseEther("1"));
        await VM.setSellFee(ethers.parseEther("1"));
        await Vault1.setFee(0);
        // approve
        let rethsupplyamount = ethers.parseEther("2"); 
        let numasupplyamount = ethers.parseEther("200000");
 
        await supplyReth(userA,rethsupplyamount);
        await supplyNuma(userB,numasupplyamount);

        // with vault using real vault price (called from vault to compare)
        let refValueWei = await Vault1.last_lsttokenvalueWei();
        let numaPrice = await VM.numaToToken(ethers.parseEther("1"),refValueWei,ethers.parseEther("1"),1000);
        console.log('numa price '+ numaPrice);

        let sellPrice = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("1"));
        console.log('numa sell price in rEth '+ sellPrice);


        // how many numas for 1 rEth
        let numaFromREth = await Vault1.getBuyNumaSimulateExtract(ethers.parseEther("1"));
        console.log("how many numa with 1 rEth "+ ethers.formatEther(numaFromREth));
        let numaBuyPriceInReth = (ethers.parseEther("1") * ethers.parseEther("1")) / numaFromREth;


        // add 1 because we round up division
        numaBuyPriceInReth = numaBuyPriceInReth +BigInt(1);
        console.log('numa buy price in rEth '+ numaBuyPriceInReth);


        // max borrow
        let collateralValueInrEthWei =  (ethers.parseEther(rEthCollateralFactor.toString())*rethsupplyamount);
        let collateralValueInNumaWei =  collateralValueInrEthWei / numaBuyPriceInReth;
        console.log("collateral value in numa (wei) "+collateralValueInNumaWei);
        console.log("collateral value in numa "+ethers.formatEther(collateralValueInNumaWei));

        let notTooMuchNuma = collateralValueInNumaWei;


        await expect(cNuma.connect(userA).borrow(notTooMuchNuma)).to.not.be.reverted;

  
        [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
          await userA.getAddress(),cReth,cNuma
        );
        expect(shortfall).to.equal(0);  
        // remove supply, will pump price
        let totalsupply = await numa.totalSupply();
        await numa.burn(totalsupply/BigInt(4));
        [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
          await userA.getAddress(),cReth,cNuma
        );

        expect(shortfall).to.be.closeTo(collateralValueInrEthWei/ethers.parseEther("3"),epsilon2); 
       

        let numaBalanceBefore = await numa.balanceOf(CNUMA_ADDRESS);

        // INCENTIVE
        // 10%
        await comptroller._setLiquidationIncentive(ethers.parseEther("1.10"));
        await Vault1.setMaxLiquidationsProfit(ethers.parseEther("10"));
        let repayAmount = notTooMuchNuma/BigInt(2);
        
        // liquidate
        await numa.approve(VAULT1_ADDRESS,repayAmount);

        
        // check lending protocol balance
        let numaBalanceLiquidatorBefore = await numa.balanceOf(await owner.getAddress());
        await Vault1.liquidateNumaBorrower(await userA.getAddress(), repayAmount,true,false) ;

        //
        // check new shortfall
        [_, collateral2, shortfall2] = await comptroller.getAccountLiquidityIsolate(
          await userA.getAddress(),cReth,cNuma
        );

        // check lending protocol balance
        let numaBalanceAfter = await numa.balanceOf(CNUMA_ADDRESS);
        expect(numaBalanceAfter).to.equal(numaBalanceBefore + repayAmount);

        let numaBalanceLiquidatorAfter = await numa.balanceOf(await owner.getAddress());
        // TODOTEST1 check this test why epsilon not enough
        expect(numaBalanceLiquidatorAfter).to.be.closeTo(numaBalanceLiquidatorBefore + (BigInt(10) * repayAmount) / BigInt(100),ethers.parseEther("1"));


      });

      // 2. standart liquidate rEth borrowers
      it('Borrow rEth, change price, liquidate simple', async () => 
      {
        // remove fees for checks
        await VM.setBuyFee(ethers.parseEther("1"));
        await VM.setSellFee(ethers.parseEther("1"));
        await Vault1.setFee(0);

        // supply reth
        let rethsupplyamount = ethers.parseEther("1");
        let numasupplyamount = ethers.parseEther("200000");

      
        await supplyReth(userA,rethsupplyamount);
        await supplyNuma(userB,numasupplyamount);
        // compute how much should be borrowable with this collateral
        let sellPrice = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("1"));
        console.log('numa sell price in rEth wei '+ sellPrice);
        // max borrow
        let collateralValueInrEthWei =  ((ethers.parseEther(numaCollateralFactor.toString())*numasupplyamount) * sellPrice)/(ethers.parseEther("1")*ethers.parseEther("1"));
        console.log("collateral value in reth (wei) "+collateralValueInrEthWei);
        console.log("collateral value in reth "+ethers.formatEther(collateralValueInrEthWei));
        // compute how much should be borrowable from vault
        let maxBorrow = await Vault1.GetMaxBorrow();
        console.log("max rEth borrow from vault "+ethers.formatEther(maxBorrow));
        // verify toomuch/nottoomuch (x2: collat and available from vault)
        let notTooMuchrEth = collateralValueInrEthWei;
        
        let lendingBalanceInitial = await rEth_contract.balanceOf(await CRETH_ADDRESS);
        // we should borrow 1rEth from lenders and 1 rEth from vault
        await expect(cReth.connect(userB).borrow(notTooMuchrEth)).to.not.be.reverted;
        let lendingBalanceAfterBorrow = await rEth_contract.balanceOf(await CRETH_ADDRESS);
        // should be empty
        expect(lendingBalanceAfterBorrow).to.equal(0);  
        let vaultBalanceAfterBorrow = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
      
        let vaultDebt = notTooMuchrEth - rethsupplyamount;
        expect(vaultBalanceAfterBorrow).to.equal(vaultInitialBalance - vaultDebt);
        let debtAfterBorrow = await Vault1.getDebt();
        expect(debtAfterBorrow).to.equal(vaultDebt);
        let [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
          await userB.getAddress(),cNuma,cReth
        );
        
        expect(shortfall).to.equal(0);  
        expect(collateral).to.be.closeTo(0,epsilon);

     
        // make it liquiditable 
        let totalsupply = await numa.totalSupply();
        await numa.mint(await owner.getAddress(),totalsupply/BigInt(5));
        [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
          await userB.getAddress(),cNuma,cReth
        );
        let sellPriceNew = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("1"));
     
        expect(shortfall).to.be.closeTo(collateralValueInrEthWei/BigInt(6),epsilon); 

        let rethBalanceBefore = await rEth_contract.balanceOf(CRETH_ADDRESS);
        // INCENTIVE
        // 10%
        await comptroller._setLiquidationIncentive(ethers.parseEther("1.10"));
        await Vault1.setMaxLiquidationsProfit(ethers.parseEther("10"));
        let repayAmount = notTooMuchrEth/BigInt(2);
        // await rEth_contract.approve(await cReth.getAddress(),repayAmount);
        // await cReth.liquidateBorrow(await userB.getAddress(), repayAmount,cNuma) ;
        await rEth_contract.approve(VAULT1_ADDRESS,repayAmount);
        let rethBalanceLiquidatorBefore = await rEth_contract.balanceOf(await owner.getAddress());
        await Vault1.liquidateLstBorrower(await userB.getAddress(), repayAmount,true,false) ;

        // check received balance equals equivalent collateral + discount
        // check lending protocol balance

        let repaidToVault = repayAmount;
        if (repayAmount > vaultDebt)
          repaidToVault = vaultDebt;
        let repaidToLending = repayAmount - repaidToVault;

        let vaultBalanceAfterLiquidation = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
        let vaultDebteAfterLiquidation = await Vault1.getDebt();
      
        let numaSoldInReth =  (BigInt(110) * repayAmount) / BigInt(100);
        expect(vaultBalanceAfterLiquidation).to.be.closeTo(vaultBalanceAfterBorrow + repaidToVault - numaSoldInReth,epsilon);
        expect(vaultDebteAfterLiquidation).to.equal(debtAfterBorrow - repaidToVault);

        let rethBalanceAfter = await rEth_contract.balanceOf(CRETH_ADDRESS);
        expect(rethBalanceAfter).to.equal(rethBalanceBefore + repaidToLending);
   
        let rethBalanceLiquidatorAfter = await rEth_contract.balanceOf(await owner.getAddress());
        expect(rethBalanceLiquidatorAfter).to.be.closeTo(rethBalanceLiquidatorBefore + (BigInt(10) * repayAmount) / BigInt(100),epsilon2);
   

  

      });

      // 3. custom liquidate numa borrowers
      it('Borrow numa, change price, liquidate flashloan', async () => 
      {
        // remove fees for checks
        await VM.setBuyFee(ethers.parseEther("1"));
        await VM.setSellFee(ethers.parseEther("1"));
        await Vault1.setFee(0);

        // supply
        let rethsupplyamount = ethers.parseEther("2");
        let numasupplyamount = ethers.parseEther("200000");

      
        await supplyReth(userA,rethsupplyamount);
        await supplyNuma(userB,numasupplyamount);
    
        let collateralValueInNumaWei = await getMaxBorrowNuma(rethsupplyamount);
        let notTooMuchNuma = collateralValueInNumaWei;


        await expect(cNuma.connect(userA).borrow(notTooMuchNuma)).to.not.be.reverted;

        [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
          await userA.getAddress(),cReth,cNuma
        );
        expect(shortfall).to.equal(0);  
        // double the supply, will multiply the price by 2
        let totalsupply = await numa.totalSupply();
        await numa.burn(totalsupply/BigInt(4));
        let numPriceBefore = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("1"));
        [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
          await userA.getAddress(),cReth,cNuma
        );

        expect(shortfall).to.be.closeTo(rethsupplyamount*ethers.parseEther(rEthCollateralFactor.toString())/ethers.parseEther("3"),epsilon); 
        
     

        let numaBalanceBefore = await numa.balanceOf(CNUMA_ADDRESS);

        let liquidatorNumaBalanceBefore = await numa.balanceOf(await owner.getAddress());
        let numaSupplyBefore = await numa.totalSupply();
        // INCENTIVE
        // 10%
        await comptroller._setLiquidationIncentive(ethers.parseEther("1.10"));
        
        let repayAmount = notTooMuchNuma/BigInt(2);
 
        await Vault1.setMaxLiquidationsProfit(ethers.parseEther("10"));
        await Vault1.liquidateNumaBorrower(await userA.getAddress(), repayAmount,true,true);


        //
        // check new shortfall
        [_, collateral2, shortfall2] = await comptroller.getAccountLiquidityIsolate(
          await userA.getAddress(),cReth,cNuma
        );

        // how much collateral should we get
        let numaFromREth = await Vault1.getBuyNumaSimulateExtract(ethers.parseEther("1"));
        let numaBuyPriceInReth = (ethers.parseEther("1") * ethers.parseEther("1")) / numaFromREth;


        // add 1 because we round up division
        numaBuyPriceInReth_plusOne = numaBuyPriceInReth +BigInt(1);
        let borrowRepaidReth = (repayAmount*numaBuyPriceInReth_plusOne)/ethers.parseEther("1");
        let collatRepaidReth = (repayAmount*numaBuyPriceInReth)/ethers.parseEther("1");

        // add discount
        let expectedCollatReceived = (BigInt(110) * collatRepaidReth) / BigInt(100);
        // liquidator should get 10%
        let expectedCollatReceivedNuma = (BigInt(10) * repayAmount) / BigInt(100);


        expect(shortfall2).to.be.closeTo(shortfall - borrowRepaidReth +(ethers.parseEther(rEthCollateralFactor.toString())*expectedCollatReceived)/(ethers.parseEther("1")),epsilon2);
       
        // check lending protocol balance
        let numaBalanceAfter = await numa.balanceOf(CNUMA_ADDRESS);
        expect(numaBalanceAfter).to.equal(numaBalanceBefore + repayAmount);
        // check vault debt
        let debt = await Vault1.getDebt();
        expect(debt).to.equal(0);

        let liquidatorNumaBalanceAfter = await numa.balanceOf(await owner.getAddress());
    
        let liquidatorProfit = liquidatorNumaBalanceAfter - liquidatorNumaBalanceBefore;
        // TODOTEST3
        expect(liquidatorProfit).to.be.closeTo(expectedCollatReceivedNuma,ethers.parseEther("0.5"));

        // check numa price is the same
        let numPriceAfter = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("1"));
        // TODOTEST3
        expect(numPriceAfter).to.be.closeTo(numPriceBefore,epsilon);
        
        
      });
     
      it('Borrow numa, change price, liquidate flashloan, max profit', async () => 
      {
        // remove fees for checks
        await VM.setBuyFee(ethers.parseEther("1"));
        await VM.setSellFee(ethers.parseEther("1"));
        await Vault1.setFee(0);

        // supply
        let rethsupplyamount = ethers.parseEther("2");
        let numasupplyamount = ethers.parseEther("200000");

      
        await supplyReth(userA,rethsupplyamount);
        await supplyNuma(userB,numasupplyamount);
    
        let collateralValueInNumaWei = await getMaxBorrowNuma(rethsupplyamount);
        let notTooMuchNuma = collateralValueInNumaWei;


        await expect(cNuma.connect(userA).borrow(notTooMuchNuma)).to.not.be.reverted;

        [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
          await userA.getAddress(),cReth,cNuma
        );
        expect(shortfall).to.equal(0);  
        // double the supply, will multiply the price by 2
        let totalsupply = await numa.totalSupply();
        await numa.burn(totalsupply/BigInt(4));
        let numaPriceBefore = await VM.numaToEth(ethers.parseEther("1"),0);
        [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
          await userA.getAddress(),cReth,cNuma
        );

        expect(shortfall).to.be.closeTo(rethsupplyamount*ethers.parseEther(rEthCollateralFactor.toString())/ethers.parseEther("3"),epsilon); 
        
     

        let numaBalanceBefore = await numa.balanceOf(CNUMA_ADDRESS);

        let liquidatorNumaBalanceBefore = await numa.balanceOf(await owner.getAddress());
        let numaSupplyBefore = await numa.totalSupply();
        // INCENTIVE
        // 10%
        await comptroller._setLiquidationIncentive(ethers.parseEther("1.10"));
        
        let repayAmount = notTooMuchNuma/BigInt(2);
 
        // numa
        let maxProfit = ethers.parseEther("2000");
        // lst
        let maxProfitLst = await VM.numaToToken(maxProfit,await Vault1.last_lsttokenvalueWei(),ethers.parseEther("1"),1000);
        await Vault1.setMaxLiquidationsProfit(maxProfitLst);
        //await Vault1.setMaxLiquidationsProfit(ethers.parseEther("1000000000000"));
        await Vault1.liquidateNumaBorrower(await userA.getAddress(), repayAmount,true,true);


        //
        // check new shortfall
        [_, collateral2, shortfall2] = await comptroller.getAccountLiquidityIsolate(
          await userA.getAddress(),cReth,cNuma
        );

        // how much collateral should we get
        let numaFromREth = await Vault1.getBuyNumaSimulateExtract(ethers.parseEther("1"));
        let numaBuyPriceInReth = (ethers.parseEther("1") * ethers.parseEther("1")) / numaFromREth;


        // add 1 because we round up division
        numaBuyPriceInReth_plusOne = numaBuyPriceInReth +BigInt(1);
        let borrowRepaidReth = (repayAmount*numaBuyPriceInReth_plusOne)/ethers.parseEther("1");
        let collatRepaidReth = (repayAmount*numaBuyPriceInReth)/ethers.parseEther("1");
        //let borrowRepaidRethBefore = (repayAmount*numaBuyPriceInRethBefore)/ethers.parseEther("1");
        //console.log(ethers.formatEther(borrowRepaidReth));
        // add discount
        let expectedCollatReceived = (BigInt(110) * collatRepaidReth) / BigInt(100);
        // liquidator should get 10%
        let expectedCollatReceivedNuma = (BigInt(10) * repayAmount) / BigInt(100);

 
        // complex to test as shortfall before changed too because numa price changed due to burning
        //expect(shortfall2).to.be.closeTo(shortfall - borrowRepaidReth +(ethers.parseEther(rEthCollateralFactor.toString())*expectedCollatReceived)/(ethers.parseEther("1")),epsilon3);
       
        // check lending protocol balance
        let numaBalanceAfter = await numa.balanceOf(CNUMA_ADDRESS);
        expect(numaBalanceAfter).to.equal(numaBalanceBefore + repayAmount);
        // check vault debt
        let debt = await Vault1.getDebt();
        expect(debt).to.equal(0);

        let liquidatorNumaBalanceAfter = await numa.balanceOf(await owner.getAddress());
    
        let liquidatorProfit = liquidatorNumaBalanceAfter - liquidatorNumaBalanceBefore;
        if (expectedCollatReceivedNuma > maxProfit)
          expectedCollatReceivedNuma = maxProfit;
        expect(liquidatorProfit).to.be.closeTo(expectedCollatReceivedNuma,epsilon2);

        // check numa price is the same

        
        let numaPriceAfter = await VM.numaToEth(ethers.parseEther("1"),0);

        // price
        expect(numaPriceAfter).to.be.above(numaPriceBefore);
        expect(numaPriceAfter).to.be.closeTo(numaPriceBefore,epsilon);
      });

      it('Borrow rEth, change price, liquidate flashloan', async () => 
      {
        // remove fees for checks
        await VM.setBuyFee(ethers.parseEther("1"));
        await VM.setSellFee(ethers.parseEther("1"));
        await Vault1.setFee(0);

        let rethsupplyamount = ethers.parseEther("1");
        let numasupplyamount = ethers.parseEther("200000");

        await supplyReth(userA,rethsupplyamount);
        await supplyNuma(userB,numasupplyamount);


        // compute how much should be borrowable with this collateral
        let sellPrice = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("1"));
        console.log('numa sell price in rEth wei '+ sellPrice);
        // max borrow
        let collateralValueInrEthWei =  await getMaxBorrowReth(numasupplyamount);
        // compute how much should be borrowable from vault
        let maxBorrow = await Vault1.GetMaxBorrow();
        console.log("max rEth borrow from vault "+ethers.formatEther(maxBorrow));
        // verify toomuch/nottoomuch (x2: collat and available from vault)
        let notTooMuchrEth = collateralValueInrEthWei;
       
       
        // we should borrow 1rEth from lenders and 1 rEth from vault
        await expect(cReth.connect(userB).borrow(notTooMuchrEth)).to.not.be.reverted;
        let lendingBalanceAfterBorrow = await rEth_contract.balanceOf(await CRETH_ADDRESS);


        let vaultDebt = notTooMuchrEth - rethsupplyamount;
        // should be empty
        expect(lendingBalanceAfterBorrow).to.equal(0);  
        let vaultBalanceAfterBorrow = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
      
        expect(vaultBalanceAfterBorrow).to.equal(vaultInitialBalance - vaultDebt);
        let debtAfterBorrow = await Vault1.getDebt();
        expect(debtAfterBorrow).to.equal(vaultDebt);
        //
        let [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
          await userB.getAddress(),cNuma,cReth
        );
        
        expect(shortfall).to.equal(0);  
        expect(collateral).to.be.closeTo(0,epsilon);


        let totalsupply = await numa.totalSupply();
        await numa.mint(await owner.getAddress(),totalsupply/BigInt(5));
        [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
          await userB.getAddress(),cNuma,cReth
        );
        let sellPriceNew = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("1"));

        expect(shortfall).to.be.closeTo(collateralValueInrEthWei/BigInt(6),epsilon); 
         
        let rethBalanceBefore = await rEth_contract.balanceOf(CRETH_ADDRESS);
        // INCENTIVE
        // 10%
        await comptroller._setLiquidationIncentive(ethers.parseEther("1.10"));
        await Vault1.setMaxLiquidationsProfit(ethers.parseEther("10"));
        let repayAmount = notTooMuchrEth/BigInt(2);
        await rEth_contract.approve(await cReth.getAddress(),repayAmount);

        let lstBalanceLiquidatorBefore = await rEth_contract.balanceOf(await owner.getAddress());

        await Vault1.liquidateLstBorrower(await userB.getAddress(), repayAmount,true,true);
        let lstBalanceLiquidatorAfter = await rEth_contract.balanceOf(await owner.getAddress());

        // checks
        // - liquidator should get 10% of repaidAmount
        expect(lstBalanceLiquidatorAfter).to.be.closeTo(lstBalanceLiquidatorBefore + BigInt(10)*repayAmount/BigInt(100),epsilon);

        // - debtrepaid --> balance lending protocol & vault debt
        let repaidToVault = repayAmount;
        if (repayAmount > vaultDebt)
          repaidToVault = vaultDebt;
        let repaidToLending = repayAmount - repaidToVault;

        let vaultBalanceAfterLiquidation = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
        let vaultDebteAfterLiquidation = await Vault1.getDebt();
      
        let numaSoldInReth =  (BigInt(110) * repayAmount) / BigInt(100);
        expect(vaultBalanceAfterLiquidation).to.be.closeTo(vaultBalanceAfterBorrow + repaidToVault - numaSoldInReth,epsilon);
        expect(vaultDebteAfterLiquidation).to.equal(debtAfterBorrow - repaidToVault);

        let rethBalanceAfter = await rEth_contract.balanceOf(CRETH_ADDRESS);
        expect(rethBalanceAfter).to.equal(rethBalanceBefore + repaidToLending);


  
      });


        // Add liquidation function.
        it('Borrow numa, change price, liquidate bad debt (no profit)', async () => 
        {
          await comptroller._setCloseFactor(ethers.parseEther("1.0").toString());
  
    

          // standart liquidate numa borrowers
          // remove fees for checks
          await VM.setBuyFee(ethers.parseEther("1"));
          await VM.setSellFee(ethers.parseEther("1"));
          await Vault1.setFee(0);
          // approve
          let rethsupplyamount = ethers.parseEther("2"); 
          let numasupplyamount = ethers.parseEther("200000");
   
          await supplyReth(userA,rethsupplyamount);
          let numasupplyamountA = ethers.parseEther("100");
          await supplyNuma(userA,numasupplyamountA);

          // 
          let crethBalance = await cReth.balanceOf(await userA.getAddress());
   
          await supplyNuma(userB,numasupplyamount);

          let [error0,tokenbalance0, borrowbalance0, exchangerate0] = await cReth.getAccountSnapshot(await userA.getAddress());
          let [error1,tokenbalance1, borrowbalance1, exchangerate1] = await cNuma.getAccountSnapshot(await userA.getAddress());

          console.log("exchange rate");
          console.log(exchangerate0);
          console.log(exchangerate1);
          // with vault using real vault price (called from vault to compare)
          let refValueWei = await Vault1.last_lsttokenvalueWei();
          let numaPrice = await VM.numaToToken(ethers.parseEther("1"),refValueWei,ethers.parseEther("1"),1000);
          console.log('numa price '+ numaPrice);
  
          let sellPrice = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("1"));
          console.log('numa sell price in rEth '+ sellPrice);
  
  
          // how many numas for 1 rEth
          let numaFromREth = await Vault1.getBuyNumaSimulateExtract(ethers.parseEther("1"));
          console.log("how many numa with 1 rEth "+ ethers.formatEther(numaFromREth));
          let numaBuyPriceInReth = (ethers.parseEther("1") * ethers.parseEther("1")) / numaFromREth;
  
  
          // add 1 because we round up division
          numaBuyPriceInReth = numaBuyPriceInReth +BigInt(1);
          console.log('numa buy price in rEth '+ numaBuyPriceInReth);
  
  
          // max borrow
          let collateralValueInrEthWei =  (ethers.parseEther(rEthCollateralFactor.toString())*rethsupplyamount);
          let collateralValueInNumaWei =  collateralValueInrEthWei / numaBuyPriceInReth;
          console.log("collateral value in numa (wei) "+collateralValueInNumaWei);
          console.log("collateral value in numa "+ethers.formatEther(collateralValueInNumaWei));
  
          let notTooMuchNuma = collateralValueInNumaWei;
  
  
          await expect(cNuma.connect(userA).borrow(notTooMuchNuma)).to.not.be.reverted;
  
    
          [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
            await userA.getAddress(),cReth,cNuma
          );
          expect(shortfall).to.equal(0);  
          // burn half the supply, will multiply the price by 2
          let totalsupply = await numa.totalSupply();
          await numa.burn(totalsupply/BigInt(2));
          [_, collateral, shortfall,badDebt] = await comptroller.getAccountLiquidityIsolate(
            await userA.getAddress(),cReth,cNuma
          );

          console.log("************************* account liquidity **************************");
          console.log(shortfall);
          console.log(badDebt);
  
          // does not match anymore since I added some numa colateral
          //expect(shortfall).to.be.closeTo(collateralValueInrEthWei/ethers.parseEther("1"),epsilon); 
         
  
          let numaBalanceBefore = await numa.balanceOf(CNUMA_ADDRESS);
  
          // INCENTIVE
          // 10%
          await comptroller._setLiquidationIncentive(ethers.parseEther("1.10"));
          await Vault1.setMaxLiquidationsProfit(ethers.parseEther("10"));
          //let repayAmount = notTooMuchNuma/BigInt(2);

          let repayAmount = notTooMuchNuma;
          await numa.approve(VAULT1_ADDRESS,repayAmount);
  
          
          // check lending protocol balance
          let numaBalanceLiquidatorBefore = await numa.balanceOf(await owner.getAddress());
          let rethBalanceLiquidatorBefore = await rEth_contract.balanceOf(await owner.getAddress());
          // revert LIQUIDATE_SEIZE_TOO_MUCH because we want to liquidtae whole position and there is bad debt
          await expect (Vault1.liquidateNumaBorrower(await userA.getAddress(), repayAmount ,true,false)).to.be.reverted;

          // this one will not but should when bad debt liquidations will be blocked
          // check bad debt
          let numaFromREth2 = await Vault1.getBuyNumaSimulateExtract(ethers.parseEther("1"));
          console.log("how many numa with 1 rEth "+ ethers.formatEther(numaFromREth2));
          let numaBuyPriceInReth2 = (ethers.parseEther("1") * ethers.parseEther("1")) / numaFromREth2;
  
  
          // add 1 because we round up division
          numaBuyPriceInReth2 = numaBuyPriceInReth2 +BigInt(1);
          console.log('numa buy price in rEth '+ numaBuyPriceInReth2);

          let collateralValueInrEthWei2 =  (ethers.parseEther("1")*rethsupplyamount);
          let collateralValueInNumaWei2 =  collateralValueInrEthWei2 / numaBuyPriceInReth2;

          // 2 reth collateral, 120 000 numa borrowed
          // numa price x 2

          // collateral equals 100 000 numa
          // bad debt = 20 000 numa


          let badDebtEstim = notTooMuchNuma - collateralValueInNumaWei2;
          badDebt = (ethers.parseEther("1")*badDebt)/ numaBuyPriceInReth2;// in numa

          // TODOTEST4
          expect(badDebt).to.be.closeTo(badDebtEstim,epsilon);
         
          let borrowNumaBalance = await cNuma.borrowBalanceStored(await userA.getAddress());
          repayAmount = (borrowNumaBalance)/BigInt(4);

          await expect(Vault1.liquidateNumaBorrower(await userA.getAddress(), repayAmount,false,false)).to.be.reverted;
  
          // repay bad debt custom function
          //address cTokenBorrowed, address cTokenCollateral,address borrower, uint actualRepayAmount
          let seizeTOkens = await comptroller.liquidateBadDebtCalculateSeizeTokens(CNUMA_ADDRESS,CRETH_ADDRESS,await userA.getAddress(),repayAmount);

          //expect(rethsupplyamount/BigInt(2)).equal(seizeTOkens[1]);

          // liquidate test      
          let balRethBefore = await rEth_contract.balanceOf(await owner.getAddress());
          await numa.approve(await cNuma.getAddress(),repayAmount);
          //await cNuma.liquidateBadDebt(await userA.getAddress(), repayAmount, CRETH_ADDRESS);
          let balNumaBefore = await numa.balanceOf(await owner.getAddress());
          await numa.approve(VAULT1_ADDRESS,repayAmount*BigInt(10));

          let balNumaBorrowBefore = await numa.balanceOf(await userA.getAddress());
          let balCRethBefore = await cReth.balanceOf(await userA.getAddress());

          await Vault1.liquidateBadDebt(await userA.getAddress(),250,cReth);

          let balNumaBorrowAfter = await numa.balanceOf(await userA.getAddress());

          let balCRethAfter = await cReth.balanceOf(await owner.getAddress());
          let balRethAfter = await rEth_contract.balanceOf(await owner.getAddress());
          let balNumaAfter = await numa.balanceOf(await owner.getAddress());




          [_, collateral, shortfall,badDebt] = await comptroller.getAccountLiquidityIsolate(
            await userA.getAddress(),cReth,cNuma
          );
          // tester :
          // - liquidator recoit n% de chaque position
          expect(balRethAfter - balRethBefore).equal(rethsupplyamount/BigInt(4));
          expect(balNumaBefore - balNumaAfter).equal(repayAmount);
        
          // - userA a encore 100 - n % de son collateral et 100 - n% de sa dette
          let crETHBalAfter = await cReth.balanceOf(await userA.getAddress());
          let cNumaBalAfter = await cNuma.balanceOf(await userA.getAddress());
          
          // collateral
          expect(crETHBalAfter).equal(BigInt(3)*balCRethBefore/BigInt(4));


          expect(balNumaBorrowAfter).equal(balNumaBorrowBefore);
          
 

          // - et avec 100%

          

          // - autre pair

          // - 100%


  
  
        });


    });
    describe('#Leverage', () => 
    {

      it('Leverage numa', async () => 
      {
        // TODO: here, we have vault debt. Do the same with some supply in lending protocol
      
        let numaPriceBefore = await VM.numaToEth(ethers.parseEther("1"),0);

        let suppliedAmount = ethers.parseEther("100");
        let borrowAmount = ethers.parseEther("100");
               
        let ethBorrowed =  await Vault1.getBuyNumaAmountIn(borrowAmount);
        let collateralEstimate = await getNumaCollateralValue(suppliedAmount+borrowAmount);

         // accept numa as collateral
        await comptroller.connect(userB).enterMarkets([cNuma.getAddress()]);

        await numa.connect(userB).approve(await cReth.getAddress(),suppliedAmount);
        await cReth.connect(userB).leverage(suppliedAmount,borrowAmount,cNuma);

        
        // account
        let [error,tokenbalance, borrowbalance, exchangerate] = await cReth.getAccountSnapshot(await userB.getAddress());
        let [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
          await userB.getAddress(),cNuma,cReth
        );
        
        

       
        // borrow
        expect(borrowbalance).to.be.closeTo(ethBorrowed,epsilon);
        expect(shortfall).to.equal(0);
       
        // collateral
        collateralEstimate = (collateralEstimate * ethers.parseEther(numaCollateralFactor.toString()))/ethers.parseEther("1");
        expect(collateral).to.be.closeTo(collateralEstimate - ethBorrowed,epsilon);
       
        // lending & vault balances
        let vaultBalanceAfter = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
        let vaultDebtAfter = await Vault1.getDebt();

        expect(collateral).to.be.closeTo(collateralEstimate - ethBorrowed,epsilon);


        // fees should be 1% (20% * 5)%
        let sentFees = (borrowbalance *  BigInt(10) )/ BigInt(1000);
        // as we swapped back borrowed amount, vault accounting balance is back to normal
        // but still has a debt
        expect(vaultBalanceAfter).to.be.closeTo(vaultInitialBalance - sentFees,epsilon);
        expect(vaultDebtAfter).to.be.closeTo(borrowbalance,epsilon);
        let rethBalanceAfter = await rEth_contract.balanceOf(CRETH_ADDRESS);
        
        expect(rethBalanceAfter).to.equal(0);


        let numaPriceAfter = await VM.numaToEth(ethers.parseEther("1"),0);

        // price
        expect(numaPriceAfter).to.be.above(numaPriceBefore);
        expect(numaPriceAfter).to.be.closeTo(numaPriceBefore,epsilon);


      });
      it('Leverage rEth', async () => 
      {
        let numaPriceBefore = await VM.numaToEth(ethers.parseEther("1"),0);
        // userB supply numa      
        let numasupplyamount = ethers.parseEther("200000");
        await supplyNuma(userB,numasupplyamount);

        await Vault1.setCTokens(CNUMA_ADDRESS,CRETH_ADDRESS);
        let suppliedAmount = ethers.parseEther("1");
        let borrowamount = ethers.parseEther("1");

                 
        let numaBorrowed =  await Vault1.getSellNumaAmountIn(borrowamount);
        let collateralEstimate = await getRethCollateralValue(suppliedAmount+borrowamount);



         // accept numa as collateral
        await comptroller.connect(userA).enterMarkets([cReth.getAddress()]);

        await rEth_contract.connect(userA).approve(await cNuma.getAddress(),suppliedAmount);
        await cNuma.connect(userA).leverage(suppliedAmount,borrowamount,cReth);

        // approx
        let rEthBorrowed = await Vault1.getBuyNumaAmountIn(numaBorrowed);
        // account
         let [error,tokenbalance, borrowbalance, exchangerate] = await cNuma.getAccountSnapshot(await userA.getAddress());
         let [_, collateral, shortfall] = await comptroller.getAccountLiquidityIsolate(
           await userA.getAddress(),cReth,cNuma
         );
          
          

          // borrow
          expect(borrowbalance).to.be.closeTo(numaBorrowed,epsilon2);
          expect(shortfall).to.equal(0);
         
          // collateral
          collateralEstimate = (collateralEstimate * ethers.parseEther(rEthCollateralFactor.toString()))/ethers.parseEther("1");
          expect(collateral).to.be.closeTo(collateralEstimate - rEthBorrowed,epsilon);


         
          // TODO: add tests here
          // // lending & vault balances
          // let vaultBalanceAfter = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
          // let vaultDebtAfter = await Vault1.getDebt();
  
          // expect(collateral).to.be.closeTo(collateralEstimate - ethBorrowed,epsilon);
  
          // let swappedToVault = (borrowbalance * (BigInt(1000)-await Vault1.fees()) )/ BigInt(1000);
  
          // expect(vaultBalanceAfter).to.be.closeTo(vaultInitialBalance + swappedToVault - vaultDebtAfter,epsilon);
          // expect(vaultDebtAfter).to.be.closeTo(borrowbalance,epsilon);
          // let rethBalanceAfter = await rEth_contract.balanceOf(CRETH_ADDRESS);
          
          // expect(rethBalanceAfter).to.equal(0);
  
  
          let numaPriceAfter = await VM.numaToEth(ethers.parseEther("1"),0);
  
          // price
          expect(numaPriceAfter).to.be.above(numaPriceBefore);
          expect(numaPriceAfter).to.be.closeTo(numaPriceBefore,epsilon);



      });

    });

});

