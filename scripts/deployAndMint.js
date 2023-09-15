const { ethers, upgrades } = require("hardhat");

// npx hardhat run --network kovan scripts/deploy_erc20.js
async function main () {
    const [owner] = await ethers.getSigners();

    const Numa = await ethers.getContractFactory('NUMA')
    const contract = await upgrades.deployProxy(
      Numa,
        [],
        {
            initializer: 'initialize',
            kind:'uups'
        }
    )
    await contract.waitForDeployment();
    console.log('ERC20 deployed to:', await contract.getAddress());

    await contract.mint(
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