pragma solidity 0.8.20;

import "./PriceOracleCollateralBorrow.sol";
import "./CNumaToken.sol";
import "../interfaces/INumaVault.sol";

import "@uniswap/v3-core/contracts/libraries/FullMath.sol";

contract NumaPriceOracleNew is PriceOracleCollateralBorrow {
    constructor() {}

    function getUnderlyingPriceAsCollateral(
        CNumaToken cToken
    ) public view override returns (uint) {
        INumaVault vault = cToken.vault();
        require((address(vault) != address(0)), "no vault");

        if (address(cToken) == vault.getcNumaAddress()) {
            // numa price from vault
            return vault.numaToLst(1e18);
        } else if (address(cToken) == vault.getcLstAddress()) {
            //
            return 1e18; // rEth has 18 decimals
        } else {
            revert("unsupported token");
        }
    }

    function getUnderlyingPriceAsBorrowed(
        CNumaToken cToken
    ) public view override returns (uint) {
        INumaVault vault = cToken.vault();
        require((address(vault) != address(0)), "no vault");
        if (address(cToken) == vault.getcNumaAddress()) {
            // numa price from vault
            uint rEthPriceInNuma = vault.lstToNuma(1e18);
            return FullMath.mulDivRoundingUp(1e18, 1e18, rEthPriceInNuma); // rounded up because we prefer borrowed to be worth a little bit more
        } else if (address(cToken) == vault.getcLstAddress()) {
            //
            return 1e18; // rEth has 18 decimals
        } else {
            revert("unsupported token");
        }
    }
}
