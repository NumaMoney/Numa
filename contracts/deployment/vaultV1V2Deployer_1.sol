// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;
import "../interfaces/INuma.sol";



import {nuAssetManager2} from "../nuAssets/nuAssetManager2.sol";
import {NumaMinter} from "../NumaProtocol/NumaMinter.sol";
import {VaultOracleSingle} from "../NumaProtocol/VaultOracleSingle.sol";
import {VaultManager} from "../NumaProtocol/VaultManager.sol";
import {NumaVault} from "../NumaProtocol/NumaVault.sol";
import {VaultMockOracle} from "../Test/mocks/VaultMockOracle.sol";
// V1 protocol
import "../oldV1/NumaVaultOld.sol";
import "../oldV1/VaultManagerOld.sol";
import "../oldV1/nuAssetManagerOld.sol";


import "@openzeppelin/contracts_5.0.2/access/Ownable2Step.sol";
import "@openzeppelin/contracts_5.0.2/token/ERC20/utils/SafeERC20.sol";





// deployer should be old numa vault admin
contract vaultV1V2Deployer_1 is Ownable2Step {

    // in
    address public numa_address;
    address public lst_Address;

    address public uptimefeed_address;
    uint128 public lstHeartbeat;
    address public pricefeed;





    // out
    nuAssetManager2 public nuAssetMgr;
    NumaMinter public numaMinter;
    VaultOracleSingle public vaultOracle;
    VaultManager public vaultManager;




    // constants
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");





    constructor(
        address _numaAddress,
        address _lstAddress,       
        address _pricefeedAddress,
        address _uptimeAddress,
        uint128 _lstHeartbeat

    ) Ownable(msg.sender){
        numa_address = _numaAddress;
        lst_Address = _lstAddress;
        pricefeed = _pricefeedAddress;
        uptimefeed_address = _uptimeAddress;
        lstHeartbeat = _lstHeartbeat;


    }


    function migrate_NumaV1V2(bool _testnet) external onlyOwner
    {
        // nuAssetManager
        nuAssetMgr = new nuAssetManager2(uptimefeed_address);
        
        // numaMinter
        numaMinter = new NumaMinter();
        numaMinter.setTokenAddress(numa_address);
        
   

        // vault oracle
        if (_testnet)
        {
            VaultMockOracle vaultOracleDeploy = new VaultMockOracle(lst_Address);
            vaultOracle = VaultOracleSingle(address(vaultOracleDeploy));
        }
        else
        {
            vaultOracle = new VaultOracleSingle(lst_Address,pricefeed,lstHeartbeat,uptimefeed_address);
        }

    }

}
