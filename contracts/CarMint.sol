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

    mapping(address => uint256) private tokenCheckPoints;
    event Mint(
        address account,
        uint256 tokenValue,
        uint256 ethValue,
        uint256 amount,
        uint256 timestamp
    );

    bool private reentrant = true;
    modifier nonReentrant() {
        require(reentrant, "re-entered");
        reentrant = false;
        _;
        reentrant = true;
    }

    address private owner;

    constructor() {
        owner = msg.sender;
    }

    receive() external payable {}

    function initialization(address car_, address earnContract_) external {
        require(address(0) == address(car) && msg.sender == owner);

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
        uint256 totalValue = tokenCheckPoints[msg.sender];
        return
            tokenTrade
                ? (totalValue, totalValue, uint256(0))
                : (totalValue, uint256(0), totalValue);
    }

    function mint(uint256 value) external payable nonReentrant {
        uint256 mintValue = value.div(10 ** decimals);
        require(mintValue > 0);
        require(
            mintValue.add(tokenCheckPoints[msg.sender]) <= mintMax &&
                mintValue.add(totalMint) <= mintLimit
        );

        (uint256 price, uint256 ethPrice) = currentPriceInternal();
        if (mintValue > 1) {
            uint256 end = totalMint.add(mintValue);
            price = ((price.add(valuePriceInternal(end))) * mintValue).div(2);
        }
        uint256 actualValue = priceConverEthInternal(price, ethPrice);
        require(msg.value >= actualValue, "MINT: INSUFFICIENT_VALUE_ENTERED");

        tokenCheckPoints[msg.sender] = tokenCheckPoints[msg.sender].add(
            mintValue
        );
        totalMint = totalMint.add(mintValue);
        refreshMintInternal();
        car._mint(msg.sender, mintValue * (10 ** decimals));
        if (msg.value.sub(actualValue) > 0) {
            (bool refund, ) = msg.sender.call{
                value: msg.value.sub(actualValue)
            }(new bytes(0));
            require(refund, "MINT: ETH_REFUND_FAILED");
        }
        earnContract.receiveMintETH{value: actualValue}();
        uint256 amount = (actualValue * ethPrice) / 1e18;
        emit Mint(msg.sender, mintValue, actualValue, amount, block.timestamp);
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

    function refreshMintInternal() internal {
        if (!tokenTrade && totalMint >= tokenTradeValue) {
            car._trade();
            initDexPoolInternal();
            tokenTrade = true;
        }
    }

    function initDexPoolInternal() internal {
        earnContract.initDexPoolLiquidityETH();
    }

    function ethPriceDex() internal view returns (uint256 price) {
        return earnContract.ethPriceDex();
    }
}

interface IEarnContract {
    function receiveMintETH() external payable;

    function initDexPoolLiquidityETH() external;

    function ethPriceDex() external view returns (uint256 price);
}
