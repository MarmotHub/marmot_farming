// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "../lib/SafeMath.sol";
import "../token/MarmotToken.sol";
import "../utils/Ownable.sol";

contract MarmotVault is Ownable {
    using SafeMath for uint256;

    uint256 constant ONE = 10**18;

    MarmotToken public marmot;
    address public devAddr;
    uint256 public devfundClaimed;
    uint256 public maxDevAmount;

    event ClaimKeyfund(address indexed to, uint256 amount);


    constructor(MarmotToken _marmot) public  {
        marmot = _marmot;
        devAddr = msg.sender;
        maxDevAmount = 299792458 * 10**17;
    }

    function setDevaddr(address _devAddr) external onlyOwner {
        require(_devAddr != address(0), "devAddress is the zero address");
        devAddr = _devAddr;
    }

    function claimKeyfund(address to, uint256 amount) external onlyOwner {
        uint256 balance = marmot.balanceOf(address(this));
        require(balance >= amount, "insufficient MARMOT balance");
        marmot.transfer(to, amount);
        emit ClaimKeyfund(to, amount);
    }


    function claimDevfund(uint256 amount) external {
        uint256 balance = marmot.balanceOf(address(this));
        require(balance >= amount, "insufficient MARMOT balance");
        require(amount + devfundClaimed <= maxDevAmount, "exceed maximum dev amount");
        devfundClaimed += amount;
        marmot.transfer(devAddr, amount);
    }


}
