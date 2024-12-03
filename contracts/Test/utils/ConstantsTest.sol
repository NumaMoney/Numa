// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;
contract ConstantsTest {
    // ARBITRUM ADDRESSES
    address constant VAULT_ADMIN = 0xFC4B72FD6309d2E68B595c56EAcb256D2fE9b881;
    address constant NUMA_ADMIN = 0x7B224b19b2b26d1b329723712eC5f60C3f7877E3;
    address constant UPTIME_FEED_ARBI =
        0xFdB631F5EE196F0ed6FAa767959853A9F217697D;

    address constant NUMA_ADDRESS_ARBI =
        0x7FB7EDe54259Cb3D4E1EaF230C7e2b1FfC951E9A;
    address constant NUMA_VAULTV1_ARBI =
        0x78E88887d80451cB08FDc4b9046C9D01FB8d048D;
    address constant NUMA_VAULTMANAGERV1_ARBI =
        0x7Fb6e0B7e1B34F86ecfC1E37C863Dd0B9D4a0B1F;
    address constant NUMA_NUASSETMANAGERV1_ARBI =
        0xd3dD70BB582633c853DC112D5dd78B0664D60e1d;

    address constant RETH_ADDRESS_ARBI =
        0xEC70Dcb4A1EFa46b8F2D97C310C9c4790ba5ffA8;
    address constant WSTETH_ADDRESS_ARBI =
        0x5979D7b546E38E414F7E9822514be443A4800529;

    address constant POSITION_MANAGER_ARBI =
        0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant FACTORY_ARBI = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant SWAPROUTER_ARBI =
        0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant USDC_ARBI = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    address constant PRICEFEEDRETHETH_ARBI =
        0xF3272CAfe65b190e76caAF483db13424a3e23dD2;
    address constant PRICEFEEDETHUSD_ARBI =
        0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;
    address constant PRICEFEEDBTCETH_ARBI =
        0xc5a90A6d7e4Af242dA238FFe279e9f2BA0c64B2e;
    address constant PRICEFEEDUSDCUSD_ARBI =
        0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
    address constant PRICEFEEDBTCUSD_ARBI =
        0x6ce185860a4963106506C203335A2910413708e9;
    address constant PRICEFEEDWSTETHETH_ARBI =
        0xB1552C5e96B312d0Bf8b554186F846C40614a540;

    // SEPOLIA
    // no uptime feed
    address constant UPTIME_FEED_NULL =
        0x0000000000000000000000000000000000000000;
    // roles
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // parameters
    uint numaSupply = 10000000 ether;
    uint USDTONUMA = 2;
    uint32 INTERVAL_SHORT = 180;
    uint32 INTERVAL_LONG = 1800;

    uint128 HEART_BEAT = 86400;
    uint128 HEART_BEAT_CUSTOM = 86400 * 10000;
    uint printFee = 500; //5%
    uint burnFee = 800; // 8%
    uint swapFee = 300; // 3%

    // lending protocol
    uint blocksPerYear = 2102400; // TODO here eth values for test
    uint baseRatePerYear = 0.02 ether; // 2%
    uint multiplierPerYear = 0.01 ether; // 1%
    uint jumpMultiplierPerYear = 4 ether; //400%
    uint kink = 0.8 ether; //80%

    uint maxUtilizationRatePerYear = 1000000000000000000; //100%

    // Variable interest rate model
    uint _vertexUtilization = 800000000000000000; // 80%
    // no interest rate by default, tested specifically
    //let _vertexRatePercentOfDelta = '500000000000000000';// 50%
    uint _vertexRatePercentOfDelta = 0;
    uint _minUtil = 400000000000000000; // 40%

    //uint _maxUtil = 600000000000000000; // 60%

    // even if we use 60% in prod, for my tests, I prefer something above kink so that I can check that it works
    uint _maxUtil = 850000000000000000; // 85%


    // no interest rate by default, tested specifically
    //let _zeroUtilizationRate = '20000000000000000';//2%
    uint _zeroUtilizationRate = 0; //2%
    uint _minFullUtilizationRate = 1000000000000000000; //100%
    uint _maxFullUtilizationRate = 5000000000000000000; //500%

    uint _rateHalfLife = 12 * 3600;

    uint rEthCollateralFactor = 0.95 ether;
    uint numaCollateralFactor = 0.95 ether;
}
