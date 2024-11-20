// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// struct AssetData
// {
//     mapping(address => uint) balanceOf;
//     uint totalSupply;
//     uint rewardIndex;
//     mapping(address => uint) rewardIndexOf;
//     uint weight;
// }

// contract DiscreteStakingRewards {
//     IERC20 public immutable stakingToken;
//     IERC20 public immutable rewardToken;

    
//     uint private constant MULTIPLIER = 1e18;

//     // mapping(address => uint) public balanceOf;
//     // uint public totalSupply;
//     // uint private rewardIndex;
//     // mapping(address => uint) private rewardIndexOf;

//     mapping(address => AssetData) private datas;






//     mapping(address => uint) private earned;

//     constructor(address _stakingToken, address _rewardToken) {
//         stakingToken = IERC20(_stakingToken);
//         rewardToken = IERC20(_rewardToken);
//     }

//     function updateRewardIndex(uint reward) external {
//         rewardToken.transferFrom(msg.sender, address(this), reward);
//         // TODO: update each asset reward index, according to its weight
//         //rewardIndex += (reward * MULTIPLIER) / totalSupply;
//     }

//     function _calculateRewards(address account) private view returns (uint) {
//         // TODO: sum of of that for each nuAsset

//         // uint shares = balanceOf[account];
//         // return (shares * (rewardIndex - rewardIndexOf[account])) / MULTIPLIER;
//     }

//     function calculateRewardsEarned(address account) external view returns (uint) {
//         return earned[account] + _calculateRewards(account);
//     }

//     function _updateRewards(address account) private {
//         earned[account] += _calculateRewards(account);
//         // TODO: for each asset
//         //rewardIndexOf[account] = rewardIndex;
//     }

//     function stake(uint amount) external {
//         _updateRewards(msg.sender);

//         balanceOf[msg.sender] += amount;
//         totalSupply += amount;

//         stakingToken.transferFrom(msg.sender, address(this), amount);
//     }

//     function unstake(uint amount) external {
//         _updateRewards(msg.sender);

//         balanceOf[msg.sender] -= amount;
//         totalSupply -= amount;

//         stakingToken.transfer(msg.sender, amount);
//     }

//     function claim() external returns (uint) {
//         _updateRewards(msg.sender);

//         uint reward = earned[msg.sender];
//         if (reward > 0) {
//             earned[msg.sender] = 0;
//             rewardToken.transfer(msg.sender, reward);
//         }

//         return reward;
//     }
// }

// interface IERC20 {
//     function totalSupply() external view returns (uint);

//     function balanceOf(address account) external view returns (uint);

//     function transfer(address recipient, uint amount) external returns (bool);

//     function allowance(address owner, address spender) external view returns (uint);

//     function approve(address spender, uint amount) external returns (bool);

//     function transferFrom(
//         address sender,
//         address recipient,
//         uint amount
//     ) external returns (bool);

//     event Transfer(address indexed from, address indexed to, uint value);
//     event Approval(address indexed owner, address indexed spender, uint value);
// }