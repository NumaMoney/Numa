// TODO

// a chaque fois:
//  - match de prix
//  - buy/sells ok et même qtité
//  - buy ancien KO
// TESTS
// - test migration from old to current without lending/without printing
// - test migration from old to current with lending/with printing
// - test current without lending/printing, setup lending/printing
// - test current with/without lending/printing to new one current
//  ** with lending done and debt --> transfer test that lending works with new vault
//  **

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/console2.sol";
import {Setup} from "./utils/Setup_ArbitrumFork.sol";
import "../lending/ExponentialNoError.sol";
import "../interfaces/IVaultManager.sol";

contract VaultMigrationTest is Setup, ExponentialNoError {
    function setUp() public virtual override {
        console2.log("VAULT TEST");
        super.setUp();
    }
    function test_CheckSetup() public {
        // TODO: check current price, do a swap
    }

    function test_Migrate() public {}
}
