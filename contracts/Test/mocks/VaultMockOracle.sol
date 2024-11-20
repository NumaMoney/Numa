//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../../interfaces/IVaultOracleSingle.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
contract VaultMockOracle is IVaultOracleSingle {
    uint price = 1 ether;
    address public token;
    constructor(address _token)
    {
        token = _token;
    }

    function setPrice(uint256 _price) external {
        price = _price;
    }

    // function getTokenPriceSimple(address _tokenAddress) external view returns (uint256)
    // {

    //     return (price);
    // }

    function getTokenPrice(uint256 _amount) external view returns (uint256) {
        return FullMath.mulDiv(_amount, uint256(price), 10 ** 18);
    }
}
