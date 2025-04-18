//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "../interfaces/IVaultOracleSingle.sol";
import "../libraries/OracleUtils.sol";
import "@openzeppelin/contracts_5.0.2/token/ERC20/extensions/IERC20Metadata.sol";

contract VaultOracleSingle is IVaultOracleSingle, OracleUtils {
    address public feed;

    uint128 chainlink_heartbeat;
    address public token;
    constructor(
        address _token,
        address _feed,
        uint128 _chainlink_heartbeat,
        address _uptimeFeedAddress
    ) OracleUtils(_uptimeFeedAddress) {
        feed = _feed;
        chainlink_heartbeat = _chainlink_heartbeat;
        token = _token;
    }

    /**
     * @dev value in Eth (in wei) of this amount of token
     */
    function getTokenPrice(uint256 _amount) external view returns (uint256) {
        return
            tokenToEth(
                _amount,
                feed,
                chainlink_heartbeat,
                IERC20Metadata(token).decimals()
            );
    }
}
