const { getPoolData, initPoolETH, initPool, addLiquidity, weth9, artifacts, linkLibraries } = require("../../scripts/Utils.js");
//const { time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { time, takeSnapshot } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const fs = require('fs');

const configRelativePathArbi = '../../configTestArbitrum.json';
const configArbi = require(configRelativePathArbi);

let LOG = true;

const ERC20abi = [
  "function balanceOf(address owner) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function transfer(address to, uint amount) returns (bool)",
  "function approve(address spender, uint amount)",
  "event Transfer(address indexed from, address indexed to, uint amount)"
];



async function deployNumaNumaPoolnuAssetsPrinters() {

  let { DEPLOY_UNISWAP, WETH_ADDRESS, FACTORY_ADDRESS,
    POSITION_MANAGER_ADDRESS, PRICEFEEDETHUSD,PRICEFEEDBTCETH, INTERVAL_SHORT, INTERVAL_LONG, FEE } = configArbi;

  let USDC_ADDRESS = "0xaf88d065e77c8cC2239327C5EDb3A432268e5831";// arbitrum usdc
  let signer, signer2;
  let numaOwner;
  let numa;
  // 
  let nuUSD;
  let nuusd_address;

  //
  let nuBTC;
  let nubtc_address;

  // uniswap
  let nonfungiblePositionManager;
  let wethContract;
  let usdcContract;
  // oracle
  let oracleAddress;
  let factory;
  let snapshotGlobal = await takeSnapshot();;

  //
  [signer, signer2, signer3,signer4] = await ethers.getSigners();


  // Min and Max tick numbers, as a multiple of 60
  const tickMin = -887220;
  const tickMax = 887220;

  let UPTIME_FEED = "0xFdB631F5EE196F0ed6FAa767959853A9F217697D";
  const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));

  let rETH_ADDRESS = configArbi.RETH_ADDRESS;
  let RETH_FEED = configArbi.RETH_FEED;

  let rEth_contract = await hre.ethers.getContractAt(ERC20abi, rETH_ADDRESS);

  // uniswap v3 pool fee
  let _fee = Number(FEE);

  

  // amount to be transfered to signer
  let numaAmount = ethers.parseEther('100000');







  // *** Uniswap ******************************
  if (DEPLOY_UNISWAP == "TRUE") {
    let NFTDescriptor = new ethers.ContractFactory(artifacts.NFTDescriptor.abi, artifacts.NFTDescriptor.bytecode, signer);
    let nftDescriptor = await NFTDescriptor.deploy();

    let NFTDescriptorAddress = await nftDescriptor.getAddress();

    const linkedBytecode = linkLibraries(
      {
        bytecode: artifacts.NonfungibleTokenPositionDescriptor.bytecode,
        linkReferences: {
          "NFTDescriptor.sol": {
            NFTDescriptor: [
              {
                length: 20,
                start: 1681,
              },
            ],
          },
        },
      },
      {
        NFTDescriptor: NFTDescriptorAddress,
      }
    );

    NonfungibleTokenPositionDescriptor = new ethers.ContractFactory(artifacts.NonfungibleTokenPositionDescriptor.abi, linkedBytecode, signer);

    const nativeCurrencyLabelBytes = ethers.encodeBytes32String('WETH');
    nonfungibleTokenPositionDescriptor = await NonfungibleTokenPositionDescriptor.deploy(WETH_ADDRESS, nativeCurrencyLabelBytes);

    let nonfungibleTokenPositionDescriptorAddress = await nonfungibleTokenPositionDescriptor.getAddress();
    const Factory = new ethers.ContractFactory(artifacts.UniswapV3Factory.abi, artifacts.UniswapV3Factory.bytecode, signer);
    factory = await Factory.deploy();
    let NonfungiblePositionManager = new ethers.ContractFactory(artifacts.NonfungiblePositionManager.abi, artifacts.NonfungiblePositionManager.bytecode, signer);
    nonfungiblePositionManager = await NonfungiblePositionManager.deploy(await factory.getAddress(), WETH_ADDRESS, nonfungibleTokenPositionDescriptorAddress);


  }
  else {
    factory = await hre.ethers.getContractAt(artifacts.UniswapV3Factory.abi, FACTORY_ADDRESS);
    nonfungiblePositionManager = await hre.ethers.getContractAt(artifacts.NonfungiblePositionManager.abi, POSITION_MANAGER_ADDRESS);
  }

  FACTORY_ADDRESS = await factory.getAddress();



  wethContract = await hre.ethers.getContractAt(weth9.WETH9.abi, WETH_ADDRESS);
  usdcContract = await hre.ethers.getContractAt(ERC20abi, USDC_ADDRESS);
  
  // get pool price from chainlink USD/ETH PRICEFEEDETHUSD
  let chainlinkInstance = await hre.ethers.getContractAt(artifacts.AggregatorV3, PRICEFEEDETHUSD);
  let latestRoundData = await chainlinkInstance.latestRoundData();
  let latestRoundPrice = Number(latestRoundData.answer);
  let decimals = Number(await chainlinkInstance.decimals());
  let price = latestRoundPrice / 10 ** decimals;
  if (LOG)
    console.log(`Chainlink Price USD/ETH: ${price}`);

  // get some weth
  await wethContract.connect(signer).deposit({
    value: ethers.parseEther('100'),
  });

  // get some usdc
  const addressWhaleUSDC = "0x70d95587d40a2caf56bd97485ab3eec10bee6336";
  await helpers.impersonateAccount(addressWhaleUSDC);
  const impersonatedSignerUSDC = await ethers.getSigner(addressWhaleUSDC);
  await helpers.setBalance(addressWhaleUSDC, ethers.parseEther("10"));
  // transfer to signer so that it can buy numa
  await usdcContract.connect(impersonatedSignerUSDC).transfer(await signer.getAddress(), ethers.parseUnits("20000000",6));


  // *** Numa deploy
  const Numa = await ethers.getContractFactory('NUMA')
  numa = await upgrades.deployProxy(
    Numa,
    [],
    {
      initializer: 'initialize',
      kind: 'uups'
    }
  )
  await numa.waitForDeployment();

  await numa.mint(
    signer.getAddress(),
    ethers.parseEther("10000000.0")
  );

  numaOwner = signer;
  let numa_address = await numa.getAddress();
  if (LOG)
    console.log(`Numa deployed to: ${numa_address}`);
  // numa at 0.5 usd     
  let EthPriceInNuma = price * 2;
  let USDCPriceInNuma = 2000000000000;// 12 decimals because USDC has 6 decimals
  // create numa/eth univ3 pool
  await initPoolETH(WETH_ADDRESS, numa_address, _fee, EthPriceInNuma, nonfungiblePositionManager, WETH_ADDRESS);

  // create numa/USDC univ3 pool
  console.log("usdc pool**********************");
  await initPoolETH(USDC_ADDRESS, numa_address, _fee, USDCPriceInNuma, nonfungiblePositionManager, USDC_ADDRESS);

  // 10 ethers
  let nbEthers = 10;
  let EthAmountNumaPool = ethers.parseEther(nbEthers.toString());
  let NumaAmountNumaPool = ethers.parseEther((nbEthers * EthPriceInNuma).toString());

  if (LOG)
    console.log(`pool liquidity: ${hre.ethers.formatUnits(EthAmountNumaPool, 18)} / ${hre.ethers.formatUnits(NumaAmountNumaPool, 18)}`);
  // if we run the tests many times on the fork, we increase manually time so we need our deadlines to be 
  // very very large so that we can run the tests many times without relaunching local node
  let offset = 3600 * 100;// we should be able to run 100 tests
  let timestamp = Math.ceil(Date.now() / 1000 + 300 + offset);
  await addLiquidity(
    WETH_ADDRESS,
    numa_address,
    wethContract,
    numa,
    _fee,
    tickMin,
    tickMax,
    EthAmountNumaPool,
    NumaAmountNumaPool,
    BigInt(0),
    BigInt(0),
    signer,
    timestamp,
    nonfungiblePositionManager
  );



  let NUMA_ETH_POOL_ADDRESS = await factory.getPool(
    WETH_ADDRESS,
    numa_address,
    _fee,
  );
  if (LOG)
    console.log('numa eth pool: ', NUMA_ETH_POOL_ADDRESS);

    
  // numa/USDC pool
  let USDCAmountNumaPool = ethers.parseUnits("200000",6);
  let NumaAmountNumaPoolUSDC = ethers.parseEther("400000");


  await addLiquidity(
      USDC_ADDRESS,
      numa_address,
      usdcContract,
      numa,
      _fee,
      tickMin,
      tickMax,
      USDCAmountNumaPool,
      NumaAmountNumaPoolUSDC,
      BigInt(0),
      BigInt(0),
      signer,
      timestamp,
      nonfungiblePositionManager
    );
  let NUMA_USDC_POOL_ADDRESS = await factory.getPool(
      USDC_ADDRESS,
      numa_address,
      _fee,
    );

   if (LOG)
   {
      console.log('numa usdc pool: ', NUMA_USDC_POOL_ADDRESS);
      let balancePoolUSDC = await usdcContract.balanceOf(NUMA_USDC_POOL_ADDRESS);
      let balancePoolNuma = await numa.balanceOf(NUMA_USDC_POOL_ADDRESS);
      console.log('bal pool usdc', hre.ethers.formatUnits(balancePoolUSDC, 6));
      console.log('bal pool numa', hre.ethers.formatUnits(balancePoolNuma, 18));

      console.log('bal pool usdc expected', hre.ethers.formatUnits(USDCAmountNumaPool, 6));
      console.log('bal pool numa expected', hre.ethers.formatUnits(NumaAmountNumaPoolUSDC, 18));
   }
  
    
  const poolContractNuma = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUMA_USDC_POOL_ADDRESS);
  //const poolDataNuma = await getPoolData(poolContractNuma);

  // Deploy vault
   // *********************** nuAssetManager **********************************
   let nuAM = await ethers.deployContract("nuAssetManager",
   [UPTIME_FEED]
   );
   await nuAM.waitForDeployment();
   let NUAM_ADDRESS = await nuAM.getAddress();
   console.log('nuAssetManager address: ', NUAM_ADDRESS);

   // minter contract
   let theMinter = await ethers.deployContract("NumaMinter", []);
   await theMinter.waitForDeployment();
   let MINTER_ADDRESS = await theMinter.getAddress();
   await numa.grantRole(roleMinter, MINTER_ADDRESS);
   await theMinter.setTokenAddress(numa_address);

   // *********************** vaultManager **********************************
   let VM = await ethers.deployContract("VaultManager",
   [numa_address,NUAM_ADDRESS]);
   await VM.waitForDeployment();
   let VM_ADDRESS = await VM.getAddress();
   console.log('vault manager address: ', VM_ADDRESS);

   // *********************** VaultOracle **********************************
  //  VO = await ethers.deployContract("VaultOracleSingle",
  //  [rETH_ADDRESS,RETH_FEED,16*86400,UPTIME_FEED]);
  //  await VO.waitForDeployment();
  //  VO_ADDRESS= await VO.getAddress();
  //  console.log('vault 1 oracle address: ', VO_ADDRESS);


   let VOcustomHeartbeat = await ethers.deployContract("VaultOracleSingle",
   [rETH_ADDRESS,RETH_FEED,402*86400,UPTIME_FEED]);
   await VOcustomHeartbeat.waitForDeployment();
   let VO_ADDRESScustomHeartbeat= await VOcustomHeartbeat.getAddress();
   console.log('vault 1 oracle address: ', VO_ADDRESScustomHeartbeat);



   // *********************** NumaVault rEth **********************************
   let Vault1 = await ethers.deployContract("NumaVault",
   [numa_address,rETH_ADDRESS,ethers.parseEther("1"),VO_ADDRESScustomHeartbeat,MINTER_ADDRESS]);
   await Vault1.waitForDeployment();
   let VAULT1_ADDRESS = await Vault1.getAddress();
   console.log('vault rETH address: ', VAULT1_ADDRESS);

   await VM.addVault(VAULT1_ADDRESS);
   await Vault1.setVaultManager(VM_ADDRESS);

   // fee address
   await Vault1.setFeeAddress(await signer3.getAddress(),false);

   // **************** send rETH to vault to initiate price **************
   // rETH arbitrum whale
   const address = "0x8Eb270e296023E9D92081fdF967dDd7878724424";
   await helpers.impersonateAccount(address);
   const impersonatedSigner = await ethers.getSigner(address);
   await helpers.setBalance(address, ethers.parseEther("10"));
   // transfer to signer so that it can buy numa
   await rEth_contract.connect(impersonatedSigner).transfer(await signer.getAddress(), ethers.parseEther("5"));
   // transfer to vault to initialize price
   // for now 
   let chainlinkInstancerEth = await hre.ethers.getContractAt(artifacts.AggregatorV3, RETH_FEED);
   let latestRoundDatarEth = await chainlinkInstancerEth.latestRoundData();
   let latestRoundPricerEth = Number(latestRoundDatarEth.answer);
   let decimalsrEth = Number(await chainlinkInstancerEth.decimals());
   let pricerEth = latestRoundPricerEth / 10 ** decimalsrEth;
   if (LOG)
     console.log(`Chainlink Price RETH/ETH: ${pricerEth}`);
   // price_pool = EthAmountNumaPool/NumaAmountNumaPool
   // price_ vault = EthVault/numasupply
   let amountEthTosend = (ethers.parseEther("10000000")*EthAmountNumaPool)/NumaAmountNumaPool;
   
   console.log(amountEthTosend);
   amountEthTosend = (amountEthTosend/latestRoundDatarEth.answer)* BigInt(10 ** decimalsrEth) ;
   console.log(amountEthTosend);

   await rEth_contract.connect(impersonatedSigner).transfer(VAULT1_ADDRESS,amountEthTosend);



  // ***********************************  NUMA ORACLE ******************************
  const oracle = await ethers.deployContract("NumaOracle", [USDC_ADDRESS, INTERVAL_SHORT, INTERVAL_LONG, signer.getAddress(),NUAM_ADDRESS]);
  await oracle.waitForDeployment();
  oracleAddress = await oracle.getAddress();
  if (LOG)
    console.log(`numa oracle deployed to: ${oracleAddress}`);

  // ***********************************  NUUSD & PRINTER ******************************
  const NuUSD = await ethers.getContractFactory('nuAsset');
  let defaultAdmin = await signer.getAddress();
  let minter = await signer.getAddress();
  let upgrader = await signer.getAddress();
  nuUSD = await upgrades.deployProxy(
    NuUSD,
    ["nuUSD","NUSD",defaultAdmin, minter, upgrader],
    {
      initializer: 'initialize',
      kind: 'uups'
    }
  );
  await nuUSD.waitForDeployment();
  nuusd_address = await nuUSD.getAddress();

  if (LOG)
    console.log(`nuUSD deployed to: ${nuusd_address}`);

 
  // register nuAsset
  await nuAM.addNuAsset(nuusd_address,configArbi.PRICEFEEDETHUSD,86400);
  //await nuAM.addNuAsset(NUBTC_ADDRESS,configArbi.PRICEFEEDBTCETH,86400);
  

