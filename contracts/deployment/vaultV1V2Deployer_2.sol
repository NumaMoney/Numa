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

// deployers
import "./vaultV1V2Deployer_1.sol";




// deployer should be old numa vault admin
contract vaultV1V2Deployer_2 is Ownable2Step {


    address public numa_address;
    address public lst_Address;

    address public vaultFeeReceiver;
    address public vaultRwdReceiver;
    

    // V1
    address vaultOldAddress;
    address vaultManagerOldAddress;


    


    // constants
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");


    constructor(
        

        address _numaAddress,
        address _lstAddress,       

        address _vaultFeeReceiver,
        address _vaultRwdReceiver,

        address _vaultOldAddress,
        address _vaultManagerOldAddress

    ) Ownable(msg.sender){

        numa_address = _numaAddress;
        lst_Address = _lstAddress;





        vaultFeeReceiver = _vaultFeeReceiver;
        vaultRwdReceiver = _vaultRwdReceiver;

        vaultOldAddress = _vaultOldAddress;
        vaultManagerOldAddress = _vaultManagerOldAddress;
        
    }


    function migrateVault() external onlyOwner
    {
     
       
        // vault manager
        vaultManager = new VaultManager(numa_address, address(nuAssetMgr));

        deploymentReport.vault = new NumaVault(
            numa_address,
            lst_Address,
            1 ether,
            address(deploymentReport.vaultOracle),
            address(deploymentReport.numaMinter),
            0,
            0
        );
        deploymentReport.vault.setVaultManager(address(deploymentReport.vaultManager));
        deploymentReport.vault.setFeeAddress(vaultFeeReceiver, false);
        deploymentReport.vault.setRwdAddress(vaultRwdReceiver, false);


        INuma(numa_address).grantRole(MINTER_ROLE, address(deploymentReport.numaMinter));

        
        // add vault as a numa minter
        deploymentReport.numaMinter.addToMinters(address(deploymentReport.vault));

      
        NumaVaultOld vaultOld = NumaVaultOld(vaultOldAddress);
        VaultManagerOld vaultManagerOld = VaultManagerOld(vaultManagerOldAddress);
       

  

        // first we need to match numa supply
        uint numaSupplyOld = vaultManagerOld.getNumaSupply();
        uint numaSupplyNew = deploymentReport.vaultManager.getNumaSupply();
      

        uint diff = numaSupplyNew -
            numaSupplyOld -
            vaultManagerOld.constantRemovedSupply();

        // keep same period
        uint newPeriod = vaultManagerOld.decayPeriod() -
            (block.timestamp - vaultManagerOld.startTime());


        deploymentReport.vaultManager.addVault(address(deploymentReport.vault));

        // set buy/sell fees to match old price
        deploymentReport.vaultManager.setSellFee((uint(vaultOld.sell_fee()) * 1 ether) / 1000);
        deploymentReport.vaultManager.setBuyFee((uint(vaultOld.buy_fee()) * 1 ether) / 1000);



        deploymentReport.vaultManager.setDecayValues(
            diff / 2,
            newPeriod,
            diff / 2,
            newPeriod,
            vaultManagerOld.constantRemovedSupply() // same constant
        );
        // TODO: move it?
        deploymentReport.vaultManager.startDecay();



    }


    function transferBalance() external onlyOwner
    {
        IERC20 rEth = IERC20(lst_Address);

        NumaVaultOld vaultOld = NumaVaultOld(vaultOldAddress);
        vaultOld.withdrawToken(
            lst_Address,
            rEth.balanceOf(vaultOldAddress),
            address(deploymentReport.vault));
    }

    function unpauseVault() external onlyOwner
    {
        deploymentReport.vault.unpause();
    }


 
}
