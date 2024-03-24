//

import { ethers,network } from 'hardhat';

import { CTokenDeployArg, deployNumaCompoundV2 } from './';

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

async function main() {
  const [deployer, userA,userB] = await ethers.getSigners();

  // deploy tokens
  // numa
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
  console.log('ERC20 deployed to:', await contract.getAddress());

  await contract.mint(
      deployer.getAddress(),
      ethers.parseEther("10000000.0")
    );


  // const uni = await deployErc20Token(
  //   {
  //     name: 'Uniswap',
  //     symbol: 'UNI',
  //     decimals: 18,
  //   },
  //   deployer
  // );


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
      underlyingPrice: '35721743800000000000000',// TODO
      collateralFactor: '600000000000000000',// TODO
    },
  ];

  const { comptroller, cTokens, priceOracle, interestRateModels } = await deployNumaCompoundV2(cTokenDeployArgs, deployer, { gasLimit: 8_000_000 });
  const { cNuma, crEth } = cTokens;
  // userA will deposit numa and borrow rEth
  console.log("numa ctoken");
  console.log(await cNuma.getAddress());
  console.log("reth ctoken");
  console.log(await crEth.getAddress());
  await comptroller.connect(userA).enterMarkets([cNuma.getAddress()]);


  // deposit numa
  // We need to supply some eth for collateral.
  //await cNuma.mint("1000000000000000000");
  // approve 
  // not working
  let numa = await ethers.getContractAt(ERC20abi, numaAddress);
  let reth = await ethers.getContractAt(ERC20abi, rethAddress);
 // console.log(await numa.totalSupply());


  // transfer numa to userA
  let numawhale = "0xe8153Afbe4739D4477C1fF86a26Ab9085C4eDC69";
  await network.provider.request({
    method: "hardhat_impersonateAccount",
    params: [numawhale],
  });
  
  // get associated signer
  const signer = await ethers.getSigner(numawhale);

  console.log(await signer.getAddress());
  console.log(await numa.balanceOf(signer.getAddress()));
 // not needed as I already transfered
 // await numa.connect(signer).transfer(userA.getAddress(),ethers.parseEther("1000"));
  console.log(await numa.balanceOf(userA.getAddress()));
  // approve
  await numa.connect(userA).approve(await cNuma.getAddress(),ethers.parseEther("100"));
  await cNuma.connect(userA).mint(ethers.parseEther("100"));

 console.log(await cNuma.balanceOf(userA.getAddress()));
 

 // userB mints crEth
 console.log(await reth.balanceOf(signer.getAddress()));
 // not needed as I already transfered
  await reth.connect(signer).transfer(userB.getAddress(),ethers.parseEther("100"));
  console.log(await reth.balanceOf(userB.getAddress()));
  // approve
  await reth.connect(userB).approve(await crEth.getAddress(),ethers.parseEther("10"));
  await crEth.connect(userB).mint(ethers.parseEther("10"));

 console.log(await crEth.balanceOf(userB.getAddress()));



  // const { cTokens } = await deployNumaCompoundV2(cTokenDeployArgs, deployer, { gasLimit: 8_000_000 });
  // const { cETH: cEth, cUNI: cUni } = cTokens;

  // const uniAmount = parseUnits('100', 18).toString();
  // await uni.mint(userA.address, uniAmount);
  // await uni.connect(userA).approve(cUni.address, uniAmount);
  // await cUni.connect(userA).mint(parseUnits('25', 18).toString());
  // await cEth.connect(userA).mint({
  //   value: parseUnits('2', 18).toString(),
  // });
}

main().catch(console.error);
