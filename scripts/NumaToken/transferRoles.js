const { ethers, upgrades } = require("hardhat");

// npx hardhat run --network kovan scripts/deploy_erc20.js
async function main () 
{
    
    const [owner] = await ethers.getSigners();

    // token address
    let deployedAddress = "0x15B2F0Df5659585b3030274168319185CFC9a9f4";
    const Numa = await ethers.getContractFactory('NUMA')
    const myToken = await Numa.attach(deployedAddress);



  
    let newRoleOwnerAddress = "0x6aeC8F3EeA17D903CCEcbC4FA9aAB67Fa1F0D264";

    const rolePauser = ethers.keccak256(ethers.toUtf8Bytes("PAUSER_ROLE"));
    const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
    const roleUpgrade = ethers.keccak256(ethers.toUtf8Bytes("UPGRADER_ROLE"));
    const roleAdmin = '0x0000000000000000000000000000000000000000000000000000000000000000';


    //
    await myToken.grantRole(rolePauser, newRoleOwnerAddress);
    await myToken.grantRole(roleMinter, newRoleOwnerAddress);
    await myToken.grantRole(roleUpgrade, newRoleOwnerAddress);
    await myToken.grantRole(roleAdmin, newRoleOwnerAddress);

    // renounce 
    await myToken.renounceRole(rolePauser, owner.address);
    await myToken.renounceRole(roleMinter, owner.address);
    await myToken.renounceRole(roleUpgrade, owner.address);
    await myToken.renounceRole(roleAdmin, owner.address);


}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })