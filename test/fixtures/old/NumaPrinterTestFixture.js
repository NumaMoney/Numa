const { getPoolData,initPoolETH,addLiquidity,weth9,artifacts } = require("../../../scripts/Utils.js");
const fs = require('fs');
//const configRelativePath = fs.existsSync('./configTestSepolia.json') ? './configTestSepolia.json' : '../configTestSepolia.json';
const configRelativePath = '../../configTestSepolia.json';
const config = require(configRelativePath);



let {NUMA_ADDRESS,UNIV3_NUMAETH_ADDRESS,WETH_ADDRESS,FACTORY_ADDRESS,
  POSITION_MANAGER_ADDRESS,PRICEFEEDETHUSD,INTERVAL_SHORT,INTERVAL_LONG,FLEXFEETHRESHOLD} = config;

async function deployPrinterTestFixture() {
    let signer,signer2;
    let numaOwner;
    let numa;
    let nuUSD;
    let NUUSD_ADDRESS;
    let NUUSD_ETH_POOL_ADDRESS;


    let moneyPrinter;
    let MONEY_PRINTER_ADDRESS;

    // uniswap
    let nonfungiblePositionManager;
    let wethContract;
    // oracle
    let oracleAddress;

     // amount to be transfered to signer
     let numaAmount = ethers.parseEther('100000');




     [signer,signer2] = await ethers.getSigners();

     //  impersonating NUMA deployer's account on Sepolia
     let deployerAddress = "0x6aeC8F3EeA17D903CCEcbC4FA9aAB67Fa1F0D264";
     await network.provider.request({
       method: "hardhat_impersonateAccount",
       params: [deployerAddress],
     });
     // get associated signer
     numaOwner = await ethers.getSigner(deployerAddress);



     // TODO: move parameters in fixture/config
     // Min and Max tick numbers, as a multiple of 60
     const tickMin = -887220;
     const tickMax = 887220;
     const defaultTimestamp = Math.ceil(Date.now()/1000 + 300);
     // uniswap v3 pool fee
     let _fee = 500;


 

     // *** Uniswap from fork
     nonfungiblePositionManager = await hre.ethers.getContractAt(artifacts.NonfungiblePositionManager.abi, POSITION_MANAGER_ADDRESS);
     wethContract = await hre.ethers.getContractAt(weth9.WETH9.abi, WETH_ADDRESS);

     
     // *** Numa get from fork
     const Numa = await ethers.getContractFactory('NUMA');
     numa =  await Numa.attach(NUMA_ADDRESS);

     // *** nuUSD deploy
     const NuUSD = await ethers.getContractFactory('nuUSD');
     let defaultAdmin = await signer.getAddress();
     let minter = await signer.getAddress();
     let upgrader = await signer.getAddress();
     nuUSD = await upgrades.deployProxy(
       NuUSD,
       [defaultAdmin,minter,upgrader],
       {
         initializer: 'initialize',
         kind:'uups'
       }
     );
     await nuUSD.waitForDeployment();
     NUUSD_ADDRESS = await nuUSD.getAddress();

   

     // get pool price from chainlink USD/ETH PRICEFEEDETHUSD
     let chainlinkInstance = await hre.ethers.getContractAt(artifacts.AggregatorV3, PRICEFEEDETHUSD);
     let latestRoundData = await chainlinkInstance.latestRoundData();
     let latestRoundPrice = Number(latestRoundData.answer);
     let decimals = Number(await chainlinkInstance.decimals());
     let price = latestRoundPrice / 10**decimals;
     console.log(`Chainlink Price USD/ETH: ${price}`)



     // Create nuUSD/ETH pool 
     await initPoolETH(WETH_ADDRESS,NUUSD_ADDRESS,_fee,price,nonfungiblePositionManager);

     // 10 ethers
     let EthAmount = "10000000000000000000";

     let USDAmount = 10*price;
     USDAmount = ethers.parseEther(USDAmount.toString());

     // get some weth
     await wethContract.connect(signer).deposit({
         value: ethers.parseEther('100'),
       });

     // TODO: get nuUSD from printer before setting pool 
     // ... or not, here we only want to test printer
     // the other script would test that initial minting works and that we can create pool from it

     // get some nuUSD
     await nuUSD.connect(signer).mint(signer.getAddress(),USDAmount);
       
     
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
         defaultTimestamp,
         nonfungiblePositionManager
       );

       //const factory = await hre.ethers.getContractAt(artifacts.UniswapV3Factory.abi, FACTORY_ADDRESS);

       const Factory = new ContractFactory(artifacts.UniswapV3Factory.abi, artifacts.UniswapV3Factory.bytecode, await signer.getAddress());
       const factory = await Factory.deploy();

       NUUSD_ETH_POOL_ADDRESS = await factory.getPool(
         WETH_ADDRESS,
         NUUSD_ADDRESS,
         _fee,
       )
      
       const poolContract = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, NUUSD_ETH_POOL_ADDRESS);
       const poolData = await getPoolData(poolContract);
      
       
       // Deploy numa oracle
       const oracle = await ethers.deployContract("NumaOracle", [WETH_ADDRESS,INTERVAL_SHORT,INTERVAL_LONG,FLEXFEETHRESHOLD,signer.getAddress()]);
       await oracle.waitForDeployment();
       oracleAddress = await oracle.getAddress();

       // Deploy printerUSD
       moneyPrinter = await ethers.deployContract("NumaPrinter",
       [NUMA_ADDRESS,NUUSD_ADDRESS,UNIV3_NUMAETH_ADDRESS,oracleAddress,PRICEFEEDETHUSD]);
       await moneyPrinter.waitForDeployment();
       MONEY_PRINTER_ADDRESS = await moneyPrinter.getAddress();

       await moneyPrinter.setTokenPool(NUUSD_ETH_POOL_ADDRESS);

       //
       let printFee = 500;
       await moneyPrinter.setPrintAssetFeeBps(printFee);
       //
       let burnFee = 800;
       await moneyPrinter.setBurnAssetFeeBps(burnFee);
        // set printer as a NuUSD minter
        const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
        await nuUSD.connect(signer).grantRole(roleMinter, MONEY_PRINTER_ADDRESS);// owner is NuUSD deployer
        // set printer as a NUMA minter
        await numa.connect(numaOwner).grantRole(roleMinter, MONEY_PRINTER_ADDRESS);// signer is Numa deployer
        return { signer,signer2, numaOwner, numa, nuUSD,NUUSD_ADDRESS,NUUSD_ETH_POOL_ADDRESS,moneyPrinter,MONEY_PRINTER_ADDRESS,nonfungiblePositionManager,
            wethContract,oracleAddress,numaAmount,factory };
}


module.exports.deployPrinterTestFixture = deployPrinterTestFixture;
module.exports.config = config;