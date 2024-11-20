// ************* vault v2 deployment from scratch ************************




const fs = require("fs");

const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
const configRelativePathSepo = './configSepolia.json';
const configSepo = require(configRelativePathSepo);
const ERC20abi = [
    "function balanceOf(address owner) view returns (uint256)",
    "function decimals() view returns (uint8)",
    "function symbol() view returns (string)",
    "function transfer(address to, uint amount) returns (bool)",
    "function approve(address spender, uint amount)",
    "event Transfer(address indexed from, address indexed to, uint amount)"
  ];
  

  


// deployment parameters
// npx hardhat run .\scripts\deploy\deployVaultV2.js --network sepolia
let { uptime_feed, numa_address, lstAddress,
    debt, rwdFromDebt,feeReceiver, rwdReceiver, vaultV1_address, vaultManagerV1_address } = configSepo;


// TODO: compare price before/After
async function migrateVaultV1 () 
{

    // first deploy new vault
    let vo_address = "";
    let nuam_address = "";
    let numa_minter_address = "";
    let vaultmanager_address = "";
    let vault_address = "";


    if (fs.existsSync("outputFork.json")) {
        const data = JSON.parse(fs.readFileSync("outputFork.json"));
        console.log("reading:", data);
        vo_address = data.oracle;
        nuam_address =  data.assetManager;
        numa_minter_address =  data.minter;
        vaultmanager_address =  data.vaultManager;
        vault_address =  data.vault;

    } else {
        console.log("No contract data.");
    }



    let vaultOld = await hre.ethers.getContractAt("NumaVaultOldSepoliaVer", vaultV1_address); 
    let vmOld = await vaultOld.vaultManager();
  
    // set buy/sell fees to match old price
    let oldsellfee = await vaultOld.SELL_FEE();
    let newsellfee = await vaultOld.BUY_FEE();
    console.log(`old sell fee:`,oldsellfee);
    console.log(`old buy fee:`,newsellfee);


    let numaNominalPrice = await vmOld.numaToToken(
        ethers.parseEther("1"),
        ethers.parseEther("1"),
        ethers.parseEther("1"),
    );
    console.log('numaNominalPrice', numaNominalPrice);
    numaBuyPrice = (numaNominalPrice * 1000) / await vaultOld.buy_fee();
    console.log('numaBuyPrice', numaBuyPrice);
    numaSellPrice = (numaNominalPrice * await vaultOld.sell_fee()) / 1000;
    console.log('numaSellPrice', numaSellPrice);
    rEthRefPrice = await vaultOld.last_lsttokenvalueWei();
    console.log('rEthRefPrice', rEthRefPrice);


    let vaultManager = await hre.ethers.getContractAt("VaultManager", vaultmanager_address);
    let vault = await hre.ethers.getContractAt("NumaVault", vault_address);


    // let tx = await vaultManager.setSellFee(((await vaultOld.sell_fee()) * ethers.parseEther("1")) / 1000);
    // tx = await vaultManager.setBuyFee(((await vaultOld.buy_fee()) * ethers.parseEther("1")) / 1000);
    // let receipt = await tx.wait(1);
    // 
    // first we need to match numa supply
    let numaSupplyOld = await vmOld.getNumaSupply();
    console.log(`old vault manager numa supply:`,numaSupplyOld);
     

     // todo display old price
     let numaSupplyNew = await vaultManager.getNumaSupply();
     console.log(`old vault manager numa supply:`,numaSupplyNew);

    //  uint diff = numaSupplyNew -
    //      numaSupplyOld -
    //      vaultManagerOld.constantRemovedSupply();
    //  // 29/10 diff in supply: 500 000 constant + 600 000 currently decaying
    //  // will put the decay half in LP, half in other --> 300 000
    //  // keep same period
    //  uint newPeriod = vaultManagerOld.decayPeriod() -
    //      (block.timestamp - vaultManagerOld.startTime());

    //  vaultManager.setDecayValues(
    //      diff / 2,
    //      newPeriod,
    //      diff / 2,
    //      newPeriod,
    //      vaultManagerOld.constantRemovedSupply() // same constant
    //  );
    //  vaultManager.startDecay();

     // check price is the same (if not send the lst back to V1 vault)

     // unpause
     //vault.unpause();

}




migrateVaultV1()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })



