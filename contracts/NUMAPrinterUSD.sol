// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Numa.sol";
import "./nuAssets/nuUSD.sol";
import "./interfaces/IOracle.sol";

// TODO
// ** Features
// - Burn $NUMA to mint either $nuUSD or $nuBTC

// - Burn either $nuUSD or $nuBTC to mint $NUMA 
// - More currencies will come in the future, so we need to be prepared for that
// - Chainlink should be used as an oracle: TODO/Q Drew: only for usd/btc, as for numa wil will use univ3?
// - Charge 0.3% fee for any minting transaction, paid in either nu money or $NUMA, depending on which token is being burnt. The tokens that are collected as fees should be permanently burnt. 


// ROADMAP/TODOs

// ** make it work with 1 currency, test it
// ** test with mockup chainlink & uniswap V3
// ** test with real chainlink & uniswap V3 on testnet
// ** rename && redesign & refacto - see other contracts similar


// ** many currencies

// ** see other contracts that do that kind of things
// ** how to be generic nuUSD, nuBTC, other currencies: rename core and deploy 1 per currency?
// ** see uniswapv3: how to migrate, how to test?
// ** Naming
// ** authorisations
// ** design, base class comme offshift?
// ** voir les risque flashloans etc... uniswap v3 utilisation
// ** events
// ** voir les test de offshift pour m'en inspirer
// ** voir le code de jarvis pour m'en inspirer, design et naming + les familles de tokens (mintable, burnable etc...)


// TODOs:
// - nuasset inherit same contract

// Questions:
// ** nuAssets: upgradeable? permit?, owner?


// End 2 End & dev resources
// https://blog.chain.link/how-to-use-chainlink-price-feeds-on-arbitrum/
// https://www.youtube.com/watch?v=SeiaiiviEhM&ab_channel=BlockmanCodes
// https://blog.chain.link/testing-chainlink-smart-contracts/ --> faudra mocker sur local fork ou utiliser sepolia

contract NUMAPrinterUSD is Pausable, Ownable
{
    // numa token
    // paused
    // oracle oracleactive
    
    NUMA numa;
    nuUSD nUsd;
    // TODO: see what's necessary here
    IOracle public oracle;
    address public numaPool;// TODO: input
    // address public tokenPool;
    address public chainlinkFeed;// TODO input
    // bool public oracleActive = true;

    constructor(address _numaAddress,address _nuUSDAddress,IOracle _oracle) Ownable(msg.sender)
    {
        numa = NUMA(_numaAddress);
        nUsd = nuUSD(_nuUSDAddress);
        oracle = _oracle;
    }
    
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function setOracle(IOracle _oracle) external onlyOwner whenNotPaused 
    {
        oracle = _oracle;
        //emit SetOracle(address(_oracle));
    }


    function getCost(uint256 _amount) public view returns (uint256) 
    {
        //if (!oracleActive) return _amount;// TODO: why oracleActive and why returning amount
        return oracle.getCost(_amount, chainlinkFeed, numaPool);
    }

    // TODO: denomination? --> understand, for now I use _amount
    // NUMA should be approced before calling this functio
    function _numaToAsset(uint _amount) internal whenNotPaused 
    {
        //uint256 depositCost = getCost(denomination);
        uint256 depositCost = getCost(_amount);
        require(numa.balanceOf(msg.sender) >= depositCost, "Insufficient Balance");// todo custom errors
        //numa.burn(msg.sender, depositCost);// TODO: should we have all rights to burn or should we keep approve?
        numa.burnFrom(msg.sender, depositCost);


        // mint token
        nUsd.mint(msg.sender,_amount);
    }

    function _nuAssetToNuma(uint _amount) internal whenNotPaused 
    {

    }

    
  function _nuAssetToNuma(uint256 _amount, address _recipient) public whenNotPaused {// cf simpleShift
        // require(token.balanceOf(msg.sender) >= _amount, "Insufficient balance");
        // uint256 _output = oracle.getCostSimpleShift(_amount, chainlinkFeed, xftPool, tokenPool);
        // token.burn(msg.sender, _amount);
        // xft.mint(_recipient, _output);
        // emit SimpleShift(_amount, _recipient, _output);
  }
}
