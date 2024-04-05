pragma solidity 0.8.20;

import "./PriceOracle.sol";
import "./CErc20.sol";
import "../interfaces/INumaVault.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract NumaPriceOracle is PriceOracle,Ownable {
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
    function getUnderlyingPrice(CToken cToken) public override view returns (uint) {
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
    }


    function compareStrings(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked((a))) == keccak256(abi.encodePacked((b))));
    }
}
