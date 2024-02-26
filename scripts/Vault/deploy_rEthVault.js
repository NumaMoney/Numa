// ************* Arbitrum deployment ************************

// 1. Oracle
// 2. nuAsset
// 3. Printer
// 4. Mint nuUSD
// 5. Setup univ3 pool
// 6. Set pool to Printer

// addresses on arbitrum
// let numa_address = "0x7FB7EDe54259Cb3D4E1EaF230C7e2b1FfC951E9A";
// let rETH_ADDRESS = "0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8";
// let RETH_FEED = "0xD6aB2298946840262FcC278fF31516D39fF611eF";


// TODO
// let FEE_ADDRESS = "";
// let RWD_ADDRESS = "";
// let newOwner_ADDRESS = "";

let UPTIME_FEED = "";
let rEth_heartbeat = 86400;

const { ethers, upgrades } = require("hardhat");
const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
// npx hardhat run --network kovan scripts/deploy_erc20.js
async function main () {
    
    const [signer] = await ethers.getSigners();
 

   

   // *********************** nuAssetManager **********************************
   let nuAM = await ethers.deployContract("nuAssetManager",
   [UPTIME_FEED]
   );
   await nuAM.waitForDeployment();
   let NUAM_ADDRESS = await nuAM.getAddress();
   console.log('nuAssetManager address: ', NUAM_ADDRESS);


   console.log('initial synth value: ', await nuAM.getTotalSynthValueEth());


   // *********************** vaultManager **********************************
   let VM = await ethers.deployContract("VaultManager",
   [numa_address,NUAM_ADDRESS]);

   await VM.waitForDeployment();
   let VM_ADDRESS = await VM.getAddress();
   console.log('vault manager address: ', VM_ADDRESS);




   let VO = await ethers.deployContract("VaultOracleSingle",
   [rETH_ADDRESS,RETH_FEED,rEth_heartbeat,UPTIME_FEED]);
   await VO.waitForDeployment();
   let VO_ADDRESS= await VO.getAddress();
  


   // vault1 rETH
   let Vault1 = await ethers.deployContract("NumaVault",
   [numa_address,rETH_ADDRESS,ethers.parseEther("1"),VO_ADDRESS]);
   

   await Vault1.waitForDeployment();
   let VAULT1_ADDRESS = await Vault1.getAddress();
   console.log('vault rETH address: ', VAULT1_ADDRESS);

   await VM.addVault(VAULT1_ADDRESS);
   await Vault1.setVaultManager(VM_ADDRESS);

   // fee address
   await Vault1.setFeeAddress(FEE_ADDRESS);
   await Vault1.setRwdAddress(RWD_ADDRESS);

   // allow vault to mint numa
   let numa = await hre.ethers.getContractAt("NUMA", numa_address);
   await numa.grantRole(roleMinter, VAULT1_ADDRESS);


   // TODO transfer rETH to vault to initialize price
   // START
   // await VM.startDecaying();
   // await Vault1.unpause();

   // Transfer ownership



   // TODO grant ownership to owner
   // await Vault1.transferOwnership(newOwner_ADDRESS);
   // await nuAM.transferOwnership(newOwner_ADDRESS);
   // await VO.transferOwnership(newOwner_ADDRESS);
   // await VM.transferOwnership(newOwner_ADDRESS);

   // TODO: connect with new owner: from etherscan
   // await Vault1.acceptOwnership();
   // await nuAM.acceptOwnership();
   // await VO.acceptOwnership();
   // await VM.acceptOwnership();







}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })