// ************* vault v2 deployment from scratch ************************




const fs = require("fs");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");

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





async function test() {

    let { uptime_feed, numa_address, lstAddress,
        debt, rwdFromDebt, feeReceiver, rwdReceiver, vaultV1_address, vaultManagerV1_address } = configSepo;

    let vo_address = "";
    let nuam_address = "";
    let numa_minter_address = "";
    let vaultmanager_address = "";
    let vault_address = "";


    if (fs.existsSync("outputFork.json")) {
        const data = JSON.parse(fs.readFileSync("outputFork.json"));
        console.log("reading:", data);
        vo_address = data.oracle;
        nuam_address = data.assetManager;
        numa_minter_address = data.minter;
        vaultmanager_address = data.vaultManager;
        vault_address = data.vault;

    } else {
        console.log("No contract data.");
    }

    let vaultAddress = vault_address;


    const address = "0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69";
    let rEth_contract = await hre.ethers.getContractAt(ERC20abi, lstAddress);


    await helpers.impersonateAccount(address);
    const impersonatedSigner = await ethers.getSigner(address);


    let vaultBalance = await rEth_contract.balanceOf(vaultAddress);
    console.log('vault balance before: ', vaultBalance);
    if (vaultBalance === 0n)
    {
        console.log('sending reth');
        await rEth_contract.connect(impersonatedSigner).transfer(vaultAddress, ethers.parseEther("100"));
    }
    vaultBalance = await rEth_contract.balanceOf(vaultAddress);
    console.log('vault balance after: ', vaultBalance);



    // //let vault = await hre.ethers.getContractAt("NumaVault", "0xD51d83E3458dB51Bc41991193DAAD309a749a167"); 
    // // let buy_amount = await vault.buy(ethers.parseEther("0.01"),0,"0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69");

    // // fork mode
    let vault = await hre.ethers.getContractAt("NumaVault", vaultAddress);
    await vault.unpause();
    await rEth_contract.approve(vaultAddress, ethers.parseEther("100000"));
    let buy_amount = await vault.connect(impersonatedSigner).buy(ethers.parseEther("1"), 0, "0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69");

}



test()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })



