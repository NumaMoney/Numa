require('dotenv').config()

TETHER_ADDRESS = process.env.TETHER_ADDRESS
USDC_ADDRESS = process.env.USDC_ADDRESS
WRAPPED_BITCOIN_ADDRESS = process.env.WRAPPED_BITCOIN_ADDRESS
WETH_ADDRESS = process.env.WETH_ADDRESS
FACTORY_ADDRESS = process.env.FACTORY_ADDRESS
SWAP_ROUTER_ADDRESS = process.env.SWAP_ROUTER_ADDRESS
NFT_DESCRIPTOR_ADDRESS = process.env.NFT_DESCRIPTOR_ADDRESS
POSITION_DESCRIPTOR_ADDRESS = process.env.POSITION_DESCRIPTOR_ADDRESS
POSITION_MANAGER_ADDRESS = process.env.POSITION_MANAGER_ADDRESS
USDT_USDC_500 = process.env.USDT_USDC_500


const artifacts = {
  NonfungiblePositionManager: require("@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json"),
  Usdt: require("../../artifacts/contracts/tests/Tether.sol/Tether.json"),
  Usdc: require("../../artifacts/contracts/tests/UsdCoin.sol/UsdCoin.json"),
  UniswapV3Pool: require("@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json"),
  UniswapV3Factory: require("@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json"),
};

const { Contract } = require("ethers")
const { Token } = require('@uniswap/sdk-core')
const { Pool, Position, nearestUsableTick } = require('@uniswap/v3-sdk')

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

async function main() {
  const [_owner, signer2] = await ethers.getSigners();
  const provider = ethers.provider

  const usdtContract = new Contract(TETHER_ADDRESS,artifacts.Usdt.abi,provider)
  const usdcContract = new Contract(USDC_ADDRESS,artifacts.Usdc.abi,provider)

  await usdtContract.connect(signer2).approve(POSITION_MANAGER_ADDRESS, ethers.parseEther('1000'))
  await usdcContract.connect(signer2).approve(POSITION_MANAGER_ADDRESS, ethers.parseEther('1000'))

  const poolContract = new Contract(USDT_USDC_500, artifacts.UniswapV3Pool.abi, provider)

  const poolData = await getPoolData(poolContract)


  let Token0 = new Token(31337, TETHER_ADDRESS, 18, 'USDT', 'Tether')
  let Token1 = new Token(31337, USDC_ADDRESS, 18, 'USDC', 'UsdCoin')

  let token0 = TETHER_ADDRESS;
  let token1 = USDC_ADDRESS;
  if (token1 < token0)
  {
    let tmp = token1;
    token1 = token0;
    token0 = tmp;
    Token1 = new Token(31337, TETHER_ADDRESS, 18, 'USDT', 'Tether')
    Token0 = new Token(31337, USDC_ADDRESS, 18, 'USDC', 'UsdCoin')
    console.log("switching in 4");
  }
  


  console.log(poolData.tick);
  const pool = new Pool(
    Token0,
    Token1,
    Number(poolData.fee),
    poolData.sqrtPriceX96.toString(),
    poolData.liquidity.toString(),
    Number(poolData.tick)
  )

  const position = new Position({
    pool: pool,
    liquidity: ethers.parseEther('1').toString(),
    tickLower: nearestUsableTick( Number(poolData.tick),  Number(poolData.tickSpacing)) -  Number(poolData.tickSpacing) * 2,
    tickUpper: nearestUsableTick( Number(poolData.tick),  Number(poolData.tickSpacing)) +  Number(poolData.tickSpacing) * 2,
  })

  const { amount0: amount0Desired, amount1: amount1Desired} = position.mintAmounts

  console.log(nearestUsableTick( Number(poolData.tick),  Number(poolData.tickSpacing)) -  Number(poolData.tickSpacing) * 2);
  console.log(nearestUsableTick( Number(poolData.tick),  Number(poolData.tickSpacing)) +  Number(poolData.tickSpacing) * 2);


  params = {
    token0: token0,
    token1: token1,
    fee: poolData.fee,
    tickLower: nearestUsableTick( Number(poolData.tick),  Number(poolData.tickSpacing)) -  Number(poolData.tickSpacing) * 2,
    tickUpper: nearestUsableTick( Number(poolData.tick),  Number(poolData.tickSpacing)) +  Number(poolData.tickSpacing) * 2,
    amount0Desired: amount0Desired.toString(),
    amount1Desired: amount1Desired.toString(),
    amount0Min: 0,
    amount1Min: 0,
    recipient: signer2.address,
    deadline: Math.floor(Date.now() / 1000) + (60 * 10) + 10000000000
  }
  const factory = new Contract(
    FACTORY_ADDRESS,
    artifacts.UniswapV3Factory.abi,
    provider
  )
  
  const poolAddress = await factory.connect(_owner).getPool(
    token0,
    token1,
    poolData.fee,
  )
  console.log(poolAddress);

  const nonfungiblePositionManager = new Contract(
    POSITION_MANAGER_ADDRESS,
    artifacts.NonfungiblePositionManager.abi,
    provider
  )

  const tx = await nonfungiblePositionManager.connect(signer2).mint(
    params,
    { gasLimit: '1000000' }
  )
  await tx.wait()
}

/*
  npx hardhat run --network localhost scripts/04_addLiquidity.js
*/

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
