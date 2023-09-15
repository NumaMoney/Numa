const { ethers, upgrades } = require("hardhat");

// npx hardhat run --network kovan scripts/deploy_erc20.js
async function main () {
    const Numa = await ethers.getContractFactory('NUMA')


    // token address
    let deployedAddress = "0x15B2F0Df5659585b3030274168319185CFC9a9f4";
    // uniswap pair that will trigger fee when receiver
    let pairAddress = "0xbD6C83365410AAe54d6dbafb7D813C55e2d72F58";
    // uniswap V2 router that is whitelisted as a spend (for adding liquidity)
    let uniswapV2Router = "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D";

    // we can use following code if we use an already deployed version
    const contract = await Numa.attach(
        deployedAddress
      );



    const [owner,other] = await ethers.getSigners();

    await contract.SetFee(10);
    await contract.SetFeeTriggerer(pairAddress,true);
    await contract.SetWlTransferer(uniswapV2Router,true);
   

}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })