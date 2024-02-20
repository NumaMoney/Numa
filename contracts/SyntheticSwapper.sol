// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./NumaProtocol/NumaPrinter.sol";
import "./Numa.sol";
import "./interfaces/INuAsset.sol";
/// @title SyntheticSwapper
/// @notice Responsible for swapping nuAssets
/// @dev
contract SyntheticSwapper is Pausable, Ownable {
    NUMA public immutable numa;
    // Mapping from nuAsset to associated printer
    mapping(address => address) public nuAssetToPrinter;

    // TODO: list of supported assets?

    event SetPrinter(address _nuAsset, address _printer);
    event SwapExactInput(
        address _nuAssetFrom,
        address _nuAssetTo,
        address _from,
        address _to,
        uint256 _amountToSwap,
        uint256 _amountReceived
    );
    event SwapExactOutput(
        address _nuAssetFrom,
        address _nuAssetTo,
        address _from,
        address _to,
        uint256 _amountToSwap,
        uint256 _amountReceived
    );

    constructor(address _numaAddress) Ownable(msg.sender) {
        numa = NUMA(_numaAddress);
    }

    function setPrinter(address _nuAsset, address _printer) external onlyOwner {
        NumaPrinter printer = NumaPrinter(_printer);
        INuAsset printerAsset = printer.GetNuAsset();

        require(_nuAsset == address(printerAsset), "not printer token");
        nuAssetToPrinter[_nuAsset] = _printer;
        // approve printer on nuAsset and Numa token for burning
        // TODO: test that approval is infinite
        uint256 MAX_INT = 2 ** 256 - 1;
        IERC20(_nuAsset).approve(_printer, MAX_INT);
        numa.approve(_printer, MAX_INT);
        emit SetPrinter(_nuAsset, _printer);
    }
    function swapExactInput(
        address _nuAssetFrom,
        address _nuAssetTo,
        address _receiver,
        uint256 _amountToSwap,
        uint256 _amountOutMinimum
    ) external whenNotPaused returns (uint256 amountOut) {
        require(_nuAssetFrom != address(0), "input asset not set");
        require(_nuAssetTo != address(0), "output asset not set");
        require(_receiver != address(0), "receiver not set");

        address printerFromAddress = nuAssetToPrinter[_nuAssetFrom];
        address printerToAddress = nuAssetToPrinter[_nuAssetTo];

        require(printerFromAddress != address(0), "input asset has no printer");
        require(printerToAddress != address(0), "output asset has no printer");

        // NumaPrinter printerFrom = NumaPrinter(printerFromAddress);
        // NumaPrinter printerTo = NumaPrinter(printerToAddress);

        // estimate output and check that it's ok with slippage
        (uint256 numaEstimatedOutput, ) = NumaPrinter(printerFromAddress)
            .getNbOfNumaFromAssetWithFee(_amountToSwap);
        // estimate amount of nuAssets from this amount of Numa
        (uint256 nuAssetToAmount, uint256 fee) = NumaPrinter(printerToAddress)
            .getNbOfNuAssetFromNuma(numaEstimatedOutput);

        require(
            (nuAssetToAmount) >= _amountOutMinimum,
            "minimum output amount not reached"
        );

        // transfer input tokens
        SafeERC20.safeTransferFrom(
            IERC20(_nuAssetFrom),
            msg.sender,
            address(this),
            _amountToSwap
        );
        // no fee here, they will be applied when burning Numas
        uint256 numaMintedAmount = NumaPrinter(printerFromAddress)
            .burnAssetToNumaWithoutFee(_amountToSwap, address(this));
        uint256 assetAmount = NumaPrinter(printerToAddress)
            .mintAssetOutputFromNuma(numaMintedAmount, _receiver);
        // TODO: should we check again slippage here?

        require(
            (assetAmount) >= _amountOutMinimum,
            "minimum output amount not reached"
        );

        emit SwapExactInput(
            _nuAssetFrom,
            _nuAssetTo,
            msg.sender,
            _receiver,
            _amountToSwap,
            assetAmount
        );

        return assetAmount;
    }

    function swapExactOutput(
        address _nuAssetFrom,
        address _nuAssetTo,
        address _receiver,
        uint256 _amountToReceive,
        uint256 _amountInMaximum
    ) external whenNotPaused returns (uint256 amountOut) {
        require(_nuAssetFrom != address(0), "input asset not set");
        require(_nuAssetTo != address(0), "output asset not set");
        require(_receiver != address(0), "receiver not set");

        address printerFromAddress = nuAssetToPrinter[_nuAssetFrom];
        address printerToAddress = nuAssetToPrinter[_nuAssetTo];

        require(printerFromAddress != address(0), "input asset has no printer");
        require(printerToAddress != address(0), "output asset has no printer");

        // number of numa needed
        (uint256 numaAmount, uint256 fee) = NumaPrinter(printerToAddress)
            .getNbOfNumaNeededWithFee(_amountToReceive);

        // how much _nuAssetFrom are needed to get this amount of Numa
        (uint256 nuAssetAmount, uint256 fee2) = NumaPrinter(printerToAddress)
            .GetNbOfnuAssetNeededForNuma(numaAmount + fee);

        // we don't use fee2 as we apply fee only one time
        require(nuAssetAmount <= _amountInMaximum, "maximum input reached");

        // execute
        // transfer input tokens
        SafeERC20.safeTransferFrom(
            IERC20(_nuAssetFrom),
            msg.sender,
            address(this),
            nuAssetAmount
        );
        // no fee here, they will be applied when burning Numas
        uint256 numaMintedAmount = NumaPrinter(printerFromAddress)
            .burnAssetToNumaWithoutFee(nuAssetAmount, address(this));

        require(numaMintedAmount == numaAmount + fee, "just to be sure");

        uint256 assetAmount = NumaPrinter(printerToAddress)
            .mintAssetOutputFromNuma(numaMintedAmount, _receiver);

        require(assetAmount == _amountToReceive, "did not work");
        emit SwapExactOutput(
            _nuAssetFrom,
            _nuAssetTo,
            msg.sender,
            _receiver,
            nuAssetAmount,
            assetAmount
        );

        return assetAmount;
    }
}
