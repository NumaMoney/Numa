// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import "../../contracts/interfaces/INuma.sol";

import "../../contracts/deployment/utils.sol";
import "@openzeppelin/contracts_5.0.2/token/ERC20/ERC20.sol";
import {nuAssetManager} from "../../contracts/nuAssets/nuAssetManager.sol";
import {NumaMinter} from "../../contracts/NumaProtocol/NumaMinter.sol";
import {VaultOracleSingle} from "../../contracts/NumaProtocol/VaultOracleSingle.sol";
import {VaultManager} from "../../contracts/NumaProtocol/VaultManager.sol";
import {NumaVault} from "../../contracts/NumaProtocol/NumaVault.sol";


import {NumaComptroller} from "../../contracts/lending/NumaComptroller.sol";
import {Unitroller} from "../../contracts/lending/Unitroller.sol";
import {NumaPriceOracleNew} from "../../contracts/lending/NumaPriceOracleNew.sol";

import {JumpRateModelV4} from "../../contracts/lending/JumpRateModelV4.sol";

import {JumpRateModelVariable} from "../../contracts/lending/JumpRateModelVariable.sol";

import {CNumaLst} from "../../contracts/lending/CNumaLst.sol";

import {CNumaToken} from "../../contracts/lending/CNumaToken.sol";

import {NumaPrinter} from "../../contracts/NumaProtocol/NumaPrinter.sol";
import {NumaOracle} from "../../contracts/NumaProtocol/NumaOracle.sol";
import {INumaOracle} from "../../contracts/interfaces/INumaOracle.sol";
import {USDCToEthConverter} from "../../contracts/NumaProtocol/USDCToEthConverter.sol";



import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";



contract TransferOwnership is Script {


   


    // out
    NumaComptroller public comptroller;
    NumaPriceOracleNew public numaPriceOracle; 
    JumpRateModelV4 public rateModelV4;
    JumpRateModelVariable public rateModel;
    CNumaLst public cReth;
    CNumaToken public cNuma;



    function run() external {


        // current deployment config
        string memory filename = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addresses_", vm.toString(block.chainid), ".json")
        );

        string memory deployedData = vm.readFile(filename);//"./scripts/DeploymentFoundry/deployed_addresses.json");
        

        // 1st deploy contracts
        address vault_address = vm.parseJsonAddress(deployedData, ".vault");
        address vaultManager_address = vm.parseJsonAddress(deployedData, ".vaultManager");
        address nuAssetManager_address = vm.parseJsonAddress(deployedData, ".nuAssetManager");
        address numaMinter_address = vm.parseJsonAddress(deployedData, ".numaMinter");
        address vaultOracle_address = vm.parseJsonAddress(deployedData, ".vaultOracle");

        // 2nd deploy contracts
        string memory filename2 = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addressesLending_", vm.toString(block.chainid), ".json")
        );

        string memory deployedData2 = vm.readFile(filename2);//"./scripts/DeploymentFoundry/deployed_addresses.json");
        address comptroller_address = vm.parseJsonAddress(deployedData2, ".Comptroller");
        address priceOracle_address = vm.parseJsonAddress(deployedData2, ".PriceOracle");
        address rateModelV4_address = vm.parseJsonAddress(deployedData2, ".rateModelV4");
        address rateModel_address = vm.parseJsonAddress(deployedData2, ".rateModel");
        address cnuma_address = vm.parseJsonAddress(deployedData2, ".cNuma");
        address creth_address = vm.parseJsonAddress(deployedData2, ".cReth");

        // 3rd deploy contracts
        string memory filename3 = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addressesPrinter_", vm.toString(block.chainid), ".json")
        );

        string memory deployedData3 = vm.readFile(filename3);//"./scripts/DeploymentFoundry/deployed_addresses.json");
        address numaOracle_address = vm.parseJsonAddress(deployedData3, ".NumaOracle");
        address uSDCToEthConverter_address = vm.parseJsonAddress(deployedData3, ".USDCToEthConverter");
        address printer_address = vm.parseJsonAddress(deployedData3, ".NumaPrinter");

        // TODO: confirm address
        address msig_address = 0xFC4B72FD6309d2E68B595c56EAcb256D2fE9b881;

        // uint256 deployerPrivateKey = vm.envUint("PKEYFoundry");
        // vm.startBroadcast(deployerPrivateKey);
        vm.startBroadcast();
        address deployer = msg.sender;
        console2.log("deployer",deployer);

        NumaVault vault = NumaVault(vault_address);
        VaultManager vaultManager = VaultManager(vaultManager_address);
        nuAssetManager2 nuAssetManager = nuAssetManager2(nuAssetManager_address);
        NumaMinter numaMinter = NumaMinter(numaMinter_address);
        VaultOracleSingle vaultOracle = VaultOracleSingle(vaultOracle_address);
        //
        vault.transferOwnership(msig_address);
        vaultManager.transferOwnership(msig_address);
        nuAssetManager.transferOwnership(msig_address);
        numaMinter.transferOwnership(msig_address);
        //vaultOracle.transferOwnership(msig_address);

        // LENDING

        NumaComptroller comptroller = NumaComptroller(comptroller_address);
        NumaPriceOracleNew numaPriceOracle = NumaPriceOracleNew(priceOracle_address); 
        JumpRateModelV4 rateModelV4 = JumpRateModelV4(rateModelV4_address);
        JumpRateModelVariable rateModel = JumpRateModelVariable(rateModel_address);
        CNumaLst cReth = CNumaLst(creth_address);
        CNumaToken cNuma = CNumaToken(cnuma_address);
        // 
        //Unitroller u = Unitroller(payable(comptroller_address))._setPendingAdmin(payable(msig_address));
         
        // Unitroller comptroller2 = Unitroller(payable(comptroller_address));
        // comptroller2._setPendingAdmin(payable(msig_address));
        // cReth._setPendingAdmin(payable(msig_address));
        // cNuma._setPendingAdmin(payable(msig_address));
        // rateModelV4.transferOwnership(msig_address);
        // rateModel.transferOwnership(msig_address);


        NumaPrinter printer = NumaPrinter(printer_address);
        USDCToEthConverter uSDCToEthConverter = USDCToEthConverter(uSDCToEthConverter_address);
        NumaOracle numaOracle = NumaOracle(numaOracle_address);

        printer.transferOwnership(msig_address);
        numaOracle.transferOwnership(msig_address);


        vm.stopBroadcast();
        
        
    }
    function toAsciiString(address addr) internal pure returns (string memory) {
        bytes memory s = new bytes(42);
        s[0] = "0";
        s[1] = "x";
        for (uint i = 0; i < 20; i++) {
            uint8 b = uint8(uint160(addr) / (2**(8 * (19 - i))));
            s[2 + i * 2] = _char(b / 16);
            s[3 + i * 2] = _char(b % 16);
        }
        return string(s);
    }

    
    function _char(uint8 b) private pure returns (bytes1) {
        return b < 10 ? bytes1(b + 48) : bytes1(b + 87);
    }
}