const { getPoolData, initPoolETH, initPool, addLiquidity, weth9, artifacts, linkLibraries } = require("../../scripts/Utils.js");
const { time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const fs = require('fs');
//const configRelativePath = fs.existsSync('./configTestSepolia.json') ? './configTestSepolia.json' : '../configTestSepolia.json';
const configRelativePath = '../../configTestSepolia.json';
const config = require(configRelativePath);



let { DEPLOY_UNISWAP,WETH_ADDRESS, FACTORY_ADDRESS,
  POSITION_MANAGER_ADDRESS, PRICEFEEDETHUSD, INTERVAL_SHORT, INTERVAL_LONG, FLEXFEETHRESHOLD,FEE } = config;

async function deployPrinterTestFixture() {
  let signer, signer2;
  let numaOwner;
  let numa;
  let nuUSD;
  let NUUSD_ADDRESS;
  let NUUSD_ETH_POOL_ADDRESS;


  let moneyPrinter;
  let MONEY_PRINTER_ADDRESS;

  // uniswap
  let nonfungiblePositionManager;
  let factory;
  let wethContract;
  // oracle
  let oracleAddress;

  // amount to be transfered to signer
  let numaAmount = ethers.parseEther('100000');

  [signer, signer2, signer3] = await ethers.getSigners();


  // TODO: move parameters in fixture/config
  // Min and Max tick numbers, as a multiple of 60
  const tickMin = -887220;
  const tickMax = 887220;

  // uniswap v3 pool fee
  let _fee = Number(FEE);




  // *** Uniswap ******************************
  if (DEPLOY_UNISWAP === "TRUE")
  {
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
  else
  {
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
  await initPool(WETH_ADDRESS, numa_address, _fee, EthPriceInNuma, nonfungiblePositionManager, WETH_ADDRESS);

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

  // *** nuUSD deploy
  const NuUSD = await ethers.getContractFactory('nuUSD');
  let defaultAdmin = await signer.getAddress();
  let minter = await signer.getAddress();
  let upgrader = await signer.getAddress();
  nuUSD = await upgrades.deployProxy(
    NuUSD,
    [defaultAdmin, minter, upgrader],
    {
      initializer: 'initialize',
      kind: 'uups'
    }
  );
  await nuUSD.waitForDeployment();
  NUUSD_ADDRESS = await nuUSD.getAddress();
  // temp fix for issues when swapping
  while (NUUSD_ADDRESS < WETH_ADDRESS) {
    nuUSD = await upgrades.deployProxy(
      NuUSD,
      [defaultAdmin, minter, upgrader],
      {
        initializer: 'initialize',
        kind: 'uups'
      }
    );
    await nuUSD.waitForDeployment();
    NUUSD_ADDRESS = await nuUSD.getAddress();
    console.log(`TOBEFIXED nuUSD deployed to: ${NUUSD_ADDRESS}`);
  }

  console.log(`nuUSD deployed to: ${NUUSD_ADDRESS}`);

  //  // Create nuUSD/ETH pool 
  //  await initPoolETH(WETH_ADDRESS,NUUSD_ADDRESS,_fee,price,nonfungiblePositionManager);

  //  // 10 ethers
  //  let EthAmount = "10000000000000000000";

  //  let USDAmount = 10*price;
  //  USDAmount = ethers.parseEther(USDAmount.toString());


  //  // TODO: get nuUSD from printer before setting pool 
  //  // ... or not, here we only want to test printer
  //  // the other script would test that initial minting works and that we can create pool from it

  //  // get some nuUSD
  //  await nuUSD.connect(signer).mint(signer.getAddress(),USDAmount);


  //  await addLiquidity(
  //      WETH_ADDRESS,
  //      NUUSD_ADDRESS,
  //      wethContract,
  //      nuUSD,
  //      _fee,
  //      tickMin,
  //      tickMax,
  //      EthAmount,
  //      USDAmount,
  //      BigInt(0),
  //      BigInt(0),
  //      signer,
  //      defaultTimestamp,
  //      nonfungiblePositionManager
  //    );


  //    NUUSD_ETH_POOL_ADDRESS = await factory.getPool(
  //      WETH_ADDRESS,
  //      NUUSD_ADDRESS,
  //      _fee,
  //    )

  //    const poolContract = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUUSD_ETH_POOL_ADDRESS);
  //    const poolData = await getPoolData(poolContract);


  // Deploy numa oracle
  const oracle = await ethers.deployContract("NumaOracle", [WETH_ADDRESS, INTERVAL_SHORT, INTERVAL_LONG, FLEXFEETHRESHOLD, signer.getAddress()]);
  await oracle.waitForDeployment();
  oracleAddress = await oracle.getAddress();

  // Deploy printerUSD      
  moneyPrinter = await ethers.deployContract("NumaPrinter",
    [numa_address, NUUSD_ADDRESS, NUMA_ETH_POOL_ADDRESS, oracleAddress, PRICEFEEDETHUSD]);
  await moneyPrinter.waitForDeployment();
  MONEY_PRINTER_ADDRESS = await moneyPrinter.getAddress();

  // set printer as a NuUSD minter
  const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
  await nuUSD.connect(signer).grantRole(roleMinter, MONEY_PRINTER_ADDRESS);// owner is NuUSD deployer
  // set printer as a NUMA minter
  await numa.connect(numaOwner).grantRole(roleMinter, MONEY_PRINTER_ADDRESS);// signer is Numa deployer



  // Create nuUSD/ETH pool 
  await initPoolETH(WETH_ADDRESS, NUUSD_ADDRESS, _fee, price, nonfungiblePositionManager, WETH_ADDRESS);

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
  await numa.connect(signer).approve(MONEY_PRINTER_ADDRESS, approvalAmount);
  await moneyPrinter.mintAssetFromNuma(USDAmount, signer.getAddress());

  //let timestamp2 = Math.ceil(Date.now()/1000 + 300);
  // we have to increase deadline as we manually increased time
  let timestamp2 = Math.ceil(Date.now() / 1000 + 3000 + offset);
  await addLiquidity(
    WETH_ADDRESS,
    NUUSD_ADDRESS,
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


  NUUSD_ETH_POOL_ADDRESS = await factory.getPool(
    WETH_ADDRESS,
    NUUSD_ADDRESS,
    _fee,
  )
  console.log("****************************");
  console.log(NUUSD_ETH_POOL_ADDRESS);
  console.log(WETH_ADDRESS);
  console.log(NUUSD_ADDRESS);
  console.log(_fee);
  console.log("****************************");

  const poolContract = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUUSD_ETH_POOL_ADDRESS);
  const poolData = await getPoolData(poolContract);
  await poolContract.increaseObservationCardinalityNext(cardinality);




  await moneyPrinter.setTokenPool(NUUSD_ETH_POOL_ADDRESS);

  //
  let printFee = 500;
  await moneyPrinter.setPrintAssetFeeBps(printFee);
  //
  let burnFee = 800;
  await moneyPrinter.setBurnAssetFeeBps(burnFee);


  // do it again
  await time.increase(1800);
  await poolContractNuma.increaseObservationCardinalityNext(cardinality);
  await poolContract.increaseObservationCardinalityNext(cardinality);

  // deploying our own SwapRouter as I can't find address on sepolia

  let SwapRouter = new ethers.ContractFactory(artifacts.SwapRouter.abi, artifacts.SwapRouter.bytecode, signer);
  swapRouter = await SwapRouter.deploy(await factory.getAddress(), config.WETH_ADDRESS);


  return {
    signer, signer2, signer3, numaOwner, numa, NUMA_ETH_POOL_ADDRESS, nuUSD, NUUSD_ADDRESS, NUUSD_ETH_POOL_ADDRESS, moneyPrinter, MONEY_PRINTER_ADDRESS, nonfungiblePositionManager,
    wethContract, oracleAddress, numaAmount, cardinality, factory, swapRouter
  };
}


module.exports.deployPrinterTestFixture = deployPrinterTestFixture;
module.exports.config = config;