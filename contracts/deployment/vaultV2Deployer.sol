// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;
import "../interfaces/INuma.sol";

import "./utils.sol";

import {nuAssetManager} from "../nuAssets/nuAssetManager.sol";
import {NumaMinter} from "../NumaProtocol/NumaMinter.sol";
import {VaultOracleSingle} from "../NumaProtocol/VaultOracleSingle.sol";
import {VaultManager} from "../NumaProtocol/VaultManager.sol";
import {NumaVault} from "../NumaProtocol/NumaVault.sol";
import {VaultMockOracle} from "../Test/mocks/VaultMockOracle.sol";

// deployer should be numa admin
contract vaultV2Deployer is deployUtils {
    address vaultFeeReceiver;
    address vaultRwdReceiver;
    uint128 lstHeartbeat;

    // TODO: constructor
    //
    INuma numa;
    address vaultOldAddress = 0x8Fe15Da7485830f26c37Da8b3c233773EB0623D2;
    address vaultOracleAddress = 0x8Fe15Da7485830f26c37Da8b3c233773EB0623D2;
    address lstAddress;
    address pricefeed;
    address uptimefeed;

    // out
    nuAssetManager public nuAssetMgr;
    NumaMinter public numaMinter;
    VaultOracleSingle public vaultOracle;
    VaultManager public vaultManager;
    NumaVault public vault;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(
        address _vaultFeeReceiver,
        address _vaultRwdReceiver,
        uint128 _lstHeartbeat,
        address _numaAddress,
        address _lstAddress,
        address _pricefeedAddress,
        address _uptimeAddress

    ) {
        vaultFeeReceiver = _vaultFeeReceiver;
        vaultRwdReceiver = _vaultRwdReceiver;
        lstHeartbeat = _lstHeartbeat;
    }
    function deploy_NumaV2() public {



        VaultMockOracle vaultOracleDeploy = new VaultMockOracle(lstAddress);
        deployUtils.deployVaultParameters memory parameters = deployUtils.deployVaultParameters(
            lstHeartbeat,
            uptimefeed,
            pricefeed,
            vaultFeeReceiver,
            vaultRwdReceiver,
            numa,
             0,
            0,
            address(0),
            address(0),
            address(vaultOracleDeploy),
            lstAddress
        );

        (nuAssetMgr,numaMinter,vaultManager,vaultOracle,vault) = setupVaultAndAssetManager(parameters);

        numa.grantRole(MINTER_ROLE, address(numaMinter));

     }

    // function migrate_NumaV1V2(address _vaultOldAddress) public 
    // {
    //     VaultMockOracle vaultOracleDeploy = new VaultMockOracle();
    //     deployVaultParameters memory parameters = deployVaultParameters(
    //         lstHeartbeat,
    //         uptimefeed,
    //         pricefeed,
    //         vaultFeeReceiver,
    //         vaultRwdReceiver,
    //         numa,
    //          0,
    //         0,
    //         address(0),
    //         address(0),
    //         address(vaultOracleDeploy),
    //         lstAddress
    //     );

    //     (nuAssetMgr,numaMinter,vaultManager,vaultOracle,vault) = setupVaultAndAssetManager(parameters);

    //     numa.grantRole(MINTER_ROLE, address(numaMinter));

    //     // migrate rEth, match price
    //     // NumaVaultOld vaultOld = NumaVaultOld(_vaultOldAddress);

    //     // vaultOld.withdrawToken(address(rEth),rEth.balanceOf(_vaultOldAddress),address(vault));
       
      
    //     // vaultManager.setSellFee((uint(vaultOld.sell_fee()) * 1 ether)/1000);
    //     // vaultManager.setBuyFee((uint(vaultOld.buy_fee()) * 1 ether)/1000);
    //     // // first we need to match numa supply
    //     // uint numaSupplyOld = vaultManagerOld.getNumaSupply();
    //     // uint numaSupplyNew = vaultManager.getNumaSupply();
       
    //     // uint diff = numaSupplyNew - numaSupplyOld -vaultManagerOld.constantRemovedSupply();
      
    //     // // keep same period
    //     // uint newPeriod = vaultManagerOld.decayPeriod() - (block.timestamp - vaultManagerOld.startTime());
    //     // vaultManager.setDecayValues(
    //     // diff/2,
    //     // newPeriod,
    //     // diff/2,
    //     // newPeriod,
    //     // vaultManagerOld.constantRemovedSupply()// same constant
    //     // );
    //     // vaultManager.startDecay();
    //     // // unpause
    //     // vault.unpause();
    // }

    function migrate_NumaV2V2() public {
    }

}
