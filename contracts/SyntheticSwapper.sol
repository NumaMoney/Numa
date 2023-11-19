// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";



/// @title SyntheticSwapper
/// @notice Responsible for swapping nuAssets
/// @dev 
contract SyntheticSwapper is Pausable, Ownable
{
    // Mapping from nuAsset to associated printer
    mapping(address => address) public nuAssetToPrinter;

    function Swap(address _nuAssetFrom,address _nuAssetTo,address _receiver,uint256 _amountToSwap)
    {
        // TODO: check inputs
        NumaPrinter printerFrom = nuAssetToPrinter[_nuAssetFrom];
        NumaPrinter printerTo = nuAssetToPrinter[_nuAssetTo];

        // TODO: check printers != 0
        // TODO: safeTransferFrom to this contract or swapper/printer allowed to burnFrom
        uint256 numaMintedAmount = printerFrom.burnAssetToNumaWithoutFee(_amountToSwap,address(this));
        uint256 nuAssetToAmount = ;// TODO: from input?, use slippage params?, functions to estimate ?
        printerTo.mintAssetFromNuma(nuAssetToAmount,_receiver);
        // todo: event

    }
}