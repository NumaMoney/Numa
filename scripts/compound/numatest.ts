//

import { ethers,network } from 'hardhat';
import { CTokenDeployArg, deployNumaCompoundV2 } from './';
import "colors";
import { assert } from "chai";
const ERC20abi = [
  "function balanceOf(address owner) view returns (uint256)",
  "function decimals() view returns (uint8)",
  "function symbol() view returns (string)",
  "function transfer(address to, uint amount) returns (bool)",
  "function approve(address spender, uint amount)",
  "function totalSupply() view returns (uint256)",
  "event Transfer(address indexed from, address indexed to, uint amount)"
];

const numaAddress = "0x2e4a312577A78786051052c28D5f1132d93c557A";
const rethAddress = "0x1521c67fDFDb670fa21407ebDbBda5F41591646c";
const vaultAddress = "0x1c027eb3A6216A0cD6428F8577D231A0EfCA3F50";

async function printAccountLiquidity(
  accountAddress: string,
  comptroller: Comptroller
) {
  const [_, collateral, shortfall] = await comptroller.getAccountLiquidity(
    accountAddress
  );


  if (shortfall === 0n) {
    console.log(
      "Healthy".green,
      "collateral=",
      collateral.toString().green,
      "shortfall=",
      shortfall.toString().green
    );
  } else {
    console.log(
      "Underwalter !!!".red,
      "collateral=",
      collateral.toString().red,
      "shortfall=",
      shortfall.toString().red
    );
  }
}


async function main() {
  const [deployer, userA,userB] = await ethers.getSigners();

  let numa = await ethers.getContractAt(ERC20abi, numaAddress);
  let reth = await ethers.getContractAt(ERC20abi, rethAddress);
  let rethVault = await ethers.getContractAt("NumaVault", vaultAddress);

  const cTokenDeployArgs: CTokenDeployArg[] = [
    {
      cToken: 'cNuma',
      underlying: numaAddress,
      underlyingPrice:'500000000000000000',// TODO 
      collateralFactor: '800000000000000000',// TODO
    },
    {
      cToken: 'clstETH',
      underlying: rethAddress,
      underlyingPrice: '3000000000000000000000',// TODO
      collateralFactor: '600000000000000000',// TODO
    },
  ];

  const { comptroller, priceOracle, interestRateModels,cTokens } = await deployNumaCompoundV2(cTokenDeployArgs, deployer, { gasLimit: 8_000_000 });



  
  const { cNuma, clstETH } = cTokens;
  console.log("set vault oracle");
  await priceOracle.setVault(vaultAddress);

  console.log("setting collateral factor");
  await comptroller._setCollateralFactor(await cNuma.getAddress(), '800000000000000000');
  await comptroller._setCollateralFactor(await clstETH.getAddress(), '600000000000000000');
  

  console.log("set close factor");
  await comptroller._setCloseFactor(ethers.parseEther("0.5").toString());


  
// FOR DEBUG REMOVE IR
let IM_address = await cNuma.interestRateModel();
let IMV2 = await ethers.getContractAt("BaseJumpRateModelV2", IM_address);
// await IMV2.updateJumpRateModel(ethers.parseEther('0.02'),ethers.parseEther('0.18')
// ,ethers.parseEther('4'),ethers.parseEther('0.8'));

console.log("cancelling interest rates");
await IMV2.updateJumpRateModel(ethers.parseEther('0'),ethers.parseEther('0')
,ethers.parseEther('0'),ethers.parseEther('1'));


  // userA will deposit numa and borrow rEth
  await comptroller.connect(userA).enterMarkets([cNuma.getAddress()]);





  // transfer numa to userA
  let numawhale = "0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69";
  await network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [numawhale],
  });
  
  // get associated signer
  const signer = await ethers.getSigner(numawhale);

  // console.log(await signer.getAddress());
  // console.log(await numa.balanceOf(signer.getAddress()));
 // not needed as I already transfered
 let balNuma = await numa.balanceOf(userA.getAddress());

 let numaDepositAmount = ethers.parseEther("100000");
 if (balNuma < numaDepositAmount)
 {
   console.log("transferring numas");
   await numa.connect(signer).transfer(userA.getAddress(),numaDepositAmount);
 }

 // approve
 await numa.connect(userA).approve(await cNuma.getAddress(),numaDepositAmount);
 // deposit (mint cnuma)
 console.log("deposit numa");
 console.log(ethers.formatEther(numaDepositAmount));
 await cNuma.connect(userA).mint(numaDepositAmount);

 console.log(await cNuma.balanceOf(userA.getAddress()));
 

 // userB mints crEth
 //console.log(await reth.balanceOf(signer.getAddress()));
 // not needed as I already transfered
 let balREth = await reth.balanceOf(userB.getAddress());
 if (balREth === 0n)
 {
  console.log("transferring rEth");
  await reth.connect(signer).transfer(userB.getAddress(),ethers.parseEther("100"));
 }

  // approve
  let rethdepositamount = ethers.parseEther("10");
  await reth.connect(userB).approve(await clstETH.getAddress(),rethdepositamount);

  console.log("deposit rEth");
  console.log(ethers.formatEther(rethdepositamount));
  await clstETH.connect(userB).mint(rethdepositamount);

  console.log(await clstETH.balanceOf(userB.getAddress()));



 // stats
 console.log("************************* STATS BEFORE BORROW **********************************");
 console.log("************************* CNUMA **********************************");
 // exchangeRateCurrent
 let numa_borrowRatePerBlock = await cNuma.borrowRatePerBlock();
 let numa_supplyRatePerBlock = await cNuma.supplyRatePerBlock();
 let numa_borrowIndex = await cNuma.borrowIndex();
 let numa_totalBorrows = await cNuma.totalBorrows();
 let numa_totalReserves = await cNuma.totalReserves();
 let numa_totalSupply = await cNuma.totalSupply();
 let numa_exchangeRateCurrent = await cNuma.exchangeRateStored();

 // total borrow
 console.log("numa_totalBorrows");
 console.log(ethers.formatEther(numa_totalBorrows));

 // collateral factor
 console.log("collateral factor");
 let res = await comptroller.markets(await cNuma.getAddress());
 console.log(res[1]);

 //
 console.log("utilization");

 //console.log(IM_address);
 let IM = await ethers.getContractAt("JumpRateModel", IM_address);;
 let getCashPrior = await numa.balanceOf(await cNuma.getAddress());//cNuma.getCashPrior();
 let totalBorrows = await cNuma.totalBorrows();
 let totalReserves = await cNuma.totalReserves();
 


 let utilizationRate = await IM.utilizationRate(getCashPrior,totalBorrows,totalReserves);
 console.log(utilizationRate);

//  console.log("numa_borrowRatePerBlock");
//  console.log(numa_borrowRatePerBlock);

//  console.log("numa_supplyRatePerBlock");
//  console.log(numa_supplyRatePerBlock);

//  console.log("numa_borrowIndex");
//  console.log(numa_borrowIndex);



//  console.log("numa_totalReserves");
//  console.log(numa_totalReserves);

//  console.log("numa_totalSupply");
//  console.log(numa_totalSupply);

//  console.log("numa_exchangeRateCurrent");
//  console.log(numa_exchangeRateCurrent);

 // RETH
 let reth_borrowRatePerBlock = await clstETH.borrowRatePerBlock();
 let reth_supplyRatePerBlock = await clstETH.supplyRatePerBlock();
 let reth_borrowIndex = await clstETH.borrowIndex();
 let reth_totalBorrows = await clstETH.totalBorrows();
 let reth_totalReserves = await clstETH.totalReserves();
 let reth_totalSupply = await clstETH.totalSupply();
 let reth_exchangeRateCurrent = await clstETH.exchangeRateStored();
//  console.log("reth_borrowRatePerBlock");
//  console.log(reth_borrowRatePerBlock);

//  console.log("reth_supplyRatePerBlock");
//  console.log(reth_supplyRatePerBlock);

//  console.log("reth_borrowIndex");
//  console.log(reth_borrowIndex);

//  console.log("reth_totalBorrows");
//  console.log(reth_totalBorrows);

//  console.log("reth_totalReserves");
//  console.log(reth_totalReserves);

//  console.log("reth_totalSupply");
//  console.log(reth_totalSupply);

//  console.log("reth_exchangeRateCurrent");
//  console.log(reth_exchangeRateCurrent);



 // borrow numa
 console.log("**************** Borrow numa *****************************");

 let bal = await numa.balanceOf(userB.getAddress());
 console.log('balance bef '+ ethers.formatEther(bal));

 // need to enter market to be able to borrow?
 await comptroller.connect(userB).enterMarkets([clstETH.getAddress()]);
 await cNuma.connect(userB).borrow(ethers.parseEther("1"));
 bal = await numa.balanceOf(userB.getAddress());
 console.log('balance aft '+ ethers.formatEther(bal));
 printAccountLiquidity(await userB.getAddress(),comptroller);

 console.log("**************** Borrow reth *****************************");

 let bal2 = await reth.balanceOf(userA.getAddress());
 console.log('balance bef '+ ethers.formatEther(bal2));

 // need to enter market to be able to borrow?
 await comptroller.connect(userA).enterMarkets([cNuma.getAddress()]);
 await clstETH.connect(userA).borrow(ethers.parseEther("1"));
 bal2 = await reth.balanceOf(userA.getAddress());
 console.log('balance aft '+ ethers.formatEther(bal2));
 printAccountLiquidity(await userA.getAddress(),comptroller);




 // borrow reth
//  await comptroller.connect(userA).enterMarkets([cNuma.getAddress()]);
//  bal = await reth.balanceOf(userA.getAddress());
//  console.log('balance before '+ bal);
//  await clstETH.connect(userA).borrow(ethers.parseEther("1"));
//  bal = await reth.balanceOf(userA.getAddress());
//  console.log('balance after '+ bal);


//  console.log("************************* STATS AFER BORROW **********************************");
//  console.log("************************* CNUMA **********************************");
//  // total borrow
//  numa_totalBorrows = await cNuma.totalBorrows();
//  console.log("numa_totalBorrows");
//  console.log(ethers.formatEther(numa_totalBorrows));

//  // collateral factor
//  console.log("collateral factor");
//  res = await comptroller.markets(await cNuma.getAddress());
//  console.log(ethers.formatEther(res[1]));

//  //
//  console.log("utilization");
//  getCashPrior = await numa.balanceOf(await cNuma.getAddress());//cNuma.getCashPrior();

//  totalReserves = await cNuma.totalReserves();
 


//  utilizationRate = await IM.utilizationRate(getCashPrior,numa_totalBorrows,totalReserves);
//  console.log(utilizationRate);







//  // LIQUIDATE
//  // liquidateBorrow

//  // liquidate numa borrower
//  // is he liquiditable?
//  // rEth supplied as collateral
//  // 

//  reth_exchangeRateCurrent = await clstETH.exchangeRateStored();
//  console.log("reth exchange rate");
//  console.log(reth_exchangeRateCurrent);


//  console.log("reth supplied");
//  console.log(ethers.formatEther(reth_totalSupply));

//  console.log("numa borrowed");
//  console.log(ethers.formatEther(numa_totalBorrows));


// //  cToken: 'cNuma',
// //  underlying: numaAddress,
// //  underlyingPrice:'500000000000000000',
// //  collateralFactor: '800000000000000000',

// //  cToken: 'clstETH',
// //  underlying: rethAddress,
// //  underlyingPrice: '3000000000000000000000',
// //  collateralFactor: '600000000000000000',

// // exchange rate 200000000000000000000000000n
// // 200000000

// // rEth supplied = 0.00000005
// // 0.00000005 x 3000000000000000000000 = 0.00000005 x 3000 = 0.00015
// // x exchangerate = 200000000 x 0.00015 = 30000
// // x collateralFactor = 600000000000000000 = 0.6 = 18000
 
// // numa borrowed = X
// // X x 0.5 = 0.5 X



//  let resliq = await comptroller.getAccountLiquidity(await userB.getAddress());
//  console.log("userB (numa borrower) liquidity:")
//  console.log(resliq);

//  // we have 18000 collat for a borrow of 36000 x 0.5
//  // change some price to be liquiditable
// //  let fakeOracle = await ethers.getContractAt("NumaPriceOracle", priceOracle);;
// //  await fakeOracle.setUnderlyingPrice(await cNuma.getAddress(),ethers.parseEther("1"));

//  resliq = await comptroller.getAccountLiquidity(await userB.getAddress());
//  console.log("userB (numa borrower) liquidity after changing numa price:")
//  printAccountLiquidity(await userB.getAddress(),comptroller);


//  // liquidate numa borrower and check received incentives and check balances

//  // how much collateral have been seized?
// let collatBefore = await clstETH.balanceOf(await userB.getAddress());
// console.log("collateral before");
// console.log(collatBefore);

// let receivedBefore = await clstETH.balanceOf(await deployer.getAddress());
// console.log("received before");
// console.log(receivedBefore);

// INCENTIVE
// await comptroller._setLiquidationIncentive(ethers.parseEther("1.08"));

//  let repayAmount = ethers.parseEther("18000");
//  await numa.connect(signer).transfer(deployer.getAddress(),repayAmount);
//  await numa.approve(await cNuma.getAddress(),repayAmount);
//  await cNuma.liquidateBorrow(await userB.getAddress(), repayAmount,clstETH) ;


//  // TODOQ: quelle unité le montant dans liquidateborrow 
//  // NUMA 


//  // TODOQ: pourquoi il reste de la dette si je ne prend pas de collat (pas d'incentive)?
//  // INTERETS (cf multiplier & utilization)

//  // TODOQ: quelles incentives
//  // TODOQ: pourquoi collat + received < collat before ou sont passés les autres clstEth?
//  // workflow: on rembourse une partie de l'emprunt, on récupere l'équivalent en collateral - 2.8% qui vont au protocol (restent dans le lending contract)
//  // si 1.08 --> 8%, le liquidator fait un benef de 5.2% et reverse 2.8% au protocol
//  // + tester avec un autre incentive pour verif les calculs



// resliq = await comptroller.getAccountLiquidity(await userB.getAddress());
// console.log("userB (numa borrower) liquidity after liquidation:")
// // console.log(resliq);
// printAccountLiquidity(await userB.getAddress(),comptroller);

// // how much collateral have been seized?
// let collatAfter = await clstETH.balanceOf(await userB.getAddress());
// console.log("collateral after");
// console.log(collatAfter);

// let received = await clstETH.balanceOf(await deployer.getAddress());
// console.log("received after");
// console.log(received);



}

main().catch(console.error);
