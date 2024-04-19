// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INumaVault {

    function buyFromCToken(uint _inputAmount,uint _minNumaAmount) external returns (uint);
    function getDebt() external view returns (uint);
    //function setDebt(uint newDebt) external;
    function repay(uint amount) external;
    function borrow(uint amount) external;
    function getEthBalance() external view returns (uint256);
        
    function GetMaxBorrow() external view returns (uint256);
    function getSellNumaSimulateExtract(uint256 _amount) external view returns (uint256);
    function getBuyNumaSimulateExtract(uint256 _amount) external view returns (uint256);
    function repayLeverage() external;
    function borrowLeverage(uint _amount) external;
    function getAmountIn(uint256 _amount) external view returns (uint256);
    //function getBuyNuma(uint256 _amount) external view returns (uint256);
}
