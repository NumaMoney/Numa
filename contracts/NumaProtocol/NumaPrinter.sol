// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../Numa.sol";
import "./NumaMinter.sol";
import "../interfaces/INuAsset.sol";
import "../interfaces/INumaOracle.sol";
import "../interfaces/IVaultManager.sol";

import "hardhat/console.sol";

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

    // synth minting/burning parameters
    uint16 public constant BASE_1000 = 1000;
    uint public cf_critical = 1500;
    uint public cf_warning = 1700;

    uint public debaseValue = 20;//base 1000
    uint public rebaseValue = 30;//base 1000
    uint public minimumScale = 500;
    uint public deltaRebase = 24 hours;
    uint public deltaDebase = 24 hours;

    uint lastScale = 1000;
    //uint lastCF = 20000;
    uint lastBlockTime;




    event SetOracle(address oracle); 
    event SetChainlinkFeed(address _chainlink);
    event SetNumaPool(address _pool,address _convertAddress);
    event AssetMint(address _asset, uint _amount);
    event AssetBurn(address _asset, uint _amount);
    event PrintAssetFeeBps(uint _newfee);
    event BurnAssetFeeBps(uint _newfee);
    event SwapAssetFeeBps(uint _newfee);
    event BurntFee(uint _fee);
    event PrintFee(uint _fee);
    event SwapFee(uint _fee);
    event SetVaultManager(address _vaultManager);
   
    event SetScalingParameters(
        uint cf_critical,
        uint cf_warning,
        uint debaseValue,
        uint rebaseValue,
        uint deltaRebase,
        uint deltaDebase,
        uint minimumScale);
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
        address _numaPool,
        address _tokenToEthConverter,
        INumaOracle _oracle,
        address _vaultManagerAddress

    ) Ownable(msg.sender) {
        numa = NUMA(_numaAddress);
        minterContract = NumaMinter(_numaMinterAddress);

        numaPool = _numaPool;
        // might not be necessary if using numa/ETH pool
        if (_tokenToEthConverter != address(0))
            tokenToEthConverter = _tokenToEthConverter;
        oracle = _oracle;
        vaultManager = IVaultManager(_vaultManagerAddress);
      
    }




    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setVaultManager(address _vaultManager) external onlyOwner
    {
        vaultManager = IVaultManager(_vaultManager);
        emit SetVaultManager(_vaultManager);
    }

    function setScalingParameters(uint _cf_critical,
        uint _cf_warning,
        uint _debaseValue,
        uint _rebaseValue,
        uint _deltaRebase,
        uint _deltaDebase,
        uint _minimumScale) external onlyOwner
    {

        cf_critical = _cf_critical;
        cf_warning = _cf_warning;
        debaseValue = _debaseValue;
        rebaseValue = _rebaseValue;
        deltaRebase = _deltaRebase;
        deltaDebase = _deltaDebase;
        minimumScale = _minimumScale;
        emit SetScalingParameters(
            _cf_critical,
            _cf_warning,
            _debaseValue,
            _rebaseValue,
            _deltaRebase,
            _deltaDebase,
            _minimumScale
            );
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
    function setNumaPoolAndConverter(address _numaPool,address _converterAddress) external onlyOwner {
        numaPool = _numaPool;
        tokenToEthConverter = _converterAddress;
        emit SetNumaPool(_numaPool,_converterAddress);
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
     * @dev mints a newAsset
     * @notice block minting according to globalCF. Call accrueInterests on lending contracts as it will impact vault max borrowable amount
     */
    function mintNuAsset(INuAsset _asset,address _recipient,uint _amount) internal
    {
        // TODO: we might want to use globalCFWithoutDebt for this one, to block minting of nuAssets when too much is borrowed
        uint currentCF = vaultManager.getGlobalCF();
        require(currentCF > cf_warning,"minting forbidden");

        // accrue interest on lending because synth supply has changed so utilization rates also
        // as to be done before minting because we accrue interest from current parameters
        vaultManager.accrueInterests();

        // for same reasons, we need to update our synth scaling snapshot because synth supplies changes
        //getSynthScalingUpdate();       
        (uint scaleOverride, uint scaleMemory,uint blockTime) = getSynthScaling();
        // mint
        _asset.mint(_recipient, _amount);

        // update snapshot
        //lastCF = vaultManager.getGlobalCF();
        lastBlockTime = blockTime;
        lastScale = scaleMemory;

        emit AssetMint(address(_asset), _amount);
    }

    /**
     * @dev burns a newAsset
     * @notice Call accrueInterests on lending contracts as it will impact vault max borrowable amount
     */
    function burnNuAssetFrom(INuAsset _asset,address _sender,uint _amount) internal
    {   
        // accrue interest on lending because synth supply has changed so utilization rates also
        vaultManager.accrueInterests();
        // burn
        _asset.burnFrom(_sender, _amount);
        emit AssetBurn(address(_asset), _amount);
    }


    function getSynthScalingUpdate() public returns (uint,uint,uint)
    {  
        (uint scaleOverride, uint scaleMemory,uint blockTime) = getSynthScaling();
        // save 
        lastScale = scaleMemory;
        lastBlockTime = blockTime;
    }

    function getSynthScaling() public virtual view returns (uint,uint,uint)// virtual for test&overrides
    {
        
        uint lastScaleMemory = lastScale;
        // synth scaling
        uint currentCF = vaultManager.getGlobalCF();
        uint blockTime = block.timestamp;
        if (currentCF < cf_critical)
        {        
            // we need to debase
            console.logUint(lastScaleMemory);
            //if (lastScaleMemory < BASE_1000)
            {
                // we are currently in debase/rebase mode

                if (blockTime > (lastBlockTime + deltaDebase))
                {
                    console.logUint(blockTime);
                    console.logUint(lastBlockTime);
                    // debase again
                    uint ndebase = (blockTime - lastBlockTime)/(deltaDebase);
                    console.logUint(ndebase);
                    ndebase = ndebase * debaseValue;
                     console.logUint(ndebase);
                    if (lastScaleMemory > ndebase)
                    {
                        lastScaleMemory = lastScaleMemory - ndebase;
                        if (lastScaleMemory < minimumScale)
                            lastScaleMemory = minimumScale;
                    }
                    else
                        lastScaleMemory = minimumScale;
                } 

            }
            // else
            // {
            //     // start debase
            //     lastScaleMemory = lastScaleMemory - debaseValue;
            // }
        }
        else
        {
            if (lastScaleMemory < BASE_1000)
            {
                 console.logUint(lastScaleMemory);
                // need to rebase
                if (blockTime > (lastBlockTime + deltaRebase))
                {
                    // rebase
                    uint nrebase = (blockTime - lastBlockTime)/(deltaRebase);
                     console.logUint(nrebase);
                    nrebase = nrebase * rebaseValue;
                    console.logUint(nrebase);
                    lastScaleMemory = lastScaleMemory + nrebase;
                      console.logUint(lastScaleMemory);
                    if (lastScaleMemory > BASE_1000)
                        lastScaleMemory = BASE_1000;
                } 
               

            }
        }

        // apply scale to synth burn price
        uint scale1000 = lastScaleMemory;

        // SECURITY
        if (currentCF < BASE_1000)
        {
            // TODO: do we use vaults balance with debt here?
            uint scaleSecure = currentCF;
            if (scaleSecure < scale1000)
                scale1000 = scaleSecure;
        }
        return (scale1000,lastScaleMemory,blockTime);

    }

    // NUASSET --> NUASSET
    
    function getNbOfNuAssetFromNuAsset(address _nuAssetIn,address _nuAssetOut,uint256 _amountIn
    ) public view returns (uint256, uint256) {

        // print fee
        uint256 amountToBurn = (_amountIn * swapAssetFeeBps) / 10000;

        uint256 output = oracle.getNbOfNuAssetFromNuAsset(
            _amountIn - amountToBurn,
            _nuAssetIn,
            _nuAssetOut
        );
        return (output, amountToBurn);
    }


    function getNbOfNuAssetNeededForNuAsset(address _nuAssetIn,address _nuAssetOut,uint256 _amountOut
    ) public view returns (uint256, uint256)
    {
        // le /1-x% devrait être appliqué avant le call oracle?
        uint256 nuAssetIn = oracle.getNbOfNuAssetFromNuAsset(
            _amountOut,
            _nuAssetOut,
            _nuAssetIn
        );
        // need more assetIn to pay the fee
        uint256 nuAssetInWithFee = (nuAssetIn*10000) / (10000 - swapAssetFeeBps);

        return (nuAssetInWithFee,(nuAssetInWithFee - nuAssetIn));
    }


    // NUMA --> NUASSET
    function getNbOfNuAssetFromNuma(address _nuAsset,uint256 _numaAmount
    ) public view returns (uint256, uint256) {

        // print fee
        uint256 amountToBurn = (_numaAmount * printAssetFeeBps) / 10000;

        uint256 output = oracle.getNbOfNuAsset(
            _numaAmount - amountToBurn,
            _nuAsset,
            numaPool,
            tokenToEthConverter
        );
        return (output, amountToBurn);
    }


    /**
     * @dev returns amount of Numa needed and fee to mint an amount of nuAsset
     * @param {uint256} _nuAssetAmount amount we want to mint
     * @return {uint256,uint256} amount of Numa that will be needed and fee to be burnt
     */
    function getNbOfNumaNeededAndFee(address _nuAsset,
        uint256 _nuAssetAmount
    ) public view returns (uint256, uint256) 
    {

        uint256 costWithoutFee = oracle.getNbOfNumaNeeded(
            _nuAssetAmount,
            _nuAsset,
            numaPool,
            tokenToEthConverter
        );
        uint256 costWithFee = (costWithoutFee*10000) / (10000 - printAssetFeeBps);

        // print fee
        //uint256 amountToBurn = (cost * printAssetFeeBps) / 10000;
        // will need to pay (burn): cost + amountToBurn 
        return (costWithFee, costWithFee - costWithoutFee);
    }


    // NUASSET --> NUMA
    /**
     * @dev returns amount of nuAsset needed mint an amount of numa
     * @notice if fees needs to be applied they should be in input amount
     * @param {uint256} _numaAmount amount we want to mint
     * @return {uint256} amount of nuAsset that will be needed
     */
    function getNbOfnuAssetNeededForNuma(address _nuAsset,
        uint _numaAmount
        ) internal returns (uint256,uint256) 
    {
        uint256 amountWithFee = (_numaAmount*10000) / (10000 - burnAssetFeeBps);

        uint256 nuAssetIn = oracle.getNbOfAssetneeded(
            amountWithFee,
            _nuAsset,
            numaPool,
            tokenToEthConverter
        );

       
        
        return (nuAssetIn,amountWithFee - _numaAmount);
    }

      /**
     * @dev returns amount of nuAsset needed mint an amount of numa
     * @notice if fees needs to be applied they should be in input amount
     * @param {uint256} _numaAmount amount we want to mint
     * @return {uint256} amount of nuAsset that will be needed
     */
    function getNbOfnuAssetNeededForNumaView(address _nuAsset,
        uint _numaAmount
    ) public view returns (uint256,uint256) 
    {
        uint256 amountWithFee = (_numaAmount*10000) / (10000 - burnAssetFeeBps);
        uint256 nuAssetIn = oracle.getNbOfAssetneeded(
            amountWithFee,
            _nuAsset,
            numaPool,
            tokenToEthConverter
        );

        (uint scaleOverride, uint scaleMemory,uint blockTime) = getSynthScaling();
        // apply scale
        nuAssetIn = (nuAssetIn*BASE_1000)/scaleOverride;
        

        return (nuAssetIn,amountWithFee - _numaAmount);
    }





    /**
     * @dev returns amount of Numa minted and fee to be burnt from an amount of nuAsset
     * @param {uint256} _nuAssetAmount amount of nuAsset we want to burn
     * @return {uint256,uint256} amount of Numa that will be minted and fee to be burnt
     */
    function getNbOfNumaFromAssetWithFee(address _nuAsset,
        uint256 _nuAssetAmount,uint scaleOverride
    ) public returns (uint256, uint256) 
    {

        uint256 _output = oracle.getNbOfNumaFromAsset(
            _nuAssetAmount,
            _nuAsset,
            numaPool,
            tokenToEthConverter
        );


        // (uint scaleOverride, uint scaleMemory,uint blockTime) = getSynthScalingUpdate();
        // apply scale
        _output = (_output*scaleOverride)/BASE_1000;


    
        // burn fee
        uint256 amountToBurn = (_output * burnAssetFeeBps) / 10000;
        return (_output, amountToBurn);
    }


     /**
     * @dev returns amount of Numa minted and fee to be burnt from an amount of nuAsset
     * @param {uint256} _nuAssetAmount amount of nuAsset we want to burn
     * @return {uint256,uint256} amount of Numa that will be minted and fee to be burnt
     */
    function getNbOfNumaFromAssetWithFeeView(address _nuAsset,
        uint256 _nuAssetAmount
    ) external view returns (uint256, uint256) 
    {

        uint256 _output = oracle.getNbOfNumaFromAsset(
            _nuAssetAmount,
            _nuAsset,
            numaPool,
            tokenToEthConverter
        );

        (uint scaleOverride, uint scaleMemory,uint blockTime) = getSynthScaling();
        // apply scale
        _output = (_output*scaleOverride)/BASE_1000;         

        

        // burn fee
        uint256 amountToBurn = (_output * burnAssetFeeBps) / 10000;
        return (_output, amountToBurn);
    }



    /**
     * dev
     * notice
     * param {uint256} _amount
     * param {address} _recipient
     */
    function mintAssetFromNumaInput(address _nuAsset,
        uint _numaAmount,
        uint _minNuAssetAmount,
        address _recipient
    ) public whenNotPaused returns (uint256) {
        require(address(oracle) != address(0), "oracle not set");
        require(numaPool != address(0), "uniswap pool not set");


        uint256 assetAmount;
        uint256 numaFee;
        // this function applies fees (amount = amount - fee)
        
        (assetAmount, numaFee) = getNbOfNuAssetFromNuma(_nuAsset,_numaAmount);

        require(assetAmount >= _minNuAssetAmount,"min amount");
        // burn
        numa.burnFrom(msg.sender, _numaAmount);
        // mint token
        INuAsset nuAsset = INuAsset(_nuAsset);
        // mint token
        mintNuAsset(nuAsset,_recipient,assetAmount);

        emit PrintFee(numaFee);
        return assetAmount;
    }
    /**
     * dev burn Numa to mint nuAsset
     * notice contract should be nuAsset minter, and should have allowance from sender to burn Numa
     * param {uint256} _nuAssetamount amount of nuAsset to mint
     * param {address} _recipient recipient of minted nuAsset tokens
     */
    function mintAssetOutputFromNuma(address _nuAsset,
        uint _nuAssetamount,
        uint _maxNumaAmount,
        address _recipient
    ) external whenNotPaused {
        require(address(oracle) != address(0), "oracle not set");
        require(numaPool != address(0), "uniswap pool not set");
        INuAsset nuAsset = INuAsset(_nuAsset);
        
        // how much numa should we burn to get this nuAsset amount
        uint256 numaCost;
        uint256 numaFee;
        (numaCost, numaFee) = getNbOfNumaNeededAndFee(_nuAsset,_nuAssetamount);

        // slippage check
        require (numaCost <= _maxNumaAmount,"max numa");

        // burn numa
        numa.burnFrom(msg.sender, numaCost);
        // mint token
        mintNuAsset(nuAsset,_recipient,_nuAssetamount);       
        emit PrintFee(numaFee); // NUMA burnt
    }

    /**
     * dev burn nuAsset to mint Numa
     * notice contract should be Numa minter, and should have allowance from sender to burn nuAsset
     * param {uint256} _nuAssetAmount amount of nuAsset that we want to burn
     * param {address} _recipient recipient of minted Numa tokens
     */
    function burnAssetInputToNuma(address _nuAsset,
        uint256 _nuAssetAmount,
        uint256 _minimumReceivedAmount,
        address _recipient
    ) external whenNotPaused returns (uint) {
      
        INuAsset nuAsset = INuAsset(_nuAsset);
      
        (uint scaleOverride, uint scaleMemory,uint blockTime) = getSynthScaling();
        uint256 _output;
        uint256 amountToBurn;
        (_output, amountToBurn) = getNbOfNumaFromAssetWithFee(_nuAsset,_nuAssetAmount,scaleOverride);

      
        // burn fee
        _output -= amountToBurn;
        require (_output >= _minimumReceivedAmount,"minimum amount");

        // burn amount       
        burnNuAssetFrom(nuAsset,msg.sender,_nuAssetAmount);
        // and mint
        minterContract.mint(_recipient,_output);

        // update snapshot
        //lastCF = vaultManager.getGlobalCF();
        lastBlockTime = blockTime;
        lastScale = scaleMemory;



        emit BurntFee(amountToBurn); // NUMA burnt (not minted)
        return (_output);
    }

   
    function burnAssetToNumaOutput(address _nuAsset,
        uint256 _numaAmount,
        uint256 _maximumAmountIn,
        address _recipient
    ) external whenNotPaused returns (uint) {
        //require (tokenPool != address(0),"No nuAsset pool");
        INuAsset nuAsset = INuAsset(_nuAsset);
      
        // burn fee
        //uint256 amountWithFee = (_numaAmount*10000) / (10000 - burnAssetFeeBps);

        // how much _nuAssetFrom are needed to get this amount of Numa

        (uint scaleOverride, uint scaleMemory,uint blockTime) = getSynthScaling();
        (uint256 nuAssetAmount,uint256 numaFee) = getNbOfnuAssetNeededForNuma(_nuAsset,_numaAmount);
        // apply scale
        nuAssetAmount = (nuAssetAmount*BASE_1000)/scaleOverride;
        require(nuAssetAmount <= _maximumAmountIn,"max amount");

        // burn amount
        burnNuAssetFrom(nuAsset,msg.sender,nuAssetAmount);
             
        minterContract.mint(_recipient,_numaAmount);

        
        // update snapshot
        //lastCF = vaultManager.getGlobalCF();
        lastBlockTime = blockTime;
        lastScale = scaleMemory;
        
      
        emit BurntFee(numaFee); // NUMA burnt (not minted)
        return (_numaAmount);
    }

   
    

   

    function swapExactInput(
        address _nuAssetFrom,
        address _nuAssetTo,
        address _receiver,
        uint256 _amountToSwap,
        uint256 _amountOutMinimum
    ) external whenNotPaused returns (uint256 amountOut) 
    {
        require(_nuAssetFrom != address(0), "input asset not set");
        require(_nuAssetTo != address(0), "output asset not set");
        require(_receiver != address(0), "receiver not set");

        INuAsset nuAssetFrom = INuAsset(_nuAssetFrom);
        INuAsset nuAssetTo = INuAsset(_nuAssetTo);
        // estimate output and check that it's ok with slippage
        // don't apply synth scaling here
        // fee is applied only 1 time when swapping
        (uint256 assetAmount,uint amountInFee) = getNbOfNuAssetFromNuAsset(_nuAssetFrom,_nuAssetTo,_amountToSwap);

        require(
            (assetAmount) >= _amountOutMinimum,
            "min output"
            );

        // burn asset from
        nuAssetFrom.burnFrom(msg.sender, _amountToSwap);
        emit AssetBurn(_nuAssetFrom, _amountToSwap);

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

        INuAsset nuAssetFrom = INuAsset(_nuAssetFrom);
        INuAsset nuAssetTo = INuAsset(_nuAssetTo);

        (uint256 nuAssetAmount, uint256 fee) = getNbOfNuAssetNeededForNuAsset(_nuAssetFrom,_nuAssetTo,_amountToReceive);


        require(nuAssetAmount <= _amountInMaximum, "maximum input reached");

        // burn asset from
        nuAssetFrom.burnFrom(msg.sender, nuAssetAmount);
        emit AssetBurn(_nuAssetFrom, nuAssetAmount);

        // mint asset dest
        // TODO don't call that function (block mint & accrueinterest)
        // mintNuAsset(nuAssetTo,_receiver,_amountToReceive);
        // emit PrintFee(fee);

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
