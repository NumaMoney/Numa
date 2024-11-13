// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INumaVault {
    function buy(uint, uint, address) external returns (uint);
    function sell(uint, uint, address) external returns (uint);
    function getDebt() external view returns (uint);
    function repay(uint amount) external;
    function borrow(uint amount) external;
    function getEthBalance() external view returns (uint256);
    function getEthBalanceNoDebt() external view returns (uint256);
    function getMaxBorrow() external view returns (uint256);
    function numaToLst(uint256 _amount) external view returns (uint256);
    function lstToNuma(uint256 _amount) external view returns (uint256);
    function repayLeverage(bool _closePosition) external;
    function borrowLeverage(uint _amount, bool _closePosition) external;

    function updateVault() external;
    function getcNumaAddress() external view returns (address);
    function getcLstAddress() external view returns (address);
}
