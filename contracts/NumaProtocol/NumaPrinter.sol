// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../Numa.sol";
import "../interfaces/INuAsset.sol";
import "../interfaces/INumaOracle.sol";

import "./NumaMinter.sol";
import "./VaultManager.sol";
import "../nuAssets/nuAssetManager.sol";

/// @title NumaPrinter
/// @notice Responsible for minting/burning Numa for nuAsset
/// @dev
contract NumaPrinter is Pausable, Ownable2Step {
    NUMA public immutable numa;
    NumaMinter public immutable minterContract;
    //INuAsset public immutable nuAsset;
    //
    address public numaPool;

    //
    INumaOracle public oracle;
    // address public chainlinkFeed;
    // uint128 public chainlinkheartbeat;

    VaultManager public vaultManager;
    nuAssetManager public nuAManager;
    //
    uint public printAssetFeeBps;
    uint public burnAssetFeeBps;
    mapping(address => bool) public burnFeeWhitelist;

    // synth minting/burning parameters
    uint16 public constant BASE_1000 = 1000;
    uint cf_critical = 1500;
    uint cf_warning = 1700;

    uint debaseValue = 20;//base 1000
    uint rebaseValue = 30;//base 1000
    uint deltaRebase = 24 hours;
    uint deltaDebase = 24 hours;
    uint lastScale = 1000;
    uint lastBlockTime;




    event SetOracle(address oracle); 
    event SetChainlinkFeed(address _chainlink);
    event SetNumaPool(address _pool);
    event AssetMint(address _asset, uint _amount);
    event AssetBurn(address _asset, uint _amount);
    event PrintAssetFeeBps(uint _newfee);
    event BurnAssetFeeBps(uint _newfee);
    event BurntFee(uint _fee);
    event PrintFee(uint _fee);
    event WhitelistBurnFee(address _address, bool value);
    event SetScalingParameters(
        uint cf_critical,
        uint cf_warning,
        uint debaseValue,
        uint rebaseValue,
        uint deltaRebase,
        uint deltaDebase);
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

    constructor(
        address _numaAddress,
        address _numaMinterAddress,
        //address _nuAssetAddress,
        address _numaPool,
        INumaOracle _oracle,
        address _vaultManagerAddress
        // address _chainlinkFeed,
        // uint128 _chainlinkheartbeat
    ) Ownable(msg.sender) {
        numa = NUMA(_numaAddress);
        minterContract = NumaMinter(_numaMinterAddress);
        //nuAsset = INuAsset(_nuAssetAddress);
        numaPool = _numaPool;
        oracle = _oracle;
        vaultManager = VaultManager(_vaultManagerAddress);
        INuAssetManager AMinterface = vaultManager.getNuAssetManager();
        nuAManager = nuAssetManager(address(AMinterface));

        // chainlinkFeed = _chainlinkFeed;
        // chainlinkheartbeat = _chainlinkheartbeat;
    }




    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setScalingParameters(uint _cf_critical,
        uint _cf_warning,
        uint _debaseValue,
        uint _rebaseValue,
        uint _deltaRebase,
        uint _deltaDebase) external onlyOwner
    {

        cf_critical = _cf_critical;
        cf_warning = _cf_warning;
        debaseValue = _debaseValue;
        rebaseValue = _rebaseValue;
        deltaRebase = _deltaRebase;
        deltaDebase = _deltaDebase;
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
    function setNumaPool(address _numaPool) external onlyOwner {
        numaPool = _numaPool;
        emit SetNumaPool(address(_numaPool));
    }

    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */
    function setPrintAssetFeeBps(uint _printAssetFeeBps) external onlyOwner {
        require(
            _printAssetFeeBps <= 10000,
            "Fee percentage must be 100 or less"
        );
        printAssetFeeBps = _printAssetFeeBps;
        emit PrintAssetFeeBps(_printAssetFeeBps);
    }

    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */
    function setBurnAssetFeeBps(uint _burnAssetFeeBps) external onlyOwner {
        require(
            _burnAssetFeeBps <= 10000,
            "Fee percentage must be 100 or less"
        );
        burnAssetFeeBps = _burnAssetFeeBps;
        emit BurnAssetFeeBps(_burnAssetFeeBps);
    }

    function mintNuAsset(INuAsset _asset,address _recipient,uint _amount) internal
    {
        uint currentCF = vaultManager.getGlobalCF();
        require(currentCF > cf_warning,"minting forbidden");

        _asset.mint(_recipient, _amount);
        // accrue interest on lending because synth supply has changed so utilization rates also
        vaultManager.accrueInterests();
        emit AssetMint(address(_asset), _amount);
    }
    // TODO: test it
    function whiteListBurnFee(address _input, bool _value) external onlyOwner {
        burnFeeWhitelist[_input] = _value;
        emit WhitelistBurnFee(_input, _value);
    }

    /**
     * @dev returns amount of Numa needed and fee to mint an amount of nuAsset
     * @param {uint256} _amount amount we want to mint
     * @return {uint256,uint256} amount of Numa that will be needed and fee to be burnt
     */
    function getNbOfNumaNeededWithFee(address _nuAsset,
        uint256 _amount
    ) public view returns (uint256, uint256) 
    {
        require(nuAManager.contains(_nuAsset),"bad nuAsset");
        nuAssetInfo memory info = nuAManager.getNuAssetInfo(_nuAsset);

        uint256 cost = oracle.getNbOfNumaNeeded(
            _amount,
            info.feed,
            info.heartbeat,
            numaPool
        );
        // print fee
        uint256 amountToBurn = (cost * printAssetFeeBps) / 10000;
        return (cost, amountToBurn);
    }

    /**
     * @dev returns amount of Numa minted and fee to be burnt from an amount of nuAsset
     * @param {uint256} _amount amount we want to burn
     * @return {uint256,uint256} amount of Numa that will be minted and fee to be burnt
     */
    function getNbOfNumaFromAssetWithFee(address _nuAsset,
        uint256 _amount
    ) public view returns (uint256, uint256) 
    {

        require(nuAManager.contains(_nuAsset),"bad nuAsset");
        nuAssetInfo memory info = nuAManager.getNuAssetInfo(_nuAsset);

        uint256 _output = oracle.getNbOfNumaFromAsset(
            _amount,
            info.feed,
            info.heartbeat,
            numaPool
        );
        // burn fee
        uint256 amountToBurn = (_output * burnAssetFeeBps) / 10000;
        return (_output, amountToBurn);
    }

    /**
     * dev burn Numa to mint nuAsset
     * notice contract should be nuAsset minter, and should have allowance from sender to burn Numa
     * param {uint256} _amount amount of nuAsset to mint
     * param {address} _recipient recipient of minted nuAsset tokens
     */
    function mintAssetFromNuma(address _nuAsset,
        uint _amount,
        address _recipient
    ) external whenNotPaused {
        require(address(oracle) != address(0), "oracle not set");
        require(numaPool != address(0), "uniswap pool not set");
        INuAsset nuAsset = INuAsset(_nuAsset);
        

        // how much numa should we burn to get this nuAsset amount
        uint256 numaCost;
        uint256 numaFee;
        (numaCost, numaFee) = getNbOfNumaNeededWithFee(_nuAsset,_amount);

        uint256 depositCost = numaCost + numaFee;

        require(
            numa.balanceOf(msg.sender) >= depositCost,
            "Insufficient Balance"
        );
        // burn
        numa.burnFrom(msg.sender, depositCost);
        // mint token
        mintNuAsset(nuAsset,_recipient,_amount);
       
        emit PrintFee(numaFee); // NUMA burnt
    }

    /**
     * dev burn nuAsset to mint Numa
     * notice contract should be Numa minter, and should have allowance from sender to burn nuAsset
     * param {uint256} _amount amount of nuAsset that we want to burn
     * param {address} _recipient recipient of minted Numa tokens
     */
    function burnAssetToNuma(address _nuAsset,
        uint256 _amount,
        address _recipient
    ) external whenNotPaused returns (uint) {
        //require (tokenPool != address(0),"No nuAsset pool");
        INuAsset nuAsset = INuAsset(_nuAsset);
        require(
            nuAsset.balanceOf(msg.sender) >= _amount,
            "Insufficient balance"
        );

        uint256 _output;
        uint256 amountToBurn;

        (_output, amountToBurn) = getNbOfNumaFromAssetWithFee(_nuAsset,_amount);

        // burn amount
        nuAsset.burnFrom(msg.sender, _amount);

        // burn fee
        _output -= amountToBurn;

        //numa.mint(_recipient, _output);
        minterContract.mint(_recipient,_output);
        // accrue interest on lending because synth supply has changed so utilization rates also
        vaultManager.accrueInterests();
        emit AssetBurn(address(nuAsset), _amount);
        emit BurntFee(amountToBurn); // NUMA burnt (not minted)
        return (_output);
    }

    // NEW FUNCTIONS FOR SYNTHETIC SWAP: TODO: add to printer&oracle tests

    function burnAssetToNumaWithoutFee(address _nuAsset,
        uint256 _amount,
        address _recipient
    ) public whenNotPaused returns (uint) 
    {
        INuAsset nuAsset = INuAsset(_nuAsset);
      
        require(
            (burnFeeWhitelist[msg.sender] == true),
            "Sender can not burn without fee"
        );
        require(
            nuAsset.balanceOf(msg.sender) >= _amount,
            "Insufficient balance"
        );

        uint256 _output;
        uint256 amountToBurn;

        (_output, amountToBurn) = getNbOfNumaFromAssetWithFee(_nuAsset,_amount);

        // burn amount
        nuAsset.burnFrom(msg.sender, _amount);

        // burn fee
        //_output -= amountToBurn;

        //numa.mint(_recipient, _output);
        minterContract.mint(_recipient,_output);
        // accrue interest on lending because synth supply has changed so utilization rates also
        vaultManager.accrueInterests();
        emit AssetBurn(address(nuAsset), _amount);
        return _output;
    }

    function getNbOfNuAssetFromNuma(address _nuAsset,uint256 _amount
    ) public view returns (uint256, uint256) {

        require(nuAManager.contains(_nuAsset),"bad nuAsset");
        nuAssetInfo memory info = nuAManager.getNuAssetInfo(_nuAsset);

        // print fee
        uint256 amountToBurn = (_amount * printAssetFeeBps) / 10000;

        uint256 output = oracle.getNbOfNuAsset(
            _amount - amountToBurn,
            info.feed,
            info.heartbeat,
            numaPool
        );
        return (output, amountToBurn);
    }

    // function GetNbOfnuAssetNeededForNuma(address _nuAsset,
    //     uint _amount
    // ) public view returns (uint256, uint256) {
    //     require(nuAManager.contains(_nuAsset),"bad nuAsset");
    //     nuAssetInfo memory info = nuAManager.getNuAssetInfo(_nuAsset);

    //     uint256 input = oracle.getNbOfAssetneeded(
    //         _amount,
    //         info.feed,
    //         info.heartbeat,
    //         numaPool
    //     );

    //     uint256 amountToBurn = (_amount * burnAssetFeeBps) / 10000;

    //     return (input, amountToBurn);
    // }

    /**
     * dev
     * notice
     * param {uint256} _amount
     * param {address} _recipient
     */
    function mintAssetOutputFromNuma(address _nuAsset,
        uint _amount,
        address _recipient
    ) public whenNotPaused returns (uint256) {
        require(address(oracle) != address(0), "oracle not set");
        require(numaPool != address(0), "uniswap pool not set");

        uint256 assetAmount;
        uint256 numaFee;
        (assetAmount, numaFee) = getNbOfNuAssetFromNuma(_nuAsset,_amount);

        require(numa.balanceOf(msg.sender) >= _amount, "Insufficient Balance");
        // burn
        numa.burnFrom(msg.sender, _amount);
        // mint token
        INuAsset nuAsset = INuAsset(_nuAsset);
        // nuAsset.mint(_recipient, assetAmount);
        // // accrue interest on lending because synth supply has changed so utilization rates also
        // vaultManager.accrueInterests();
        // emit AssetMint(address(nuAsset), assetAmount);

        // mint token
        mintNuAsset(nuAsset,_recipient,assetAmount);


        emit PrintFee(numaFee);
        return assetAmount;
    }


    // // swap functions
    // function swapExactInput(
    //     address _nuAssetFrom,
    //     address _nuAssetTo,
    //     address _receiver,
    //     uint256 _amountToSwap,
    //     uint256 _amountOutMinimum
    // ) external whenNotPaused returns (uint256 amountOut) {
    //     require(_nuAssetFrom != address(0), "input asset not set");
    //     require(_nuAssetTo != address(0), "output asset not set");
    //     require(_receiver != address(0), "receiver not set");

    //     // estimate output and check that it's ok with slippage
    //     (uint256 numaEstimatedOutput, ) = getNbOfNumaFromAssetWithFee(_nuAssetFrom,_amountToSwap);
    //     // estimate amount of nuAssets from this amount of Numa
    //     (uint256 nuAssetToAmount, uint256 fee) = getNbOfNuAssetFromNuma(_nuAssetTo,numaEstimatedOutput);

    //     require(
    //         (nuAssetToAmount) >= _amountOutMinimum,
    //         "min output"
    //     );

    //     // transfer input tokens
    //     SafeERC20.safeTransferFrom(
    //         IERC20(_nuAssetFrom),
    //         msg.sender,
    //         address(this),
    //         _amountToSwap
    //     );
    //     // no fee here
    //     uint256 numaMintedAmount = burnAssetToNumaWithoutFee(_nuAssetFrom,_amountToSwap, address(this));
    //     // fees here
    //     uint256 assetAmount = mintAssetOutputFromNuma(_nuAssetTo,numaMintedAmount, _receiver);
     
    //     require(
    //         (assetAmount) >= _amountOutMinimum,
    //         "min output"
    //     );

    //     emit SwapExactInput(
    //         _nuAssetFrom,
    //         _nuAssetTo,
    //         msg.sender,
    //         _receiver,
    //         _amountToSwap,
    //         assetAmount
    //     );

    //     return assetAmount;
    // }

    // TODO
    // function swapExactOutput(
    //     address _nuAssetFrom,
    //     address _nuAssetTo,
    //     address _receiver,
    //     uint256 _amountToReceive,
    //     uint256 _amountInMaximum
    // ) external whenNotPaused returns (uint256 amountOut) {
    //     require(_nuAssetFrom != address(0), "input asset not set");
    //     require(_nuAssetTo != address(0), "output asset not set");
    //     require(_receiver != address(0), "receiver not set");

    //     address printerFromAddress = nuAssetToPrinter[_nuAssetFrom];
    //     address printerToAddress = nuAssetToPrinter[_nuAssetTo];

    //     require(printerFromAddress != address(0), "input asset has no printer");
    //     require(printerToAddress != address(0), "output asset has no printer");

    //     // number of numa needed
    //     (uint256 numaAmount, uint256 fee) = NumaPrinter(printerToAddress)
    //         .getNbOfNumaNeededWithFee(_amountToReceive);

    //     // how much _nuAssetFrom are needed to get this amount of Numa
    //     (uint256 nuAssetAmount, uint256 fee2) = NumaPrinter(printerToAddress)
    //         .GetNbOfnuAssetNeededForNuma(numaAmount + fee);

    //     // we don't use fee2 as we apply fee only one time
    //     require(nuAssetAmount <= _amountInMaximum, "maximum input reached");

    //     // execute
    //     // transfer input tokens
    //     SafeERC20.safeTransferFrom(
    //         IERC20(_nuAssetFrom),
    //         msg.sender,
    //         address(this),
    //         nuAssetAmount
    //     );
    //     // no fee here, they will be applied when burning Numas
    //     uint256 numaMintedAmount = NumaPrinter(printerFromAddress)
    //         .burnAssetToNumaWithoutFee(nuAssetAmount, address(this));

    //     require(numaMintedAmount == numaAmount + fee, "just to be sure");

    //     uint256 assetAmount = NumaPrinter(printerToAddress)
    //         .mintAssetOutputFromNuma(numaMintedAmount, _receiver);

    //     require(assetAmount == _amountToReceive, "did not work");
    //     emit SwapExactOutput(
    //         _nuAssetFrom,
    //         _nuAssetTo,
    //         msg.sender,
    //         _receiver,
    //         nuAssetAmount,
    //         assetAmount
    //     );

    //     return assetAmount;
    // }


}
