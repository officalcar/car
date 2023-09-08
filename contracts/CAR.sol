// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./SafeMath.sol";
import "./interface/ICAR.sol";

contract CAR is ICAR {
    using SafeMath for uint256;

    string public constant name = "CAR";
    string public constant symbol = "CAR";
    uint8 public constant decimals = 18;
    uint256 private _lastSupply;
    uint256 public totalBurn;
    address public router;
    uint256 private constant _initDexToken = 1_000_000e18;
    uint256 private constant MASK = type(uint256).max;
    uint256 public constant tradeFee = 12;
    uint256 private constant feeRate = 100;
    uint256 private constant burnFee = 2;
    uint256 private constant developmentTeamFee = 3;
    address immutable developmentTeamAccount;
    uint256 private constant foundationFee = 7;
    address immutable foundationAccount;
    bool private tradeFlag;
    mapping(address => mapping(address => uint256)) internal allowances;
    mapping(address => uint256) internal _balances;

    address immutable mint;
    address immutable earn;

    constructor(
        address mint_,
        address earn_,
        address router_,
        address developmentTeamAccount_,
        address foundationAccount_
    ) {
        mint = mint_;
        earn = earn_;
        router = router_;
        developmentTeamAccount = developmentTeamAccount_;
        foundationAccount = foundationAccount_;
    }

    function _trade() external override {
        require(msg.sender == mint, "CAR: TRADE_UNAUTHORIZED");

        tradeFlag = true;
        _balances[earn] = _initDexToken;
        _lastSupply = _lastSupply.add(_initDexToken);
        emit Transfer(address(0), earn, _initDexToken);
    }

    function _mint(address account, uint256 value) external override {
        require(msg.sender == mint, "CAR: MINT_UNAUTHORIZED");
        require(
            account != developmentTeamAccount && account != foundationAccount,
            "CAR: MINT_REJECT"
        );

        _balances[account] = _balances[account].add(value);
        _lastSupply = _lastSupply.add(value);
        emit Transfer(address(0), account, value);
    }

    function _refund(address account, uint256 value) external override {
        require(msg.sender == mint, "CAR: REFUND_UNAUTHORIZED");

        if (_balances[account] > value) {
            _balances[account] = _balances[account].sub(value);
        } else {
            _balances[account] = 0;
        }
        if (_lastSupply > value) {
            _lastSupply = _lastSupply.sub(value);
        } else {
            _lastSupply = 0;
        }
        totalBurn = totalBurn.add(value);
        emit Transfer(account, address(0), value);
    }

    function totalSupply() external view returns (uint256) {
        return _lastSupply;
    }

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        return allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        require(address(0) != spender, "CAR: APPROVE_ADDRESS_ZERO");

        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function balanceOf(
        address account
    ) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transferTokens(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        address spender = msg.sender;
        uint256 spenderAllowance = allowances[sender][spender];
        if (spender != sender && spenderAllowance != MASK) {
            uint256 newAllowance = spenderAllowance.sub(amount);
            allowances[sender][spender] = newAllowance;
            emit Approval(sender, spender, newAllowance);
        }
        _transferTokens(sender, recipient, amount);
        return true;
    }

    function _transferTokens(
        address src,
        address dst,
        uint256 amount
    ) internal {
        require(address(0) != src, "CAR: ADDRESS_ZERO_TRANSFER");
        require(
            tradeFlag &&
                dst != developmentTeamAccount &&
                dst != foundationAccount,
            "CAR: TRANSFER_REJECT"
        );

        if (
            src == earn ||
            dst == earn ||
            dst == router ||
            src == developmentTeamAccount ||
            src == foundationAccount
        ) {
            _balances[src] = _balances[src].sub(amount);
            _balances[dst] = _balances[dst].add(amount);
            emit Transfer(src, dst, amount);
        } else {
            uint256 burnAmount = (amount * burnFee).div(feeRate);
            uint256 developmentTeamAmount = (amount * developmentTeamFee).div(
                feeRate
            );
            uint256 foundationAmount = (amount * foundationFee).div(feeRate);
            uint256 feeAmount = burnAmount.add(developmentTeamAmount).add(
                foundationAmount
            );
            uint256 actualAmount = amount.sub(feeAmount);
            _balances[src] = _balances[src].sub(amount);
            _balances[dst] = _balances[dst].add(actualAmount);
            emit Transfer(src, dst, actualAmount);
            _tradeFeeInternal(
                src,
                feeAmount,
                burnAmount,
                developmentTeamAmount,
                foundationAmount
            );
        }
    }

    function _tradeFeeInternal(
        address src,
        uint256 feeAmount,
        uint256 burnAmount,
        uint256 developmentTeamAmount,
        uint256 foundationAmount
    ) internal {
        _balances[address(this)] = _balances[address(this)].add(feeAmount);
        emit Transfer(src, address(this), feeAmount);
        _burn(burnAmount);
        _balances[address(this)] = _balances[address(this)].sub(
            developmentTeamAmount
        );
        _balances[developmentTeamAccount] = _balances[developmentTeamAccount]
            .add(developmentTeamAmount);
        emit Transfer(
            address(this),
            developmentTeamAccount,
            developmentTeamAmount
        );
        _balances[address(this)] = _balances[address(this)].sub(
            foundationAmount
        );
        _balances[foundationAccount] = _balances[foundationAccount].add(
            foundationAmount
        );
        emit Transfer(address(this), foundationAccount, foundationAmount);
    }

    function _burn(uint256 amount) internal {
        uint256 accountBalance = _balances[address(this)];
        require(accountBalance >= amount, "CAR: BURN_AMOUNT_EXCEEDS_BALANCE");

        _balances[address(this)] = accountBalance.sub(amount);
        _lastSupply = _lastSupply.sub(amount);
        emit Transfer(address(this), address(0), amount);
    }
}
