// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts_5.0.2/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts_5.0.2/token/ERC20/extensions/IERC20Metadata.sol";

import "@openzeppelin/contracts_5.0.2/access/Ownable2Step.sol";

import "../libraries/OracleUtils.sol";
import "../interfaces/INuAssetManager.sol";

// struct representing a nuAsset: index in list (starts at 1), and pricefeed address
struct nuAssetInfo {
    address feed;
    uint128 heartbeat;
    uint index;
}

/// @title nuAssets manager
/// @notice used to compute total synthetics value in Eth
contract nuAssetManager is INuAssetManager, OracleUtils, Ownable2Step {
    // nuAsset to nuAssetInfo mapping
    mapping(address => nuAssetInfo) public nuAssetInfos;
    // list of nuAssets
    address[] public nuAssetList;

    // max number of nuAssets this contract can handle
    uint constant max_nuasset = 200;

    bool public renounceAddingRemovingAssets = false;

    event AddedAsset(address _assetAddress, address _pricefeed);
    event UpdatedAsset(address _assetAddress, address _pricefeed);
    event RemovedAsset(address _assetAddress);
    constructor(
        address _uptimeFeedAddress
    ) Ownable(msg.sender) OracleUtils(_uptimeFeedAddress) {}

    /**
     * @dev returns nuAssets list
     */
    function getNuAssetList() external view returns (address[] memory) {
        return nuAssetList;
    }

    function getNuAssetInfo(
        address _nuAsset
    ) public view returns (nuAssetInfo memory) {
        return nuAssetInfos[_nuAsset];
    }

    function renounceAddingRemoving() external onlyOwner {
        renounceAddingRemovingAssets = true;
    }

    /**
     * @dev does a nuAsset belong to our list
     */
    function contains(address _assetAddress) public view returns (bool) {
        return (nuAssetInfos[_assetAddress].index != 0);
    }

    /**
     * @dev adds a newAsset to the list
     */
    function addNuAsset(
        address _assetAddress,
        address _pricefeed,
        uint128 _heartbeat
    ) external onlyOwner {
        require(!renounceAddingRemovingAssets, "adding nuAsset renounced");
        require(_assetAddress != address(0), "invalid nuasset address");
        require(_pricefeed != address(0), "invalid price feed address");
        require(!contains(_assetAddress), "already added");
        require(nuAssetList.length < max_nuasset, "too many nuAssets");

        // add to list
        nuAssetList.push(_assetAddress);
        // add to mapping
        nuAssetInfos[_assetAddress] = nuAssetInfo(
            _pricefeed,
            _heartbeat,
            nuAssetList.length
        );
        emit AddedAsset(_assetAddress, _pricefeed);
    }

    /**
     * @dev removes a newAsset from the list
     */
    function removeNuAsset(address _assetAddress) external onlyOwner {
        require(!renounceAddingRemovingAssets, "adding nuAsset renounced");
        require(contains(_assetAddress), "not in list");
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
        emit RemovedAsset(_assetAddress);
    }

    /**
     * @dev updates a newAsset from the list
     */
    function updateNuAsset(
        address _assetAddress,
        address _pricefeed,
        uint128 _heartbeat
    ) external onlyOwner {
        require(_assetAddress != address(0), "invalid nuasset address");
        require(_pricefeed != address(0), "invalid price feed address");
        require(contains(_assetAddress), "not in list");
        // find out the index
        uint256 index = nuAssetInfos[_assetAddress].index;
        nuAssetInfos[_assetAddress] = nuAssetInfo(
            _pricefeed,
            _heartbeat,
            index
        );

        emit UpdatedAsset(_assetAddress, _pricefeed);
    }

    /**
     * @dev total synth value in Eth (in wei)
     */
    function getTotalSynthValueEth() external view returns (uint256) {
        uint result;
        uint256 nbNuAssets = nuAssetList.length;
        require(nbNuAssets <= max_nuasset, "too many nuAssets in list");
        for (uint256 i = 0; i < nbNuAssets; i++) {
            address nuAsset = nuAssetList[i];
            uint256 totalSupply = IERC20(nuAsset).totalSupply();
            if (totalSupply > 0) {
                nuAssetInfo memory info = nuAssetInfos[nuAsset];

                (address priceFeed, uint128 heartbeat) = (
                    info.feed,
                    info.heartbeat
                );
                uint256 EthValue = tokenToEth(
                    totalSupply,
                    priceFeed,
                    heartbeat,
                    IERC20Metadata(nuAsset).decimals()
                );

                result += EthValue;
            }
        }
        return result;
    }

    function nuAssetToEth(
        address _nuAsset,
        uint256 _amount
    ) public view returns (uint256 EthValue) {
        require(contains(_nuAsset), "bad nuAsset");
        nuAssetInfo memory info = getNuAssetInfo(_nuAsset);
        (address priceFeed, uint128 heartbeat) = (info.feed, info.heartbeat);
        return
            tokenToEth(
                _amount,
                priceFeed,
                heartbeat,
                IERC20Metadata(_nuAsset).decimals()
            );
    }

    function nuAssetToEthRoundUp(
        address _nuAsset,
        uint256 _amount
    ) public view returns (uint256 EthValue) {
        require(contains(_nuAsset), "bad nuAsset");
        nuAssetInfo memory info = getNuAssetInfo(_nuAsset);
        (address priceFeed, uint128 heartbeat) = (info.feed, info.heartbeat);
        return
            tokenToEthRoundUp(
                _amount,
                priceFeed,
                heartbeat,
                IERC20Metadata(_nuAsset).decimals()
            );
    }

    function ethToNuAsset(
        address _nuAsset,
        uint256 _amount
    ) public view returns (uint256 EthValue) {
        require(contains(_nuAsset), "bad nuAsset");
        nuAssetInfo memory info = getNuAssetInfo(_nuAsset);
        (address priceFeed, uint128 heartbeat) = (info.feed, info.heartbeat);
        return ethToToken(_amount, priceFeed, heartbeat, 18);
    }

    function ethToNuAssetRoundUp(
        address _nuAsset,
        uint256 _amount
    ) public view returns (uint256 EthValue) {
        require(contains(_nuAsset), "bad nuAsset");
        nuAssetInfo memory info = getNuAssetInfo(_nuAsset);
        (address priceFeed, uint128 heartbeat) = (info.feed, info.heartbeat);
        return ethToTokenRoundUp(_amount, priceFeed, heartbeat, 18);
    }

    function changeSequencerUptimeFeedAddress(
        address _newaddress
    ) external onlyOwner {
        sequencerUptimeFeed = _newaddress;
    }
}
