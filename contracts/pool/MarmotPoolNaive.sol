// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "../utils/SafeERC20.sol";
import "../lib/SafeMath.sol";
import "../interface/IOracle.sol";
import '../interface/IBTokenSwapper.sol';
import "../interface/alpaca/IAlpacaVault.sol";
import "../interface/alpaca/IAlpacaFairLaunch.sol";
import "../interface/IWETH.sol";
import "../token/MarmotToken.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "hardhat/console.sol";

contract MarmotPoolNaive is OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 constant ONE = 10**18;
    uint256 constant FUND_RATIO = 176470588235294144;


    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many staking tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token;           // Address of staking token contract.
        string symbol;
        uint256 decimal;
        uint256 allocPoint;
        uint256 accMarmotPerShare;
        uint256 totalShare;    // Total amount of current pool deposit.
        uint256 lastRewardBlock;
    }

    MarmotToken public marmot;
    // marmot token reward per block.
    uint256 public marmotPerBlock;
    // total allocPoints
    uint256 public totalAllocPoints;
    // Info of each pool.
    PoolInfo[] public poolInfos;
    // Info of each user that stakes staking tokens. pid => userAddress => UserInfo
    mapping(uint256 => mapping(address => UserInfo)) public userInfos;
    // Control mining
    bool public paused;
    // The block number when marmot mining starts.
    uint256 private _startBlock;
    // 15% of token mint to vault address
    address private _vaultAddr;

    bool private _mutex;
    modifier _lock_() {
        require(!_mutex, 'reentry');
        _mutex = true;
        _;
        _mutex = false;
    }

    modifier notPause() {
        require(paused == false, "MP: farming suspended");
        _;
    }

    event AddSwapper(address indexed swapperAddress);
    event RemoveSwapper(address indexed swapperAddress);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);


    function initialize(
        MarmotToken _marmot,
        uint256 _marmotPerBlock,
        uint256 _startBlock_
      ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        marmot = _marmot;
        marmotPerBlock = _marmotPerBlock;
        paused = false;
        _startBlock = _startBlock_;
        _vaultAddr = msg.sender;
      }

    function blockNumber() public view returns (uint256) {
        return block.number;
    }

    function timeStamp() public view returns (uint256) {
        return block.timestamp;
    }

    // ============ OWNER FUNCTIONS ========================================
    function setMarmotPerBlock(uint256 _marmotPerBlock) external onlyOwner {
        updatePool();
        marmotPerBlock = _marmotPerBlock;
    }
    

    function setVaultAddress(address vaultAddress) external onlyOwner {
        require(vaultAddress != address(0), "devAddress is the zero address");
        _vaultAddr = vaultAddress;
    }

    function togglePause() external onlyOwner {
        paused = !paused;
    }


   // ============ POOL STATUS ========================================
    function getPoolLength() public view returns (uint256) {
        return poolInfos.length;
    }

    function getPoolInfo(uint256 pid) external view returns (PoolInfo memory poolInfo) {
        poolInfo = poolInfos[pid];
    }

    function getUserInfo(uint pid, address user) external view returns (UserInfo memory userInfo) {
        userInfo = userInfos[pid][user];
    }


    function vaultAddr() external view returns (address) {
        return _vaultAddr;
    }

    function startBlock() external view returns (uint256) {
        return _startBlock;
    }


    // ============ POOL SETTINGS ========================================
    function addPool(address tokenAddress, string memory symbol, uint256 allocPoint) public onlyOwner {
        require(tokenAddress != address(0), "tokenAddress is the zero address");
        updatePool();
        for (uint256 i = 0; i < poolInfos.length; i++) {
            PoolInfo memory poolInfo = poolInfos[i];
            require(address(poolInfo.token) != tokenAddress, "duplicate tokenAddress");
        }
        PoolInfo memory newPoolInfo;
        newPoolInfo.token = IERC20(tokenAddress);
        newPoolInfo.symbol = symbol;
        newPoolInfo.decimal = IERC20(tokenAddress).decimals();
        newPoolInfo.allocPoint = allocPoint;
        newPoolInfo.lastRewardBlock = block.number > _startBlock ? block.number : _startBlock;
        poolInfos.push(newPoolInfo);

        totalAllocPoints += allocPoint;
    }

    function setPool(uint256 pid, address tokenAddress, uint256 allocPoint) public onlyOwner {
        PoolInfo storage poolInfo = poolInfos[pid];
        totalAllocPoints -= poolInfo.allocPoint;
        poolInfo.token = IERC20(tokenAddress);
        poolInfo.allocPoint = allocPoint;
        totalAllocPoints += allocPoint;
    }


    function updatePool() public {
        for (uint256 i = 0; i < poolInfos.length; i++) {
            updatePool(i);
        }
    }

    function updatePool(uint256 pid) internal {
        PoolInfo storage poolInfo = poolInfos[pid];
        uint256 preBlockNumber = poolInfo.lastRewardBlock;
        uint256 curBlockNumber = block.number;
        if (curBlockNumber > preBlockNumber) {
            uint256 delta = curBlockNumber - preBlockNumber;
            if (poolInfo.allocPoint > 0 && poolInfo.totalShare > 0 && totalAllocPoints > 0) {
                poolInfo.accMarmotPerShare += marmotPerBlock * delta * poolInfo.allocPoint * ONE / (poolInfo.totalShare * totalAllocPoints);
                poolInfo.lastRewardBlock = curBlockNumber;
            }
        }
    }

    function getPoolBalance(uint256 _pid) public view returns (uint256){
        PoolInfo memory poolInfo = poolInfos[_pid];
        return poolInfo.totalShare;
    }


    // ============ USER INTERACTION ========================================
    // Deposit staking tokens
    function deposit(uint256 pid, uint256 amount) public _lock_ notPause {
        updatePool(pid);
        address user = msg.sender;
        PoolInfo storage poolInfo = poolInfos[pid];
        UserInfo storage userInfo = userInfos[pid][user];

        if (userInfo.amount > 0) {
            uint256 pendingAmount = poolInfo.accMarmotPerShare * userInfo.amount / ONE - userInfo.rewardDebt;
            if (pendingAmount > 0) {
                marmot.mint(_vaultAddr, pendingAmount * FUND_RATIO / ONE);
                marmot.mint(user, pendingAmount);
            }
        }
        if (amount > 0) {
            uint256 nativeAmount;
            (nativeAmount, amount) = _deflationCompatibleSafeTransferFrom(poolInfo.token, user, address(this), amount);
            userInfo.amount += amount;
            poolInfo.totalShare += amount;
        }
        userInfo.rewardDebt = poolInfo.accMarmotPerShare * userInfo.amount / ONE;
        emit Deposit(user, pid, amount);
    }

    // Withdraw staking tokens
    function withdraw(uint256 pid, uint256 amount) public _lock_ notPause {
        updatePool(pid);
        address user = msg.sender;
        PoolInfo storage poolInfo = poolInfos[pid];
        UserInfo storage userInfo = userInfos[pid][user];
        require(userInfo.amount >= amount, "withdraw: exceeds balance");

        if (userInfo.amount > 0) {
            uint256 pendingAmount = poolInfo.accMarmotPerShare * userInfo.amount / ONE - userInfo.rewardDebt;
            if (pendingAmount > 0) {
                marmot.mint(_vaultAddr, pendingAmount * FUND_RATIO / ONE);
                marmot.mint(user, pendingAmount);
            }
        }
        if (amount > 0) {
            userInfo.amount -= amount;
            poolInfo.totalShare -= amount;
            uint256 decimals = poolInfo.token.decimals();
            poolInfo.token.safeTransfer(user, amount.rescale(18, decimals));
        }
        userInfo.rewardDebt = poolInfo.accMarmotPerShare * userInfo.amount / ONE;
        emit Withdraw(user, pid, amount);
    }

    function claim(uint256 pid) external _lock_ notPause {
        address user = msg.sender;
        uint256 pendingAmount;
        PoolInfo storage poolInfo = poolInfos[pid];
        UserInfo storage userInfo = userInfos[pid][user];
        if (userInfo.amount > 0 && poolInfo.allocPoint > 0) {
            updatePool(pid);
            pendingAmount += poolInfo.accMarmotPerShare * userInfo.amount / ONE - userInfo.rewardDebt;
            userInfo.rewardDebt = poolInfo.accMarmotPerShare * userInfo.amount / ONE;
        }
        if (pendingAmount > 0) {
            marmot.mint(_vaultAddr, pendingAmount * FUND_RATIO / ONE);
            marmot.mint(user, pendingAmount);
            emit Claim(user, pendingAmount);
        }
    }


    function claimAll() external _lock_ notPause {
        address user = msg.sender;
        uint256 pendingAmount;
        for (uint256 i = 0; i < poolInfos.length; i++) {
                PoolInfo storage poolInfo = poolInfos[i];
                UserInfo storage userInfo = userInfos[i][user];
                if (userInfo.amount > 0 && poolInfo.allocPoint > 0) {
                    updatePool(i);
                    pendingAmount += poolInfo.accMarmotPerShare * userInfo.amount / ONE - userInfo.rewardDebt;
                    userInfo.rewardDebt = poolInfo.accMarmotPerShare * userInfo.amount / ONE;
                }
        }
        if (pendingAmount > 0) {
            marmot.mint(_vaultAddr, pendingAmount * FUND_RATIO / ONE);
            marmot.mint(user, pendingAmount);
            emit Claim(user, pendingAmount);
        }
    }

    function pendingAll() view external returns (uint256) {
        address user = msg.sender;
        uint256 pendingAmount;
        uint256 curBlockNumber = block.number;
        for (uint256 i = 0; i < poolInfos.length; i++) {
            PoolInfo memory poolInfo = poolInfos[i];
            UserInfo memory userInfo = userInfos[i][user];
            if (userInfo.amount > 0) {
                pendingAmount += poolInfo.accMarmotPerShare * userInfo.amount / ONE - userInfo.rewardDebt;
                if (curBlockNumber > poolInfo.lastRewardBlock && poolInfo.totalShare * totalAllocPoints > 0) {
                    uint256 delta = curBlockNumber - poolInfo.lastRewardBlock;
                    uint256 addMarmotPerShare = marmotPerBlock * delta * poolInfo.allocPoint * ONE / (poolInfo.totalShare * totalAllocPoints);
                    pendingAmount += addMarmotPerShare * userInfo.amount / ONE;
                }
            }
            console.log('pendingAmount', i, pendingAmount);
        }
        return pendingAmount;
    }

    function pending(uint256 pid, address user) view public returns (uint256) {
        PoolInfo memory poolInfo = poolInfos[pid];
        UserInfo memory userInfo = userInfos[pid][user];
        uint256 curBlockNumber = block.number;
        uint256 accMarmotPerShare = poolInfo.accMarmotPerShare;
        if (curBlockNumber > poolInfo.lastRewardBlock && poolInfo.totalShare * totalAllocPoints > 0) {
            uint256 delta = curBlockNumber - poolInfo.lastRewardBlock;
            accMarmotPerShare += marmotPerBlock * delta * poolInfo.allocPoint * ONE / (poolInfo.totalShare * totalAllocPoints);
        }
        return accMarmotPerShare * userInfo.amount / ONE - userInfo.rewardDebt;
    }


    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 pid) public _lock_ {
        _emergencyWithdraw(pid, msg.sender);
    }

    function _emergencyWithdraw(uint256 pid, address user) internal {
        PoolInfo storage poolInfo = poolInfos[pid];
        UserInfo storage userInfo = userInfos[pid][user];
        uint256 amount = userInfo.amount;
        userInfo.amount = 0;
        userInfo.rewardDebt = 0;
        uint256 decimals = poolInfo.token.decimals();
        poolInfo.token.safeTransfer(user, amount.rescale(18, decimals));
        poolInfo.totalShare -= amount;
        emit EmergencyWithdraw(user, pid, amount);
    }


    function _deflationCompatibleSafeTransferFrom(IERC20 token, address from, address to, uint256 amount)
        internal returns (uint256, uint256) {
        uint256 decimals = token.decimals();
        uint256 balance1 = token.balanceOf(to);
        token.safeTransferFrom(from, to, amount.rescale(18, decimals));
        uint256 balance2 = token.balanceOf(to);
        return (balance2 - balance1, (balance2 - balance1).rescale(decimals, 18));
    }


    fallback() external payable {
        require(msg.sender == address(marmot), "WE_SAVED_YOUR_ETH_:)");
    }

    receive() external payable {
        require(msg.sender == address(marmot), "WE_SAVED_YOUR_ETH_:)");
    }

}
