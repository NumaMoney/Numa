// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;

import "../interfaces/INuma.sol";
import {nuAssetManager} from "../nuAssets/nuAssetManager.sol";
import {NumaMinter} from "../NumaProtocol/NumaMinter.sol";
import {VaultOracleSingle} from "../NumaProtocol/VaultOracleSingle.sol";
import {VaultManager} from "../NumaProtocol/VaultManager.sol";
import {NumaVault} from "../NumaProtocol/NumaVault.sol";
import "forge-std/console2.sol";

contract deployUtils {
    struct deployVaultParameters {
        uint128 _heartbeat;
        address _uptimefeed;
        address _pricefeed;
        address _feereceiver;
        address _rwdreceiver;
        INuma _numa;
        uint _debt;
        uint _rwdfromDebt;
        address _existingAssetManager;
        address _existingNumaminter;
        address _existingVaultOracle;
        address _lst;
    }

    function setupVaultAndAssetManager(
        deployVaultParameters memory _parameters
    )
        public
        returns (
            nuAssetManager nuAM,
            NumaMinter minter,
            VaultManager vaultm,
            VaultOracleSingle vo,
            NumaVault v
        )
    {
        // nuAssetManager
        if (_parameters._existingAssetManager != address(0)) {
            nuAM = nuAssetManager(_parameters._existingAssetManager);
        } else {
            nuAM = new nuAssetManager(_parameters._uptimefeed);
        }


        // numaMinter
        if (_parameters._existingNumaminter != address(0)) {
            minter = NumaMinter(_parameters._existingNumaminter);
        } else {
            minter = new NumaMinter();
            minter.setTokenAddress(address(_parameters._numa));
        }
        // vault manager
        vaultm = new VaultManager(address(_parameters._numa), address(nuAM));

        if (_parameters._existingVaultOracle != address(0))
        {
            vo = VaultOracleSingle(_parameters._existingVaultOracle);
        }
        else
        {
            vo = new VaultOracleSingle(
                _parameters._lst,
                _parameters._pricefeed,
                _parameters._heartbeat,
                _parameters._uptimefeed
            );
        }

        v = setupVault(
            vo,
            address(minter),
            address(vaultm),
            _parameters._numa,
            _parameters._debt,
            _parameters._rwdfromDebt
        );

        v.setFeeAddress(_parameters._feereceiver, false);
        v.setRwdAddress(_parameters._rwdreceiver, false);
    }

    function setupVault(
        VaultOracleSingle _vo,
        address _minter,
        address _vaultm,
        INuma _numa,
        uint _debt,
        uint _rwdfromDebt
    ) public returns (NumaVault v) {
        // vault
        v = new NumaVault(
            address(_numa),
            _vo.token(),
            1 ether,
            address(_vo),
            _minter,
            _debt,
            _rwdfromDebt
        );
        // add vault as a numa minter
        NumaMinter(_minter).addToMinters(address(v));
        VaultManager(_vaultm).addVault(address(v));
        v.setVaultManager(_vaultm);
    }
}
