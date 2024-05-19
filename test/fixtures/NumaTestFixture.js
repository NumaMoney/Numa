const { getPoolData, initPoolETH, initPool, addLiquidity, weth9, artifacts, linkLibraries } = require("../../scripts/Utils.js");
const { time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const fs = require('fs');
const configRelativePathSepo = '../../configTestSepolia.json';
const configRelativePathArbi = '../../configTestArbitrum.json';
const configSepo = require(configRelativePathSepo);
const configArbi = require(configRelativePathArbi);

let LOG = true;

async function deployPrinterTestFixtureArbi() {

  let { DEPLOY_UNISWAP, WETH_ADDRESS, FACTORY_ADDRESS,
    POSITION_MANAGER_ADDRESS, PRICEFEEDETHUSD,PRICEFEEDBTCETH, INTERVAL_SHORT, INTERVAL_LONG, FEE } = configArbi;

  let signer, signer2;
  let numaOwner;
  let numa;
  // 
  let nuUSD;
  let nuusd_address;
  let nuusd_eth_pool_address;
  //
  let moneyprinterUSD;
  let moneyprinterUSD_address;

  //
  let nuBTC;
  let nubtc_address;
  let nubtc_eth_pool_address;
  //
  let moneyprinterbtc;
  let moneyprinterbtc_address;
  

  // uniswap
  let nonfungiblePositionManager;
  let wethContract;
  // oracle
  let oracleAddress;
  let factory;

  //
  [signer, signer2, signer3,signer4] = await ethers.getSigners();


  // Min and Max tick numbers, as a multiple of 60
  const tickMin = -887220;
  const tickMax = 887220;
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
  // create numa/eth univ3 pool
  await initPoolETH(WETH_ADDRESS, numa_address, _fee, EthPriceInNuma, nonfungiblePositionManager, WETH_ADDRESS);

  // 10 ethers
  let nbEthers = 10;
  let EthAmountNumaPool = ethers.parseEther(nbEthers.toString());
  let NumaAmountNumaPool = ethers.parseEther((nbEthers * EthPriceInNuma).toString());

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

  const poolContractNuma = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUMA_ETH_POOL_ADDRESS);
  const poolDataNuma = await getPoolData(poolContractNuma);


  // ***********************************  NUMA ORACLE ******************************
  const oracle = await ethers.deployContract("NumaOracle", [WETH_ADDRESS, INTERVAL_SHORT, INTERVAL_LONG, signer.getAddress()]);
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

 


  // Deploy printerUSD      
  moneyprinterUSD = await ethers.deployContract("NumaPrinter",
    [numa_address, nuusd_address, NUMA_ETH_POOL_ADDRESS, oracleAddress, PRICEFEEDETHUSD,86400]);
  await moneyprinterUSD.waitForDeployment();
  moneyprinterUSD_address = await moneyprinterUSD.getAddress();
  if (LOG)
    console.log(`nuUSD printer deployed to: ${moneyprinterUSD_address}`);


  // set printer as a NuUSD minter
  const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
  await nuUSD.connect(signer).grantRole(roleMinter, moneyprinterUSD_address);// owner is NuUSD deployer
  // set printer as a NUMA minter
  await numa.connect(numaOwner).grantRole(roleMinter, moneyprinterUSD_address);// signer is Numa deployer



  // Create nuUSD/ETH pool 
  await initPoolETH(WETH_ADDRESS, nuusd_address, _fee, price, nonfungiblePositionManager, WETH_ADDRESS);

  // 10 ethers
  let EthAmount = "10000000000000000000";

  // minting nuUSD
  let USDAmount = 10 * price;
  USDAmount = ethers.parseEther(USDAmount.toString());
  // get some nuUSD
  //await nuUSD.connect(signer).mint(signer.getAddress(),USDAmount);

  // IMPORTANT: for the uniswap V3 avg price calculations, we need this
  // or else it will revert

  // Get the pools to be as old as INTERVAL_LONG    
  await time.increase(1800);
  let cardinality = 10;
  await poolContractNuma.increaseObservationCardinalityNext(cardinality);



  return {
    signer, signer2, signer3,signer4, numaOwner, numa, NUMA_ETH_POOL_ADDRESS, nuUSD, NUUSD_ADDRESS: nuusd_address,  moneyPrinter: moneyprinterUSD, MONEY_PRINTER_ADDRESS: moneyprinterUSD_address, nonfungiblePositionManager,
    wethContract, oracleAddress, numaAmount, cardinality, factory
  };
}





async function deployPrinterTestFixtureSepo() {

  let { DEPLOY_UNISWAP, WETH_ADDRESS, FACTORY_ADDRESS,
    POSITION_MANAGER_ADDRESS, PRICEFEEDETHUSD,PRICEFEEDBTCETH, INTERVAL_SHORT, INTERVAL_LONG, FEE } = configSepo;

  let signer, signer2;
  let numaOwner;
  let numa;
  // 
  let nuUSD;
  let nuusd_address;
  let nuusd_eth_pool_address;
  //
  let moneyprinterUSD;
  let moneyprinterUSD_address;

  //
  let nuBTC;
  let nubtc_address;
  let nubtc_eth_pool_address;
  //
  let moneyprinterbtc;
  let moneyprinterbtc_address;
  

  // uniswap
  let nonfungiblePositionManager;
  let wethContract;
  // oracle
  let oracleAddress;
  let factory;

  //
  [signer, signer2, signer3,signer4] = await ethers.getSigners();


  // Min and Max tick numbers, as a multiple of 60
  const tickMin = -887220;
  const tickMax = 887220;
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

  // get pool price from chainlink USD/ETH PRICEFEEDETHUSD
  let chainlinkInstance = await hre.ethers.getContractAt(artifacts.AggregatorV3, PRICEFEEDETHUSD);
  let latestRoundData = await chainlinkInstance.latestRoundData();
  let latestRoundPrice = Number(latestRoundData.answer);
  let decimals = Number(await chainlinkInstance.decimals());
  let price = latestRoundPrice / 10 ** decimals;
  console.log(`Chainlink Price USD/ETH: ${price}`);

  // get some weth
  await wethContract.connect(signer).deposit({
    value: ethers.parseEther('100'),
  });


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
  console.log(`Numa deployed to: ${numa_address}`);
  // numa at 0.5 usd     
  let EthPriceInNuma = price * 2;
  // create numa/eth univ3 pool
  await initPoolETH(WETH_ADDRESS, numa_address, _fee, EthPriceInNuma, nonfungiblePositionManager, WETH_ADDRESS);

  // 10 ethers
  let nbEthers = 10;
  let EthAmountNumaPool = ethers.parseEther(nbEthers.toString());
  let NumaAmountNumaPool = ethers.parseEther((nbEthers * EthPriceInNuma).toString());

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
  console.log('numa eth pool: ', NUMA_ETH_POOL_ADDRESS);

  const poolContractNuma = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUMA_ETH_POOL_ADDRESS);
  const poolDataNuma = await getPoolData(poolContractNuma);
  // console.log(poolDataNuma);


  // ***********************************  NUMA ORACLE ******************************
  const oracle = await ethers.deployContract("NumaOracle", [WETH_ADDRESS, INTERVAL_SHORT, INTERVAL_LONG, signer.getAddress()]);
  await oracle.waitForDeployment();
  oracleAddress = await oracle.getAddress();
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


  console.log(`nuUSD deployed to: ${nuusd_address}`);

 


  // Deploy printerUSD      
  moneyprinterUSD = await ethers.deployContract("NumaPrinter",
    [numa_address, nuusd_address, NUMA_ETH_POOL_ADDRESS, oracleAddress, PRICEFEEDETHUSD,86400]);
  await moneyprinterUSD.waitForDeployment();
  moneyprinterUSD_address = await moneyprinterUSD.getAddress();
  console.log(`nuUSD printer deployed to: ${moneyprinterUSD_address}`);


  // set printer as a NuUSD minter
  const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
  await nuUSD.connect(signer).grantRole(roleMinter, moneyprinterUSD_address);// owner is NuUSD deployer
  // set printer as a NUMA minter
  await numa.connect(numaOwner).grantRole(roleMinter, moneyprinterUSD_address);// signer is Numa deployer



  // Create nuUSD/ETH pool 
  await initPoolETH(WETH_ADDRESS, nuusd_address, _fee, price, nonfungiblePositionManager, WETH_ADDRESS);

  // 10 ethers
  let EthAmount = "10000000000000000000";

  // minting nuUSD
  let USDAmount = 10 * price;
  USDAmount = ethers.parseEther(USDAmount.toString());
  // get some nuUSD
  //await nuUSD.connect(signer).mint(signer.getAddress(),USDAmount);

  // IMPORTANT: for the uniswap V3 avg price calculations, we need this
  // or else it will revert

  // Get the pools to be as old as INTERVAL_LONG    
  await time.increase(1800);
  let cardinality = 10;
  await poolContractNuma.increaseObservationCardinalityNext(cardinality);

  //

  // mint using printer
  // TODO: need more, why?
  //let numaAmountToApprove = 10*price*2;// numa is 50 cts in our tests
  let numaAmountToApprove = 10 * price * 2 + 10;// numa is 50 cts in our tests
  let approvalAmount = ethers.parseEther(numaAmountToApprove.toString());
  await numa.connect(signer).approve(moneyprinterUSD_address, approvalAmount);
  await moneyprinterUSD.mintAssetFromNuma(USDAmount, signer.getAddress());

  //let timestamp2 = Math.ceil(Date.now()/1000 + 300);
  // we have to increase deadline as we manually increased time
  let timestamp2 = Math.ceil(Date.now() / 1000 + 3000 + offset);
  await addLiquidity(
    WETH_ADDRESS,
    nuusd_address,
    wethContract,
    nuUSD,
    _fee,
    tickMin,
    tickMax,
    EthAmount,
    USDAmount,
    BigInt(0),
    BigInt(0),
    signer,
    timestamp2,
    nonfungiblePositionManager
  );


  nuusd_eth_pool_address = await factory.getPool(
    WETH_ADDRESS,
    nuusd_address,
    _fee,
  )
  console.log("****************************");
  console.log(nuusd_eth_pool_address);
  console.log(WETH_ADDRESS);
  console.log(nuusd_address);
  console.log(_fee);
  console.log("****************************");

  const poolContract = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, nuusd_eth_pool_address);
  const poolData = await getPoolData(poolContract);
  await poolContract.increaseObservationCardinalityNext(cardinality);




  //
  let printFee = 500;
  console.log("setting printer fee")
  await moneyprinterUSD.setPrintAssetFeeBps(printFee);
  //
  let burnFee = 800;
  await moneyprinterUSD.setBurnAssetFeeBps(burnFee);




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

 
  

  // Deploy printerBTC      
  moneyPrinterBTC = await ethers.deployContract("NumaPrinter",
    [numa_address, nubtc_address, NUMA_ETH_POOL_ADDRESS, oracleAddress, PRICEFEEDBTCETH,86400]);
  await moneyPrinterBTC.waitForDeployment();
  moneyprinterbtc_address = await moneyPrinterBTC.getAddress();
  console.log(`nuBTC printer deployed to: ${moneyprinterbtc_address}`);


  // set printer as a NuBTC minter
 
  await nuBTC.connect(signer).grantRole(roleMinter, moneyprinterbtc_address);// owner is NuUSD deployer
  // set printer as a NUMA minter
  await numa.connect(numaOwner).grantRole(roleMinter, moneyprinterbtc_address);// signer is Numa deployer



  // Create nuUSD/ETH pool 
  let chainlinkInstanceBTC = await hre.ethers.getContractAt(artifacts.AggregatorV3, PRICEFEEDBTCETH);
  let latestRoundDataBTC = await chainlinkInstanceBTC.latestRoundData();
  let latestRoundPriceBTC = Number(latestRoundDataBTC.answer);
  let decimalsBTC = Number(await chainlinkInstanceBTC.decimals());
  let priceBTC = latestRoundPriceBTC / 10 ** decimalsBTC;
  console.log(`Chainlink Price ETH/BTC: ${priceBTC}`);
  await initPoolETH(nubtc_address,WETH_ADDRESS, _fee, priceBTC, nonfungiblePositionManager, WETH_ADDRESS);


  // do it again
  await time.increase(1800);
  await poolContractNuma.increaseObservationCardinalityNext(cardinality);
  await poolContract.increaseObservationCardinalityNext(cardinality);

  // deploying our own SwapRouter as I can't find address on sepolia

  let SwapRouter = new ethers.ContractFactory(artifacts.SwapRouter.abi, artifacts.SwapRouter.bytecode, signer);
  // DBGREFACTO
  swapRouter = await SwapRouter.deploy(await factory.getAddress(), configSepo.WETH_ADDRESS);

  console.log(`swap router: ${swapRouter}`);

  return {
    signer, signer2, signer3,signer4, numaOwner, numa, NUMA_ETH_POOL_ADDRESS, nuUSD, NUUSD_ADDRESS: nuusd_address, NUUSD_ETH_POOL_ADDRESS: nuusd_eth_pool_address, moneyPrinter: moneyprinterUSD, MONEY_PRINTER_ADDRESS: moneyprinterUSD_address, nonfungiblePositionManager,
    wethContract, oracleAddress, numaAmount, cardinality, factory, swapRouter
  };
}



module.exports.deployPrinterTestFixtureSepo = deployPrinterTestFixtureSepo;
module.exports.deployPrinterTestFixtureArbi = deployPrinterTestFixtureArbi;

module.exports.configArbi = configArbi;
module.exports.configSepo = configSepo;