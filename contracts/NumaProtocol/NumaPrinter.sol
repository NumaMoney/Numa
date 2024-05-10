// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../Numa.sol";
import "./NumaMinter.sol";
import "../interfaces/INuAsset.sol";
import "../interfaces/INumaOracle.sol";
import "../interfaces/IVaultManager.sol";



/// @title NumaPrinter
/// @notice Responsible for minting/burning Numa for nuAsset
/// @dev
contract NumaPrinter is Pausable, Ownable2Step {
    NUMA public immutable numa;
    NumaMinter public immutable minterContract;
    address public numaPool;

    //
    INumaOracle public oracle;
    //
    IVaultManager public vaultManager;
    //
    uint public printAssetFeeBps;
    uint public burnAssetFeeBps;

    // synth minting/burning parameters
    uint16 public constant BASE_1000 = 1000;
    uint cf_critical = 1500;
    uint cf_warning = 1700;

    uint debaseValue = 20;//base 1000
    uint rebaseValue = 30;//base 1000
    uint minimumScale = 500;
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
        INumaOracle _oracle,
        address _vaultManagerAddress

    ) Ownable(msg.sender) {
        numa = NUMA(_numaAddress);
        minterContract = NumaMinter(_numaMinterAddress);

        numaPool = _numaPool;
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
    function setNumaPool(address _numaPool) external onlyOwner {
        numaPool = _numaPool;
        emit SetNumaPool(address(_numaPool));
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
     * @notice block minting according to vaultCF. Call accrueInterests on lending contracts as it will impact vault max borrowable amount
     */
    function mintNuAsset(INuAsset _asset,address _recipient,uint _amount) internal
    {
        uint currentCF = vaultManager.getGlobalCF();
        require(currentCF > cf_warning,"minting forbidden");

        // accrue interest on lending because synth supply has changed so utilization rates also
        vaultManager.accrueInterests();
        // mint
        _asset.mint(_recipient, _amount);
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


    function getSynthScaling() internal view returns (uint,uint,uint)
    {
        uint lastScaleMemory = lastScale;
        // synth scaling
        uint currentCF = vaultManager.getGlobalCF();
        uint blockTime = block.timestamp;
        if (currentCF < cf_critical)
        {
            // we need to debase
            if (lastScaleMemory < BASE_1000)
            {
                // we are currently in debase/rebase mode

                if (blockTime > lastBlockTime + deltaDebase)
                {
                    // debase again
                    uint ndebase = blockTime/(lastBlockTime + deltaDebase);
                    ndebase = ndebase * debaseValue;
                    if (lastScaleMemory > ndebase)
                        lastScaleMemory = lastScaleMemory - ndebase;
                        if (lastScaleMemory < minimumScale)
                            lastScaleMemory = minimumScale;
                    else
                        lastScaleMemory = minimumScale;
                } 

            }
            else
            {
                // start debase
                lastScaleMemory = lastScaleMemory - debaseValue;
            }
        }
        else
        {
            if (lastScaleMemory < BASE_1000)
            {
                // need to rebase
                if (blockTime > lastBlockTime + deltaRebase)
                {
                    // rebase
                    uint nrebase = blockTime/(lastBlockTime + deltaRebase);
                    nrebase = nrebase * rebaseValue;

                    lastScaleMemory = lastScaleMemory + nrebase;
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

    // NUMA --> NUASSET
    function getNbOfNuAssetFromNuma(address _nuAsset,uint256 _numaAmount
    ) public view returns (uint256, uint256) {

        // print fee
        uint256 amountToBurn = (_numaAmount * printAssetFeeBps) / 10000;

        uint256 output = oracle.getNbOfNuAsset(
            _numaAmount - amountToBurn,
            _nuAsset,
            numaPool
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

        uint256 cost = oracle.getNbOfNumaNeeded(
            _nuAssetAmount,
            _nuAsset,
            numaPool
        );
        // print fee
        uint256 amountToBurn = (cost * printAssetFeeBps) / 10000;
        // will need to pay (burn): cost + amountToBurn 
        return (cost, amountToBurn);
    }


    // NUASSET --> NUMA
    /**
     * @dev returns amount of nuAsset needed mint an amount of numa
     * @notice if fees needs to be applied they should be in input amount
     * @param {uint256} _numaAmount amount we want to mint
     * @return {uint256} amount of nuAsset that will be needed
     */
    function GetNbOfnuAssetNeededForNuma(address _nuAsset,
        uint _numaAmountIncludingFee,bool _applyScaling
    ) internal returns (uint256) 
    {
        uint256 nuAssetIn = oracle.getNbOfAssetneeded(
            _numaAmountIncludingFee,
            _nuAsset,
            numaPool
        );

        if (_applyScaling)
        {
            (uint scaleOverride, uint scaleMemory,uint blockTime) = getSynthScaling();
            // apply scale
            nuAssetIn = (nuAssetIn*BASE_1000)/scaleOverride;
            // save 
            lastScale = scaleMemory;
            lastBlockTime = blockTime;

        }

        return nuAssetIn;
    }

  




    /**
     * @dev returns amount of Numa minted and fee to be burnt from an amount of nuAsset
     * @param {uint256} _nuAssetAmount amount of nuAsset we want to burn
     * @return {uint256,uint256} amount of Numa that will be minted and fee to be burnt
     */
    function getNbOfNumaFromAssetWithFee(address _nuAsset,
        uint256 _nuAssetAmount,bool _applyScaling
    ) public returns (uint256, uint256) 
    {

        uint256 _output = oracle.getNbOfNumaFromAsset(
            _nuAssetAmount,
            _nuAsset,
            numaPool
        );

        if (_applyScaling)
        {
            (uint scaleOverride, uint scaleMemory,uint blockTime) = getSynthScaling();
            // apply scale
            _output = (_output*scaleOverride)/BASE_1000;
            // save 
            lastScale = scaleMemory;
            lastBlockTime = blockTime;

        }

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
        uint256 _nuAssetAmount,bool _applyScaling
    ) external view returns (uint256, uint256) 
    {

        uint256 _output = oracle.getNbOfNumaFromAsset(
            _nuAssetAmount,
            _nuAsset,
            numaPool
        );

        if (_applyScaling)
        {
            (uint scaleOverride, uint scaleMemory,uint blockTime) = getSynthScaling();
            // apply scale
            _output = (_output*scaleOverride)/BASE_1000;         

        }

        // burn fee
        uint256 amountToBurn = (_output * burnAssetFeeBps) / 10000;
        return (_output, amountToBurn);
    }




    /**
     * dev burn Numa to mint nuAsset
     * notice contract should be nuAsset minter, and should have allowance from sender to burn Numa
     * param {uint256} _nuAssetamount amount of nuAsset to mint
     * param {address} _recipient recipient of minted nuAsset tokens
     */
    function mintAssetOutputFromNuma(address _nuAsset,
        uint _nuAssetamount,
        address _recipient
    ) external whenNotPaused {
        require(address(oracle) != address(0), "oracle not set");
        require(numaPool != address(0), "uniswap pool not set");
        INuAsset nuAsset = INuAsset(_nuAsset);
        

        // how much numa should we burn to get this nuAsset amount
        uint256 numaCost;
        uint256 numaFee;
        (numaCost, numaFee) = getNbOfNumaNeededAndFee(_nuAsset,_nuAssetamount);

        uint256 depositCost = numaCost + numaFee;

        // burn numa
        numa.burnFrom(msg.sender, depositCost);
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
        address _recipient
    ) external whenNotPaused returns (uint) {
      
        INuAsset nuAsset = INuAsset(_nuAsset);
      
        uint256 _output;
        uint256 amountToBurn;

        (_output, amountToBurn) = getNbOfNumaFromAssetWithFee(_nuAsset,_nuAssetAmount,true);

        // burn amount       
        burnNuAssetFrom(nuAsset,msg.sender,_nuAssetAmount);

        // burn fee
        _output -= amountToBurn;
        minterContract.mint(_recipient,_output);
        emit BurntFee(amountToBurn); // NUMA burnt (not minted)
        return (_output);
    }

   
    function burnAssetToNumaOutput(address _nuAsset,
        uint256 _numaAmount,
        address _recipient
    ) external whenNotPaused returns (uint) {
        //require (tokenPool != address(0),"No nuAsset pool");
        INuAsset nuAsset = INuAsset(_nuAsset);
      
        // burn fee
        uint256 amountWithFee = (_numaAmount*10000) / (10000 - burnAssetFeeBps);

        // how much _nuAssetFrom are needed to get this amount of Numa
        uint256 nuAssetAmount = GetNbOfnuAssetNeededForNuma(_nuAsset,amountWithFee,true);

        // burn amount
        burnNuAssetFrom(nuAsset,msg.sender,nuAssetAmount);
             
        minterContract.mint(_recipient,_numaAmount);
      
        emit BurntFee(amountWithFee - _numaAmount); // NUMA burnt (not minted)
        return (_numaAmount);
    }

   
    

    /**
     * dev
     * notice
     * param {uint256} _amount
     * param {address} _recipient
     */
    function mintAssetFromNumaInput(address _nuAsset,
        uint _numaAmount,
        address _recipient
    ) public whenNotPaused returns (uint256) {
        require(address(oracle) != address(0), "oracle not set");
        require(numaPool != address(0), "uniswap pool not set");


        uint256 assetAmount;
        uint256 numaFee;
        // this function applies fees (amount = amount - fee)
        (assetAmount, numaFee) = getNbOfNuAssetFromNuma(_nuAsset,_numaAmount);

        // burn
        numa.burnFrom(msg.sender, _numaAmount);
        // mint token
        INuAsset nuAsset = INuAsset(_nuAsset);
        // mint token
        mintNuAsset(nuAsset,_recipient,assetAmount);

        emit PrintFee(numaFee);
        return assetAmount;
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
        // --> not applied here
        (uint256 numaEstimatedOutput,uint amountToBurnNotUsed) = getNbOfNumaFromAssetWithFee(_nuAssetFrom,_amountToSwap,false);
        // --> applied here
	    (uint assetAmount, uint numaFee) = getNbOfNuAssetFromNuma(_nuAssetTo,numaEstimatedOutput);

       require(
            (assetAmount) >= _amountOutMinimum,
            "min output"
        );

        // burn asset from
        nuAssetFrom.burnFrom(msg.sender, _amountToSwap);
        emit AssetBurn(_nuAssetFrom, _amountToSwap);

        // mint asset dest
        mintNuAsset(nuAssetTo,_receiver,assetAmount);
        emit PrintFee(numaFee);
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
        // number of numa needed
        (uint256 numaAmount, uint256 fee) = getNbOfNumaNeededAndFee(_nuAssetFrom,_amountToReceive);




        // how much _nuAssetFrom are needed to get this amount of Numa
        uint256 nuAssetAmount = GetNbOfnuAssetNeededForNuma(_nuAssetTo,numaAmount + fee,false);

        require(nuAssetAmount <= _amountInMaximum, "maximum input reached");

        // burn asset from
        nuAssetFrom.burnFrom(msg.sender, nuAssetAmount);
        emit AssetBurn(_nuAssetFrom, nuAssetAmount);

        // mint asset dest
        mintNuAsset(nuAssetTo,_receiver,_amountToReceive);
        emit PrintFee(fee);


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
