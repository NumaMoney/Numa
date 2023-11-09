const { ethers, upgrades,network } = require("hardhat");

// Sepolia test
WETH_ADDRESS= '0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9'
priceFeedETHUSD_sepo = "0x694AA1769357215DE4FAC081bf1f309aDC325306";
priceFeedBTCUSD_sepo = "0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43";
ORACLE_ADDRESS =  "0x88dcdFD83E5c5A773E0396EBC2DB37850B1E7486";
NUMA_ADDRESS = "0x7243B72b1BC036fc72A94e7F2D8266D3274dBD2e";// not upgraded
UNIV3POOL_ADDRESS = "0x67387E84B945825CdC3615D5E653BdDAE814a653"

// ************* Dev resources ************************
// https://blog.chain.link/how-to-use-chainlink-price-feeds-on-arbitrum/
// https://www.youtube.com/watch?v=SeiaiiviEhM&ab_channel=BlockmanCodes
// uniswap v3 examples
// https://docs.uniswap.org/sdk/v3/guides/liquidity/minting
// https://docs.uniswap.org/contracts/v3/guides/providing-liquidity/setting-up
// https://solidity-by-example.org/defi/uniswap-v3-liquidity/
// https://blog.chain.link/testing-chainlink-smart-contracts/ --> faudra mocker sur local fork ou utiliser sepolia



// run node
// npx hardhat node (sepolia fork in hardhat config)

// run script
// npx hardhat run .\scripts\testMintBurnNumaTonuUSD_Sepolia.js --network localhost
async function main () {
    const [owner,signer2] = await ethers.getSigners();

    //  impersonating NUMA deployer's account on Sepolia
    let deployerAddress = "0x6aeC8F3EeA17D903CCEcbC4FA9aAB67Fa1F0D264";
    await network.provider.request({
      method: "hardhat_impersonateAccount",
      params: [deployerAddress],
    });
    
    // get associated signer
    const signer = await ethers.getSigner(deployerAddress);


    // ****************** CHAINLINK *********************************
    // Use sepolia fork chainlink pricefeeds
    
    // Deploy Oracle

    // TODO: check these values coming from Offshift
    let INTERVAL_SHORT = 180;
    let INTERVAL_LONG = 1800;
    let flexFeeThreshold = 0;// TODO
    const oracle = await ethers.deployContract("NumaOracle", [WETH_ADDRESS,INTERVAL_SHORT,INTERVAL_LONG,flexFeeThreshold,owner], {
      value: 0,
    });
    
    await oracle.waitForDeployment();
    let oracleAddress = await oracle.getAddress();
    console.log('Oracle deployed to:', oracleAddress);
    
    ORACLE_ADDRESS = oracleAddress;
    // const Oracle = await ethers.getContractFactory('Oracle')
    // const oracle =  await Oracle.attach(ORACLE_ADDRESS);

    // call chainlinkPrice to check values from arbitrum fork
    let priceETH = await oracle.chainlinkPrice(priceFeedETHUSD_sepo);
    console.log('Chainlink price of ETH in USD: ', priceETH);
    let priceBTC = await oracle.chainlinkPrice(priceFeedBTCUSD_sepo);
    console.log('Chainlink price of BTC in USD: ', priceBTC);

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

    // attach Numa, already deployed on sepolia
    const Numa = await ethers.getContractFactory('NUMA')
    const numa =  await Numa.attach(NUMA_ADDRESS);
    
    // Deploy MoneyPrinter
    const moneyPrinter = await ethers.deployContract("NumaPrinter",
     [NUMA_ADDRESS,NUUSD_ADDRESS,UNIV3POOL_ADDRESS,ORACLE_ADDRESS,priceFeedETHUSD_sepo], 
     {
      value: 0,
    });
    await moneyPrinter.waitForDeployment();
    let MONEY_PRINTER_ADDRESS = await moneyPrinter.getAddress();
    console.log('moneyPrinter address: ', MONEY_PRINTER_ADDRESS);

    
    // give ownership of nuUSD so that we can mint
    //await nuUSD.transferOwnership(MONEY_PRINTER_ADDRESS);
    
    // set printer as a NuUSD minter
    const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
    await nuUSD.connect(owner).grantRole(roleMinter, MONEY_PRINTER_ADDRESS);// owner is NuUSD deployer
    // set printer as a NUMA minter
    await numa.connect(signer).grantRole(roleMinter, MONEY_PRINTER_ADDRESS);// signer is Numa deployer

    // ** mint nuUSD, check amounts
    let balanceNuma = await numa.balanceOf(signer2.getAddress());
    let balanceNuUSD = await nuUSD.balanceOf(signer2.getAddress())
    console.log('Numa balance ',balanceNuma);
    console.log('NuUSD balance ',balanceNuUSD);

    // send some Numa to signer2
    let balanceNumaDeployer = await numa.balanceOf(deployerAddress);
    //console.log('Numa balance ',balanceNumaDeployer);


    // transfer numa to signer2
    let numaAmount = ethers.parseEther('100000');
    await numa.connect(signer).transfer(signer2.getAddress(),numaAmount);

    balanceNuma = await numa.balanceOf(signer2.getAddress());
    console.log('Numa balance after transfer',balanceNuma);



    let amountToMintUSD = 100;

    // 1 numa = 0.016 dollars
    let amountToMintNuma = amountToMintUSD/0.016;
    amountToMintNuma = Math.ceil(amountToMintNuma);
    let approvalAmount = ethers.parseEther(amountToMintNuma.toString());// 100 dollars
    let amountToMint = ethers.parseEther(amountToMintUSD.toString());// 100 dollars

    await numa.connect(signer2).approve(MONEY_PRINTER_ADDRESS,approvalAmount);
    await moneyPrinter.connect(signer2).mintAssetFromNuma(amountToMint,signer2.getAddress());

    balanceNuma = await numa.balanceOf(signer2.getAddress());
    balanceNuUSD = await nuUSD.balanceOf(signer2.getAddress())
    console.log('Numa balance after minting USD',balanceNuma);
    console.log('NuUSD balance after minting USD',balanceNuUSD);

    // ** burn nuUSD, check amounts
    // burn all nuUSD
    let amountToBurn = amountToMint;
    await nuUSD.connect(signer2).approve(MONEY_PRINTER_ADDRESS,amountToBurn);
    await moneyPrinter.connect(signer2).burnAssetToNuma(amountToBurn,signer2.getAddress());

    balanceNuma = await numa.balanceOf(signer2.getAddress());
    balanceNuUSD = await nuUSD.balanceOf(signer2.getAddress())
    console.log('Numa balance after burning USD',balanceNuma);
    console.log('NuUSD balance after burning USD',balanceNuUSD);

    


    

}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });


    


