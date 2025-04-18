// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IRewardFeeReceiver {
    function DepositFromVault(uint256 _amount) external;
}
