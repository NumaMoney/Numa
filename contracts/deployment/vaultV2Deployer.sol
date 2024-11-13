// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;
import "../interfaces/INuma.sol";

import "./utils.sol";

// deployer should be numa admin
contract vaultV2Deployer is deployUtils {
    address vaultFeeReceiver;
    address vaultRwdReceiver;
    uint lstHeartbeat;

    // TODO: constructor
    //
    INuma numa;

    constructor(
        address _vaultFeeReceiver,
        address _vaultRwdReceiver,
        uint _lstHeartbeat
    ) {
        vaultFeeReceiver = _vaultFeeReceiver;
        vaultRwdReceiver = _vaultRwdReceiver;
        lstHeartbeat = _lstHeartbeat;
    }
    function deploy_NumaV2() public {
        // TODO: factorize code with tests
        // (nuAssetMgr,numaMinter,vaultManager,vaultOracle,vault) = setupVaultAndAssetManager(
        //     lstHeartbeat,
        //     vaultFeeReceiver,
        //     vaultRwdReceiver,
        //     numa,
        //     0,
        //     0,
        //     address(0),
        //     address(0)
        // );
        // _numa.grantRole(MINTER_ROLE, address(minter));
        // ***************************************************
        // // transfer rETh
        // vm.startPrank(VAULT_ADMIN);
        // vaultOld.withdrawToken(address(rEth),rEth.balanceOf(address(vaultOld)),address(vault));
        // vm.stopPrank();
        // rEth.approve(address(vaultOld),1000 ether);
        // vm.expectRevert();
        // uint buyAmount = vaultOld.buy(10 ether,0,deployer);
        // vm.expectRevert();
        // buyAmount = vault.buy(10 ether,0,deployer);
        // // unpause
        // vm.startPrank(deployer);
        // // set buy/sell fees to match old price
        // console2.log(vaultOld.sell_fee());
        // console2.log((uint(vaultOld.sell_fee()) * 1 ether)/1000);
        // vaultManager.setSellFee((uint(vaultOld.sell_fee()) * 1 ether)/1000);
        // vaultManager.setBuyFee((uint(vaultOld.buy_fee()) * 1 ether)/1000);
        // // first we need to match numa supply
        // uint numaSupplyOld = vaultManagerOld.getNumaSupply();
        // uint numaSupplyNew = vaultManager.getNumaSupply();
        // console2.log(numaSupplyNew);
        // uint diff = numaSupplyNew - numaSupplyOld -vaultManagerOld.constantRemovedSupply();
        // // 29/10 diff in supply: 500 000 constant + 600 000 currently decaying
        // // will put the decay half in LP, half in other --> 300 000
        // // keep same period
        // uint newPeriod = vaultManagerOld.decayPeriod() - (block.timestamp - vaultManagerOld.startTime());
        // vaultManager.setDecayValues(
        // diff/2,
        // newPeriod,
        // diff/2,
        // newPeriod,
        // vaultManagerOld.constantRemovedSupply()// same constant
        // );
        // vaultManager.startDecay();
        // // unpause
        // vault.unpause();
    }
}
