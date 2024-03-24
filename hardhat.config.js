
require("@openzeppelin/hardhat-upgrades");
require("@nomicfoundation/hardhat-chai-matchers")
require("@onmychain/hardhat-uniswap-v2-deploy-plugin");
require("dotenv").config();
//require("hardhat-gas-reporter");


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
        settings: {
          optimizer: {
            enabled: true,
            runs: 100,
          },
          viaIR: true,
        },

    },
      {
        version: "0.8.0",
      },
    ],
    
  },
  defaultNetwork: "hardhat",
  
  networks: {
    sepolia: {
      url: process.env.URL,
      accounts: [process.env.PKEY,process.env.PKEY,process.env.PKEY],
    },
    goerli: {
      url: process.env.URL2,
      accounts: [process.env.PKEY],
    },


    arbitest: {
      url: process.env.URL5,
      accounts: [process.env.PKEYARBITEST],
    },

    hardhat: {
      forking: {
        //url: process.env.URL4,// sepolia
        url: process.env.URL5,// arbitrum
      },
      allowUnlimitedContractSize: true,
      blockNumber: 187501896
    }
  },
};
