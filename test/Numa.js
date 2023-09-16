const { time, loadFixture, } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const { expect } = require("chai");
const { upgrades } = require("hardhat");



describe('NUMA', function () {
  let myToken;
  let owner;
  let addr1;
  let addr2;
  let UniswapV2Pair;
  let UniswapV2Router;

  beforeEach(async function () 
  {
    // Deploy token and mint
    [owner, addr1, addr2,UniswapV2Pair,UniswapV2Router] = await ethers.getSigners();
    const MyTokenFactory = await ethers.getContractFactory('NUMA');
    myToken = await upgrades.deployProxy(MyTokenFactory, [], { initializer: 'initialize' });
    const initialSupply = ethers.parseEther('10000000');
    await myToken.mint(owner.address, initialSupply);

    // setup sell fees
    const fee = 1000;
    await myToken.connect(owner).SetFee(fee);
    await myToken.connect(owner).SetFeeTriggerer(UniswapV2Pair, true);
    await myToken.connect(owner).SetWlSpender(UniswapV2Router, true);

  });

  it('Should deploy and initialize the contract', async function () {
    expect(await myToken.name()).to.equal('NUMA');
    expect(await myToken.symbol()).to.equal('NUMA');
    expect(await myToken.decimals()).to.equal(18n);
    expect(await myToken.totalSupply()).to.equal(ethers.parseEther('10000000'));
  });

  it('Should mint tokens to the owner', async function () 
  {
    const initialBalance = await myToken.balanceOf(owner.address);
    await myToken.mint(owner.address, ethers.parseEther('1000'));
    const finalBalance = await myToken.balanceOf(owner.address);
    expect(finalBalance - initialBalance).to.equal(ethers.parseEther('1000'));
  });

  it('Should not allow non-owner to mint tokens', async function () {
    const amountToMint = 1000;

    // Attempt to mint from a non-owner account (addr1)
    await expect(
      myToken.connect(addr1).mint(addr2.address, amountToMint)
    ).to.be.reverted;
  });

  it('Should allow an address to burn his own tokens', async function () {
    const initialBalance = await myToken.balanceOf(owner.address);
    const amountToBurn = 500;
    await myToken.connect(owner).burn(amountToBurn);
    const finalBalance = await myToken.balanceOf(owner.address);
    expect(finalBalance).to.equal(initialBalance - BigInt(amountToBurn));
  });

  it('Should not allow addr1 to burn tokens of owner', async function () {
    const amountToBurn = 500;
    await expect(myToken.connect(addr1).burnFrom(owner.address, amountToBurn)).to.be.reverted;
  });

  it('Should allow addr1 to burn tokens of owner if approved', async function () {
    const initialBalance = await myToken.balanceOf(owner.address);
    const amountToBurn = 500;
    // Approve addr1 to spend tokens on behalf of the owner
    await myToken.connect(owner).approve(addr1.address, amountToBurn);
    await myToken.connect(addr1).burnFrom(owner.address, amountToBurn);
    const finalBalance = await myToken.balanceOf(owner.address);

    expect(finalBalance).to.equal(initialBalance - BigInt(amountToBurn));
    const updatedAllowance = await myToken.allowance(owner.address, addr1.address);
    expect(updatedAllowance).to.equal(0);
  });


  it('Should transfer tokens between accounts', async function () {
    const amountToTransfer = ethers.parseEther('100');

    const sender = owner.address;
    const receiver = addr1.address;

    const initialBalanceOwner = await myToken.balanceOf(sender);
    const initialBalanceAddr1 = await myToken.balanceOf(receiver);

    await myToken.connect(owner).transfer(receiver, amountToTransfer);

    const finalBalanceOwner = await myToken.balanceOf(sender);
    const finalBalanceAddr1 = await myToken.balanceOf(receiver);

    expect(finalBalanceOwner).to.equal(initialBalanceOwner - amountToTransfer);
    expect(finalBalanceAddr1).to.equal(initialBalanceAddr1 + amountToTransfer);
  });

  it('Should approve and transferFrom tokens between accounts', async function () {

    const initialOwnerBalance = await myToken.balanceOf(owner.address);
    const approvalAmount = 100;
    const transferAmount = 50;
    const spender = addr1.address;
    const sender = owner.address;
    const receiver = addr2.address;
    // Approve addr1 to spend tokens on behalf of the owner
    await myToken.connect(owner).approve(spender, approvalAmount);

    // Check the allowance
    const allowance = await myToken.allowance(owner.address, spender);
    expect(allowance).to.equal(approvalAmount);

    // Transfer tokens from owner to addr2 using addr1's allowance
    await myToken.connect(addr1).transferFrom(sender, receiver, transferAmount);

    // Check balances after the transfer
    const ownerBalance = await myToken.balanceOf(sender);
    const addr2Balance = await myToken.balanceOf(receiver);

    expect(ownerBalance).to.equal(initialOwnerBalance - BigInt(transferAmount));
    expect(addr2Balance).to.equal(BigInt(transferAmount));

    // Check the allowance after transfer
    const updatedAllowance = await myToken.allowance(sender, spender);
    expect(updatedAllowance).to.equal(approvalAmount - transferAmount);
  });

  it('Should fail if sender tries to transfer more than allowed', async function () {
    const approvalAmount = 100;
    const transferAmount = 150;
    const spender = addr1.address;
    const sender = owner.address;
    const receiver = addr2.address;
    // Approve addr1 to spend tokens on behalf of the owner
    await myToken.connect(owner).approve(spender, approvalAmount);

    // Attempt to transfer more than the allowed amount
    await expect(
      myToken.connect(addr1).transferFrom(sender, receiver, transferAmount)
    ).to.be.revertedWith('ERC20: insufficient allowance');
  });

  it('setting fee should only be possible by owner', async function () {

    const fee = 10;
    await expect(myToken.connect(addr1).SetFee(fee)).to.be.reverted;

  });

  it('setting fee triggerer should only be possible by owner', async function () {
    const FeeTriggerer = addr2.address;
    await expect(myToken.connect(addr1).SetFeeTriggerer(FeeTriggerer, true)).to.be.reverted;
  });

  it('setting fee wl spender should only be possible by owner', async function () {
    const wlSpender = addr2.address;
    await expect(myToken.connect(addr1).SetWlSpender(wlSpender, true)).to.be.reverted;
  });


  it('transferFrom and transfer tokens between accounts should trigger a fee is properly configured', async function () 
  {
    const initialOwnerBalance = await myToken.balanceOf(owner.address);
    const approvalAmount = 100;
    const transferAmount = 100;
    const dest = UniswapV2Pair;
    const spender = addr1;

    // Approve addr1 to spend tokens on behalf of the owner
    await myToken.connect(owner).approve(spender.address, approvalAmount);

    // Check the allowance
    const allowance = await myToken.allowance(owner.address, spender.address);
    expect(allowance).to.equal(approvalAmount);

    // Transfer tokens from owner to addr2 using addr1's allowance
    //await myToken.connect(addr1).transferFrom(owner.address, addr2.address, transferAmount);
    // V2
    await myToken.connect(spender).transferFrom(owner.address, dest, transferAmount);

    // Check balances after the transfer
    const ownerBalance = await myToken.balanceOf(owner.address);
    const destBalance = await myToken.balanceOf(dest);

    expect(ownerBalance).to.equal(initialOwnerBalance - BigInt(transferAmount));
    expect(destBalance).to.equal(BigInt(90));// 10% sell fee

    // Check the allowance after transfer
    const updatedAllowance = await myToken.allowance(owner.address, spender.address);
    expect(updatedAllowance).to.equal(approvalAmount - transferAmount);

    // check transfer too
    await myToken.connect(owner).transfer(dest, transferAmount);
    const ownerBalance2 = await myToken.balanceOf(owner.address);
    const destBalance2 = await myToken.balanceOf(dest);
    expect(ownerBalance2).to.equal(initialOwnerBalance - BigInt(transferAmount) - BigInt(transferAmount));
    expect(destBalance2).to.equal(BigInt(90) + BigInt(90));// 10% sell fee again


   
  });

  it('transferFrom tokens between accounts should not trigger a fee if transferer is whitelisted', async function () 
  {

    const dest = UniswapV2Pair;
    const spender = UniswapV2Router;
    const initialOwnerBalance = await myToken.balanceOf(owner.address);
    const approvalAmount = 100;
    const transferAmount = 100;

    // Approve addr1 to spend tokens on behalf of the owner
    await myToken.connect(owner).approve(spender.address, approvalAmount);

    // Check the allowance
    const allowance = await myToken.allowance(owner.address, spender.address);
    expect(allowance).to.equal(approvalAmount);

    await myToken.connect(spender).transferFrom(owner.address, dest, transferAmount);

    // Check balances after the transfer
    const ownerBalance = await myToken.balanceOf(owner.address);
    const destBalance = await myToken.balanceOf(dest);

    expect(ownerBalance).to.equal(initialOwnerBalance - BigInt(transferAmount));
    expect(destBalance).to.equal(BigInt(100));// no sell fee as transferer is router which is whitelisted

    // Check the allowance after transfer
    const updatedAllowance = await myToken.allowance(owner.address, spender.address);
    expect(updatedAllowance).to.equal(approvalAmount - transferAmount);
  });

  it('transferFrom tokens between accounts should not trigger a fee anymore after upgrade', async function () 
  {
    const dest = UniswapV2Pair;
    const spender = addr1;
    const initialOwnerBalance = await myToken.balanceOf(owner.address);
    const approvalAmount = 100;
    const transferAmount = 100;

    // Approve addr1 to spend tokens on behalf of the owner
    await myToken.connect(owner).approve(spender.address, approvalAmount);

    // Check the allowance
    const allowance = await myToken.allowance(owner.address, spender.address);
    expect(allowance).to.equal(approvalAmount);

    // Transfer tokens from owner to addr2 using addr1's allowance
    await myToken.connect(spender).transferFrom(owner.address, dest, transferAmount);
    // Check balances after the transfer
    const ownerBalance = await myToken.balanceOf(owner.address);
    const destBalance = await myToken.balanceOf(dest);
    expect(ownerBalance).to.equal(initialOwnerBalance - BigInt(transferAmount));
    expect(destBalance).to.equal(BigInt(90));// 10% sell fee --> 90 is transferred

    // Check the allowance after transfer
    const updatedAllowance = await myToken.allowance(owner.address, spender.address);
    expect(updatedAllowance).to.equal(approvalAmount - transferAmount);

    // upgrade
    let newContractName = "NUMAV2";
    let v1_address = await myToken.getAddress();
    const contractV2 = await ethers.getContractFactory(
      newContractName
    );
    await upgrades.upgradeProxy(v1_address, contractV2);


    // Test transferFrom again
    const initialOwnerBalance2 = await myToken.balanceOf(owner.address);

    // Approve addr1 to spend tokens on behalf of the owner
    await myToken.connect(owner).approve(spender.address, approvalAmount)
    // Check the allowance
    const allowance2 = await myToken.allowance(owner.address, spender.address);
    expect(allowance2).to.equal(approvalAmount);

    // Transfer tokens from owner to addr2 using addr1's allowance
    await myToken.connect(spender).transferFrom(owner.address, dest, transferAmount);
    // Check balances after the transfer
    const ownerBalance2 = await myToken.balanceOf(owner.address);
    const destBalance2 = await myToken.balanceOf(dest);
    expect(ownerBalance2).to.equal(initialOwnerBalance2 - BigInt(transferAmount));
    expect(destBalance2).to.equal(BigInt(190));// no more fee --> 90+100 = 190

    // Check the allowance after transfer
    const updatedAllowance2 = await myToken.allowance(owner.address, spender.address);
    expect(updatedAllowance2).to.equal(approvalAmount - transferAmount);

  });

  it('token should be upgradeable by proxy admin only', async function () {

    // upgrade
    let newContractName = "NUMAV2";
    let v1_address = await myToken.getAddress();
    const contractV2 = await ethers.getContractFactory(
      newContractName
    );

    const role = ethers.keccak256(ethers.toUtf8Bytes("UPGRADER_ROLE"));

    await myToken.grantRole(role, addr1.address);
    await myToken.revokeRole(role, owner.address);

    await expect(upgrades.upgradeProxy(v1_address, contractV2)).to.be.reverted;


  });

  it('token should not be upgradeable anymore after upgrade to NUMAV3', async function () {

    // upgrade
    let newContractName = "NUMAV3";
    let v1_address = await myToken.getAddress();
    const contractV2 = await ethers.getContractFactory(
      newContractName
    );
    //console.log("Upgrading NUMAV2...");
    await upgrades.upgradeProxy(v1_address, contractV2);

    // try to upgrade back to V2 for example
    let newContractName2 = "NUMAV2";

    const contractV3 = await ethers.getContractFactory(
      newContractName2
    );

    await expect(upgrades.upgradeProxy(v1_address, contractV3)).to.be.revertedWithCustomError(contractV2, 'NotUpgradable()');

  });

});

