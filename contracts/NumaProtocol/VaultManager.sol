// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "../interfaces/IVaultManager.sol";
import "../interfaces/INumaVault.sol";

import "../Numa.sol";

import "../interfaces/INuAssetManager.sol";

contract VaultManager is IVaultManager, Ownable2Step {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet vaultsList;

    INuAssetManager public nuAssetManager;
    NUMA public immutable numa;
    //EnumerableSet.AddressSet removedSupplyAddresses;

    uint initialRemovedSupply;
    uint decayPeriod;
    uint startTime;
    bool isDecaying;
    uint16 private constant DECAY_BASE = 10000;



    uint constant max_vault = 50;
    //uint constant max_addresses = 50;

    event SetNuAssetManager(address nuAssetManager);
    event RemovedVault(address);
    event AddedVault(address);
    event AddedToRemovesupply(address);
    event RemovedFromRemovesupply(address);

    constructor(
        address _numaAddress,
        address _nuAssetManagerAddress     
    ) Ownable(msg.sender) {
        numa = NUMA(_numaAddress);       
        nuAssetManager = INuAssetManager(_nuAssetManagerAddress);
    }



    function startDecay() external onlyOwner
    {
        startTime = block.timestamp;
        isDecaying = true;
    }

    function setDecayValues(uint _initialRemovedSupply, uint _decayPeriod) external onlyOwner
    {
        initialRemovedSupply = _initialRemovedSupply;
        decayPeriod = _decayPeriod;
        isDecaying = false;

    }


    function isVault(address _addy) external view returns (bool)
    {
        return (vaultsList.contains(_addy));

    }





    /**
     * @dev set the INuAssetManager address (used to compute synth value in Eth)
     */
    function setNuAssetManager(address _nuAssetManager) external onlyOwner {
        require(_nuAssetManager != address(0x0), "zero address");
        nuAssetManager = INuAssetManager(_nuAssetManager);
        emit SetNuAssetManager(_nuAssetManager);
    }

    /**
     * @dev How many Numas from lst token amount
     */
    function tokenToNuma(
        uint _inputAmount,
        uint _refValueWei,
        uint _decimals
    ) external view returns (uint256) {
        uint256 EthValue = FullMath.mulDiv(
            _refValueWei,
            _inputAmount,
            _decimals
        );
        uint synthValueInEth = getTotalSynthValueEth();
        uint circulatingNuma = getNumaSupply();

        uint EthBalance = getTotalBalanceEth();
        require(
            EthBalance > synthValueInEth,
            "vault is empty or synth value is too big"
        );
       
        uint result = FullMath.mulDiv(
            EthValue,
             circulatingNuma,
            (EthBalance - synthValueInEth)
        );

        return result;
    }

    /**
     * @dev How many lst tokens from numa amount
     */
    function numaToToken(
        uint _inputAmount,
        uint _refValueWei,
        uint _decimals
    ) external view returns (uint256) {
        uint synthValueInEth = getTotalSynthValueEth();
        uint circulatingNuma = getNumaSupply();
        uint EthBalance = getTotalBalanceEth();

        require(
            EthBalance > synthValueInEth,
            "vault is empty or synth value is too big"
        );
        require(circulatingNuma > 0, "no numa in circulation");
        uint result;
       
        // using snaphot price
        result = FullMath.mulDiv(
            FullMath.mulDiv(
                _inputAmount,
                EthBalance - synthValueInEth,
                circulatingNuma
            ),
            _decimals,
            _refValueWei
        );
        return result;
    }


    function GetPriceFromVaultWithoutFees(uint _inputAmount) external view returns (uint256)
    {
        uint synthValueInEth = getTotalSynthValueEth();
        uint circulatingNuma = getNumaSupply();
        uint EthBalance = getTotalBalanceEth();

        require(
            EthBalance > synthValueInEth,
            "vault is empty or synth value is too big"
        );
        require(circulatingNuma > 0, "no numa in circulation");
        uint result;
       
        // using snaphot price
        result = FullMath.mulDiv(
                _inputAmount,
                EthBalance - synthValueInEth,
                circulatingNuma
            );
        return result;

    }


    /**
     * @dev Total synth value in Eth
     */
    function getTotalSynthValueEth() internal view returns (uint256) {
        require(
            address(nuAssetManager) != address(0),
            "nuAssetManager not set"
        );
        return nuAssetManager.getTotalSynthValueEth();
    }

    /**
     * @dev total numa supply without wallet's list balances
     * @notice for another vault, either we use this function from this vault, either we need to set list in the other vault too
     */
    function getNumaSupply() public view returns (uint) {
        uint circulatingNuma = numa.totalSupply();
        uint currentRemovedSupply = initialRemovedSupply;

        uint currentTime = block.timestamp;
        if (isDecaying && (currentTime > startTime) && (decayPeriod > 0))
        {
            uint delta = ((currentTime - startTime) * DECAY_BASE)/decayPeriod;
            if (delta >= DECAY_BASE)
            {
                currentRemovedSupply = 0;
            }
            else {
                currentRemovedSupply -= (delta * initialRemovedSupply)/DECAY_BASE;                
            }

        }

     
        circulatingNuma = circulatingNuma - currentRemovedSupply;



        // uint256 nbWalletsToRemove = removedSupplyAddresses.length();
        // require(
        //     nbWalletsToRemove < max_addresses,
        //     "too many wallets to remove from supply"
        // );
        // // remove wallets balances from numa supply
        // for (uint256 i = 0; i < nbWalletsToRemove; i++) {
        //     uint bal = numa.balanceOf(removedSupplyAddresses.at(i));
        //     circulatingNuma -= bal;
        // }
        return circulatingNuma;
    }

    // /**
    //  * @dev list of wallets whose numa balance is removed from total supply
    //  */
    // function getRemovedWalletsList() external view returns (address[] memory) {
    //     return removedSupplyAddresses.values();
    // }

    // /**
    //  * @dev adds a wallet to wallets whose numa balance is removed from total supply
    //  */
    // function addToRemovedSupply(address _address) external onlyOwner {
    //     require(
    //         removedSupplyAddresses.length() < max_addresses,
    //         "too many wallets in list"
    //     );
    //     require(removedSupplyAddresses.add(_address), "already in list");
    //     emit AddedToRemovesupply(_address);
    // }

    // /**
    //  * @dev removes a wallet to wallets whose numa balance is removed from total supply
    //  */
    // function removeFromRemovedSupply(address _address) external onlyOwner {
    //     require(removedSupplyAddresses.contains(_address), "not in list");
    //     removedSupplyAddresses.remove(_address);
    //     emit RemovedFromRemovesupply(_address);
    // }

    /**
     * @dev returns vaults list
     */
    function getVaults() external view returns (address[] memory) {
        return vaultsList.values();
    }

    /**
     * @dev adds a vault to the total balance
     */
    function addVault(address _vault) external onlyOwner {
        require(vaultsList.length() < max_vault, "too many vaults");
        require(vaultsList.add(_vault), "already in list");
        emit AddedVault(_vault);
    }

    /**
     * @dev removes a vault from total balance
     */
    function removeVault(address _vault) external onlyOwner {
        require(vaultsList.contains(_vault), "not in list");
        vaultsList.remove(_vault);
        emit RemovedVault(_vault);
    }

    /**
     * @dev sum of all vaults balances in Eth
     */
    function getTotalBalanceEth() public view returns (uint256) {
        uint result;
        uint256 nbVaults = vaultsList.length();
        require(nbVaults <= max_vault, "too many vaults in list");

        for (uint256 i = 0; i < nbVaults; i++) {
            result += INumaVault(vaultsList.at(i)).getEthBalance();
        }
        return result;
    }
}
