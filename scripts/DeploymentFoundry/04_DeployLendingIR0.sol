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

import {NumaPriceOracleNew} from "../../contracts/lending/NumaPriceOracleNew.sol";

import {JumpRateModelV4} from "../../contracts/lending/JumpRateModelV4.sol";

import {JumpRateModelVariable} from "../../contracts/lending/JumpRateModelVariable.sol";

import {CNumaLst} from "../../contracts/lending/CNumaLst.sol";

import {CNumaToken} from "../../contracts/lending/CNumaToken.sol";



import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";



contract DeployLending is Script {






    function run() external {



        vm.startBroadcast();
        address deployer = msg.sender;
        console2.log("deployer",deployer);



        uint zeroUtilizationRate = 0;
        uint minFullUtilizationRate = 0;
        uint maxFullUtilizationRate = 0;
        uint vertexUtilization = 1 ether;
        uint vertexRatePercentOfDelta = 0;
        uint minUtil = 0;
        uint maxUtil = 1 ether;
        uint rateHalfLife = 360 days;

        uint blocksPerYear = 126144000;

        uint _zeroUtilizationRatePerBlock = 0;
        uint _minFullUtilizationRatePerBlock = (minFullUtilizationRate /
            blocksPerYear);
        uint _maxFullUtilizationRatePerBlock = (maxFullUtilizationRate /
            blocksPerYear);

        JumpRateModelVariable rateModel = new JumpRateModelVariable(
            "numaRateModel",
            vertexUtilization,
            vertexRatePercentOfDelta,
            minUtil,
            maxUtil,
            _zeroUtilizationRatePerBlock,
            _minFullUtilizationRatePerBlock,
            _maxFullUtilizationRatePerBlock,
            rateHalfLife,
            deployer
        );

    

        //
        // Write the JSON to the specified path using writeJson
        string memory json = string(abi.encodePacked(
            '{"rateModel": "', toAsciiString( address(rateModel)),  '"}'
        ));

        // Create the filename with the chain ID
        string memory filename2 = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addressesLending2_", vm.toString(block.chainid), ".json")
        );

        //string memory path2 = "./scripts/DeploymentFoundry/deployed_addresses.json";
        vm.writeJson(json, filename2);

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