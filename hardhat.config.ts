
// require("@openzeppelin/hardhat-upgrades");
// require("@nomicfoundation/hardhat-chai-matchers")
// require("@onmychain/hardhat-uniswap-v2-deploy-plugin");
// require("dotenv").config();
// //require("hardhat-gas-reporter");

import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-chai-matchers";
import "@onmychain/hardhat-uniswap-v2-deploy-plugin";
import "@nomicfoundation/hardhat-foundry";
import '@typechain/hardhat'
import 'dotenv/config';
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-verify";






/** @type import('hardhat/config').HardhatUserConfig */
//module.exports = {
const config: HardhatUserConfig = {
  mocha: {
    timeout: 100000000,
  },
  solidity: {
    compilers: [
      {
        version: '0.5.16',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: '0.6.10',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
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
            runs: 200,
          },
          viaIR: true,
        },
      },
      {
        version: "0.8.15",
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
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
  allowUnlimitedContractSize: true,
  etherscan: {
    // Your API key for Etherscan
    // Obtain one at https://etherscan.io/
    apiKey: "HQMWJJVJXBXZ9EDSNUAAHRPX7YGYA537IC"
  },

  networks: {
    sepolia: {
      url: process.env.URL,
      accounts: [process.env.PKEY,process.env.PKEY,process.env.PKEY],
    },
    goerli: {
      url: process.env.URL2,
      accounts: [process.env.PKEY],
    },


    // arbitest: {
    //   url: process.env.URL5,
    //   accounts: [process.env.PKEYARBITEST],
    // },

    hardhat: {
      forking: {
        url: process.env.URL4,// sepolia
            
      },
      accounts: [ {
        privateKey:  process.env.PKEY2,
        balance: '1000000000000000000000000',
      }],
      allowUnlimitedContractSize: true
    },

    // hardhat: {
    //   forking: {
    //     //url: process.env.URL4,// sepolia
    //     url: process.env.URL5,// arbitrum
    //     blockNumber: 212810911,
    //   },
    //   // accounts: [ {
    //   //   privateKey:  process.env.PKEY2,
    //   //   balance: '1000000000000000000000000',
    //   // }],
    //   allowUnlimitedContractSize: true
    // },
  },

};

export default config;

