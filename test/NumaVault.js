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
const epsilon = ethers.parseEther('0.0000000001');


// ********************* Numa vault test using arbitrum fork for chainlink *************************

describe('NUMA VAULT', function () {
  let owner, signer2,signer3,signer4;
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
  let vault1Bal;
  // no more decay
  let decaydenom = 100;

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
  after(async function () {
    await snapshotGlobal.restore();
  });



  before(async function () {
    testData = await loadFixture(deployNumaNumaPoolnuAssetsPrinters);
    snapshotGlobal = testData.snapshotGlobal;
    owner = testData.signer;
    signer2 = testData.signer2;
    signer3 = testData.signer3;
    signer4 = testData.signer4;
    numa = testData.numa;
    numa_address = await numa.getAddress();



    
    // Deploy contracts
    // USE CONTRACTS FROM FIXTURE
    nuUSD = testData.nuUSD;
    nuBTC = testData.NUBTC;

    NUUSD_ADDRESS = await nuUSD.getAddress();
    NUBTC_ADDRESS = await nuBTC.getAddress();

    minterAddress = testData.MINTER_ADDRESS;
    VM = testData.VM;
    VM_ADDRESS = await VM.getAddress();
    Vault1 = testData.Vault1;
    VAULT1_ADDRESS = await Vault1.getAddress();

    nuAM = testData.nuAM;

    // *********************** NUUSD TOKEN **********************************
    // const NuUSD = await ethers.getContractFactory('nuAsset');
    defaultAdmin = await owner.getAddress();
    // let minter = await owner.getAddress();
    // let upgrader = await owner.getAddress();
    // nuUSD = await upgrades.deployProxy(
    //   NuUSD,
    //   ["NuUSD", "NUSD",defaultAdmin,minter,upgrader],
    //   {
    //     initializer: 'initialize',
    //     kind:'uups'
    //   }
    // );
    // await nuUSD.waitForDeployment();
    // NUUSD_ADDRESS = await nuUSD.getAddress();
    // console.log('nuUSD address: ', NUUSD_ADDRESS);


    // // *********************** NUBTC TOKEN **********************************
    // const NuBTC = await ethers.getContractFactory('nuAsset');
    
    // nuBTC = await upgrades.deployProxy(
    //   NuBTC,
    //   ["NuBTC", "NBTC",defaultAdmin,minter,upgrader],
    //   {
    //     initializer: 'initialize',
    //     kind:'uups'
    //   }
    // );
    // await nuBTC.waitForDeployment();
    // NUBTC_ADDRESS = await nuBTC.getAddress();
    // console.log('nuBTC address: ', NUBTC_ADDRESS);


    // // *********************** nuAssetManager **********************************
    // nuAM = await ethers.deployContract("nuAssetManager",
    // [UPTIME_FEED]
    // );
    // await nuAM.waitForDeployment();
    // NUAM_ADDRESS = await nuAM.getAddress();
    // console.log('nuAssetManager address: ', NUAM_ADDRESS);

    // // register nuAsset
    // await nuAM.addNuAsset(NUUSD_ADDRESS,configArbi.PRICEFEEDETHUSD,86400);
    // await nuAM.addNuAsset(NUBTC_ADDRESS,configArbi.PRICEFEEDBTCETH,86400);


    // // *********************** vaultManager **********************************
    // VM = await ethers.deployContract("VaultManager",
    // [numa_address,NUAM_ADDRESS]);
    // await VM.waitForDeployment();
    // VM_ADDRESS = await VM.getAddress();
    // console.log('vault manager address: ', VM_ADDRESS);

    // // *********************** VaultOracle **********************************
    // VO = await ethers.deployContract("VaultOracleSingle",
    // [rETH_ADDRESS,RETH_FEED,16*86400,UPTIME_FEED]);
    // await VO.waitForDeployment();
    // VO_ADDRESS= await VO.getAddress();
    // console.log('vault 1 oracle address: ', VO_ADDRESS);


    // VOcustomHeartbeat = await ethers.deployContract("VaultOracleSingle",
    // [rETH_ADDRESS,RETH_FEED,402*86400,UPTIME_FEED]);
    // await VOcustomHeartbeat.waitForDeployment();
    // VO_ADDRESScustomHeartbeat= await VOcustomHeartbeat.getAddress();
    // console.log('vault 1 oracle address: ', VO_ADDRESScustomHeartbeat);


    VO2 = await ethers.deployContract("VaultOracleSingle",
    [wstETH_ADDRESS,wstETH_FEED,50*86400,UPTIME_FEED]);
    await VO2.waitForDeployment();
    VO_ADDRESS2= await VO2.getAddress();
    console.log('vault 2 oracle address: ', VO_ADDRESS2);



    // *********************** NumaVault rEth **********************************
    // Vault1 = await ethers.deployContract("NumaVault",
    // [numa_address,rETH_ADDRESS,ethers.parseEther("1"),VO_ADDRESS]);
    // await Vault1.waitForDeployment();
    // VAULT1_ADDRESS = await Vault1.getAddress();
    // console.log('vault rETH address: ', VAULT1_ADDRESS);

    // await VM.addVault(VAULT1_ADDRESS);
    // await Vault1.setVaultManager(VM_ADDRESS);

    // // fee address
    // await Vault1.setFeeAddress(await signer3.getAddress(),false);
    // // vault has to be allowed to mint Numa
    // await numa.grantRole(roleMinter, VAULT1_ADDRESS);

    // get rEth contract 
    rEth_contract = await hre.ethers.getContractAt(ERC20abi, rETH_ADDRESS);
    vault1Bal = await rEth_contract.balanceOf(VAULT1_ADDRESS);
    snapshot = await takeSnapshot();

  });
  describe('#get prices', () => 
  {
      // getting prices should revert if vault is empty 
      it('empty vault', async () => 
      {
        let bal = await rEth_contract.balanceOf(VAULT1_ADDRESS);
        console.log(bal);
        await Vault1.withdrawToken(rETH_ADDRESS,bal,await owner.getAddress());
        bal = await rEth_contract.balanceOf(VAULT1_ADDRESS);
        console.log(bal);

        await expect(
          Vault1.getBuyNumaSimulateExtract(ethers.parseEther("2"))
        ).to.be.reverted;
        await expect(
          Vault1.getSellNumaSimulateExtract(ethers.parseEther("1000"))
        ).to.be.reverted;
      });

      it('with rETH in the vault', async () => 
      {
        //await sendEthToVault();
        let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);
        let numaSupply = await numa.totalSupply();
        let buyfee = await VM.buy_fee();
        let sellfee = await VM.sell_fee();
        let feedenom = 1000;

        // BUY
        let inputreth = ethers.parseEther("2");
        let buypricerefnofees = inputreth*numaSupply/(balvaultWei);
        // fees
        let buypriceref = (buypricerefnofees* BigInt(buyfee))/BigInt(feedenom);
        let buyprice = await Vault1.getBuyNumaSimulateExtract(inputreth);
        expect(buypriceref).to.equal(buyprice);

        // SELL 
        let inputnuma = ethers.parseEther("1000");
        let sellpricerefnofees = inputnuma*balvaultWei/(numaSupply);
        let sellpriceref = (sellpricerefnofees* BigInt(sellfee))/BigInt(feedenom);
        let sellprice = await Vault1.getSellNumaSimulateExtract(inputnuma);
        //expect(sellpriceref).to.equal(sellprice); 
        expect(sellpriceref).to.be.closeTo(sellprice,epsilon); 

      });


      // DECAY SUPPLY
      it('with rETH in the vault decay not started', async () => 
      {
        //await sendEthToVault();
        let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);
        let numaSupply = await numa.totalSupply();
        let buyfee = await VM.buy_fee();
        let sellfee = await VM.sell_fee();
        let feedenom = 1000;


        let removedSupply = numaSupply / BigInt(2);
       
        await VM.setDecayValues(removedSupply,365*24*3600,0,0,0);




        numaSupply = numaSupply - removedSupply;

        // BUY
        let inputreth = ethers.parseEther("2");
        let buypricerefnofees = inputreth*(numaSupply)/(balvaultWei);
        // fees
        let buypriceref = (buypricerefnofees* BigInt(buyfee))/BigInt(feedenom);
        let buyprice = await Vault1.getBuyNumaSimulateExtract(inputreth);
        expect(buypriceref).to.equal(buyprice);

        // SELL 
        let inputnuma = ethers.parseEther("1000");
        let sellpricerefnofees = inputnuma*balvaultWei/(numaSupply);
        let sellpriceref = (sellpricerefnofees* BigInt(sellfee))/BigInt(feedenom);
        let sellprice = await Vault1.getSellNumaSimulateExtract(inputnuma);
        //expect(sellpriceref).to.equal(sellprice); 
        expect(sellpriceref).to.be.closeTo(sellprice,epsilon); 

      });

      it('with rETH in the vault 3/4 time decay', async () => 
      {
        //await sendEthToVault();
        let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);
        let numaSupply = await numa.totalSupply();
        let buyfee = await VM.buy_fee();
        let sellfee = await VM.sell_fee();
        let feedenom = 1000;


        let removedSupply = ethers.parseEther("4000000");
        await VM.setDecayValues(removedSupply,400*24*3600,0,0,0);
        console.log(numaSupply);

        await VM.startDecay();
        // change heartbeats for testing purpose
        //await Vault1.setOracle(VO_ADDRESScustomHeartbeat);// no need if using vault from fixture
        await nuAM.removeNuAsset(NUUSD_ADDRESS);
        await nuAM.removeNuAsset(NUBTC_ADDRESS);
                   
        await nuAM.addNuAsset(NUUSD_ADDRESS,configArbi.PRICEFEEDETHUSD,400*86400);
        await nuAM.addNuAsset(NUBTC_ADDRESS,configArbi.PRICEFEEDBTCETH,400*86400);
        await time.increase(300*24*3600-4);// don't know why it gives me 5 more seconds

        numaSupply = numaSupply - removedSupply/ BigInt(4);

        let numaSupplyFromVM = await VM.getNumaSupply();

        console.log(numaSupply);
        console.log(numaSupplyFromVM);

        expect(numaSupply).to.be.closeTo(numaSupplyFromVM,epsilon);

    
        // BUY
        let inputreth = ethers.parseEther("2");
        let buypricerefnofees = inputreth*(numaSupply)/(balvaultWei);
        console.log(buypricerefnofees);
        // fees
        let buypriceref = (buypricerefnofees* BigInt(buyfee))/BigInt(feedenom);
        console.log(buypriceref);

        let supplyModi = await VM.getNumaSupply();
        console.log(supplyModi);

        let buyprice = await Vault1.getBuyNumaSimulateExtract(inputreth);
        expect(buypriceref).to.be.closeTo(buyprice,epsilon);

        // SELL 
        let inputnuma = ethers.parseEther("1000");
        let sellpricerefnofees = inputnuma*balvaultWei/(numaSupply);
        let sellpriceref = (sellpricerefnofees* BigInt(sellfee))/BigInt(feedenom);
        let sellprice = await Vault1.getSellNumaSimulateExtract(inputnuma);
        //expect(sellpriceref).to.equal(sellprice); 
        expect(sellpriceref).to.be.closeTo(sellprice,epsilon); 

      });

      it('with rETH in the vault decay over', async () => 
      {
        //await sendEthToVault();
        let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);
        let numaSupply = await numa.totalSupply();
        let buyfee = await VM.buy_fee();
        let sellfee = await VM.sell_fee();
        let feedenom = 1000;


        let removedSupply = numaSupply / BigInt(2);
        await VM.setDecayValues(removedSupply,400*24*3600,0,0,0);


        await VM.startDecay();
        // change heartbeats for testing purpose
        //await Vault1.setOracle(VO_ADDRESScustomHeartbeat);
        await nuAM.removeNuAsset(NUUSD_ADDRESS);
        await nuAM.removeNuAsset(NUBTC_ADDRESS);
                   
        await nuAM.addNuAsset(NUUSD_ADDRESS,configArbi.PRICEFEEDETHUSD,402*86400);
        await nuAM.addNuAsset(NUBTC_ADDRESS,configArbi.PRICEFEEDBTCETH,402*86400);
        await time.increase(401*24*3600);

        //numaSupply = numaSupply - removedSupply/ BigInt(4);

        // BUY
        let inputreth = ethers.parseEther("2");
        let buypricerefnofees = inputreth*(numaSupply)/(balvaultWei);
        // fees
        let buypriceref = (buypricerefnofees* BigInt(buyfee))/BigInt(feedenom);
        let buyprice = await Vault1.getBuyNumaSimulateExtract(inputreth);
        expect(buypriceref).to.equal(buyprice);

        // SELL 
        let inputnuma = ethers.parseEther("1000");
        let sellpricerefnofees = inputnuma*balvaultWei/(numaSupply);
        let sellpriceref = (sellpricerefnofees* BigInt(sellfee))/BigInt(feedenom);
        let sellprice = await Vault1.getSellNumaSimulateExtract(inputnuma);
        //expect(sellpriceref).to.equal(sellprice); 
        expect(sellpriceref).to.be.closeTo(sellprice,epsilon); 

      });


      it('with rETH in the vault decay over restart new decay', async () => 
      {

        //await sendEthToVault();
        let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);
        let numaSupply = await numa.totalSupply();
        let buyfee = await VM.buy_fee();
        let sellfee = await VM.sell_fee();
        let feedenom = 1000;


        let removedSupply = numaSupply / BigInt(2);
        await VM.setDecayValues(removedSupply,100*24*3600,0,0,0);


        await VM.startDecay();
        // change heartbeats for testing purpose
        //await Vault1.setOracle(VO_ADDRESScustomHeartbeat);
        await nuAM.removeNuAsset(NUUSD_ADDRESS);
        await nuAM.removeNuAsset(NUBTC_ADDRESS);
                   
        await nuAM.addNuAsset(NUUSD_ADDRESS,configArbi.PRICEFEEDETHUSD,402*86400);
        await nuAM.addNuAsset(NUBTC_ADDRESS,configArbi.PRICEFEEDBTCETH,402*86400);
        await time.increase(101*24*3600);

  

        await VM.setDecayValues(removedSupply,100*24*3600,0,0,0);
        await VM.startDecay();


        await time.increase(25*24*3600);//1/4
        numaSupply = numaSupply - BigInt(3)*removedSupply/ BigInt(4);

        // BUY
        let inputreth = ethers.parseEther("2");
        let buypricerefnofees = inputreth*(numaSupply)/(balvaultWei);
        // fees
        let buypriceref = (buypricerefnofees* BigInt(buyfee))/BigInt(feedenom);
        let buyprice = await Vault1.getBuyNumaSimulateExtract(inputreth);
        expect(buypriceref).to.equal(buyprice);

        // SELL 
        let inputnuma = ethers.parseEther("1000");
        let sellpricerefnofees = inputnuma*balvaultWei/(numaSupply);
        let sellpriceref = (sellpricerefnofees* BigInt(sellfee))/BigInt(feedenom);
        let sellprice = await Vault1.getSellNumaSimulateExtract(inputnuma);
        //expect(sellpriceref).to.equal(sellprice); 
        expect(sellpriceref).to.be.closeTo(sellprice,epsilon); 

      });


      it('with rETH in the vault constant decay', async () => 
      {


      

      });



      it('with rETH in the vault decay over cancel decay', async () => 
      {
        //await sendEthToVault();
        let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);
        let numaSupply = await numa.totalSupply();
        let buyfee = await VM.buy_fee();
        let sellfee = await VM.sell_fee();
        let feedenom = 1000;


        let removedSupply = numaSupply / BigInt(2);
        await VM.setDecayValues(removedSupply,400*24*3600,0,0,0);


        await VM.startDecay();
        // change heartbeats for testing purpose
        //await Vault1.setOracle(VO_ADDRESScustomHeartbeat);
        await nuAM.removeNuAsset(NUUSD_ADDRESS);
        await nuAM.removeNuAsset(NUBTC_ADDRESS);
                   
        await nuAM.addNuAsset(NUUSD_ADDRESS,configArbi.PRICEFEEDETHUSD,402*86400);
        await nuAM.addNuAsset(NUBTC_ADDRESS,configArbi.PRICEFEEDBTCETH,402*86400);
        await time.increase(401*24*3600);

  

        await VM.setDecayValues(0,0,0,0,0);

        await VM.startDecay();
        // BUY
        let inputreth = ethers.parseEther("2");
        let buypricerefnofees = inputreth*(numaSupply)/(balvaultWei);
        // fees
        let buypriceref = (buypricerefnofees* BigInt(buyfee))/BigInt(feedenom);
        let buyprice = await Vault1.getBuyNumaSimulateExtract(inputreth);
        expect(buypriceref).to.equal(buyprice);

        // SELL 
        let inputnuma = ethers.parseEther("1000");
        let sellpricerefnofees = inputnuma*balvaultWei/(numaSupply);
        let sellpriceref = (sellpricerefnofees* BigInt(sellfee))/BigInt(feedenom);
        let sellprice = await Vault1.getSellNumaSimulateExtract(inputnuma);
        //expect(sellpriceref).to.equal(sellprice); 
        expect(sellpriceref).to.be.closeTo(sellprice,epsilon); 

      });

      


      it('with rETH in the vault and minted nuAssets', async () => 
      {
        // mint synthetics
        // 100000 nuUSD
        let nuUSDamount = ethers.parseEther("100000");
        await nuUSD.connect(owner).mint(defaultAdmin,nuUSDamount);
        //await sendEthToVault();
        let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);
        let numaSupply = await numa.totalSupply();
        let buyfee = await VM.buy_fee();
        let sellfee = await VM.sell_fee();
        let feedenom = 1000;

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
        let buyprice = await Vault1.getBuyNumaSimulateExtract(inputreth);
        expect(buypriceref).to.be.closeTo(buyprice, epsilon);

        // SELL 
        let inputnuma = ethers.parseEther("1000");
        let sellpricerefnofees = inputnuma*(balvaultWei - synthValuerEth)/(numaSupply);
        let sellpriceref = (sellpricerefnofees* BigInt(sellfee))/BigInt(feedenom);
        let sellprice = await Vault1.getSellNumaSimulateExtract(inputnuma); 
        expect(sellpriceref).to.be.closeTo(sellprice, epsilon);
      });

      it('with rETH in the vault', async () => 
      {
        //await sendEthToVault();
        let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);
        let numaSupply = await numa.totalSupply();
        let buyfee = await VM.buy_fee();
        let sellfee = await VM.sell_fee();
        let feedenom = 1000;

  

        // BUY
        let inputreth = ethers.parseEther("2");
        let buypricerefnofees = inputreth*numaSupply/(BigInt(decaydenom/100)*balvaultWei);
        // fees
        let buypriceref = (buypricerefnofees* BigInt(buyfee))/BigInt(feedenom);
        let buyprice = await Vault1.getBuyNumaSimulateExtract(inputreth);
        expect(buypriceref).to.equal(buyprice);

        // SELL 
        let inputnuma = ethers.parseEther("1000");
        let sellpricerefnofees = BigInt(decaydenom/100)*inputnuma*balvaultWei/(numaSupply);
        let sellpriceref = (sellpricerefnofees* BigInt(sellfee))/BigInt(feedenom);
        let sellprice = await Vault1.getSellNumaSimulateExtract(inputnuma);
        expect(sellpriceref).to.be.closeTo(sellprice,epsilon); 
      });

      it('with rETH in the vault and start decay and rebase', async () => 
      {
        // change heartbeat for time simulation
        await nuAM.removeNuAsset(NUUSD_ADDRESS);
        await nuAM.removeNuAsset(NUBTC_ADDRESS);

        await nuAM.addNuAsset(NUUSD_ADDRESS,configArbi.PRICEFEEDETHUSD,26*86400);
        await nuAM.addNuAsset(NUBTC_ADDRESS,configArbi.PRICEFEEDBTCETH,26*86400);

        //await sendEthToVault();
        await time.increase(25*3600);
        let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);
        let numaSupply = await numa.totalSupply();
        let buyfee = await VM.buy_fee();
        let sellfee = await VM.sell_fee();
        let feedenom = 1000;


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
        await Vault1.setRwdAddress(await signer4.getAddress(),false);

        let [estimateRewards,newvalue] = await Vault1.rewardsValue();

        console.log(estimateRewards);
        console.log(lastprice);
        console.log(newvalue);


        expect(newvalue).to.equal(newprice);
        

        let estimateRewardsEth = estimateRewards*newprice;
        let rwdEth = balvaultWei*(newprice - lastprice);        
        expect(estimateRewardsEth).to.equal(rwdEth);
        
        // price should stay the same (with ratio as rEth is now worth more)
        let ratio = newprice/lastprice;
        // BUY
        let inputreth = ethers.parseEther("2");
        let buypricerefnofees = ratio*inputreth*numaSupply/(BigInt(decaydenom/100)*balvaultWei);
        
        // fees
        let buypriceref = (buypricerefnofees* BigInt(buyfee))/BigInt(feedenom);
        let buyprice = await Vault1.getBuyNumaSimulateExtract(inputreth);
        let numaSupplyVM = await VM.getNumaSupply();
        console.log(numaSupplyVM);
        console.log(numaSupply);
        expect(buypriceref).to.equal(buyprice);

        // SELL 
        let inputnuma = ethers.parseEther("1000");
        let sellpricerefnofees = BigInt(decaydenom/100)*inputnuma*balvaultWei/(numaSupply*ratio);
        
        let sellpriceref = (sellpricerefnofees* BigInt(sellfee))/BigInt(feedenom);
        let sellprice = await Vault1.getSellNumaSimulateExtract(inputnuma);        
        expect(sellpriceref).to.be.closeTo(sellprice,epsilon); 



        // extract and price should stays the same
        await Vault1.extractRewards();
        let balrwd = await rEth_contract.balanceOf(await signer4.getAddress());
        expect(estimateRewards).to.equal(balrwd);

        // check prices
        buyprice = await Vault1.getBuyNumaSimulateExtract(inputreth);


        expect(buypriceref).to.equal(buyprice);
        sellprice = await Vault1.getSellNumaSimulateExtract(inputnuma);
        expect(sellpriceref).to.be.closeTo(sellprice,epsilon); 


      });
    
    });

  describe('#buy/sell tests', () => {


    it('buy with rEth', async () => 
    {
      let buypricerefnofees = (ethers.parseEther("2")*ethers.parseEther("10000000"))/vault1Bal;
      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);
      //await sendEthToVault();
      // BUY
      // should be paused by default 
      await expect(Vault1.buy(ethers.parseEther("2"),buypriceref,await signer2.getAddress())).to.be.reverted;
      await Vault1.unpause();
      await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));
      await Vault1.buy(ethers.parseEther("2"),buypriceref,await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
      let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
      expect(balbuyer).to.equal(buypriceref);
      expect(bal1).to.equal(vault1Bal + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
      expect(balfee).to.equal(fees);
    });

    it('sell to rEth', async () => 
    {
      //await sendEthToVault();

      let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);
      let numaSupply = await numa.totalSupply();
     
      let sellfee = await VM.sell_fee();
      let feedenom = 1000;

      // SELL 
      let inputnuma = ethers.parseEther("1000");
      let sellpricerefnofees = inputnuma*balvaultWei/(numaSupply);
      let sellpriceref = (sellpricerefnofees* BigInt(sellfee))/BigInt(feedenom);
      // should be paused by default 
      let balBefore = await numa.balanceOf(await owner.getAddress());
      await expect(Vault1.sell(inputnuma,sellpriceref-epsilon,await signer2.getAddress())).to.be.reverted;
      await Vault1.unpause();
      await numa.connect(owner).approve(VAULT1_ADDRESS,inputnuma);
      await Vault1.sell(inputnuma,sellpriceref - epsilon,await signer2.getAddress());
      let numaSupplyAfter = await numa.totalSupply();
      let balseller = await rEth_contract.balanceOf(await signer2.getAddress());
      let bal1 = numaSupply - numaSupplyAfter;
      let bal2 = balBefore - (await numa.balanceOf(await owner.getAddress()));
      let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

      // 1% fees
      let fees = BigInt(1) * sellpricerefnofees/BigInt(100);
      //expect(balseller).to.equal(sellpriceref);
      expect(balseller).to.be.closeTo(sellpriceref,epsilon);
      expect(bal1).to.equal(inputnuma);
      expect(bal2).to.equal(inputnuma);
      expect(balfee).to.be.closeTo(fees,epsilon);

     
    });

    it('buy & extract if rwd > threshold', async () => 
    {
      // change heartbeat for time simulation
      await nuAM.removeNuAsset(NUUSD_ADDRESS);
      await nuAM.removeNuAsset(NUBTC_ADDRESS);
      
      await nuAM.addNuAsset(NUUSD_ADDRESS,configArbi.PRICEFEEDETHUSD,26*86400);
      await nuAM.addNuAsset(NUBTC_ADDRESS,configArbi.PRICEFEEDBTCETH,26*86400);

      let buypricerefnofees = (ethers.parseEther("2")*ethers.parseEther("10000000"))/(vault1Bal);
      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);
      //await sendEthToVault();
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
      await Vault1.setRwdAddress(await signer4.getAddress(),false);
    
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
      await Vault1.buy(ethers.parseEther("2"),ratio*buypriceref,await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
      let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
      expect(balbuyer).to.equal(ratio*buypriceref);
      let balrwd = await rEth_contract.balanceOf(await signer4.getAddress());
      expect(balrwd).to.equal(estimateRewards);
      expect(bal1).to.equal(vault1Bal + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100) - balrwd);
      expect(balfee).to.equal(fees);
      
    });

    it('sell & extract if rwd > threshold', async () => 
    {
      // TODO
    });

    it('buy & no extract if rwd < threshold', async () => 
    {
      // change heartbeat for time simulation
      await nuAM.removeNuAsset(NUUSD_ADDRESS);
      await nuAM.removeNuAsset(NUBTC_ADDRESS);
       
      await nuAM.addNuAsset(NUUSD_ADDRESS,configArbi.PRICEFEEDETHUSD,26*86400);
      await nuAM.addNuAsset(NUBTC_ADDRESS,configArbi.PRICEFEEDBTCETH,26*86400);


      let buypricerefnofees = (ethers.parseEther("2")*ethers.parseEther("10000000"))/(vault1Bal);
      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);
      //await sendEthToVault();
      await time.increase(25*3600);
      let balvaultWei = await rEth_contract.balanceOf(VAULT1_ADDRESS);

      // set a mock rEth oracle to simulate rebase
      let VMO = await ethers.deployContract("VaultMockOracle",[]);
      await VMO.waitForDeployment();
      let VMO_ADDRESS= await VMO.getAddress();
      await Vault1.setOracle(VMO_ADDRESS);
      // set rwd address
      await Vault1.setRwdAddress(await signer4.getAddress(),false);
    
      // set new price, simulate a 100% rebase
      let lastprice = await Vault1.last_lsttokenvalueWei();
      let newprice = (BigInt(2)*lastprice);
      await VMO.setPrice(newprice);
      
      let [estimateRewards,newvalue] = await Vault1.rewardsValue();
      expect(newvalue).to.equal(newprice);
      //price made x 2 so rewards should be half balance
      expect(estimateRewards).to.equal(vault1Bal / BigInt(2));

      // change threshold so that we can not extract
      let newThreshold = estimateRewards+ethers.parseEther("1");
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
      await Vault1.buy(ethers.parseEther("2"),buypriceref,await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
      let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
      //expect(balbuyer).to.equal(ratio*buypriceref);
      expect(balbuyer).to.equal(buypriceref);
      let balrwd = await rEth_contract.balanceOf(await signer4.getAddress());
      expect(balrwd).to.equal(0);// no extraction thanks to new threshold
      expect(bal1).to.equal(vault1Bal + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100) - balrwd);
      expect(balfee).to.equal(fees);
    });

    it('sell & no extract if rwd < threshold', async () => 
    {
      // TODO
    });


    it('buy with rEth with decay starting time', async () => 
    {
      let buypricerefnofees = (ethers.parseEther("2")*ethers.parseEther("10000000"))/(vault1Bal);

      buypricerefnofees = (buypricerefnofees * BigInt(100))/BigInt(decaydenom);
      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

      //await sendEthToVault();
      // BUY
      // paused by default 
      await Vault1.unpause();
      await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));


      await Vault1.buy(ethers.parseEther("2"),buypriceref,await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      //console.log("numa minted start decay ",balbuyer);
      bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
      let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
      expect(balbuyer).to.equal(buypriceref);
      expect(bal1).to.equal(vault1Bal + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
      expect(balfee).to.equal(fees);
    });

    it('buy with rEth with decay half time', async () => 
    {
      // change heartbeat for time simulation
      await nuAM.removeNuAsset(NUUSD_ADDRESS);
      await nuAM.removeNuAsset(NUBTC_ADDRESS);
             
      await nuAM.addNuAsset(NUUSD_ADDRESS,configArbi.PRICEFEEDETHUSD,26*86400);
      await nuAM.addNuAsset(NUBTC_ADDRESS,configArbi.PRICEFEEDBTCETH,26*86400);


      let buypricerefnofees = (ethers.parseEther("2")*ethers.parseEther("10000000"))/(vault1Bal);

      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

      //await sendEthToVault();
      // BUY
      // paused by default 
      await Vault1.unpause();
      await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));


      // wait 15 days
      await time.increase(15*24*3600);

      await Vault1.buy(ethers.parseEther("2"),buypriceref - epsilon,await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      //console.log("numa minted half decay ",balbuyer);
      bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
      let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
      
      expect(balbuyer).to.be.closeTo(buypriceref, epsilon);
      expect(bal1).to.equal(vault1Bal + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
      expect(balfee).to.equal(fees);

    });

    it('buy with rEth with decay over', async () => 
    {
      // change heartbeat for time simulation
      await nuAM.removeNuAsset(NUUSD_ADDRESS);
      await nuAM.removeNuAsset(NUBTC_ADDRESS);
                   
      await nuAM.addNuAsset(NUUSD_ADDRESS,configArbi.PRICEFEEDETHUSD,31*86400);
      await nuAM.addNuAsset(NUBTC_ADDRESS,configArbi.PRICEFEEDBTCETH,31*86400);

      // test
      await Vault1.setRwdAddress(await signer4.getAddress(),false);
      //await Vault1.setOracle(VO_ADDRESScustomHeartbeat);

      let buypricerefnofees = (ethers.parseEther("2")*ethers.parseEther("10000000"))/(vault1Bal);
      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

      //await sendEthToVault();
      // BUY
      //  paused by default 
      await Vault1.unpause();
      await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));

      // wait 30 days
      await time.increase(30*24*3600);
    
      await Vault1.buy(ethers.parseEther("2"),buypriceref,await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      //console.log("numa minted end decay ",balbuyer);
      bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
      let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
      expect(balbuyer).to.equal(buypriceref);
      expect(bal1).to.equal(vault1Bal + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
      expect(balfee).to.equal(fees);
    });

    it('buy with rEth and synth supply', async () => 
    {
      //await sendEthToVault();

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
      let buypricerefnofees = ethers.parseEther("2")*ethers.parseEther("10000000")/(vault1Bal - fullSynthValueInrEth);

      let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

      // BUY
      // paused by default 
      await expect(Vault1.buy(ethers.parseEther("2"),buypriceref - epsilon,await signer2.getAddress())).to.be.reverted;
      await Vault1.unpause();
      await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));
      await Vault1.buy(ethers.parseEther("2"),buypriceref- epsilon,await signer2.getAddress());

      let balbuyer = await numa.balanceOf(await signer2.getAddress());
      bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
      let balfee = await rEth_contract.balanceOf(await signer3.getAddress());

      let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);

      expect(balbuyer).to.be.closeTo(buypriceref, epsilon);
      expect(bal1).to.equal(vault1Bal + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));
      expect(balfee).to.equal(fees);
    });
  });

  it('test withdraw', async function () 
  {
    //await sendEthToVault();
    let balbeforeLST = await rEth_contract.balanceOf(await owner.getAddress());    
    await Vault1.withdrawToken(rETH_ADDRESS,ethers.parseEther("50"),await owner.getAddress());
    let balafterLST = await rEth_contract.balanceOf(await owner.getAddress());
    expect(balafterLST - balbeforeLST).to.equal(ethers.parseEther("50"));


    await Vault1.revokeWithdraw();

    await expect(Vault1.withdrawToken(rETH_ADDRESS,ethers.parseEther("50"),await owner.getAddress())).to.be.reverted;

  });

  it('with another vault', async function () 
  {
    // vault1 needs some rETH 
    //await sendEthToVault();

    //
    let address2 = "0x513c7e3a9c69ca3e22550ef58ac1c0088e918fff";
    await helpers.impersonateAccount(address2);
    const impersonatedSigner2 = await ethers.getSigner(address2);
    await helpers.setBalance(address2,ethers.parseEther("10"));
    const wstEth_contract  = await hre.ethers.getContractAt(ERC20abi, wstETH_ADDRESS);
    //
    // await VO.setTokenFeed(wstETH_ADDRESS,wstETH_FEED);
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
    [numa_address,wstETH_ADDRESS,ethers.parseEther("1"),VO_ADDRESS2,minterAddress]);


    await Vault2.waitForDeployment();
    let VAULT2_ADDRESS = await Vault2.getAddress();
    console.log('vault wstETH address: ', VAULT2_ADDRESS);

    await VM.addVault(VAULT2_ADDRESS);
    await Vault2.setVaultManager(VM_ADDRESS);

    // add vault as a minter
    const Minter = await ethers.getContractFactory('NumaMinter');
    let theMinter = await Minter.attach(minterAddress);
    await theMinter.addToMinters(VAULT2_ADDRESS);


    // price before feeding vault2

    buyprice = await Vault1.getBuyNumaSimulateExtract(ethers.parseEther("2"));
    let buyprice2 = await Vault2.getBuyNumaSimulateExtract(ethers.parseEther("2"));

    
    //vault1Bal = BigInt(ethers.formatEther(vault1Bal));
    let buypricerefnofees = (ethers.parseEther("2")*ethers.parseEther("10000000"))/(vault1Bal);
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

    let totalBalancerEth = vault1Bal + (ethers.parseEther("100")*BigInt(latestRoundPrice2))/BigInt(latestRoundPrice);
    let totalBalancewstEth = ethers.parseEther("100") + (vault1Bal*BigInt(latestRoundPrice))/BigInt(latestRoundPrice2);

    let buypricerefnofeesrEth = (ethers.parseEther("2")*ethers.parseEther("10000000"))/(totalBalancerEth);
    let buypricerefnofeeswstEth = (ethers.parseEther("2")*ethers.parseEther("10000000"))/(totalBalancewstEth);

    buypriceref = buypricerefnofeesrEth - BigInt(5) * buypricerefnofeesrEth/BigInt(100);
    buypriceref2 = buypricerefnofeeswstEth - BigInt(5) * buypricerefnofeeswstEth/BigInt(100);

    buyprice = await Vault1.getBuyNumaSimulateExtract(ethers.parseEther("2"));   
    buyprice2 = await Vault2.getBuyNumaSimulateExtract(ethers.parseEther("2"));

    expect(buypriceref).to.be.closeTo(buyprice, epsilon);
    expect(buypriceref2).to.be.closeTo(buyprice2, epsilon);

    // make vault Numa minter
    //await numa.grantRole(roleMinter, VAULT2_ADDRESS);
    // set fee address
    await Vault2.setFeeAddress(await signer3.getAddress(),false);

    // unpause it
    await Vault2.unpause();
    // approve wstEth to be able to buy
    await wstEth_contract.connect(owner).approve(VAULT2_ADDRESS,ethers.parseEther("2"));


    let balfee = await wstEth_contract.balanceOf(await signer3.getAddress());
 
    await Vault2.buy(ethers.parseEther("2"),buypriceref2 - epsilon,await signer2.getAddress());

    // let balbuyer = await numa.balanceOf(await signer2.getAddress());
    // bal1 = await wstEth_contract.balanceOf(VAULT2_ADDRESS);
    // balfee = await wstEth_contract.balanceOf(await signer3.getAddress());

    // let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);
  
    // expect(balbuyer).to.be.closeTo(buypriceref2, epsilon);
    // expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));

    // expect(balfee).to.equal(fees);
  });

  it('Extract rewards', async function () {
  
    //await sendEthToVault();
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


    // MockRwdReceiverContract/MockRwdReceiverContract_Deposit
    let rwdreceiver = await ethers.deployContract("MockRwdReceiverContract_Deposit",
    []
    );
    await rwdreceiver.waitForDeployment();

    console.log("rwd address");
    console.log(await rwdreceiver.getAddress());

    await Vault1.setRwdAddress(await rwdreceiver.getAddress(),true);

    let [estimateRewards,newvalue] = await Vault1.rewardsValue();

    expect(newvalue).to.equal(newprice);

    let estimateRewardsEth = estimateRewards*newprice;
    let rwdEth = vault1Bal*(newprice - lastprice);
    expect(estimateRewardsEth).to.equal(rwdEth);

    await Vault1.extractRewards();

    let test = await rwdreceiver.test();
    expect(test).to.equal(estimateRewards);

    let balrwd = await rEth_contract.balanceOf(await rwdreceiver.getAddress());
    console.log("rewards balance");
    console.log(balrwd);
    expect(estimateRewards).to.equal(balrwd);

    let [estimateRewardsAfter,newvalueAfter] = await Vault1.rewardsValue();
    expect(newvalueAfter).to.equal(newprice);
    expect(estimateRewardsAfter).to.equal(0);
    await expect(Vault1.extractRewards()).to.be.reverted;
  });



  it('sell fee scaling', async function () 
  {
    // 
    // evaluate sell fee and sell price
    let sellFee = await VM.getSellFeeOriginal();
    let sellFeeScaling = await VM.getSellFeeScaling();
    
    expect(sellFee).to.equal(sellFeeScaling[0]);

    // we will check that output increases/decreases
    let output = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("100"));

      
  

    // set sell fee scaling parameters
    await VM.setSellFeeParameters(21000,
      10,
      30,
     600,
     1200,      
     500);

    


    // time debase
    await time.increase(600*10);
    // should debase by 100
    let sellFeeScaling2 = await VM.getSellFeeScaling();
    expect(sellFeeScaling2[0]).to.equal(sellFeeScaling[0] - BigInt(100));
    let output2 = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("100"));
    expect(output2).to.be.below(output);
    console.log(output);
    console.log(output2);

    // time debase
    await time.increase(600*20);
    // should debase by 200
    sellFeeScaling2 = await VM.getSellFeeScaling();
    expect(sellFeeScaling2[0]).to.equal(sellFeeScaling[0] - BigInt(300));
    let output3 = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("100"));
    expect(output3).to.be.below(output2);

    // reach min 
     // time debase
     await time.increase(600*20);
     // should debase by 200
     sellFeeScaling2 = await VM.getSellFeeScaling();
     expect(sellFeeScaling2[0]).to.equal(BigInt(500));
     let output4 = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("100"));
     expect(output4).to.be.below(output3);

    // time rebase
    // set sell fee scaling parameters
    await VM.setSellFeeParameters(19000,
      10,
      30,
     600,
     1200,      
     500);
     await time.increase(1200*10);
     // should rebase by 300
     let sellFeeScaling3 = await VM.getSellFeeScaling();
     expect(sellFeeScaling3[0]).to.equal(sellFeeScaling2[0] + BigInt(300));
     let output5 = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("100"));
     expect(output5).to.be.above(output4);
    // time rebase
    await time.increase(1200*10);
    // should rebase by 300
    let sellFeeScaling4 = await VM.getSellFeeScaling();
    expect(sellFeeScaling4[0]).to.equal(sellFee);
    let output6 = await Vault1.getSellNumaSimulateExtract(ethers.parseEther("100"));
    expect(output6).to.be.above(output5);



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
    [UPTIME_FEED]
    );
    await nuAM2.waitForDeployment();
    let NUAM_ADDRESS2 = await nuAM2.getAddress();



    let fullSynthValueInEth = await nuAM.getTotalSynthValueEth();
    let fullSynthValueInrEth = (fullSynthValueInEth*BigInt(10 ** decimals) / BigInt(latestRoundPrice));

    // TODO: some imprecision (10-6 numa)
    let buypricerefnofees = ethers.parseEther("2")*ethers.parseEther("10000000")/(vault1Bal - fullSynthValueInrEth);
    let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

    // BUY
    // should be paused by default 
    await Vault1.unpause();
    await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));
    await Vault1.buy(ethers.parseEther("2"),buypriceref - epsilon,await signer2.getAddress());

    let balbuyer = await numa.balanceOf(await signer2.getAddress());
    bal1 = await rEth_contract.balanceOf(VAULT1_ADDRESS);
    let balfee = await rEth_contract.balanceOf(await signer3.getAddress());
    let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);

    expect(balbuyer).to.be.closeTo(buypriceref, epsilon);

  });


  it('Fees', async () => 
  {
  
    await expect(VM.setBuyFee(ethers.parseEther("1.001"))).to.be.reverted;
    await expect(VM.setSellFee(ethers.parseEther("1.001"))).to.be.reverted;
    await expect(VM.setBuyFee(ethers.parseEther("0.8"))).to.not.be.reverted;
    await expect(VM.setSellFee(ethers.parseEther("0.8"))).to.not.be.reverted;
    await expect(Vault1.setFee(200)).to.not.be.reverted;
    await expect(Vault1.setFee(1001)).to.be.reverted;

  });
  it('Pausable', async () => 
  {
    //await sendEthToVault();
    // BUY
    // should be paused by default 
    await rEth_contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("2"));
    await expect(Vault1.buy(ethers.parseEther("1"),0,await signer2.getAddress())).to.be.reverted;
    await Vault1.unpause();
    await expect(Vault1.buy(ethers.parseEther("1"),0,await signer2.getAddress())).to.not.be.reverted;
    await Vault1.pause();
    await expect(Vault1.buy(ethers.parseEther("1"),0,await signer2.getAddress())).to.be.reverted;
  });

  it('Owner', async function () 
  {
    let addy = "0x1230000000000000000000000000000000000004";
    let newBuySellFee = ethers.parseEther("0.9");// 10%
    let newFees = 20; // 2%
    let newRwdThreshold = ethers.parseEther("1");




    //
    await expect( Vault1.connect(signer2).setOracle(addy)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());



    await expect( Vault1.connect(signer2).setVaultManager(addy)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( Vault1.connect(signer2).setRwdAddress(addy,false)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( Vault1.connect(signer2).setFeeAddress(addy,false)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( VM.connect(signer2).setSellFee(newBuySellFee)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( VM.connect(signer2).setBuyFee(newBuySellFee)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( Vault1.connect(signer2).setFee(newFees)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    await expect( Vault1.connect(signer2).setRewardsThreshold(newRwdThreshold)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());

    //await sendEthToVault();
    // await expect( Vault1.connect(signer2).withdrawToken(await rEth_contract.getAddress(),ethers.parseEther("10"))).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    // .withArgs(await signer2.getAddress());

    await expect( Vault1.connect(signer2).unpause()).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());
    // transfer ownership then unpause should work
    await Vault1.connect(owner).transferOwnership(await signer2.getAddress());
    await Vault1.connect(signer2).acceptOwnership();
    await expect( Vault1.connect(signer2).unpause()).to.not.be.reverted;

    // vault manager
    // await expect( VM.connect(signer2).addToRemovedSupply(addy)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    // .withArgs(await signer2.getAddress());

    // await expect( VM.connect(signer2).removeFromRemovedSupply(addy)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    // .withArgs(await signer2.getAddress());

    await expect( VM.connect(signer2).setNuAssetManager(addy)).to.be.revertedWithCustomError(Vault1,"OwnableUnauthorizedAccount",)
    .withArgs(await signer2.getAddress());


  });



});

