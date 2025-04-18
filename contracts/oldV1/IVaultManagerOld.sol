// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IVaultManagerOld {
    function getTotalBalanceEth() external view returns (uint256);

    function tokenToNuma(
        uint _inputAmount,
        uint _refValueWei,
        uint _decimals
    ) external view returns (uint256);

    function numaToToken(
        uint _inputAmount,
        uint _refValueWei,
        uint _decimals
    ) external view returns (uint256);

    function isVault(address _addy) external view returns (bool);
}
