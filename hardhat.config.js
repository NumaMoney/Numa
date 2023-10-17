
require("@openzeppelin/hardhat-upgrades");
require("@nomicfoundation/hardhat-chai-matchers")
require("@onmychain/hardhat-uniswap-v2-deploy-plugin");
require("dotenv").config();



/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    compilers: [
      {
        version: "0.7.6",   
      },
      {
        version: "0.8.19",
      },
      {
        version: "0.8.20",
      },
    ],
  },
  networks: {
    sepolia: {
      url: process.env.URL,
      accounts: [process.env.PKEY],
    },
    goerli: {
      url: process.env.URL2,
      accounts: [process.env.PKEY],
    },
    arbitest: {
      url: process.env.URL3,
      accounts: [process.env.PKEY],
    },
    hardhat: {
      forking: {
        url: "https://arbitrum-mainnet.infura.io/v3/916abfc599974040abfd299a6889c49d",
      }
    }
  },
};
