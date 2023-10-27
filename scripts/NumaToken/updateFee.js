const { ethers, upgrades } = require("hardhat");

// npx hardhat run --network kovan scripts/deploy_erc20.js
async function main () {
    const Numa = await ethers.getContractFactory('NUMA')


    // token address
    let deployedAddress = "0x1521c67fDFDb670fa21407ebDbBda5F41591646c";
    // uniswap pair that will trigger fee when receiver
    let pairAddress = "0x58293Da3cA7c9F9c28d503036d1A8f335A2b0Bc3";
    // uniswap V2 router that is whitelisted as a spend (for adding liquidity)
    let uniswapV2Router = "0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506";

    // we can use following code if we use an already deployed version
    const contract = await Numa.attach(
        deployedAddress
      );



    const [owner,other] = await ethers.getSigners();

    await contract.SetFee(1000);
    await contract.SetFeeTriggerer(pairAddress,true);
    await contract.SetWlSpender(uniswapV2Router,true);
   

}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })