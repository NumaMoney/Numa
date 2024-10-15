// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts_5.0.2/access/Ownable.sol";
import "@openzeppelin/contracts_5.0.2/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts_5.0.2/token/ERC20/extensions/IERC20Metadata.sol";
import "../../libraries/OracleUtils.sol";
import "../../interfaces/INuAsset.sol";
import "../../interfaces/INuAssetManager.sol";

contract nuAssetManagerMock is INuAssetManager, OracleUtils {
    struct nuAssetInfo {
        address feed;
        uint index;
    }

    mapping(address => nuAssetInfo) public nuAssetInfos;
    address[] public nuAssetList;

    uint constant max_nuasset = 200;

    constructor(address _uptimeFeedAddress) OracleUtils(_uptimeFeedAddress) {}
    function getNuAssetList() external view returns (address[] memory) {
        return nuAssetList;
    }

    function contains(address _assetAddress) public view returns (bool) {
        return (nuAssetInfos[_assetAddress].index != 0);
    }

    function addNuAsset(address _assetAddress, address _pricefeed) external {
        require(_assetAddress != address(0), "invalid nuasset address");
        require(_pricefeed != address(0), "invalid price feed address");
        //require (!contains(_assetAddress),"already added");// to test having 200 nuAssets in list
        require(nuAssetList.length < max_nuasset, "too many nuAssets");

        nuAssetList.push(_assetAddress);
        nuAssetInfos[_assetAddress] = nuAssetInfo(
            _pricefeed,
            nuAssetList.length
        );
    }

    function getTotalSynthValueEth() external view returns (uint256) {
        uint result;
        uint256 nbNuAssets = nuAssetList.length;
        require(nbNuAssets <= max_nuasset, "too many nuAssets in list");
        for (uint256 i = 0; i < nbNuAssets; i++) {
            uint256 totalSupply = IERC20(nuAssetList[i]).totalSupply();
            address priceFeed = nuAssetInfos[nuAssetList[i]].feed;
            require(priceFeed != address(0), "currency not supported");
            uint256 EthValue = tokenToEth(
                totalSupply,
                priceFeed,
                24 hours,
                IERC20Metadata(nuAssetList[i]).decimals()
            );
            result += EthValue;
        }
        return result;
    }
}
