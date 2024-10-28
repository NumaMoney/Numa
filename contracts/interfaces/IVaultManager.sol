// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IVaultManager {
    // Enum representing shipping status
    enum PriceType {
        NoFeePrice,
        BuyPrice,
        SellPrice
    }

    function getBuyFee() external view returns (uint);
    function getSellFeeOriginal() external view returns (uint);
    function getSellFeeScaling() external view returns (uint, uint, uint);
    function getSellFeeScalingUpdate() external returns (uint);
    function getTotalBalanceEth() external view returns (uint256);
    function getTotalBalanceEthNoDebt() external view returns (uint256);

    function numaToEth(
        uint _amount,
        PriceType _t
    ) external view returns (uint256);

    function ethToNuma(
        uint _amount,
        PriceType _t
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
    function lockSupplyFlashloan(bool _lock) external;
    function getGlobalCF() external view returns (uint);
    function updateVaults() external;
    function updateBuyFeePID(uint _numaAmount, bool _isVaultBuy) external;
    function updateDebasings() external returns (uint, uint, uint);

    function getSynthScaling() external view returns (uint, uint, uint, uint);
    function getWarningCF() external view returns (uint);
}
