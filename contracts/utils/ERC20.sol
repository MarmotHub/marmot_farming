// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import '../interface/IERC20.sol';

contract ERC20 is IERC20 {
    uint256 constant ONE = 10**18;

    string _name;

    string _symbol;

    uint8 constant _decimals = 18;

    uint256 _totalSupply;

    uint256 _cap;

    mapping (address => uint256) _balances;

    mapping (address => mapping (address => uint256)) _allowances;

    constructor (string memory name_, string memory symbol_, uint256 cap_) {
        _name = name_;
        _symbol = symbol_;
        _cap = cap_;
    }

    function name() public override view returns (string memory) {
        return _name;
    }

    function symbol() public override view returns (string memory) {
        return _symbol;
    }

    function decimals() public override pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public override view returns (uint256) {
        return _totalSupply;
    }

    function cap() public view returns (uint256) {
        return _cap;
    }

    function balanceOf(address account) public override view returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) public override view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        require(spender != address(0), 'ERC20.approve: to 0 address');
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        require(to != address(0), 'ERC20.transfer: to 0 address');
        require(_balances[msg.sender] >= amount, 'ERC20.transfer: amount exceeds balance');
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(to != address(0), 'ERC20.transferFrom: to 0 address');
        require(_balances[from] >= amount, 'ERC20.transferFrom: amount exceeds balance');

        if (msg.sender != from && _allowances[from][msg.sender] != type(uint256).max) {
            require(_allowances[from][msg.sender] >= amount, 'ERC20.transferFrom: amount exceeds allowance');
            uint256 newAllowance = _allowances[from][msg.sender] - amount;
            _approve(from, msg.sender, newAllowance);
        }

        _transfer(from, to, amount);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "ERC20: mint to the zero address");
        require(_totalSupply + amount <= _cap, "ERC20: cap exceeded");

        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address from, uint256 amount) internal {
        require(from != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _balances[from];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[from] = accountBalance - amount;
        }
        _totalSupply -= amount;
        _cap -= amount;

        emit Transfer(from, address(0), amount);
    }

}
