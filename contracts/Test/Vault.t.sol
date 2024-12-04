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
import "@openzeppelin/contracts_5.0.2/token/ERC20/ERC20.sol";

// forge coverage --report lcov
//$Env:FOUNDRY_PROFILE = 'lite'
// npx prettier --write --plugin=prettier-plugin-solidity 'contracts/**/*.sol'
contract VaultTest is Setup, ExponentialNoError {
    
    uint inputreth = 2 ether;
    uint vaultBalance;
    uint userBalance;

    uint buyfee;
    uint sellfee;

    ERC20 wsteth;
    function setUp() public virtual override {
        console2.log("VAULT TEST");
        super.setUp();
        // send some rEth to userA
        vm.stopPrank();
        vm.prank(deployer);
        rEth.transfer(userA, 1000 ether);
        vm.prank(deployer);
        numa.transfer(userA, 1000000 ether);
        //
        vaultBalance = rEth.balanceOf(address(vault));
        userBalance = rEth.balanceOf(userA);

        buyfee = vaultManager.buy_fee();
        sellfee = vaultManager.sell_fee();

        wsteth = ERC20(WSTETH_ADDRESS_ARBI);
        deal({token: WSTETH_ADDRESS_ARBI, to: deployer, give: 100 ether});
    }

    function checkPrices(
        uint inputreth,
        uint inputnuma,
        uint supply,
        uint balEthMinusSynthValue
    ) internal view {
        // BUY
        // note: multiplying by last_lsttokenvalueWei() to match exactly what is done in the function
        uint numaAmountNoFee = FullMath.mulDiv(
            ((inputreth * vault.last_lsttokenvalueWei()) / 1 ether),
            (supply),
            balEthMinusSynthValue
        );
        // fees
        uint numaAmountWithFee = (numaAmountNoFee * buyfee) / 1 ether;

        uint numaAmount = vault.lstToNuma(inputreth);
        assertEq(numaAmountWithFee, numaAmount, "buy ko");

        // SELL
        uint rEthAmountNoFee = FullMath.mulDiv(
            FullMath.mulDiv(inputnuma, balEthMinusSynthValue, (supply)),
            1 ether,
            vault.last_lsttokenvalueWei()
        );
        uint rEthAmountWithFee = (rEthAmountNoFee * sellfee) / 1 ether;
        uint rEthAmount = vault.numaToLst(inputnuma);
        assertEq(rEthAmountWithFee, rEthAmount, "sell ko");
    }
    function test_GetPriceEmptyVaultAndWithdraw() public {
        uint balDeployer = rEth.balanceOf(deployer);
        assertGt(vaultBalance, 0);
        vm.prank(deployer);
        vault.withdrawToken(address(rEth), vaultBalance, deployer);

        assertEq(rEth.balanceOf(address(vault)), 0);
        assertEq(rEth.balanceOf(deployer) - balDeployer, vaultBalance);

        vm.expectRevert("empty vaults");
        vault.lstToNuma(2 ether);
        vm.expectRevert("empty vaults");
        vault.numaToLst(1000 ether);
    }
    function test_GetPriceSimple() public view {
        uint inputreth = 2 ether;
        uint inputnuma = 1000 ether;
        //
        checkPrices(
            inputreth,
            inputnuma,
            numaSupply,
            (vaultBalance * vault.last_lsttokenvalueWei()) / 1 ether
        );
    }

    function test_GetPriceSimpleDecay() public {
        uint inputreth = 2 ether;
        uint inputnuma = 1000 ether;

        // decay not started
        uint removedSupply = 4000000 ether;

        vm.prank(deployer);
        vaultManager.setDecayValues(removedSupply, 400 * 24 * 3600, 0, 0, 0);

        // DECAY NOT STARTED
        checkPrices(
            inputreth,
            inputnuma,
            numa.totalSupply() - removedSupply,
            (rEth.balanceOf(address(vault)) * vault.last_lsttokenvalueWei()) /
                1 ether
        );

        // START DECAY
        vm.prank(deployer);
        vaultManager.startDecay();

        vm.warp(block.timestamp + 300 * 24 * 3600);

        uint decayedSupply = numaSupply - removedSupply / 4;
        assertEq(decayedSupply, vaultManager.getNumaSupply());

        checkPrices(
            inputreth,
            inputnuma,
            decayedSupply,
            (vaultBalance * vault.last_lsttokenvalueWei()) / 1 ether
        );

        // DECAY OVER
        vm.warp(block.timestamp + 100 * 24 * 3600 + 1);
        decayedSupply = numaSupply;
        assertEq(decayedSupply, vaultManager.getNumaSupply());

        checkPrices(
            inputreth,
            inputnuma,
            decayedSupply,
            (vaultBalance * vault.last_lsttokenvalueWei()) / 1 ether
        );

        // START NEW DECAY
        vm.prank(deployer);
        removedSupply = numaSupply / 2;
        vaultManager.setDecayValues(removedSupply, 100 * 24 * 3600, 0, 0, 0);
        vm.prank(deployer);
        vaultManager.startDecay();
        vm.warp(block.timestamp + 25 * 24 * 3600);
        decayedSupply = numaSupply - (3 * removedSupply) / 4;

        checkPrices(
            inputreth,
            inputnuma,
            decayedSupply,
            (vaultBalance * vault.last_lsttokenvalueWei()) / 1 ether
        );
    }

    function test_GetPriceConstantDecay() public {
        // TODO, & test 2nd decay too & test cancel decay?
    }

    function test_GetPriceWithMintedSynth() public {
        uint inputreth = 2 ether;
        uint inputnuma = 1000 ether;

        // mint synthetics
        // 100000 nuUSD
        uint nuUSDamount = 100000;
        vm.prank(deployer);
        nuUSD.mint(deployer, nuUSDamount);

        uint synthValueEth = (1e8 * nuUSDamount) / (uint(ethusd));
        assertGt(synthValueEth, 0);
        checkPrices(
            inputreth,
            inputnuma,
            numaSupply,
            (vaultBalance * vault.last_lsttokenvalueWei()) /
                1 ether -
                synthValueEth
        );
    }

    function test_GetPriceWithRebase() public {
        uint inputreth = 2 ether;
        uint inputnuma = 1000 ether;

        // set a mock rEth oracle to simulate rebase
        vm.stopPrank();
        vm.startPrank(deployer);
        // cancelling buy fee to compare amounts more easily
        vaultManager.setBuyFee(1 ether);

        uint numaAmount = vault.lstToNuma(inputreth);
        uint priceEth = vaultManager.numaToEth(
            inputnuma,
            IVaultManager.PriceType.BuyPrice
        );

        VaultMockOracle VMO = new VaultMockOracle(address(rEth));
        vault.setOracle(address(VMO));

        // set new price, simulate a 100% rebase
        uint lastprice = vault.last_lsttokenvalueWei();
        uint newprice = 2 * lastprice;

        VMO.setPrice(newprice);
        (uint estimateRewards, uint newvalue, ) = vault.rewardsValue();
        assertEq(newvalue, newprice, "new price ko");

        // uint estimateRewardsEth = (estimateRewards * newprice)/1e18;
        // uint rwdEth = (vaultBalance * (newprice - lastprice))/1e18;
        // assertApproxEqAbs(estimateRewardsEth, rwdEth,1,"estimate rwd ko");

        uint rwdREth = (vaultBalance * (newprice - lastprice)) / newprice;
        assertEq(estimateRewards, rwdREth, "estimate rwd ko");

        // price in Eth should be the same
        uint priceEthAfter = vaultManager.numaToEth(
            inputnuma,
            IVaultManager.PriceType.BuyPrice
        );
        assertApproxEq(priceEthAfter, priceEth, 1, "price after ko 0");
        //
        uint numaAmountAfter = vault.lstToNuma(inputreth);
        assertApproxEq(numaAmountAfter, 2 * numaAmount, 1, "numa amount ko");

        // extract and price should stays the same
        vm.warp(block.timestamp + 24 * 3600 + 1);
        vault.updateVault();
        uint balrwd = rEth.balanceOf(vaultRwdReceiver);
        assertApproxEq(balrwd, estimateRewards, 200, "rwds ko");

        uint priceEthAfterExtract = vaultManager.numaToEth(
            inputnuma,
            IVaultManager.PriceType.BuyPrice
        );
        assertApproxEq(
            priceEthAfter,
            priceEthAfterExtract,
            0,
            "price after ko 1"
        );
    }

    function test_BuySell() public {
        uint inputreth = 2 ether;
        uint inputnuma = 1000 ether;
        uint numaAmount = vault.lstToNuma(inputreth);
        uint lstAmount = vault.numaToLst(inputnuma);
        vm.prank(deployer);
        vault.pause();
        // revert if paused
        vm.prank(userA);
        vm.expectRevert();
        vault.buy(inputreth, numaAmount, userA);
        vm.expectRevert();
        vault.sell(inputnuma, lstAmount, userA);
        vm.prank(deployer);
        vault.unpause();
        vm.prank(deployer);
        vault.pauseBuy(true);
        vm.expectRevert("buy paused");
        vault.buy(inputreth, numaAmount, userA);
        // should not revert
        vm.startPrank(userA);
        numa.approve(address(vault), inputnuma);
        vault.sell(inputnuma, lstAmount, userA);

        vm.stopPrank();
        vm.prank(deployer);
        vault.pauseBuy(false);

        vm.startPrank(userA);
        rEth.approve(address(vault), inputreth);
        numaAmount = vault.lstToNuma(inputreth);
        vm.expectRevert("Min NUMA");
        vault.buy(inputreth, numaAmount + 1, userA);

        numa.approve(address(vault), inputnuma);
        lstAmount = vault.numaToLst(inputnuma);
        vm.expectRevert("Min Token");
        vault.sell(inputnuma, lstAmount + 1, userA);

        // this one should go through
        uint balUserA = numa.balanceOf(userA);
        numaAmount = vault.lstToNuma(inputreth);
        uint buyAmount = vault.buy(inputreth, numaAmount, userA);
        assertEq(buyAmount, numaAmount);
        assertEq(numa.balanceOf(userA) - balUserA, numaAmount);

        uint balrEthUserA = rEth.balanceOf(userA);
        numa.approve(address(vault), inputnuma);
        lstAmount = vault.numaToLst(inputnuma);
        uint buyAmountrEth = vault.sell(inputnuma, lstAmount, userA);
        assertEq(buyAmountrEth, lstAmount);
        assertEq(rEth.balanceOf(userA) - balrEthUserA, lstAmount);
    }

    function test_BuySellRwdExtraction() public {
        uint inputreth = 2 ether;
        uint inputnuma = 1000 ether;

        // set a mock rEth oracle to simulate rebase
        vm.stopPrank();
        vm.startPrank(deployer);
        // cancelling buy fee to compare amounts more easily
        vaultManager.setBuyFee(1 ether);

        VaultMockOracle VMO = new VaultMockOracle(address(rEth));
        vault.setOracle(address(VMO));

        // set new price, simulate a 100% rebase
        uint lastprice = vault.last_lsttokenvalueWei();
        uint newprice = 2 * lastprice;

        VMO.setPrice(newprice);
        (uint estimateRewards, uint newvalue, ) = vault.rewardsValue();
        assertEq(newvalue, newprice);

        // BUY
        // extract when buying
        vm.warp(block.timestamp + 24 * 3600 + 1);
        uint numaAmount = vault.lstToNuma(inputreth);
        uint balUserA = numa.balanceOf(userA);

        uint balRwdAddy = rEth.balanceOf(vaultRwdReceiver);

        rEth.approve(address(vault), inputreth);
        // some slippage because, we are extracting rewards so estimation can be a little bit off
        uint buyAmount = vault.buy(inputreth, numaAmount - 100, userA);
        assertApproxEqAbs(buyAmount, numaAmount, 100);
        assertEq(numa.balanceOf(userA) - balUserA, buyAmount);
        assertEq(
            rEth.balanceOf(vaultRwdReceiver) - balRwdAddy,
            estimateRewards
        );

        // SELL
        newprice = 2 * newprice;

        VMO.setPrice(newprice);
        (estimateRewards, newvalue, ) = vault.rewardsValue();
        assertEq(newvalue, newprice);
        assertGt(estimateRewards, 0);
        //

        // extract when selling
        vm.warp(block.timestamp + 24 * 3600 + 1);
        uint rethAmount = vault.numaToLst(inputnuma);

        balRwdAddy = rEth.balanceOf(vaultRwdReceiver);
        balUserA = rEth.balanceOf(userA);
        numa.approve(address(vault), inputnuma);
        buyAmount = vault.sell(inputnuma, rethAmount, userA);
        assertEq(buyAmount, rethAmount);
        assertEq(rEth.balanceOf(userA) - balUserA, rethAmount);
        assertEq(
            rEth.balanceOf(vaultRwdReceiver) - balRwdAddy,
            estimateRewards
        );
    }

    function test_Fees() public {
        uint inputreth = 2 ether;

        uint inputnuma = 1000 ether;

        vm.startPrank(userA);
        uint balFeeAddress = rEth.balanceOf(vaultFeeReceiver);
        // buy
        rEth.approve(address(vault), inputreth);
        vault.buy(inputreth, vault.lstToNuma(inputreth), userA);
        uint feesRwd = ((vault.fees() *
            ((1 ether - vaultManager.getBuyFee()) * inputreth)) / 1 ether) /
            1000;
        // % sent to fee_address
        assertEq(rEth.balanceOf(vaultFeeReceiver) - balFeeAddress, feesRwd);
        // rest is used for numa backing
        assertEq(
            rEth.balanceOf(address(vault)) - vaultBalance,
            inputreth - feesRwd
        );

        // sell
        balFeeAddress = rEth.balanceOf(vaultFeeReceiver);
        vaultBalance = rEth.balanceOf(address(vault));
        numa.approve(address(vault), inputnuma);
        uint receivedREth = vault.sell(
            inputnuma,
            vault.numaToLst(inputnuma),
            userA
        );

        // feesRwd = (vault.fees()*
        // ((1 ether - vaultManager.getSellFeeOriginal()) *vaultManager.numaToToken(inputnuma,vault.last_lsttokenvalueWei(),1 ether,1000))/1 ether)/1000;
        // % sent to fee_address
        //assertEq(rEth.balanceOf(vaultFeeReceiver) - balFeeAddress, feesRwd);

        feesRwd =
            (receivedREth * 1 ether) /
            vaultManager.getSellFeeOriginal() -
            receivedREth;
        feesRwd = (feesRwd * vault.fees()) / 1000;
        assertEq(rEth.balanceOf(vaultFeeReceiver) - balFeeAddress, feesRwd);
        // rest is used for numa backing
        assertEq(
            vaultBalance - rEth.balanceOf(address(vault)),
            receivedREth + feesRwd
        );
    }
    function test_BuySellDecay() public {
        uint inputnuma = 1000 ether;
        vm.prank(deployer);
        uint removedSupply = numaSupply / 2;
        vaultManager.setDecayValues(removedSupply, 100 * 24 * 3600, 0, 0, 0);
        vm.prank(deployer);
        vaultManager.startDecay();
        vm.warp(block.timestamp + 25 * 24 * 3600);
        uint decayedSupply = numaSupply - (3 * removedSupply) / 4;

        assertLt(vaultManager.getNumaSupply(), numaSupply);
        assertEq(vaultManager.getNumaSupply(), decayedSupply);

        uint rethAmount = vault.numaToLst(inputnuma);

        uint balUserA = rEth.balanceOf(userA);
        vm.startPrank(userA);
        numa.approve(address(vault), inputnuma);
        uint buyAmount = vault.sell(inputnuma, rethAmount, userA);
        assertEq(buyAmount, rethAmount);
        assertEq(rEth.balanceOf(userA) - balUserA, rethAmount);
    }

    function test_BuySellSynthSupply() public {
        uint inputreth = 2 ether;
        uint inputnuma = 1000 ether;

        vm.startPrank(userA);
        // mint synthetics
        uint nuUSDAmount = 20000 ether;
        uint nuBTCAmount = 1 ether;
        numa.approve(address(moneyPrinter), 10000000 ether);
        console2.log(
            "synth value before: ",
            nuAssetMgr.getTotalSynthValueEth() / uint(ethusd)
        );
        moneyPrinter.mintAssetOutputFromNuma(
            address(nuUSD),
            nuUSDAmount,
            10000000 ether,
            userA
        );
        console2.log("nuusd supply", nuUSD.totalSupply());
        console2.log("ethusd", ethusd);
        console2.log(
            "synth value USD after minting nuUSD: ",
            (nuAssetMgr.getTotalSynthValueEth() * uint(ethusd)) / 1e26
        );

        moneyPrinter.mintAssetOutputFromNuma(
            address(nuBTC),
            nuBTCAmount,
            10000000 ether,
            userA
        );
        console2.log(
            "synth value after minting nuBTC: ",
            (nuAssetMgr.getTotalSynthValueEth() * uint(ethusd)) / 1e26
        );

        // check buy price
        uint balEthMinusSynthValue = (vaultBalance *
            vault.last_lsttokenvalueWei()) /
            1 ether -
            nuAssetMgr.getTotalSynthValueEth();
        uint numaAmountNoFee = FullMath.mulDiv(
            ((inputreth * vault.last_lsttokenvalueWei()) / 1 ether),
            (numa.totalSupply()),
            balEthMinusSynthValue
        );
        // fees
        uint numaAmountWithFee = (numaAmountNoFee * buyfee) / 1 ether;

        uint numaAmount = vault.lstToNuma(inputreth);
        assertEq(numaAmountWithFee, numaAmount);

        rEth.approve(address(vault), inputreth);
        numa.approve(address(vault), inputnuma);

        // BUY
        uint balUserA = numa.balanceOf(userA);
        uint buyAmount = vault.buy(inputreth, numaAmount, userA);
        assertEq(buyAmount, numaAmount);
        assertEq(numa.balanceOf(userA) - balUserA, numaAmount);

        // SELL
        uint balrEthUserA = rEth.balanceOf(userA);
        numa.approve(address(vault), inputnuma);
        uint lstAmount = vault.numaToLst(inputnuma);
        // compare price
        balEthMinusSynthValue =
            (rEth.balanceOf(address(vault)) * vault.last_lsttokenvalueWei()) /
            1 ether -
            nuAssetMgr.getTotalSynthValueEth();
        uint rEthAmountNoFee = FullMath.mulDiv(
            FullMath.mulDiv(
                inputnuma,
                balEthMinusSynthValue,
                (numa.totalSupply())
            ),
            1 ether,
            vault.last_lsttokenvalueWei()
        );

        assertEq((rEthAmountNoFee * sellfee) / 1 ether, lstAmount);

        uint buyAmountrEth = vault.sell(inputnuma, lstAmount, userA);
        assertEq(buyAmountrEth, lstAmount);
        assertEq(rEth.balanceOf(userA) - balrEthUserA, lstAmount);
    }

    function test_BuySell2ndVault() public {
        uint amountBuy = vaultManager.ethToNuma(
            inputreth,
            IVaultManager.PriceType.BuyPrice
        );


        vm.startPrank(deployer);
        // deploy 2nd vault
        VaultOracleSingle vo2 = new VaultOracleSingle(
            WSTETH_ADDRESS_ARBI,
            PRICEFEEDWSTETHETH_ARBI,
            402 * 86400,
            UPTIME_FEED_NULL
        );
        NumaVault v2 = _setupVault(vo2,
        address(numaMinter),address(vaultManager),numa,
        0,0);

        v2.setFeeAddress(vaultFeeReceiver, false);
        v2.setRwdAddress(vaultRwdReceiver, false);

        uint amountBuy2 = vaultManager.ethToNuma(
            inputreth,
            IVaultManager.PriceType.BuyPrice
        );

        assertEq(amountBuy,amountBuy2);

        //send some wseth
        uint wstEthBal = 50 ether;
        deal({token: WSTETH_ADDRESS_ARBI, to: address(v2), give: wstEthBal});
        amountBuy2 = vaultManager.ethToNuma(
            inputreth,
            IVaultManager.PriceType.BuyPrice
        );
        assertGt(amountBuy,amountBuy2);

        // check prices
        uint numaAmountNoFee = FullMath.mulDiv(
            ((inputreth * vault.last_lsttokenvalueWei()) / 1 ether),
            (numaSupply),
            ((vaultBalance * vault.last_lsttokenvalueWei()) +(wstEthBal * v2.last_lsttokenvalueWei()))/ 1 ether
        );
        // fees
        uint numaAmountWithFee = (numaAmountNoFee * buyfee) / 1 ether;

        uint numaAmount = vault.lstToNuma(inputreth);
        assertEq(numaAmountWithFee, numaAmount, "buy ko");

        // SELL
        uint rEthAmountNoFee = FullMath.mulDiv(
            FullMath.mulDiv(1000 ether,  ((vaultBalance * vault.last_lsttokenvalueWei()) +(wstEthBal * v2.last_lsttokenvalueWei()))/ 1 ether, (numaSupply)),
            1 ether,
            vault.last_lsttokenvalueWei()
        );
        uint rEthAmountWithFee = (rEthAmountNoFee * sellfee) / 1 ether;
        uint rEthAmount = vault.numaToLst(1000 ether);
        assertEq(rEthAmountWithFee, rEthAmount, "sell ko");

        // testing buy from wsteth too 
        numaAmountNoFee = FullMath.mulDiv(
            ((inputreth * v2.last_lsttokenvalueWei()) / 1 ether),
            (numaSupply),
            ((vaultBalance * vault.last_lsttokenvalueWei()) +(wstEthBal * v2.last_lsttokenvalueWei()))/ 1 ether
        );
        // fees
        numaAmountWithFee = (numaAmountNoFee * buyfee) / 1 ether;

        numaAmount = v2.lstToNuma(inputreth);
        assertEq(numaAmountWithFee, numaAmount, "buy ko");


        uint balnuma = numa.balanceOf(userA);
        uint balwstEth = wsteth.balanceOf(address(v2));

        
        wsteth.approve(address(v2),100 ether);

        v2.unpause();
        assertEq(v2.buy(inputreth, numaAmount, userA),numaAmount);

        // % sent to fee_address
        assertEq(wsteth.balanceOf(vaultFeeReceiver), ((v2.fees() *
            ((1 ether - vaultManager.getBuyFee()) * inputreth)) / 1 ether) /
            1000);


        assertEq(numa.balanceOf(userA) - balnuma,numaAmount);
        assertEq(wsteth.balanceOf(vaultFeeReceiver)+ERC20(WSTETH_ADDRESS_ARBI).balanceOf(address(v2)) - balwstEth,inputreth);

        // check CF from multiple vaults
        
    }

}
