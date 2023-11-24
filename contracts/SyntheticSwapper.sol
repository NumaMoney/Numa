// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NumaProtocol/NumaPrinter.sol";
import "./Numa.sol";
import "./interfaces/INuAsset.sol";
/// @title SyntheticSwapper
/// @notice Responsible for swapping nuAssets
/// @dev 
contract SyntheticSwapper is Pausable, Ownable
{
    NUMA public immutable numa;
    // Mapping from nuAsset to associated printer
    mapping(address => address) public nuAssetToPrinter;

    event SetPrinter(address _nuAsset, address _printer);
    event SwapExactInput(address _nuAssetFrom,address _nuAssetTo,address _from,address _to,uint256 _amountToSwap,uint256 _amountReceived);

    constructor(address _numaAddress) Ownable(msg.sender)
    {
        numa = NUMA(_numaAddress);
    }

    function setPrinter(address _nuAsset, address _printer) external onlyOwner
    {
        NumaPrinter printer = NumaPrinter(_printer);
        INuAsset printerAsset = printer.GetNuAsset();

        require(_nuAsset == address(printerAsset),"not printer token");
        nuAssetToPrinter[_nuAsset] = _printer;
        // approve printer on nuAsset and Numa token for burning 
        // TODO: test that approval is infinite
        uint256 MAX_INT = 2**256 - 1;
        IERC20(_nuAsset).approve(_printer,MAX_INT);
        numa.approve(_printer,MAX_INT);
        emit SetPrinter(_nuAsset,_printer);

    }
    function swapExactInput(address _nuAssetFrom,address _nuAssetTo,address _receiver,uint256 _amountToSwap,uint256 _amountOutMinimum) external whenNotPaused returns (uint256 amountOut) 
    {
     
        require(_nuAssetFrom != address(0),"input asset not set");
        require(_nuAssetTo != address(0),"output asset not set");
        require(_receiver != address(0),"receiver not set");

        address printerFromAddress = nuAssetToPrinter[_nuAssetFrom];
        address printerToAddress = nuAssetToPrinter[_nuAssetTo];

        require(printerFromAddress != address(0),"input asset has no printer");
        require(printerToAddress != address(0),"output asset has no printer");

        // NumaPrinter printerFrom = NumaPrinter(printerFromAddress);
        // NumaPrinter printerTo = NumaPrinter(printerToAddress);

        // estimate output and check that it's ok with slippage
        (uint256 numaEstimatedOutput,) = NumaPrinter(printerFromAddress).getNbOfNumaFromAssetWithFee(_amountToSwap);
        // estimate amount of nuAssets from this amount of Numa
        (uint256 nuAssetToAmount,uint256 fee) = NumaPrinter(printerToAddress).getNbOfNuAssetFromNuma(numaEstimatedOutput);
        
        require((nuAssetToAmount - fee) >=  _amountOutMinimum,"minimum output amount not reached");


        // transfer input tokens
        SafeERC20.safeTransferFrom(IERC20(_nuAssetFrom),msg.sender,address(this),_amountToSwap);
        // no fee here, they will be applied when burning Numas       
        uint256 numaMintedAmount = NumaPrinter(printerFromAddress).burnAssetToNumaWithoutFee(_amountToSwap,address(this));
        uint256 assetAmount = NumaPrinter(printerToAddress).mintAssetOutputFromNuma(numaMintedAmount,_receiver);
        emit SwapExactInput(_nuAssetFrom,_nuAssetTo,msg.sender,_receiver, _amountToSwap,assetAmount);

        return assetAmount;

    }


    // // TODO?
    // function swapExactOutput(address _nuAssetFrom,address _nuAssetTo,address _receiver,uint256 _amountToSwap)
    // {


    // }
}