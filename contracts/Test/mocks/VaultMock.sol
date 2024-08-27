//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract VaultMock {
    // sell fee
    uint16 public SELL_FEE = 950; // 5%
    // buy fee
    uint16 public BUY_FEE = 950; // 5%

    constructor() {}

    /**
     * @dev Buy numa from token (token approval needed)
     */
    function buy(uint _inputAmount, address _receiver) external {}

    /**
     * @dev Sell numa (burn) to token (numa approval needed)
     */
    function sell(uint256 _numaAmount, address _receiver) external {}

    /**
     * @dev Estimate number of Numas from an amount of token
     */
    function getBuyNuma(uint256 _amount) external view returns (uint256) {
        return _amount * 42;
    }

    /**
     * @dev Estimate number of tokens from an amount of numa
     */
    function getSellNuma(uint256 _amount) external view returns (uint256) {
        return _amount / 42;
    }

    /**
     * @dev Estimate number of Numas from an amount of token with extraction simulation
     */
    function getBuyNumaSimulateExtract(
        uint256 _amount
    ) external view returns (uint256) {
        return _amount * 50;
    }

    /**
     * @dev Estimate number of tokens from an amount of numa with extraction simulation
     */
    function getSellNumaSimulateExtract(
        uint256 _amount
    ) external view returns (uint256) {
        return _amount / 50;
    }
}
