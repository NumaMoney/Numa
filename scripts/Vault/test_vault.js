const helpers = require("@nomicfoundation/hardhat-toolbox/network-helpers");

// 1. Numa
// 2. nuAssets: nuUSD, NUBTC
// 3. nuAssetManager
// 4. VaultManager
// rETH oracle
// 5. Deploy Vault 1, deploy rETH oracle
// 6. mint nuAssets

// 7. test buy/sell, check prices, check fees


// multi vault & 2nd vault


// 8. mockoracle, change price, test again
// 9. test rwd extraction



// on arbitrum fork to get chainlink

let ETHUSD_FEED = "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612";
let BTCETH_FEED = "0xc5a90A6d7e4Af242dA238FFe279e9f2BA0c64B2e";
let rETH_ADDRESS = "0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8";
let wstETH_ADDRESS = "0x5979d7b546e38e414f7e9822514be443a4800529";
let RETH_FEED = "0xD6aB2298946840262FcC278fF31516D39fF611eF";
let wstETH_FEED = "0xb523AE262D20A936BC152e6023996e46FDC2A95D";

  
const ERC20abi = [
    // Read-Only Functions
    "function balanceOf(address owner) view returns (uint256)",
    "function decimals() view returns (uint8)",
    "function symbol() view returns (string)",
  
    // Authenticated Functions
    "function transfer(address to, uint amount) returns (bool)",
    "function approve(address spender, uint amount)",
  
    // Events
    "event Transfer(address indexed from, address indexed to, uint amount)"
];


const { ethers, upgrades } = require("hardhat");

// npx hardhat run --network kovan scripts/deploy_erc20.js
async function main () {
   
    // *********************** NUMA TOKEN **********************************
    const [owner,signer2,signer3,signer4] = await ethers.getSigners();

    const Numa = await ethers.getContractFactory('NUMA')
    const contract = await upgrades.deployProxy(
      Numa,
        [],
        {
            initializer: 'initialize',
            kind:'uups'
        }
    )
    await contract.waitForDeployment();
    let NUMA_ADDRESS = await contract.getAddress();
    console.log('Numa deployed to:', NUMA_ADDRESS);

    // await contract.mint(
    //     owner.getAddress(),
    //     ethers.parseEther("10000000.0")
    //   );


    





    // *********************** NUUSD TOKEN **********************************
    const NuUSD = await ethers.getContractFactory('nuAsset');
    let defaultAdmin = await owner.getAddress();
    let minter = await owner.getAddress();
    let upgrader = await owner.getAddress();
    const nuUSD = await upgrades.deployProxy(
      NuUSD,
      ["NuUSD", "NUSD",defaultAdmin,minter,upgrader],
      {
        initializer: 'initialize',
        kind:'uups'
      }
    );
    await nuUSD.waitForDeployment();
    let NUUSD_ADDRESS = await nuUSD.getAddress();
    console.log('nuUSD address: ', NUUSD_ADDRESS);


    // *********************** NUBTC TOKEN **********************************
    const NuBTC = await ethers.getContractFactory('nuAsset');
    
    const nuBTC = await upgrades.deployProxy(
      NuBTC,
      ["NuBTC", "NBTC",defaultAdmin,minter,upgrader],
      {
        initializer: 'initialize',
        kind:'uups'
      }
    );
    await nuBTC.waitForDeployment();
    let NUBTC_ADDRESS = await nuBTC.getAddress();
    console.log('nuBTC address: ', NUBTC_ADDRESS);


    // *********************** nuAssetManager **********************************
    let nuAM = await ethers.deployContract("nuAssetManager",
    []
    );
    await nuAM.waitForDeployment();
    let NUAM_ADDRESS = await nuAM.getAddress();
    console.log('nuAssetManager address: ', NUAM_ADDRESS);

    // register nuAsset
    await nuAM.addNuAsset(NUUSD_ADDRESS,ETHUSD_FEED);
    await nuAM.addNuAsset(NUBTC_ADDRESS,BTCETH_FEED);

    console.log('initial synth value: ', await nuAM.getTotalSynthValueEth());




    // TODO: test removing nuAsset

    // *********************** vaultManager **********************************
    let VM = await ethers.deployContract("VaultManager",
    []);
    await VM.waitForDeployment();
    let VM_ADDRESS = await VM.getAddress();
    console.log('vault manager address: ', VM_ADDRESS);


    let VO = await ethers.deployContract("VaultOracle",
    []);
    await VO.waitForDeployment();
    let VO_ADDRESS= await VO.getAddress();
    console.log('vault oracle address: ', VO_ADDRESS);

    // adding rETH to our oracle
    await VO.setTokenFeed(rETH_ADDRESS,RETH_FEED);

    // vault1 rETH
    let Vault1 = await ethers.deployContract("NumaVault",
    [NUMA_ADDRESS,rETH_ADDRESS,ethers.parseEther("1"), VO_ADDRESS,NUAM_ADDRESS,267]);
    await Vault1.waitForDeployment();
    let VAULT1_ADDRESS = await Vault1.getAddress();
    console.log('vault rETH address: ', VAULT1_ADDRESS);

    await VM.addVault(VAULT1_ADDRESS);
    await Vault1.setVaultManager(VM_ADDRESS);

    // TEST 1, no rETH in VAULT1 --> get price, and buy/sell
    
    // Prices --> REVERT because no numa minted, no rETh in vault
    // let buyprice = await Vault1.getBuyNuma(ethers.parseEther("2"));
    // console.log('how many numa for 2 Eth: ',buyprice);
    // let sellprice = await Vault1.getSellNuma(ethers.parseEther("1000"));
    // console.log('how many rEth for 1000 Numas: ',sellprice);




    // TEST 2: adding rETH in the vault
    const address = "0x8Eb270e296023E9D92081fdF967dDd7878724424";
    await helpers.impersonateAccount(address);
    const impersonatedSigner = await ethers.getSigner(address);

    // transfer eth to this address
    // const tx = await owner.sendTransaction({
    //   to: address,
    //   value: ethers.parseEther("1"),
    // });
    // console.log(tx);
    await helpers.setBalance(address,ethers.parseEther("10"));


    const erc20_rw  = await hre.ethers.getContractAt(ERC20abi, rETH_ADDRESS);

    let bal0 = await erc20_rw.balanceOf(address);
    // transfer to signer so that it can buy numa
    await erc20_rw.connect(impersonatedSigner).transfer(defaultAdmin,ethers.parseEther("5"));
    // transfer to vault to initialize price
    await erc20_rw.connect(impersonatedSigner).transfer(VAULT1_ADDRESS,ethers.parseEther("100"));

    let bal1 = await erc20_rw.balanceOf(VAULT1_ADDRESS);

    console.log("rETH balance of the vault ",bal1);

    // should still revert because no numa supply
    // let buyprice = await Vault1.getBuyNuma(ethers.parseEther("2"));
    // console.log('how many numa for 2 Eth: ',buyprice);
    // let sellprice = await Vault1.getSellNuma(ethers.parseEther("1000"));
    // console.log('how many rEth for 1000 Numas: ',sellprice);
    // Numa mint
    await contract.mint(
        owner.getAddress(),
        ethers.parseEther("10000000.0")
      );
    let buyprice = await Vault1.getBuyNuma(ethers.parseEther("2"));
    console.log('how many numa for 2 rEth: ',buyprice);

    let sellprice = await Vault1.getSellNuma(ethers.parseEther("1000"));
    console.log('how many rEth for 1000 Numas: ',sellprice);

    // buy and sell should revert because still paused
    //await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());
    //await Vault1.sell(ethers.parseEther("1000"),await signer2.getAddress());



    // fee address
    await Vault1.setFeeAddress(await signer3.getAddress(),false);

    // unpause
    await Vault1.unpause();

    // Buy Numa
    // approve vault to spend our rETH
    await erc20_rw.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("10"));

    // make vault Numa minter
    const roleMinter = ethers.keccak256(ethers.toUtf8Bytes("MINTER_ROLE"));
    await contract.grantRole(roleMinter, VAULT1_ADDRESS);
   

    await Vault1.buy(ethers.parseEther("2"),await signer2.getAddress());
    let balbuyer = await contract.balanceOf(await signer2.getAddress());
    bal1 = await erc20_rw.balanceOf(VAULT1_ADDRESS);
    let balfee = await erc20_rw.balanceOf(await signer3.getAddress());
    bal0 = await erc20_rw.balanceOf(defaultAdmin);
    console.log("Numa balance of receiver ",balbuyer);
    console.log("rETH balance of the vault ",bal1);
    console.log("rETH balance of fee address ",balfee);
    console.log("rETH balance of buyer ",bal0);
    


    // Sell Numa
    // approve vault to burn our Numas
    await contract.connect(owner).approve(VAULT1_ADDRESS,ethers.parseEther("10000"));
    sellprice = await Vault1.getSellNuma(ethers.parseEther("1000"));
    console.log('how many rEth for 1000 Numas: ',sellprice);
    await Vault1.sell(ethers.parseEther("1000"),await signer2.getAddress());

    balbuyer = await contract.balanceOf(defaultAdmin);
    bal1 = await erc20_rw.balanceOf(VAULT1_ADDRESS);
    balfee = await erc20_rw.balanceOf(await signer3.getAddress());
    let balreceiver = await erc20_rw.balanceOf(await signer2.getAddress());

    console.log("Numa balance of seller ",balbuyer);
    console.log("rETH balance of the vault ",bal1);
    console.log("rETH balance of fee address ",balfee);
    console.log("rETH balance of receiver ",balreceiver);


    // *********************** mint some nuUSD and nuBTC **********************************

    // 100000 nuUSD
    await nuUSD.connect(owner).mint(defaultAdmin,ethers.parseEther("10000"));
    // 10 BTC
    await nuBTC.connect(owner).mint(defaultAdmin,ethers.parseEther("1"));

    console.log('synth value after minting nuAssets: ', await nuAM.getTotalSynthValueEth());

    // sell again
    sellprice = await Vault1.getSellNuma(ethers.parseEther("1000"));
    console.log('how many rEth for 1000 Numas: ',sellprice);
    await Vault1.sell(ethers.parseEther("1000"),await signer2.getAddress());

    balbuyer = await contract.balanceOf(defaultAdmin);
    bal1 = await erc20_rw.balanceOf(VAULT1_ADDRESS);
    balfee = await erc20_rw.balanceOf(await signer3.getAddress());
    balreceiver = await erc20_rw.balanceOf(await signer2.getAddress());

    console.log("Numa balance of seller ",balbuyer);
    console.log("rETH balance of the vault ",bal1);
    console.log("rETH balance of fee address ",balfee);
    console.log("rETH balance of receiver ",balreceiver);



    // Deploy vault 2
    // first add wstETH to oracle
    await VO.setTokenFeed(wstETH_ADDRESS,wstETH_FEED);

    // deploy
    let Vault2 = await ethers.deployContract("NumaVault",
    [NUMA_ADDRESS,wstETH_ADDRESS,ethers.parseEther("1"),VO_ADDRESS,NUAM_ADDRESS,267]);
    await Vault2.waitForDeployment();
    let VAULT2_ADDRESS = await Vault2.getAddress();
    console.log('vault wstETH address: ', VAULT2_ADDRESS);

    await VM.addVault(VAULT2_ADDRESS);
    await Vault2.setVaultManager(VM_ADDRESS);

    // TEST 1, no rETH in VAULT1 --> get price, and buy/sell
    
    // Prices --> REVERT because no numa minted, no rETh in vault
    // let buyprice = await Vault1.getBuyNuma(ethers.parseEther("2"));
    // console.log('how many numa for 2 Eth: ',buyprice);
    // let sellprice = await Vault1.getSellNuma(ethers.parseEther("1000"));
    // console.log('how many rEth for 1000 Numas: ',sellprice);




    // TEST 2: adding wstETH in the vault
    let address2 = "0x513c7e3a9c69ca3e22550ef58ac1c0088e918fff";
    await helpers.impersonateAccount(address2);
    const impersonatedSigner2 = await ethers.getSigner(address2);
    await helpers.setBalance(address2,ethers.parseEther("10"));


    const erc20_rw2  = await hre.ethers.getContractAt(ERC20abi, wstETH_ADDRESS);


    // price before feeding vault2
    buyprice = await Vault1.getBuyNuma(ethers.parseEther("2"));
    console.log('how many numa for 2 rEth: ',buyprice);
    buyprice = await Vault2.getBuyNuma(ethers.parseEther("2"));
    console.log('how many numa for 2 wstEth: ',buyprice);


    bal0 = await erc20_rw2.balanceOf(address);
    // transfer to signer so that it can buy numa
    await erc20_rw2.connect(impersonatedSigner2).transfer(defaultAdmin,ethers.parseEther("5"));
    // transfer to vault to initialize price
    await erc20_rw2.connect(impersonatedSigner2).transfer(VAULT2_ADDRESS,ethers.parseEther("100"));


    bal1 = await erc20_rw2.balanceOf(VAULT2_ADDRESS);
    console.log("wstETH balance of the vault ",bal1);

    // price after feeding vault2
    buyprice = await Vault1.getBuyNuma(ethers.parseEther("2"));
    console.log('how many numa for 2 rEth: ',buyprice);
    buyprice = await Vault2.getBuyNuma(ethers.parseEther("2"));
    console.log('how many numa for 2 wstEth: ',buyprice);



    // make vault Numa minter
    await contract.grantRole(roleMinter, VAULT2_ADDRESS);

    // TODO: sell/buy
       


    // ********************** rwd extraction *******************
    let VMO = await ethers.deployContract("VaultMockOracle",
    []);
    await VMO.waitForDeployment();
    let VMO_ADDRESS= await VMO.getAddress();
    console.log('vault mock oracle address: ', VMO_ADDRESS);

    
    let lastprice = await Vault1.last_lsttokenvalue();
    console.log(lastprice);


}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })