import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { Overrides } from 'ethers';

import {
  BaseJumpRateModelV2,
  CErc20Delegate,
  CErc20Delegate__factory,
  CErc20Delegator,
  CErc20Delegator__factory,
  CErc20Immutable,
  CErc20Immutable__factory,
  CEther,
  CEther__factory,
  Comptroller,
  Comptroller__factory,
  NumaComptroller,
  JumpRateModelV2__factory,
  LegacyJumpRateModelV2__factory,
  NumaComptroller__factory,
  SimplePriceOracle,
  SimplePriceOracle__factory,
  NumaPriceOracle,
  NumaPriceOracle__factory,
  WhitePaperInterestRateModel,
  WhitePaperInterestRateModel__factory,
} from '../../typechain-types';

import { CTOKEN, INTEREST_RATE_MODEL } from './configs';
import { CTokenType, InterestRateModelType } from './enums';
import {
  CErc20Args,
  CErc20DelegatorArgs,
  CEthArgs,
  CompoundV2,
  CTokenArgs,
  CTokenDeployArg,
  CTokenLike,
  CTokens,
  InterestRateModelConfig,
  InterestRateModels,
  JumpRateModelV2Args,
  LegacyJumpRateModelV2Args,
  WhitePaperInterestRateModelArgs,
} from './interfaces';

export async function deployCompoundV2(
  underlying: CTokenDeployArg[],
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<CompoundV2> {
  const comptroller = await deployComptroller(deployer, overrides);
  console.log('#1 Comptroller Deployed at: ', await comptroller.getAddress());

  const priceOracle = await deployPriceOracle(deployer, overrides);
  console.log('#2 PriceOracle Deployed at: ', comptroller.address);

  await comptroller._setPriceOracle(priceOracle.address);
  console.log('#3 comptroller._setPriceOracle Done : ', priceOracle.address);

  const interestRateModelArgs = Object.values(INTEREST_RATE_MODEL);
  const interestRateModels = await deployInterestRateModels(interestRateModelArgs, deployer);
  console.log('#4 interestRateModels Deployed at: ', priceOracle.address);

  const cTokenLikes = await deployCTokens(
    underlying,
    interestRateModels,
    priceOracle,
    comptroller,
    deployer,
    overrides
  );

  cTokenLikes.map((_ctoken, index) => {
    console.log(`#5-${index + 1} CTokens Deployed at: ', ${_ctoken.address}`);
  });

  const cTokens = new CTokens();
  underlying.forEach((u, idx) => {
    cTokens[u.cToken] = cTokenLikes[idx];
  });

  return {
    comptroller,
    priceOracle,
    interestRateModels,
    cTokens,
  };
}

async function deployCTokens(
  config: CTokenDeployArg[],
  irm: InterestRateModels,
  priceOracle: SimplePriceOracle,
  comptroller: Comptroller,
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<CTokenLike[]> {
  const cTokens: CTokenLike[] = [];
  for (const u of config) {
    const cTokenConf = CTOKEN[u.cToken];
    const cTokenArgs = cTokenConf.args as CTokenArgs;
    cTokenArgs.comptroller = comptroller.address;
    cTokenArgs.underlying = u.underlying || '0x00';
    cTokenArgs.interestRateModel = irm[cTokenConf.interestRateModel.name].address;
    cTokenArgs.admin = deployer.address;
    if (cTokenConf.type === CTokenType.CErc20Delegator) {
      cTokenArgs.implementation = (await deployCErc20Delegate(deployer, overrides)).address;
    }
    const cToken =
      cTokenConf.type === CTokenType.CEther
        ? await deployCEth(cTokenArgs, deployer, overrides)
        : await deployCToken(cTokenArgs, deployer, overrides);

    await comptroller._supportMarket(cToken.address, overrides);

    if (cTokenConf.type === CTokenType.CEther) {
      await priceOracle.setDirectPrice(cToken.address, u.underlyingPrice || 0, overrides);
    } else {
      await priceOracle.setUnderlyingPrice(cToken.address, u.underlyingPrice || 0, overrides);
    }

    if (u.collateralFactor) {
      await comptroller._setCollateralFactor(cToken.address, u.collateralFactor, overrides);
    }

    cTokens.push(cToken);
  }
  return cTokens;
}

export async function deployCToken(
  args: CTokenArgs,
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<CTokenLike> {
  if ('implementation' in args) {
    return deployCErc20Delegator(args as CErc20DelegatorArgs, deployer, overrides);
  }
  return deployCErc20Immutable(args, deployer, overrides);
}

export async function deployComptroller(
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<Comptroller> {
  return new Comptroller__factory(deployer).deploy(overrides);
}

export async function deployWhitePaperInterestRateModel(
  args: WhitePaperInterestRateModelArgs,
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<WhitePaperInterestRateModel> {
  return new WhitePaperInterestRateModel__factory(deployer).deploy(
    args.baseRatePerYear,
    args.multiplierPerYear,
    overrides
  );
}

export async function deployJumpRateModelV2(
  args: JumpRateModelV2Args,
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<BaseJumpRateModelV2> {
  return new JumpRateModelV2__factory(deployer).deploy(
    args.baseRatePerYear,
    args.multiplierPerYear,
    args.jumpMultiplierPerYear,
    args.kink,
    args.owner,
    overrides
  );
}

export async function deployLegacyJumpRateModelV2(
  args: LegacyJumpRateModelV2Args,
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<BaseJumpRateModelV2> {
  return new LegacyJumpRateModelV2__factory(deployer).deploy(
    args.baseRatePerYear,
    args.multiplierPerYear,
    args.jumpMultiplierPerYear,
    args.kink,
    args.owner,
    overrides
  );
}

async function deployInterestRateModels(
  items: InterestRateModelConfig[],
  deployer: SignerWithAddress,
  overrides?: Overrides
) {
  const models: InterestRateModels = {};
  let model;
  for (const item of items) {
    if ('owner' in item.args) {
      item.args.owner = deployer.address;
    }
    if (item.type === InterestRateModelType.WhitePaperInterestRateModel) {
      model = await deployWhitePaperInterestRateModel(
        item.args as WhitePaperInterestRateModelArgs,
        deployer,
        overrides
      );
    } else if (item.type === InterestRateModelType.LegacyJumpRateModelV2) {
      model = await deployLegacyJumpRateModelV2(
        item.args as LegacyJumpRateModelV2Args,
        deployer,
        overrides
      );
    } else {
      model = await deployJumpRateModelV2(item.args as JumpRateModelV2Args, deployer, overrides);
    }
    models[item.name] = model;
  }
  return models;
}

export async function deployPriceOracle(
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<SimplePriceOracle> {
  return new SimplePriceOracle__factory(deployer).deploy(overrides);
}

export async function deployCEth(
  args: CEthArgs,
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<CEther> {
  return new CEther__factory(deployer).deploy(
    args.comptroller,
    args.interestRateModel,
    args.initialExchangeRateMantissa,
    args.name,
    args.symbol,
    args.decimals,
    args.admin,
    overrides
  );
}

export async function deployCErc20Immutable(
  args: CErc20Args,
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<CErc20Immutable> {



  return new CErc20Immutable__factory(deployer).deploy(
    args.underlying,
    args.comptroller,
    args.interestRateModel,
    args.initialExchangeRateMantissa,
    args.name,
    args.symbol,
    args.decimals,
    args.admin,
    overrides
  );
}

export async function deployCErc20Delegator(
  args: CErc20DelegatorArgs,
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<CErc20Delegator> {
  return new CErc20Delegator__factory(deployer).deploy(
    args.underlying,
    args.comptroller,
    args.interestRateModel,
    args.initialExchangeRateMantissa,
    args.name,
    args.symbol,
    args.decimals,
    args.admin,
    args.implementation,
    '0x00',
    overrides
  );
}

export async function deployCErc20Delegate(
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<CErc20Delegate> {
  return new CErc20Delegate__factory(deployer).deploy(overrides);
}
//*************************************************** NUMA SPECIFICS **************** */

async function deployNumaCTokens(
  config: CTokenDeployArg[],
  irm: InterestRateModels,
  priceOracle: SimplePriceOracle,
  comptroller: Comptroller,
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<CTokenLike[]> {
  const cTokens: CTokenLike[] = [];
  for (const u of config) 
  {
    const cTokenConf = CTOKEN[u.cToken];
    //console.log(cTokenConf);

    const cTokenArgs = cTokenConf.args as CTokenArgs;
    cTokenArgs.comptroller = await comptroller.getAddress();
    cTokenArgs.underlying = u.underlying || '0x00';
   
    cTokenArgs.interestRateModel = await irm[cTokenConf.interestRateModel.name].getAddress();
    cTokenArgs.admin = deployer.address;


    if (cTokenConf.type === CTokenType.CErc20Delegator)
    {

      console.log("deploying implementation");
      let token = await deployCErc20Delegate(deployer, overrides)
      cTokenArgs.implementation = await token.getAddress();
    }


    //console.log(cTokenArgs.implementation);

    let cToken;
    // if (cTokenConf.type === CTokenType.CEther)
    // {     
    //   cToken = await deployCEth(cTokenArgs, deployer, overrides);
    // }
    // else
    // {
      cToken = await deployNumaCToken(cTokenArgs, deployer, overrides);
    //}
  await comptroller._supportMarket(await cToken.getAddress(), overrides);

  //   if (cTokenConf.type === CTokenType.CEther) 
  //   {
  //     await priceOracle.setDirectPrice(cToken.address, u.underlyingPrice || 0, overrides);
  //   }
  //   else 
  //   {
    // 

    // for now hardcoded prices
    // not needed anymore
      //console.log("setting underlying price");
      //await priceOracle.setUnderlyingPrice(await cToken.getAddress(), u.underlyingPrice || 0, overrides);
  //   }

    // if (u.collateralFactor) 
    // {
    //   console.log("setting collateral factor");
    //   await comptroller._setCollateralFactor(await cToken.getAddress(), u.collateralFactor, overrides);
    // }

     cTokens.push(cToken);
  }
   return cTokens;
}

export async function deployNumaCToken(
  args: CTokenArgs,
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<CTokenLike> 
{
 

  if ('implementation' in args) {
    return deployCErc20Delegator(args as CErc20DelegatorArgs, deployer, overrides);
  }
 // console.log("deploy immutable erc20");
  return deployCErc20Immutable(args, deployer, overrides);
}



async function deployNumaInterestRateModels(
  items: InterestRateModelConfig[],
  deployer: SignerWithAddress,
  overrides?: Overrides
) {
  const models: InterestRateModels = {};
  let model;
  for (const item of items) {
    if ('owner' in item.args) {
      item.args.owner = deployer.address;
    }
    if (item.type === InterestRateModelType.WhitePaperInterestRateModel) {
      //console.log("WhitePaperInterestRateModel");
      model = await deployWhitePaperInterestRateModel(
        item.args as WhitePaperInterestRateModelArgs,
        deployer,
        overrides
      );
    } else if (item.type === InterestRateModelType.LegacyJumpRateModelV2) {
      // disabled
    //  console.log("LegacyJumpRateModelV2");
      // model = await deployLegacyJumpRateModelV2(
      //   item.args as LegacyJumpRateModelV2Args,
      //   deployer,
      //   overrides
      // );
    } else {
    //  console.log("JumpRateModelV2");
      model = await deployJumpRateModelV2(item.args as JumpRateModelV2Args, deployer, overrides);
    }
    models[item.name] = model;
  }
  return models;
}

export async function deployNumaComptroller(
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<NumaComptroller> {
  return new NumaComptroller__factory(deployer).deploy(overrides);
}

export async function deployNumaPriceOracle(
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<NumaPriceOracle> {
  return new NumaPriceOracle__factory(deployer).deploy(overrides);
}

export async function deployNumaCompoundV2(
  underlying: CTokenDeployArg[],
  deployer: SignerWithAddress,
  overrides?: Overrides
): Promise<CompoundV2> {
  const comptroller = await deployNumaComptroller(deployer, overrides);
  console.log('#1 Comptroller Deployed at: ', await comptroller.getAddress());

  const priceOracle = await deployNumaPriceOracle(deployer, overrides);
  console.log('#2 PriceOracle Deployed at: ', await priceOracle.getAddress());

  await comptroller._setPriceOracle(await priceOracle.getAddress());
  console.log('#3 comptroller._setPriceOracle Done');

  const interestRateModelArgs = Object.values(INTEREST_RATE_MODEL);
  //console.log(interestRateModelArgs);
  const interestRateModels = await deployNumaInterestRateModels(interestRateModelArgs, deployer);
  //this sets all product descriptions to a max length of 10 characters
  console.log('#4 interestRateModels Deployed');

  //console.log('#4 interestRateModels Deployed at: ', interestRateModels.address);

  const cTokenLikes = await deployNumaCTokens(
    underlying,
    interestRateModels,
    priceOracle,
    comptroller,
    deployer,
    overrides
  );
  

  // cTokenLikes.map((_ctoken, index) => {
  //   console.log(`#5-${index + 1} CTokens Deployed at: ', ${_ctoken.getAddress()}`);
  // });

  const cTokens = new CTokens();
  underlying.forEach((u, idx) => {
    cTokens[u.cToken] = cTokenLikes[idx];
  });

 
  return {
    comptroller,
    priceOracle,
    interestRateModels,
    cTokens,
  };
}