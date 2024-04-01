
// require("@openzeppelin/hardhat-upgrades");
// require("@nomicfoundation/hardhat-chai-matchers")
// require("@onmychain/hardhat-uniswap-v2-deploy-plugin");
// require("dotenv").config();
// //require("hardhat-gas-reporter");

import "@openzeppelin/hardhat-upgrades";
import "@nomicfoundation/hardhat-chai-matchers";
import "@onmychain/hardhat-uniswap-v2-deploy-plugin";
import '@typechain/hardhat'
import 'dotenv/config';
import { HardhatUserConfig } from "hardhat/config";







/** @type import('hardhat/config').HardhatUserConfig */
//module.exports = {
const config: HardhatUserConfig = {
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
        },
      },
      {
        version: "0.8.0",
      },
    ],
    
  },
  defaultNetwork: "hardhat",
  allowUnlimitedContractSize: true,
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
        //url: process.env.URL4,// sepolia
        url: process.env.URL5,// arbitrum
      },
      // accounts: [ {
      //   privateKey:  process.env.PKEY2,
      //   balance: '1000000000000000000000000',
      // }],
      allowUnlimitedContractSize: true
    },
  },
};

export default config;

