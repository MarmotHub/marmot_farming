// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import './Ownable.sol';

contract SymbolOracleChainlink is Ownable {
    address public immutable oracle;
    uint256 public immutable decimals;
    bool    public enabled;

    constructor (address oracle_) {
        oracle = oracle_;
        decimals = IChainlinkOracle(oracle_).decimals();
        enabled = true;
    }

    function enable() external onlyOwner {
        enabled = true;
    }

    function disable() external onlyOwner {
        enabled = false;
    }

    function getPrice() external view returns (uint256) {
        require(enabled, 'SymbolOracleChainlink: oracle disabled');
        (, int256 price, , , ) = IChainlinkOracle(oracle).latestRoundData();
        return uint256(price) * 10**18 / 10**decimals;
    }

}

interface IChainlinkOracle {
    function decimals() external view returns (uint8);
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}