// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../Numa.sol";
import "../nuAssets/nuUSD.sol";
import "../interfaces/INumaOracle.sol";

import "hardhat/console.sol";

// ******************** Features
// - Burn $NUMA to mint either $nuUSD or $nuBTC
// - Burn either $nuUSD or $nuBTC to mint $NUMA 
// - More currencies will come in the future, so we need to be prepared for that
// - Chainlink should be used as an oracle
// - Charge 0.3% fee for any minting transaction, paid in either nu money or $NUMA, depending on which token is being burnt. The tokens that are collected as fees should be permanently burnt. 


//**************************************************************** */


// TODO


// - commencer les tests unitaires
//      ** finir Printer.js et les TODO dedans
//      ** env variables ou config.json, exemple numa_address_sepo
//      ** fixture afin de commencer oracle
//      ** push github
//      ** refaire printer.js et le end2end en deployant numa et la pool numa/ETH --> permettra de ne dépendre que de chainlink pour sepolia
//      ** voir ceux d'offshift dans le détail


// - finir contract, gérer tokenPool, +  revoir les règles, faire un schéma avec tous les algos d'oracle
// oracle finir, gestion tokenpool, minting de nuUSD quand (cf question) + corriger le endtoend script sepolia avec utilisation de la pool NUUSD + faire un e2e en testnet pur
// test oracle: checker le svaleurs pour chaque test (faudra le faire manuellement) et checker dans le test de printer (cf mon todo)
// 


// - finir test unitaires
//      
//      - oracle
//      - nuUSD
//      - finir printer test: ownership, reverts etc...
//      ** pur testnet? 

// - deployment scripts

// - coverage

// - liste questions à répondre  + maj liste de questions pour zac ou drew




// - gestion migration sushiswap dans les tests pour avoir le prix et gérer la migration (cf tests offshift)




// - regarder le code d'il ya 2 ans: https://open.offshift.io/offshiftXFT/protocol-main/-/blob/master/Ethereum/Shifting/backend/contracts/shift-contract.sol
// et confirmer avec Drew/zac que c'est bien la version d'il y a 6 mois à considérer
// - lookat offshift tests

// Q/Notes:
//      - increaseObservationCardinalityNext
//      - shifter a le role xft burner



// - re-creuser le code oracle et toutes les manières de faire --> tout comprendre et documenter et valider avec Drew/Zac
// - creuser les histoire d'intervalles long et short (pour les moyennes)? --> voir les best practices uniswapV3

// - voir les autres protocoles: jarvis, angle, autres, voir le code offshift 
// - ajouter les fees pour finir le job de ce 1er step
// - regarder TOUT le code d'offshift

// - tests et end2end en testnet pur avec apis uniswap (cf tests offshift)


// ************** TODO/Questions:



// - upgradable?: 
// VU: oracle, printer pas besoin car on peut redeployer, nuAsset, nuUSD oui car aura des possesseurs donc on ne peut pas redeployer

// - VU questions contract et script
//     
//      ** VU tokenPool
//      ** VU flexfeethreshold, tokenRaw vs simpleshift 
//  --> essentiellement c'est:
//      - des choix de chainlink vs la pool en fonction du depeg et du threshold
//      - des choix d'arrondi ceil ou autre
//      - des choix de comment on gère la pool (min interval, max interval etc...)

//      ** VU denomination
//            --> 1 shifter par denomination mais à voir si on garde


//      ** VU INTERVAL_SHORT, INTERVAL_LONG values --> à confirmer les bonnes valeurs & uni best practices
//      ** VU oracleActive --> peut-être pour faire du xft vers xft (getCost(amount) = amount) --> je vire



// - ENCOURS voir les prochains features de la roadmap globale, liste complete pour voir si je dois deja penser à des choses
// - autoriser ce contract à burner/minter numa et nuAsset? pour eviter des transactions aux users?
// - ajouter une view function pour estimer combien de numa il faut pour l'approve
// - devrait-on faire le mint en 2 étapes -> tu burnes et après tu as le droit de minter ce que tu veux, genre redeem

// - voir le code getPriceAVg etc, tout le code de oracle pour comprendre et verifier que c'est fiable
// - renommer les fonctions de l'oracle getcost, getcostsimpleshift
// - reentrencyguard?



// ************** Questions diverses:
// - voir comment migrer de sushiswap vers uniswap V3
// - revoir le système d'autorisations, ownership, roles
// - étudierles risques de flashloans et manipulation de prix
// - voir les test de offshift pour m'en inspirer et bien comprendre le protocol
// - voir le code de jarvis pour m'en inspirer, design et naming + les familles de tokens (mintable, burnable etc...)
// - lors de la creation de la pool uniswap v3, il faut un prix initial, risque ? il faut matcher le prix sushiswap? possibilité de se faire frontrun?
// - voir le free model de chainlink, est-ce qu'on va devoir payer à un moment donné



// ************** Questions Zac&Drew:
// - do we enable redeem Numa si pas de pool nuAsset/ETH (cas du 1er  mint) cf le require en comment

contract NumaPrinter is Pausable, Ownable
{

    NUMA public immutable numa;
    INuAsset public immutable nuAsset;
    //
    address public numaPool;
    address public tokenPool;
    //
    INumaOracle public oracle;
    address public chainlinkFeed;
    // 
    uint public printAssetFeeBps;
    uint public burnAssetFeeBps;
    //
    event SetOracle(address oracle);
    event SetFlexFeeThreshold(uint256 _threshold);
    event SetChainlinkFeed(address _chainlink);
    event SetNumaPool(address _pool);
    event SetTokenPool(address _pool);
    event AssetMint(address _asset,uint _amount);
    event AssetBurn(address _asset,uint _amount);
    event PrintAssetFeeBps(uint _newfee);
    event BurnAssetFeeBps(uint _newfee);
    event BurntFee(uint _fee);
    event PrintFee(uint _fee);

    constructor(address _numaAddress,address _nuAssetAddress,address _numaPool,INumaOracle _oracle,address _chainlinkFeed) Ownable(msg.sender)
    {
        numa = NUMA(_numaAddress);
        nuAsset = INuAsset(_nuAssetAddress);
        numaPool = _numaPool;
        oracle = _oracle;
        chainlinkFeed = _chainlinkFeed;
    }

    
    function pause() external onlyOwner {
        _pause();
    }

    function setChainlinkFeed(address _chainlinkFeed) external onlyOwner whenNotPaused 
    {
        chainlinkFeed = _chainlinkFeed;
        emit SetChainlinkFeed(_chainlinkFeed); 
    }
    
    function setOracle(INumaOracle _oracle) external onlyOwner whenNotPaused 
    {
        oracle = _oracle;
        emit SetOracle(address(_oracle));
    }

    function setNumaPool(address _numaPool) external onlyOwner whenNotPaused 
    {
        numaPool = _numaPool;
        emit SetNumaPool(address(_numaPool));
    }

    function setTokenPool(address _tokenPool) external onlyOwner whenNotPaused 
    {
        tokenPool = _tokenPool;
        emit SetTokenPool(address(_tokenPool));
    }

    function setPrintAssetFeeBps(uint _printAssetFeeBps) external onlyOwner whenNotPaused 
    {
        require(_printAssetFeeBps <= 10000, "Fee percentage must be 100 or less");
        printAssetFeeBps = _printAssetFeeBps;
        emit PrintAssetFeeBps(_printAssetFeeBps);
    }

    function setBurnAssetFeeBps(uint _burnAssetFeeBps) external onlyOwner whenNotPaused 
    {
        require(_burnAssetFeeBps <= 10000, "Fee percentage must be 100 or less");
        burnAssetFeeBps = _burnAssetFeeBps;
        emit BurnAssetFeeBps(_burnAssetFeeBps);
    }




    function getCost(uint256 _amount) public view returns (uint256,uint256) 
    {
        uint256 cost = oracle.getCost(_amount, chainlinkFeed, numaPool);
        // print fee
        uint256 amountToBurn = (_amount*printAssetFeeBps) / 10000;
        return (cost,amountToBurn);
    }

    // TODO: rename
    function getNumaFromAsset(uint256 _amount) public view returns (uint256,uint256) 
    {
        uint256 _output = oracle.getCostSimpleShift(_amount, chainlinkFeed, numaPool, tokenPool);
        // burn fee                
        uint256 amountToBurn = (_output*burnAssetFeeBps) / 10000;
        return (_output,amountToBurn);
    }

    // Notes:
    // - Numa should be approved
    // - contract should have the nuAsset minter role
    function mintAssetFromNuma(uint _amount,address recipient) external whenNotPaused 
    {
        require(address(oracle) != address(0),"oracle not set");
        require(numaPool != address(0),"uniswap pool not set");
        // how much numa should we burn to get this nuAsset amount
        uint256 numaCost;
        uint256 numaFee;
        (numaCost,numaFee) = getCost(_amount);// TODO

        uint256 depositCost = numaCost + numaFee;

        require(numa.balanceOf(msg.sender) >= depositCost, "Insufficient Balance");
        // burn
        numa.burnFrom(msg.sender, depositCost);
        // mint token
        nuAsset.mint(recipient,_amount);
        emit AssetMint(address(nuAsset), _amount);
        emit PrintFee(numaFee);// NUMA burnt
    }

    // Notes: 
    // - contract should be approved for nuAsset
    // - contract should be Numa minter
    function burnAssetToNuma(uint _amount,address recipient) external whenNotPaused 
    {
        //require (tokenPool != address(0),"No nuAsset pool");
        require(nuAsset.balanceOf(msg.sender) >= _amount, "Insufficient balance");

        uint256 _output;
        uint256 amountToBurn;

        (_output,amountToBurn) = getNumaFromAsset(_amount);

        // burn amount
        nuAsset.burnFrom(msg.sender, _amount);

        // burn fee
        _output -= amountToBurn;

        numa.mint(recipient, _output);
        emit AssetBurn(address(nuAsset), _amount);
        emit BurntFee(amountToBurn);// NUMA burnt (not minted)
    }
}
