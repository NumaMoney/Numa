// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts_5.0.2/utils/Pausable.sol";
import "@openzeppelin/contracts_5.0.2/access/Ownable2Step.sol";

import "@openzeppelin/contracts_5.0.2/token/ERC20/utils/SafeERC20.sol";
import "../Numa.sol";
import "./NumaMinter.sol";
import "../interfaces/INuAsset.sol";
import "../interfaces/INumaOracle.sol";
import "../interfaces/IVaultManager.sol";
import "../utils/constants.sol";

/// @title NumaPrinter
/// @notice Responsible for minting/burning Numa for nuAsset
/// @dev
contract NumaPrinter is Pausable, Ownable2Step {
    NUMA public immutable numa;
    NumaMinter public immutable minterContract;
    address public numaPool;
    address public tokenToEthConverter;
    //
    INumaOracle public oracle;
    //
    IVaultManager public vaultManager;
    //
    uint public printAssetFeeBps;
    uint public burnAssetFeeBps;
    uint public swapAssetFeeBps;

    uint public printBurnAssetFeeSentBps;
    address payable private fee_address;

    event SetOracle(address oracle);
    event SetChainlinkFeed(address _chainlink);
    event SetNumaPool(address _pool, address _convertAddress);
    event AssetMint(address _asset, uint _amount);
    event AssetBurn(address _asset, uint _amount);
    event PrintAssetFeeBps(uint _newfee);
    event BurnAssetFeeBps(uint _newfee);
    event SwapAssetFeeBps(uint _newfee);
    event SetFeeAddressAndBps(
        address payable _fee_address,
        uint _printBurnAssetFeeSentBps
    );

    event BurntFee(uint _fee);
    event PrintFee(uint _fee);
    event SwapFee(uint _fee);

    event SetVaultManager(address _vaultManager);

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

    modifier notInWarningCF() {
        uint currentCF = vaultManager.getGlobalCF();
        require(currentCF > vaultManager.getWarningCF(), "minting forbidden");
        _;
    }

    constructor(
        address _numaAddress,
        address _numaMinterAddress,
        address _numaPool,
        address _tokenToEthConverter,
        INumaOracle _oracle,
        address _vaultManagerAddress
    ) Ownable(msg.sender) {
        require(_numaPool != address(0), "no pool");
        numa = NUMA(_numaAddress);
        minterContract = NumaMinter(_numaMinterAddress);

        numaPool = _numaPool;
        // might not be necessary if using numa/ETH pool
        if (_tokenToEthConverter != address(0))
            tokenToEthConverter = _tokenToEthConverter;
        oracle = _oracle;
        vaultManager = IVaultManager(_vaultManagerAddress);

        // pause by default
        _pause();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setVaultManager(address _vaultManager) external onlyOwner {
        vaultManager = IVaultManager(_vaultManager);
        emit SetVaultManager(_vaultManager);
    }

    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */
    function setOracle(INumaOracle _oracle) external onlyOwner {
        oracle = _oracle;
        emit SetOracle(address(_oracle));
    }

    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */
    function setNumaPoolAndConverter(
        address _numaPool,
        address _converterAddress
    ) external onlyOwner {
        numaPool = _numaPool;
        tokenToEthConverter = _converterAddress;
        emit SetNumaPool(_numaPool, _converterAddress);
    }

    function setFeeAddress(
        address payable _fee_address,
        uint _printBurnAssetFeeSentBps
    ) external onlyOwner {
        fee_address = _fee_address;
        printBurnAssetFeeSentBps = _printBurnAssetFeeSentBps;
        emit SetFeeAddressAndBps(_fee_address, _printBurnAssetFeeSentBps);
    }

    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */
    function setPrintAssetFeeBps(uint _printAssetFeeBps) external onlyOwner {
        require(
            _printAssetFeeBps < 10000,
            "Fee percentage must be less than 100"
        );
        printAssetFeeBps = _printAssetFeeBps;
        emit PrintAssetFeeBps(_printAssetFeeBps);
    }

    function setSwapAssetFeeBps(uint _swapAssetFeeBps) external onlyOwner {
        require(
            _swapAssetFeeBps < 10000,
            "Fee percentage must be less than 100"
        );
        swapAssetFeeBps = _swapAssetFeeBps;
        emit SwapAssetFeeBps(_swapAssetFeeBps);
    }

    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */
    function setBurnAssetFeeBps(uint _burnAssetFeeBps) external onlyOwner {
        require(
            _burnAssetFeeBps < 10000,
            "Fee percentage must be less than 100"
        );
        burnAssetFeeBps = _burnAssetFeeBps;
        emit BurnAssetFeeBps(_burnAssetFeeBps);
    }

    /**
     * @dev mints a newAsset by burning numa
     * @notice block minting according to globalCF. Call accrueInterests on lending contracts as it will impact vault max borrowable amount
     */
    function mintNuAsset(
        INuAsset _asset,
        address _recipient,
        uint _amount,
        uint _numaAmount
    ) internal notInWarningCF {
        // uint currentCF = vaultManager.getGlobalCF();
        // require(currentCF > vaultManager.getWarningCF(), "minting forbidden");

        // mint
        _asset.mint(_recipient, _amount);
        vaultManager.updateBuyFeePID(_numaAmount, false);
        emit AssetMint(address(_asset), _amount);
    }

    /**
     * @dev burns a newAsset and mint numa
     * @notice
     */
    function burnNuAssetFrom(
        INuAsset _asset,
        address _sender,
        uint _amount,
        uint _numaAmount
    ) internal {
        // burn
        _asset.burnFrom(_sender, _amount);
        vaultManager.updateBuyFeePID(_numaAmount, false);
        emit AssetBurn(address(_asset), _amount);
    }

    /**
     * @notice update vault and accrue lending protocol interest rates  
     * @return scale 
     * @return criticalScaleForNumaPriceAndSellFee scale used in numa price computation (from vault) and in sell fee
     * @return sell_fee_res updated sell fee
     */
    function updateVaultAndInterest()
        public
        returns (
            uint scale,
            uint criticalScaleForNumaPriceAndSellFee,
            uint sell_fee_res
        )
    {
        // accrue interest on lending because synth supply has changed so utilization rates also
        // as to be done before minting because we accrue interest from current parameters
        vaultManager.updateVaults();

        // for same reasons, we need to update our synth scaling snapshot because synth supplies changes
        (
            scale,
            criticalScaleForNumaPriceAndSellFee,
            sell_fee_res
        ) = vaultManager.updateDebasings();
    }

    /**
     * @notice compute fees when amount in is specified
     * @param _amountIn amount
     * @param _fee fee parameter
     */
    function computeFeeAmountIn(
        uint _amountIn,
        uint _fee
    ) public pure returns (uint) {
        uint256 feeAmount = (_amountIn * _fee) / 10000;
        return feeAmount;
    }

    /**
     * @notice compute fees when amount out is specified
     * @param _amountIn amount
     * @param _fee fee parameter
     */
    function computeFeeAmountOut(
        uint _amountIn,
        uint _fee
    ) public pure returns (uint) {
        uint256 feeAmount = (_amountIn * _fee) / (10000 - _fee);
        return feeAmount;
    }

    /**
     * @notice get numa twap price in eth
     * @param _numaAmount amount
     * @param _interval time interval
     */
    function getTWAPPriceInEth(
        uint _numaAmount,
        uint32 _interval
    ) external view returns (uint) {
        return
            oracle.getTWAPPriceInEth(
                numaPool,
                tokenToEthConverter,
                _numaAmount,
                _interval
            );
    }

    // NUASSET --> NUASSET
    /**
     * @notice nb of nuassets B from nuasset A
     * @param _nuAssetIn input nuasset address
     * @param _nuAssetOut output nuasset address
     * @param _amountIn amount
     * @return amount out
     * @return fee 
     */
    function getNbOfNuAssetFromNuAsset(
        address _nuAssetIn,
        address _nuAssetOut,
        uint256 _amountIn
    ) public view returns (uint256, uint256) {
        // print fee
        uint256 amountToBurn = computeFeeAmountIn(_amountIn, swapAssetFeeBps);

        uint256 output = oracle.getNbOfNuAssetFromNuAsset(
            _amountIn - amountToBurn,
            _nuAssetIn,
            _nuAssetOut
        );
        return (output, amountToBurn);
    }

    /**
     * @notice nb of nuassets A needed to get a nb of nuAsset B
     * @param _nuAssetIn address of nuasset in
     * @param _nuAssetOut address of nuasset out
     * @param _amountOut desired amount
     * @return amount of nuasset in
     * @return fee
     */
    function getNbOfNuAssetNeededForNuAsset(
        address _nuAssetIn,
        address _nuAssetOut,
        uint256 _amountOut
    ) public view returns (uint256, uint256) {
        // le /1-x% devrait être appliqué avant le call oracle?
        uint256 nuAssetIn = oracle.getNbOfNuAssetFromNuAsset(
            _amountOut,
            _nuAssetOut,
            _nuAssetIn
        );
        // need more assetIn to pay the fee
        // uint256 nuAssetInWithFee = (nuAssetIn*10000) / (10000 - swapAssetFeeBps);
        //return (nuAssetInWithFee,(nuAssetInWithFee - nuAssetIn));
        uint256 feeAMount = computeFeeAmountOut(nuAssetIn, swapAssetFeeBps);
        return (nuAssetIn + feeAMount, feeAMount);
    }

    // NUMA --> NUASSET
    /**
     * @notice nb of nuassets froma numa amount
     * @param _nuAsset address of nuasset
     * @param _numaAmount numa amount
     * @return amount of nuasset
     * @return fee
     */
    function getNbOfNuAssetFromNuma(
        address _nuAsset,
        uint256 _numaAmount
    ) public view returns (uint256, uint256) {
        // print fee
        uint256 amountToBurn = computeFeeAmountIn(
            _numaAmount,
            printAssetFeeBps
        );

        // first convert this amount to Eth
        // formula is numaPrice = min(LPshort,LPlong,LPspot,vaultBuyPrice)
        // numa --> eth vault (buyprice)
        uint256 ethAmountVault = vaultManager.numaToEth(
            _numaAmount - amountToBurn,
            IVaultManager.PriceType.BuyPrice
        );

        // numa --> eth (pool lowest price)
        uint256 ethAmountPool = oracle.numaToEth(
            _numaAmount - amountToBurn,
            numaPool,
            tokenToEthConverter,
            INumaOracle.PriceType.LowestPrice
        );

        // compare
        uint ethAmount = ethAmountVault;
        if (ethAmountPool < ethAmountVault) ethAmount = ethAmountPool;

        // convert to nuAsset
        uint256 output = oracle.ethToNuAsset(_nuAsset, ethAmount);

        return (output, amountToBurn);
    }

    /**
     * @dev returns amount of Numa needed and fee to mint an amount of nuAsset
     * @param _nuAsset address of nuasset
     * @param _nuAssetAmount desired amount of nuasset
     * @return {uint256,uint256} amount of Numa that will be needed and fee to be burnt
     */
    function getNbOfNumaNeededAndFee(
        address _nuAsset,
        uint256 _nuAssetAmount
    ) public view returns (uint256, uint256) {
        // nuAssetAmount --> ethAmount
        // rounding up because we want rounding in favor of the protocol
        uint256 ethAmount = oracle.nuAssetToEthRoundUp(
            _nuAsset,
            _nuAssetAmount
        );

        // ethAmount --> numaAmount from vault
        uint256 numaAmountVault = vaultManager.ethToNuma(
            ethAmount,
            IVaultManager.PriceType.BuyPrice
        );

        uint256 numaAmountPool = oracle.ethToNuma(
            ethAmount,
            numaPool,
            tokenToEthConverter,
            INumaOracle.PriceType.LowestPrice
        );

        // mint price is the minimum between vault buy price and LP price
        uint costWithoutFee = numaAmountPool;
        if (numaAmountVault > numaAmountPool) costWithoutFee = numaAmountVault;

        uint256 feeAMount = computeFeeAmountOut(
            costWithoutFee,
            printAssetFeeBps
        );

        return (costWithoutFee + feeAMount, feeAMount);
    }

    // NUASSET --> NUMA
    /**
     * @dev returns amount of Numa minted and fee to be burnt from an amount of nuAsset
     * @param {address} _nuAsset nuasset address
     * @param {uint256} _nuAssetAmount amount of nuAsset we want to burn
     * @return {uint256,uint256} amount of Numa that will be minted and fee to be burnt
     */
    function getNbOfNumaFromAssetWithFee(
        address _nuAsset,
        uint256 _nuAssetAmount
    ) public view returns (uint256, uint256) {
        // nuAssetAmount --> ethAmount
        // rounding down
        uint256 ethAmount = oracle.nuAssetToEth(_nuAsset, _nuAssetAmount);

        // ethAmount --> numaAmount from vault
        uint256 numaAmountVault = vaultManager.ethToNuma(
            ethAmount,
            IVaultManager.PriceType.SellPrice
        );

        uint256 numaAmountPool = oracle.ethToNuma(
            ethAmount,
            numaPool,
            tokenToEthConverter,
            INumaOracle.PriceType.HighestPrice
        );

        // burn price is the max between vault sell price and LP price
        uint costWithoutFee = numaAmountPool;

        if (numaAmountVault < numaAmountPool) costWithoutFee = numaAmountVault;

        (uint scaleSynthBurn, , , ) = vaultManager.getSynthScaling();
        // apply scale
        costWithoutFee = (costWithoutFee * scaleSynthBurn) / BASE_1000;
        // burn fee
        uint256 amountToBurn = computeFeeAmountIn(
            costWithoutFee,
            burnAssetFeeBps
        );
        //uint256 amountToBurn = (_output * burnAssetFeeBps) / 10000;
        return (costWithoutFee - amountToBurn, amountToBurn);
    }

    /**
     * @dev returns amount of nuAsset needed mint an amount of numa
     * @notice if fees needs to be applied they should be in input amount
     * @param {uint256} _numaAmount amount we want to mint
     * @return {uint256} amount of nuAsset that will be needed
     */
    function getNbOfnuAssetNeededForNuma(
        address _nuAsset,
        uint _numaAmount
    ) public view returns (uint256, uint256) {
        uint256 feeAmount = computeFeeAmountOut(_numaAmount, burnAssetFeeBps);
        uint256 amountWithFee = _numaAmount + feeAmount;

        uint256 ethAmountVault = vaultManager.numaToEth(
            amountWithFee,
            IVaultManager.PriceType.SellPrice
        );
        // numa --> eth pool
        uint256 ethAmountPool = oracle.numaToEth(
            amountWithFee,
            numaPool,
            tokenToEthConverter,
            INumaOracle.PriceType.HighestPrice
        );

        // burn price is the max between vault sell price and LP price
        uint ethAmount = ethAmountVault;
        if (ethAmountPool > ethAmountVault) ethAmount = ethAmountPool;

        // ethAmount -- nuAssetAmount
        // rounding up because we need roundings in favor of protocol
        uint256 nuAssetIn = oracle.ethToNuAssetRoundUp(_nuAsset, ethAmount);
        (uint scaleSynthBurn, , , ) = vaultManager.getSynthScaling();
        // apply scale
        nuAssetIn = (nuAssetIn * BASE_1000) / scaleSynthBurn;

        return (nuAssetIn, amountWithFee - _numaAmount);
    }

    /**
     * dev
     * notice
     * param {uint256} _amount
     * param {address} _recipient
     */
    function mintAssetFromNumaInput(
        address _nuAsset,
        uint _numaAmount,
        uint _minNuAssetAmount,
        address _recipient
    ) public whenNotPaused returns (uint256) {
        require(address(oracle) != address(0), "oracle not set");
        require(numaPool != address(0), "uniswap pool not set");

        updateVaultAndInterest();

        uint256 assetAmount;
        uint256 numaFee;

        (assetAmount, numaFee) = getNbOfNuAssetFromNuma(_nuAsset, _numaAmount);

        require(assetAmount >= _minNuAssetAmount, "min amount");

        uint amountToBurn = _numaAmount;
        if (fee_address != address(0)) {
            uint amountToSend = (numaFee * printBurnAssetFeeSentBps) / 10000;
            SafeERC20.safeTransferFrom(
                IERC20(address(numa)),
                msg.sender,
                fee_address,
                amountToSend
            );
            amountToBurn -= amountToSend;
        }

        // burn
        numa.burnFrom(msg.sender, amountToBurn);
        // mint token
        INuAsset nuAsset = INuAsset(_nuAsset);
        // mint token
        mintNuAsset(nuAsset, _recipient, assetAmount, _numaAmount);

        emit PrintFee(numaFee);
        return assetAmount;
    }
    /**
     * dev burn Numa to mint nuAsset
     * notice contract should be nuAsset minter, and should have allowance from sender to burn Numa
     * param {uint256} _nuAssetamount amount of nuAsset to mint
     * param {address} _recipient recipient of minted nuAsset tokens
     */
    function mintAssetOutputFromNuma(
        address _nuAsset,
        uint _nuAssetamount,
        uint _maxNumaAmount,
        address _recipient
    ) external whenNotPaused {
        require(address(oracle) != address(0), "oracle not set");
        require(numaPool != address(0), "uniswap pool not set");

        updateVaultAndInterest();

        INuAsset nuAsset = INuAsset(_nuAsset);

        // how much numa should we burn to get this nuAsset amount
        uint256 numaCost;
        uint256 numaFee;
        (numaCost, numaFee) = getNbOfNumaNeededAndFee(_nuAsset, _nuAssetamount);

        // slippage check
        require(numaCost <= _maxNumaAmount, "max numa");

        uint amountToBurn = numaCost;

        if (fee_address != address(0)) {
            uint amountToSend = (numaFee * printBurnAssetFeeSentBps) / 10000;
            SafeERC20.safeTransferFrom(
                IERC20(address(numa)),
                msg.sender,
                fee_address,
                amountToSend
            );
            amountToBurn -= amountToSend;
        }

        // burn numa
        numa.burnFrom(msg.sender, amountToBurn);
        // mint token
        mintNuAsset(nuAsset, _recipient, _nuAssetamount, numaCost);
        emit PrintFee(numaFee); // NUMA burnt&sent
    }

    /**
     * dev burn nuAsset to mint Numa
     * notice contract should be Numa minter, and should have allowance from sender to burn nuAsset
     * param {uint256} _nuAssetAmount amount of nuAsset that we want to burn
     * param {address} _recipient recipient of minted Numa tokens
     */
    function burnAssetInputToNuma(
        address _nuAsset,
        uint256 _nuAssetAmount,
        uint256 _minimumReceivedAmount,
        address _recipient
    ) external whenNotPaused returns (uint) {
        updateVaultAndInterest();

        INuAsset nuAsset = INuAsset(_nuAsset);
        uint256 _output;
        uint256 amountToBurn;
        (_output, amountToBurn) = getNbOfNumaFromAssetWithFee(
            _nuAsset,
            _nuAssetAmount
        );

        require(_output >= _minimumReceivedAmount, "minimum amount");

        if (fee_address != address(0)) {
            uint amountToSend = (amountToBurn * printBurnAssetFeeSentBps) /
                10000;
            minterContract.mint(fee_address, amountToSend);
        }

        // burn amount
        burnNuAssetFrom(
            nuAsset,
            msg.sender,
            _nuAssetAmount,
            _output + amountToBurn
        );
        // and mint
        minterContract.mint(_recipient, _output);

        emit BurntFee(amountToBurn); // NUMA burnt (not minted & minted to fee address)
        return (_output);
    }

    /**
     * notice burn nuasset to get a specified amount of numa
     * @param _nuAsset nuasset address
     * @param _numaAmount numa amount needed
     * @param _maximumAmountIn max amount of nuasset (slippage parameter)
     * @param _recipient recipient 
     */
    function burnAssetToNumaOutput(
        address _nuAsset,
        uint256 _numaAmount,
        uint256 _maximumAmountIn,
        address _recipient
    ) external whenNotPaused returns (uint) {
        updateVaultAndInterest();
        INuAsset nuAsset = INuAsset(_nuAsset);

        // burn fee
        //uint256 amountWithFee = (_numaAmount*10000) / (10000 - burnAssetFeeBps);

        // how much _nuAssetFrom are needed to get this amount of Numa
        (uint256 nuAssetAmount, uint256 numaFee) = getNbOfnuAssetNeededForNuma(
            _nuAsset,
            _numaAmount
        );
        require(nuAssetAmount <= _maximumAmountIn, "max amount");

        if (fee_address != address(0)) {
            uint amountToSend = (numaFee * printBurnAssetFeeSentBps) / 10000;
            minterContract.mint(fee_address, amountToSend);
        }

        // burn amount
        burnNuAssetFrom(
            nuAsset,
            msg.sender,
            nuAssetAmount,
            _numaAmount + numaFee
        );

        minterContract.mint(_recipient, _numaAmount);

        emit BurntFee(numaFee); // NUMA burnt (not minted)
        return (_numaAmount);
    }

    /**
     * notice swap nuasset to nuasset, amount in specified
     * @param _nuAssetFrom input nuasset address
     * @param _nuAssetTo output nuasset address
     * @param _receiver recipient address
     * @param _amountToSwap amount in 
     * @param _amountOutMinimum minimum output amount (slippage)
     */
    function swapExactInput(
        address _nuAssetFrom,
        address _nuAssetTo,
        address _receiver,
        uint256 _amountToSwap,
        uint256 _amountOutMinimum
    ) external whenNotPaused notInWarningCF returns (uint256 amountOut) {
        require(_nuAssetFrom != address(0), "input asset not set");
        require(_nuAssetTo != address(0), "output asset not set");
        require(_receiver != address(0), "receiver not set");

        updateVaultAndInterest();

        INuAsset nuAssetFrom = INuAsset(_nuAssetFrom);
        INuAsset nuAssetTo = INuAsset(_nuAssetTo);
        // estimate output and check that it's ok with slippage
        // don't apply synth scaling here
        // fee is applied only 1 time when swapping
        (uint256 assetAmount, uint amountInFee) = getNbOfNuAssetFromNuAsset(
            _nuAssetFrom,
            _nuAssetTo,
            _amountToSwap
        );
        require((assetAmount) >= _amountOutMinimum, "min output");

        uint amountToBurn = _amountToSwap;
        // fees are 100% sent
        if (fee_address != address(0)) {
            SafeERC20.safeTransferFrom(
                IERC20(_nuAssetFrom),
                msg.sender,
                fee_address,
                amountInFee
            );
            amountToBurn -= amountInFee;
        }

        //

        // burn asset from
        burnNuAssetFrom(nuAssetFrom, msg.sender, amountToBurn, 0);

        // mint asset dest
        nuAssetTo.mint(_receiver, assetAmount);
        emit AssetMint(_nuAssetTo, assetAmount);

        emit SwapFee(amountInFee);
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

    /**
     * notice swap nuasset to nuasset, amount out specified
     * @param _nuAssetFrom input nuasset address
     * @param _nuAssetTo output nuasset address
     * @param _receiver recipient address
     * @param _amountToReceive amount out desired 
     * @param _amountInMaximum maximum input amount (slippage)
     */
    function swapExactOutput(
        address _nuAssetFrom,
        address _nuAssetTo,
        address _receiver,
        uint256 _amountToReceive,
        uint256 _amountInMaximum
    ) external whenNotPaused notInWarningCF returns (uint256 amountOut) {
        require(_nuAssetFrom != address(0), "input asset not set");
        require(_nuAssetTo != address(0), "output asset not set");
        require(_receiver != address(0), "receiver not set");

        updateVaultAndInterest();

        INuAsset nuAssetFrom = INuAsset(_nuAssetFrom);
        INuAsset nuAssetTo = INuAsset(_nuAssetTo);

        (uint256 nuAssetAmount, uint256 fee) = getNbOfNuAssetNeededForNuAsset(
            _nuAssetFrom,
            _nuAssetTo,
            _amountToReceive
        );

        require(nuAssetAmount <= _amountInMaximum, "maximum input reached");

        uint amountToBurn = nuAssetAmount;
        // fees are 100% sent
        if (fee_address != address(0)) {
            SafeERC20.safeTransferFrom(
                IERC20(_nuAssetFrom),
                msg.sender,
                fee_address,
                fee
            );
            amountToBurn -= fee;
        }

        // burn asset from
        burnNuAssetFrom(nuAssetFrom, msg.sender, amountToBurn, 0);

        nuAssetTo.mint(_receiver, _amountToReceive);
        emit AssetMint(_nuAssetTo, _amountToReceive);

        emit SwapFee(fee);
        emit SwapExactOutput(
            _nuAssetFrom,
            _nuAssetTo,
            msg.sender,
            _receiver,
            nuAssetAmount,
            _amountToReceive
        );

        return _amountToReceive;
    }
}
