// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/console2.sol";
import {Setup} from "./utils/SetupDeployNuma_Arbitrum.sol";

contract LendingTest is Setup 
{
    function setUp() public virtual override {
        console2.log("LENDING TEST");
        super.setUp();
        // set reth vault balance so that 1 numa = 1 rEth
        deal({token:address(rEth),to:address(vault),give:numaSupply});

        // send some numa to userA
        vm.stopPrank();
        vm.prank(deployer);
        numa.transfer(userA,1000 ether);
    }
    function test_CheckSetup() public 
    {
       // test that numa price (without fees) is 1 reth
       uint numaPriceReth = vaultManager.numaToToken(
            1 ether,
            vault.last_lsttokenvalueWei(),
            vault.decimals(),
            1000
        );
       console2.log(numaPriceReth);
       assertEq(numaPriceReth,1 ether);
       // TODO
       // check collateral factor

       // check fees

       


    }

    function test_LeverageAndCloseProfit() public 
    {
        // user calls leverage x 10
        vm.startPrank(userA);
        address[] memory t = new address[](1);
        t[0] = address(cNuma);
        comptroller.enterMarkets(t);



       
        numa.approve(address(cReth),10 ether);
        cReth.leverage(10 ether,40 ether,cNuma);

        // check balances
        // cnuma position
        uint cNumaBal = cNuma.balanceOf(userA);
        console2.log(cNumaBal);

        uint exchangeRate = 1;
        assertEq(cNumaBal,100 ether*exchangeRate);

        // numa stored in cnuma contract
        uint numaBal = numa.balanceOf(address(cNuma));        
        assertEq(numaBal,100 ether);

        // borrow balance
        uint borrowrEThBalance = cReth.borrowBalanceStored(userA);

        console2.log(borrowrEThBalance);

        // vault borrow (should be the same)

        // numa price increase 10%
        uint newRethBalance = numaSupply + (10 * numaSupply)/100;
        deal({token:address(rEth),to:address(vault),give:newRethBalance});

        // check states

        // close position

        // check balances

        vm.stopPrank();
    }


   
}