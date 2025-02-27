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


    uint256 blocksPerYear;
    uint256 baseRatePerYear ;
    uint256 multiplierPerYear;
    uint256 jumpMultiplierPerYear;
    uint256 kink;
    uint256 maxUtilizationRatePerYear;
    uint256 zeroUtilizationRate;
    uint256 minFullUtilizationRate;
    uint256 maxFullUtilizationRate;
    uint256 vertexUtilization;
    uint256 vertexRatePercentOfDelta;
    uint256 minUtil;
    uint256 maxUtil;
    uint256 rateHalfLife;
    uint256 maxBorrowVault;
    uint256 numaCollateralFactor;
    uint256 rEthCollateralFactor;
    uint256 closeFactor;
    uint256 liquidationIncentive;
    uint256 maxLiquidationProfit;
    uint256 borrowRateMaxMantissaARBI;
    uint ltvMinBadDebtLiquidations;
    uint ltvMinPartialLiquidations;


    // out
    NumaComptroller public comptroller;
    NumaPriceOracleNew public numaPriceOracle; 
    JumpRateModelV4 public rateModelV4;
    JumpRateModelVariable public rateModel;
    CNumaLst public cReth;
    CNumaToken public cNuma;



    function run() external {


        // deployment parameter
        string memory configData = vm.readFile("./scripts/DeploymentFoundry/config.json");
        string memory path = string(abi.encodePacked(".", vm.toString(block.chainid)));

        address numa_address = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".numa_address")));
        address reth_address = vm.parseJsonAddress(configData, string(abi.encodePacked(path, ".lstAddress")));

        // lending parameters
        blocksPerYear = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".blocksPerYear")));
        baseRatePerYear = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".baseRatePerYear")));
        multiplierPerYear = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".multiplierPerYear")));
        jumpMultiplierPerYear = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".jumpMultiplierPerYear")));
        kink = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".kink")));
        maxUtilizationRatePerYear = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".maxUtilizationRatePerYear")));
        zeroUtilizationRate = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".zeroUtilizationRate")));
        minFullUtilizationRate = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".minFullUtilizationRate")));
        maxFullUtilizationRate = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".maxFullUtilizationRate")));
        vertexUtilization = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".vertexUtilization")));
        vertexRatePercentOfDelta = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".vertexRatePercentOfDelta")));
        minUtil = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".minUtil")));
        maxUtil = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".maxUtil")));
        rateHalfLife = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".rateHalfLife")));
        maxBorrowVault = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".maxBorrowVault")));
        numaCollateralFactor = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".numaCollateralFactor")));
        rEthCollateralFactor = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".rEthCollateralFactor")));
        closeFactor = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".closeFactor")));
        liquidationIncentive = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".liquidationIncentive")));
        maxLiquidationProfit = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".maxLiquidationProfit")));
        borrowRateMaxMantissaARBI = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".borrowRateMaxMantissaARBI")));
        ltvMinBadDebtLiquidations = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".ltvMinBadDebtLiquidations")));
        ltvMinPartialLiquidations = vm.parseJsonUint(configData, string(abi.encodePacked(path, ".ltvMinPartialLiquidations")));




        // current deployment config
        string memory filename = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addresses_", vm.toString(block.chainid), ".json")
        );

        string memory deployedData = vm.readFile(filename);//"./scripts/DeploymentFoundry/deployed_addresses.json");
        
        address vault_address = vm.parseJsonAddress(deployedData, ".vault");




        uint256 deployerPrivateKey = vm.envUint("PKEYFoundry");
        vm.startBroadcast(deployerPrivateKey);

        address deployer = msg.sender;
        console2.log("deployer",deployer);

        NumaVault vault = NumaVault(vault_address);
        ERC20 numa = ERC20(numa_address);
        ERC20 rEth = ERC20(reth_address);
        // COMPTROLLER
        comptroller = new NumaComptroller();

        // PRICE ORACLE
        numaPriceOracle = new NumaPriceOracleNew();
        //numaPriceOracle.setVault(address(vault));
        comptroller._setPriceOracle((numaPriceOracle));
        // INTEREST RATE MODEL
        uint maxUtilizationRatePerBlock = maxUtilizationRatePerYear /
            blocksPerYear;

        // standard jump rate model V4
        rateModelV4 = new JumpRateModelV4(
            blocksPerYear,
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink,
            deployer,
            "numaJumpRateModel"
        );

        uint _zeroUtilizationRatePerBlock = (zeroUtilizationRate /
            blocksPerYear);
        uint _minFullUtilizationRatePerBlock = (minFullUtilizationRate /
            blocksPerYear);
        uint _maxFullUtilizationRatePerBlock = (maxFullUtilizationRate /
            blocksPerYear);

        rateModel = new JumpRateModelVariable(
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

        // CTOKENS
        cNuma = new CNumaToken(
            address(numa),
            comptroller,
            rateModelV4,
            200000000000000000000000000,
            "numa CToken",
            "cNuma",
            8,
            maxUtilizationRatePerBlock,
            payable(deployer),
            address(vault)
        );
        cReth = new CNumaLst(
            address(rEth),
            comptroller,
            rateModel,
            200000000000000000000000000,
            "rEth CToken",
            "crEth",
            8,
            maxUtilizationRatePerBlock,
            payable(deployer),
            address(vault)
        );

        // arbitrum values
        // add a x10 for reth because due to variable interest rate model we can go high
        cReth._setBorrowRateMaxMantissa(borrowRateMaxMantissaARBI*10);
        cNuma._setBorrowRateMaxMantissa(borrowRateMaxMantissaARBI);

        cReth._setReserveFactor(0.5 ether);


        vault.setCTokens(address(cNuma), address(cReth));

        // add markets (has to be done before _setcollateralFactor)
        comptroller._supportMarket((cNuma));
        comptroller._supportMarket((cReth));

        // collateral factors
        comptroller._setCollateralFactor((cNuma), numaCollateralFactor);
        comptroller._setCollateralFactor((cReth), rEthCollateralFactor);



        // 100% liquidation close factor
        comptroller._setCloseFactor(closeFactor);
        comptroller._setLiquidationIncentive(liquidationIncentive);
        //comptroller._setLtvThresholds(0.98 ether,1.1 ether);
        comptroller._setLtvThresholds(ltvMinBadDebtLiquidations,ltvMinPartialLiquidations);





        // pause everything
        comptroller._setBorrowPaused(cNuma,true);
        comptroller._setBorrowPaused(cReth,true);
        comptroller._setMintPaused(cNuma,true);
        comptroller._setMintPaused(cReth,true);





        // strategies
        // deploy strategy
        // NumaLeverageVaultSwap strat0 = new NumaLeverageVaultSwap(
        //     address(_vault)
        // );
        // cReth.addStrategy(address(strat0));
        // cNuma.addStrategy(address(strat0));

        //
        // Write the JSON to the specified path using writeJson
        string memory json = string(abi.encodePacked(
            '{"Comptroller": "', toAsciiString(address(comptroller)), '", ',
            '"PriceOracle": "', toAsciiString( address(numaPriceOracle)), '",',
            '"rateModelV4": "', toAsciiString( address(rateModelV4)), '",',
            '"rateModel": "', toAsciiString( address(rateModel)), '",',
            '"cNuma": "', toAsciiString( address(cNuma)), '",',
            '"cReth": "', toAsciiString( address(cReth)), '"}'
        ));

        // Create the filename with the chain ID
        string memory filename2 = string(
            abi.encodePacked("./scripts/DeploymentFoundry/deployed_addressesLending_", vm.toString(block.chainid), ".json")
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