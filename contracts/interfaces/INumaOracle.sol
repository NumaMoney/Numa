// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface INumaOracle {
    enum PriceType {
        HighestPrice,
        LowestPrice
    }

    function nuAssetToEthRoundUp(
        address _nuAsset,
        uint256 _amount
    ) external view returns (uint256 EthValue);

    function nuAssetToEth(
        address _nuAsset,
        uint256 _amount
    ) external view returns (uint256 EthValue);
    function ethToNuAsset(
        address _nuAsset,
        uint256 _amount
    ) external view returns (uint256 TokenAmount);
    function ethToNuAssetRoundUp(
        address _nuAsset,
        uint256 _amount
    ) external view returns (uint256 TokenAmount);
    function ethToNuma(
        uint256 _ethAmount,
        address _numaPool,
        address _converter,
        PriceType _priceType
    ) external view returns (uint256 numaAmount);

    function numaToEth(
        uint256 _amount,
        address _numaPool,
        address _converter,
        PriceType _priceType
    ) external view returns (uint256);

    function getNbOfNuAssetFromNuAsset(
        uint256 _nuAssetAmountIn,
        address _nuAssetIn,
        address _nuAssetOut
    ) external view returns (uint256);

    function getTWAPPriceInEth(
        address _numaPool,
        address _converter,
        uint _numaAmount,
        uint32 _interval
    ) external view returns (uint256);
}
