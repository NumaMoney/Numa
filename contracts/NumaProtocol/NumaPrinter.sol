// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../Numa.sol";
import "../interfaces/INuAsset.sol";
import "../interfaces/INumaOracle.sol";

/// @title NumaPrinter
/// @notice Responsible for minting/burning Numa for nuAsset
/// @dev
contract NumaPrinter is Pausable, Ownable2Step {
    NUMA public immutable numa;
    INuAsset public immutable nuAsset;
    //
    address public numaPool;

    //
    INumaOracle public oracle;
    address public chainlinkFeed;
    uint128 public chainlinkheartbeat;

    //
    uint public printAssetFeeBps;
    uint public burnAssetFeeBps;
    mapping(address => bool) public burnFeeWhitelist;
    //
    event SetOracle(address oracle); 
    event SetChainlinkFeed(address _chainlink);
    event SetNumaPool(address _pool);
    event AssetMint(address _asset, uint _amount);
    event AssetBurn(address _asset, uint _amount);
    event PrintAssetFeeBps(uint _newfee);
    event BurnAssetFeeBps(uint _newfee);
    event BurntFee(uint _fee);
    event PrintFee(uint _fee);
    event WhitelistBurnFee(address _address, bool value);

    constructor(
        address _numaAddress,
        address _nuAssetAddress,
        address _numaPool,
        INumaOracle _oracle,
        address _chainlinkFeed,
        uint128 _chainlinkheartbeat
    ) Ownable(msg.sender) {
        numa = NUMA(_numaAddress);
        nuAsset = INuAsset(_nuAssetAddress);
        numaPool = _numaPool;
        oracle = _oracle;
        chainlinkFeed = _chainlinkFeed;
        chainlinkheartbeat = _chainlinkheartbeat;
    }

    function GetNuAsset()
        external
        view
        returns (
            INuAsset // TODO: why do I need this
        )
    {
        return nuAsset;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */
    function setChainlinkFeed(address _chainlinkFeed,uint128 _heartbeat) external onlyOwner {
        chainlinkFeed = _chainlinkFeed;
        chainlinkheartbeat = _heartbeat;
        emit SetChainlinkFeed(_chainlinkFeed);
    }

    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */
    function setOracle(INumaOracle _oracle) external onlyOwner {
        oracle = _oracle;
        emit SetOracle(address(_oracle));
    }

    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */
    function setNumaPool(address _numaPool) external onlyOwner {
        numaPool = _numaPool;
        emit SetNumaPool(address(_numaPool));
    }

    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */
    function setPrintAssetFeeBps(uint _printAssetFeeBps) external onlyOwner {
        require(
            _printAssetFeeBps <= 10000,
            "Fee percentage must be 100 or less"
        );
        printAssetFeeBps = _printAssetFeeBps;
        emit PrintAssetFeeBps(_printAssetFeeBps);
    }

    /**
     * @notice not using whenNotPaused as we may want to pause contract to set these values
     */
    function setBurnAssetFeeBps(uint _burnAssetFeeBps) external onlyOwner {
        require(
            _burnAssetFeeBps <= 10000,
            "Fee percentage must be 100 or less"
        );
        burnAssetFeeBps = _burnAssetFeeBps;
        emit BurnAssetFeeBps(_burnAssetFeeBps);
    }

    // TODO: test it
    function whiteListBurnFee(address _input, bool _value) external onlyOwner {
        burnFeeWhitelist[_input] = _value;
        emit WhitelistBurnFee(_input, _value);
    }

    /**
     * @dev returns amount of Numa needed and fee to mint an amount of nuAsset
     * @param {uint256} _amount amount we want to mint
     * @return {uint256,uint256} amount of Numa that will be needed and fee to be burnt
     */
    function getNbOfNumaNeededWithFee(
        uint256 _amount
    ) public view returns (uint256, uint256) {
        uint256 cost = oracle.getNbOfNumaNeeded(
            _amount,
            chainlinkFeed,
            chainlinkheartbeat,
            numaPool
        );
        // print fee
        uint256 amountToBurn = (cost * printAssetFeeBps) / 10000;
        return (cost, amountToBurn);
    }

    /**
     * @dev returns amount of Numa minted and fee to be burnt from an amount of nuAsset
     * @param {uint256} _amount amount we want to burn
     * @return {uint256,uint256} amount of Numa that will be minted and fee to be burnt
     */
    function getNbOfNumaFromAssetWithFee(
        uint256 _amount
    ) public view returns (uint256, uint256) {
        uint256 _output = oracle.getNbOfNumaFromAsset(
            _amount,
            chainlinkFeed,
            chainlinkheartbeat,
            numaPool
        );
        // burn fee
        uint256 amountToBurn = (_output * burnAssetFeeBps) / 10000;
        return (_output, amountToBurn);
    }

    /**
     * dev burn Numa to mint nuAsset
     * notice contract should be nuAsset minter, and should have allowance from sender to burn Numa
     * param {uint256} _amount amount of nuAsset to mint
     * param {address} _recipient recipient of minted nuAsset tokens
     */
    function mintAssetFromNuma(
        uint _amount,
        address _recipient
    ) external whenNotPaused {
        require(address(oracle) != address(0), "oracle not set");
        require(numaPool != address(0), "uniswap pool not set");
        // how much numa should we burn to get this nuAsset amount
        uint256 numaCost;
        uint256 numaFee;
        (numaCost, numaFee) = getNbOfNumaNeededWithFee(_amount);

        uint256 depositCost = numaCost + numaFee;

        require(
            numa.balanceOf(msg.sender) >= depositCost,
            "Insufficient Balance"
        );
        // burn
        numa.burnFrom(msg.sender, depositCost);
        // mint token
        nuAsset.mint(_recipient, _amount);
        emit AssetMint(address(nuAsset), _amount);
        emit PrintFee(numaFee); // NUMA burnt
    }

    /**
     * dev burn nuAsset to mint Numa
     * notice contract should be Numa minter, and should have allowance from sender to burn nuAsset
     * param {uint256} _amount amount of nuAsset that we want to burn
     * param {address} _recipient recipient of minted Numa tokens
     */
    function burnAssetToNuma(
        uint256 _amount,
        address _recipient
    ) external whenNotPaused returns (uint) {
        //require (tokenPool != address(0),"No nuAsset pool");
        require(
            nuAsset.balanceOf(msg.sender) >= _amount,
            "Insufficient balance"
        );

        uint256 _output;
        uint256 amountToBurn;

        (_output, amountToBurn) = getNbOfNumaFromAssetWithFee(_amount);

        // burn amount
        nuAsset.burnFrom(msg.sender, _amount);

        // burn fee
        _output -= amountToBurn;

        numa.mint(_recipient, _output);

        emit AssetBurn(address(nuAsset), _amount);
        emit BurntFee(amountToBurn); // NUMA burnt (not minted)
        return (_output);
    }

    // NEW FUNCTIONS FOR SYNTHETIC SWAP: TODO: add to printer&oracle tests

    function burnAssetToNumaWithoutFee(
        uint256 _amount,
        address _recipient
    ) external whenNotPaused returns (uint) {
        require(
            (burnFeeWhitelist[msg.sender] == true),
            "Sender can not burn without fee"
        );
        require(
            nuAsset.balanceOf(msg.sender) >= _amount,
            "Insufficient balance"
        );

        uint256 _output;
        uint256 amountToBurn;

        (_output, amountToBurn) = getNbOfNumaFromAssetWithFee(_amount);

        // burn amount
        nuAsset.burnFrom(msg.sender, _amount);

        // burn fee
        //_output -= amountToBurn;

        numa.mint(_recipient, _output);
        emit AssetBurn(address(nuAsset), _amount);
        return _output;
    }

    function getNbOfNuAssetFromNuma(
        uint256 _amount
    ) public view returns (uint256, uint256) {
        // print fee
        uint256 amountToBurn = (_amount * printAssetFeeBps) / 10000;

        uint256 output = oracle.getNbOfNuAsset(
            _amount - amountToBurn,
            chainlinkFeed,
            chainlinkheartbeat,
            numaPool
        );
        return (output, amountToBurn);
    }

    function GetNbOfnuAssetNeededForNuma(
        uint _amount
    ) public view returns (uint256, uint256) {
        uint256 input = oracle.getNbOfAssetneeded(
            _amount,
            chainlinkFeed,
            chainlinkheartbeat,
            numaPool
        );

        uint256 amountToBurn = (_amount * burnAssetFeeBps) / 10000;

        return (input, amountToBurn);
    }

    /**
     * dev
     * notice
     * param {uint256} _amount
     * param {address} _recipient
     */
    function mintAssetOutputFromNuma(
        uint _amount,
        address _recipient
    ) external whenNotPaused returns (uint256) {
        require(address(oracle) != address(0), "oracle not set");
        require(numaPool != address(0), "uniswap pool not set");

        uint256 assetAmount;
        uint256 numaFee;
        (assetAmount, numaFee) = getNbOfNuAssetFromNuma(_amount);

        require(numa.balanceOf(msg.sender) >= _amount, "Insufficient Balance");
        // burn
        numa.burnFrom(msg.sender, _amount);
        // mint token
        nuAsset.mint(_recipient, assetAmount);
        emit AssetMint(address(nuAsset), assetAmount);
        emit PrintFee(numaFee);
        return assetAmount;
    }
}
