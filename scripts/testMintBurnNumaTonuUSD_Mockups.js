const { ethers, upgrades } = require("hardhat");


// uniswap V3 interactions
NUMA_ADDRESS= '0x7FB7EDe54259Cb3D4E1EaF230C7e2b1FfC951E9A'
WETH_ADDRESS= '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1'
FACTORY_ADDRESS= '0x1F98431c8aD98523631AE4a59f267346ea31F984'
//SWAP_ROUTER_ADDRESS= '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0'
//NFT_DESCRIPTOR_ADDRESS= '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9'
//POSITION_DESCRIPTOR_ADDRESS= '0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9'
POSITION_MANAGER_ADDRESS= '0xC36442b4a4522E871399CD717aBDD847Ab11FE88'

const artifacts = {
    UniswapV3Factory: require("@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json"),
    NonfungiblePositionManager: require("@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json"),
    UniswapV3Pool: require("@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json"),
  };

  const { Token } = require('@uniswap/sdk-core')
  const { Pool, Position, nearestUsableTick } = require('@uniswap/v3-sdk')

  //const { BigNumber } = require("ethers")
const bn = require('bignumber.js')
bn.config({ EXPONENTIAL_AT: 999999, DECIMAL_PLACES: 40 })

  function encodePriceSqrt(reserve1, reserve0)
   {

    return 
      new bn(reserve1.toString())
        .div(reserve0.toString())
        .sqrt()
        .multipliedBy(new bn(2).pow(96))
        .integerValue(3)
        .toString();
    
  }
  

  async function getPoolData(poolContract) {
    const [tickSpacing, fee, liquidity, slot0] = await Promise.all([
      poolContract.tickSpacing(),
      poolContract.fee(),
      poolContract.liquidity(),
      poolContract.slot0(),
    ])
  
    return {
      tickSpacing: tickSpacing,
      fee: fee,
      liquidity: liquidity,
      sqrtPriceX96: slot0[0],
      tick: slot0[1],
    }
  }

// npx hardhat run --network kovan scripts/deploy_erc20.js
async function main () {
    const [owner,signer2] = await ethers.getSigners();

    // Parameters
    // TODO: check these values coming from Offshift
    let INTERVAL_SHORT = 180;
    let INTERVAL_LONG = 1800;
    let weth9_arbi = "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1";
    let flexFeeThreshold = 0;// TODO


    let priceFeedETHUSD_arbi = "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612";
    let priceFeedBTCUSD_arbi = "0x6ce185860a4963106506C203335A2910413708e9";

    // Deploy & mint Numa
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


      // ****************** CHAINLINK *********************************
      // Use arbitrum mainnet fork chainlink pricefeeds

      // Deploy Oracle
      const oracle = await ethers.deployContract("Oracle", [weth9_arbi,INTERVAL_SHORT,INTERVAL_LONG,flexFeeThreshold,owner], {
        value: 0,
      });
    
      await oracle.waitForDeployment();
      let oracleAddress = await oracle.getAddress();
      console.log('Oracle deployed to:', oracleAddress);

        // call chainlinkPrice to check values from arbitrum fork
    //   let priceETH = await oracle.chainlinkPrice(priceFeedETHUSD_arbi);
    //   console.log('Chainlink price of ETH in USD: ', priceETH);


    //   let priceBTC = await oracle.chainlinkPrice(priceFeedBTCUSD_arbi);
    //   console.log('Chainlink price of BTC in USD: ', priceBTC);


    // ***************************** UNISWAP V3 *************************
    // cf https://gist.github.com/BlockmanCodes/d0f1e31f711011b93b3a2fef96bf322c
    const factory = await hre.ethers.getContractAt(artifacts.UniswapV3Factory.abi, FACTORY_ADDRESS);
    
    const nonfungiblePositionManager = await hre.ethers.getContractAt(artifacts.NonfungiblePositionManager.abi, POSITION_MANAGER_ADDRESS);

    let f  = await nonfungiblePositionManager.totalSupply();
    console.log(f);
    
      //console.log(nonfungiblePositionManager);

      // then create our pool
      let token0 = NUMA_ADDRESS;
      let token1 =  WETH_ADDRESS;
      let fee = 300;//500
      // TODO 1 NUMA = 1 ETH for now
      //let price =  encodePriceSqrt(1, 1);// TODO: make it work
      //console.log(price);


      await nonfungiblePositionManager.connect(owner).createAndInitializePoolIfNecessary(
        token0,
        token1,
        //fee,
        //price,
       fee,
        "80000000000000000000000000000",
        
        { gasLimit: 10000000 }
      );


    //   const poolAddress = await factory.connect(owner).getPool(
    //     token0,
    //     token1,
    //     fee,
    //   );

    //   console.log('pool address: ',poolAddress);

//       // add liquidity
//       const poolContract = await hre.ethers.getContractAt(artifacts.UniswapV3Pool.abi, poolAddress);
//       const poolData = await getPoolData(poolContract);

//       const chainid = 31337;
//       const WethToken = new Token(chainid, weth9_arbi, 18)
//       const NumaToken = new Token(chainid, NUMA_ADDRESS, 18)

// console.log('fee ',poolData.fee);
// console.log('sqrtPricex96 ',poolData.sqrtPriceX96.toString());

//   const pool = new Pool(
//     NumaToken,
//     WethToken,
//     300,// hundreds of bps?
//     poolData.sqrtPriceX96.toString(),
//     poolData.liquidity.toString(),
//     poolData.tick
//   )

//   const position = new Position({
//     pool: pool,
//     liquidity: ethers.utils.parseEther('1'),
//     tickLower: nearestUsableTick(poolData.tick, poolData.tickSpacing) - poolData.tickSpacing * 2,
//     tickUpper: nearestUsableTick(poolData.tick, poolData.tickSpacing) + poolData.tickSpacing * 2,
//   })

//   const { amount0: amount0Desired, amount1: amount1Desired} = position.mintAmounts

//   params = {
//     token0: NUMA_ADDRESS,
//     token1: WethToken,
//     fee: poolData.fee,
//     tickLower: nearestUsableTick(poolData.tick, poolData.tickSpacing) - poolData.tickSpacing * 2,
//     tickUpper: nearestUsableTick(poolData.tick, poolData.tickSpacing) + poolData.tickSpacing * 2,
//     amount0Desired: amount0Desired.toString(),
//     amount1Desired: amount1Desired.toString(),
//     amount0Min: 0,
//     amount1Min: 0,
//     recipient: signer2.address,
//     deadline: Math.floor(Date.now() / 1000) + (60 * 10)
//   }



//   const tx = await nonfungiblePositionManager.connect(signer2).mint(
//     params,
//     { gasLimit: '1000000' }
//   )
//   const receipt = await tx.wait()
  
      // Deploy MoneyPrinter


      // mint nuUSD, check amount

      // burn nuUSD, check Numa amount


}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });


    


