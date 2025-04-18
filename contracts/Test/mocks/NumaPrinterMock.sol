// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../NumaProtocol/NumaPrinter.sol";

/// @title NumaPrinter
/// @notice Responsible for minting/burning Numa for nuAsset
/// @dev
contract NumaPrinterMock is NumaPrinter {
    constructor(
        address _numaAddress,
        address _numaMinterAddress,
        address _numaPool,
        address _tokenToEthConverter,
        INumaOracle _oracle,
        address _vaultManagerAddress
    )
        NumaPrinter(
            _numaAddress,
            _numaMinterAddress,
            _numaPool,
            _tokenToEthConverter,
            _oracle,
            _vaultManagerAddress
        )
    {}
}
