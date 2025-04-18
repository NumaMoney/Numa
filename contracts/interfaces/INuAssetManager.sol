// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INuAssetManager {
    function getTotalSynthValueEth() external view returns (uint256);
}
