// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/OracleUtils.sol";
import "../interfaces/INuAsset.sol";
import "../interfaces/INuAssetManager.sol";
import "hardhat/console.sol";


contract nuAssetManager is INuAssetManager, Ownable, OracleUtils {


    struct nuAssetInfo { 
       address feed;
       uint index;
    }

    mapping(address => nuAssetInfo) public nuAssetInfos;
    address[] public nuAssetList;

    uint constant max_nuasset = 200;


    constructor() Ownable(msg.sender)
    {

    }

    function getNuAssetList() external view returns(address[] memory)
    {
        return nuAssetList;
    }

    function contains(address _assetAddress) public view returns(bool) 
    {
        return (nuAssetInfos[_assetAddress].index != 0);
    }       

    function addNuAsset(address _assetAddress,address _pricefeed) external onlyOwner  
    {
        require(_assetAddress != address(0),"invalid nuasset address");
        require(_pricefeed != address(0),"invalid price feed address");
        require (!contains(_assetAddress),"already added");
        require (nuAssetList.length < max_nuasset,"too many nuAssets");

        nuAssetList.push(_assetAddress);
        nuAssetInfos[_assetAddress] = nuAssetInfo(_pricefeed,nuAssetList.length);

    }



    function removeNuAsset(address _assetAddress) external onlyOwner  
    {
        require (contains(_assetAddress),"not in list");
        // find out the index
        uint256 index = nuAssetInfos[_assetAddress].index;
        // moves last element to the place of the value
        // so there are no free spaces in the array
        address lastValue = nuAssetList[nuAssetList.length - 1];
        nuAssetList[index - 1] = lastValue;
        nuAssetInfos[lastValue].index = index;

        // delete the index
        delete nuAssetInfos[_assetAddress];

        // deletes last element and reduces array size
        nuAssetList.pop();
    }






    function getTotalSynthValueEth() external view returns (uint256)
    {
        uint result;
        uint256 nbNuAssets = nuAssetList.length;
        require(nbNuAssets <= max_nuasset,"too many nuAssets in list");
        for (uint256 i = 0;i < nbNuAssets;i++)
        {
            uint256 totalSupply = IERC20(nuAssetList[i]).totalSupply();
            console.logUint(totalSupply);
            address priceFeed = nuAssetInfos[nuAssetList[i]].feed;
            require(priceFeed != address(0),"currency not supported");
            uint256 EthValue = getPriceInEth(totalSupply,priceFeed);
            console.logUint(EthValue);
            result += EthValue;                                                                                                                                                                                                                                                                                 
        }
        return result;

    }

}
