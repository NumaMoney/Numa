//SPDX-License-Identifier: MIT
pragma solidity 0.8.16;


import "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV2V3Interface.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

import "../Numa.sol";
import "./NumaOracle.sol";


// TODO:
// - finir contract
//      - finir les view functions de prix
//      - withdraw functions
//      - events
//      - j'utilise ceci ou pas: ETHinWEI (j'ai du 1e18 dans le code)
// - revoir les formules de prix et si possible mettre left side et tout dans le contrat oracle
// - synth value
// - extract rewards
// - natspec, indexed event, refacto/optim, view functions
// - TESTS


contract NumaVault Ownable, ReentrancyGuard, Pausable 
{

    address payable private FEE_ADDRESS;
    uint16 public SELL_FEE = 950;// 5%
    uint16 public BUY_FEE = 950;// 5%
    // 
    NUMA public immutable numa;
    IVaultOracle oracle;
    address whitelistAddress[];
    address supportedTokens[];
    //
    uint16 public constant FEE_BASE_1000 = 1000;
    uint8 public constant FEES = 100;
    uint128 public constant ETHinWEI = 1 * 10 ** 18;
    uint constant max_addresses = 50;
    uint constant max_tokens = 10;

    // Events
    event SetOracle(address oracle);
    event Price(uint256 time, uint256 received, uint256 sent);
    event SellFeeUpdated(uint256 sellFee);
    event buyFeeUpdated(uint256 buyFee);

    constructor(address numaAddress,oracleAddress) {
        numa = NUMA(_numaAddress);
        oracle = IVaultOracle(numaOracleAddress);      
        _pause();
       
    }

    
    function setOracle(address _oracle) external onlyOwner  
    {
        oracle = IVaultOracle(_oracle);
        emit SetOracle(address(_oracle));
    }




    function isInWhitelist(address _walletAddress) public view returns (bool,uint)
    {
        int nbWallets = whitelistAddress.length();
        require(nbWallets <= max_addresses,"too many wallets in list");
        for (int i = 0;i < nbWallets)
        {
            if (whitelistAddress[i] == _walletAddress)
            {
                return (true,i);
            }
        }
        return (false,);

    }

    function whitelistAddress(address _address) external onlyOwner  
    {
        (bool exist,) = isInWhitelist(_address);
        require(!exist);
        require (whitelistAddress.length() < max_addresses);
        whitelistAddress.push(_address);
    }

    function unwhitelistAddress(address _address) external onlyOwner  
    {
        (bool exist,uint index) = isInWhitelist(_address);
        require(exist);
        // whitelistAddress[index] = whitelistAddress[whitelistAddress.length - 1];
        // whitelistAddress.pop();
        unwhitelistAddress(index);


    }

    function unwhitelistAddress(uint _index) public onlyOwner  
    {
        require(_index < whitelistAddress.length, "index out of bound");  
        whitelistAddress[_index] = whitelistAddress[whitelistAddress.length - 1];
        whitelistAddress.pop();
    }



    function isSupportedToken(address _tokenAddress) public view returns (bool,uint)
    {
        int nbTokens = supportedTokens.length();
        require(nbTokens <= max_tokens,"too many tokens in list");
        for (int i = 0;i < nbTokens)
        {
            if (supportedTokens[i] == _tokenAddress)
            {
                return (true,i);
            }
        }
        return (false,);

    }

    function addSupportedToken(address _tokenAddress) external onlyOwner  
    {
        (bool exist,) = isSupportedToken(_tokenAddress);
        require(!exist);
        require (supportedTokens.length() < max_tokens);
        supportedTokens.push(_tokenAddress);
    }

    function removeSupportedToken(address _tokenAddress) external onlyOwner  
    {
        (bool exist,uint index) = isSupportedToken(_tokenAddress);
        require(exist);
        // whitelistAddress[index] = whitelistAddress[whitelistAddress.length - 1];
        // whitelistAddress.pop();
        removeSupportedToken(index);


    }

    function removeSupportedToken(uint _index) public onlyOwner  
    {
        require(_index < supportedTokens.length, "index out of bound");  
        supportedTokens[_index] = supportedTokens[whitelistAddress.length - 1];
        supportedTokens.pop();
    }

    
    // added code
    function pause() external onlyOwner {
        _pause();
    }

    // added code
    function unpause() external onlyOwner {
        _unpause();
    }
    

    function getEthBalance() public view return (uint256)
    {
        require(oracle != address(0),"oracle not set");
        int nbTokens = supportedTokens.length();
        require(nbTokens <= max_tokens,"too many tokens in list");
        uint totalEthValue;
        for (int i = 0;i < nbTokens)
        {
            (uint256 price,uint256 decimalPrecision,bool ethLeftSide) = oracle.getTokenPrice(supportedTokens[i]);
            //if ETH is on the left side of the fraction in the price feed
            if (ethLeftSide) 
            {
                totalEthValue += FullMath.mulDiv(inputAmount, price, 10**decimalPrecision);
            }
            else 
            {
                totalEthValue += FullMath.mulDiv(inputAmount, 10**decimalPrecision, price);
            }

        }
    }

    function getTotalSynthValueEth() public view return (uint256)
    {
        // TODO
        return 0;
    }


    function TokenToNuma(address _tokenAddress,uint _inputAmount) public view returns (uint256) 
    {

        require(oracle != address(0),"oracle not set");
        (uint256 price,uint256 decimalPrecision,bool ethLeftSide) = oracle.getTokenPrice(_tokenAddress);
        uint256 EthValue;

        //if ETH is on the left side of the fraction in the price feed
        if (ethLeftSide) 
        {
            EthValue = FullMath.mulDiv(_inputAmount, price, 10**decimalPrecision);
        }
        else 
        {
            EthValue = FullMath.mulDiv(_inputAmount, 10**decimalPrecision, price);
        }


        uint synthValueInEth = getTotalSynthValueEth();
        uint circulatingNuma = numa.totalSupply(); 
        int nbWalletsToRemove = removedAddressFromSupply.length();
        require(nbWalletsToRemove < max_addresses,"too many wallets to remove from supply");
        for (int i = 0;i < nbWalletsToRemove)
        {
            uint bal = numa.balanceOf(removedAddressFromSupply[i]);
            circulatingNuma -= bal;
        }
        uint EthBalance = getEthBalance();
        uint result = FullMath.mulDiv(EthValue, circulating_numa, EthBalance - synth_value);
        return result;

    }
    function NumaToToken(address _tokenAddress,uint _inputAmount) public view returns (uint256) 
    {
        require(oracle != address(0),"oracle not set");
        (uint256 price,uint256 decimalPrecision,bool ethLeftSide) = oracle.getTokenPrice(_tokenAddress);

       
        uint synthValueInEth = getTotalSynthValueEth();
        uint circulatingNuma = numa.totalSupply();
        int nbWalletsToRemove = removedAddressFromSupply.length();
        require(nbWalletsToRemove < max_addresses,"too many wallets to remove from supply");
        for (int i = 0;i < nbWalletsToRemove)
        {
            uint bal = numa.balanceOf(removedAddressFromSupply[i]);
            circulatingNuma -= bal;
        }
        uint EthBalance = getEthBalance();


        uint result;
        if (ethLeftSide) 
        {
            result = FullMath.mulDiv(FullMath.mulDiv(inputAmount,EthBalance - synthValueInEth, circulating_numa),10**decimalPrecision,price*1e18);
        }
        else 
        {
            result = FullMath.mulDiv(FullMath.mulDiv(inputAmount,EthBalance - synthValueInEth, circulating_numa),price,1e18*10**decimalPrecision);
        }
        return result;

    }


    // Buy Numa
    function buy(address _inputToken,uint _inputAmount,address _receiver) external payable nonReentrant whenNotPaused 
    {
        uint256 numaAmount = TokenToNuma(inputAmount);
        require(numaAmount > 0,"amount of numa is <=0");

        // transfer token
        SafeERC20.safeTransferFrom(IERC20(_inputToken),msg.sender,address(this),_inputAmount);

        numa.mint(receiver, (numaAmount* BUY_FEE) / FEE_BASE_1000);
        // 
        // TODO: event (x2?)
        // fee
        SafeERC20.safeTransfer(IERC20(_inputToken),FEE_ADDRESS,_inputAmount/FEES);
        // emit Price(block.timestamp, jay, msg.value);
    }
    
  

    function sell(address _outTokenAddress,uint256 _numaAmount,address _receiver) external nonReentrant whenNotPaused
    {
    
        // Total Eth to be sent
        uint256 tokenAmount = NumaToToken(numaAmount);
        require(tokenAmount > 0,"amount of token is <=0");
        // TODO: check balance is enough
        // Burn of Numa
        numa.burn(msg.sender, numaAmount);

        // Payment to sender
        SafeERC20.safeTransfer(IERC20(_inputToken),_receiver,(tokenAmount * SELL_FEE) / FEE_BASE_1000);
        // Team fee
        SafeERC20.safeTransfer(IERC20(_inputToken),FEE_ADDRESS,tokenAmount / FEES);


        // TODO: event x 2?
        //emit Price(block.timestamp, jay, eth);
    }




    function setFeeAddress(address _address) external onlyOwner {
        require(_address != address(0x0));
        FEE_ADDRESS = payable(_address);
        // TODO: event
    }

    function setSellFee(uint16 amount) external onlyOwner {
        require(amount <= 969);
        require(amount > SELL_FEE);
        SELL_FEE = amount;
        emit SellFeeUpdated(amount);
    }

    function setBuyFee(uint16 amount) external onlyOwner {
        require(amount <= 969 && amount >= 10);
        BUY_FEE = amount;
        emit buyFeeUpdated(amount);
    }

    //utils
    function getBuyNuma(uint256 amount) external view returns (uint256) {
        return
            (amount * (totalSupply()) * (BUY_FEE)) /
            (address(this).balance) /
            (FEE_BASE_1000);
    }

    function getSellNuma(uint256 amount) external view returns (uint256) {
        return
            ((amount * address(this).balance) * (SELL_FEE)) /
            (totalSupply()) /
            (FEE_BASE_1000);
    }


    function withdrawToken(address _tokenAddress,uint256 _amount) external OnlyOwner
    {

    }

    function withdrawEth(uint256 _amount) external OnlyOwner
    {
        
    }




    receive() external payable {}

    fallback() external payable {}

    // TODO: withdraw LST -> dangerous if owner is compromised, but needed if we need to migrate the vault
    // withdraw ou allowance (pour permettre d'utiliser les LST si necessaire, les placer)
}