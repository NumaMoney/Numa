// ************* Arbitrum deployment ************************
// deployer: 0x96bad7E7236BC8EdCE36A9dA71288a39c7638F9a
// gnosis safe test multi sig: arb1:0x218221CA9740d20e40CFca1bfA6Cb0B22F11b157
// addresses on arbitrum
let numa_address = "0x7FB7EDe54259Cb3D4E1EaF230C7e2b1FfC951E9A";
let rETH_ADDRESS = "0xec70dcb4a1efa46b8f2d97c310c9c4790ba5ffa8";
let RETH_FEED = "0xF3272CAfe65b190e76caAF483db13424a3e23dD2";
let UPTIME_FEED = "0xFdB631F5EE196F0ed6FAa767959853A9F217697D";
let rEth_heartbeat = 86400;



// TODO
// ** param values

// Treasury:
// 0xFC4B72FD6309d2E68B595c56EAcb256D2fE9b881

// Staking Rewards:
// 0xe5F8aA3f4000Bc6A0F07E9E3a1b9C9A3d48ed4a4

// LST Rewards:
// 0x52fAb8465f3ce229Fd104FD8155C02990A0E1326


let FEE_ADDRESS = "";
let RWD_ADDRESS = "";
let newOwner_ADDRESS = "";
let decayAmount = "1800000";
let constantRemoved = "500000";
let decayPeriod = 365 * 24*3600;
let burnAmount = "5000000";

// ** check addresses

// ** ask for drew to give me admin rôle on numa
// TODO: voir comment faire

// numbers
//203 ETH
// 0.00203
//0.0203 --> scale = 10000
// 0.00203 --> scale = 100 000

// current numa supply: 9387552966147424416516814
// scaled supply = 938755296614742441651 / 93875529661474244165
// whitelist amount = 1 800 000 000000000000000000
// scaled wl amount = 1 800 000 00000000000000 / 1 800 000 0000000000000

// 0.00203 / 93875529661474244165 / 18000000000000000000







const { ethers, upgrades } = require("hardhat");
const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));

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
   console.log('vault oracle address: ', VO_ADDRESS);




    // 

   // vault1 rETH
   let Vault1 = await ethers.deployContract("NumaVault",
   [numa_address,rETH_ADDRESS,ethers.parseEther("1"),VO_ADDRESS]);


   await Vault1.waitForDeployment();
   let VAULT1_ADDRESS = await Vault1.getAddress();
   console.log('vault rETH address: ', VAULT1_ADDRESS);
 

   console.log('add vault to vault manager');
   await VM.addVault(VAULT1_ADDRESS);
   console.log('set vault manager to reth vault');
   await Vault1.setVaultManager(VM_ADDRESS);

   // fee address
   await Vault1.setFeeAddress(FEE_ADDRESS,false);
   await Vault1.setRwdAddress(RWD_ADDRESS,false);

   // allow vault to mint numa
   let numa = await hre.ethers.getContractAt("NUMA", numa_address);
   await numa.grantRole(roleMinter, VAULT1_ADDRESS);

   await VM.setDecayValues( ethers.parseEther(decayAmount),decayPeriod,ethers.parseEther(constantRemoved));

   // BUY FEE 25%
   await Vault1.setBuyFee(750);

   // TODO transfer rETH to vault to initialize price
  

   // TODO: deploy front end
  
   // TODO START
   // await VM.startDecay();

   // TODO UNPAUSE
   // await Vault1.unpause();


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