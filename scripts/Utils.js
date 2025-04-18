
const { SwapRouter } = require('@uniswap/universal-router-sdk');
const { TradeType, Ether, Token, CurrencyAmount, Percent } = require('@uniswap/sdk-core');
const { Trade: V2Trade } = require('@uniswap/v2-sdk');
const { Pool, nearestUsableTick, TickMath, TICK_SPACINGS, FeeAmount, Trade: V3Trade, Route: RouteV3  } = require('@uniswap/v3-sdk');
const { MixedRouteTrade, Trade: RouterTrade } = require('@uniswap/router-sdk');
const IUniswapV3Pool = require('@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json');
const JSBI = require('jsbi');
//const erc20Abi = require('../abis/erc20.json');

const artifacts = {
 
  SwapRouter: require("uniV3periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json"),
  NFTDescriptor: require("uniV3periphery/artifacts/contracts/libraries/NFTDescriptor.sol/NFTDescriptor.json"),
  NonfungibleTokenPositionDescriptor: require("uniV3periphery/artifacts/contracts/NonfungibleTokenPositionDescriptor.sol/NonfungibleTokenPositionDescriptor.json"),
  NonfungiblePositionManager: require("uniV3periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json"),
  UniswapV3Pool: require("@uniswap/v3-core/artifacts/contracts/UniswapV3Pool.sol/UniswapV3Pool.json"),
  UniswapV3Factory: require("@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json"),
  AggregatorV3: require("@chainlink/contracts/abi/v0.8/AggregatorV3Interface.json"),
};

const weth9 = require('@ethereum-artifacts/weth9');

const linkLibraries = ({ bytecode, linkReferences }, libraries) => {
  Object.keys(linkReferences).forEach((fileName) => {
    Object.keys(linkReferences[fileName]).forEach((contractName) => {
      if (!libraries.hasOwnProperty(contractName)) {
        throw new Error(`Missing link library name ${contractName}`)
      }
      const address = ethers
        .getAddress(libraries[contractName])
        .toLowerCase()
        .slice(2)
      linkReferences[fileName][contractName].forEach(
        ({ start, length }) => {
          const start2 = 2 + start * 2
          const length2 = length * 2
          bytecode = bytecode
            .slice(0, start2)
            .concat(address)
            .concat(bytecode.slice(start2 + length2, bytecode.length))
        }
      )
    })
  })
  return bytecode
}




let initPoolETH = async function (token0_, token1_, fee_, price_,nonfungiblePositionManager,wethAddress) 
{  
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
      console.log("****************");

  }
  else 
  {
      price = BigInt(2**96/sqrtPrice);
      console.log("++++++++");
  }
  console.log("price");

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
      let token0, token1;
      let amount0ToMint,amount1ToMint;
      let amount0Min,amount1Min;

      if (token1_ > token0_) 
      {
          token1 = token1Contract;
          token0 = token0Contract;
          amount0ToMint = amount0ToMint_;
          amount1ToMint = amount1ToMint_;
          amount0Min = amount0Min_;
          amount1Min = amount1Min_;
      }
      else 
      {
          token1 = token0Contract;
          token0 = token1Contract;
          amount0ToMint = amount1ToMint_;
          amount1ToMint = amount0ToMint_;
          amount0Min = amount1Min_;
          amount1Min = amount0Min_;
      }
      let mintParams = [
        await token0.getAddress(), 
        await token1.getAddress(), 
        fee_, 
        tickLower_, 
        tickUpper_, 
        BigInt(amount0ToMint), 
        BigInt(amount1ToMint),
        amount0Min,
        amount1Min,
        recipient_,
        timestamp_
      ];
      await token0.approve(nonfungiblePositionManagerAddress, amount0ToMint);
      await token1.approve(nonfungiblePositionManagerAddress, amount1ToMint);




      const tx = await nonfungiblePositionManager.mint(
          mintParams,
          { gasLimit: '30000000' }
          );

      // which id is it ?
      // let info0 = await nonfungiblePositionManager.positions(1);
      // console.log(info0);
      



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


  // SWAP
  async function getPool(tokenA, tokenB, feeAmount) {
    const [token0, token1] = tokenA.sortsBefore(tokenB) ? [tokenA, tokenB] : [tokenB, tokenA]

    const poolAddress = Pool.getAddress(token0, token1, feeAmount)

    const contract = new hardhat.ethers.Contract(poolAddress, IUniswapV3Pool.abi, provider)

    let liquidity = await contract.liquidity()

    let { sqrtPriceX96, tick } = await contract.slot0()

    liquidity = JSBI.BigInt(liquidity.toString())
    sqrtPriceX96 = JSBI.BigInt(sqrtPriceX96.toString())

    return new Pool(token0, token1, feeAmount, sqrtPriceX96, liquidity, tick, [
        {
            index: nearestUsableTick(TickMath.MIN_TICK, TICK_SPACINGS[feeAmount]),
            liquidityNet: liquidity,
            liquidityGross: liquidity,
        },
        {
            index: nearestUsableTick(TickMath.MAX_TICK, TICK_SPACINGS[feeAmount]),
            liquidityNet: JSBI.multiply(liquidity, JSBI.BigInt('-1')),
            liquidityGross: liquidity,
        },
    ])
}


function swapOptions(options) {
    return Object.assign(
        {
            slippageTolerance: new Percent(5, 100),
            recipient: RECIPIENT,
        },
        options
    )
}


function buildTrade(trades) {
    return new RouterTrade({
        v2Routes: trades
            .filter((trade) => trade instanceof V2Trade)
            .map((trade) => ({
                routev2: trade.route,
                inputAmount: trade.inputAmount,
                outputAmount: trade.outputAmount,
        })),
        v3Routes: trades
            .filter((trade) => trade instanceof V3Trade)
            .map((trade) => ({
                routev3: trade.route,
                inputAmount: trade.inputAmount,
                outputAmount: trade.outputAmount,
            })),
        mixedRoutes: trades
            .filter((trade) => trade instanceof MixedRouteTrade)
            .map((trade) => ({
                    mixedRoute: trade.route,
                    inputAmount: trade.inputAmount,
                outputAmount: trade.outputAmount,
            })),
    tradeType: trades[0].tradeType,
    })
}
  

  
  // Export it to make it available outside
  module.exports.getPool = getPool;
  module.exports.swapOptions = swapOptions;
  module.exports.buildTrade = buildTrade;
  module.exports.getPoolData = getPoolData;
  module.exports.initPoolETH = initPoolETH;
  module.exports.addLiquidity = addLiquidity;
  module.exports.weth9 = weth9;
  module.exports.artifacts = artifacts;
  module.exports.SwapRouter = SwapRouter;
  module.exports.Token = Token;
  module.exports.linkLibraries = linkLibraries;