
require("@openzeppelin/hardhat-upgrades");
require("@nomicfoundation/hardhat-chai-matchers")
require("@onmychain/hardhat-uniswap-v2-deploy-plugin");
require("dotenv").config();



/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.19",
  networks: {
    sepolia: {
      url: process.env.URL,
      accounts: [process.env.PKEY],
    },
    goerli: {
      url: process.env.URL2,
      accounts: [process.env.PKEY],
    },
  },
};
