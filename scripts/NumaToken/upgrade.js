const { ethers, upgrades } = require("hardhat");

// npx hardhat run --network kovan scripts/deploy_erc20.js
async function main () {
    const Numa = await ethers.getContractFactory('NUMA')


    // TOken address
    let deployedAddress = "0x15B2F0Df5659585b3030274168319185CFC9a9f4";
    // name of the new contract
    let newContractName = "NUMAV2";
    // we can use following code if we use an already deployed version
    const contract = await Numa.attach(
        deployedAddress
      );



    const [owner,other] = await ethers.getSigners();

   
  
    let v1_address = await contract.getAddress();
    const contractV2 = await ethers.getContractFactory(
        newContractName
    );
    console.log("Upgrading NUMAV2...");
    await upgrades.upgradeProxy(
      v1_address,
      contractV2
    );
    console.log("Upgraded Successfully");
    





}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })