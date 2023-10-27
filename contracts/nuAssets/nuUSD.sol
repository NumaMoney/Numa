// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../interfaces/INuAsset.sol";

contract nuUSD is INuAsset {
    /// @custom:oz-upgrades-unsafe-allow constructor
    function initialize(address defaultAdmin, address minter, address upgrader) initializer public virtual override
    {
        __ERC20_init("NuUSD", "NUSD");
        __ERC20Burnable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(UPGRADER_ROLE, upgrader);
    }
}
