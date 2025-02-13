// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/console2.sol";
import {Setup} from "./utils/SetupDeployNuma_Arbitrum.sol";
import "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import "../lending/ExponentialNoError.sol";
import "../interfaces/IVaultManager.sol";

import "./mocks/VaultMockOracle.sol";
import {VaultOracleSingle} from "../NumaProtocol/VaultOracleSingle.sol";
import {NumaVault} from "../NumaProtocol/NumaVault.sol";
import {NumaOFT} from "../layerzero/NumaOFT.sol";
import {NumaOFTAdapter} from "../layerzero/NumaOFTAdapter.sol";
import "@openzeppelin/contracts_5.0.2/token/ERC20/ERC20.sol";


// OApp imports
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

// OFT imports
import { IOFT, SendParam, OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import { OFTMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";

// DevTools imports
import { TestHelperOz5 } from "./test-devtools-evm-foundry/contracts/TestHelperOz5.sol";


// forge coverage --report lcov
//$Env:FOUNDRY_PROFILE = 'lite'
// npx prettier --write --plugin=prettier-plugin-solidity 'contracts/**/*.sol'
contract BridgeTest is Setup, ExponentialNoError,TestHelperOz5 {


    using OptionsBuilder for bytes;

    uint32 private aEid = 1;
    uint32 private bEid = 2;


    NumaOFTAdapter private aOFTAdapter;
    NumaOFT private bOFT;
    uint initialBalance;

    function setUp() public virtual override {
        console2.log("BRIDGE TEST");
        super.setUp();
        // TestHelperOz5 setup
        setUp2();

        // TODO: can I Use my current chain ? (arbi fork)        
        //setUpEndpoints(2, LibraryType.UltraLightNode);

        //aToken = ERC20Mock(_deployOApp(type(ERC20Mock).creationCode, abi.encode("Token", "TOKEN")));

        // console2.log("deploying numa OFT adapter");
        // vm.startPrank(deployer);
        // aOFTAdapter = new NumaOFTAdapter(address(numa),address(endpoints[aEid]),deployer);

        // aOFTAdapter = NumaOFTAdapter(
        //     _deployOApp(
        //         type(NumaOFTAdapter).creationCode,
        //         abi.encode(address(numa), address(endpoints[aEid]), address(this))
        //     )
        // );

        // bOFT = NumaOFT(
        //     _deployOApp(
        //         type(NumaOFT).creationCode,
        //         abi.encode("Numa", "NUMA", address(endpoints[bEid]), address(this))
        //     )
        // );

        // config and wire the ofts
        // address[] memory ofts = new address[](2);
        // ofts[0] = address(aOFTAdapter);
        // ofts[1] = address(bOFT);
        // this.wireOApps(ofts);


        // // send some rEth to userA
        // vm.stopPrank();
        // vm.prank(deployer);
        // rEth.transfer(userA, 1000 ether);
        // vm.prank(deployer);
        // numa.transfer(userA, 1000000 ether);

        initialBalance = numa.balanceOf(userA);

    }

    function test_bridge() public {
        // TODO: this should not be possible directly
        // only through vault buy/sell

        // test that we can bridge numa and that totalsupply in vaultmanager is updated

        // bridge from chain 1 -> 2

        // bridge from chain 2 -> 1

    }

    function test_send_oft_adapter() public {
    //     uint256 tokensToSend = 1 ether;
    //     bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    //     SendParam memory sendParam = SendParam(
    //         bEid,
    //         addressToBytes32(userB),
    //         tokensToSend,
    //         tokensToSend,
    //         options,
    //         "",
    //         ""
    //     );
    //     MessagingFee memory fee = aOFTAdapter.quoteSend(sendParam, false);

    //     assertEq(numa.balanceOf(userA), initialBalance);
    //     assertEq(numa.balanceOf(address(aOFTAdapter)), 0);
    //     assertEq(bOFT.balanceOf(userB), 0);

    //     vm.prank(userA);
    //     numa.approve(address(aOFTAdapter), tokensToSend);

    //     // console2.log("a token supply BEFORE",aToken.totalSupply());
    //     // console2.log("dst oft token supply BEFORE",bOFT.totalSupply());

    //     vm.prank(userA);
    //     //aOFTAdapter.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
    //     (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) = aOFTAdapter.send{ value: fee.nativeFee }(
    //         sendParam,
    //         fee,
    //         payable(address(this))
    //     );

    //     //console2.log("receipt info",oftReceipt.amountReceivedLD);


    //     verifyPackets(bEid, addressToBytes32(address(bOFT)));

    //     assertEq(numa.balanceOf(userA), initialBalance - tokensToSend);
    //     assertEq(numa.balanceOf(address(aOFTAdapter)), tokensToSend);
    //     assertEq(bOFT.balanceOf(userB), tokensToSend);


    //     console2.log("adapter contract AFTER",numa.balanceOf(address(aOFTAdapter)));
    //     console2.log("user A balance after AFTER",numa.balanceOf(userA));

    //     console2.log("b token balance after",bOFT.balanceOf(userB));
        

    //     console2.log("************************************************************");

    //     sendParam = SendParam(
    //         aEid,
    //         addressToBytes32(userA),
    //         tokensToSend,
    //         tokensToSend,
    //         options,
    //         "",
    //         ""
    //     );
    //    fee = bOFT.quoteSend(sendParam, false);
    //     vm.prank(userB);
    //     (msgReceipt, oftReceipt) = bOFT.send{ value: fee.nativeFee }(
    //         sendParam,
    //         fee,
    //         payable(address(this))
    //     );
    //      verifyPackets(aEid, addressToBytes32(address(aOFTAdapter)));


    //     console2.log("adapter contract AFTER BACK",numa.balanceOf(address(aOFTAdapter)));
    //     console2.log("user A balance after AFTER BACK",numa.balanceOf(userA));

    //     console2.log("b token balance after BACK",bOFT.balanceOf(userB));


    }

    // todo 3 chains
}