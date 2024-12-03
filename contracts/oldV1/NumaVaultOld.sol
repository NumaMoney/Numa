//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts_5.0.2/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts_5.0.2/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts_5.0.2/utils/Pausable.sol";
import "@openzeppelin/contracts_5.0.2/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts_5.0.2/utils/structs/EnumerableSet.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "../Numa.sol";
import "../interfaces/IVaultOracleSingle.sol";
import "./INuAssetManagerOld.sol";
import "./IVaultManagerOld.sol";
import "./INumaVaultOld.sol";
import "../interfaces/IRewardFeeReceiver.sol";

/// @title Numa vault to mint/burn Numa to lst token
contract NumaVaultOld is
    Ownable2Step,
    ReentrancyGuard,
    Pausable,
    INumaVaultOld
{
    using EnumerableSet for EnumerableSet.AddressSet;

    // address that receives fees
    address payable private fee_address;
    // address that receives REWARDS (extracted from lst token rebase)
    address payable private rwd_address;

    bool private isFeeReceiver;
    bool private isRwdReceiver;

    // sell fee
    uint16 public sell_fee = 950; // 5%
    // buy fee
    uint16 public buy_fee = 950; // 5%
    // fee that is sent to fee_address
    uint16 public fees = 10; //1%

    uint16 public max_percent = 100; //10%

    // threshold for reward extraction
    uint public rwd_threshold = 0;

    //
    NUMA public immutable numa;
    IERC20 public immutable lstToken;
    IVaultOracleSingle public oracle;
    //INuAssetManager public nuAssetManager;
    IVaultManagerOld public vaultManager;

    // reward extraction variables
    uint256 public last_extracttimestamp;
    uint256 public last_lsttokenvalueWei;

    // constants
    // minimum input amount for buy/sell
    uint256 public constant MIN = 1000;
    //uint16 public constant DECAY_BASE_100 = 100;
    uint16 public constant FEE_BASE_1000 = 1000;

    // decimals of lst token
    uint256 immutable decimals;

    bool isWithdrawRevoked = false;

    // Events
    event SetOracle(address oracle);
    event SetVaultManager(address vaultManager);
    event Buy(uint256 received, uint256 sent, address receiver);
    event Sell(uint256 sent, uint256 received, address receiver);
    event Fee(uint256 fee, address feeReceiver);
    event SellFeeUpdated(uint16 sellFee);
    event BuyFeeUpdated(uint16 buyFee);
    event FeeUpdated(uint16 Fee);
    event MaxPercentUpdated(uint16 NewValue);
    event ThresholdUpdated(uint256 newThreshold);
    event FeeAddressUpdated(address feeAddress);
    event RwdAddressUpdated(address rwdAddress);
    event AddedToRemovedSupply(address _address);
    event RemovedFromRemoveSupply(address _address);
    event RewardsExtracted(uint _rwd, uint _currentvalueWei);
    event StartDecay();

    constructor(
        address _numaAddress,
        address _tokenAddress,
        uint256 _decimals,
        address _oracleAddress
    ) Ownable(msg.sender) {
        numa = NUMA(_numaAddress);
        oracle = IVaultOracleSingle(_oracleAddress);
        lstToken = IERC20(_tokenAddress);
        decimals = _decimals;

        // lst rewards
        last_extracttimestamp = block.timestamp;
        //last_lsttokenvalueWei = oracle.getTokenPrice(address(lstToken),decimals);
        last_lsttokenvalueWei = oracle.getTokenPrice(decimals);

        // paused by default because might be empty
        _pause();
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
    function setOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0x0), "zero address");
        oracle = IVaultOracleSingle(_oracle);
        emit SetOracle(address(_oracle));
    }

    /**
     * @dev set the IVaultManager address (used to total Eth balance of all vaults)
     */
    function setVaultManager(address _vaultManager) external onlyOwner {
        require(_vaultManager != address(0x0), "zero address");
        vaultManager = IVaultManagerOld(_vaultManager);
        // vault have to be registered before
        require(vaultManager.isVault(address(this)), "not a registered vault");
        emit SetVaultManager(_vaultManager);
    }

    /**
     * @dev Set Rwd address
     */
    function setRwdAddress(
        address _address,
        bool _isRwdReceiver
    ) external onlyOwner {
        rwd_address = payable(_address);
        isRwdReceiver = _isRwdReceiver;
        emit RwdAddressUpdated(_address);
    }

    /**
     * @dev Set Fee address
     */
    function setFeeAddress(
        address _address,
        bool _isFeeReceiver
    ) external onlyOwner {
        fee_address = payable(_address);
        isFeeReceiver = _isFeeReceiver;
        emit FeeAddressUpdated(_address);
    }

    /**
     * @dev Set Sell fee percentage (exemple: 5% fee --> fee = 950)
     */
    function setSellFee(uint16 _fee) external onlyOwner {
        require(_fee <= FEE_BASE_1000, "fee above 1000");
        sell_fee = _fee;
        emit SellFeeUpdated(_fee);
    }

    /**
     * @dev Set Buy fee percentage (exemple: 5% fee --> fee = 950)
     */
    function setBuyFee(uint16 _fee) external onlyOwner {
        require(_fee <= FEE_BASE_1000, "fee above 1000");
        buy_fee = _fee;
        emit BuyFeeUpdated(_fee);
    }

    /**
     * @dev Set Fee percentage (exemple: 1% fee --> fee = 10)
     */
    function setFee(uint16 _fees) external onlyOwner {
        // fees have to be  <= buy/sell fee
        require(
            ((_fees <= (FEE_BASE_1000 - buy_fee)) &&
                (_fees <= (FEE_BASE_1000 - sell_fee))),
            "fees above buy/sell fee"
        );
        fees = _fees;
        emit FeeUpdated(_fees);
    }

    function setMaxPercent(uint16 _maxPercent) external onlyOwner {
        require(max_percent <= FEE_BASE_1000, "Percent above 100");
        max_percent = _maxPercent;
        emit MaxPercentUpdated(_maxPercent);
    }

    /**
     * @dev Set rewards threshold
     */
    function setRewardsThreshold(uint256 _threshold) external onlyOwner {
        rwd_threshold = _threshold;
        emit ThresholdUpdated(_threshold);
    }

    /**
     * @dev returns the estimated rewards value of lst token
     */
    function rewardsValue() public view returns (uint256, uint256) {
        require(address(oracle) != address(0), "oracle not set");
        //uint currentvalueWei = oracle.getTokenPrice(address(lstToken),decimals);
        uint currentvalueWei = oracle.getTokenPrice(decimals);
        if (currentvalueWei <= last_lsttokenvalueWei) {
            return (0, currentvalueWei);
        }
        uint diff = (currentvalueWei - last_lsttokenvalueWei);
        uint balance = lstToken.balanceOf(address(this));
        uint rwd = FullMath.mulDiv(balance, diff, currentvalueWei);
        return (rwd, currentvalueWei);
    }

    function extractInternal(uint rwd, uint currentvalueWei) internal {
        last_extracttimestamp = block.timestamp;
        last_lsttokenvalueWei = currentvalueWei;

        if (rwd_address != address(0)) {
            SafeERC20.safeTransfer(IERC20(lstToken), rwd_address, rwd);
            if (isContract(rwd_address) && isRwdReceiver) {
                // we don't check result as contract might not implement the deposit function (if multi sig for example)
                rwd_address.call(
                    abi.encodeWithSignature("DepositFromVault(uint256)", rwd)
                );
            }
        }
        emit RewardsExtracted(rwd, currentvalueWei);
    }

    /**
     * @dev transfers rewards to rwd_address and updates reference price
     */
    function extractRewards() external {
        require(
            block.timestamp >= (last_extracttimestamp + 24 hours),
            "reward already extracted"
        );

        (uint256 rwd, uint256 currentvalueWei) = rewardsValue();
        require(rwd > rwd_threshold, "not enough rewards to collect");
        extractInternal(rwd, currentvalueWei);
    }

    /**
     * @dev transfers rewards to rwd_address and updates reference price
     * @notice no require as it will be called from buy/sell function and we only want to skip this step if
     * conditions are not filled
     */
    function extractRewardsNoRequire() internal {
        if (block.timestamp >= (last_extracttimestamp + 24 hours)) {
            (uint256 rwd, uint256 currentvalueWei) = rewardsValue();
            if (rwd > rwd_threshold) {
                extractInternal(rwd, currentvalueWei);
            }
        }
    }

    /**
     * @dev vaults' balance in Eth
     */
    function getEthBalance() external view returns (uint256) {
        require(address(oracle) != address(0), "oracle not set");
        uint balance = lstToken.balanceOf(address(this));
        // we use last reference value for balance computation
        uint result = FullMath.mulDiv(last_lsttokenvalueWei, balance, decimals);
        return result;
    }

    /**
     * @dev Buy numa from token (token approval needed)
     */
    function buy(
        uint _inputAmount,
        uint _minNumaAmount,
        address _receiver
    ) external nonReentrant whenNotPaused returns (uint _numaOut) {
        require(_inputAmount > MIN, "must trade over min");

        // extract rewards if any
        extractRewardsNoRequire();

        uint256 vaultsBalance = lstToken.balanceOf(address(this));
        uint256 MAX = (max_percent * vaultsBalance) / FEE_BASE_1000;
        require(_inputAmount <= MAX, "must trade under max");

        // execute buy
        uint256 numaAmount = vaultManager.tokenToNuma(
            _inputAmount,
            last_lsttokenvalueWei,
            decimals
        );
        require(numaAmount > 0, "amount of numa is <= 0");

        // transfer token
        SafeERC20.safeTransferFrom(
            lstToken,
            msg.sender,
            address(this),
            _inputAmount
        );

        _numaOut = (numaAmount * buy_fee) / FEE_BASE_1000;
        require(_numaOut >= _minNumaAmount, "Min NUMA");

        // mint numa
        numa.mint(_receiver, _numaOut);
        emit Buy(_numaOut, _inputAmount, _receiver);
        // fee
        if (fee_address != address(0x0)) {
            uint256 feeAmount = (fees * _inputAmount) / FEE_BASE_1000;
            SafeERC20.safeTransfer(lstToken, fee_address, feeAmount);

            if (isContract(fee_address) && isFeeReceiver) {
                // we don't check result as contract might not implement the deposit function (if multi sig for example)
                fee_address.call(
                    abi.encodeWithSignature(
                        "DepositFromVault(uint256)",
                        feeAmount
                    )
                );
            }
            emit Fee(feeAmount, fee_address);
        }
    }

    /**
     * @dev Sell numa (burn) to token (numa approval needed)
     */
    function sell(
        uint256 _numaAmount,
        uint256 _minTokenAmount,
        address _receiver
    ) external nonReentrant whenNotPaused returns (uint _tokenOut) {
        require(_numaAmount > MIN, "must trade over min");
        // extract rewards if any
        extractRewardsNoRequire();
        // execute sell
        // Total Eth to be sent
        uint256 tokenAmount = vaultManager.numaToToken(
            _numaAmount,
            last_lsttokenvalueWei,
            decimals
        );
        require(tokenAmount > 0, "amount of token is <=0");
        require(
            lstToken.balanceOf(address(this)) >= tokenAmount,
            "not enough liquidity in vault"
        );

        _tokenOut = (tokenAmount * sell_fee) / FEE_BASE_1000;
        require(_tokenOut >= _minTokenAmount, "Min Token");

        // burning numa tokens
        numa.burnFrom(msg.sender, _numaAmount);

        // transfer lst tokens to receiver
        SafeERC20.safeTransfer(lstToken, _receiver, _tokenOut);
        emit Sell(_numaAmount, _tokenOut, _receiver);
        // fee
        if (fee_address != address(0x0)) {
            uint256 feeAmount = (fees * tokenAmount) / FEE_BASE_1000;
            SafeERC20.safeTransfer(IERC20(lstToken), fee_address, feeAmount);

            if (isContract(fee_address) && isFeeReceiver) {
                // we don't check result as contract might not implement the deposit function (if multi sig for example)
                fee_address.call(
                    abi.encodeWithSignature(
                        "DepositFromVault(uint256)",
                        feeAmount
                    )
                );
            }

            emit Fee(feeAmount, fee_address);
        }
    }

    /**
     * @dev Estimate number of Numas from an amount of token
     */
    function getBuyNuma(uint256 _amount) external view returns (uint256) {
        uint256 numaAmount = vaultManager.tokenToNuma(
            _amount,
            last_lsttokenvalueWei,
            decimals
        );



        return (numaAmount * buy_fee) / FEE_BASE_1000;
    }

    /**
     * @dev Estimate number of tokens from an amount of numa
     */
    function getSellNuma(uint256 _amount) external view returns (uint256) {
        uint256 tokenAmount = vaultManager.numaToToken(
            _amount,
            last_lsttokenvalueWei,
            decimals
        );
        return (tokenAmount * sell_fee) / FEE_BASE_1000;
    }

    /**
     * @dev Estimate number of Numas from an amount of token with extraction simulation
     */
    function getBuyNumaSimulateExtract(
        uint256 _amount
    ) external view returns (uint256) {
        uint256 refValue = last_lsttokenvalueWei;
        (uint256 rwd, uint256 currentvalueWei) = rewardsValue();
        if (rwd > rwd_threshold) {
            refValue = currentvalueWei;
        }

        uint256 numaAmount = vaultManager.tokenToNuma(
            _amount,
            refValue,
            decimals
        );
        return (numaAmount * buy_fee) / FEE_BASE_1000;
    }

    /**
     * @dev Estimate number of tokens from an amount of numa with extraction simulation
     */
    function getSellNumaSimulateExtract(
        uint256 _amount
    ) external view returns (uint256) {
        uint256 refValue = last_lsttokenvalueWei;
        (uint256 rwd, uint256 currentvalueWei) = rewardsValue();
        if (rwd > rwd_threshold) {
            refValue = currentvalueWei;
        }

        uint256 tokenAmount = vaultManager.numaToToken(
            _amount,
            refValue,
            decimals
        );
        return (tokenAmount * sell_fee) / FEE_BASE_1000;
    }

    /**
     * @dev Withdraw any ERC20 from vault
     */
    function withdrawToken(
        address _tokenAddress,
        uint256 _amount,
        address _receiver
    ) external onlyOwner {
        require(!isWithdrawRevoked);
        SafeERC20.safeTransfer(IERC20(_tokenAddress), _receiver, _amount);
    }

    function revokeWithdraw() external onlyOwner {
        isWithdrawRevoked = true;
    }

    function isContract(address addr) internal view returns (bool) {
        uint extSize;
        assembly {
            extSize := extcodesize(addr) // returns 0 if EOA, >0 if smart contract
        }
        return (extSize > 0);
    }
}
