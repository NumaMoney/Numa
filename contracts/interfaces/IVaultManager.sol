// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IVaultManager {

    function getBuyFee() external view returns (uint16);
    function getSellFee() external view returns (uint16);
    function getTotalBalanceEth() external view returns (uint256);
    function getTotalBalanceEthNoDebt() external view returns (uint256);
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




    function getTotalSynthValueEth() external view returns (uint256);
    function isVault(address _addy) external view returns (bool);
    function lockSupplyFlashloan(bool _lock) external ;
    function getGlobalCF() external view returns (uint);
    function accrueInterests() external;
  
}
