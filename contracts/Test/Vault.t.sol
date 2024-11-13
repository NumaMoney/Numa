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
// forge coverage --report lcov
// xcz@DELL4764DSY:/mnt/e/dev/numa/Numa_github$ genhtml lcov.info -o html
//$Env:FOUNDRY_PROFILE = 'lite'
// npx prettier --write --plugin=prettier-plugin-solidity 'contracts/**/*.sol'
contract VaultTest is Setup, ExponentialNoError {
    uint vaultBalance;
    uint userBalance;

    uint buyfee;
    uint sellfee;
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

        VaultMockOracle VMO = new VaultMockOracle();
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

        VaultMockOracle VMO = new VaultMockOracle();
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
        // uint inputreth = 2 ether;
        // uint inputnuma = 1000 ether;
        // vm.startPrank(userA);
        // // mint synthetics
        // numa.approve(address(moneyPrinter),10000000 ether);
        // moneyPrinter.mintAssetOutputFromNuma(address(nuUSD),20000 ether,10000000 ether,userA);
        // moneyPrinter.mintAssetOutputFromNuma(address(nuBTC),1 ether,10000000 ether,userA);
        // // deploy 2nd vault
        // VaultOracleSingle vo2 = new VaultOracleSingle(
        //     WSTETH_ADDRESS_ARBI,
        //     PRICEFEEDWSTETHETH_ARBI,
        //     402 * 86400,
        //     UPTIME_FEED_NULL
        // );
        // NumaVault v2 = _setupVault(vo2,
        // address(numaMinter),address(vaultManager),numa,
        // 0,0);
        // v2.setFeeAddress(vaultFeeReceiver, false);
        // v2.setRwdAddress(vaultRwdReceiver, false);
        // TODO
        // check price with 2nd vault, should be the same
        // check that we can't buy from 2nd vault
        // send some wseth
        // check new price f
        // check buys/sells, coherent with prices
        // check CF from multiple vaults
        // // check buy price
        // uint balEthMinusSynthValue = (vaultBalance * vault.last_lsttokenvalueWei()) / 1 ether - nuAssetMgr.getTotalSynthValueEth();
        // uint numaAmountNoFee = FullMath.mulDiv(
        //     ((inputreth * vault.last_lsttokenvalueWei()) / 1 ether),
        //     (numa.totalSupply()),
        //     balEthMinusSynthValue
        // );
        // // fees
        // uint numaAmountWithFee = (numaAmountNoFee * buyfee) / 1 ether;
        // uint numaAmount = vault.lstToNuma(inputreth);
        // assertEq(numaAmountWithFee, numaAmount);
        // rEth.approve(address(vault), inputreth);
        // numa.approve(address(vault), inputnuma);
        // // BUY
        // uint balUserA = numa.balanceOf(userA);
        // uint buyAmount = vault.buy(inputreth, numaAmount, userA);
        // assertEq(buyAmount, numaAmount);
        // assertEq(numa.balanceOf(userA) - balUserA, numaAmount);
        // // SELL
        // uint balrEthUserA = rEth.balanceOf(userA);
        // numa.approve(address(vault), inputnuma);
        // uint lstAmount = vault.numaToLst(inputnuma);
        // // compare price
        // balEthMinusSynthValue = (rEth.balanceOf(address(vault)) * vault.last_lsttokenvalueWei()) / 1 ether - nuAssetMgr.getTotalSynthValueEth();
        // uint rEthAmountNoFee = FullMath.mulDiv(
        //     FullMath.mulDiv(inputnuma, balEthMinusSynthValue, (numa.totalSupply())),
        //     1 ether,
        //     vault.last_lsttokenvalueWei()
        // );
        // assertEq((rEthAmountNoFee * sellfee) / 1 ether, lstAmount);
        // uint buyAmountrEth = vault.sell(inputnuma, lstAmount, userA);
        // assertEq(buyAmountrEth, lstAmount);
        // assertEq(rEth.balanceOf(userA) - balrEthUserA, lstAmount);
    }

    //   it('with another vault', async function ()
    //   {
    //     // vault1 needs some rETH
    //     //await sendEthToVault();

    //     //
    //     let address2 = "0x513c7e3a9c69ca3e22550ef58ac1c0088e918fff";
    //     await helpers.impersonateAccount(address2);
    //     const impersonatedSigner2 = await ethers.getSigner(address2);
    //     await helpers.setBalance(address2,ethers.parseEther("10"));
    //     const wstEth_contract  = await hre.ethers.getContractAt(ERC20abi, wstETH_ADDRESS);
    //     //
    //     // await VO.setTokenFeed(wstETH_ADDRESS,wstETH_FEED);
    //     // compute prices
    //     let chainlinkInstance = await hre.ethers.getContractAt(artifacts.AggregatorV3, RETH_FEED);
    //     let latestRoundData = await chainlinkInstance.latestRoundData();
    //     let latestRoundPrice = Number(latestRoundData.answer);
    //     //let decimals = Number(await chainlinkInstance.decimals());
    //     let chainlinkInstance2 = await hre.ethers.getContractAt(artifacts.AggregatorV3, wstETH_FEED);
    //     let latestRoundData2 = await chainlinkInstance2.latestRoundData();
    //     let latestRoundPrice2 = Number(latestRoundData2.answer);

    //     // deploy
    //     let Vault2 = await ethers.deployContract("NumaVault",
    //     [numa_address,wstETH_ADDRESS,ethers.parseEther("1"),VO_ADDRESS2,minterAddress]);

    //     await Vault2.waitForDeployment();
    //     let VAULT2_ADDRESS = await Vault2.getAddress();
    //     console.log('vault wstETH address: ', VAULT2_ADDRESS);

    //     await VM.addVault(VAULT2_ADDRESS);
    //     await Vault2.setVaultManager(VM_ADDRESS);

    //     // add vault as a minter
    //     const Minter = await ethers.getContractFactory('NumaMinter');
    //     let theMinter = await Minter.attach(minterAddress);
    //     await theMinter.addToMinters(VAULT2_ADDRESS);

    //     // price before feeding vault2

    //     buyprice = await Vault1.getBuyNumaSimulateExtract(ethers.parseEther("2"));
    //     let buyprice2 = await Vault2.getBuyNumaSimulateExtract(ethers.parseEther("2"));

    //     //vault1Bal = BigInt(ethers.formatEther(vault1Bal));
    //     let buypricerefnofees = (ethers.parseEther("2")*ethers.parseEther("10000000"))/(vault1Bal);
    //     let buypriceref = buypricerefnofees - BigInt(5) * buypricerefnofees/BigInt(100);

    //     let buypricerefnofees2 = (buypricerefnofees*BigInt(latestRoundPrice2))/BigInt(latestRoundPrice);
    //     let buypriceref2 = buypricerefnofees2 - BigInt(5) * buypricerefnofees2/BigInt(100);

    //     expect(buypriceref).to.equal(buyprice);
    //     expect(buypriceref2).to.be.closeTo(buyprice2, epsilon);

    //     bal0 = await wstEth_contract.balanceOf(address2);
    //     // transfer to signer so that it can buy numa
    //     await wstEth_contract.connect(impersonatedSigner2).transfer(defaultAdmin,ethers.parseEther("5"));
    //     // transfer to vault to initialize price
    //     await wstEth_contract.connect(impersonatedSigner2).transfer(VAULT2_ADDRESS,ethers.parseEther("100"));

    //     bal1 = await wstEth_contract.balanceOf(VAULT2_ADDRESS);

    //     let totalBalancerEth = vault1Bal + (ethers.parseEther("100")*BigInt(latestRoundPrice2))/BigInt(latestRoundPrice);
    //     let totalBalancewstEth = ethers.parseEther("100") + (vault1Bal*BigInt(latestRoundPrice))/BigInt(latestRoundPrice2);

    //     let buypricerefnofeesrEth = (ethers.parseEther("2")*ethers.parseEther("10000000"))/(totalBalancerEth);
    //     let buypricerefnofeeswstEth = (ethers.parseEther("2")*ethers.parseEther("10000000"))/(totalBalancewstEth);

    //     buypriceref = buypricerefnofeesrEth - BigInt(5) * buypricerefnofeesrEth/BigInt(100);
    //     buypriceref2 = buypricerefnofeeswstEth - BigInt(5) * buypricerefnofeeswstEth/BigInt(100);

    //     buyprice = await Vault1.getBuyNumaSimulateExtract(ethers.parseEther("2"));
    //     buyprice2 = await Vault2.getBuyNumaSimulateExtract(ethers.parseEther("2"));

    //     expect(buypriceref).to.be.closeTo(buyprice, epsilon);
    //     expect(buypriceref2).to.be.closeTo(buyprice2, epsilon);

    //     // make vault Numa minter
    //     //await numa.grantRole(roleMinter, VAULT2_ADDRESS);
    //     // set fee address
    //     await Vault2.setFeeAddress(await signer3.getAddress(),false);

    //     // unpause it
    //     await Vault2.unpause();
    //     // approve wstEth to be able to buy
    //     await wstEth_contract.connect(owner).approve(VAULT2_ADDRESS,ethers.parseEther("2"));

    //     let balfee = await wstEth_contract.balanceOf(await signer3.getAddress());

    //     await Vault2.buy(ethers.parseEther("2"),buypriceref2 - epsilon,await signer2.getAddress());

    //     // let balbuyer = await numa.balanceOf(await signer2.getAddress());
    //     // bal1 = await wstEth_contract.balanceOf(VAULT2_ADDRESS);
    //     // balfee = await wstEth_contract.balanceOf(await signer3.getAddress());

    //     // let fees = BigInt(1) * ethers.parseEther("2")/BigInt(100);

    //     // expect(balbuyer).to.be.closeTo(buypriceref2, epsilon);
    //     // expect(bal1).to.equal(ethers.parseEther("100") + ethers.parseEther("2")- BigInt(1) * ethers.parseEther("2")/BigInt(100));

    //     // expect(balfee).to.equal(fees);
    //   });
}
