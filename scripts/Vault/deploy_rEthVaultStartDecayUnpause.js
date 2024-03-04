// ************* Arbitrum deployment ************************
// deployer: 0x96bad7E7236BC8EdCE36A9dA71288a39c7638F9a
// gnosis safe test multi sig: arb1:0x218221CA9740d20e40CFca1bfA6Cb0B22F11b157
// addresses on arbitrum
let numa_address = "0x7FB7EDe54259Cb3D4E1EaF230C7e2b1FfC951E9A";
let rETH_ADDRESS = "0xec70dcb4a1efa46b8f2d97c310c9c4790ba5ffa8";
let RETH_FEED = "0xF3272CAfe65b190e76caAF483db13424a3e23dD2";
let UPTIME_FEED = "0xFdB631F5EE196F0ed6FAa767959853A9F217697D";
let rEth_heartbeat = 86400;




let FEE_ADDRESS = "";
let RWD_ADDRESS = "";
let newOwner_ADDRESS = "";
let decayAmount = "1800000";//1800000000000000000000000;
let decayPeriod = 365 * 24*3600;



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


// ARBITEST
let arbiTest = true;
let numaSupply = BigInt(93875529661474244165);
FEE_ADDRESS = "0x218221CA9740d20e40CFca1bfA6Cb0B22F11b157";
RWD_ADDRESS = "0x218221CA9740d20e40CFca1bfA6Cb0B22F11b157";
newOwner_ADDRESS = "0x218221CA9740d20e40CFca1bfA6Cb0B22F11b157";



decayAmount = "18";//18000000000000000000
decayPeriod = 48*3600;





const { ethers, upgrades } = require("hardhat");
const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));

async function main () {
    
    const [signer] = await ethers.getSigners();
 

//     if (arbiTest)
//     {
//         // DEPLOY FAKE NUMA
//         const Numa = await ethers.getContractFactory('NUMA')
//         const contract = await upgrades.deployProxy(
//         Numa,
//             [],
//             {
//                 initializer: 'initialize',
//                 kind:'uups' 
//             }
//         )
//         await contract.waitForDeployment();
//         console.log('Numa deployed to:', await contract.getAddress());

//         await contract.mint(
//             signer.getAddress(),
//             numaSupply
//           );
//        numa_address = await contract.getAddress();
//     }

//    // *********************** nuAssetManager **********************************
//    let nuAM = await ethers.deployContract("nuAssetManager",
//    [UPTIME_FEED]
//    );
//    await nuAM.waitForDeployment();
//    let NUAM_ADDRESS = await nuAM.getAddress();
//    console.log('nuAssetManager address: ', NUAM_ADDRESS);


//    console.log('initial synth value: ', await nuAM.getTotalSynthValueEth());


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
  


    // 2 steps deploy
    //numa_address = "0xc436f6e95E603c7a669872F4CE969594F9cC6230";
    //let VO_ADDRESS = "0xac399dea74f802a336b7D484C64AFDC28490b1c5";
    let VM_ADDRESS = "0x154829AE752200E8716620e0bC0ba521A4Bf658F";
    let VM = await hre.ethers.getContractAt("VaultManager", VM_ADDRESS);;

    // 

   // vault1 rETH
//    let Vault1 = await ethers.deployContract("NumaVault",
//    [numa_address,rETH_ADDRESS,ethers.parseEther("1"),VO_ADDRESS]);


//    await Vault1.waitForDeployment();
//    let VAULT1_ADDRESS = await Vault1.getAddress();
//    console.log('vault rETH address: ', VAULT1_ADDRESS);
   //0x8613177810651E3B948964aC41B1dBCabfdE03e1

//    await VM.addVault(VAULT1_ADDRESS);
//    await Vault1.setVaultManager(VM_ADDRESS);

//    // fee address
//    await Vault1.setFeeAddress(FEE_ADDRESS,false);
//    await Vault1.setRwdAddress(RWD_ADDRESS,false);

//    // allow vault to mint numa
//    let numa = await hre.ethers.getContractAt("NUMA", numa_address);
//    await numa.grantRole(roleMinter, VAULT1_ADDRESS);

//    await VM.setDecayValues( ethers.parseEther(decayAmount),decayPeriod);

   // TODO transfer rETH to vault to initialize price
   // DONE

   // TODO: deploy front end
   // DONE

   // TODO: check price 
   // 10 cts

   // KO

   // MISSED:
   // BURN TOKENS 5581112.01
   // 





   // TODO START

   let VAULT1_ADDRESS = "0x8613177810651E3B948964aC41B1dBCabfdE03e1";
   let Vault1 = await hre.ethers.getContractAt("NumaVault", VAULT1_ADDRESS);;


   await VM.startDecay();
   await Vault1.unpause();


   //55811120000000000000

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







}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })