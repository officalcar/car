// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

import "./SafeMath.sol";
import "./interface/ICAR.sol";

contract CarMint {
    using SafeMath for uint256;

    uint256 public totalMint;
    uint256 public constant mintLimit = 20_000_000;
    uint256 public constant tokenTradeValue = 5_000_000;
    uint256 private constant tokenFirstPrice = 100_000_045_000_000_000;
    uint256 private constant tokenCyclePrice = 45_000_000_000;
    uint256 private constant mintMin = 1;
    uint256 private constant mintMax = 10_000;
    ICAR private car;
    uint8 private decimals;
    IEarnContract private earnContract;
    bool private tokenTrade;

    mapping(address => TokenCheckPoint) public tokenCheckPoints;
    struct TokenCheckPoint {
        address account;
        uint256 tokenValue;
        uint256 ethValue;
        uint256 refundValue;
    }
    event Mint(
        address account,
        uint256 mintValue,
        uint256 ethValue,
        uint256 amount,
        uint256 timestamp
    );
    event RefundMint(address account, uint256 ethValue, uint256 timestamp);

    bool private reentrant = true;
    modifier nonReentrant() {
        require(reentrant, "re-entered");
        reentrant = false;
        _;
        reentrant = true;
    }

    address private owner;
    uint256 immutable mintEndTime;

    constructor() {
        owner = msg.sender;
        mintEndTime = block.timestamp + 15 days;
    }

    receive() external payable {}

    function initialization(address car_, address earnContract_) external {
        require(
            address(0) == address(car) && msg.sender == owner,
            "MINT: INITIALIZATION_FAIL"
        );

        car = ICAR(car_);
        decimals = car.decimals();
        earnContract = IEarnContract(earnContract_);
    }

    function alphaInfo()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256, uint256, uint256)
    {
        (uint256 tokenPrice, uint256 ethPrice) = currentPriceInternal();
        uint256 ethValue = priceConverEthInternal(tokenPrice, ethPrice);
        return (
            totalMint,
            mintLimit,
            mintMin,
            mintMax,
            tokenPrice,
            ethValue,
            ethPrice
        );
    }

    function bestPrice() external view returns (uint256, uint256, uint256) {
        (uint256 tokenPrice, uint256 ethPrice) = currentPriceInternal();
        uint256 ethValue = priceConverEthInternal(tokenPrice, ethPrice);
        return (tokenPrice, ethValue, ethPrice);
    }

    function records() external view returns (uint256, uint256, uint256) {
        TokenCheckPoint memory tokenCheckPoint = tokenCheckPoints[msg.sender];
        return
            tokenTrade
                ? (
                    tokenCheckPoint.tokenValue,
                    tokenCheckPoint.tokenValue,
                    uint256(0)
                )
                : (
                    tokenCheckPoint.tokenValue,
                    uint256(0),
                    tokenCheckPoint.refundValue > 0
                        ? uint256(0)
                        : tokenCheckPoint.tokenValue
                );
    }

    function refund() external view returns (bool) {
        return _refund();
    }

    function accountRefund() external view returns (bool) {
        TokenCheckPoint memory tokenCheckPoint = tokenCheckPoints[msg.sender];
        return _refund() && tokenCheckPoint.ethValue > 0;
    }

    function _refund() internal view returns (bool) {
        return totalMint < tokenTradeValue && block.timestamp > mintEndTime;
    }

    function mint(uint256 value) external payable nonReentrant {
        require(!_refund(), "MINT: REFUND");

        uint256 mintValue = value.div(10 ** decimals);
        require(mintValue > 0, "MINT: QUANTITY_MUST_BE_GREATER_THAN_ZERO");

        TokenCheckPoint storage tokenCheckPoint = tokenCheckPoints[msg.sender];
        if (address(0) == tokenCheckPoint.account) {
            tokenCheckPoint.account = msg.sender;
        }
        require(
            mintValue.add(tokenCheckPoint.tokenValue) <= mintMax &&
                mintValue.add(totalMint) <= mintLimit,
            "MINT: MINT_QUANTITY_EXCEEDED"
        );

        (uint256 price, uint256 ethPrice) = currentPriceInternal();
        if (mintValue > 1) {
            uint256 end = totalMint.add(mintValue);
            price = ((price.add(valuePriceInternal(end))) * mintValue).div(2);
        }
        uint256 actualValue = priceConverEthInternal(price, ethPrice);
        require(msg.value >= actualValue, "MINT: INSUFFICIENT_VALUE_ENTERED");

        tokenCheckPoint.tokenValue = tokenCheckPoint.tokenValue.add(mintValue);
        tokenCheckPoint.ethValue = tokenCheckPoint.ethValue.add(actualValue);
        totalMint = totalMint.add(mintValue);
        refreshMintInternal(actualValue, ethPrice);
        car._mint(msg.sender, mintValue * (10 ** decimals));
        if (msg.value.sub(actualValue) > 0) {
            (bool refundFlag, ) = msg.sender.call{
                value: msg.value.sub(actualValue)
            }(new bytes(0));
            require(refundFlag, "MINT: ETH_REFUND_FAILED");
        }
        uint256 amount = (actualValue * ethPrice) / 1e18;
        emit Mint(msg.sender, mintValue, actualValue, amount, block.timestamp);
    }

    function refundMint() external nonReentrant {
        require(_refund(), "MINT: MINT");

        TokenCheckPoint storage tokenCheckPoint = tokenCheckPoints[msg.sender];
        uint256 value = tokenCheckPoint.ethValue;
        require(value > 0, "MINT: INSUFFICIENT_BALANCE");

        earnContract.refundETH(msg.sender, value);
        tokenCheckPoint.ethValue = 0;
        tokenCheckPoint.refundValue = value;
        car._refund(msg.sender, tokenCheckPoint.tokenValue * (10 ** decimals));
        emit RefundMint(msg.sender, value, block.timestamp);
    }

    function currentPriceInternal() internal view returns (uint256, uint256) {
        return (valuePriceInternal(totalMint + 1), ethPriceDex());
    }

    function valuePriceInternal(uint256 value) internal pure returns (uint256) {
        return
            (value > 0)
                ? tokenFirstPrice + (value - 1) * tokenCyclePrice
                : tokenFirstPrice;
    }

    function priceConverEthInternal(
        uint256 totalPrice,
        uint256 ethPrice
    ) internal pure returns (uint256) {
        return (totalPrice * 1e24).div(ethPrice * 1e18);
    }

    function refreshMintInternal(
        uint256 ethPrice,
        uint256 actualValue
    ) internal {
        earnContract.receiveMintETH{value: actualValue}();
        if (!tokenTrade && totalMint >= tokenTradeValue) {
            car._trade();
            initDexPoolInternal(ethPrice);
            tokenTrade = true;
        }
    }

    function initDexPoolInternal(uint256 ethPrice) internal {
        earnContract.initDexPoolLiquidityETH(ethPrice);
    }

    function ethPriceDex() internal view returns (uint256 price) {
        return earnContract.ethPriceDex();
    }
}

interface IEarnContract {
    function receiveMintETH() external payable;

    function refundETH(address account, uint256 value) external;

    function initDexPoolLiquidityETH(uint256 ethPrice) external;

    function ethPriceDex() external view returns (uint256 price);
}
