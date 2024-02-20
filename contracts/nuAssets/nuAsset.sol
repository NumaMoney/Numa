// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interfaces/INuAsset.sol";

contract nuAsset is INuAsset {
    /// @custom:oz-upgrades-unsafe-allow constructor
    function initialize(
        string memory _name,
        string memory _symbol,
        address _defaultAdmin,
        address _minter,
        address _upgrader
    ) public virtual override initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Burnable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _grantRole(MINTER_ROLE, _minter);
        _grantRole(UPGRADER_ROLE, _upgrader);
    }
}
