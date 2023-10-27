const { ethers, upgrades } = require("hardhat");

// npx hardhat run --network kovan scripts/deploy_erc20.js
async function main () 
{
    
    const [owner] = await ethers.getSigners();

    // token address
    let deployedAddress = "0x15B2F0Df5659585b3030274168319185CFC9a9f4";
    const Numa = await ethers.getContractFactory('NUMA')
    const myToken = await Numa.attach(deployedAddress);



  
    let newRoleOwnerAddress = "0x1AEA6e9F801E65c9967D061d8202C3dFc3447220";

    const rolePauser = ethers.keccak256(ethers.toUtf8Bytes("PAUSER_ROLE"));
    const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
    const roleUpgrade = ethers.keccak256(ethers.toUtf8Bytes("UPGRADER_ROLE"));
    const roleAdmin = '0x0000000000000000000000000000000000000000000000000000000000000000';


    // Change ownership - admin only
    //await myToken.grantRole(rolePauser, newRoleOwnerAddress);
   
    // minter only
    await myToken.mint(
        owner.getAddress(),
        ethers.parseEther("10000000.0")
      );

}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })