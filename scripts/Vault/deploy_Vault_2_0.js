const { ethers, upgrades } = require("hardhat");

// On arbitrum
// numa 0x7FB7EDe54259Cb3D4E1EaF230C7e2b1FfC951E9A
// numaVault: 0x78E88887d80451cB08FDc4b9046C9D01FB8d048D
// vaultManager: 0x7Fb6e0B7e1B34F86ecfC1E37C863Dd0B9D4a0B1F

// Q: compute new decay parameters from current state
// il faudra getNumaSupply + getconstantremove

// faudra déduire _decayPeriod, _initialRemovedSupply
//

// Par exemple
// getNumaSupply 6082297182546751867410269 
// constant 500000000000000000000000
// totalSupply 7679177319533053237273283

// 6082297182546751867410269 = 7679177319533053237273283  - currentRemovedSupply - 500000000000000000000000;
// currentRemovedSupply = 7679177319533053237273283 - 500000000000000000000000 - 6082297182546751867410269
// 1096880136986301369863014


// --> currentRemovedSupply
// --> constant + currentRemovedSupply & no decay


//  for sepolia test: 

// 0) (TEST ONLY)
//      - deploy fake rEth (if necessary)
//      - deploy numa (if necessary)    
//
// 1) (TEST ONLY) 
//      - deploy existing vault/vaultmanager, reth, etc... so that I can test updating

// 2) V2
//      - (TEST ONLY) deploy pool numa/USDC
//      - nuAssetManager
//      - numa minter
//      - vaultmanager
//      - vault oracle
//      - vault
//      - transfer rEth to vault to initialize price
//          Q: last_price will be initialized ok when tansferring? (extract will match this init?)
//          Note: pause before removing rETh
//      - migrate from old vault, then close old vault/vaultmanager

// 3) printer
//      - NumaOracle
//      - nuAssets nuUSD, nuBTC
//      - USDCtoETHConverter
//      - moneyprinter
//      - theMinter.addToMinters: vault & moneyprinter
//      - money printer can mint nuUSD
//      - moneyprinter set fees: print, burn & swap
//      - nuAM.addNuAsset

// 4) from isolated tests (before and some insides)
//    ** vault
//      - VM.setDecayValues/VM.startDecay();
//      - setRwdAddress
//      - setSellFeeParameters
//      - Vault1.unpause()  
//
//    ** printer&oracle
//      - VM setScalingParameters
//    ** lending
//      - setMaxBorrow
//      - comptroller
//      - numaPriceOracle
//      - setvault, _setPriceOracle
//      - deploy rateModel
//      - cNuma, cReth
//      - setCTokens(CNUMA_ADDRESS,CRETH_ADDRESS);
//      - setMinLiquidationsPc(250);//25% min
//      - comptroller._supportMarket(await cNuma.getAddress());
//      - comptroller._supportMarket(await cReth.getAddress());
//      - _setCollateralFactor
//      - setcloseFactor
//      - setMaxCF?
//      - _setLiquidationIncentive(ethers.parseEther("1.10"));
//      - setMaxLiquidationsProfit(ethers.parseEther("10"));

// Notes:

// - be careful of what could be frontrun at deploy, add pause if necessary, check each deploy 1 by 1
// - be careful when transferring from old vault. old vault should be paused first, numa could be minted a zero price!!!

// parameters:
//      - vault fee addresses
//      - fees
//      - sell fee scaling parameters
//      - synth scaling parameters
//      - money printer fees

// addresses:
// sepolia
let SIGNER_ADDRESS = "";
let USDC_ADDRESS = "";
let WETH_ADDRESS = "";
let RETH_ADDRESS = "";
let NUMA_USDC_POOL_ADDRESS = "";

// TODO
let UPTIME_FEED = "0x0000000000000000000000000000000000000000";// no sequencer up feed on sepolia
let VMO_ADDRESS = "";
let LST_ADDRESS = "";
let NUMA_ADDRESS = "";

//
let numaSupplyArbitrum = ethers.parseEther("7679177.319533");
let vaultREthBalanceArbitrum = ethers.parseEther("627.658723771");
let rEThPrice = "1.1198";

// for migrating simulation
let migrateVault = true;
let VAULT1_ADDRESS = "";
let Vault1;

const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));

async function main() {

    console.log("starting");
    const [signer] = await ethers.getSigners();
    SIGNER_ADDRESS = await signer.getAddress();

     // deploy numa
     const Numa = await ethers.getContractFactory('NUMA')
   

     const numa = await upgrades.deployProxy(
         Numa,
         [],
         {
             initializer: 'initialize',
             kind: 'uups'
         }
     )

     await numa.waitForDeployment();


     NUMA_ADDRESS = await numa.getAddress();
     console.log('Numa deployed to:', NUMA_ADDRESS);

     await numa.mint(
         signer.getAddress(),
         numaSupplyArbitrum
     );


     // deploy Lst mock
     let lstToken = await ethers.deployContract("LstTokenMock", [await signer.getAddress()]);
     await lstToken.waitForDeployment();
     LST_ADDRESS = await lstToken.getAddress();


    if (migrateVault) {
        console.log("deploying V1 VAULT");
       


        // *********************** nuAssetManager **********************************
        // TODO: deploy old version of these contracts
        let nuAM = await ethers.deployContract("nuAssetManagerOld",
            ["0x0000000000000000000000000000000000000000"]// no sequencer up feed on sepolia
        );
        await nuAM.waitForDeployment();
        let NUAM_ADDRESS = await nuAM.getAddress();
        console.log('nuAssetManager OLD  address: ', NUAM_ADDRESS);

        // *********************** vaultManager **********************************
        let VM = await ethers.deployContract("VaultManagerOld",
            [NUMA_ADDRESS, NUAM_ADDRESS]);

        await VM.waitForDeployment();
        let VM_ADDRESS = await VM.getAddress();
        console.log('vault manager OLD address: ', VM_ADDRESS);




        // using custom MockOracle as we don't have rEth chainlink feeds on sepolia
        let VMO = await ethers.deployContract("VaultMockOracle", []);
        await VMO.waitForDeployment();
        VMO_ADDRESS = await VMO.getAddress();

        await VMO.setPrice(ethers.parseEther(rEThPrice));

        // vault1 rETH
        Vault1 = await ethers.deployContract("NumaVaultOld",
            [NUMA_ADDRESS, LST_ADDRESS, ethers.parseEther("1"), VMO_ADDRESS]);


        await Vault1.waitForDeployment();
        VAULT1_ADDRESS = await Vault1.getAddress();
        console.log('vault rETH OLD address: ', VAULT1_ADDRESS);


        await VM.addVault(VAULT1_ADDRESS);
        await Vault1.setVaultManager(VM_ADDRESS);

        // fee address
        // use a contract to repro revert in etherscan
        FEE_ADDRESS = SIGNER_ADDRESS;
        RWD_ADDRESS = SIGNER_ADDRESS;
        await Vault1.setFeeAddress(FEE_ADDRESS, false);
        await Vault1.setRwdAddress(RWD_ADDRESS, false);

        // allow vault to mint numa       
        await numa.grantRole(roleMinter, VAULT1_ADDRESS);

        // TODO: decay amount/period same as current state arbitrum
        await VM.setDecayValues( 0, 0,ethers.parseEther("1096880.136986301369863014"));


        // init them, send lst, unpause, etc...
        // TODO: same quantity as arbitrum + check lastlstprice OK
        await lstToken.transfer(VAULT1_ADDRESS, vaultREthBalanceArbitrum);
        await Vault1.setBuyFee(ethers.parseEther("0.75"));//25%     
        await VM.startDecay();
        await Vault1.unpause();

        // check that we have same price than arbitrum/etherscan
        let priceV1 = await VM.GetPriceFromVaultWithoutFees(ethers.parseEther("1000"));
        console.log(priceV1);

        let numaSupply = await VM.getNumaSupply();
        console.log(numaSupply);

        let balanceEth = await VM.getTotalBalanceEth();
        console.log(balanceEth);

        // // deploy pool numa/USDC
        // TODO FOR PRINTER
        // // create numa/USDC univ3 pool
        // await initPoolETH(USDC_ADDRESS, numa_address, _fee, USDCPriceInNuma, nonfungiblePositionManager, USDC_ADDRESS);

        // let offset = 3600 * 100;// we should be able to run 100 tests
        // let timestamp = Math.ceil(Date.now() / 1000 + 300 + offset);
        // await addLiquidity(
        //     WETH_ADDRESS,
        //     numa_address,
        //     wethContract,
        //     numa,
        //     _fee,
        //     tickMin,
        //     tickMax,
        //     EthAmountNumaPool,
        //     NumaAmountNumaPool,
        //     BigInt(0),
        //     BigInt(0),
        //     signer,
        //     timestamp,
        //     nonfungiblePositionManager
        // );

        // await addLiquidity(
        //     USDC_ADDRESS,
        //     numa_address,
        //     usdcContract,
        //     numa,
        //     _fee,
        //     tickMin,
        //     tickMax,
        //     USDCAmountNumaPool,
        //     NumaAmountNumaPoolUSDC,
        //     BigInt(0),
        //     BigInt(0),
        //     signer,
        //     timestamp,
        //     nonfungiblePositionManager
        // );
        // let NUMA_USDC_POOL_ADDRESS = await factory.getPool(
        //     USDC_ADDRESS, numa_address, _fee,);



    }


    // new vault migration
    // Deploy vault
    // *********************** nuAssetManager **********************************
    let nuAM2 = await ethers.deployContract("nuAssetManager",
        [UPTIME_FEED]
    );
    await nuAM2.waitForDeployment();
    let NUAM_ADDRESS2 = await nuAM2.getAddress();
    console.log('nuAssetManager address: ', NUAM_ADDRESS2);

    // minter contract
    let theMinter = await ethers.deployContract("NumaMinter", []);
    await theMinter.waitForDeployment();
    let MINTER_ADDRESS = await theMinter.getAddress();
    await numa.grantRole(roleMinter, MINTER_ADDRESS);
    await theMinter.setTokenAddress(NUMA_ADDRESS);

    // *********************** vaultManager **********************************
    let VM2 = await ethers.deployContract("VaultManager",
        [NUMA_ADDRESS, NUAM_ADDRESS2]);
    await VM2.waitForDeployment();
    let VM_ADDRESS2 = await VM2.getAddress();
    console.log('vault manager address: ', VM_ADDRESS2);

    // we use mock oracle as we don't have a rEth/eth price feed on sepolia
    // let VOcustomHeartbeat = await ethers.deployContract("VaultOracleSingle",
    //     [LST_ADDRESS, RETH_FEED, 402 * 86400, UPTIME_FEED]);
    //await VOcustomHeartbeat.waitForDeployment();
    // let VO_ADDRESScustomHeartbeat = await VOcustomHeartbeat.getAddress();
    let VO_ADDRESScustomHeartbeat = VMO_ADDRESS;

    console.log('vault 1 oracle address: ', VO_ADDRESScustomHeartbeat);
    

    // *********************** NumaVault rEth **********************************
    let Vault1_2 = await ethers.deployContract("NumaVault",
        [NUMA_ADDRESS, LST_ADDRESS, ethers.parseEther("1"), VO_ADDRESScustomHeartbeat, MINTER_ADDRESS]);
    await Vault1_2.waitForDeployment();
    let VAULT1_ADDRESS2 = await Vault1_2.getAddress();
    console.log('vault rETH address: ', VAULT1_ADDRESS2);

    await VM2.addVault(VAULT1_ADDRESS2);
    await Vault1_2.setVaultManager(VM_ADDRESS2);

    // fee address
    await Vault1_2.setFeeAddress(SIGNER_ADDRESS, false);


    // TODO MIGRATE VAULT & UNPAUSE c(f old script migration)

    if (migrateVault)
    {
        // pause V1 vault
        await Vault1.pause();

        // transfer rEth to V2
        let balLst = await lstToken.balanceOf(VAULT1_ADDRESS);
        await Vault1.withdrawToken(LST_ADDRESS,balLst,VAULT1_ADDRESS2);
    }
    // setup V2 decay to match V1
    // TODO

    // unpause V2
    await Vault1_2.unpause();

    // check that we have same price than arbitrum/etherscan
    let priceV2 = await VM2.GetNumaPriceEth(ethers.parseEther("1000"));
    console.log(priceV2);

    let numaSupply2 = await VM2.getNumaSupply();
    console.log(numaSupply2);

    let balanceEth2 = await VM2.getTotalBalanceEth();
    console.log(balanceEth2);

    // // printer

    // // ***********************************  NUMA ORACLE ******************************
    // const oracle = await ethers.deployContract("NumaOracle", [USDC_ADDRESS, INTERVAL_SHORT, INTERVAL_LONG, signer.getAddress(), NUAM_ADDRESS]);
    // await oracle.waitForDeployment();
    // oracleAddress = await oracle.getAddress();
    // if (LOG)
    //     console.log(`numa oracle deployed to: ${oracleAddress}`);

    // // ***********************************  NUUSD & PRINTER ******************************
    // const NuUSD = await ethers.getContractFactory('nuAsset');
    // let defaultAdmin = await signer.getAddress();
    // let minter = await signer.getAddress();
    // let upgrader = await signer.getAddress();
    // nuUSD = await upgrades.deployProxy(
    //     NuUSD,
    //     ["nuUSD", "NUSD", defaultAdmin, minter, upgrader],
    //     {
    //         initializer: 'initialize',
    //         kind: 'uups'
    //     }
    // );
    // await nuUSD.waitForDeployment();
    // nuusd_address = await nuUSD.getAddress();

    // if (LOG)
    //     console.log(`nuUSD deployed to: ${nuusd_address}`);


    // // register nuAsset
    // await nuAM.addNuAsset(nuusd_address, configArbi.PRICEFEEDETHUSD, 86400);
    // //await nuAM.addNuAsset(NUBTC_ADDRESS,configArbi.PRICEFEEDBTCETH,86400);


    // let USDCtoETHConverter = await ethers.deployContract("USDCToEthConverter",
    //     ["0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3", 1000 * 86400, "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612", 1000 * 86400, UPTIME_FEED]);
    // await USDCtoETHConverter.waitForDeployment();
    // let USDCtoETHConverter_address = await USDCtoETHConverter.getAddress();
    // if (LOG)
    //     console.log(`usdc/ETH converter deployed to: ${USDCtoETHConverter_address}`);



    // moneyPrinter = await ethers.deployContract("NumaPrinter",
    //     [numa_address, MINTER_ADDRESS, NUMA_USDC_POOL_ADDRESS, USDCtoETHConverter_address, oracleAddress, VM_ADDRESS]);
    // await moneyPrinter.waitForDeployment();
    // moneyPrinter_address = await moneyPrinter.getAddress();
    // if (LOG)
    //     console.log(`printer deployed to: ${moneyPrinter_address}`);


    // // add moneyPrinter as a minter
    // theMinter.addToMinters(moneyPrinter_address);
    // // add vault as a minter
    // theMinter.addToMinters(VAULT1_ADDRESS);
    // // set printer as a NuUSD minter

    // await nuUSD.connect(signer).grantRole(roleMinter, moneyPrinter_address);// owner is NuUSD deployer



    // // IMPORTANT: for the uniswap V3 avg price calculations, we need this
    // // or else it will revert

    // // Get the pools to be as old as INTERVAL_LONG    
    // await time.increase(1800);
    // let cardinality = 10;
    // await poolContractNuma.increaseObservationCardinalityNext(cardinality);




    // let printFee = 500;
    // await moneyPrinter.setPrintAssetFeeBps(printFee);
    // //
    // let burnFee = 800;
    // await moneyPrinter.setBurnAssetFeeBps(burnFee);




    // // ***********************************  NUBTC & PRINTER ******************************
    // const NuBTC = await ethers.getContractFactory('nuAsset');





    // lending
    // *********************** Deploy lending **********************************
    // COMPTROLLER
    comptroller = await ethers.deployContract("NumaComptroller",
        []);
    await comptroller.waitForDeployment();
    COMPTROLLER_ADDRESS = await comptroller.getAddress();
    console.log('numa comptroller address: ', COMPTROLLER_ADDRESS);

    // PRICE ORACLE 
    numaPriceOracle = await ethers.deployContract("NumaPriceOracleNew",
        []);
    await numaPriceOracle.waitForDeployment();
    NUMA_PRICEORACLE_ADDRESS = await numaPriceOracle.getAddress();
    console.log('numa price oracle address: ', NUMA_PRICEORACLE_ADDRESS);

    await numaPriceOracle.setVault(VAULT1_ADDRESS);
    console.log('numaPriceOracle.setVault Done');
    await comptroller._setPriceOracle(await numaPriceOracle.getAddress());
    console.log('comptroller._setPriceOracle Done');

    // INTEREST RATE MODEL
    let maxUtilizationRatePerBlock = Math.floor(maxUtilizationRatePerYear / blocksPerYear);


    let _vertexUtilization = '800000000000000000';// 80%
    // no interest rate by default, tested specifically
    //let _vertexRatePercentOfDelta = '500000000000000000';// 50%
    let _vertexRatePercentOfDelta = '000000000000000000';// 50%
    let _minUtil = '400000000000000000';// 40%
    let _maxUtil = '600000000000000000';// 60%
    // no interest rate by default, tested specifically
    //let _zeroUtilizationRate = '20000000000000000';//2%
    let _zeroUtilizationRate = '00000000000000000';//2%
    let _minFullUtilizationRate = '1000000000000000000';//100%
    let _maxFullUtilizationRate = '5000000000000000000';//500%
    // 
    // Interest Rate Half-Life: The time it takes for the interest to halve when Utilization is 0%.
    // This is the speed at which the interest rate adjusts.
    // In the currently available Rate Calculator, the Interest Rate Half-Life is 12 hours.

    let _rateHalfLife = 12 * 3600;
    // perblock
    let _zeroUtilizationRatePerBlock = Math.floor(_zeroUtilizationRate / blocksPerYear);
    let _minFullUtilizationRatePerBlock = Math.floor(_minFullUtilizationRate / blocksPerYear);
    let _maxFullUtilizationRatePerBlock = Math.floor(_maxFullUtilizationRate / blocksPerYear);


    rateModel = await ethers.deployContract("JumpRateModelVariable",
        ["numaRateModel", _vertexUtilization, _vertexRatePercentOfDelta, _minUtil, _maxUtil,
            _zeroUtilizationRatePerBlock, _minFullUtilizationRatePerBlock, _maxFullUtilizationRatePerBlock,
            _rateHalfLife, await owner.getAddress()]);


    let baseRatePerYear = '20000000000000000';
    let multiplierPerYear = '180000000000000000';
    let jumpMultiplierPerYear = '4000000000000000000';
    let kink = '800000000000000000';
    rateModel = await ethers.deployContract("JumpRateModelV4",
        [blocksPerYear, baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink, await owner.getAddress(), "numaRateModel"]);


    await rateModel.waitForDeployment();
    JUMPRATEMODELV2_ADDRESS = await rateModel.getAddress();
    console.log('rate model address: ', JUMPRATEMODELV2_ADDRESS);


    // CTOKENS
    cReth = await ethers.deployContract("CNumaLst",
        [rETH_ADDRESS, comptroller, rateModel, '200000000000000000000000000',
            'rEth CToken', 'crEth', 8, maxUtilizationRatePerBlock, await owner.getAddress(), VAULT1_ADDRESS]);
    await cReth.waitForDeployment();
    CRETH_ADDRESS = await cReth.getAddress();
    console.log('crEth address: ', CRETH_ADDRESS);

    cNuma = await ethers.deployContract("CNumaToken",
        [numa_address, comptroller, rateModel, '200000000000000000000000000',
            'numa CToken', 'cNuma', 8, maxUtilizationRatePerBlock, await owner.getAddress(), VAULT1_ADDRESS]);
    await cNuma.waitForDeployment();
    CNUMA_ADDRESS = await cNuma.getAddress();
    console.log('cNuma address: ', CNUMA_ADDRESS);


    await Vault1.setCTokens(CNUMA_ADDRESS, CRETH_ADDRESS);
    await Vault1.setMinLiquidationsPc(250);//25% min
    // add markets (has to be done before _setcollateralFactor)
    await comptroller._supportMarket(await cNuma.getAddress());
    await comptroller._supportMarket(await cReth.getAddress());

    console.log("setting collateral factor");

    // 80% for numa as collateral
    await comptroller._setCollateralFactor(await cNuma.getAddress(), ethers.parseEther(numaCollateralFactor.toString()).toString());
    // 60% for rEth as collateral
    await comptroller._setCollateralFactor(await cReth.getAddress(), ethers.parseEther(rEthCollateralFactor.toString()).toString());

    // 50% liquidation close factor
    console.log("set close factor");
    await comptroller._setCloseFactor(ethers.parseEther("0.5").toString());


    // divers: cf liste & debut de fcts dans les tests




    // ******************************************** ref code *******************************

    //     // *********************** nuAssetManager **********************************
    //     let nuAM = await ethers.deployContract("nuAssetManager",
    //    ["0x0000000000000000000000000000000000000000"]// no sequencer up feed on sepolia
    //    );
    //     await nuAM.waitForDeployment();
    //     let NUAM_ADDRESS = await nuAM.getAddress();
    //     console.log('nuAssetManager address: ', NUAM_ADDRESS);


    //     console.log('initial synth value: ', await nuAM.getTotalSynthValueEth());


    //    // *********************** vaultManager **********************************
    //    let VM = await ethers.deployContract("VaultManager",
    //    [numa_address,NUAM_ADDRESS]);

    //    await VM.waitForDeployment();
    //    let VM_ADDRESS = await VM.getAddress();
    //    console.log('vault manager address: ', VM_ADDRESS);




    //    // using custom MockOracle as we don't have rEth chainlink feeds on sepolia
    //     let VMO = await ethers.deployContract("VaultMockOracle",[]);
    //     await VMO.waitForDeployment();
    //     let VMO_ADDRESS= await VMO.getAddress();



    //     // 

    //    // vault1 rETH
    //    let Vault1 = await ethers.deployContract("NumaVault",
    //    [numa_address,LST_ADDRESS,ethers.parseEther("1"),VMO_ADDRESS]);


    //    await Vault1.waitForDeployment();
    //    let VAULT1_ADDRESS = await Vault1.getAddress();
    //    console.log('vault rETH address: ', VAULT1_ADDRESS);


    //    console.log('add vault to vault manager');
    //    await VM.addVault(VAULT1_ADDRESS);
    //    console.log('set vault manager to reth vault');
    //    await Vault1.setVaultManager(VM_ADDRESS);

    //    // fee address
    //    FEE_ADDRESS = VM_ADDRESS;
    //    RWD_ADDRESS = VM_ADDRESS;
    //    await Vault1.setFeeAddress(FEE_ADDRESS,false);
    //    await Vault1.setRwdAddress(RWD_ADDRESS,false);

    //    // allow vault to mint numa
    //    let numa = await hre.ethers.getContractAt("NUMA", numa_address);
    //    await numa.grantRole(roleMinter, VAULT1_ADDRESS);

    //    await VM.setDecayValues( ethers.parseEther(decayAmount),decayPeriod,0,0,ethers.parseEther(constantRemoved));

    //    // BUY FEE 25%
    //    await Vault1.setBuyFee(750);

    //    // TODO transfer rETH to vault to initialize price
    //    let lstToken = await hre.ethers.getContractAt("LstTokenMock", LST_ADDRESS);
    //    await lstToken.transfer(VAULT1_ADDRESS, ethers.parseEther("2000"));

    //    // TODO: deploy front end

    //    // TODO START
    //    await VM.startDecay();

    //    // TODO UNPAUSE
    //    await Vault1.unpause();


    // TODO: front end official deploy

    // Transfer ownership

    // TODO grant ownership to owner
    // await Vault1.transferOwnership(newOwner_ADDRESS);
    // await nuAM.transferOwnership(newOwner_ADDRESS);
    // await VO.transferOwnership(newOwner_ADDRESS);
    // await VM.transferOwnership(newOwner_ADDRESS);

    // TODO: connect with new owner: from etherscan
    // await Vault1.acceptOwnership();
    // await nuAM.acceptOwnership();
    // await VO.acceptOwnership();
    // await VM.acceptOwnership();


    // new vault?

    // - deploy new vault
    // - get all rEth from vault1
    // - pause it
    // - send reth to new vault
    // - remove v1 from vault manager
    // - add v2 to vauylt manager
    // - set vault manager to v2
    // - grant role
    // - set fee/rwd address
    // - set decay values, startdecay, unpause







}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })