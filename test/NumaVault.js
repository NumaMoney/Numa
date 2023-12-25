const { getPoolData, getPool, initPoolETH, addLiquidity, weth9, artifacts, swapOptions, buildTrade, SwapRouter, Token } = require("../scripts/Utils.js");
const { deployPrinterTestFixtureArbi, configArbi } = require("./fixtures/NumaTestFixture.js");
const { time, loadFixture, takeSnapshot } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");

const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { upgrades, ethers } = require("hardhat");


// TODO: move it in config
let rETH_ADDRESS = "0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8";
let wstETH_ADDRESS = "0x5979d7b546e38e414f7e9822514be443a4800529";
let RETH_FEED = "0xD6aB2298946840262FcC278fF31516D39fF611eF";
let wstETH_FEED = "0xb523AE262D20A936BC152e6023996e46FDC2A95D";

const ERC20abi = [
  // Read-Only Functions
  "function balanceOf(address owner) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",

  // Authenticated Functions
  "function transfer(address to, uint amount) returns (bool)",
  "function approve(address spender, uint amount)",

  // Events
  "event Transfer(address indexed from, address indexed to, uint amount)"
];

const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
// ********************* Numa vault test using arbitrum fork for chainlink *************************

describe('NUMA VAULT', function () {
  let owner, signer2,signer3,signer4;
  let numaOwner;
  let numa;

  // amount to be transfered to signer
  let numaAmount;

  let testData;
  let numa_address;
  let snapshot;

  let Vault1;
  let VAULT1_ADDRESS;
  let defaultAdmin;
  let nuAM;
  let nuUSD;
  let nuBTC;
  let erc20_rw;
  let VO;
  let VO_ADDRESS;
  let VM;
  let NUAM_ADDRESS;
  let VM_ADDRESS;
  let NUUSD_ADDRESS;
  let decaydenom = 200;

  let sendEthToVault = async function () {
    // send rETH to the vault
    const address = "0x8Eb270e296023E9D92081fdF967dDd7878724424";
    await helpers.impersonateAccount(address);
    const impersonatedSigner = await ethers.getSigner(address);
    await helpers.setBalance(address, ethers.parseEther("10"));

    // send eth to vault to check
   
    let bal0 = await erc20_rw.balanceOf(address);
    // transfer to signer so that it can buy numa
    await erc20_rw.connect(impersonatedSigner).transfer(defaultAdmin, ethers.parseEther("5"));
    // transfer to vault to initialize price
    await erc20_rw.connect(impersonatedSigner).transfer(VAULT1_ADDRESS, ethers.parseEther("100"));
    let bal1 = await erc20_rw.balanceOf(VAULT1_ADDRESS);

  };

  afterEach(async function () {
    //console.log("reseting snapshot");
    await snapshot.restore();
    snapshot = await takeSnapshot();
  })

  beforeEach(async function () {
    //console.log("calling before each");
  })


  before(async function () {
    testData = await loadFixture(deployPrinterTestFixtureArbi);

    owner = testData.signer;
    signer2 = testData.signer2;
    signer3 = testData.signer3;
    signer4 = testData.signer4;
    numaOwner = testData.numaOwner;
    numa = testData.numa;
    numaAmount = testData.numaAmount;

    numa_address = await numa.getAddress();
    NUMA_ETH_POOL_ADDRESS = testData.NUMA_ETH_POOL_ADDRESS;


    
    // Deploy everything
    // TODO: move it in fixture especially if used by printer tests


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
    let NUBTC_ADDRESS = await nuBTC.getAddress();
    console.log('nuBTC address: ', NUBTC_ADDRESS);


    // *********************** nuAssetManager **********************************
    nuAM = await ethers.deployContract("nuAssetManager",
    []
    );
    await nuAM.waitForDeployment();
    NUAM_ADDRESS = await nuAM.getAddress();
    console.log('nuAssetManager address: ', NUAM_ADDRESS);

    // register nuAsset
    await nuAM.addNuAsset(NUUSD_ADDRESS,configArbi.PRICEFEEDETHUSD);
    await nuAM.addNuAsset(NUBTC_ADDRESS,configArbi.PRICEFEEDBTCETH);

    //console.log('initial synth value: ', await nuAM.getTotalSynthValueEth());


    // *********************** vaultManager **********************************
    VM = await ethers.deployContract("vaultManager",
    []);
    await VM.waitForDeployment();
    VM_ADDRESS = await VM.getAddress();
    console.log('vault manager address: ', VM_ADDRESS);


    VO = await ethers.deployContract("VaultOracle",
    []);
    await VO.waitForDeployment();
    VO_ADDRESS= await VO.getAddress();
    console.log('vault oracle address: ', VO_ADDRESS);

    // adding rETH to our oracle
    await VO.setTokenFeed(rETH_ADDRESS,RETH_FEED);

    // vault1 rETH
    Vault1 = await ethers.deployContract("NumaVault",
    [numa_address,rETH_ADDRESS,ethers.parseEther("1"),VO_ADDRESS,NUAM_ADDRESS,decaydenom]);
    await Vault1.waitForDeployment();
    VAULT1_ADDRESS = await Vault1.getAddress();
    console.log('vault rETH address: ', VAULT1_ADDRESS);

    await VM.addVault(VAULT1_ADDRESS);
    await Vault1.setVaultManager(VM_ADDRESS);
    // fee address
    await Vault1.setFeeAddress(await signer3.getAddress());

    await numa.grantRole(roleMinter, VAULT1_ADDRESS);

    erc20_rw = await hre.ethers.getContractAt(ERC20abi, rETH_ADDRESS);

    snapshot = await takeSnapshot();

  });
  describe('#get prices', () => {
      it('empty vault', async () => 
      {

        await expect(
          Vault1.getBuyNuma(ethers.parseEther("2"))
        ).to.be.reverted;


        await expect(
          Vault1.getSellNuma(ethers.parseEther("1000"))
        ).to.be.reverted;


      });
      it('with rETH in the vault', async () => 
      {
        await sendEthToVault();
        let bal1 = await erc20_rw.balanceOf(VAULT1_ADDRESS);

        // we have no synth assets and no other vault so numa mint price should be 100/10000000
        let buypricerefnofees = ethers.parseEther("2")*BigInt(10000000)/(BigInt(100));
        let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

        let buyprice = await Vault1.getBuyNuma(ethers.parseEther("2"));
        expect(buypriceref).to.equal(buyprice);

        let sellpricerefnofees = ethers.parseEther("1000")*BigInt(100)/(BigInt(10000000));
        let sellpriceref = sellpricerefnofees - BigInt(5) * sellpricerefnofees/BigInt(100);
        let sellprice = await Vault1.getSellNuma(ethers.parseEther("1000"));
        expect(sellpriceref).to.equal(sellprice); 
      });

      it('with rETH in the vault and minted nuAssets', async () => 
      {
        await sendEthToVault();
        let bal1 = await erc20_rw.balanceOf(VAULT1_ADDRESS);

        // we have no synth assets and no other vault so numa mint price should be 100/10000000
        let buypricerefnofees = ethers.parseEther("2")*BigInt(10000000)/(BigInt(100));
        let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

        let buyprice = await Vault1.getBuyNuma(ethers.parseEther("2"));
        expect(buypriceref).to.equal(buyprice);

        let sellpricerefnofees = ethers.parseEther("1000")*BigInt(100)/(BigInt(10000000));
        let sellpriceref = sellpricerefnofees - BigInt(5) * sellpricerefnofees/BigInt(100);
        let sellprice = await Vault1.getSellNuma(ethers.parseEther("1000"));
        expect(sellpriceref).to.equal(sellprice);
       
      });
    
    });

  describe('#buy/sell tests', () => {

    it('buy with rEth', async () => 
    {
      let buypricerefnofees = ethers.parseEther("2")*BigInt(10000000)/(BigInt(100));
      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

      await sendEthToVault();
      // BUY
      // should be paused by default 
      await expect(Vault1.buy(ethers.parseEther("2"),await signer2.getAddress())).to.be.reverted;
      await Vault1.unpause();
      await erc20_rw.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));
      await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      bal1 = await erc20_rw.balanceOf(VAULT1_ADDRESS);
      let balfee = await erc20_rw.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
      expect(balbuyer).to.equal(buypriceref);
      expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
      expect(balfee).to.equal(fees);
    });

    it('buy with rEth with decay starting time', async () => 
    {
      let buypricerefnofees = ethers.parseEther("2")*BigInt(10000000)/(BigInt(100));

      buypricerefnofees = (buypricerefnofees * BigInt(100))/BigInt(decaydenom);
      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

      await sendEthToVault();
      // BUY
      // should be paused by default 
      await Vault1.unpause();
      await erc20_rw.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));

      await Vault1.startDecaying();

      await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      //console.log("numa minted start decay ",balbuyer);
      bal1 = await erc20_rw.balanceOf(VAULT1_ADDRESS);
      let balfee = await erc20_rw.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
      expect(balbuyer).to.equal(buypriceref);
      expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
      expect(balfee).to.equal(fees);
    });

    it('buy with rEth with decay half time', async () => 
    {
      let buypricerefnofees = ethers.parseEther("2")*BigInt(10000000)/(BigInt(100));

      buypricerefnofees = (buypricerefnofees * BigInt(100))/BigInt(150);
      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

      await sendEthToVault();
      // BUY
      // should be paused by default 
      await Vault1.unpause();
      await erc20_rw.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));

      await Vault1.startDecaying();

      // wait 45 days
      await time.increase(45*24*3600);

      await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      //console.log("numa minted half decay ",balbuyer);
      bal1 = await erc20_rw.balanceOf(VAULT1_ADDRESS);
      let balfee = await erc20_rw.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
      const epsilon = ethers.parseEther('0.00000000000001');
      expect(balbuyer).to.be.closeTo(buypriceref, epsilon);
      expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
      expect(balfee).to.equal(fees);

    });

    it('buy with rEth with decay over', async () => 
    {
      let buypricerefnofees = ethers.parseEther("2")*BigInt(10000000)/(BigInt(100));

      //buypricerefnofees = (buypricerefnofees * BigInt(100))/BigInt(decaydenom);
      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

      await sendEthToVault();
      // BUY
      // should be paused by default 
      await Vault1.unpause();
      await erc20_rw.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));

      await Vault1.startDecaying();
      // wait 90 days
      await time.increase(90*24*3600);
    
      await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      //console.log("numa minted end decay ",balbuyer);
      bal1 = await erc20_rw.balanceOf(VAULT1_ADDRESS);
      let balfee = await erc20_rw.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
      expect(balbuyer).to.equal(buypriceref);
      expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
      expect(balfee).to.equal(fees);
    });

    it('buy with rEth and synth supply', async () => 
    {
      await sendEthToVault();

      let chainlinkInstance = await hre.ethers.getContractAt(artifacts.AggregatorV3, RETH_FEED);
      let latestRoundData = await chainlinkInstance.latestRoundData();
      let latestRoundPrice = Number(latestRoundData.answer);
      let decimals = Number(await chainlinkInstance.decimals());
     // let price = latestRoundPrice / 10 ** decimals;

      // 100000 nuUSD
      await nuUSD.connect(owner).mint(defaultAdmin,ethers.parseEther("10000"));
      // 10 BTC
      await nuBTC.connect(owner).mint(defaultAdmin,ethers.parseEther("1"));
      // TODO check the value
      let fullSynthValueInEth = await nuAM.getTotalSynthValueEth();
      let fullSynthValueInrEth = (fullSynthValueInEth*BigInt(10 ** decimals) / BigInt(latestRoundPrice));

     // console.log('synth value after minting nuAssets: ', fullSynthValueInrEth);

      // TODO: some imprecision (10-6 numa) -> probably some rounding diff but I need to be sure!
      const epsilon = ethers.parseEther('0.00000000001');
      let buypricerefnofees = ethers.parseEther("2")*ethers.parseEther("10000000")/(ethers.parseEther("100") - fullSynthValueInrEth);

      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

      // BUY
      // should be paused by default 
      await expect(Vault1.buy(ethers.parseEther("2"),await signer2.getAddress())).to.be.reverted;
      await Vault1.unpause();
      await erc20_rw.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));
      await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      bal1 = await erc20_rw.balanceOf(VAULT1_ADDRESS);
      let balfee = await erc20_rw.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
      //expect(balbuyer).to.equal(buypriceref);
      expect(balbuyer).to.be.closeTo(buypriceref, epsilon);

      expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
      expect(balfee).to.equal(fees);
    });
  });

  it('test withdraw', async function () 
  {
    await sendEthToVault();
    let balbeforeLST = await erc20_rw.balanceOf(await owner.getAddress());    
    await Vault1.withdrawToken(rETH_ADDRESS,ethers.parseEther("50"));
    let balafterLST = await erc20_rw.balanceOf(await owner.getAddress());
    expect(balafterLST - balbeforeLST).to.equal(ethers.parseEther("50"));
  });

  it('with another vault', async function () 
  {
    // vault1 needs some rETH 
    await sendEthToVault();

    //
    let address2 = "0x513c7e3a9c69ca3e22550ef58ac1c0088e918fff";
    await helpers.impersonateAccount(address2);
    const impersonatedSigner2 = await ethers.getSigner(address2);
    await helpers.setBalance(address2,ethers.parseEther("10"));
    const erc20_rw2  = await hre.ethers.getContractAt(ERC20abi, wstETH_ADDRESS);
    //
    await VO.setTokenFeed(wstETH_ADDRESS,wstETH_FEED);
    // compute prices
    let chainlinkInstance = await hre.ethers.getContractAt(artifacts.AggregatorV3, RETH_FEED);
    let latestRoundData = await chainlinkInstance.latestRoundData();
    let latestRoundPrice = Number(latestRoundData.answer);
    //let decimals = Number(await chainlinkInstance.decimals());
    let chainlinkInstance2 = await hre.ethers.getContractAt(artifacts.AggregatorV3, wstETH_FEED);
    let latestRoundData2 = await chainlinkInstance2.latestRoundData();
    let latestRoundPrice2 = Number(latestRoundData2.answer);

    // deploy
    let Vault2 = await ethers.deployContract("NumaVault",
    [numa_address,wstETH_ADDRESS,ethers.parseEther("1"),VO_ADDRESS,NUAM_ADDRESS,100]);
    await Vault2.waitForDeployment();
    let VAULT2_ADDRESS = await Vault2.getAddress();
    console.log('vault wstETH address: ', VAULT2_ADDRESS);

    await VM.addVault(VAULT2_ADDRESS);
    await Vault2.setVaultManager(VM_ADDRESS);

    // price before feeding vault2
    buyprice = await Vault1.getBuyNuma(ethers.parseEther("2"));
    let buyprice2 = await Vault2.getBuyNuma(ethers.parseEther("2"));


    let buypricerefnofees = ethers.parseEther("2")*BigInt(10000000)/(BigInt(100));
    let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);


    let buypricerefnofees2 = (buypricerefnofees*BigInt(latestRoundPrice2))/BigInt(latestRoundPrice);
    let buypriceref2 = buypricerefnofees2 - BigInt(5) * buypricerefnofees2/BigInt(100);

    expect(buypriceref).to.equal(buyprice);
    //expect(buypriceref2).to.equal(buyprice2);// Rounding errors here TODO: check
    const epsilon = ethers.parseEther('0.00000000001');
    expect(buypriceref2).to.be.closeTo(buyprice2, epsilon);

    bal0 = await erc20_rw2.balanceOf(address2);
    // transfer to signer so that it can buy numa
    await erc20_rw2.connect(impersonatedSigner2).transfer(defaultAdmin,ethers.parseEther("5"));
    // transfer to vault to initialize price
    await erc20_rw2.connect(impersonatedSigner2).transfer(VAULT2_ADDRESS,ethers.parseEther("100"));

    bal1 = await erc20_rw2.balanceOf(VAULT2_ADDRESS);
    //console.log("wstETH balance of the vault ",bal1);

    // price after feeding vault2
    // let totalBalancerEth = BigInt(100) + (BigInt(100)*BigInt(latestRoundPrice2))/BigInt(latestRoundPrice);
    // let totalBalancewstEth = BigInt(100) + (BigInt(100)*BigInt(latestRoundPrice))/BigInt(latestRoundPrice2);

    let totalBalancerEth = ethers.parseEther("100") + (ethers.parseEther("100")*BigInt(latestRoundPrice2))/BigInt(latestRoundPrice);
    let totalBalancewstEth = ethers.parseEther("100") + (ethers.parseEther("100")*BigInt(latestRoundPrice))/BigInt(latestRoundPrice2);

    let buypricerefnofeesrEth = (ethers.parseEther("2")*ethers.parseEther("10000000"))/(totalBalancerEth);
    let buypricerefnofeeswstEth = (ethers.parseEther("2")*ethers.parseEther("10000000"))/(totalBalancewstEth);

    buypriceref = buypricerefnofeesrEth - BigInt(5) * buypricerefnofeesrEth/BigInt(100);
    buypriceref2 = buypricerefnofeeswstEth - BigInt(5) * buypricerefnofeeswstEth/BigInt(100);

    buyprice = await Vault1.getBuyNuma(ethers.parseEther("2"));   
    buyprice2 = await Vault2.getBuyNuma(ethers.parseEther("2"));

    expect(buypriceref).to.be.closeTo(buyprice, epsilon);
    expect(buypriceref2).to.be.closeTo(buyprice2, epsilon);

    // make vault Numa minter
    await numa.grantRole(roleMinter, VAULT2_ADDRESS);
    // set fee address
    await Vault2.setFeeAddress(await signer3.getAddress());

    // unpause it
    await Vault2.unpause();
    // approve wstEth to be able to buy
    await erc20_rw2.connect(owner).approve(VAULT2_ADDRESS,ethers.parseEther("2"));


    let balfee = await erc20_rw2.balanceOf(await signer3.getAddress());
 
    await Vault2.buy(ethers.parseEther("2"),await signer2.getAddress());

    let balbuyer = await numa.balanceOf(await signer2.getAddress());
    bal1 = await erc20_rw2.balanceOf(VAULT2_ADDRESS);
    balfee = await erc20_rw2.balanceOf(await signer3.getAddress());

    let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
  
    expect(balbuyer).to.be.closeTo(buypriceref2, epsilon);
    expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));

    expect(balfee).to.equal(fees);
  });

  it('Extract rewards', async function () {
  
    await sendEthToVault();

    // ********************** rwd extraction *******************
    let VMO = await ethers.deployContract("VaultMockOracle",
    []);
    await VMO.waitForDeployment();
    let VMO_ADDRESS= await VMO.getAddress();
    console.log('vault mock oracle address: ', VMO_ADDRESS);
    await Vault1.setOracle(VMO_ADDRESS);

    // set new price, simulate a 100 rebase
    let lastprice = await Vault1.last_lsttokenvalueWei();
    let newprice = (BigInt(2)*lastprice);
  
    await VMO.setPrice(newprice);

    // should revert as we don't have a rwd address set
    await expect(Vault1.extractRewards()).to.be.reverted;
    await Vault1.setRwdAddress(await signer4.getAddress());

    let [estimateRewards,newvalue] = await Vault1.rewardsValue();

    expect(newvalue).to.equal(newprice);

    let estimateRewardsEth = estimateRewards*newprice;
    let rwdEth = ethers.parseEther("100")*(newprice - lastprice);
    expect(estimateRewardsEth).to.equal(rwdEth);

    await Vault1.extractRewards();
    let balrwd = await erc20_rw.balanceOf(await signer4.getAddress());
    expect(estimateRewards).to.equal(balrwd);

    let [estimateRewardsAfter,newvalueAfter] = await Vault1.rewardsValue();
    expect(newvalueAfter).to.equal(newprice);
    expect(estimateRewardsAfter).to.equal(0);
    await expect(Vault1.extractRewards()).to.be.reverted;
  });

  it('Buy with rEth and add to skipWallet', async function () {
    await sendEthToVault();
    // BUY
    // should be paused by default 
    await expect(Vault1.buy(ethers.parseEther("2"),await signer2.getAddress())).to.be.reverted;
    await Vault1.unpause();
    await erc20_rw.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));

    // send 1000000 Numa supply to signer3
    await numa.transfer(await signer3.getAddress(),ethers.parseEther("1000000"));
    await Vault1.addToRemovedSupply(await signer3.getAddress());

    let buypricerefnofees = ethers.parseEther("2")*(BigInt(9000000))/(BigInt(100));
    let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

    await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

    let balbuyer = await numa.balanceOf(await signer2.getAddress());
    bal1 = await erc20_rw.balanceOf(VAULT1_ADDRESS);
    let balfee = await erc20_rw.balanceOf(await signer3.getAddress());

    let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
    expect(balbuyer).to.equal(buypriceref);
    expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
    expect(balfee).to.equal(fees);
  });


  it('Buy with rEth and add/remove to skipWallet', async function () {
    await sendEthToVault();
    // BUY
    // should be paused by default 
    await expect(Vault1.buy(ethers.parseEther("2"),await signer2.getAddress())).to.be.reverted;
    await Vault1.unpause();
    await erc20_rw.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));

    // send 1000000 Numa supply to signer3
    await numa.transfer(await signer3.getAddress(),ethers.parseEther("1000000"));
    await Vault1.addToRemovedSupply(await signer3.getAddress());

    // testing remove
    await Vault1.removeFromRemovedSupply(await signer3.getAddress());
    
    let buypricerefnofees = ethers.parseEther("2")*(BigInt(10000000))/(BigInt(100));
    let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);
    await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

    let balbuyer = await numa.balanceOf(await signer2.getAddress());
    bal1 = await erc20_rw.balanceOf(VAULT1_ADDRESS);
    let balfee = await erc20_rw.balanceOf(await signer3.getAddress());

    let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
    expect(balbuyer).to.equal(buypriceref);
    expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
    expect(balfee).to.equal(fees);


  });

  it('nuAssetManager', async function () {

    let chainlinkInstance = await hre.ethers.getContractAt(artifacts.AggregatorV3, RETH_FEED);
    let latestRoundData = await chainlinkInstance.latestRoundData();
    let latestRoundPrice = Number(latestRoundData.answer);
    let decimals = Number(await chainlinkInstance.decimals());


    // 224 nuUSD
    await nuUSD.connect(owner).mint(defaultAdmin,ethers.parseEther("224"));
    // 1 BTC
    await nuBTC.connect(owner).mint(defaultAdmin,ethers.parseEther("1"));

    // console.log("adding nuUSD, nuBTC");
    // console.log(await nuAM.getNuAssetList());
    // console.log(await nuAM.getTotalSynthValueEth());
    await nuAM.removeNuAsset(NUUSD_ADDRESS);
    // console.log("removing nuUSD");
    // console.log(await nuAM.getNuAssetList());
    // console.log(await nuAM.getTotalSynthValueEth());
    let nuAM2 = await ethers.deployContract("nuAssetManagerMock",
    []
    );
    await nuAM2.waitForDeployment();
    let NUAM_ADDRESS2 = await nuAM2.getAddress();


    // register nuAsset
    // for (let i = 0; i < 200; i++) {
    //   await nuAM2.addNuAsset(NUUSD_ADDRESS,configArbi.PRICEFEEDETHUSD);
    // }
   // console.log("adding nuUSD 200 times");
   // console.log(await nuAM2.getNuAssetList());
    //console.log(await nuAM2.getTotalSynthValueEth());

    //await Vault1.setNuAssetManager(nuAM2);
    //let fullSynthValueInEth = await nuAM2.getTotalSynthValueEth();
    let fullSynthValueInEth = await nuAM.getTotalSynthValueEth();
    let fullSynthValueInrEth = (fullSynthValueInEth*BigInt(10 ** decimals) / BigInt(latestRoundPrice));

    // TODO: some imprecision (10-6 numa) -> probably some rounding diff but I need to be sure!
    const epsilon = ethers.parseEther('0.00000000001');
    let buypricerefnofees = ethers.parseEther("2")*ethers.parseEther("10000000")/(ethers.parseEther("100") - fullSynthValueInrEth);
    let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);


    await sendEthToVault();
    // BUY
    // should be paused by default 
    await Vault1.unpause();
    await erc20_rw.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));
    await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

    let balbuyer = await numa.balanceOf(await signer2.getAddress());
    bal1 = await erc20_rw.balanceOf(VAULT1_ADDRESS);
    let balfee = await erc20_rw.balanceOf(await signer3.getAddress());
    let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);

    //expect(balbuyer).to.equal(buypriceref);
    expect(balbuyer).to.be.closeTo(buypriceref, epsilon);
    // expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
    // expect(balfee).to.equal(fees);

  });

  it('Owner', async function () {
    // TODO
  });

  it('Pausable', async function () {
    // TODO
  });

});

