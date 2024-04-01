


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
// - borrow from vault & lenderscheck UR

// - repay vault first, etc, formula

// test CFs with synthetics 

// test extract from debt

// test liquidations

// standart compound tests?
describe('NUMA LENDING', function () {
  let owner, userA,userB,userC;
  let numa;
  let testData;
  let numa_address;
  let snapshot;

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

  let rateModel;
  let JUMPRATEMODELV2_ADDRESS;

  let cReth;
  let CRETH_ADDRESS;

  let cNuma;
  let CNUMA_ADDRESS;

   // sends rETH to the vault and to users
  let sendrEth = async function () {
   
    // rETH arbitrum whale
    const address = "0x8Eb270e296023E9D92081fdF967dDd7878724424";
    await helpers.impersonateAccount(address);
    const impersonatedSigner = await ethers.getSigner(address);
    await helpers.setBalance(address, ethers.parseEther("10"));
    // transfer to signer, users so that it can buy numa
    await rEth_contract.connect(impersonatedSigner).transfer(defaultAdmin, ethers.parseEther("5"));
    await rEth_contract.connect(impersonatedSigner).transfer(await userA.getAddress(), ethers.parseEther("5"));
    await rEth_contract.connect(impersonatedSigner).transfer(await userB.getAddress(), ethers.parseEther("5"));
    await rEth_contract.connect(impersonatedSigner).transfer(await userC.getAddress(), ethers.parseEther("5"));
    // transfer to vault to initialize price
    await rEth_contract.connect(impersonatedSigner).transfer(VAULT1_ADDRESS, ethers.parseEther("100"));
  };

  afterEach(async function () {
    await snapshot.restore();
    snapshot = await takeSnapshot();
  })



  before(async function () {
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
    snapshot = await takeSnapshot();


    // *********************** Deploy lending **********************************
    comptroller = await ethers.deployContract("NumaComptroller",
    []);
    await comptroller.waitForDeployment();
    COMPTROLLER_ADDRESS = await comptroller.getAddress();
    console.log('numa comptroller address: ', COMPTROLLER_ADDRESS);
   
    numaPriceOracle = await ethers.deployContract("NumaPriceOracle",
    []);
    await numaPriceOracle.waitForDeployment();
    NUMA_PRICEORACLE_ADDRESS = await numaPriceOracle.getAddress();
    console.log('numa price oracle address: ', NUMA_PRICEORACLE_ADDRESS);
  
    await numaPriceOracle.setVault(VAULT1_ADDRESS);
    console.log('numaPriceOracle.setVault Done');

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
    cReth = await ethers.deployContract("CErc20Immutable",
    [rETH_ADDRESS,comptroller,rateModel,'200000000000000000000000000',
    'rEth CToken','crEth',8,await owner.getAddress()]);
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

    console.log("setting collateral factor");
    // 80% for numa as collateral
    await comptroller._setCollateralFactor(await cNuma.getAddress(), '800000000000000000');
    // 60% for rEth as collateral
    await comptroller._setCollateralFactor(await cReth.getAddress(), '600000000000000000');
    
    // 50% liquidation close factor
    console.log("set close factor");
    await comptroller._setCloseFactor(ethers.parseEther("0.5").toString());
  

    // add markets
    await comptroller._supportMarket(await cNuma.getAddress());
    await comptroller._supportMarket(await cReth.getAddress());
    
  // // FOR DEBUG REMOVE IR
  // let IM_address = await cNuma.interestRateModel();
  // let IMV2 = await ethers.getContractAt("BaseJumpRateModelV2", IM_address);
  // // await IMV2.updateJumpRateModel(ethers.parseEther('0.02'),ethers.parseEther('0.18')
  // // ,ethers.parseEther('4'),ethers.parseEther('0.8'));
  
  // console.log("cancelling interest rates");
  // await IMV2.updateJumpRateModel(ethers.parseEther('0'),ethers.parseEther('0')
  // ,ethers.parseEther('0'),ethers.parseEther('1'));
  
      await sendrEth();
  });
  describe('#Supply & Borrow', () => 
  {
      // getting prices should revert if vault is empty 
      it('Supply rEth', async () => 
      {
        // approve
        let rethsupplyamount = ethers.parseEther("2");
        await rEth_contract.connect(userA).approve(await cReth.getAddress(),rethsupplyamount);

        // 
        //await comptroller.connect(userA).enterMarkets([cReth.getAddress()]);


        await cReth.connect(userA).mint(rethsupplyamount);
        // check balance, total supply,
        let balcrEth = await cReth.balanceOf(await userA.getAddress());
        let exchangeRate = BigInt(await cReth.exchangeRateStored());
        console.log(rethsupplyamount);
        console.log(exchangeRate);
        // TODO: understand exchange rate
        // let expectedBal = (rethsupplyamount)/exchangeRate;
        // expect(balcrEth).to.equal(expectedBal);

        let totalSupply = await cReth.totalSupply();

        expect(totalSupply).to.equal(balcrEth);
        //  TODO: other params to validate


 
      });

   
    });





});

