// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;


import {nuAssetManager2} from "../nuAssets/nuAssetManager2.sol";
import {NumaMinter} from "../NumaProtocol/NumaMinter.sol";
import {VaultOracleSingle} from "../NumaProtocol/VaultOracleSingle.sol";
import {VaultMockOracle} from "../Test/mocks/VaultMockOracle.sol";
import {VaultManager} from "../NumaProtocol/VaultManager.sol";
import {NumaVault} from "../NumaProtocol/NumaVault.sol";

import "./vaultV1V2Deployer_1.sol";
import "./vaultV1V2Deployer_2.sol";

struct vaultV1V2DeploymentReport {
    nuAssetManager2 nuAssetMgr;
    NumaMinter numaMinter;
    VaultOracleSingle vaultOracle;
    VaultManager vaultManager;
    NumaVault vault;
}

// TODO: renaming all 

// TODO: ownership

// TODO: deployment of deployers


contract vaultV1V2Deployer {

    vaultV1V2Deployer_1 public deployer1;
    vaultV1V2Deployer_2 public deployer2;

    // TODO lending and printer here


    // report
    vaultV1V2DeploymentReport public report;

    constructor(address _vaultV1V2Deployer_1, address _vaultV1V2Deployer_2) {
        deployer1 = vaultV1V2Deployer_1(_vaultV1V2Deployer_1);
        deployer2 = vaultV1V2Deployer_2(_vaultV1V2Deployer_2);
    }

    function deploy1() external  {
        bool istestnet = true;
        deployer1.migrate_NumaV1V2(istestnet);
        report.nuAssetMgr = deployer1.nuAssetMgr;
        report.numaMinter = deployer1.numaMinter;
        report.vaultOracle = deployer1.vaultOracle;
        
    }

    function deploy2() external returns (address) {
         deployer2.migrate_NumaV1V2();
         report.vaultManager = deployer2.vaultManager;
    }
}

// Example deployer contract
contract DeployerA {
    function deploy() external returns (address) {
        ContractA newContract = new ContractA();
        return address(newContract);
    }
}

// Another deployer contract
contract DeployerB {
    function deploy() external returns (address) {
        ContractB newContract = new ContractB();
        return address(newContract);
    }
}