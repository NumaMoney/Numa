pragma solidity 0.8.20;

import "./PriceOracleCollateralBorrow.sol";
import "./CErc20.sol";
import "../interfaces/INumaVault.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "hardhat/console.sol";

contract NumaPriceOracleNew is PriceOracleCollateralBorrow,Ownable {
    INumaVault vault;
    
    /// @notice set vault event
    event SetVault(address vaultAddress);
    constructor() Ownable(msg.sender)
    {

    }
    function setVault(address _vault) external onlyOwner 
    {
        vault = INumaVault(_vault);
        emit SetVault(_vault);
    }
    function getUnderlyingPriceAsCollateral(CToken cToken) public override view returns (uint) {
                console.log("underlying price as collateral");
        require((address(vault) != address(0)),"vault null address");
        if (compareStrings(cToken.symbol(), "cNuma")) 
        {
            // numa price from vault
            return vault.getSellNumaSimulateExtract(1e18);
        } 
        else if (compareStrings(cToken.symbol(), "crEth")) 
        {
            // 
            return 1e18;// todo confirm and check lst decimals, also should we use 1/numa buy price?
        }
        else
        {
            revert("unsupported token");
        }

    }

    function getUnderlyingPriceAsBorrowed(CToken cToken) public override view returns (uint) 
    {
        console.log("underlying price as borrowed");
        require((address(vault) != address(0)),"vault null address");
        if (compareStrings(cToken.symbol(), "cNuma")) 
        {
            // numa price from vault
            uint rEthPriceInNuma = vault.getBuyNumaSimulateExtract(1e18);
            console.logUint(rEthPriceInNuma);
            console.logUint(FullMath.mulDivRoundingUp(1e18,1e18,rEthPriceInNuma));
            return FullMath.mulDivRoundingUp(1e18,1e18,rEthPriceInNuma);// rounded up because we prefer borrowed to be worth a little bit more  TODO confirm
        } 
        else if (compareStrings(cToken.symbol(), "crEth")) 
        {
            // 
            return 1e18;// todo confirm and check lst decimals
        }
        else
        {
            revert("unsupported token");
        }
    }


    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
