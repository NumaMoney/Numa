//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;


import "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "../Numa.sol";
import "../interfaces/IVaultOracle.sol";
import "../interfaces/INuAssetManager.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/INumaVault.sol";

import "hardhat/console.sol";




// - natspec, indexed event, refacto/optim, code review, reverts, 
//      ** pour code review
//            ** numavault and interface
//            ** VaultOracle and interface
//            ** nuAssetManager
//            ** vaultmanager
//            ** la "lib"




// revoir toute la partie oracle, est-ce que tout est ok, est-ce qu'on a des arrondis (cf mon test)
// NumaToToen & TokenToNuma --> + de precision possible? revoir les arrondis dans l'autre sens pour maximiser le Numa price?





// - min/max --> pouruoi? cf ALL QUESTIONS
// - REVIEW CODE / SECURITY



// - estimation gas de nuassetmanager si 200 nuAssets (devra peut etre faire un mock pour accepter 200 x le même)
// --> 3600000 gas si 1 gwei --> 8 dollars --> ca va encore 

// schema d'archi?


// remove console


contract NumaVault is Ownable, ReentrancyGuard, Pausable ,INumaVault
{
    using EnumerableSet for EnumerableSet.AddressSet;

    address payable private FEE_ADDRESS;
    address payable private RWD_ADDRESS;

    uint16 public SELL_FEE = 950;// 5%
    uint16 public BUY_FEE = 950;// 5%
    // 
    NUMA public immutable numa;
    IERC20 public immutable lstToken;
    IVaultOracle public oracle;
    INuAssetManager public nuAssetManager;
    IVaultManager public vaultManager;

    //address[] public removedSupplyAddresses;
    EnumerableSet.AddressSet removedSupplyAddresses;


    uint256 public last_extracttimestamp;
    uint256 public last_lsttokenvalue;
  

    // constants
    uint16 public constant FEE_BASE_1000 = 1000;
    //uint8 public constant FEES = 100;
    uint8 public constant FEES = 10;
    uint constant max_addresses = 50;
    uint constant rwd_threshold = 0.001 ether;
    uint256 immutable decimals;

    // Events
    event SetOracle(address oracle);
    event SetNuAssetManager(address nuAssetManager);
    event SetVaultManager(address vaultManager);
    event Buy(uint256 received, uint256 sent,address receiver);
    event Sell(uint256 sent, uint256 received,address receiver);
    event Fee(uint256 fee,address feeReceiver);
    event SellFeeUpdated(uint256 sellFee);
    event BuyFeeUpdated(uint256 buyFee);
    event FeeAddressUpdated(address feeAddress);
    event RwdAddressUpdated(address rwdAddress);


    constructor(address _numaAddress,address _tokenAddress,uint256 _decimals,address _oracleAddress,address _nuAssetManagerAddress) Ownable(msg.sender)
    {
        numa = NUMA(_numaAddress);
        oracle = IVaultOracle(_oracleAddress);  
        lstToken = IERC20(_tokenAddress);
        decimals = _decimals;
        nuAssetManager = INuAssetManager(_nuAssetManagerAddress);

        // lst rewards
        last_extracttimestamp = block.timestamp;
        last_lsttokenvalue = oracle.getTokenPrice(address(lstToken),decimals);
        
        // paused by default because might be empty
        _pause();
    }

        
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setOracle(address _oracle) external onlyOwner  
    {
        oracle = IVaultOracle(_oracle);
        emit SetOracle(address(_oracle));
    }


    function setNuAssetManager(address _nuAssetManager) external onlyOwner  
    {
        nuAssetManager = INuAssetManager(_nuAssetManager);
        emit SetNuAssetManager(_nuAssetManager);
    }

    function setVaultManager(address _vaultManager) external onlyOwner  
    {
        vaultManager = IVaultManager(_vaultManager);
        emit SetVaultManager(_vaultManager);
    }

    function rewardsValue() public view returns (uint256,uint256)
    {
        require(address(oracle) != address(0),"oracle not set");
        console.logUint(decimals);
        uint currentvalue = oracle.getTokenPrice(address(lstToken),decimals);       
        uint diff = (currentvalue - last_lsttokenvalue);

        //console.logUint(diff);
        uint balance = lstToken.balanceOf(address(this));
          //      console.logUint(balance);

        uint rwd = FullMath.mulDiv(balance,diff, currentvalue);

            //    console.logUint(rwd);

        return (rwd,currentvalue);   
    }

    function extractRewards() external
    {
        require(RWD_ADDRESS != address(0),"reward address not set");
        (uint256 rwd,uint256 currentvalue) = rewardsValue();

        require(rwd > rwd_threshold,"not enough rewards to collect");
        SafeERC20.safeTransfer(IERC20(lstToken),RWD_ADDRESS,rwd);
        last_extracttimestamp = block.timestamp;
        last_lsttokenvalue = currentvalue;

    }
    

    function getRemovedWalletsList() external view returns (address[] memory) {
        return removedSupplyAddresses.values();
    }


    function addToRemovedSupply(address _address) external onlyOwner  
    {
        require (removedSupplyAddresses.length() < max_addresses,"too many wallets in list");
        require(removedSupplyAddresses.add(_address), "already in list");    
    }



    function removeFromRemovedSupply(address _address) external onlyOwner  
    {
        require(removedSupplyAddresses.contains(_address), "not in list");
        removedSupplyAddresses.remove(_address);
    }



    function getEthBalanceAllVAults() public view returns (uint256)
    {
        require (address(vaultManager) != address(0),"vault manager not set");
        return vaultManager.getTotalBalanceEth();
    }

    function getEthBalance() external view returns (uint256)
    {
        require(address(oracle) != address(0),"oracle not set");
        uint balance = lstToken.balanceOf(address(this));
        uint result = oracle.getTokenPrice(address(lstToken),balance);
        return result;   
    }    

    function getTotalSynthValueEth() public view returns (uint256)
    {
        require(address(nuAssetManager) != address(0),"nuAssetManager not set");
        return nuAssetManager.getTotalSynthValueEth();
    }

    function getNumaSupply() public view returns (uint)
    {
        uint circulatingNuma = numa.totalSupply(); 
      
        uint256 nbWalletsToRemove = removedSupplyAddresses.length();
        require(nbWalletsToRemove < max_addresses,"too many wallets to remove from supply");
        for (uint256 i = 0;i < nbWalletsToRemove;i++)
        {
            uint bal = numa.balanceOf(removedSupplyAddresses.at(i));
            circulatingNuma -= bal;
        }
        return circulatingNuma;
    }


    function TokenToNuma(uint _inputAmount) public view returns (uint256) 
    {

        require(address(oracle) != address(0),"oracle not set");

        uint256 EthValue = oracle.getTokenPrice(address(lstToken),_inputAmount);
        console.log("eth value");
        console.logUint(EthValue);


        uint synthValueInEth = getTotalSynthValueEth();
        console.log("synth value");
        console.logUint(synthValueInEth);
        uint circulatingNuma = getNumaSupply();
        console.log("supply value");
        console.logUint(circulatingNuma);
      
        uint EthBalance = getEthBalanceAllVAults();
        console.log("Eth full balance");
        console.logUint(EthBalance);
        require(EthBalance > synthValueInEth,"vault is empty or synth value is too big");
        uint result = FullMath.mulDiv(EthValue, circulatingNuma, EthBalance - synthValueInEth);
         console.logUint(result);
        return result;

    }

    function NumaToToken(uint _inputAmount) public view returns (uint256) 
    {
        require(address(oracle) != address(0),"oracle not set");
        (uint256 price,uint256 decimalPrecision,bool ethLeftSide) = oracle.getTokenPrice(address(lstToken));

       
        uint synthValueInEth = getTotalSynthValueEth();
        uint circulatingNuma = getNumaSupply();
        uint EthBalance = getEthBalanceAllVAults();
        console.log("balance");
        console.logUint(EthBalance);

        console.log("price");
        console.logUint(price);


        require(EthBalance > synthValueInEth,"vault is empty or synth value is too big");
        require(circulatingNuma > 0,"no numa in circulation");
        uint result;
        if (ethLeftSide) 
        {
            console.log("here");
            result = FullMath.mulDiv(FullMath.mulDiv(_inputAmount,EthBalance - synthValueInEth, circulatingNuma),price,10**decimalPrecision);
        }
        else 
        {
            console.log("there");
            result = FullMath.mulDiv(FullMath.mulDiv(_inputAmount,EthBalance - synthValueInEth, circulatingNuma),10**decimalPrecision,price);
        }

        console.log("dbg1");
        console.logUint(_inputAmount);

        console.log("dbg2");
        console.logUint(EthBalance - synthValueInEth);

        console.log("result");
        console.logUint(result);
        return result;

    }


    // Buy Numa
    function buy(uint _inputAmount,address _receiver) external payable nonReentrant whenNotPaused 
    {
        uint256 numaAmount = TokenToNuma(_inputAmount);
        require(numaAmount > 0,"amount of numa is <= 0");

        // transfer token
        SafeERC20.safeTransferFrom(lstToken,msg.sender,address(this),_inputAmount);

        numa.mint(_receiver, (numaAmount* BUY_FEE) / FEE_BASE_1000);
        emit Buy( (numaAmount* BUY_FEE) / FEE_BASE_1000, _inputAmount,_receiver);
        // fee
        if (FEE_ADDRESS != address(0x0))
        {
            uint256 feeAmount = FEES*_inputAmount / FEE_BASE_1000;
            SafeERC20.safeTransfer(lstToken,FEE_ADDRESS,feeAmount);
            emit Fee(feeAmount,FEE_ADDRESS);
        }

    }
    
  

    function sell(uint256 _numaAmount,address _receiver) external nonReentrant whenNotPaused
    {
    
        // Total Eth to be sent
        uint256 tokenAmount = NumaToToken(_numaAmount);
        require(tokenAmount > 0,"amount of token is <=0");
        require(lstToken.balanceOf(address(this)) >= tokenAmount,"not enough liquidity in vault");
       
        // Burn of Numa
        numa.burnFrom(msg.sender, _numaAmount);

        // Payment to sender
        SafeERC20.safeTransfer(lstToken,_receiver,(tokenAmount * SELL_FEE) / FEE_BASE_1000);
        emit Sell(_numaAmount, (tokenAmount * SELL_FEE) / FEE_BASE_1000,_receiver);
        // fee
        if (FEE_ADDRESS != address(0x0))
        {
            uint256 feeAmount = FEES*tokenAmount / FEE_BASE_1000;
            SafeERC20.safeTransfer(IERC20(lstToken),FEE_ADDRESS,feeAmount);
            emit Fee(feeAmount,FEE_ADDRESS);
        }


    }

    function setRwdAddress(address _address) external onlyOwner {
        require(_address != address(0x0));
        RWD_ADDRESS = payable(_address);
        emit RwdAddressUpdated(_address);
    }


    function setFeeAddress(address _address) external onlyOwner {
        require(_address != address(0x0));
        FEE_ADDRESS = payable(_address);
        emit FeeAddressUpdated(_address);
    }

    function setSellFee(uint16 fee) external onlyOwner {
        require(fee <= 969);// TODO: confirm these limitations
        require(fee > SELL_FEE);
        SELL_FEE = fee;
        emit SellFeeUpdated(fee);
    }

    function setBuyFee(uint16 fee) external onlyOwner {
        require(fee <= 969 && fee >= 10);// TODO: confirm these limitations
        BUY_FEE = fee;
        emit BuyFeeUpdated(fee);
    }

    //utils
    function getBuyNuma(uint256 _amount) external view returns (uint256) 
    {
        uint256 numaAmount = TokenToNuma(_amount);
        return (numaAmount* BUY_FEE) / FEE_BASE_1000;
    }

    function getSellNuma(uint256 _amount) external view returns (uint256) 
    {
        uint256 tokenAmount = NumaToToken(_amount);
        return (tokenAmount * SELL_FEE) / FEE_BASE_1000;
    }


    function withdrawToken(address _tokenAddress,uint256 _amount) external onlyOwner
    {
        SafeERC20.safeTransfer(IERC20(_tokenAddress),msg.sender,_amount);
    }


}