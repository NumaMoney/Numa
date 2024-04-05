// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INumaVault {

    
    function getDebt() external view returns (uint);
    //function setDebt(uint newDebt) external;
    function repay(uint amount) external;
    function borrow(uint amount) external;
    function getEthBalance() external view returns (uint256);
        
    function GetMaxBorrow() external view returns (uint256);
    function getSellNumaSimulateExtract(uint256 _amount) external view returns (uint256);
    function getBuyNumaSimulateExtract(uint256 _amount) external view returns (uint256);
}
