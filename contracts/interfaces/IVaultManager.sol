// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IVaultManager {

    function getBuyFee() external view returns (uint16);
    function getSellFeeOriginal() external view returns (uint16);
    function getSellFeeScaling() external view returns (uint16,uint);
    function getSellFeeScalingUpdate() external returns (uint16,uint);
    function getTotalBalanceEth() external view returns (uint256);
    function getTotalBalanceEthNoDebt() external view returns (uint256);

    function GetNumaPriceEth(
        uint _amount
    ) external view returns (uint256);


    function GetNumaPerEth(
        uint _amount
    ) external view returns (uint256);


    function tokenToNuma(
        uint _inputAmount,
        uint _refValueWei,
        uint _decimals,
        uint _currentDebase
    ) external view returns (uint256);

    function numaToToken(
        uint _inputAmount,
        uint _refValueWei,
        uint _decimals,
        uint _currentDebase
    ) external view returns (uint256);




    function getTotalSynthValueEth() external view returns (uint256);
    function isVault(address _addy) external view returns (bool);
    function lockSupplyFlashloan(bool _lock) external ;
    function getGlobalCF() external view returns (uint);
    function accrueInterests() external;

    //function getSynthScalingUpdate() external returns (uint,uint,uint);
    function updateAll() external returns (uint,uint16);


    function getSynthScaling() external view returns (uint,uint,uint);
    function getWarningCF() external view returns (uint);
  
}
