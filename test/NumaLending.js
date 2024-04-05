


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
const epsilon = ethers.parseEther('0.0000000001');


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
   // sends rETH to the vault and to users
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
    let balanceUserBInitial = await rEth_contract.balanceOf(await userB.getAddress());
    console.log("userb balance "+balanceUserBInitial);
    console.log("*******************************************");

  };

  after(async function () {
    await snapshotGlobal.restore();
  });


  afterEach(async function () {
    console.log("****************** restoresnapshot *************************");

    await snapshot.restore();

    let balanceUserBInitial = await rEth_contract.balanceOf(await userB.getAddress());
    console.log("userb balance "+balanceUserBInitial);
    console.log("*******************************************");
    snapshot = await takeSnapshot();

  })



  before(async function () 
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


    // VO2 = await ethers.deployContract("VaultOracleSingle",
    // [wstETH_ADDRESS,wstETH_FEED,50*86400,UPTIME_FEED]);
    // await VO2.waitForDeployment();
    // VO_ADDRESS2= await VO2.getAddress();
    // console.log('vault 2 oracle address: ', VO_ADDRESS2);

    // *********************** NumaVault rEth **********************************
    Vault1 = await ethers.deployContract("NumaVault",
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
    'rEth CToken','crEth',8,await owner.getAddress(),VAULT1_ADDRESS]);
    await cReth.waitForDeployment();
    CRETH_ADDRESS = await cReth.getAddress();
    console.log('crEth address: ', CRETH_ADDRESS);

    // cNuma is custom
    cNuma = await ethers.deployContract("CNumaLst",
    [numa_address,comptroller,rateModel,'200000000000000000000000000',
    'numa CToken','cNuma',8,await owner.getAddress(),VAULT1_ADDRESS]);
    await cNuma.waitForDeployment();
    CNUMA_ADDRESS = await cNuma.getAddress();
    console.log('cNuma address: ', CNUMA_ADDRESS);


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
  
    
  // // FOR DEBUG REMOVE IR
  // let IM_address = await cNuma.interestRateModel();
  // let IMV2 = await ethers.getContractAt("BaseJumpRateModelV2", IM_address);
  // // await IMV2.updateJumpRateModel(ethers.parseEther('0.02'),ethers.parseEther('0.18')
  // // ,ethers.parseEther('4'),ethers.parseEther('0.8'));
  
  // console.log("cancelling interest rates");
  // await IMV2.updateJumpRateModel(ethers.parseEther('0'),ethers.parseEther('0')
  // ,ethers.parseEther('0'),ethers.parseEther('1'));
  
  snapshot = await takeSnapshot();

  

     
  });
  describe('#Supply & Borrow', () => 
  {
      // getting prices should revert if vault is empty 
      it('Supply rEth, Borrow numa fake oracle', async () => 
      {
        // approve
        let rethsupplyamount = ethers.parseEther("2");
        await rEth_contract.connect(userA).approve(await cReth.getAddress(),rethsupplyamount);
        await cReth.connect(userA).mint(rethsupplyamount);
        // check balance, total supply,
        let balcrEth = await cReth.balanceOf(await userA.getAddress());
        let exchangeRate = BigInt(await cReth.exchangeRateStored());
        // console.log(rethsupplyamount);
        // console.log(exchangeRate);
        // TODO: understand exchange rate
        // let expectedBal = (rethsupplyamount)/exchangeRate;
        // expect(balcrEth).to.equal(expectedBal);

        let totalSupply = await cReth.totalSupply();

        expect(totalSupply).to.equal(balcrEth);
        //  TODO: other params to validate


        // userB supply numa 
        let numasupplyamount = ethers.parseEther("50000");
        await numa.connect(userB).approve(await cNuma.getAddress(),numasupplyamount);

        // 
        //await comptroller.connect(userA).enterMarkets([cReth.getAddress()]);


        await cNuma.connect(userB).mint(numasupplyamount);

        // TODO: validate supply

        // ******************* userA borrow numa ************************

        // userA will deposit numa and borrow rEth
        // accept rEth as collateral
        await comptroller.connect(userA).enterMarkets([cReth.getAddress()]);



        // With fake oracle
        await comptroller._setPriceOracle(await fakePriceOracle.getAddress());

        // 2 reth --> equivalent à 2000 numa --> 0.6 * 2000 (collateralFactor) = 1200
        let tooMuchNuma = ethers.parseEther("1201");

        let liquidity = await comptroller.getHypotheticalAccountLiquidity(
          await userA.getAddress(),
          await cNuma.getAddress(),
          0,
          tooMuchNuma);

        console.log(liquidity);


        // should revert
        await expect(cNuma.connect(userA).borrow(tooMuchNuma)).to.be.reverted;
       
        // should not revert
        let notTooMuchNuma = ethers.parseEther("1200");
        await expect(cNuma.connect(userA).borrow(notTooMuchNuma)).to.not.be.reverted;


        // TODO: validate UR, interest rates, etc

 
      });

      it('Supply rEth, Borrow numa with vault prices', async () => 
      {
        // approve
        let rethsupplyamount = ethers.parseEther("2");
        await rEth_contract.connect(userA).approve(await cReth.getAddress(),rethsupplyamount);
        await cReth.connect(userA).mint(rethsupplyamount);
        // check balance, total supply,
        let balcrEth = await cReth.balanceOf(await userA.getAddress());
        let exchangeRate = BigInt(await cReth.exchangeRateStored());
        // console.log(rethsupplyamount);
        // console.log(exchangeRate);
        // TODO: understand exchange rate
        // let expectedBal = (rethsupplyamount)/exchangeRate;
        // expect(balcrEth).to.equal(expectedBal);

        let totalSupply = await cReth.totalSupply();

        expect(totalSupply).to.equal(balcrEth);
        //  TODO: other params to validate


        // userB supply numa 
        let numasupplyamount = ethers.parseEther("200000");
        await numa.connect(userB).approve(await cNuma.getAddress(),numasupplyamount);

        // 
        //await comptroller.connect(userA).enterMarkets([cReth.getAddress()]);
        await cNuma.connect(userB).mint(numasupplyamount);

        // TODO: validate supply

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
        let collateralValueInNumaWei =  (ethers.parseEther(rEthCollateralFactor.toString())*ethers.parseEther("2")) / numaBuyPriceInReth;
        console.log("collateral value in numa (wei) "+collateralValueInNumaWei);
        console.log("collateral value in numa "+ethers.formatEther(collateralValueInNumaWei));

        let notTooMuchNuma = collateralValueInNumaWei;

        let tooMuchNuma = ((numaFromREth *BigInt(2)* ethers.parseEther(rEthCollateralFactor.toString()))/ethers.parseEther("1")) + BigInt(1);
        console.log(tooMuchNuma);
        // let liquidity = await comptroller.getHypotheticalAccountLiquidity(
        //   await userA.getAddress(),
        //   await cNuma.getAddress(),
        //   0,
        //   tooMuchNuma);

        // console.log(liquidity);

        // should revert 
        await expect(cNuma.connect(userA).borrow(tooMuchNuma)).to.be.reverted;
       
        // should not revert
       
        console.log(notTooMuchNuma);
        await expect(cNuma.connect(userA).borrow(notTooMuchNuma)).to.not.be.reverted;


        // TODO: validate UR, interest rates, etc

       // TODO: check that we have borrowed

 
      });


      it('Supply Numa, Borrow rEth from vault', async () => 
      {
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
        let tooMuchrEth = notTooMuchrEth+BigInt(1);
        // should revert 
        await expect(cReth.connect(userB).borrow(tooMuchrEth)).to.be.reverted;
       
        // should not revert
  
      
        await expect(cReth.connect(userB).borrow(notTooMuchrEth)).to.not.be.reverted;

        // TODO: validate UR, interest rates, etc

        // TODO: check that we have borrowed from vault
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
        let tooMuchrEth = notTooMuchrEth+BigInt(1);
        // should revert 
        await expect(cReth.connect(userB).borrow(tooMuchrEth)).to.be.reverted;
       
        // should not revert
  
      
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
        console.log(balanceUserBInitial);
        // not enough lenders, we take from vault
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
        let tooMuchrEth = notTooMuchrEth+BigInt(1);
        // should revert 
        await expect(cReth.connect(userB).borrow(tooMuchrEth)).to.be.reverted;
       
        // should not revert
  
      
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
        
        });

        it('Borrow rEth, repay rEth borrowed from lenders only', async () => 
        {
        
        });

        it('Borrow rEth, repay rEth borrowed from vault only', async () => 
        {
        
        });

        it('Borrow rEth, repay rEth borrowed from vault and lenders', async () => 
        {
        
        });



    });

    describe('#Vault collateral factor', () => 
    {
      // limite du borrow possible

      // with/without synthetics --> check that borrows are limited (borrow should revert)
      // autres?      


    });

    describe('#Rewards extraction from debt', () => 
    {
      // borrow

      // prix rEth up

      // extract

      // repay, check that remaining rewards are extracted and that total reward is ok


    });

    describe('#Liquidations', () => 
    {
      // Add liquidation function.
      //  Function#1 supply rETH, get rETH+$100profit back.
      //  Function#2 flashloan rETH from vault & call function#1, repay flashloan, return $100 to user.

      // TODO AccountRequest -> besoin du subgraph? tester de le deployer voir comment marchent les bots

      // 1. comment ça marche de base
      // on peut liquider selon close factor
      // puis l'incentive _setLiquidationIncentive: si 1.08 --> le liquidator garde 8%
      // 
      // comment le modifier?

    });

});

