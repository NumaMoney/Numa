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



const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
const epsilon = ethers.parseEther('0.0000000001');


// ********************* Numa vault test using arbitrum fork for chainlink *************************

describe('NUMA VAULT', function () {
  let owner, signer2,signer3,signer4;
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
  let VM;
  let NUAM_ADDRESS;
  let VM_ADDRESS;
  let NUUSD_ADDRESS;
  let decaydenom = 200;

   // sends rETH to the vault
  let sendEthToVault = async function () {
   
    // rETH arbitrum whale
    const address = "0x8Eb270e296023E9D92081fdF967dDd7878724424";
    await helpers.impersonateAccount(address);
    const impersonatedSigner = await ethers.getSigner(address);
    await helpers.setBalance(address, ethers.parseEther("10"));
    // transfer to signer so that it can buy numa
    await rEth_contract.connect(impersonatedSigner).transfer(defaultAdmin, ethers.parseEther("5"));
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
    signer2 = testData.signer2;
    signer3 = testData.signer3;
    signer4 = testData.signer4;
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


    // *********************** vaultManager **********************************
    VM = await ethers.deployContract("VaultManager",
    [numa_address,decaydenom]);
    await VM.waitForDeployment();
    VM_ADDRESS = await VM.getAddress();
    console.log('vault manager address: ', VM_ADDRESS);

    // *********************** VaultOracle **********************************
    VO = await ethers.deployContract("VaultOracle",
    []);
    await VO.waitForDeployment();
    VO_ADDRESS= await VO.getAddress();
    console.log('vault oracle address: ', VO_ADDRESS);

    // adding rETH to our oracle
    await VO.setTokenFeed(rETH_ADDRESS,RETH_FEED);

    // *********************** NumaVault rEth **********************************
    Vault1 = await ethers.deployContract("NumaVault",
    [numa_address,rETH_ADDRESS,ethers.parseEther("1"),VO_ADDRESS,NUAM_ADDRESS,decaydenom]);
    await Vault1.waitForDeployment();
    VAULT1_ADDRESS = await Vault1.getAddress();
    console.log('vault rETH address: ', VAULT1_ADDRESS);

    await VM.addVault(VAULT1_ADDRESS);
    await Vault1.setVaultManager(VM_ADDRESS);

    // fee address
    await Vault1.setFeeAddress(await signer3.getAddress());
    // vault has to be allowed to mint Numa
    await numa.grantRole(roleMinter, VAULT1_ADDRESS);

    // get rEth contract 
    rEth_contract = await hre.ethers.getContractAt(ERC20abi, rETH_ADDRESS);
    snapshot = await takeSnapshot();

  });
  describe('#get prices', () => 
  {
      // getting prices should revert if vault is empty 
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
        let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);
        let numaSupply = await numa.totalSupply();
        let buyfee = await Vault1.BUY_FEE();
        let sellfee = await Vault1.SELL_FEE();
        let feedenom = await Vault1.FEE_BASE_1000();

        // BUY
        let inputreth = ethers.parseEther("2");
        let buypricerefnofees = inputreth*numaSupply/(balvaultWei);
        // fees
        let buypriceref = (buypricerefnofees* BigInt(buyfee))/BigInt(feedenom);
        let buyprice = await Vault1.getBuyNuma(inputreth);
        expect(buypriceref).to.equal(buyprice);

        // SELL 
        let inputnuma = ethers.parseEther("1000");
        let sellpricerefnofees = inputnuma*balvaultWei/(numaSupply);
        let sellpriceref = (sellpricerefnofees* BigInt(sellfee))/BigInt(feedenom);
        let sellprice = await Vault1.getSellNuma(inputnuma);
        expect(sellpriceref).to.equal(sellprice); 
      });

      it('with rETH in the vault and minted nuAssets', async () => 
      {
        // mint synthetics
        // 100000 nuUSD
        let nuUSDamount = ethers.parseEther("100000");
        await nuUSD.connect(owner).mint(defaultAdmin,nuUSDamount);
        await sendEthToVault();
        let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);
        let numaSupply = await numa.totalSupply();
        let buyfee = await Vault1.BUY_FEE();
        let sellfee = await Vault1.SELL_FEE();
        let feedenom = await Vault1.FEE_BASE_1000();

        let chainlinkInstance = await hre.ethers.getContractAt(artifacts.AggregatorV3, ETH_FEED);
        let latestRoundData = await chainlinkInstance.latestRoundData();
        let latestRoundPrice = Number(latestRoundData.answer);
        let decimals = Number(await chainlinkInstance.decimals());

        let chainlinkInstancerEth = await hre.ethers.getContractAt(artifacts.AggregatorV3, RETH_FEED);
        let latestRoundDatarEth = await chainlinkInstancerEth.latestRoundData();
        let latestRoundPricerEth = Number(latestRoundDatarEth.answer);
        let decimalsrEth = Number(await chainlinkInstancerEth.decimals());

        let synthValueEth = (BigInt(10**decimals)*nuUSDamount)/(BigInt(latestRoundPrice));
        let synthValuerEth = (BigInt(10**decimalsrEth)*synthValueEth)/(BigInt(latestRoundPricerEth));



        // BUY
        let inputreth = ethers.parseEther("2");
        let buypricerefnofees = (inputreth)*numaSupply/(balvaultWei - synthValuerEth);
        // fees
        let buypriceref = (buypricerefnofees* BigInt(buyfee))/BigInt(feedenom);
        let buyprice = await Vault1.getBuyNuma(inputreth);
        expect(buypriceref).to.be.closeTo(buyprice, epsilon);

        // SELL 
        let inputnuma = ethers.parseEther("1000");
        let sellpricerefnofees = inputnuma*(balvaultWei - synthValuerEth)/(numaSupply);
        let sellpriceref = (sellpricerefnofees* BigInt(sellfee))/BigInt(feedenom);
        let sellprice = await Vault1.getSellNuma(inputnuma); 
        expect(sellpriceref).to.be.closeTo(sellprice, epsilon);
      });

      it('with rETH in the vault and start decay', async () => 
      {
        await sendEthToVault();
        let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);
        let numaSupply = await numa.totalSupply();
        let buyfee = await Vault1.BUY_FEE();
        let sellfee = await Vault1.SELL_FEE();
        let feedenom = await Vault1.FEE_BASE_1000();

        await Vault1.startDecaying();

        // BUY
        let inputreth = ethers.parseEther("2");
        let buypricerefnofees = inputreth*numaSupply/(BigInt(decaydenom/100)*balvaultWei);
        // fees
        let buypriceref = (buypricerefnofees* BigInt(buyfee))/BigInt(feedenom);
        let buyprice = await Vault1.getBuyNuma(inputreth);
        expect(buypriceref).to.equal(buyprice);

        // SELL 
        let inputnuma = ethers.parseEther("1000");
        let sellpricerefnofees = BigInt(decaydenom/100)*inputnuma*balvaultWei/(numaSupply);
        let sellpriceref = (sellpricerefnofees* BigInt(sellfee))/BigInt(feedenom);
        let sellprice = await Vault1.getSellNuma(inputnuma);
        expect(sellpriceref).to.equal(sellprice); 
      });

      it('with rETH in the vault and start decay and rebase', async () => 
      {
        await sendEthToVault();
        await time.increase(25*3600);
        let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);
        let numaSupply = await numa.totalSupply();
        let buyfee = await Vault1.BUY_FEE();
        let sellfee = await Vault1.SELL_FEE();
        let feedenom = await Vault1.FEE_BASE_1000();

        await Vault1.startDecaying();
        
        // set a mock rEth oracle to simulate rebase
        let VMO = await ethers.deployContract("VaultMockOracle",[]);
        await VMO.waitForDeployment();
        let VMO_ADDRESS= await VMO.getAddress();
        await Vault1.setOracle(VMO_ADDRESS);

        // set new price, simulate a 100% rebase
        let lastprice = await Vault1.last_lsttokenvalueWei();
        let newprice = (BigInt(2)*lastprice);
  

        await VMO.setPrice(newprice);
       
        // set rwd address
        await Vault1.setRwdAddress(await signer4.getAddress());

        let [estimateRewards,newvalue] = await Vault1.rewardsValue();

        expect(newvalue).to.equal(newprice);
        

        let estimateRewardsEth = estimateRewards*newprice;
        let rwdEth = balvaultWei*(newprice - lastprice);        
        expect(estimateRewardsEth).to.equal(rwdEth);
        
        // price should stay the same (with ratio as rEth is now worth more)
        let ratio = newprice/lastprice;
        // BUY
        let inputreth = ethers.parseEther("2");
        //let buypricerefnofees = ratio*inputreth*numaSupply/(BigInt(decaydenom/100)*balvaultWei);
        let buypricerefnofees = inputreth*numaSupply/(BigInt(decaydenom/100)*balvaultWei);
        // fees
        let buypriceref = (buypricerefnofees* BigInt(buyfee))/BigInt(feedenom);
        let buyprice = await Vault1.getBuyNuma(inputreth);
        expect(buypriceref).to.equal(buyprice);

        // SELL 
        let inputnuma = ethers.parseEther("1000");
        //let sellpricerefnofees = BigInt(decaydenom/100)*inputnuma*balvaultWei/(numaSupply*ratio);
        let sellpricerefnofees = BigInt(decaydenom/100)*inputnuma*balvaultWei/(numaSupply);
        let sellpriceref = (sellpricerefnofees* BigInt(sellfee))/BigInt(feedenom);
        let sellprice = await Vault1.getSellNuma(inputnuma);
        expect(sellpriceref).to.equal(sellprice); 


        // this one should give real price as we will extract rewards and update snapshot price
        let buypriceReal = await Vault1.getBuyNumaSimulateExtract(inputreth);
        expect(ratio*buypriceref).to.equal(buypriceReal);
        let sellpriceReal = await Vault1.getSellNumaSimulateExtract(inputnuma);
        expect(sellpriceref).to.equal(ratio*sellpriceReal); 


        // extract and price should stays the same
        await Vault1.extractRewards();
        let balrwd = await rEth_contract.balanceOf(await signer4.getAddress());
        expect(estimateRewards).to.equal(balrwd);

        // check prices
        buyprice = await Vault1.getBuyNuma(inputreth);


        expect(ratio*buypriceref).to.equal(buyprice);
        sellprice = await Vault1.getSellNuma(inputnuma);
        expect(sellpriceref).to.equal(ratio*sellprice); 


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
      await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));
      await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
      let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
      expect(balbuyer).to.equal(buypriceref);
      expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
      expect(balfee).to.equal(fees);
    });

    it('sell to rEth', async () => 
    {
      await sendEthToVault();

      let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);
      let numaSupply = await numa.totalSupply();
     
      let sellfee = await Vault1.SELL_FEE();
      let feedenom = await Vault1.FEE_BASE_1000();

      // SELL 
      let inputnuma = ethers.parseEther("1000");
      let sellpricerefnofees = inputnuma*balvaultWei/(numaSupply);
      let sellpriceref = (sellpricerefnofees* BigInt(sellfee))/BigInt(feedenom);
      // should be paused by default 
      let balBefore = await numa.balanceOf(await owner.getAddress());
      await expect(Vault1.sell(inputnuma,await signer2.getAddress())).to.be.reverted;
      await Vault1.unpause();
      await numa.connect(owner).approve(VAULT1_ADDRESS,inputnuma);
      await Vault1.sell(inputnuma,await signer2.getAddress());
      let numaSupplyAfter = await numa.totalSupply();
      let balseller = await rEth_contract.balanceOf(await signer2.getAddress());
      let bal1 = numaSupply - numaSupplyAfter;
      let bal2 = balBefore - (await numa.balanceOf(await owner.getAddress()));
      let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

      // 1% fees
      let fees = BigInt(1) * sellpricerefnofees/BigInt(100);
      expect(balseller).to.equal(sellpriceref);
      expect(bal1).to.equal(inputnuma);
      expect(bal2).to.equal(inputnuma);
      expect(balfee).to.equal(fees);

     
    });

    it('buy & extract if rwd > threshold', async () => 
    {
      let buypricerefnofees = ethers.parseEther("2")*BigInt(10000000)/(BigInt(100));
      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);
      await sendEthToVault();
      let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);

      // set a mock rEth oracle to simulate rebase
      let VMO = await ethers.deployContract("VaultMockOracle",[]);
      await VMO.waitForDeployment();
      let VMO_ADDRESS= await VMO.getAddress();
      await Vault1.setOracle(VMO_ADDRESS);
    
      // set new price, simulate a 100% rebase
      let lastprice = await Vault1.last_lsttokenvalueWei();
      let newprice = (BigInt(2)*lastprice);
      
    
      await VMO.setPrice(newprice);
      
      // set rwd address
      await Vault1.setRwdAddress(await signer4.getAddress());
    
      let [estimateRewards,newvalue] = await Vault1.rewardsValue();
    
      expect(newvalue).to.equal(newprice);
      
    
      let estimateRewardsEth = estimateRewards*newprice;
      let rwdEth = balvaultWei*(newprice - lastprice);        
      expect(estimateRewardsEth).to.equal(rwdEth);
      
      // price should stay the same (with ratio as rEth is now worth more)
      let ratio = newprice/lastprice;
              

      // BUY
      await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));
      await Vault1.unpause();
      // wait 1 day so that rewards are available
      await time.increase(25*3600);
      await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
      let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
      expect(balbuyer).to.equal(ratio*buypriceref);
      let balrwd = await rEth_contract.balanceOf(await signer4.getAddress());
      expect(balrwd).to.equal(estimateRewards);
      expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100) - balrwd);
      expect(balfee).to.equal(fees);
      
    });

    it('sell & extract if rwd > threshold', async () => 
    {
      // TODO
    });

    it('buy & no extract if rwd < threshold', async () => 
    {
      let buypricerefnofees = ethers.parseEther("2")*BigInt(10000000)/(BigInt(100));
      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);
      await sendEthToVault();
      await time.increase(25*3600);
      let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);

      // set a mock rEth oracle to simulate rebase
      let VMO = await ethers.deployContract("VaultMockOracle",[]);
      await VMO.waitForDeployment();
      let VMO_ADDRESS= await VMO.getAddress();
      await Vault1.setOracle(VMO_ADDRESS);
      // set rwd address
      await Vault1.setRwdAddress(await signer4.getAddress());
    
      // set new price, simulate a 100% rebase
      let lastprice = await Vault1.last_lsttokenvalueWei();
      let newprice = (BigInt(2)*lastprice);
      await VMO.setPrice(newprice);
      
      let [estimateRewards,newvalue] = await Vault1.rewardsValue();
      expect(newvalue).to.equal(newprice);
      // we have 100 rEth and price made x 2 so rewards should be 50 rEth
      expect(estimateRewards).to.equal(ethers.parseEther("50"));

      // change threshold so that we can not extract
      let newThreshold = ethers.parseEther("51");
      await Vault1.setRewardsThreshold(newThreshold);
      [estimateRewards,newvalue] = await Vault1.rewardsValue();
      await expect(Vault1.extractRewards()).to.be.reverted;

      // BUY
      let estimateRewardsEth = estimateRewards*newprice;
      let rwdEth = balvaultWei*(newprice - lastprice);        
      expect(estimateRewardsEth).to.equal(rwdEth);
      
      // price should stay the same (with ratio as rEth is now worth more)
      let ratio = newprice/lastprice;

      await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));
      await Vault1.unpause();
      await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
      let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
      //expect(balbuyer).to.equal(ratio*buypriceref);
      expect(balbuyer).to.equal(buypriceref);
      let balrwd = await rEth_contract.balanceOf(await signer4.getAddress());
      expect(balrwd).to.equal(0);// no extraction thanks to new threshold
      expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100) - balrwd);
      expect(balfee).to.equal(fees);
    });

    it('sell & no extract if rwd < threshold', async () => 
    {
      // TODO
    });


    it('buy with rEth with decay starting time', async () => 
    {
      let buypricerefnofees = ethers.parseEther("2")*BigInt(10000000)/(BigInt(100));

      buypricerefnofees = (buypricerefnofees * BigInt(100))/BigInt(decaydenom);
      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

      await sendEthToVault();
      // BUY
      // paused by default 
      await Vault1.unpause();
      await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));

      await Vault1.startDecaying();

      await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      //console.log("numa minted start decay ",balbuyer);
      bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
      let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

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
      // paused by default 
      await Vault1.unpause();
      await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));

      await Vault1.startDecaying();

      // wait 45 days
      await time.increase(45*24*3600);

      await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      //console.log("numa minted half decay ",balbuyer);
      bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
      let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
      
      expect(balbuyer).to.be.closeTo(buypriceref, epsilon);
      expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
      expect(balfee).to.equal(fees);

    });

    it('buy with rEth with decay over', async () => 
    {
      let buypricerefnofees = ethers.parseEther("2")*BigInt(10000000)/(BigInt(100));
      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

      await sendEthToVault();
      // BUY
      //  paused by default 
      await Vault1.unpause();
      await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));

      await Vault1.startDecaying();
      // wait 90 days
      await time.increase(90*24*3600);
    
      await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      //console.log("numa minted end decay ",balbuyer);
      bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
      let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

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

      // TODO: some imprecision (10-6 numa) 
      let buypricerefnofees = ethers.parseEther("2")*ethers.parseEther("10000000")/(ethers.parseEther("100") - fullSynthValueInrEth);

      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

      // BUY
      // paused by default 
      await expect(Vault1.buy(ethers.parseEther("2"),await signer2.getAddress())).to.be.reverted;
      await Vault1.unpause();
      await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));
      await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
      let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);

      expect(balbuyer).to.be.closeTo(buypriceref, epsilon);
      expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
      expect(balfee).to.equal(fees);
    });
  });

  it('test withdraw', async function () 
  {
    await sendEthToVault();
    let balbeforeLST = await rEth_contract.balanceOf(await owner.getAddress());    
    await Vault1.withdrawToken(rETH_ADDRESS,ethers.parseEther("50"));
    let balafterLST = await rEth_contract.balanceOf(await owner.getAddress());
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
    const wstEth_contract  = await hre.ethers.getContractAt(ERC20abi, wstETH_ADDRESS);
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
    expect(buypriceref2).to.be.closeTo(buyprice2, epsilon);

    bal0 = await wstEth_contract.balanceOf(address2);
    // transfer to signer so that it can buy numa
    await wstEth_contract.connect(impersonatedSigner2).transfer(defaultAdmin,ethers.parseEther("5"));
    // transfer to vault to initialize price
    await wstEth_contract.connect(impersonatedSigner2).transfer(VAULT2_ADDRESS,ethers.parseEther("100"));

    bal1 = await wstEth_contract.balanceOf(VAULT2_ADDRESS);

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
    await wstEth_contract.connect(owner).approve(VAULT2_ADDRESS,ethers.parseEther("2"));


    let balfee = await wstEth_contract.balanceOf(await signer3.getAddress());
 
    await Vault2.buy(ethers.parseEther("2"),await signer2.getAddress());

    let balbuyer = await numa.balanceOf(await signer2.getAddress());
    bal1 = await wstEth_contract.balanceOf(VAULT2_ADDRESS);
    balfee = await wstEth_contract.balanceOf(await signer3.getAddress());

    let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
  
    expect(balbuyer).to.be.closeTo(buypriceref2, epsilon);
    expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));

    expect(balfee).to.equal(fees);
  });

  it('Extract rewards', async function () {
  
    await sendEthToVault();
    await time.increase(25*3600);

    // ********************** rwd extraction *******************
    let VMO = await ethers.deployContract("VaultMockOracle",
    []);
    await VMO.waitForDeployment();
    let VMO_ADDRESS= await VMO.getAddress();
    console.log('vault mock oracle address: ', VMO_ADDRESS);
    await Vault1.setOracle(VMO_ADDRESS);

    // set new price, simulate a 100% rebase
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
    let balrwd = await rEth_contract.balanceOf(await signer4.getAddress());
    expect(estimateRewards).to.equal(balrwd);

    let [estimateRewardsAfter,newvalueAfter] = await Vault1.rewardsValue();
    expect(newvalueAfter).to.equal(newprice);
    expect(estimateRewardsAfter).to.equal(0);
    await expect(Vault1.extractRewards()).to.be.reverted;
  });

  it('Buy with rEth and add to skipWallet', async function () {
    await sendEthToVault();
    // BUY
    // paused by default 
    await expect(Vault1.buy(ethers.parseEther("2"),await signer2.getAddress())).to.be.reverted;
    await Vault1.unpause();
    await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));

    // send 1000000 Numa supply to signer3
    await numa.transfer(await signer3.getAddress(),ethers.parseEther("1000000"));
    await Vault1.addToRemovedSupply(await signer3.getAddress());

    let buypricerefnofees = ethers.parseEther("2")*(BigInt(9000000))/(BigInt(100));
    let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

    await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

    let balbuyer = await numa.balanceOf(await signer2.getAddress());
    bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
    let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

    let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
    expect(balbuyer).to.equal(buypriceref);
    expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
    expect(balfee).to.equal(fees);
  });


  it('Buy with rEth and add/remove to skipWallet', async function () {
    await sendEthToVault();
    // BUY
    // paused by default 
    await expect(Vault1.buy(ethers.parseEther("2"),await signer2.getAddress())).to.be.reverted;
    await Vault1.unpause();
    await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));

    // send 1000000 Numa supply to signer3
    await numa.transfer(await signer3.getAddress(),ethers.parseEther("1000000"));
    await Vault1.addToRemovedSupply(await signer3.getAddress());

    // testing remove
    await Vault1.removeFromRemovedSupply(await signer3.getAddress());
    
    let buypricerefnofees = ethers.parseEther("2")*(BigInt(10000000))/(BigInt(100));
    let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);
    await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

    let balbuyer = await numa.balanceOf(await signer2.getAddress());
    bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
    let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

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
    await nuAM.removeNuAsset(NUUSD_ADDRESS);

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

    // TODO: some imprecision (10-6 numa)
    let buypricerefnofees = ethers.parseEther("2")*ethers.parseEther("10000000")/(ethers.parseEther("100") - fullSynthValueInrEth);
    let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);


    await sendEthToVault();
    // BUY
    // should be paused by default 
    await Vault1.unpause();
    await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));
    await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());

    let balbuyer = await numa.balanceOf(await signer2.getAddress());
    bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
    let balfee = await rEth_contract.balanceOf(await signer3.getAddress());
    let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);

    //expect(balbuyer).to.equal(buypriceref);
    expect(balbuyer).to.be.closeTo(buypriceref, epsilon);
    // expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
    // expect(balfee).to.equal(fees);

  });


  it('Fees', async () => 
  {
  
    await expect(Vault1.setBuyFee(1001)).to.be.reverted;
    await expect(Vault1.setSellFee(1001)).to.be.reverted;
    await expect(Vault1.setBuyFee(800)).to.not.be.reverted;
    await expect(Vault1.setSellFee(800)).to.not.be.reverted;
    await expect(Vault1.setFee(200)).to.not.be.reverted;
    await expect(Vault1.setFee(201)).to.be.reverted;

  });
  it('Pausable', async () => 
  {
    await sendEthToVault();
    // BUY
    // should be paused by default 
    await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));
    await expect(Vault1.buy(ethers.parseEther("1"),await signer2.getAddress())).to.be.reverted;
    await Vault1.unpause();
    await expect(Vault1.buy(ethers.parseEther("1"),await signer2.getAddress())).to.not.be.reverted;
    await Vault1.pause();
    await expect(Vault1.buy(ethers.parseEther("1"),await signer2.getAddress())).to.be.reverted;
  });

  it('Owner', async function () 
  {
    let addy = "0x1230000000000000000000000000000000000004";
    let newBuySellFee = 900;// 10%
    let newFees = 20; // 2%
    let newRwdThreshold = ethers.parseEther("1");

    await expect( Vault1.connect(signer2).startDecaying()).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());


    //
    await expect( Vault1.connect(signer2).setOracle(addy)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( Vault1.connect(signer2).setNuAssetManager(addy)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( Vault1.connect(signer2).setVaultManager(addy)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( Vault1.connect(signer2).setRwdAddress(addy)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( Vault1.connect(signer2).setFeeAddress(addy)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( Vault1.connect(signer2).setSellFee(newBuySellFee)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( Vault1.connect(signer2).setBuyFee(newBuySellFee)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( Vault1.connect(signer2).setFee(newFees)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( Vault1.connect(signer2).setRewardsThreshold(newRwdThreshold)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( Vault1.connect(signer2).addToRemovedSupply(addy)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( Vault1.connect(signer2).removeFromRemovedSupply(addy)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await sendEthToVault();
    await expect( Vault1.connect(signer2).withdrawToken(await rEth_contract.getAddress(),ethers.parseEther("10"))).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( Vault1.connect(signer2).unpause()).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());
    // transfer ownership then unpause should work
    await Vault1.connect(owner).transferOwnership(await signer2.getAddress());
    await expect( Vault1.connect(signer2).unpause()).to.not.be.reverted;
  });



});

