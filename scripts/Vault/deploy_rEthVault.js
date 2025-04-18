// ************* Arbitrum deployment ************************
// deployer: 0x96bad7E7236BC8EdCE36A9dA71288a39c7638F9a



// TODO: CONFIRM
let numa_address = "0x7FB7EDe54259Cb3D4E1EaF230C7e2b1FfC951E9A";// OK
let rETH_ADDRESS = "0xec70dcb4a1efa46b8f2d97c310c9c4790ba5ffa8"; // OK
let RETH_FEED = "0xF3272CAfe65b190e76caAF483db13424a3e23dD2";// OK
let UPTIME_FEED = "0xFdB631F5EE196F0ed6FAa767959853A9F217697D";// OK
let rEth_heartbeat = 86400;



// TODO
// ** param values

// Treasury:
// 0xFC4B72FD6309d2E68B595c56EAcb256D2fE9b881

// Staking Rewards:
// 0xe5F8aA3f4000Bc6A0F07E9E3a1b9C9A3d48ed4a4

// LST Rewards:
// 0x52fAb8465f3ce229Fd104FD8155C02990A0E1326


let FEE_ADDRESS = "0xe5F8aA3f4000Bc6A0F07E9E3a1b9C9A3d48ed4a4";
let RWD_ADDRESS = "0x52fAb8465f3ce229Fd104FD8155C02990A0E1326";
let newOwner_ADDRESS = "0xFC4B72FD6309d2E68B595c56EAcb256D2fE9b881";
//0xFC4B72FD6309d2E68B595c56EAcb256D2fE9b881
// TODO CONFIRM
let decayAmount = "1800000";
let constantRemoved = "500000";
let decayPeriod = 365 * 24*3600;
// TODO burn
let burnAmount = "5000000";





const { ethers, upgrades } = require("hardhat");
const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));

async function main () {
    
    const [signer] = await ethers.getSigners();
 

//     // *********************** nuAssetManager **********************************
//     let nuAM = await ethers.deployContract("nuAssetManager",
//     [UPTIME_FEED]
//     );
//     await nuAM.waitForDeployment();
//     let NUAM_ADDRESS = await nuAM.getAddress();
//     console.log('nuAssetManager address: ', NUAM_ADDRESS);


//     console.log('initial synth value: ', await nuAM.getTotalSynthValueEth());


//    // *********************** vaultManager **********************************
//    let VM = await ethers.deployContract("VaultManager",
//    [numa_address,NUAM_ADDRESS]);

//    await VM.waitForDeployment();
//    let VM_ADDRESS = await VM.getAddress();
//    console.log('vault manager address: ', VM_ADDRESS);




//    let VO = await ethers.deployContract("VaultOracleSingle",
//    [rETH_ADDRESS,RETH_FEED,rEth_heartbeat,UPTIME_FEED]);
//    await VO.waitForDeployment();
//    let VO_ADDRESS= await VO.getAddress();
//    console.log('vault oracle address: ', VO_ADDRESS);




//     // 

//    // vault1 rETH
//    let Vault1 = await ethers.deployContract("NumaVault",
//    [numa_address,rETH_ADDRESS,ethers.parseEther("1"),VO_ADDRESS]);


//    await Vault1.waitForDeployment();
//    let VAULT1_ADDRESS = await Vault1.getAddress();
//    console.log('vault rETH address: ', VAULT1_ADDRESS);
 

//    console.log('add vault to vault manager');
//    await VM.addVault(VAULT1_ADDRESS);
//    console.log('set vault manager to reth vault');
//    await Vault1.setVaultManager(VM_ADDRESS);

//    // fee address
//    await Vault1.setFeeAddress(FEE_ADDRESS,false);
//    await Vault1.setRwdAddress(RWD_ADDRESS,false);



    // REPRISE
    let VM_ADDRESS = "0x7Fb6e0B7e1B34F86ecfC1E37C863Dd0B9D4a0B1F";
    let VM = await hre.ethers.getContractAt("VaultManager", VM_ADDRESS);;
    let VAULT1_ADDRESS = "0x78E88887d80451cB08FDc4b9046C9D01FB8d048D";
    let Vault1 = await hre.ethers.getContractAt("NumaVault", VAULT1_ADDRESS);;

    let nuam_address = "0xd3dD70BB582633c853DC112D5dd78B0664D60e1d";
    let nuam = await hre.ethers.getContractAt("nuAssetManager", nuam_address);;
   
    let vo_ADDRESS = "0x5e69D848340b03F56097CB9852c3D0c204fd193A";
    let vo = await hre.ethers.getContractAt("VaultOracleSingle", VM_ADDRESS);;
   
    // --

   // allow vault to mint numa
   // TODO: etherscan, 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6
//    let numa = await hre.ethers.getContractAt("NUMA", numa_address);
//    await numa.grantRole(roleMinter, VAULT1_ADDRESS);

   //await VM.setDecayValues( ethers.parseEther(decayAmount),decayPeriod,ethers.parseEther(constantRemoved));

   // BUY FEE 30%
   //await Vault1.setBuyFee(700);

   // TODO transfer rETH to vault to initialize price
  

   // TODO: deploy front end
  
   // TODO START
   //await VM.startDecay();

   // TODO UNPAUSE
   //await Vault1.unpause();


   // TODO: front end official deploy

   // Transfer ownership

   // TODO grant ownership to owner
   //await Vault1.transferOwnership(newOwner_ADDRESS);
   //await nuam.transferOwnership(newOwner_ADDRESS);
  // await vo.transferOwnership(newOwner_ADDRESS);
   //await VM.transferOwnership(newOwner_ADDRESS);
  // await vo.transferOwnership(newOwner_ADDRESS);

  // DONE
   // TODO: connect with new owner: from etherscan
   // await Vault1.acceptOwnership();
   // await nuAM.acceptOwnership();
   // await VO.acceptOwnership();
   // await VM.acceptOwnership();

   // TODO verify



}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })