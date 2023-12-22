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



contract NumaVault is Ownable, ReentrancyGuard, Pausable ,INumaVault
{
    using EnumerableSet for EnumerableSet.AddressSet;

    address payable private FEE_ADDRESS;
    address payable private RWD_ADDRESS;

    uint16 public SELL_FEE = 950;// 5%
    uint16 public BUY_FEE = 950;// 5%
    uint8 public  FEES = 10; //1%




    // 
    NUMA public immutable numa;
    IERC20 public immutable lstToken;
    IVaultOracle public oracle;
    INuAssetManager public nuAssetManager;
    IVaultManager public vaultManager;
    EnumerableSet.AddressSet removedSupplyAddresses;


    uint256 public decayingDenominator;
    uint256 public decaytimestamp;
    bool public isdecaying;

    uint256 public last_extracttimestamp;
    uint256 public last_lsttokenvalue;
  

    // constants
    uint256 public constant MIN = 1000;
    uint16 public constant DECAY_BASE_100 = 100;
    uint16 public constant FEE_BASE_1000 = 1000;
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
    event FeeUpdated(uint256 Fee);
    event FeeAddressUpdated(address feeAddress);
    event RwdAddressUpdated(address rwdAddress);


    constructor(address _numaAddress,address _tokenAddress,uint256 _decimals,address _oracleAddress,address _nuAssetManagerAddress,uint256 _decayingDenominator) Ownable(msg.sender)
    {
        numa = NUMA(_numaAddress);
        oracle = IVaultOracle(_oracleAddress);  
        lstToken = IERC20(_tokenAddress);
        decimals = _decimals;
        nuAssetManager = INuAssetManager(_nuAssetManagerAddress);

        // lst rewards
        last_extracttimestamp = block.timestamp;
        last_lsttokenvalue = oracle.getTokenPrice(address(lstToken),decimals);
        
        decayingDenominator = _decayingDenominator;
        isdecaying = false;
        // paused by default because might be empty
        _pause();
    }


    /**
     * @dev Starts the decaying period
     * @notice decayingDenominator will go from initial value to 1 in 90 days
     */
    function startDecaying() external onlyOwner
    {
        isdecaying = true;
        decaytimestamp = block.timestamp;
    }

    /**
     * @dev Current decaying denominator (from initial value to 1 at the end of the period)
     * @return {uint256} current decaying denominator 
     */
    function getDecayDenominator() internal view returns (uint256)
    {
        if (isdecaying)
        {
            uint256 currenttimestamp = block.timestamp;
            uint256 delta_s = currenttimestamp - decaytimestamp;
            // should go down to 1 during 90 days
            uint256 period = 90 * 1 days;
            uint256 decay_factor_1000 = (1000*delta_s) / period;

            if (decay_factor_1000 >= 1000)
            {
                return DECAY_BASE_100;
            }
            uint256 currentDecay_1000 = decay_factor_1000 * DECAY_BASE_100 + (1000 - decay_factor_1000) * decayingDenominator;
            return currentDecay_1000/1000;
        }
        else
        {
            return DECAY_BASE_100;
        }

    }



    /**
     * @dev pause buying and selling from vault
     */  
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev unpause buying and selling from vault
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev set the IVaultOracle address (used to compute token price in Eth)
     */
    function setOracle(address _oracle) external onlyOwner  
    {
        oracle = IVaultOracle(_oracle);
        emit SetOracle(address(_oracle));
    }

    /**
     * @dev set the INuAssetManager address (used to compute synth value in Eth)
     */
    function setNuAssetManager(address _nuAssetManager) external onlyOwner  
    {
        nuAssetManager = INuAssetManager(_nuAssetManager);
        emit SetNuAssetManager(_nuAssetManager);
    }


    /**
     * @dev set the IVaultManager address (used to total Eth balance of all vaults)
     */
    function setVaultManager(address _vaultManager) external onlyOwner  
    {
        vaultManager = IVaultManager(_vaultManager);
        emit SetVaultManager(_vaultManager);
    }


    /**
     * @dev Set Rwd address
     */
    function setRwdAddress(address _address) external onlyOwner {
        require(_address != address(0x0));
        RWD_ADDRESS = payable(_address);
        emit RwdAddressUpdated(_address);
    }

    /**
     * @dev Set Fee address
     */
    function setFeeAddress(address _address) external onlyOwner {
        require(_address != address(0x0));
        FEE_ADDRESS = payable(_address);
        emit FeeAddressUpdated(_address);
    }


    /**
     * @dev Set Sell fee percentage 
     */
    function setSellFee(uint16 fee) external onlyOwner {
        require(fee > SELL_FEE);
        SELL_FEE = fee;
        emit SellFeeUpdated(fee);
    }

    /**
     * @dev Set Buy fee percentage 
     */
    function setBuyFee(uint16 fee) external onlyOwner {
        BUY_FEE = fee;
        emit BuyFeeUpdated(fee);
    }

    /**
     * @dev Set Fee percentage 
     */
    function setFee(uint8 fees) external onlyOwner {
        FEES = fees;
        emit FeeUpdated(fees);
    }


    /**
     * @dev returns the estimated rewards value of lst token
     */
    function rewardsValue() public view returns (uint256,uint256)
    {
        require(address(oracle) != address(0),"oracle not set");        
        uint currentvalue = oracle.getTokenPrice(address(lstToken),decimals);       
        uint diff = (currentvalue - last_lsttokenvalue);
        uint balance = lstToken.balanceOf(address(this));
        uint rwd = FullMath.mulDiv(balance,diff, currentvalue);
        return (rwd,currentvalue);   
    }

    /**
     * @dev transfers rewards to RWD_ADDRESS and updates reference price
     */
    function extractRewards() external
    {
        require(RWD_ADDRESS != address(0),"reward address not set");
        (uint256 rwd,uint256 currentvalue) = rewardsValue();

        require(rwd > rwd_threshold,"not enough rewards to collect");
        SafeERC20.safeTransfer(IERC20(lstToken),RWD_ADDRESS,rwd);
        last_extracttimestamp = block.timestamp;
        last_lsttokenvalue = currentvalue;
    }
    
    /**
     * @dev list of wallets whose numa balance is removed from total supply
     */
    function getRemovedWalletsList() external view returns (address[] memory) {
        return removedSupplyAddresses.values();
    }

    /**
     * @dev adds a wallet to wallets whose numa balance is removed from total supply
     */
    function addToRemovedSupply(address _address) external onlyOwner  
    {
        require (removedSupplyAddresses.length() < max_addresses,"too many wallets in list");
        require(removedSupplyAddresses.add(_address), "already in list");    
    }


    /**
     * @dev removes a wallet to wallets whose numa balance is removed from total supply
     */
    function removeFromRemovedSupply(address _address) external onlyOwner  
    {
        require(removedSupplyAddresses.contains(_address), "not in list");
        removedSupplyAddresses.remove(_address);
    }


    /**
     * @dev sum of balances of all vaults in Eth
     */
    function getEthBalanceAllVAults() public view returns (uint256)
    {
        require (address(vaultManager) != address(0),"vault manager not set");
        return vaultManager.getTotalBalanceEth();
    }

    /**
     * @dev vaults' balance in Eth
     */
    function getEthBalance() external view returns (uint256)
    {
        require(address(oracle) != address(0),"oracle not set");
        uint balance = lstToken.balanceOf(address(this));
        uint result = oracle.getTokenPrice(address(lstToken),balance);
        return result;   
    }    

    /**
     * @dev Total synth value in Eth
     */
    function getTotalSynthValueEth() public view returns (uint256)
    {
        require(address(nuAssetManager) != address(0),"nuAssetManager not set");
        return nuAssetManager.getTotalSynthValueEth();
    }

    /**
     * @dev total numa supply without wallet's list balances
     */
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

    /**
     * @dev How many Numas from token amount
     */
    function TokenToNuma(uint _inputAmount) public view returns (uint256) 
    {

        require(address(oracle) != address(0),"oracle not set");

        uint256 EthValue = oracle.getTokenPrice(address(lstToken),_inputAmount);
        uint synthValueInEth = getTotalSynthValueEth();
        uint circulatingNuma = getNumaSupply();
      
        uint EthBalance = getEthBalanceAllVAults();
        require(EthBalance > synthValueInEth,"vault is empty or synth value is too big");
        uint256 decaydenom = getDecayDenominator();
        uint result = FullMath.mulDiv(EthValue, DECAY_BASE_100* circulatingNuma, decaydenom*(EthBalance - synthValueInEth));

        return result;
    }

    /**
     * @dev How many tokens from numa amount
     */
    function NumaToToken(uint _inputAmount) public view returns (uint256) 
    {
        require(address(oracle) != address(0),"oracle not set");
        (uint256 price,uint256 decimalPrecision,bool ethLeftSide) = oracle.getTokenPrice(address(lstToken));

       
        uint synthValueInEth = getTotalSynthValueEth();
        uint circulatingNuma = getNumaSupply();
        uint EthBalance = getEthBalanceAllVAults();
  
        require(EthBalance > synthValueInEth,"vault is empty or synth value is too big");
        require(circulatingNuma > 0,"no numa in circulation");
        uint result;
        uint256 decaydenom = getDecayDenominator();
        if (ethLeftSide) 
        {
            result = FullMath.mulDiv(FullMath.mulDiv(decaydenom*_inputAmount,EthBalance - synthValueInEth, DECAY_BASE_100*circulatingNuma),price,10**decimalPrecision);
        }
        else 
        {
            result = FullMath.mulDiv(FullMath.mulDiv(decaydenom*_inputAmount,EthBalance - synthValueInEth, DECAY_BASE_100*circulatingNuma),10**decimalPrecision,price);
        }
        return result;
    }


    /**
     * @dev Buy numa from token (token approval needed)
     */
    function buy(uint _inputAmount,address _receiver) external payable nonReentrant whenNotPaused 
    {
        require(_inputAmount > MIN, "must trade over min");
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
    
  
    /**
     * @dev Sell numa (burn) to token (numa approval needed)
     */
    function sell(uint256 _numaAmount,address _receiver) external nonReentrant whenNotPaused
    {
        require(_numaAmount > MIN, "must trade over min");
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

    /**
     * @dev Estimate number of Numas from an amount of token
     */
    function getBuyNuma(uint256 _amount) external view returns (uint256) 
    {
        uint256 numaAmount = TokenToNuma(_amount);
        return (numaAmount* BUY_FEE) / FEE_BASE_1000;
    }

    /**
     * @dev Estimate number of tokens from an amount of numa
     */
    function getSellNuma(uint256 _amount) external view returns (uint256) 
    {
        uint256 tokenAmount = NumaToToken(_amount);
        return (tokenAmount * SELL_FEE) / FEE_BASE_1000;
    }


    /**
     * @dev Withdraw any ERC20 from vault
     */
    function withdrawToken(address _tokenAddress,uint256 _amount) external onlyOwner
    {
        SafeERC20.safeTransfer(IERC20(_tokenAddress),msg.sender,_amount);
    }


}