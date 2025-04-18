// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
// //import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
// import "@openzeppelin/contracts/access/AccessControl.sol";
// import "@layerzerolabs/lz-evm-oapp-v2/contracts/oft/OFT.sol";

// abstract contract INuAsset is OFT, ERC20Burnable, AccessControl{
//     bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
//     bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");


//     constructor() {
        
//     }

//     //function initialize(address defaultAdmin, address minter, address upgrader) public virtual;

//     function initialize(string memory name,string memory symbol,address defaultAdmin, address minter, address upgrader) public virtual;

//     function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
//         _mint(to, amount);
//     }

// }