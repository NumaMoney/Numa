// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import "../contracts/interfaces/INuma.sol";

import "../contracts/deployment/utils.sol";
import "@openzeppelin/contracts_5.0.2/token/ERC20/ERC20.sol";
import {nuAssetManager} from "../contracts/nuAssets/nuAssetManager.sol";
import {NumaMinter} from "../contracts/NumaProtocol/NumaMinter.sol";
import {VaultOracleSingle} from "../contracts/NumaProtocol/VaultOracleSingle.sol";
import {VaultManager} from "../contracts/NumaProtocol/VaultManager.sol";
import {NumaVault} from "../contracts/NumaProtocol/NumaVault.sol";


import {NumaComptroller} from "../contracts/lending/NumaComptroller.sol";

import {NumaPriceOracleNew} from "../contracts/lending/NumaPriceOracleNew.sol";

import {JumpRateModelV4} from "../contracts/lending/JumpRateModelV4.sol";

import {JumpRateModelVariable} from "../contracts/lending/JumpRateModelVariable.sol";

import {CNumaLst} from "../contracts/lending/CNumaLst.sol";

import {CNumaToken} from "../contracts/lending/CNumaToken.sol";



import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";


// forge verify-contract 0x732fF1c4D6825F859142E7f6D610c1183838d35C CNumaLst --watch --chain sepolia
// forge script --chain arbitrum .\scripts\DeployLending.sol:DeployLending --fork-url 'https://sepolia.infura.io/v3/916abfc599974040abfd299a6889c49d' -vv --verify --private-key PKEY --broadcast
// TODO
// - test on sepolia, check transactions
// - test on local arbitrum fork, make some tests
contract DeployLending is Script {




    // ARBITRUM
    // address constant VAULT_ADMIN = 0xFC4B72FD6309d2E68B595c56EAcb256D2fE9b881;
    // address constant NUMA_ADMIN = 0x7B224b19b2b26d1b329723712eC5f60C3f7877E3;

    // // input
    // address numa_address;
    // address reth_address;
    // address vault_address;
    // // parameters
    // uint blocksPerYear;
    // // jumprate model
    // uint  baseRatePerYear;
    // uint multiplierPerYear;
    // uint jumpMultiplierPerYear;
    // uint kink;
    // // frax model
    // uint maxUtilizationRatePerYear;// for fraxmodel
    // uint zeroUtilizationRate;
    // uint minFullUtilizationRate;
    // uint maxFullUtilizationRate;
    // uint vertexUtilization;
    // uint vertexRatePercentOfDelta;
    // uint minUtil;
    // uint maxUtil;
    // uint rateHalfLife;
    // uint maxBorrowVault;
    // uint numaCollateralFactor;
    // uint rEthCollateralFactor;
    // uint closeFactor = 1 ether;
    // uint liquidationIncentive = 1.02 ether;
    // uint maxLiquidationProfit;

    // SEPOLIA
    address constant VAULT_ADMIN = 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69;
    address constant NUMA_ADMIN = 0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69;



    // input
    address numa_address = 0xf478F8dEDebe67cC095693A9d6778dEb3fb67FFe;
    address reth_address = 0x1521c67fDFDb670fa21407ebDbBda5F41591646c;
    address vault_address = 0xf24a7F6ae5dA1BdBA8A24D7555Fc966f2f42f007;
    // parameters
    uint blocksPerYear = 2425846;
    // jumprate model
    uint  baseRatePerYear = 0.02 ether; // 2%
    uint multiplierPerYear = 0.01 ether; // 1%
    uint jumpMultiplierPerYear = 4 ether; //400%
    uint kink = 0.8 ether; //80%

    // frax model
    uint maxUtilizationRatePerYear = 1000000000000000000; //100%;
    uint zeroUtilizationRate = 0; //0%
    uint minFullUtilizationRate = 1000000000000000000; //100%
    uint maxFullUtilizationRate = 5000000000000000000; //500%

    uint rateHalfLife = 12 * 3600;


    uint vertexUtilization = 800000000000000000; // 80%;
    uint vertexRatePercentOfDelta = 0;
    uint minUtil = 400000000000000000;
    uint maxUtil = 600000000000000000;
    uint maxBorrowVault = 1000 ether;
    uint numaCollateralFactor = 0.95 ether;
    uint rEthCollateralFactor = 0.95 ether;
    uint closeFactor = 1 ether;
    uint liquidationIncentive = 1.02 ether;
    uint maxLiquidationProfit = 0.05 ether;// in reth

    // out
    NumaComptroller public comptroller;
    NumaPriceOracleNew public numaPriceOracle; 
    JumpRateModelV4 public rateModelV4;
    JumpRateModelVariable public rateModel;
    CNumaLst public cReth;
    CNumaToken public cNuma;




    bool useForkedArbi = false;

    //forge script --chain sepolia .\scripts\MigrateVaultV1V2.sol:MigrateV1V2 --rpc-url 'SEPOLIA_RPC' --broadcast -vv --verify

    // verify KO
    // pkey obligé de la mattre en paramètre si je ne brodcast pas... et sur la vraie url
    // si je broadcast, il ne faut pas la mettre en paramètre
    function run() external {

        uint256 deployerPrivateKey = vm.envUint("PKEYFoundry");
        console2.log("deployerPrivateKey",deployerPrivateKey);
        if (useForkedArbi)
        {
            vm.startPrank(VAULT_ADMIN);
        }
        else
        {
            vm.startBroadcast(deployerPrivateKey);
        }

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



        vault.setMaxBorrow(1000 ether);
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
        vault.setMaxLiquidationsProfit(maxLiquidationProfit);

        // strategies
        // deploy strategy
        // NumaLeverageVaultSwap strat0 = new NumaLeverageVaultSwap(
        //     address(_vault)
        // );
        // cReth.addStrategy(address(strat0));
        // cNuma.addStrategy(address(strat0));

        //



        if (useForkedArbi)
        {
            
        }
        else
        {
            vm.stopBroadcast();
        }
        
    }
}