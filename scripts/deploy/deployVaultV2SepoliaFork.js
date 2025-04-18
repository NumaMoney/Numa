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

// SEPOLIA
// deploy
let vaultOracle;
let vault;
let vaultManager;
let nuAssetManager;
let numaMinter;

// npx hardhat node
// npx hardhat run .\scripts\deploy\deployVaultV2.js --network localhost


async function deployVaultV2 () {
    
    console.log('deployment vault v2 sepolia...');

    let { uptime_feed, numa_address, lstAddress,
        debt, rwdFromDebt,feeReceiver, rwdReceiver, vaultV1_address, vaultManagerV1_address } = configSepo;
    const [signer] = await ethers.getSigners();
 
    let numa = await hre.ethers.getContractAt("NUMA", numa_address);

    // *********************** vault oracle **********************************
    vaultOracle = await hre.ethers.deployContract("VaultMockOracle",
    [lstAddress]
    );
    let deploymentReceipt = await vaultOracle.deploymentTransaction().wait(1);


    //await vaultOracle.waitForDeployment();
    
    let VAULT_ORACLE_ADDRESS = await vaultOracle.getAddress();    
    console.log('vaultOracle address: ', VAULT_ORACLE_ADDRESS);

    // *********************** nuasset manager oracle **********************************
    nuAssetManager = await ethers.deployContract("nuAssetManager",
        [uptime_feed]
        );
    //await nuAssetManager.waitForDeployment();
    deploymentReceipt = await nuAssetManager.deploymentTransaction().wait(1);
    let NUAM_ADDRESS = await nuAssetManager.getAddress();
    console.log('nuAssetManager address: ', NUAM_ADDRESS);

    // *********************** numa minter **********************************
    numaMinter = await ethers.deployContract("NumaMinter",
            []
            );
    deploymentReceipt = await numaMinter.deploymentTransaction().wait(1);
   // await numaMinter.waitForDeployment();
    let NUMAMINTER_ADDRESS = await numaMinter.getAddress();
    
    console.log('numaMinter address: ', NUMAMINTER_ADDRESS);

    console.log('numaMinter setTokenAddress');
    let tx = await numaMinter.setTokenAddress(numa_address);
    let receipt = await tx.wait(1);

    // ***********************vault manager **********************************
    vaultManager = await ethers.deployContract("VaultManager",
    [numa_address, NUAM_ADDRESS]
    );
    deploymentReceipt = await vaultManager.deploymentTransaction().wait(1);
    //await vaultManager.waitForDeployment();
    let VAULTMANAGER_ADDRESS = await vaultManager.getAddress();

    console.log('vault manager address: ', VAULTMANAGER_ADDRESS);
    
    // ***********************vault **********************************
    vault = await ethers.deployContract("NumaVault",
            [numa_address,lstAddress,
                ethers.parseEther("1"),
                VAULT_ORACLE_ADDRESS,
                NUMAMINTER_ADDRESS,
                debt,
                rwdFromDebt]
            );
    deploymentReceipt = await vault.deploymentTransaction().wait(1);
    //await vault.waitForDeployment();
    let VAULT_ADDRESS = await vault.getAddress();
        
    console.log('vault address: ', VAULT_ADDRESS);

    
    console.log('addToMinters');
    tx = await numaMinter.addToMinters(VAULT_ADDRESS);
    receipt = await tx.wait(1);
    
    console.log('addVault');
    tx = await vaultManager.addVault(VAULT_ADDRESS);
    receipt = await tx.wait(1);
    // let tx = await vaultManager.addVault(VAULT_ADDRESS);
    // let receipt = await tx.wait(1);


    //console.log(receipt);
    console.log('setVaultManager');
    tx = await vault.setVaultManager(VAULTMANAGER_ADDRESS);
    receipt = await tx.wait(1);
    console.log('setFeeAddress setRwdAddress');

    tx = await vault.setFeeAddress(feeReceiver,false);
    receipt = await tx.wait(1);
    tx = await vault.setRwdAddress(rwdReceiver,false);
    receipt = await tx.wait(1);
    console.log('grant minter role');

    // for fork testing
    const address = "0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69";
    await helpers.impersonateAccount(address);
    const impersonatedSigner = await ethers.getSigner(address);
    await helpers.setBalance(address, ethers.parseEther("10")); 
    tx = await numa.connect(impersonatedSigner).grantRole(roleMinter, NUMAMINTER_ADDRESS); 

    receipt = await tx.wait(1);
    // store contract addresses
    const data = { minter: NUMAMINTER_ADDRESS, vault: VAULT_ADDRESS,assetManager: NUAM_ADDRESS,oracle: VAULT_ORACLE_ADDRESS,vaultManager:VAULTMANAGER_ADDRESS};
    fs.writeFileSync("outputFork.json", JSON.stringify(data, null, 2));
    console.log("contracts addresses saved to outputFork.json");

 
 
}




deployVaultV2()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })
   


