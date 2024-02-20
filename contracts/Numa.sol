// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./NumaStore.sol";

contract NUMA is
    NumaStore,
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __ERC20_init("NUMA", "NUMA");
        __ERC20Burnable_init();
        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    function SetFee(uint _newFeeBips) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newFeeBips <= 10000, "Fee percentage must be 100 or less");
        NumaStorage storage ns = numaStorage();
        ns.sellFeeBips = _newFeeBips;
    }

    function SetFeeTriggerer(
        address _dexAddress,
        bool _isFee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        NumaStorage storage ns = numaStorage();
        ns.isIncludedInFees[_dexAddress] = _isFee;
    }
    function SetWlSpender(
        address _address,
        bool _isWl
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        NumaStorage storage ns = numaStorage();
        ns.wlSpenders[_address] = _isWl;
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        NumaStorage storage ns = numaStorage();
        uint fee = ns.sellFeeBips;
        // spend allowance
        _spendAllowance(from, spender, value);
        // cancel fee for some spenders. Typically, this will be used for UniswapV2Router which is used when adding liquidity
        if ((!ns.wlSpenders[spender]) && (fee > 0) && ns.isIncludedInFees[to]) {
            _transferWithFee(from, to, value, fee);
        } else {
            super._transfer(from, to, value);
        }

        return true;
    }
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        // uniswap sell fee
        NumaStorage storage ns = numaStorage();
        uint fee = ns.sellFeeBips;
        // apply (burn) fee on some receivers. Typically, the UniswapV2Pair, to apply fee when selling on Uniswap.
        if ((fee > 0) && ns.isIncludedInFees[to]) {
            _transferWithFee(from, to, amount, fee);
        } else {
            super._transfer(from, to, amount);
        }
    }
    function _transferWithFee(
        address from,
        address to,
        uint256 amount,
        uint256 fee
    ) internal virtual {
        uint256 amountToBurn = (amount * fee) / 10000;
        amount -= amountToBurn;
        _burn(from, amountToBurn);
        super._transfer(from, to, amount);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}
}
