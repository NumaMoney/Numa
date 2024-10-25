// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INumaVault {

    function getDebt() external view returns (uint);
    function repay(uint amount) external;
    function borrow(uint amount) external;
    function getEthBalance() external view returns (uint256);
    function getEthBalanceNoDebt() external view returns (uint256);
    function GetMaxBorrow() external view returns (uint256);
    function numaToLst(
        uint256 _amount
    ) external view returns (uint256);
    function lstToNuma(
        uint256 _amount
    ) external view returns (uint256);
    function repayLeverage(bool _closePosition) external;
    function borrowLeverage(uint _amount, bool _closePosition) external;

    function updateVault() external;
}
