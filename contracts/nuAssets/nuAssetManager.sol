// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../libraries/OracleUtils.sol";
import "../interfaces/INuAsset.sol";
import "../interfaces/INuAssetManager.sol";

/// @title nuAssets manager
/// @notice used to compute total synthetics value in Eth
contract nuAssetManager is INuAssetManager, Ownable, OracleUtils {


    // struct representing a nuAsset: index in list (starts at 1), and pricefeed address
    struct nuAssetInfo { 
       address feed;
       uint index;
    }

    // nuAsset to nuAssetInfo mapping
    mapping(address => nuAssetInfo) public nuAssetInfos;
    // list of nuAssets
    address[] public nuAssetList;

    // max number of nuAssets this contract can handle
    uint constant max_nuasset = 200;


    constructor() Ownable(msg.sender)
    {

    }


    /**
     * @dev returns nuAssets list
     */  
    function getNuAssetList() external view returns(address[] memory)
    {
        return nuAssetList;
    }


    /**
     * @dev does a nuAsset belong to our list
     */  
    function contains(address _assetAddress) public view returns(bool) 
    {
        return (nuAssetInfos[_assetAddress].index != 0);
    }       


    /**
     * @dev adds a newAsset to the list
     */  
    function addNuAsset(address _assetAddress,address _pricefeed) external onlyOwner  
    {
        require(_assetAddress != address(0),"invalid nuasset address");
        require(_pricefeed != address(0),"invalid price feed address");
        require (!contains(_assetAddress),"already added");
        require (nuAssetList.length < max_nuasset,"too many nuAssets");

        // add to list
        nuAssetList.push(_assetAddress);
        // add to mapping
        nuAssetInfos[_assetAddress] = nuAssetInfo(_pricefeed,nuAssetList.length);

    }


    /**
     * @dev removes a newAsset from the list
     */  
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


    /**
     * @dev total synth value in Eth (in wei)
     */  
    function getTotalSynthValueEth() external view returns (uint256)
    {
        uint result;
        uint256 nbNuAssets = nuAssetList.length;
        require(nbNuAssets <= max_nuasset,"too many nuAssets in list");
        for (uint256 i = 0;i < nbNuAssets;i++)
        {
            uint256 totalSupply = IERC20(nuAssetList[i]).totalSupply();
            address priceFeed = nuAssetInfos[nuAssetList[i]].feed;
            require(priceFeed != address(0),"currency not supported");
            uint256 EthValue = getPriceInEth(totalSupply,priceFeed);
            result += EthValue;                                                                                                                                                                                                                                                                                 
        }
        return result;
    }
}