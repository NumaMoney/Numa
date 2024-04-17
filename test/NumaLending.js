


const { getPoolData, getPool, initPoolETH, addLiquidity, weth9, artifacts, swapOptions, buildTrade, SwapRouter, Token } = require("../scripts/Utils.js");
const { deployPrinterTestFixtureArbi, configArbi } = require("./fixtures/NumaTestFixture.js");
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



// ********************* Numa lending test using arbitrum fork for chainlink *************************
// deploy numa, deploy lst

// deploy vault, oracles

// deploy lending

// test borrow/repay numa/reth reth/numa
// - with/without interest rate

// - borrow from lender check UR
// - borrow from vault check UR
// - borrow from vault & lenders check UR

// - repay vault first, etc, formula

// test CFs with synthetics 

// test extract from debt

// test liquidations

// test redeem/exchange rate with and without vault debt

// test interest rates and kink when and when not Vault < CF 
// check interest rates in different configurations, check that it matches exchange rate



// test flashloan and leverage
// standart compound tests? à adapter/modifier


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
  let fakePriceOracle;
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
  let usersInitialBalance = ethers.parseEther("5");



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
    //let balanceUserBInitial = await rEth_contract.balanceOf(await userB.getAddress());
    // console.log("userb balance "+balanceUserBInitial);
    // console.log("*******************************************");

  };

  async function printAccountLiquidity(
    accountAddress,
    comptroller
  ) {
    const [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
      accountAddress
    );
    
    if (shortfall === 0n) {
      console.log("Healthy",
        "collateral=",
        ethers.formatEther(collateral),
        "shortfall=",
        ethers.formatEther(shortfall)
      );
    } else {
      console.log(
        "Underwater !!!",
        "collateral=",
        ethers.formatEther(collateral),
        "shortfall=",
        ethers.formatEther(shortfall)
      );
    }
  }

  async function initContracts() 
  {
    snapshotGlobal = await takeSnapshot();
    testData = await loadFixture(deployPrinterTestFixtureArbi);

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
    await nuAM.addNuAsset(NUUSD_ADDRESS,configArbi.PRICEFEEDETHUSD,86400);
    await nuAM.addNuAsset(NUBTC_ADDRESS,configArbi.PRICEFEEDBTCETH,86400);


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


    // *********************** NumaVault rEth **********************************
    Vault1 = await ethers.deployContract("NumaVaultMock",
    [numa_address,rETH_ADDRESS,ethers.parseEther("1"),VO_ADDRESS]);
    await Vault1.waitForDeployment();
    VAULT1_ADDRESS = await Vault1.getAddress();
    console.log('vault rETH address: ', VAULT1_ADDRESS);

    await VM.addVault(VAULT1_ADDRESS);
    await Vault1.setVaultManager(VM_ADDRESS);

    // fee address
    await Vault1.setFeeAddress(await signer3.getAddress(),false);
   

    // vault has to be allowed to mint Numa
    await numa.grantRole(roleMinter, VAULT1_ADDRESS);

    // get rEth contract 
    rEth_contract = await hre.ethers.getContractAt(ERC20abi, rETH_ADDRESS);
    
    await sendrEthAndNuma();
    await Vault1.setMaxBorrow(vaultInitialBalance);
    await Vault1.unpause();
    // *********************** Deploy lending **********************************
    comptroller = await ethers.deployContract("NumaComptroller",
    []);
    await comptroller.waitForDeployment();
    COMPTROLLER_ADDRESS = await comptroller.getAddress();
    console.log('numa comptroller address: ', COMPTROLLER_ADDRESS);
   
    numaPriceOracle = await ethers.deployContract("NumaPriceOracleNew",
    []);
    await numaPriceOracle.waitForDeployment();
    NUMA_PRICEORACLE_ADDRESS = await numaPriceOracle.getAddress();
    console.log('numa price oracle address: ', NUMA_PRICEORACLE_ADDRESS);
  
    await numaPriceOracle.setVault(VAULT1_ADDRESS);
    console.log('numaPriceOracle.setVault Done');

    // deploy fake oracle too
    fakePriceOracle = await ethers.deployContract("SimplePriceOracle",
    []);
    await fakePriceOracle.waitForDeployment();
    FAKE_PRICEORACLE_ADDRESS = await fakePriceOracle.getAddress();
    console.log('fake price oracle address: ', FAKE_PRICEORACLE_ADDRESS);



    // numa price in eth
    await fakePriceOracle.setDirectPrice(numa_address,ethers.parseEther("0.001"));
    // rETh price in eth
    await fakePriceOracle.setDirectPrice(rETH_ADDRESS,ethers.parseEther("1"));

    await comptroller._setPriceOracle(await numaPriceOracle.getAddress());
    console.log('comptroller._setPriceOracle Done');
  
    let baseRatePerYear = '20000000000000000';
    let multiplierPerYear = '180000000000000000';
    let jumpMultiplierPerYear = '4000000000000000000';
    let kink = '800000000000000000';

    rateModel = await ethers.deployContract("JumpRateModelV2",
    [baseRatePerYear,multiplierPerYear,jumpMultiplierPerYear,kink,await owner.getAddress()]);
    await rateModel.waitForDeployment();
    JUMPRATEMODELV2_ADDRESS = await rateModel.getAddress();
    console.log('rate model address: ', JUMPRATEMODELV2_ADDRESS);

    // crETH is a standart CErc20Immutable
    cReth = await ethers.deployContract("CNumaLst",
    [rETH_ADDRESS,comptroller,rateModel,'200000000000000000000000000',
    'rEth CToken','crEth',8,await owner.getAddress(),VAULT1_ADDRESS,ethers.parseEther("0.8"),ethers.parseEther("0.8")]);
    await cReth.waitForDeployment();
    CRETH_ADDRESS = await cReth.getAddress();
    console.log('crEth address: ', CRETH_ADDRESS);

    // authorizing crETh to borrow/repay from/to vault
    //await Vault1.addToLendingwl(CRETH_ADDRESS);
    cNuma = await ethers.deployContract("CNumaToken",
    [numa_address,comptroller,rateModel,'200000000000000000000000000',
    'numa CToken','cNuma',8,await owner.getAddress(),VAULT1_ADDRESS]);


    await cNuma.waitForDeployment();
    CNUMA_ADDRESS = await cNuma.getAddress();
    console.log('cNuma address: ', CNUMA_ADDRESS);
    
    await Vault1.setCTokens(CNUMA_ADDRESS,CRETH_ADDRESS);
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
  
    
    // REMOVE IR
    let IM_address = await cReth.interestRateModel();
    let IMV2 = await ethers.getContractAt("BaseJumpRateModelV2", IM_address);
    // await IMV2.updateJumpRateModel(ethers.parseEther('0.02'),ethers.parseEther('0.18')
    // ,ethers.parseEther('4'),ethers.parseEther('0.8'));
  
    console.log("cancelling interest rates");
    await IMV2.updateJumpRateModel(ethers.parseEther('0'),ethers.parseEther('0')
    ,ethers.parseEther('0'),ethers.parseEther('1'));

    
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
    //console.log("how many numa with 1 rEth "+ ethers.formatEther(numaFromREth));
    let numaBuyPriceInReth = (ethers.parseEther("1") * ethers.parseEther("1")) / numaFromREth
    // add 1 because we round up division
    numaBuyPriceInReth = numaBuyPriceInReth +BigInt(1);
    //console.log('numa buy price in rEth '+ numaBuyPriceInReth)
    // max borrow
    let collateralValueInNumaWei =  (ethers.parseEther(rEthCollateralFactor.toString())*rethsupplyamount) / numaBuyPriceInReth;
    // console.log("collateral value in numa (wei) "+collateralValueInNumaWei);
    // console.log("collateral value in numa "+ethers.formatEther(collateralValueInNumaWei));
    
    return collateralValueInNumaWei;


    // let collateralValue2 = (ethers.parseEther(rEthCollateralFactor.toString())*rethsupplyamount)/(ethers.parseEther("1"));
   

    // //let collateralValueInNumaWei2 =  await Vault1.getBuyNuma(collateralValue2);
    // let rethPrice = await Vault1.getBuyNuma(ethers.parseEther("1"));
    // let collateralValueInNumaWei2 =  (collateralValue2*ethers.parseEther("1"))/numaPrice;
    // let buyPrice =  await Vault1.getBuyNuma(ethers.parseEther("1"));
    // console.log("TEST");
    // //console.log(buyPrice);
    //console.log(collateralValueInNumaWei2);
    //console.log(collateralValueInNumaWei);

    //return collateralValueInNumaWei2;

  }

  async function getMaxBorrowReth(numasupplyamount)
  {
    let sellPrice = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("1"));
    let collateralValueInrEthWei =  ((ethers.parseEther(numaCollateralFactor.toString())*numasupplyamount) * sellPrice)/(ethers.parseEther("1")*ethers.parseEther("1"));
    return collateralValueInrEthWei;
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
        // With fake oracle
        //await comptroller._setPriceOracle(await fakePriceOracle.getAddress());
        // 
        let rethsupplyamount = ethers.parseEther("2");
        let numasupplyamount = ethers.parseEther("500000");

        await supplyReth(userA,rethsupplyamount);

        // check balance, total supply,
        let balcrEth = await cReth.balanceOf(await userA.getAddress());
        let totalSupply = await cReth.totalSupply();

        expect(totalSupply).to.equal(balcrEth);
        //  TODO: other params to validate


        // userB supply numa      
        await supplyNuma(userB,numasupplyamount);

        // TODO: validate supply

        // ******************* userA borrow numa ************************
        // TODO: pas bon car notTooMuchNuma +1 ne revert pas
        // et formule de tooMuchNuma sans le +1 reverte
        // --> pas logique

        let notTooMuchNuma = await getMaxBorrowNuma(rethsupplyamount);

        //let numaFromREth = await Vault1.getBuyNumaSimulateExtract(ethers.parseEther("1"));
        //let tooMuchNuma = ((numaFromREth *BigInt(2)* ethers.parseEther(rEthCollateralFactor.toString()))/ethers.parseEther("1")) + BigInt(1);

        // TODO: why
        let tooMuchNuma = notTooMuchNuma + BigInt(100000);

        // should revert
        await expect(cNuma.connect(userA).borrow(tooMuchNuma)).to.be.reverted;
       
        // should not revert
        await expect(cNuma.connect(userA).borrow(notTooMuchNuma)).to.not.be.reverted;

        // TODO: validate UR, interest rates, etc
      });




      it('Supply Numa, Borrow rEth from vault only', async () => 
      {
        
        let numasupplyamount = ethers.parseEther("200000");
        // userB supply numa      
        await supplyNuma(userB,numasupplyamount);


        // max borrow
        let collateralValueInrEthWei = await getMaxBorrowReth(numasupplyamount);

        // compute how much should be borrowable from vault
        let maxBorrow = await Vault1.GetMaxBorrow();
        console.log("max rEth borrow from vault "+ethers.formatEther(maxBorrow));

        // verify toomuch/nottoomuch (x2: collat and available from vault)
        let notTooMuchrEth = collateralValueInrEthWei;
        let tooMuchrEth = notTooMuchrEth+BigInt(1);
        
        await expect(cReth.connect(userB).borrow(tooMuchrEth)).to.be.reverted;
        await expect(cReth.connect(userB).borrow(notTooMuchrEth)).to.not.be.reverted;

        // TODO: validate UR, interest rates, etc
        let balanceUserB = await rEth_contract.balanceOf(await userB.getAddress());
        expect(balanceUserB).to.equal(usersInitialBalance+notTooMuchrEth);
        let vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
        console.log(vaultBalance);
        expect(vaultBalance).to.equal(vaultInitialBalance - notTooMuchrEth);
        let debt = await Vault1.getDebt();
        expect(debt).to.equal(notTooMuchrEth);

        // TODO check that numa prices are the same with debt!
      });

      it('Supply Numa, Borrow rEth from lenders', async () => 
      {
        // supply reth
        let rethsupplyamount = ethers.parseEther("2");
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
        //
        await expect(cReth.connect(userB).borrow(tooMuchrEth)).to.be.reverted;
        await expect(cReth.connect(userB).borrow(notTooMuchrEth)).to.not.be.reverted;

        // TODO: validate UR, interest rates, etc

        // TODO: check that we have borrowed from vault
        let balanceUserB = await rEth_contract.balanceOf(await userB.getAddress());
        expect(balanceUserB).to.equal(usersInitialBalance+notTooMuchrEth);
        let vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
        console.log(vaultBalance);
        expect(vaultBalance).to.equal(vaultInitialBalance);

        let debt = await Vault1.getDebt();
        expect(debt).to.equal(BigInt(0));

            
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
        await expect(cReth.connect(userB).borrow(notTooMuchrEth)).to.not.be.reverted;

        // TODO: validate UR, interest rates, etc

        // TODO: check that we have borrowed from vault
        let balanceUserB = await rEth_contract.balanceOf(await userB.getAddress());
        
        console.log(balanceUserB);
        console.log(usersInitialBalance+notTooMuchrEth);
        expect(balanceUserB).to.equal(usersInitialBalance+notTooMuchrEth);
        let vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
        
        expect(vaultBalance).to.equal(vaultInitialBalance - notTooMuchrEth+rethsupplyamount);

        let debt = await Vault1.getDebt();
        expect(debt).to.equal(notTooMuchrEth - rethsupplyamount);        
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

          console.log(notTooMuchNuma);

          //printAccountLiquidity(await userA.getAddress(),comptroller);

          let [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
            await userA.getAddress()
          );
          
          expect(shortfall).to.equal(0);  
          expect(collateral).to.be.closeTo(0,epsilon);
      
          let halfBorrow = notTooMuchNuma/BigInt(2);

          await numa.connect(userA).approve(await cNuma.getAddress(),halfBorrow);

          // const allowance = await numa.allowance(await userA.getAddress(), await cNuma.getAddress());
          // expect(allowance).to.equal(halfBorrow);

          console.log(halfBorrow);
          await cNuma.connect(userA).repayBorrow(halfBorrow);
          [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
            await userA.getAddress()
          );

         
          printAccountLiquidity(await userA.getAddress(),comptroller);
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
          let [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
            await userB.getAddress()
          );
          
          expect(shortfall).to.equal(0);  
          expect(collateral).to.be.closeTo(0,epsilon);
      
          let halfBorrow = notTooMuchrEth/BigInt(2);
          await rEth_contract.connect(userB).approve(await cReth.getAddress(),halfBorrow);


          await cReth.connect(userB).repayBorrow(halfBorrow);
          [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
            await userB.getAddress()
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

          let vaultBalanceAfterBorrow = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
        
          expect(vaultBalanceAfterBorrow).to.equal(vaultInitialBalance +rethsupplyamount - notTooMuchrEth);

          let debtAfterBorrow = await Vault1.getDebt();
          expect(debtAfterBorrow).to.equal(notTooMuchrEth - rethsupplyamount);


          let [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
            await userB.getAddress()
          );
          
          expect(shortfall).to.equal(0);  
          expect(collateral).to.be.closeTo(0,epsilon);
      
          let halfBorrow = notTooMuchrEth/BigInt(2);
          await rEth_contract.connect(userB).approve(await cReth.getAddress(),halfBorrow);


          await cReth.connect(userB).repayBorrow(halfBorrow);

         
          // validate repay
          [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
            await userB.getAddress()
          );
        
          expect(shortfall).to.equal(0);  
          let halfCollat = collateralValueInrEthWei/BigInt(2);
          expect(collateral).to.be.closeTo(halfCollat,epsilon);

          // if target UR = 80%
          let [error,tokenbalance, borrowbalance, exchangerate] = await cReth.getAccountSnapshot(await userB.getAddress());
          console.log(tokenbalance);
          console.log(borrowbalance);
          console.log(exchangerate);
          let cashneeded = borrowbalance / BigInt(4);
          console.log(cashneeded);

          let remainingcash = notTooMuchrEth - halfBorrow;
          let cashavailableforvault = remainingcash - cashneeded;
          // 80/20 --> 4/5
          let cashTransferToVault = (cashavailableforvault * BigInt(4))/BigInt(5);


          let lendingBalanceAfterRepay = await rEth_contract.balanceOf(await CRETH_ADDRESS);
          expect(lendingBalanceAfterRepay).to.equal(lendingBalanceAfterBorrow + halfBorrow - cashTransferToVault);  

          // check vault
          let vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
        
          expect(vaultBalance).to.equal(vaultBalanceAfterBorrow + cashTransferToVault);
  
          let debt = await Vault1.getDebt();
          expect(debt).to.equal(debtAfterBorrow - cashTransferToVault);        

        
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
            console.log("borrowing "+notTooMuchrEth);
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
  
  
            let [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
              await userB.getAddress()
            );
            
            expect(shortfall).to.equal(0);  
            expect(collateral).to.be.closeTo(0,epsilon);
        
            let repayBorrow = notTooMuchrEth/BigInt(8);
            await rEth_contract.connect(userB).approve(await cReth.getAddress(),repayBorrow);
  
  
            await cReth.connect(userB).repayBorrow(repayBorrow);
  
            
  
            // if target UR = 80%
            let [error,tokenbalance, borrowbalance, exchangerate] = await cReth.getAccountSnapshot(await userB.getAddress());
            console.log(tokenbalance);
            console.log(borrowbalance);
            console.log(exchangerate);
            let cashneeded = borrowbalance / BigInt(4);
            console.log(cashneeded);
  
  
            let lendingBalanceAfterRepay = await rEth_contract.balanceOf(await CRETH_ADDRESS);
            expect(lendingBalanceAfterRepay).to.equal(lendingBalanceAfterBorrow + repayBorrow);  
  
            // check vault
            let vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
          
            expect(vaultBalance).to.equal(vaultBalanceAfterBorrow);
    
            let debt = await Vault1.getDebt();
            expect(debt).to.equal(debtAfterBorrow);  
        });

        it('Borrow rEth, already at target UR repay rEth to lenders and vault', async () => 
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
            console.log("borrowing "+notTooMuchrEth);
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
  
  
            let [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
              await userB.getAddress()
            );
            
            expect(shortfall).to.equal(0);  
            expect(collateral).to.be.closeTo(0,epsilon);
        
            let halfBorrow = notTooMuchrEth/BigInt(2);
            await rEth_contract.connect(userB).approve(await cReth.getAddress(),halfBorrow);
  
  
            await cReth.connect(userB).repayBorrow(halfBorrow);
  
           
            // validate repay
            [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
              await userB.getAddress()
            );
            printAccountLiquidity(await userB.getAddress(),comptroller);
            expect(shortfall).to.equal(0);  
            let halfCollat = collateralValueInrEthWei/BigInt(2);
            expect(collateral).to.be.closeTo(halfCollat,epsilon);
  
            // if target UR = 80%
            let [error,tokenbalance, borrowbalance, exchangerate] = await cReth.getAccountSnapshot(await userB.getAddress());
            console.log(tokenbalance);
            console.log(borrowbalance);
            console.log(exchangerate);
            let cashneeded = borrowbalance / BigInt(4);
            console.log(cashneeded);
  
            let remainingcash = notTooMuchrEth - halfBorrow;
            let cashavailableforvault = remainingcash - cashneeded;
            // 80/20 --> 4/5
            let cashTransferToVault = (cashavailableforvault * BigInt(4))/BigInt(5);
  
  
            let lendingBalanceAfterRepay = await rEth_contract.balanceOf(await CRETH_ADDRESS);
            expect(lendingBalanceAfterRepay).to.equal(lendingBalanceAfterBorrow + halfBorrow - cashTransferToVault);  
  
            // check vault
            let vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
          
            expect(vaultBalance).to.equal(vaultBalanceAfterBorrow + cashTransferToVault);
    
            let debt = await Vault1.getDebt();
            expect(debt).to.equal(debtAfterBorrow - cashTransferToVault); 


            // repay again we should have 80/20 because already at 80%UR
            
            let repayBorrow = notTooMuchrEth/BigInt(4);
            await rEth_contract.connect(userB).approve(await cReth.getAddress(),repayBorrow);
  
  
            await cReth.connect(userB).repayBorrow(repayBorrow);
  
           
            // 0.8 for vault (4/5)
            let repayBorrowVault = (repayBorrow*BigInt(4))/BigInt(5);
            // cn not repay more than debt
            if (repayBorrowVault > debt)
            {
              repayBorrowVault = debt;
            }
            let repayBorrowLenders = repayBorrow - repayBorrowVault;
            let lendingBalanceAfterRepay2 = await rEth_contract.balanceOf(await CRETH_ADDRESS);
            expect(lendingBalanceAfterRepay2).to.equal(lendingBalanceAfterRepay+repayBorrowLenders);  
  
            // check vault
            let vaultBalance2 = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
          
            expect(vaultBalance2).to.equal(vaultBalance+repayBorrowVault);
    
            let debt2 = await Vault1.getDebt();
            expect(debt2).to.equal(debt - repayBorrowVault); 

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

          console.log(numaBalanceBefore);
          console.log(cnumaBalanceBefore);

          let numaBalanceAfter = await numa.balanceOf(await userB.getAddress());
          let cnumaBalanceAfter = await cNuma.balanceOf(await userB.getAddress());

          console.log(numaBalanceAfter);
          console.log(cnumaBalanceAfter);

          expect(numaBalanceAfter).to.equal(numaBalanceBefore - numasupplyamount); 

          
          // TODO: add again
          expect(cNuma.connect(userB).redeemUnderlying(numasupplyamount + BigInt(1))).to.be.reverted;
          await cNuma.connect(userB).redeemUnderlying(numasupplyamount - BigInt(1));



          let numaBalanceAfterRedeem = await numa.balanceOf(await userB.getAddress());
          let cnumaBalanceAfterRedeem = await cNuma.balanceOf(await userB.getAddress());

          console.log(numaBalanceAfterRedeem);
          console.log(cnumaBalanceAfterRedeem);


          expect(cnumaBalanceAfterRedeem).to.be.closeTo(0,epsilon); 
          expect(numaBalanceAfterRedeem).to.be.closeTo(numaBalanceBefore,epsilon); 

        });

        it('Supply&redeem rEth', async () => 
        {
          let rethBalanceBefore = await rEth_contract.balanceOf(await userA.getAddress());
          let crethBalanceBefore = await cReth.balanceOf(await userA.getAddress());
          let rethSupplyAmount = ethers.parseEther("3");

          await supplyReth(userA,rethSupplyAmount);


          let rethBalanceAfter = await rEth_contract.balanceOf(await userA.getAddress());
          let crethBalanceAfter = await cReth.balanceOf(await userA.getAddress());


          expect(rethBalanceAfter).to.equal(rethBalanceBefore - rethSupplyAmount); 

          
          // TODO: add again
          expect(cReth.connect(userA).redeemUnderlying(rethSupplyAmount + BigInt(1))).to.be.reverted;
          await cReth.connect(userA).redeemUnderlying(rethSupplyAmount - BigInt(1));



          let rethBalanceAfterRedeem = await rEth_contract.balanceOf(await userA.getAddress());
          let crethBalanceAfterRedeem = await cReth.balanceOf(await userA.getAddress());

          expect(crethBalanceAfterRedeem).to.be.closeTo(0,epsilon); 
          expect(rethBalanceAfterRedeem).to.be.closeTo(rethBalanceBefore,epsilon); 

        });

    });

    describe('#Vault collateral factor', () => 
    {
      // limite du borrow possible

      // with/without synthetics --> check that borrows are limited (borrow should revert)
      // autres?      


    });


    
    describe('#Interest rates', () => 
    {

      // kink when vault CF is reached
    


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
        // console.log("vault debt");
        // console.log(debt);

        let rewardsFromDebt = await Vault1.rewardsFromDebt();
        // console.log("rewards from debt before");
        // console.log(rewardsFromDebt);
        await Vault1.extractRewards();
       
        rewardsFromDebt = await Vault1.rewardsFromDebt();
        // console.log("rewards from debt after");
        // console.log(rewardsFromDebt);
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
        // KO
        //expect(debtAfter).to.equal(debtBefore - halfBorrow);
        // TODO check reward from dbt
        // TODO check total reward balance

      //  // printAccountLiquidity(await userB.getAddress(),comptroller);

      //   rewardsFromDebt = await Vault1.rewardsFromDebt();
      //   console.log("rewards from debt after repay");
      //   console.log(rewardsFromDebt);

      //   debt = await Vault1.getDebt();
      //   console.log("vault debt");
      //   console.log(debt);
      });

    });

    describe('#Liquidations', () => 
    {
      // Add liquidation function.
      it('Borrow numa, change price, liquidate simple', async () => 
      {
      // 1. standart liquidate numa borrowers
        // approve
        let rethsupplyamount = ethers.parseEther("2");
        await rEth_contract.connect(userA).approve(await cReth.getAddress(),rethsupplyamount);
        await cReth.connect(userA).mint(rethsupplyamount);
        // check balance, total supply,
        let balcrEth = await cReth.balanceOf(await userA.getAddress());
        let exchangeRate = BigInt(await cReth.exchangeRateStored());
     
        let totalSupply = await cReth.totalSupply();

        expect(totalSupply).to.equal(balcrEth);
        //  TODO: other params to validate


        // userB supply numa 
        let numasupplyamount = ethers.parseEther("200000");
        await numa.connect(userB).approve(await cNuma.getAddress(),numasupplyamount);

        // 
        //await comptroller.connect(userA).enterMarkets([cReth.getAddress()]);
        await cNuma.connect(userB).mint(numasupplyamount);

        // ******************* userA borrow numa ************************

        // userA will deposit numa and borrow rEth
        // accept rEth as collateral
        await comptroller.connect(userA).enterMarkets([cReth.getAddress()]);



        // with vault using real vault price (called from vault to compare)
        let refValueWei = await Vault1.last_lsttokenvalueWei();
        let numaPrice = await VM.numaToToken(ethers.parseEther("1"),refValueWei,ethers.parseEther("1"));
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

        printAccountLiquidity(await userA.getAddress(),comptroller);

        [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
          await userA.getAddress()
        );
        expect(shortfall).to.equal(0);  
        // double the supply, will multiply the price by 2
        let totalsupply = await numa.totalSupply();
        await numa.burn(totalsupply/BigInt(2));
        [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
          await userA.getAddress()
        );

        expect(shortfall).to.be.closeTo(collateralValueInrEthWei/ethers.parseEther("1"),epsilon); 
       
        printAccountLiquidity(await userA.getAddress(),comptroller);

        //let rethBalanceBefore = await rEth_contract.balanceOf(await owner.getAddress());

        let numaBalanceBefore = await numa.balanceOf(CNUMA_ADDRESS);

        // INCENTIVE
        // 10%
        await comptroller._setLiquidationIncentive(ethers.parseEther("1.10"));
        
        let repayAmount = notTooMuchNuma/BigInt(2);
        await numa.approve(await cNuma.getAddress(),repayAmount);
        await cNuma.liquidateBorrow(await userA.getAddress(), repayAmount,cReth) ;

        printAccountLiquidity(await userA.getAddress(),comptroller);

        //
        // check new shortfall
        [_, collateral2, shortfall2] = await comptroller.getAccountLiquidity(
          await userA.getAddress()
        );

        // how much collateral should we get
        numaFromREth = await Vault1.getBuyNumaSimulateExtract(ethers.parseEther("1"));
        numaBuyPriceInReth = (ethers.parseEther("1") * ethers.parseEther("1")) / numaFromREth;


        // add 1 because we round up division
        numaBuyPriceInReth = numaBuyPriceInReth +BigInt(1);


        let borrowRepaidReth = (repayAmount*numaBuyPriceInReth)/ethers.parseEther("1");
        console.log(ethers.formatEther(borrowRepaidReth));
        // add discount
        let expectedCollatReceived = (BigInt(110) * borrowRepaidReth) / BigInt(100)

        console.log(ethers.formatEther(expectedCollatReceived));


        expect(shortfall2).to.be.closeTo(shortfall - borrowRepaidReth +(ethers.parseEther(rEthCollateralFactor.toString())*expectedCollatReceived)/(ethers.parseEther("1")),epsilon2);
        // check received balance equals equivalent collateral + discount


        let crethBalanceAfter = await cReth.balanceOf(await owner.getAddress());
        console.log(crethBalanceAfter);
        let exchangeRateStored = await cReth.exchangeRateStored();
        console.log("exchange rate "+exchangeRateStored);
        let crethReceived = ((expectedCollatReceived*ethers.parseEther("1"))/exchangeRateStored);
        //protocolSeizeShareMantissa = 2.8%
        crethReceived = crethReceived - (BigInt(28)*crethReceived)/BigInt(1000);
        
        //expect(crethBalanceAfter).to.equal((expectedCollatReceived*exchangeRateStored)/ethers.parseEther("1")); 
        expect(crethBalanceAfter).to.be.closeTo(crethReceived,epsilon2); 

        // check lending protocol balance
        let numaBalanceAfter = await numa.balanceOf(CNUMA_ADDRESS);
        expect(numaBalanceAfter).to.equal(numaBalanceBefore + repayAmount);
        // check vault debt
        let debt = await Vault1.getDebt();
        expect(debt).to.equal(0);


      });

      // 2. standart liquidate rEth borrowers
      it('Borrow rEth, change price, liquidate simple', async () => 
      {
        // remove fees for checks
        await Vault1.setBuyFee(1000);
        await Vault1.setSellFee(1000);
        await Vault1.setFee(0);

        // supply reth
        let rethsupplyamount = ethers.parseEther("1");
        await rEth_contract.connect(userA).approve(await cReth.getAddress(),rethsupplyamount);
        await cReth.connect(userA).mint(rethsupplyamount);
        // supply numa
        // userB supply numa 
        let numasupplyamount = ethers.parseEther("200000");
        await numa.connect(userB).approve(await cNuma.getAddress(),numasupplyamount);
        // mint cNuma
        await cNuma.connect(userB).mint(numasupplyamount);
        // use it to borrow rEth
        await comptroller.connect(userB).enterMarkets([cNuma.getAddress()]);
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
        console.log("borrowing "+notTooMuchrEth);
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
        let [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
          await userB.getAddress()
        );
        
        expect(shortfall).to.equal(0);  
        expect(collateral).to.be.closeTo(0,epsilon);

        printAccountLiquidity(await userB.getAddress(),comptroller);
        // make it liquiditable by dividing numa price by 2
        // double the supply, will multiply the price by 2
        let totalsupply = await numa.totalSupply();
        await numa.mint(await owner.getAddress(),totalsupply);
        [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
          await userB.getAddress()
        );
        let sellPriceNew = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("1"));
        printAccountLiquidity(await userB.getAddress(),comptroller);

  
        expect(shortfall).to.be.closeTo(collateralValueInrEthWei/BigInt(2),epsilon); 
         
        let rethBalanceBefore = await rEth_contract.balanceOf(CRETH_ADDRESS);
        // INCENTIVE
        // 10%
        await comptroller._setLiquidationIncentive(ethers.parseEther("1.10"));
        
        let repayAmount = notTooMuchrEth/BigInt(2);
        await rEth_contract.approve(await cReth.getAddress(),repayAmount);
        await cReth.liquidateBorrow(await userB.getAddress(), repayAmount,cNuma) ;

        printAccountLiquidity(await userB.getAddress(),comptroller);
        
        console.log("repay amount "+ethers.formatEther(repayAmount));
        console.log("new sell price "+ethers.formatEther(sellPriceNew));
        // how much collateral should we get
        let borrowRepaidNuma = (repayAmount * ethers.parseEther("1")/sellPriceNew);
        console.log("how much collateral should we get "+borrowRepaidNuma);
        // add discount
        let expectedCollatReceived = (BigInt(110) * borrowRepaidNuma) / BigInt(100);
        let expectedCollatReceivedrEth = (BigInt(110) * repayAmount) / BigInt(100)
   
        console.log(expectedCollatReceived);
        [_, collateral2, shortfall2] = await comptroller.getAccountLiquidity(
          await userB.getAddress()
        );

        expect(shortfall2).to.be.closeTo(shortfall - repayAmount +(ethers.parseEther(numaCollateralFactor.toString())*expectedCollatReceivedrEth)/(ethers.parseEther("1")),epsilon2);

        // check received balance equals equivalent collateral + discount
   
   
        let cnumaBalanceAfter = await cNuma.balanceOf(await owner.getAddress());
        console.log("cnuma balance "+cnumaBalanceAfter);
        let exchangeRateStored = await cNuma.exchangeRateStored();
        console.log("exchange rate "+exchangeRateStored);
        let cnumaReceived = ((expectedCollatReceived*ethers.parseEther("1"))/exchangeRateStored);
        //protocolSeizeShareMantissa = 2.8%
        cnumaReceived = cnumaReceived - (BigInt(28)*cnumaReceived)/BigInt(1000);
       
        console.log(cnumaReceived);
        expect(cnumaBalanceAfter).to.be.closeTo(cnumaReceived,epsilon2); 
   
        // check lending protocol balance
        // if target UR = 80%
        let [error,tokenbalance, borrowbalance, exchangerate] = await cReth.getAccountSnapshot(await userB.getAddress());
        console.log(tokenbalance);
        console.log(borrowbalance);
        console.log(exchangerate);
        let cashneeded = borrowbalance / BigInt(4);
        console.log(cashneeded);
        let halfBorrow = notTooMuchrEth/BigInt(2);
        let remainingcash = notTooMuchrEth - halfBorrow;
        let cashavailableforvault = remainingcash - cashneeded;
        // 80/20 --> 4/5
        let cashTransferToVault = (cashavailableforvault * BigInt(4))/BigInt(5);
        let lendingBalanceAfterRepay = await rEth_contract.balanceOf(await CRETH_ADDRESS);
        expect(lendingBalanceAfterRepay).to.equal(lendingBalanceAfterBorrow + halfBorrow - cashTransferToVault);  
        // check vault
        let vaultBalance = await rEth_contract.balanceOf(await VAULT1_ADDRESS);
      
        expect(vaultBalance).to.equal(vaultBalanceAfterBorrow + cashTransferToVault);

        let debt = await Vault1.getDebt();
        expect(debt).to.equal(debtAfterBorrow - cashTransferToVault); 

      });

      // 3. custom liquidate numa borrowers
      it('Borrow numa, change price, liquidate flashloan', async () => 
      {
        // remove fees for checks
        await Vault1.setBuyFee(1000);
        await Vault1.setSellFee(1000);
        await Vault1.setFee(0);

        // supply
        let rethsupplyamount = ethers.parseEther("2");
        let numasupplyamount = ethers.parseEther("200000");

      
        await supplyReth(userA,rethsupplyamount);
        await supplyNuma(userB,numasupplyamount);
    
        let collateralValueInNumaWei = await getMaxBorrowNuma(rethsupplyamount);
        let notTooMuchNuma = collateralValueInNumaWei;


        await expect(cNuma.connect(userA).borrow(notTooMuchNuma)).to.not.be.reverted;

        [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
          await userA.getAddress()
        );
        expect(shortfall).to.equal(0);  
        // double the supply, will multiply the price by 2
        let totalsupply = await numa.totalSupply();
        await numa.burn(totalsupply/BigInt(2));
        let numPriceBefore = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("1"));
        [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
          await userA.getAddress()
        );

        expect(shortfall).to.be.closeTo(rethsupplyamount*ethers.parseEther(rEthCollateralFactor.toString())/ethers.parseEther("1"),epsilon); 
        
     

        let numaBalanceBefore = await numa.balanceOf(CNUMA_ADDRESS);

        let liquidatorNumaBalanceBefore = await numa.balanceOf(await owner.getAddress());
        let numaSupplyBefore = await numa.totalSupply();
        // INCENTIVE
        // 10%
        await comptroller._setLiquidationIncentive(ethers.parseEther("1.10"));
        
        let repayAmount = notTooMuchNuma/BigInt(2);
 
        await Vault1.setMaxLiquidationsProfit(ethers.parseEther("10000000"));
        await Vault1.liquidateNumaBorrowerFlashloan(await userA.getAddress(), repayAmount,cReth,cNuma);


        //
        // check new shortfall
        [_, collateral2, shortfall2] = await comptroller.getAccountLiquidity(
          await userA.getAddress()
        );

        // how much collateral should we get
        let numaFromREth = await Vault1.getBuyNumaSimulateExtract(ethers.parseEther("1"));
        let numaBuyPriceInReth = (ethers.parseEther("1") * ethers.parseEther("1")) / numaFromREth;


        // add 1 because we round up division
        numaBuyPriceInReth_plusOne = numaBuyPriceInReth +BigInt(1);
        let borrowRepaidReth = (repayAmount*numaBuyPriceInReth_plusOne)/ethers.parseEther("1");
        let collatRepaidReth = (repayAmount*numaBuyPriceInReth)/ethers.parseEther("1");
        //let borrowRepaidRethBefore = (repayAmount*numaBuyPriceInRethBefore)/ethers.parseEther("1");
        console.log(ethers.formatEther(borrowRepaidReth));
        // add discount
        let expectedCollatReceived = (BigInt(110) * collatRepaidReth) / BigInt(100);
        // liquidator should get 10%
        let expectedCollatReceivedNuma = (BigInt(10) * repayAmount) / BigInt(100);

        console.log(ethers.formatEther(expectedCollatReceived));

        
        expect(shortfall2).to.be.closeTo(shortfall - borrowRepaidReth +(ethers.parseEther(rEthCollateralFactor.toString())*expectedCollatReceived)/(ethers.parseEther("1")),epsilon2);
       
        // check lending protocol balance
        let numaBalanceAfter = await numa.balanceOf(CNUMA_ADDRESS);
        expect(numaBalanceAfter).to.equal(numaBalanceBefore + repayAmount);
        // check vault debt
        let debt = await Vault1.getDebt();
        expect(debt).to.equal(0);

        let liquidatorNumaBalanceAfter = await numa.balanceOf(await owner.getAddress());
    
        let liquidatorProfit = liquidatorNumaBalanceAfter - liquidatorNumaBalanceBefore;
        expect(liquidatorProfit).to.be.closeTo(expectedCollatReceivedNuma,epsilon2);

        // check numa price is the same
        let numPriceAfter = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("1"));
        expect(numPriceAfter).to.be.closeTo(numPriceBefore,epsilon);
        
        
      });
     
      it('Borrow rEth, change price, liquidate flashloan', async () => 
      {
        // remove fees for checks
        await Vault1.setBuyFee(1000);
        await Vault1.setSellFee(1000);
        await Vault1.setFee(0);

        // supply reth
        let rethsupplyamount = ethers.parseEther("1");
        await rEth_contract.connect(userA).approve(await cReth.getAddress(),rethsupplyamount);
        await cReth.connect(userA).mint(rethsupplyamount);
        // supply numa
        // userB supply numa 
        let numasupplyamount = ethers.parseEther("200000");
        await numa.connect(userB).approve(await cNuma.getAddress(),numasupplyamount);
        // mint cNuma
        await cNuma.connect(userB).mint(numasupplyamount);
        // use it to borrow rEth
        await comptroller.connect(userB).enterMarkets([cNuma.getAddress()]);
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
        console.log("borrowing "+notTooMuchrEth);
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
        //
        let [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
          await userB.getAddress()
        );
        
        expect(shortfall).to.equal(0);  
        expect(collateral).to.be.closeTo(0,epsilon);

        printAccountLiquidity(await userB.getAddress(),comptroller);
        // make it liquiditable by dividing numa price by 2
        // double the supply, will multiply the price by 2
        let totalsupply = await numa.totalSupply();
        await numa.mint(await owner.getAddress(),totalsupply);
        [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
          await userB.getAddress()
        );
        let sellPriceNew = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("1"));
        printAccountLiquidity(await userB.getAddress(),comptroller);

  
        expect(shortfall).to.be.closeTo(collateralValueInrEthWei/BigInt(2),epsilon); 
         
        let rethBalanceBefore = await rEth_contract.balanceOf(CRETH_ADDRESS);
        // INCENTIVE
        // 10%
        await comptroller._setLiquidationIncentive(ethers.parseEther("1.10"));
        
        let repayAmount = notTooMuchrEth/BigInt(2);
        await rEth_contract.approve(await cReth.getAddress(),repayAmount);
        //await cReth.liquidateBorrow(await userB.getAddress(), repayAmount,cNuma) ;
        await Vault1.liquidateLstBorrowerFlashloan(await userB.getAddress(), repayAmount,cNuma,cReth);
        printAccountLiquidity(await userB.getAddress(),comptroller);
        
        console.log("repay amount "+ethers.formatEther(repayAmount));
        console.log("new sell price "+ethers.formatEther(sellPriceNew));
        // how much collateral should we get
        let borrowRepaidNuma = (repayAmount * ethers.parseEther("1")/sellPriceNew);
        console.log("how much collateral should we get "+borrowRepaidNuma);
        // add discount
        let expectedCollatReceived = (BigInt(110) * borrowRepaidNuma) / BigInt(100);
        let expectedCollatReceivedrEth = (BigInt(110) * repayAmount) / BigInt(100)
    
        console.log(expectedCollatReceived);
        [_, collateral2, shortfall2] = await comptroller.getAccountLiquidity(
          await userB.getAddress()
        );

        expect(shortfall2).to.be.closeTo(shortfall - repayAmount +(ethers.parseEther(numaCollateralFactor.toString())*expectedCollatReceivedrEth)/(ethers.parseEther("1")),epsilon2);


        

      });


    });
    describe('#Leverage', () => 
    {

      it('Leverage numa', async () => 
      {
        // let numaAmountFromLst = await Vault1.getBuyNuma(BigInt(1052631578947368));
        // console.log(numaAmountFromLst);

        // let rEthAmountFromNumaOut = await Vault1.getBuyNumaAmountIn(numaAmountFromLst);
        // console.log(rEthAmountFromNumaOut);


        //         let lstAmountFromNuma = await Vault1.getSellNuma(ethers.parseEther("100123456"));
        // console.log(lstAmountFromNuma);

        // let NumaAmountFromRethOut = await Vault1.getSellNumaAmountIn(lstAmountFromNuma);
        // console.log(ethers.formatEther(NumaAmountFromRethOut));

      
        let suppliedAmount = ethers.parseEther("100");
        let totalAmount = ethers.parseEther("200");
         // accept numa as collateral
        await comptroller.connect(userB).enterMarkets([cNuma.getAddress()]);

        await numa.connect(userB).approve(await cReth.getAddress(),suppliedAmount);
        await cReth.connect(userB).leverage(suppliedAmount,totalAmount,cNuma);


        // TODO: checks
        // TODO: check also numa price is nearly the same (no balance issue)
      });
      it('Leverage rEth', async () => 
      {
        // userB supply numa      
        let numasupplyamount = ethers.parseEther("200000");
        await supplyNuma(userB,numasupplyamount);

        await Vault1.setCTokens(CNUMA_ADDRESS,CRETH_ADDRESS);
        let suppliedAmount = ethers.parseEther("1");
        let totalAmount = ethers.parseEther("2");
         // accept numa as collateral
        await comptroller.connect(userA).enterMarkets([cReth.getAddress()]);

        await rEth_contract.connect(userA).approve(await cNuma.getAddress(),suppliedAmount);
        await cNuma.connect(userA).leverage(suppliedAmount,totalAmount,cReth);
      });

    });

});

