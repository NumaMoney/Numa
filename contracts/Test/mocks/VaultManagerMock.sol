// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../NumaProtocol/VaultManager.sol";

contract VaultManagerMock is VaultManager {
    constructor(
        address _numaAddress,
        address _nuAssetManagerAddress
    ) VaultManager(_numaAddress, _nuAssetManagerAddress) {}

    function getSynthScaling()
        public
        view
        override
        returns (
            uint,
            uint,
            uint,
            uint // virtual for test&overrides
        )
    {
        return (250, 250, 1000, 0);
    }
}
