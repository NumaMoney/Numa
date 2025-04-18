// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts_5.0.2/access/Ownable2Step.sol";
import "@openzeppelin/contracts_5.0.2/utils/structs/EnumerableSet.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "./IVaultManagerOld.sol";
import "./INumaVaultOld.sol";

import "../Numa.sol";

import "./INuAssetManagerOld.sol";

contract VaultManagerOld is IVaultManagerOld, Ownable2Step {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet vaultsList;

    INuAssetManagerOld public nuAssetManager;
    NUMA public immutable numa;
    //EnumerableSet.AddressSet removedSupplyAddresses;

    uint public initialRemovedSupply;
    uint public constantRemovedSupply;
    uint public decayPeriod;
    uint public startTime;
    bool public isDecaying;

    uint constant max_vault = 50;
    //uint constant max_addresses = 50;

    event SetNuAssetManager(address nuAssetManager);
    event RemovedVault(address);
    event AddedVault(address);

    constructor(
        address _numaAddress,
        address _nuAssetManagerAddress
    ) Ownable(msg.sender) {
        numa = NUMA(_numaAddress);
        nuAssetManager = INuAssetManagerOld(_nuAssetManagerAddress);
    }

    function startDecay() external onlyOwner {
        startTime = block.timestamp;
        isDecaying = true;
    }

    function setConstantRemovedSupply(
        uint _constantRemovedSupply
    ) external onlyOwner {
        constantRemovedSupply = _constantRemovedSupply;
    }

    function setDecayValues(
        uint _initialRemovedSupply,
        uint _decayPeriod,
        uint _constantRemovedSupply
    ) external onlyOwner {
        initialRemovedSupply = _initialRemovedSupply;
        constantRemovedSupply = _constantRemovedSupply;
        decayPeriod = _decayPeriod;
        // start decay will have to be called again
        // CAREFUL: IF DECAYING, ALL VAULTS HAVE TO BE PAUSED WHEN CHANGING THESE VALUES, UNTIL startDecay IS CALLED
        isDecaying = false;
    }

    function isVault(address _addy) external view returns (bool) {
        return (vaultsList.contains(_addy));
    }

    /**
     * @dev set the INuAssetManager address (used to compute synth value in Eth)
     */
    function setNuAssetManager(address _nuAssetManager) external onlyOwner {
        require(_nuAssetManager != address(0x0), "zero address");
        nuAssetManager = INuAssetManagerOld(_nuAssetManager);
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

    function GetPriceFromVaultWithoutFees(
        uint _inputAmount
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
        if (isDecaying && (currentTime > startTime) && (decayPeriod > 0)) {
            uint delta = ((currentTime - startTime) * initialRemovedSupply) /
                decayPeriod;
            if (delta >= (initialRemovedSupply)) {
                currentRemovedSupply = 0;
            } else {
                currentRemovedSupply -= (delta);
            }
        }

        circulatingNuma =
            circulatingNuma -
            currentRemovedSupply -
            constantRemovedSupply;

        return circulatingNuma;
    }

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
            result += INumaVaultOld(vaultsList.at(i)).getEthBalance();
        }
        return result;
    }
}
