
require("@openzeppelin/hardhat-upgrades");
require("@nomicfoundation/hardhat-chai-matchers")
require("@onmychain/hardhat-uniswap-v2-deploy-plugin");
require("@nomicfoundation/hardhat-ledger");
require("@nomicfoundation/hardhat-verify");
require("dotenv").config();



/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.19",
  networks: {
    sepolia: {
      url: process.env.URL,
      accounts: [process.env.PKEY2],
    },
    goerli: {
      url: process.env.URL2,
      accounts: [process.env.PKEY2],
    },
    arbitest: {
      url: process.env.URL4,
      accounts: [process.env.PKEY],
    },
    arbitrum: {
      url: process.env.URL3,
      ledgerAccounts: [
        "0x47786AC88f8CDB8D3A5FE956e51F95b4aE9636fa",
      ],
    },
  },
  etherscan: {
    apiKey: {
        arbitrumOne: "7QJ5HEMUC13QIS29HDZGVMXYSW17EF56VK",
    }
  }
};
