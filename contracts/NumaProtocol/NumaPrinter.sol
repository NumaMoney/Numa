// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../Numa.sol";
import "../interfaces/INuAsset.sol";
import "../interfaces/INumaOracle.sol";

import "./NumaMinter.sol";
import "./VaultManager.sol";

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
    VaultManager public vaultManager;
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
    event WhitelistBurnFee(address _address, bool value);
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
        vaultManager = VaultManager(_vaultManagerAddress);
        //INuAssetManager AMinterface = vaultManager.getNuAssetManager();
        //nuAManager = nuAssetManager(address(AMinterface));
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

    function mintNuAsset(INuAsset _asset,address _recipient,uint _amount) internal
    {
        uint currentCF = vaultManager.getGlobalCF();
        require(currentCF > cf_warning,"minting forbidden");

        _asset.mint(_recipient, _amount);
        // accrue interest on lending because synth supply has changed so utilization rates also
        vaultManager.accrueInterests();
        emit AssetMint(address(_asset), _amount);
    }



    /**
     * @dev returns amount of Numa needed and fee to mint an amount of nuAsset
     * @param {uint256} _amount amount we want to mint
     * @return {uint256,uint256} amount of Numa that will be needed and fee to be burnt
     */
    function getNbOfNumaNeededAndFee(address _nuAsset,
        uint256 _amount
    ) public view returns (uint256, uint256) 
    {
        // require(nuAManager.contains(_nuAsset),"bad nuAsset");
        // nuAssetInfo memory info = nuAManager.getNuAssetInfo(_nuAsset);

        uint256 cost = oracle.getNbOfNumaNeeded(
            _amount,
            _nuAsset,
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
        uint256 _amount,bool _applyScaling
    ) public returns (uint256, uint256) 
    {

        // require(nuAManager.contains(_nuAsset),"bad nuAsset");
        // nuAssetInfo memory info = nuAManager.getNuAssetInfo(_nuAsset);

        uint256 _output = oracle.getNbOfNumaFromAsset(
            _amount,
            _nuAsset,
            numaPool
        );

        if (_applyScaling)
        {
            // synth scaling
            uint currentCF = vaultManager.getGlobalCF();
            uint blockTime = block.timestamp;
            if (currentCF < cf_critical)
            {
                // we need to debase
                if (lastScale < BASE_1000)
                {
                    // we are currently in debase/rebase mode

                    if (blockTime > lastBlockTime + deltaDebase)// TODO modulus
                    {
                        // debase again
                        uint ndebase = blockTime/(lastBlockTime + deltaDebase);
                        ndebase = ndebase * debaseValue;
                        if (lastScale > ndebase)
                            lastScale = lastScale - ndebase;
                            if (lastScale < minimumScale)
                                lastScale = minimumScale;
                        else
                            lastScale = minimumScale;
                    } 

                }
                else
                {
                    // start debase
                    lastScale = lastScale - debaseValue;
                }
                lastBlockTime = blockTime;

            }
            else
            {
                if (lastScale < BASE_1000)
                {
                    // need to rebase
                    if (blockTime > lastBlockTime + deltaRebase)
                    {
                        // rebase
                        uint nrebase = blockTime/(lastBlockTime + deltaRebase);
                        nrebase = nrebase * rebaseValue;

                        lastScale = lastScale + nrebase;
                        if (lastScale > BASE_1000)
                            lastScale = BASE_1000;
                    } 
                    lastBlockTime = blockTime;

                }
            }

            // apply scale to synth burn price
            uint scale1000 = lastScale;

            // SECURITY
            if (currentCF < BASE_1000)
            {
                // TODO: do we use vaults balance with debt here?
                uint scaleSecure = currentCF;
                if (scaleSecure < scale1000)
                    scale1000 = scaleSecure;
            }

            // scale
            _output = (_output*scale1000)/BASE_1000;


        }


        // burn fee
        uint256 amountToBurn = (_output * burnAssetFeeBps) / 10000;
        return (_output, amountToBurn);
    }


     /**
     * @dev returns amount of Numa minted and fee to be burnt from an amount of nuAsset
     * @param {uint256} _amount amount we want to burn
     * @return {uint256,uint256} amount of Numa that will be minted and fee to be burnt
     */
    function getNbOfNumaFromAssetWithFeeView(address _nuAsset,
        uint256 _amount,bool _applyScaling
    ) external view returns (uint256, uint256) 
    {

        // require(nuAManager.contains(_nuAsset),"bad nuAsset");
        // nuAssetInfo memory info = nuAManager.getNuAssetInfo(_nuAsset);

        uint256 _output = oracle.getNbOfNumaFromAsset(
            _amount,
            _nuAsset,
            numaPool
        );

        if (_applyScaling)
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

                    if (blockTime > lastBlockTime + deltaDebase)// TODO modulus
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

            // scale
            _output = (_output*scale1000)/BASE_1000;


        }

	
	


        // burn fee
        uint256 amountToBurn = (_output * burnAssetFeeBps) / 10000;
        return (_output, amountToBurn);
    }

    function getNbOfNuAssetFromNuma(address _nuAsset,uint256 _amount
    ) public view returns (uint256, uint256) {

        // require(nuAManager.contains(_nuAsset),"bad nuAsset");
        // nuAssetInfo memory info = nuAManager.getNuAssetInfo(_nuAsset);

        // print fee
        uint256 amountToBurn = (_amount * printAssetFeeBps) / 10000;

        uint256 output = oracle.getNbOfNuAsset(
            _amount - amountToBurn,
            _nuAsset,
            numaPool
        );
        return (output, amountToBurn);
    }

    function GetNbOfnuAssetNeededForNuma(address _nuAsset,
        uint _amount
    ) internal view returns (uint256, uint256) {
        // require(nuAManager.contains(_nuAsset),"bad nuAsset");
        // nuAssetInfo memory info = nuAManager.getNuAssetInfo(_nuAsset);

        uint256 input = oracle.getNbOfAssetneeded(
            _amount,
            _nuAsset,
            numaPool
        );

        uint256 amountToBurn = (_amount * burnAssetFeeBps) / 10000;

        return (input, amountToBurn);
    }

    /**
     * dev burn Numa to mint nuAsset
     * notice contract should be nuAsset minter, and should have allowance from sender to burn Numa
     * param {uint256} _amount amount of nuAsset to mint
     * param {address} _recipient recipient of minted nuAsset tokens
     */
    function mintAssetOutputFromNuma(address _nuAsset,
        uint _amount,
        address _recipient
    ) external whenNotPaused {
        require(address(oracle) != address(0), "oracle not set");
        require(numaPool != address(0), "uniswap pool not set");
        INuAsset nuAsset = INuAsset(_nuAsset);
        

        // how much numa should we burn to get this nuAsset amount
        uint256 numaCost;
        uint256 numaFee;
        (numaCost, numaFee) = getNbOfNumaNeededAndFee(_nuAsset,_amount);

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
    function burnAssetInputToNuma(address _nuAsset,
        uint256 _amount,
        address _recipient
    ) external whenNotPaused returns (uint) {
        //require (tokenPool != address(0),"No nuAsset pool");
        INuAsset nuAsset = INuAsset(_nuAsset);
      

        uint256 _output;
        uint256 amountToBurn;

        (_output, amountToBurn) = getNbOfNumaFromAssetWithFee(_nuAsset,_amount,true);

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

   
    function burnAssetToNumaOutput(address _nuAsset,
        uint256 _amount,
        address _recipient
    ) external whenNotPaused returns (uint) {
        //require (tokenPool != address(0),"No nuAsset pool");
        INuAsset nuAsset = INuAsset(_nuAsset);
      
        // burn fee
        uint256 amountWithFee = (_amount*10000) / (10000 - burnAssetFeeBps);

        // how much _nuAssetFrom are needed to get this amount of Numa
        (uint256 nuAssetAmount, uint256 fee) = GetNbOfnuAssetNeededForNuma(_nuAsset,_amount);


        // burn amount
        nuAsset.burnFrom(msg.sender, nuAssetAmount);

        // // burn fee
        // _output -= amountToBurn;

        // //numa.mint(_recipient, _output);
        // minterContract.mint(_recipient,_output);
        // // accrue interest on lending because synth supply has changed so utilization rates also
        // vaultManager.accrueInterests();
        // emit AssetBurn(address(nuAsset), _amount);
        // emit BurntFee(amountToBurn); // NUMA burnt (not minted)
        // return (_output);
    }

   
    

    /**
     * dev
     * notice
     * param {uint256} _amount
     * param {address} _recipient
     */
    function mintAssetFromNumaInput(address _nuAsset,
        uint _amount,
        address _recipient
    ) public whenNotPaused returns (uint256) {
        require(address(oracle) != address(0), "oracle not set");
        require(numaPool != address(0), "uniswap pool not set");


        uint256 assetAmount;
        uint256 numaFee;
        (assetAmount, numaFee) = getNbOfNuAssetFromNuma(_nuAsset,_amount);

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
        (uint256 numaEstimatedOutput,uint amountToBurn) = getNbOfNumaFromAssetWithFee(_nuAssetFrom,_amountToSwap,false);
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
        (uint256 nuAssetAmount, uint256 fee2) = GetNbOfnuAssetNeededForNuma(_nuAssetTo,numaAmount + fee);

        // we don't use fee2 as we apply fee only one time
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
