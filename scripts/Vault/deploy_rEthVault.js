// 1. Oracle
// 2. nuAsset
// 3. Printer
// 4. Mint nuUSD
// 5. Setup univ3 pool
// 6. Set pool to Printer

// addresses on arbitrum
let numaAddress = "0x7FB7EDe54259Cb3D4E1EaF230C7e2b1FfC951E9A";

let rETH_ADDRESS = "0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8";
let RETH_FEED = "0xD6aB2298946840262FcC278fF31516D39fF611eF";
// let wstETH_FEED = "0xb523AE262D20A936BC152e6023996e46FDC2A95D";
// let wstETH_ADDRESS = "0x5979d7b546e38e414f7e9822514be443a4800529";
// TODO
let FEE_ADDRESS = "";
let RWD_ADDRESS = "";
let newOwnerAddress = "";

let decaydenom = 267;

const { ethers, upgrades } = require("hardhat");

// npx hardhat run --network kovan scripts/deploy_erc20.js
async function main () {
    
    const [signer] = await ethers.getSigners();


    // TODO get admin rôle on Numa so that I can give vault minter rôle

   // *********************** nuAssetManager **********************************
   let nuAM = await ethers.deployContract("nuAssetManager",
   []
   );
   await nuAM.waitForDeployment();
   let NUAM_ADDRESS = await nuAM.getAddress();
   console.log('nuAssetManager address: ', NUAM_ADDRESS);


   console.log('initial synth value: ', await nuAM.getTotalSynthValueEth());


   // *********************** vaultManager **********************************
   let VM = await ethers.deployContract("VaultManager",
   []);
   await VM.waitForDeployment();
   let VM_ADDRESS = await VM.getAddress();
   console.log('vault manager address: ', VM_ADDRESS);


   // *********************** vaultOracle **********************************
   let VO = await ethers.deployContract("VaultOracle",
   []);
   await VO.waitForDeployment();
   let VO_ADDRESS= await VO.getAddress();
   console.log('vault oracle address: ', VO_ADDRESS);

   // adding rETH to our oracle
   await VO.setTokenFeed(rETH_ADDRESS,RETH_FEED);

   // vault1 rETH
   let Vault1 = await ethers.deployContract("NumaVault",
   [numa_address,rETH_ADDRESS,ethers.parseEther("1"),VO_ADDRESS,NUAM_ADDRESS,decaydenom]);
   await Vault1.waitForDeployment();
   let VAULT1_ADDRESS = await Vault1.getAddress();
   console.log('vault rETH address: ', VAULT1_ADDRESS);

   await VM.addVault(VAULT1_ADDRESS);
   await Vault1.setVaultManager(VM_ADDRESS);
   // fee address
   await Vault1.setFeeAddress(FEE_ADDRESS);
   await Vault1.setRwdAddress(RWD_ADDRESS);

   // allow vault to mint numa
   await numa.grantRole(roleMinter, VAULT1_ADDRESS);


   // TODO transfer rETH to vault to initialize price
   // await erc20_rw.connect(impersonatedSigner).transfer(VAULT1_ADDRESS, ethers.parseEther("100"));

   await Vault1.unpause();



   // TODO grant ownership to owner
   // TOKEN
//    await myToken.grantRole(rolePauser, newRoleOwnerAddress);
//    await myToken.grantRole(roleMinter, newRoleOwnerAddress);
//    await myToken.grantRole(roleUpgrade, newRoleOwnerAddress);
//    await myToken.grantRole(roleAdmin, newRoleOwnerAddress);

//    // renounce 
//    await myToken.renounceRole(rolePauser, owner.address);
//    await myToken.renounceRole(roleMinter, owner.address);
//    await myToken.renounceRole(roleUpgrade, owner.address);
//    await myToken.renounceRole(roleAdmin, owner.address);

await Vault1.transferOwnership(newOwnerAddress);
await nuAM.transferOwnership(newOwnerAddress);
await VO.transferOwnership(newOwnerAddress);
await VM.transferOwnership(newOwnerAddress);






}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })