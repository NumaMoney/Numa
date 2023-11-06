

const artifacts = {
  UniswapV3Factory: require("@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json"),
  NonfungiblePositionManager: require("@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json"),
  UniswapV3Pool: require("@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json"),
  AggregatorV3: require("@chainlink/contracts/abi/v0.8/AggregatorV3Interface.json"),
};

const weth9 = require('@ethereum-artifacts/weth9');


let initPool = async function (token0_, token1_, fee_, EthPriceInNuma_,nonfungiblePositionManager,wethAddress) {
  // const pool = await IUniswapV3Pool.at(pool_) //Pool we're fetching init price from
  // const slot0 = await pool.slot0()
  // const price = slot0.sqrtPriceX96
  const fee = fee_;

  // Uniswap reverts pool initialization if you don't sort by address number, beware!
  let token0, token1
  if (token1_ > token0_) {
    token1 = token1_
    token0 = token0_
  } else {
    token1 = token0_
    token0 = token1_
  }


  let sqrtPrice = Math.sqrt(EthPriceInNuma_)

  if (token0 === wethAddress) 
  {
      price = BigInt(sqrtPrice*2**96);
  }
  else 
  {
      price = BigInt(2**96/sqrtPrice);
  }


  await nonfungiblePositionManager.createAndInitializePoolIfNecessary(token0, token1, fee, price)
}


let initPoolETH = async function (token0_, token1_, fee_, price_,nonfungiblePositionManager,wethAddress) {
  // Uniswap reverts pool initialization if you don't sort by address number, beware!
  let sqrtPrice = Math.sqrt(price_);
  let token0, token1, price;

  if (token1_ > token0_) 
  {
    token1 = token1_
    token0 = token0_
  }
  else 
  {
    token1 = token0_
    token0 = token1_
  }

  if (token0 === wethAddress) 
  {
      price = BigInt(sqrtPrice*2**96);
     
  }
  else 
  {
      price = BigInt(2**96/sqrtPrice);
  }
 
  await nonfungiblePositionManager.createAndInitializePoolIfNecessary(token0, token1, fee_, price)
}

let addLiquidity = async function (
  token0_, 
  token1_, 
  token0Contract,
  token1Contract,
  fee_, 
  tickLower_ = -887220, 
  tickUpper_ = 887220, 
  amount0ToMint_,
  amount1ToMint_,
  amount0Min_ = 0,
  amount1Min_ = 0,
  recipient_ = account,
  timestamp_ = Math.ceil(Date.now()/1000 + 300),
  nonfungiblePositionManager) 
  {
      let nonfungiblePositionManagerAddress = await nonfungiblePositionManager.getAddress();
      // Uniswap reverts pool initialization if you don't sort by address number, beware!
      let token0, token1
      if (token1_ > token0_) 
      {
          token1 = token1Contract;
          token0 = token0Contract;
      }
      else 
      {
          token1 = token0Contract;
          token0 = token1Contract;
      }
      let mintParams = [
        await token0.getAddress(), 
        await token1.getAddress(), 
        fee_, 
        tickLower_, 
        tickUpper_, 
        BigInt(amount0ToMint_), 
        BigInt(amount1ToMint_),
        amount0Min_,
        amount1Min_,
        recipient_,
        timestamp_
      ];
      await token0.approve(nonfungiblePositionManagerAddress, amount0ToMint_);
      await token1.approve(nonfungiblePositionManagerAddress, amount1ToMint_);

      const tx = await nonfungiblePositionManager.mint(
          mintParams,
          { gasLimit: '1000000' }
          );
      const receipt = await tx.wait();
      //console.log(receipt);

      //const {logs} = await nonfungiblePositionManager.mint(mintParams);
      //console.log(logs);

      // const tokenId = logs[1].args.tokenId;
      // return tokenId;
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
      liquidity: liquidity.toString(),
      sqrtPriceX96: slot0[0],
      tick: slot0[1],
    }
  }
  

  
  // Export it to make it available outside
  module.exports.getPoolData = getPoolData;
  module.exports.initPoolETH = initPoolETH;
  module.exports.initPool = initPool;
  module.exports.addLiquidity = addLiquidity;
  module.exports.weth9 = weth9;
  module.exports.artifacts = artifacts;

