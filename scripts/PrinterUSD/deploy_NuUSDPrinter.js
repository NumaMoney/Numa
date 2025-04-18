// 1. Oracle
// 2. nuAsset
// 3. Printer
// 4. Mint nuUSD
// 5. Setup univ3 pool
// 6. Set pool to Printer

// addresses on arbitrum
let numaAddress = "0x7FB7EDe54259Cb3D4E1EaF230C7e2b1FfC951E9A";
let WETH_ADDRESS = "";
let INTERVAL_SHORT = ;
let INTERVAL_LONG = ;
let PRICEFEEDETHUSD = ;
let NUMA_ETH_POOL_ADDRESS = ;

// TODO: 
// - need admin rôle on NUMA token so give printer numa minter rôle
// - need NUMA/ETH uniswap V3 pool
// - if we want to mint nuUSD and to enable nuUSD burning:
//      - need some NUMA to be burnt for nuUSD on this account
//      - need to create nuUSD/ETH uniswap V3 pool
//      - need to set the pool to printer

const { ethers, upgrades } = require("hardhat");

// npx hardhat run --network kovan scripts/deploy_erc20.js
async function main () {
    const [signer] = await ethers.getSigners();

    // Deploy numa oracle
    const oracle = await ethers.deployContract("NumaOracle", [WETH_ADDRESS,INTERVAL_SHORT,INTERVAL_LONG,signer.getAddress()]);
    await oracle.waitForDeployment();
    let oracleAddress = await oracle.getAddress();
    console.log('Oracle deployed to:', oracleAddress);


    // Deploy nuUSD
    const NuUSD = await ethers.getContractFactory('nuUSD');
    let defaultAdmin = await owner.getAddress();
    let minter = await owner.getAddress();
    let upgrader = await owner.getAddress();
    const nuUSD = await upgrades.deployProxy(
      NuUSD,
      [defaultAdmin,minter,upgrader],
      {
        initializer: 'initialize',
        kind:'uups'
      }
    );
    await nuUSD.waitForDeployment();
    let NUUSD_ADDRESS = await nuUSD.getAddress();
    console.log('nuUSD address: ', NUUSD_ADDRESS);

    // Deploy printerUSD      
    moneyPrinter = await ethers.deployContract("NumaPrinter",
    [numaAddress,NUUSD_ADDRESS,NUMA_ETH_POOL_ADDRESS,oracleAddress,PRICEFEEDETHUSD]);
    await moneyPrinter.waitForDeployment();
    let MONEY_PRINTER_ADDRESS = await moneyPrinter.getAddress();

    // set printer as a NuUSD minter
    const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
    await nuUSD.grantRole(roleMinter, MONEY_PRINTER_ADDRESS);// owner is NuUSD deployer
    // set printer as a NUMA minter
    await numa.connect(numaOwner).grantRole(roleMinter, MONEY_PRINTER_ADDRESS);// signer is Numa deployer



}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })