// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INumaOracle {
    function getNbOfNumaNeeded(
        uint256 _amount,
        address _nuAsset,
        address _numaPool,
        address _converter,
        uint _numaPerEthVault
    ) external view returns (uint256);
    function getNbOfNumaFromAsset(
        uint256 _amount,
        address _nuAsset,
        address _numaPool,
        address _converter,
        uint    _ethToNumaMulAmountVault
    ) external view returns (uint256);
    function getNbOfNuAsset(
        uint256 _amount,
        address _nuAsset,
        address _numaPool,
        address _converter,
        uint    _EthPerNumaVault
    ) external view returns (uint256);
    function getNbOfAssetneeded(
        uint256 _amountNumaOut,
        address _nuAsset,
        address _numaPool,
        address _converter,
        uint _EthPerNumaVault
    ) external view returns (uint256);

    function getNbOfNuAssetFromNuAsset( uint256 _nuAssetAmountIn,
        address _nuAssetIn,
        address _nuAssetOut
    ) external view returns (uint256);

}
