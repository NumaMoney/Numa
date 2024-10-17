// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/console2.sol";
import {Setup} from "./utils/SetupDeployNuma_Arbitrum.sol";
import "../lending/ExponentialNoError.sol";
import "../interfaces/IVaultManager.sol";

contract VaultTest is Setup, ExponentialNoError {

    function setUp() public virtual override {
        console2.log("VAULT TEST");
        super.setUp();
        // send some rEth to userA
        vm.stopPrank();
        vm.prank(deployer);
        rEth.transfer(userA, 1000 ether);
    }
    function test_GetPriceEmptyVault() public
    {
        // will test withdrawToken too
        uint bal = rEth.balanceOf(address(vault));
        uint balDeployer = rEth.balanceOf(deployer);
        assertGt (bal,0);
        vm.prank(deployer);
        vault.withdrawToken(address(rEth),bal,deployer);
      
        assertEq (rEth.balanceOf(address(vault)),0);
        assertEq (rEth.balanceOf(deployer) - balDeployer,bal);

    //     await expect(
    //       Vault1.getBuyNumaSimulateExtract(ethers.parseEther("2"))
    //     ).to.be.reverted;
    //     await expect(
    //       Vault1.getSellNumaSimulateExtract(ethers.parseEther("1000"))
    //     ).to.be.reverted;
    //   });
    }

    
}
