// ************* vault v2 deployment from scratch ************************



const fs = require("fs");
const { ethers, upgrades } = require("hardhat");
const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");

const configRelativePathSepo = './configSepolia.json';
const configSepo = require(configRelativePathSepo);


async function verify() {
    let { uptime_feed, numa_address, lstAddress,
        debt, rwdFromDebt,feeReceiver, rwdReceiver, vaultV1_address, vaultManagerV1_address } = configSepo;

    // verify all
    let vo_address = "";
    let nuam_address = "";
    let numa_minter_address = "";
    let vaultmanager_address = "";
    let vault_address = "";


    if (fs.existsSync("outputSepolia.json")) {
        const data = JSON.parse(fs.readFileSync("outputSepolia.json"));
        console.log("reading:", data);
        vo_address = data.oracle;
        nuam_address =  data.assetManager;
        numa_minter_address =  data.minter;
        vaultmanager_address =  data.vaultManager;
        vault_address =  data.vault;

    } else {
        console.log("No contract data.");
    }


    // KO Compiled contract deployment bytecode does NOT match the transaction deployment bytecode.
    // await hre.run("verify:verify", {
    //     address: nuam_address,
    //     contract: "contracts/nuAssets/nuAssetManager.sol:nuAssetManager",
    //     constructorArguments: [uptime_feed],
    // });

    await hre.run("verify:verify", {
        address: numa_minter_address,
        contract: "contracts/NumaProtocol/NumaMinter.sol:NumaMinter",
        constructorArguments: [],
    });

    // KO Compiled contract deployment bytecode does NOT match the transaction deployment bytecode.
    // await hre.run("verify:verify", {
    //     address: vaultmanager_address,
    //     contract: "contracts/NumaProtocol/VaultManager.sol:VaultManager",
    //     constructorArguments: [numa_address, nuam_address],
    // });

    await hre.run("verify:verify", {
        address: vault_address,
        contract: "contracts/NumaProtocol/NumaVault.sol:NumaVault",
        constructorArguments: [numa_address, lstAddress, "1000000000000000000", vo_address, numa_minter_address, 0, 0],
    });

}








verify()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })
   


