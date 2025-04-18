const { ContractFactory, utils } = require("ethers")
const WETH9 = require("../WETH9.json")

const fs = require('fs');
const { promisify } = require('util');

const artifacts = {
  UniswapV3Factory: require("@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json"),
  SwapRouter: require("@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json"),
  NFTDescriptor: require("@uniswap/v3-periphery/artifacts/contracts/libraries/NFTDescriptor.sol/NFTDescriptor.json"),
  NonfungibleTokenPositionDescriptor: require("@uniswap/v3-periphery/artifacts/contracts/NonfungibleTokenPositionDescriptor.sol/NonfungibleTokenPositionDescriptor.json"),
  NonfungiblePositionManager: require("@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json"),
  WETH9,
};

const WETH_ADDRESS= '0x82aF49447D8a07e3bd95BD0d56f35241523fBab1'

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


async function main() {
  const [owner] = await ethers.getSigners();

  // not needed as I will use arbitrum fork
  Weth = new ContractFactory(artifacts.WETH9.abi, artifacts.WETH9.bytecode, owner);
  weth = await Weth.deploy();

  //const wethContract = await hre.ethers.getContractAt(artifacts.WETH9.abi, WETH_ADDRESS);

  Factory = new ContractFactory(artifacts.UniswapV3Factory.abi, artifacts.UniswapV3Factory.bytecode, owner);
  factory = await Factory.deploy();

  let factoryAddress = await factory.getAddress();
  //let weth9Address = await weth.getAddress();
  let weth9Address = WETH_ADDRESS;

  SwapRouter = new ContractFactory(artifacts.SwapRouter.abi, artifacts.SwapRouter.bytecode, owner);
  swapRouter = await SwapRouter.deploy(factoryAddress, weth9Address);

  NFTDescriptor = new ContractFactory(artifacts.NFTDescriptor.abi, artifacts.NFTDescriptor.bytecode, owner);
  nftDescriptor = await NFTDescriptor.deploy();

  let NFTDescriptorAddress = await nftDescriptor.getAddress();

  const linkedBytecode = linkLibraries(
    {
      bytecode: artifacts.NonfungibleTokenPositionDescriptor.bytecode,
      linkReferences: {
        "NFTDescriptor.sol": {
          NFTDescriptor: [
            {
              length: 20,
              start: 1681,
            },
          ],
        },
      },
    },
    {
      NFTDescriptor: NFTDescriptorAddress,
    }
  );

  NonfungibleTokenPositionDescriptor = new ContractFactory(artifacts.NonfungibleTokenPositionDescriptor.abi, linkedBytecode, owner);

  const nativeCurrencyLabelBytes = ethers.encodeBytes32String('WETH');
  nonfungibleTokenPositionDescriptor = await NonfungibleTokenPositionDescriptor.deploy(weth9Address, nativeCurrencyLabelBytes);

  let nonfungibleTokenPositionDescriptorAddress = await nonfungibleTokenPositionDescriptor.getAddress();

  NonfungiblePositionManager = new ContractFactory(artifacts.NonfungiblePositionManager.abi, artifacts.NonfungiblePositionManager.bytecode, owner);
  nonfungiblePositionManager = await NonfungiblePositionManager.deploy(await factory.getAddress(), weth9Address, nonfungibleTokenPositionDescriptorAddress);

  let addresses = [
    `WETH_ADDRESS=${weth9Address}`,
    `FACTORY_ADDRESS=${await factory.getAddress()}`,
    `SWAP_ROUTER_ADDRESS=${await swapRouter.getAddress()}`,
    `NFT_DESCRIPTOR_ADDRESS=${await nftDescriptor.getAddress()}`,
    `POSITION_DESCRIPTOR_ADDRESS=${await nonfungibleTokenPositionDescriptor.getAddress()}`,
    `POSITION_MANAGER_ADDRESS=${await nonfungiblePositionManager.getAddress()}`,
  ]
  const data = addresses.join('\n')

  const writeFile = promisify(fs.appendFile);
  const filePath = '.env';
  return writeFile(filePath, data)
      .then(() => {
        console.log('Addresses recorded.');
      })
      .catch((error) => {
        console.error('Error logging addresses:', error);
        throw error;
      });
}

/*
npx hardhat run --network localhost scripts/01_deployContracts.js
*/

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
