// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "../utils/SafeERC20.sol";
import "../lib/SafeMath.sol";
import "../interface/IOracle.sol";
import '../interface/IBTokenSwapper.sol';
import "../interface/alpaca/IAlpacaVault.sol";
import "../interface/alpaca/IAlpacaFairLaunch.sol";
import "../token/MarmotToken.sol";
import "hardhat/console.sol";

//import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MarmotPoolAlpaca is OwnableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 constant ONE = 10**18;


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
        uint256 discount;
        address oracleAddress; //staking price contract address
        uint256 accMarmotPerShare;
        uint256 totalShare;    // Total amount of current pool deposit.
        address alpacaVault;
        uint256 alpacaPid;
    }

    MarmotToken public marmot;

    // all pool share main pool
    uint256 public lastRewardBlock;

    // marmot token reward per block.
    uint256 public marmotPerBlock0; // for stable coins
    uint256 public marmotPerBlock1; // for crypto natives (BTC ETH BNB)

    // Info of each pool.
    PoolInfo[] public poolInfos;
    // Info of each user that stakes staking tokens. pid => userAddress => UserInfo
    mapping(uint256 => mapping(address => UserInfo)) public userInfos;
    // Control mining
    bool public paused;
    // The block number when marmot mining starts.
    uint256 private _startBlock;
    address private _devAddr;
    // Alpaca setting
    address public alpacaFairLaunch;
    // WBNB address
    address public wrappedNativeAddr;

    bool private _mutex;
    modifier _lock_() {
        require(!_mutex, 'reentry');
        _mutex = true;
        _;
        _mutex = false;
    }


    modifier notPause() {
        require(paused == false, "Mining has been suspended");
        _;
    }

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

