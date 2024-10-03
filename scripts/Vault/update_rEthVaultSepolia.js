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
 
    let numa = await hre.ethers.getContractAt("NUMA", numa_address);
    let VMO_ADDRESS = "0x331f74F3270d4EdB7F509D75565dafF7D5428dC2";
    let VM_ADDRESS = "0xF6b774a90854Aa1245dfA1E612d082E0F8f780b5";

   // - deploy new vault
   // - pause vault1, revoke minting role

   // - remove v1 from vault manager
   // - add v2 to vault manager
   // - set vault manager to v2



   // - get all rEth from vault1
   // - send reth to new vault
   // - grant role
   // - set fee/rwd address
   // - unpause




    // 

   // vault1 rETH
//    let Vault2 = await ethers.deployContract("NumaVault",
//    [numa_address,LST_ADDRESS,ethers.parseEther("1"),VMO_ADDRESS]);
//    await Vault2.waitForDeployment();

let Vault2  =  await hre.ethers.getContractAt("NumaVault", "0x1c027eb3A6216A0cD6428F8577D231A0EfCA3F50");;
   let VAULT2_ADDRESS = await Vault2.getAddress();
   console.log('vault rETH address: ', VAULT2_ADDRESS);

   // pause V1
   let V1_ADDRESS = "0x777DC0e09be08171E0ed656A2BE98AeE427F8Ba3";
   let V1 = await hre.ethers.getContractAt("NumaVault", V1_ADDRESS);;
  // await V1.pause();
   // just in case
   await numa.revokeRole(roleMinter, V1_ADDRESS);

    //
    
    let VM = await hre.ethers.getContractAt("VaultManager", VM_ADDRESS);;

    // await VM.removeVault(V1_ADDRESS);

    // console.log("number of vaults should be 0");
    // console.log(await VM.getVaults());

    // await VM.addVault(VAULT2_ADDRESS);
    // console.log("number of vaults should be 1");
    console.log(await VM.getVaults());



// **************


    await Vault2.setVaultManager(VM_ADDRESS);

   // fee address
   FEE_ADDRESS = VM_ADDRESS;
   RWD_ADDRESS = VM_ADDRESS;
   await Vault2.setFeeAddress(FEE_ADDRESS,false);
   await Vault2.setRwdAddress(RWD_ADDRESS,false);

   // allow vault to mint numa
   // TODO: etherscan, 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6
   await numa.grantRole(roleMinter, VAULT2_ADDRESS);

   

   // BUY FEE 25%
   await Vault2.setBuyFee(ethers.parseEther("0.75"));

   // TODO transfer rETH to vault to initialize price
   let lstToken = await hre.ethers.getContractAt("LstTokenMock", LST_ADDRESS);
   await V1.withdrawToken(LST_ADDRESS,await lstToken.balanceOf(V1_ADDRESS),VAULT2_ADDRESS) ;

   // TODO: deploy front end
  

   // TODO UNPAUSE
   await Vault2.unpause();


   // TODO: front end official deploy

   // Transfer ownership

   // TODO grant ownership to owner
   // await Vault2.transferOwnership(newOwner_ADDRESS);

   // TODO: connect with new owner: from etherscan
   // await Vault2.acceptOwnership();







}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })