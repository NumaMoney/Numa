// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;

import "forge-std/console.sol";
import "forge-std/console2.sol";
import "forge-std/StdCheats.sol";
//
import "@openzeppelin/contracts_5.0.2/token/ERC20/ERC20.sol";
//
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
//
import {INonfungiblePositionManager} from "../uniV3Interfaces/INonfungiblePositionManager.sol";
import "../uniV3Interfaces/ISwapRouter.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "./TickHelper.sol";
import "./Math.sol";
import {encodePriceSqrt} from "./Math.sol";
//
import {ExtendedTest} from "./ExtendedTest.sol";
import {ConstantsTest} from "./ConstantsTest.sol";
//

import {nuAssetManager} from "../../nuAssets/nuAssetManager.sol";
import {NumaMinter} from "../../NumaProtocol/NumaMinter.sol";
import {VaultOracleSingle} from "../../NumaProtocol/VaultOracleSingle.sol";
import {VaultManager} from "../../NumaProtocol/VaultManager.sol";
import {NumaVault} from "../../NumaProtocol/NumaVault.sol";
import {NuAsset2} from "../../nuAssets/nuAsset2.sol";
import {INumaOracle} from "../../interfaces/INumaOracle.sol";
import {NumaOracle} from "../../NumaProtocol/NumaOracle.sol";
import {NumaPrinter} from "../../NumaProtocol/NumaPrinter.sol";
import "../../interfaces/INumaTokenToEthConverter.sol";
import "../../NumaProtocol/USDCToEthConverter.sol";
import {NumaLeverageVaultSwap} from "../../lending/NumaLeverageVaultSwap.sol";
import {NumaComptroller} from "../../lending/NumaComptroller.sol";
import "../../lending/JumpRateModelVariable.sol";
import "../../lending/CNumaLst.sol";
import "../../lending/CNumaToken.sol";
import "../../lending/NumaPriceOracleNew.sol";
import "../../lending/ExponentialNoError.sol";
import "../../lending/ComptrollerStorage.sol";

// V1 protocol
import "../../oldV1/NumaVaultOld.sol";
import "../../oldV1/VaultManagerOld.sol";
import "../../oldV1/nuAssetManagerOld.sol";

import "./SetupBase.sol";

// forge test --fork-url <your_rpc_url>
contract Setup is SetupBase {
    // Contract instances that we will use repeatedly.
    // Tokens
    //NUMA numa;

    nuAssetManagerOld nuAssetMgrOld;
    VaultManagerOld vaultManagerOld;
    NumaVaultOld vaultOld;

    function setUp() public virtual {
        numa_admin = NUMA_ADMIN;
        // setup fork
        string memory ARBI_RPC_URL = vm.envString("URLARBI");
        uint256 arbitrumFork = vm.createFork(ARBI_RPC_URL);

        vm.selectFork(arbitrumFork);
        vm.rollFork(269602000);

        // prank deployer
        vm.startPrank(deployer);

        _setUpTokens();
        deal({token: address(rEth), to: userA, give: 100000 ether});
        deal({token: address(rEth), to: userB, give: 100000 ether});
        deal({token: address(rEth), to: userC, give: 100000 ether});
        _setupOldVaultAndAssetManager();
    }

    function _setUpTokens() internal override {
        SetupBase._setUpTokens();
        // Numa
        numa = INuma(NUMA_ADDRESS_ARBI); // admin, pauser, minter
    }

    function _setupOldVaultAndAssetManager() internal {
        // nuAssetManager
        nuAssetMgrOld = nuAssetManagerOld(NUMA_NUASSETMANAGERV1_ARBI);
        // vault manager
        vaultManagerOld = VaultManagerOld(NUMA_VAULTMANAGERV1_ARBI);
        // vault
        vaultOld = NumaVaultOld(NUMA_VAULTV1_ARBI);
    }
}
