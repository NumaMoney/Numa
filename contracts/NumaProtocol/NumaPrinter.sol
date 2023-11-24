// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../Numa.sol";
import "../nuAssets/nuUSD.sol";
import "../interfaces/INumaOracle.sol";


/// @title NumaPrinter
/// @notice Responsible for minting/burning Numa for nuAsset
/// @dev 
contract NumaPrinter is Pausable, Ownable
{

    NUMA public immutable numa;
    INuAsset public immutable nuAsset;
    //
    address public numaPool;
    address public tokenPool;
    //
    INumaOracle public oracle;
    address public chainlinkFeed;
    // 
    uint public printAssetFeeBps;
    uint public burnAssetFeeBps;
    //
    event SetOracle(address oracle);
    event SetFlexFeeThreshold(uint256 _threshold);
    event SetChainlinkFeed(address _chainlink);
    event SetNumaPool(address _pool);
    event SetTokenPool(address _pool);
    event AssetMint(address _asset,uint _amount);
    event AssetBurn(address _asset,uint _amount);
    event PrintAssetFeeBps(uint _newfee);
    event BurnAssetFeeBps(uint _newfee);
    event BurntFee(uint _fee);
    event PrintFee(uint _fee);

    constructor(address _numaAddress,address _nuAssetAddress,address _numaPool,INumaOracle _oracle,address _chainlinkFeed) Ownable(msg.sender)
    {
        numa = NUMA(_numaAddress);
        nuAsset = INuAsset(_nuAssetAddress);
        numaPool = _numaPool;
        oracle = _oracle;
        chainlinkFeed = _chainlinkFeed;
    }

    
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */   
    function setChainlinkFeed(address _chainlinkFeed) external onlyOwner  
    {
        chainlinkFeed = _chainlinkFeed;
        emit SetChainlinkFeed(_chainlinkFeed); 
    }
    
    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */       
    function setOracle(INumaOracle _oracle) external onlyOwner  
    {
        oracle = _oracle;
        emit SetOracle(address(_oracle));
    }

    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */   
    function setNumaPool(address _numaPool) external onlyOwner  
    {
        numaPool = _numaPool;
        emit SetNumaPool(address(_numaPool));
    }

    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */   
    function setTokenPool(address _tokenPool) external onlyOwner  
    {
        tokenPool = _tokenPool;
        emit SetTokenPool(address(_tokenPool));
    }

    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */   
    function setPrintAssetFeeBps(uint _printAssetFeeBps) external onlyOwner  
    {
        require(_printAssetFeeBps <= 10000, "Fee percentage must be 100 or less");
        printAssetFeeBps = _printAssetFeeBps;
        emit PrintAssetFeeBps(_printAssetFeeBps);
    }

    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */   
    function setBurnAssetFeeBps(uint _burnAssetFeeBps) external onlyOwner  
    {
        require(_burnAssetFeeBps <= 10000, "Fee percentage must be 100 or less");
        burnAssetFeeBps = _burnAssetFeeBps;
        emit BurnAssetFeeBps(_burnAssetFeeBps);
    }



    /**
     * @dev returns amount of Numa needed and fee to mint an amount of nuAsset
     * @param {uint256} _amount amount we want to mint
     * @return {uint256,uint256} amount of Numa that will be needed and fee to be burnt
     */
    function getNbOfNumaNeededWithFee(uint256 _amount) public view returns (uint256,uint256) 
    {
        uint256 cost = oracle.getNbOfNumaNeeded(_amount, chainlinkFeed, numaPool);
        // print fee
        uint256 amountToBurn = (cost*printAssetFeeBps) / 10000;
        return (cost,amountToBurn);
    }

    /**
     * @dev returns amount of Numa minted and fee to be burnt from an amount of nuAsset
     * @param {uint256} _amount amount we want to burn
     * @return {uint256,uint256} amount of Numa that will be minted and fee to be burnt
     */
    function getNbOfNumaFromAssetWithFee(uint256 _amount) public view returns (uint256,uint256) 
    {
        uint256 _output = oracle.getNbOfNumaFromAsset(_amount, chainlinkFeed, numaPool, tokenPool);
        // burn fee                
        uint256 amountToBurn = (_output*burnAssetFeeBps) / 10000;
        return (_output,amountToBurn);
    }


    /**
     * dev burn Numa to mint nuAsset
     * notice contract should be nuAsset minter, and should have allowance from sender to burn Numa
     * param {uint256} _amount amount of nuAsset to mint
     * param {address} _recipient recipient of minted nuAsset tokens
     */
    function mintAssetFromNuma(uint _amount,address _recipient) external whenNotPaused 
    {
        require(address(oracle) != address(0),"oracle not set");
        require(numaPool != address(0),"uniswap pool not set");
        // how much numa should we burn to get this nuAsset amount
        uint256 numaCost;
        uint256 numaFee;
        (numaCost,numaFee) = getNbOfNumaNeededWithFee(_amount);

        uint256 depositCost = numaCost + numaFee;

        require(numa.balanceOf(msg.sender) >= depositCost, "Insufficient Balance");
        // burn
        numa.burnFrom(msg.sender, depositCost);
        // mint token
        nuAsset.mint(_recipient,_amount);
        emit AssetMint(address(nuAsset), _amount);
        emit PrintFee(numaFee);// NUMA burnt
    }

    /**
     * dev burn nuAsset to mint Numa
     * notice contract should be Numa minter, and should have allowance from sender to burn nuAsset
     * param {uint256} _amount amount of nuAsset that we want to burn
     * param {address} _recipient recipient of minted Numa tokens
     */   
    function burnAssetToNuma(uint256 _amount,address _recipient) external whenNotPaused 
    {
        //require (tokenPool != address(0),"No nuAsset pool");
        require(nuAsset.balanceOf(msg.sender) >= _amount, "Insufficient balance");

        uint256 _output;
        uint256 amountToBurn;

        (_output,amountToBurn) = getNbOfNumaFromAssetWithFee(_amount);

        // burn amount
        nuAsset.burnFrom(msg.sender, _amount);

        // burn fee
        _output -= amountToBurn;

        numa.mint(_recipient, _output);
        emit AssetBurn(address(nuAsset), _amount);
        emit BurntFee(amountToBurn);// NUMA burnt (not minted)
    }
}