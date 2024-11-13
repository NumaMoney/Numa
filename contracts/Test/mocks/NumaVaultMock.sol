//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts_5.0.2/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts_5.0.2/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts_5.0.2/utils/Pausable.sol";
import "@openzeppelin/contracts_5.0.2/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts_5.0.2/utils/structs/EnumerableSet.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "../../Numa.sol";
import "../../interfaces/IVaultOracleSingle.sol";
import "../../interfaces/INuAssetManager.sol";
import "../../interfaces/IVaultManager.sol";
import "../../interfaces/INumaVault.sol";
import "../../interfaces/IRewardFeeReceiver.sol";

import "../../lending/CTokenInterfaces.sol";
import "../../lending/NumaComptroller.sol";
import "../../lending/CNumaToken.sol";

import "../../NumaProtocol/NumaVault.sol";

/// @title Numa vault to mint/burn Numa to lst token
contract NumaVaultMock is NumaVault {
    constructor(
        address _numaAddress,
        address _tokenAddress,
        uint256 _decimals,
        address _oracleAddress,
        address _minter
    )
        NumaVault(
            _numaAddress,
            _tokenAddress,
            _decimals,
            _oracleAddress,
            _minter,
            0,
            0
        )
    {}
    /**
     * @dev transfers rewards to rwd_address and updates reference price
     */
    function extractRewards() external {
        // require(
        //     block.timestamp >= (last_extracttimestamp + 24 hours),
        //     "reward already extracted"
        // );

        (
            uint256 rwd,
            uint256 currentvalueWei,
            uint256 rwdDebt
        ) = rewardsValue();
        require(rwd > rwd_threshold, "not enough rewards to collect");
        extractInternal(rwd, currentvalueWei, rwdDebt);
    }
}