let USDCtoETHConverter = await ethers.deployContract("USDCToEthConverter",
  ["0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3",1000*86400,"0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612",1000*86400,UPTIME_FEED]);
await USDCtoETHConverter.waitForDeployment();
let USDCtoETHConverter_address = await USDCtoETHConverter.getAddress();
if (LOG)
  console.log(`usdc/ETH converter deployed to: ${USDCtoETHConverter_address}`);



  // Deploy printerUSD 
  // address _numaAddress,
  // address _numaMinterAddress,
  // address _numaPool,
  // INumaOracle _oracle,
  // address _vaultManagerAddress

  moneyPrinter = await ethers.deployContract("NumaPrinter",
    [numa_address, MINTER_ADDRESS, NUMA_USDC_POOL_ADDRESS,USDCtoETHConverter_address, oracleAddress, VM_ADDRESS]);
  await moneyPrinter.waitForDeployment();
  moneyPrinter_address = await moneyPrinter.getAddress();
  if (LOG)
    console.log(`printer deployed to: ${moneyPrinter_address}`);


  // add moneyPrinter as a minter
  theMinter.addToMinters(moneyPrinter_address);
  // add vault as a minter
  theMinter.addToMinters(VAULT1_ADDRESS);
  // set printer as a NuUSD minter

  await nuUSD.connect(signer).grantRole(roleMinter, moneyPrinter_address);// owner is NuUSD deployer



  // IMPORTANT: for the uniswap V3 avg price calculations, we need this
  // or else it will revert

  // Get the pools to be as old as INTERVAL_LONG    
  await time.increase(1800);
  let cardinality = 10;
  await poolContractNuma.increaseObservationCardinalityNext(cardinality);

  //
  let USDAmount = 10 * price;
  USDAmount = ethers.parseEther(USDAmount.toString());
  // // mint using printer
  // // TODO: need more, why?
  // //let numaAmountToApprove = 10*price*2;// numa is 50 cts in our tests
  // let numaAmountToApprove = 10 * price * 2 + 10;// numa is 50 cts in our tests
  // let approvalAmount = ethers.parseEther(numaAmountToApprove.toString());
  // await numa.connect(signer).approve(moneyPrinter_address, approvalAmount);
  // await moneyPrinter.mintAssetFromNuma(USDAmount, signer.getAddress());

  
  console.log("****************************"); 
  console.log(WETH_ADDRESS);
  console.log(nuusd_address);
  console.log(_fee);
  console.log("****************************");



  let printFee = 500;
  await moneyPrinter.setPrintAssetFeeBps(printFee);
  //
  let burnFee = 800;
  await moneyPrinter.setBurnAssetFeeBps(burnFee);




  // ***********************************  NUBTC & PRINTER ******************************
  const NuBTC = await ethers.getContractFactory('nuAsset');

  nuBTC = await upgrades.deployProxy(
    NuBTC,
    ["nuBTC","NBTC",defaultAdmin, minter, upgrader],
    {
      initializer: 'initialize',
      kind: 'uups'
    }
  );
  await nuBTC.waitForDeployment();
  nubtc_address = await nuBTC.getAddress();


  console.log(`nuBTC deployed to: ${nubtc_address}`);

  await nuAM.addNuAsset(nubtc_address,configArbi.PRICEFEEDBTCETH,86400);
  
  await nuBTC.connect(signer).grantRole(roleMinter, moneyPrinter_address);// owner is NuUSD deployer



 
  // let chainlinkInstanceBTC = await hre.ethers.getContractAt(artifacts.AggregatorV3, PRICEFEEDBTCETH);
  // let latestRoundDataBTC = await chainlinkInstanceBTC.latestRoundData();
  // let latestRoundPriceBTC = Number(latestRoundDataBTC.answer);
  // let decimalsBTC = Number(await chainlinkInstanceBTC.decimals());
  // let priceBTC = latestRoundPriceBTC / 10 ** decimalsBTC;
  // console.log(`Chainlink Price ETH/BTC: ${priceBTC}`);


  // // do it again
  // await time.increase(1800);
  // await poolContractNuma.increaseObservationCardinalityNext(cardinality);
  // await poolContract.increaseObservationCardinalityNext(cardinality);




  swapRouter = await hre.ethers.getContractAt(artifacts.SwapRouter.abi, "0xE592427A0AEce92De3Edee1F18E0157C05861564");

  return {
    signer, signer2, signer3,signer4, numaOwner, numa, NUMA_USDC_POOL_ADDRESS, nuUSD, NUUSD_ADDRESS: nuusd_address,NUBTC:nuBTC,NUBTC_ADDRESS: nubtc_address, moneyPrinter: moneyPrinter, MONEY_PRINTER_ADDRESS: moneyPrinter_address, nonfungiblePositionManager,
    wethContract, oracleAddress, numaAmount, cardinality, factory,swapRouter,VM,Vault1,snapshotGlobal,MINTER_ADDRESS,nuAM,USDCtoETHConverter_address
  };
}








module.exports.deployNumaNumaPoolnuAssetsPrinters = deployNumaNumaPoolnuAssetsPrinters;
module.exports.configArbi = configArbi;
