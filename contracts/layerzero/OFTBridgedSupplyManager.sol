//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts_5.0.2/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IOFTBridgedSupplyManager.sol";

/// @title OFTBridgedSupplyManager
/// @notice manages bridged supply 
contract OFTBridgedSupplyManager is IOFTBridgedSupplyManager{

    //
    address public immutable oftAdapter;
    address public immutable numa;
    constructor(address _oftadapter,address _numa) 
    {
        oftAdapter = _oftadapter;
        numa = _numa;

    }
    function getBridgedSupply() public view returns (uint)
    {
        return IERC20(numa).balanceOf(oftAdapter);

    }

   
}