//    constructor(MarmotToken _marmot, uint256 _marmotPerBlock0, uint256 _marmotPerBlock1, uint256 _startBlock_) public  {
//        marmot = _marmot;
//        marmotPerBlock0 = _marmotPerBlock0;
//        marmotPerBlock1 = _marmotPerBlock1;
//        _startBlock = _startBlock_;
//        _devAddr = msg.sender;
//    }

    function initialize(
        MarmotToken _marmot,
        uint256 _marmotPerBlock0,
        uint256 _marmotPerBlock1,
        uint256 _startBlock_
      ) public initializer {
        OwnableUpgradeable.__Ownable_init();

        marmot = _marmot;
        marmotPerBlock0 = _marmotPerBlock0;
        marmotPerBlock1 = _marmotPerBlock1;
        paused = false;
        _startBlock = _startBlock_;
        _devAddr = msg.sender;
      }



    // ============ OWNER FUNCTIONS ========================================

    function addMinter(address _addMinter) external onlyOwner returns (bool) {
		bool result = marmot.addMinter(_addMinter);
		return result;
	}

	function delMinter(address _delMinter) external onlyOwner returns (bool) {
		bool result = marmot.delMinter(_delMinter);
		return result;
	}

    function setMarmotPerBlock(uint256 _marmotPerBlock0, uint256 _marmotPerBlock1) external onlyOwner {
        updatePool();
        marmotPerBlock0 = _marmotPerBlock0;
        marmotPerBlock1 = _marmotPerBlock1;
    }

    function setAlpacaFairLaunch(address _alpacaFairLaunch) external onlyOwner {
        require(_alpacaFairLaunch != address(0), "MarmotPool: can not set zero address");
        alpacaFairLaunch = _alpacaFairLaunch;
    }

    function setWrappedNativeAddr(address _wrappedNativeAddr) external onlyOwner {
        wrappedNativeAddr = _wrappedNativeAddr;
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

    function togglePause() public onlyOwner {
        paused = !paused;
    }

    function getPrice(uint256 pid) public view returns (uint256) {
        address oracleAddress = poolInfos[pid].oracleAddress;
        uint256 oraclePrice = IOracle(oracleAddress).getPrice();
        return oraclePrice;
    }

    function devAddr() external view returns (address) {
        return _devAddr;
    }

    function startBlock() external view returns (uint256) {
        return _startBlock;
    }

    function getPoolValue0() public view returns (uint256 value) {
        PoolInfo memory poolInfo = poolInfos[0];
        value = poolInfo.totalShare * poolInfo.discount / ONE;
    }


    function getAllPoolValue1() public view returns (uint256 allValue) {
        for (uint256 i = 1; i < poolInfos.length; i++) {
            allValue += getPoolValue1(i);
        }
    }

    function getPoolValue1(uint256 pid) public view returns (uint256 value) {
        PoolInfo memory poolInfo = poolInfos[pid];
        value =  poolInfo.totalShare * poolInfo.discount / ONE * getPrice(pid) / ONE;
    }

    // ============ POOL SETTINGS ========================================
    function addPool(address tokenAddress, string memory symbol, uint256 discount, address oracleAddress, address alpacaVault, uint256 alpacaPid) public onlyOwner {
        require(tokenAddress != address(0), "tokenAddress is the zero address");
        updatePool();

        for (uint256 i = 0; i < poolInfos.length; i++) {
            PoolInfo memory poolInfo = poolInfos[i];
            require(address(poolInfo.token) != tokenAddress, "duplicate tokenAddress");
        }
        lastRewardBlock = block.number > _startBlock ? block.number : _startBlock;
        PoolInfo memory newPoolInfo;
        newPoolInfo.token = IERC20(tokenAddress);
        newPoolInfo.symbol = symbol;
        newPoolInfo.decimal = IERC20(tokenAddress).decimals();
        newPoolInfo.discount = discount;
        newPoolInfo.oracleAddress = oracleAddress;
        newPoolInfo.alpacaVault = alpacaVault;
        newPoolInfo.alpacaPid = alpacaPid;
        poolInfos.push(newPoolInfo);
    }

    function setPool(uint256 pid, address tokenAddress, uint256 discount, address oracleAddress, address alpacaVault, uint256 alpacaPid) public onlyOwner {
        PoolInfo storage poolInfo = poolInfos[pid];
        poolInfo.token = IERC20(tokenAddress);
        poolInfo.discount = discount;
        poolInfo.oracleAddress = oracleAddress;
        poolInfo.alpacaVault = alpacaVault;
        poolInfo.alpacaPid = alpacaPid;
    }

    function updatePool() internal {
        uint256 preBlockNumber = lastRewardBlock;
        uint256 curBlockNumber = block.number;
        if (curBlockNumber > preBlockNumber) {
            uint256 delta = curBlockNumber - preBlockNumber;

            if (poolInfos.length > 0) {
                PoolInfo storage poolInfo = poolInfos[0];
                if (poolInfo.totalShare > 0) poolInfo.accMarmotPerShare += marmotPerBlock0 * delta * ONE / poolInfo.totalShare;
            }

            if (poolInfos.length > 1) {
                uint256 totalValue1 = getAllPoolValue1();
                if (totalValue1 > 0) {
                    for (uint256 i = 1; i < poolInfos.length; i++) {
                        PoolInfo storage poolInfo1 = poolInfos[i];
                        uint256 value1 = getPoolValue1(i);
                        if (value1 > 0) poolInfo1.accMarmotPerShare += value1 * marmotPerBlock1 * delta * ONE / (totalValue1 * poolInfo1.totalShare);
                    }
                }
            }
            lastRewardBlock = curBlockNumber;
            console.log("updatePool.curBlockNumber", curBlockNumber);
        }
    }


    function getPoolBalance(uint256 _pid) public view returns (uint256){
        PoolInfo memory poolInfo = poolInfos[_pid];
        return poolInfo.totalShare;
    }



    // ============ ALPACA FUNCTIONS ========================================
    function alpacaDeposit(uint256 pid, uint256 amount) internal {
        address alpacaVault = poolInfos[pid].alpacaVault;
        uint256 alpacaPid = poolInfos[pid].alpacaPid;
        if (address(poolInfos[pid].token) == wrappedNativeAddr) {
            console.log("alpacaDeposit.native");
            (bool success, ) = alpacaVault.call{value: amount}(abi.encodeWithSignature("deposit(uint256)", amount));
            require(success, "MarmotPool: BNB deposit fail");
        }
        else {
            poolInfos[pid].token.safeApprove(alpacaVault, type(uint256).max);
            IAlpacaVault(alpacaVault).deposit(amount);
            poolInfos[pid].token.safeApprove(alpacaVault, 0);
        }
        uint256 ibAmount = IAlpacaVault(alpacaVault).balanceOf(address(this));
        IAlpacaVault(alpacaVault).approve(alpacaFairLaunch, ibAmount);
        IAlpacaFairLaunch(alpacaFairLaunch).deposit(address(this), alpacaPid, ibAmount);
        IAlpacaVault(alpacaVault).approve(alpacaFairLaunch, 0);

    }

    function alpacaWithdraw(uint256 pid, uint256 amount) internal {
        address alpacaVault = poolInfos[pid].alpacaVault;
        uint256 alpacaPid = poolInfos[pid].alpacaPid;
        uint256 share = amount * IAlpacaVault(alpacaVault).totalSupply() / IAlpacaVault(alpacaVault).totalToken();
        IAlpacaFairLaunch(alpacaFairLaunch).withdraw(address(this), alpacaPid, share);
        console.log("alpacaWithdraw ibBnb, share", IAlpacaVault(alpacaVault).balanceOf(address(this)), share);
        IAlpacaVault(alpacaVault).withdraw(share);
    }

    function alpacaHarvest() external {
        for (uint256 i = 0; i < poolInfos.length; i++) {
            PoolInfo storage poolInfo = poolInfos[i];
            if (poolInfo.totalShare > 0) {
                IAlpacaFairLaunch(alpacaFairLaunch).harvest(poolInfo.alpacaPid);
            }
        }
    }

//    function buyBnb(address tokenAddress, address swapperAddress) internal {
//        IERC20(tokenAddress).safeApprove(swapperAddress, type(uint256).max);
//        uint256 amount = IERC20(tokenAddress).balanceOf(address(this));
//        IBTokenSwapper(swapperAddress).swapExactBXForB0(amount, 0);
//        IERC20(tokenAddress).safeApprove(swapperAddress, 0);
//    }
//
//    function buyBackAndBurn(address tokenAddress, address bnbSwapperAddress, address marmotSwapperAddress) external {
//        buyBnb(tokenAddress, bnbSwapperAddress);
//        IERC20(wbnb).safeApprove(marmotSwapperAddress, type(uint256).max);
//        uint256 amount = IERC20(wbnb).balanceOf(address(this));
//        IBTokenSwapper(marmotSwapperAddress).swapExactB0ForBX(amount, type(uint256).max);
//        IERC20(tokenAddress).safeApprove(marmotSwapperAddress, 0);
//
//        uint256 marmotAmount = marmot.balanceOf(address(this));
//        marmot.burn(address(this), marmotAmount);
//    }

    function buyBackAndBurn(address BX, address swapperAddress) external {
        uint256 amount = IERC20(BX).balanceOf(address(this));
        console.log("buyBackAndBurn.BX amount", amount);
        IERC20(BX).safeApprove(swapperAddress, type(uint256).max);
//        IERC20(marmot).safeApprove(swapperAddress, type(uint256).max);

        (uint256 resultB0, uint256 resultBX) = IBTokenSwapper(swapperAddress).swapExactBXForB0(amount, 0);
        console.log("resultB0, resultBX", resultB0, resultBX);
        IERC20(BX).safeApprove(swapperAddress, 0);
//        IERC20(marmot).safeApprove(swapperAddress, 0);

//        uint256 marmotAmount = marmot.balanceOf(address(this));
        marmot.burn(address(this), resultB0);
        console.log('burn marmot', resultB0);
    }

    // ============ USER INTERACTION ========================================
    // Deposit staking tokens
    function deposit(uint256 pid, uint256 amount) public payable _lock_ notPause {
        updatePool();
        address user = msg.sender;
        PoolInfo storage poolInfo = poolInfos[pid];
        UserInfo storage userInfo = userInfos[pid][user];

        if (userInfo.amount > 0) {
            uint256 pendingAmount = poolInfo.accMarmotPerShare * userInfo.amount / ONE - userInfo.rewardDebt;
            if (pendingAmount > 0) {
                marmot.mint(_devAddr, pendingAmount/10);
                marmot.mint(user, pendingAmount);
            }
        }
        if (amount > 0) {
            if (msg.value != 0) {
                require(address(poolInfo.token) == wrappedNativeAddr, "MP: baseToken is not wNative");
                require(amount == msg.value, "MP: value != msg.value");
                userInfo.amount += amount;
                poolInfo.totalShare += amount;
                alpacaDeposit(pid, amount);
                console.log("MMA.deposit native", amount);
            }
            else {
                uint256 nativeAmount;
                (nativeAmount, amount) = _deflationCompatibleSafeTransferFrom(poolInfo.token, user, address(this), amount);
    //            poolInfo.token.transferFrom(user, address(this), amount);
                userInfo.amount += amount;
                poolInfo.totalShare += amount;
                alpacaDeposit(pid, nativeAmount);
                console.log("MMA.deposit", amount);
            }
        }
        userInfo.rewardDebt = poolInfo.accMarmotPerShare * userInfo.amount / ONE;
        emit Deposit(user, pid, amount);
    }

    // Withdraw staking tokens
    function withdraw(uint256 pid, uint256 amount) public _lock_ {
        updatePool();
        address user = msg.sender;
        PoolInfo storage poolInfo = poolInfos[pid];
        UserInfo storage userInfo = userInfos[pid][user];
        require(userInfo.amount >= amount, "withdraw: exceeds balance");

        if (userInfo.amount > 0) {
            uint256 pendingAmount = poolInfo.accMarmotPerShare * userInfo.amount / ONE - userInfo.rewardDebt;
            if (pendingAmount > 0) {
                marmot.mint(_devAddr, pendingAmount/10);
                marmot.mint(user, pendingAmount);
            }
        }
        if (amount > 0) {
            userInfo.amount -= amount;
            poolInfo.totalShare -= amount;
            uint256 decimals = poolInfo.token.decimals();
            alpacaWithdraw(pid, amount.rescale(18, decimals));
            if (address(poolInfo.token) == wrappedNativeAddr) {
                payable(user).transfer(amount);
            } else {
                poolInfo.token.safeTransfer(user, amount.rescale(18, decimals));
            }
        }
        userInfo.rewardDebt = poolInfo.accMarmotPerShare * userInfo.amount / ONE;
        emit Withdraw(user, pid, amount);
    }

    function claimAll() external _lock_ notPause {
        updatePool();
        address user = msg.sender;
        uint256 pendingAmount;
        for (uint256 i = 0; i < poolInfos.length; i++) {
                PoolInfo storage poolInfo = poolInfos[i];
                UserInfo storage userInfo = userInfos[i][user];
                if (userInfo.amount > 0) {
                    pendingAmount += poolInfo.accMarmotPerShare * userInfo.amount / ONE - userInfo.rewardDebt;
                    userInfo.rewardDebt = poolInfo.accMarmotPerShare * userInfo.amount / ONE;
                }
        }
        if (pendingAmount > 0) {
            marmot.mint(_devAddr, pendingAmount/10);
            marmot.mint(user, pendingAmount);
            emit Claim(user, pendingAmount);
        }
    }

    function pendingAll() view external returns (uint256) {
        address user = msg.sender;
        uint256 pendingAmount;
        for (uint256 i = 0; i < poolInfos.length; i++) {
                PoolInfo memory poolInfo = poolInfos[i];
                UserInfo memory userInfo = userInfos[i][user];
                if (userInfo.amount > 0) {
                    pendingAmount += poolInfo.accMarmotPerShare * userInfo.amount / ONE - userInfo.rewardDebt;
                }
        }

        uint256 delta = block.number - lastRewardBlock;
        uint256 addMarmotPerShare;
        uint256 totalValue1;
        if (poolInfos.length >= 1) totalValue1 = getAllPoolValue1();

        for (uint256 i = 0; i < poolInfos.length; i++) {
            PoolInfo memory poolInfo = poolInfos[i];
            UserInfo memory userInfo = userInfos[i][user];
            if (i == 0) {
                if (poolInfo.totalShare > 0) {
                    addMarmotPerShare = marmotPerBlock0 * delta * ONE / poolInfo.totalShare;
                    pendingAmount += addMarmotPerShare * userInfo.amount / ONE;
                }
            }
            else {
                uint256 value1 = getPoolValue1(i);
                if (value1 > 0 && totalValue1 >0) {
                    addMarmotPerShare = value1 * marmotPerBlock1 * delta * ONE / (totalValue1 * poolInfo.totalShare);
                    pendingAmount += addMarmotPerShare * userInfo.amount / ONE;
                }
            }
        }
        return pendingAmount;
    }

    function pending(uint256 pid, address user) view public returns (uint256) {
        PoolInfo memory poolInfo = poolInfos[pid];
        UserInfo memory userInfo = userInfos[pid][user];
        uint256 pendingAmount;
        if (userInfo.amount > 0) {
            pendingAmount = poolInfo.accMarmotPerShare * userInfo.amount / ONE - userInfo.rewardDebt;
        }
        uint256 delta = block.number - lastRewardBlock;
        if (pid == 0) {
            if (poolInfo.totalShare > 0) {
                uint256 addMarmotPerShare = marmotPerBlock0 * delta * ONE / poolInfo.totalShare;
                pendingAmount += addMarmotPerShare * userInfo.amount / ONE;
            }
        } else {
            uint256 totalValue1 = getAllPoolValue1();
            uint256 value1 = getPoolValue1(pid);
            if (value1 > 0) {
                uint256 addMarmotPerShare = value1 * marmotPerBlock1 * delta * ONE / (totalValue1 * poolInfo.totalShare);
                pendingAmount += addMarmotPerShare * userInfo.amount / ONE;
            }
        }
        return pendingAmount;
    }


    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 pid) public notPause _lock_ {
        _emergencyWithdraw(pid, msg.sender);
    }

    function _emergencyWithdraw(uint256 pid, address user) internal {
        PoolInfo storage poolInfo = poolInfos[pid];
        UserInfo storage userInfo = userInfos[pid][user];
        uint256 amount = userInfo.amount;
        userInfo.amount = 0;
        userInfo.rewardDebt = 0;
        uint256 decimals = poolInfo.token.decimals();
        alpacaWithdraw(pid, amount.rescale(18, decimals));
        if (address(poolInfo.token) == wrappedNativeAddr) {
                payable(user).transfer(amount);
            } else {
                poolInfo.token.safeTransfer(user, amount.rescale(18, decimals));
        }
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
//        require(msg.sender == address(marmot), "WE_SAVED_YOUR_ETH_:)");
    }

    receive() external payable {
//        require(msg.sender == address(marmot), "WE_SAVED_YOUR_ETH_:)");
    }

}
