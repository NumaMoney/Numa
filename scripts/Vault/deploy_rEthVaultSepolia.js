// ************* Arbitrum deployment ************************
// deployer: 0x96bad7E7236BC8EdCE36A9dA71288a39c7638F9a






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

// TODO CONFIRM
let decayAmount = "1800000";
let constantRemoved = "500000";
let decayPeriod = 365 * 24*3600;
// TODO burn
let burnAmount = "5000000";




// SEPOLIA
let numa_address = "0x2e4a312577A78786051052c28D5f1132d93c557A";
let LST_ADDRESS = "0x1521c67fdfdb670fa21407ebdbbda5f41591646c";
let uptimeFeedAddress = "";

decayAmount = "26000000";
decayPeriod = 12*3600;

constantRemoved = "400000";




const { ethers, upgrades } = require("hardhat");
const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));

async function main () {
    
    const [signer] = await ethers.getSigners();
 

    // *********************** nuAssetManager **********************************
    let nuAM = await ethers.deployContract("nuAssetManager",
   ["0x0000000000000000000000000000000000000000"]// no sequencer up feed on sepolia
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




   // using custom MockOracle as we don't have rEth chainlink feeds on sepolia
    let VMO = await ethers.deployContract("VaultMockOracle",[]);
    await VMO.waitForDeployment();
    let VMO_ADDRESS= await VMO.getAddress();



    // 

   // vault1 rETH
   let Vault1 = await ethers.deployContract("NumaVault",
   [numa_address,LST_ADDRESS,ethers.parseEther("1"),VMO_ADDRESS]);


   await Vault1.waitForDeployment();
   let VAULT1_ADDRESS = await Vault1.getAddress();
   console.log('vault rETH address: ', VAULT1_ADDRESS);
 

   console.log('add vault to vault manager');
   await VM.addVault(VAULT1_ADDRESS);
   console.log('set vault manager to reth vault');
   await Vault1.setVaultManager(VM_ADDRESS);

   // fee address
   FEE_ADDRESS = VM_ADDRESS;
   RWD_ADDRESS = VM_ADDRESS;
   await Vault1.setFeeAddress(FEE_ADDRESS,false);
   await Vault1.setRwdAddress(RWD_ADDRESS,false);

   // allow vault to mint numa
   // TODO: etherscan, 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6
   let numa = await hre.ethers.getContractAt("NUMA", numa_address);
   await numa.grantRole(roleMinter, VAULT1_ADDRESS);

   await VM.setDecayValues( ethers.parseEther(decayAmount),decayPeriod,0,0,ethers.parseEther(constantRemoved));

   // BUY FEE 25%
   await Vault1.setBuyFee(ethers.parseEther("0.75"));

   // TODO transfer rETH to vault to initialize price
   let lstToken = await hre.ethers.getContractAt("LstTokenMock", LST_ADDRESS);
   await lstToken.transfer(VAULT1_ADDRESS, ethers.parseEther("2000"));

   // TODO: deploy front end
  
   // TODO START
   await VM.startDecay();

   // TODO UNPAUSE
   await Vault1.unpause();


   // TODO: front end official deploy

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


   // new vault?

   // - deploy new vault
   // - get all rEth from vault1
   // - pause it
   // - send reth to new vault
   // - remove v1 from vault manager
   // - add v2 to vauylt manager
   // - set vault manager to v2
   // - grant role
   // - set fee/rwd address
   // - set decay values, startdecay, unpause







}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })