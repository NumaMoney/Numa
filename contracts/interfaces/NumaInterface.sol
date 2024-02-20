// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface NUMAInterface {
    function SetFee(uint _newFeeBips) external;
    function SetFeeTriggerer(address _dexAddress, bool _isFee) external;
    function SetWlSpender(address _address, bool _isWl) external;
}
