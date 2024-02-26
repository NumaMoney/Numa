// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;


import "hardhat/console.sol";

contract MockRwdReceiverContract_Deposit {

    uint public test = 1;
    function DepositFromVault(uint _amount) external payable
    {
        console.log("desposit ok");
        test = _amount;

    }

    fallback() external payable {
        console.log("fallback called");
    }
}
