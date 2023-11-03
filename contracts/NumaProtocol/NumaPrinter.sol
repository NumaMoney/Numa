// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../Numa.sol";
import "../nuAssets/nuUSD.sol";
import "../interfaces/INumaOracle.sol";

import "hardhat/console.sol";


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

    function setChainlinkFeed(address _chainlinkFeed) external onlyOwner whenNotPaused 
    {
        chainlinkFeed = _chainlinkFeed;
        emit SetChainlinkFeed(_chainlinkFeed); 
    }
    
    function setOracle(INumaOracle _oracle) external onlyOwner whenNotPaused 
    {
        oracle = _oracle;
        emit SetOracle(address(_oracle));
    }

    function setNumaPool(address _numaPool) external onlyOwner whenNotPaused 
    {
        numaPool = _numaPool;
        emit SetNumaPool(address(_numaPool));
    }

    function setTokenPool(address _tokenPool) external onlyOwner whenNotPaused 
    {
        tokenPool = _tokenPool;
        emit SetTokenPool(address(_tokenPool));
    }

    function setPrintAssetFeeBps(uint _printAssetFeeBps) external onlyOwner whenNotPaused 
    {
        require(_printAssetFeeBps <= 10000, "Fee percentage must be 100 or less");
        printAssetFeeBps = _printAssetFeeBps;
        emit PrintAssetFeeBps(_printAssetFeeBps);
    }

    function setBurnAssetFeeBps(uint _burnAssetFeeBps) external onlyOwner whenNotPaused 
    {
        require(_burnAssetFeeBps <= 10000, "Fee percentage must be 100 or less");
        burnAssetFeeBps = _burnAssetFeeBps;
        emit BurnAssetFeeBps(_burnAssetFeeBps);
    }




    function getCost(uint256 _amount) public view returns (uint256,uint256) 
    {
        uint256 cost = oracle.getNbOfNumaNeeded(_amount, chainlinkFeed, numaPool);
        // print fee
        uint256 amountToBurn = (_amount*printAssetFeeBps) / 10000;
        return (cost,amountToBurn);
    }

    // TODO: rename
    function getNumaFromAsset(uint256 _amount) public view returns (uint256,uint256) 
    {
        uint256 _output = oracle.getNbOfNumaFromAsset(_amount, chainlinkFeed, numaPool, tokenPool);
        // burn fee                
        uint256 amountToBurn = (_output*burnAssetFeeBps) / 10000;
        return (_output,amountToBurn);
    }

    // Notes:
    // - Numa should be approved
    // - contract should have the nuAsset minter role
    function mintAssetFromNuma(uint _amount,address recipient) external whenNotPaused 
    {
        require(address(oracle) != address(0),"oracle not set");
        require(numaPool != address(0),"uniswap pool not set");
        // how much numa should we burn to get this nuAsset amount
        uint256 numaCost;
        uint256 numaFee;
        (numaCost,numaFee) = getCost(_amount);

        uint256 depositCost = numaCost + numaFee;

        require(numa.balanceOf(msg.sender) >= depositCost, "Insufficient Balance");
        // burn
        numa.burnFrom(msg.sender, depositCost);
        // mint token
        nuAsset.mint(recipient,_amount);
        emit AssetMint(address(nuAsset), _amount);
        emit PrintFee(numaFee);// NUMA burnt
    }

    // Notes: 
    // - contract should be approved for nuAsset
    // - contract should be Numa minter
    function burnAssetToNuma(uint _amount,address recipient) external whenNotPaused 
    {
        //require (tokenPool != address(0),"No nuAsset pool");
        require(nuAsset.balanceOf(msg.sender) >= _amount, "Insufficient balance");

        uint256 _output;
        uint256 amountToBurn;

        (_output,amountToBurn) = getNumaFromAsset(_amount);

        // burn amount
        nuAsset.burnFrom(msg.sender, _amount);

        // burn fee
        _output -= amountToBurn;

        numa.mint(recipient, _output);
        emit AssetBurn(address(nuAsset), _amount);
        emit BurntFee(amountToBurn);// NUMA burnt (not minted)
    }
}
