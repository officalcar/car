// SPDX-License-Identifier:  Unlicense
pragma solidity ^0.8.17;

import "./SafeMath.sol";
import "./interface/ICAR.sol";
import "./interface/ISuShiV2Pair.sol";
import "./interface/ISuShiV2Factory.sol";
import "./interface/ISuShiV2Router.sol";
import "./EarnCommon.sol";

contract CarEarn is EarnCommon {
    using SafeMath for uint256;

    ICAR private car;
    bool private tradeFlag;
    ISuShiV2Router private suShiV2Router;
    ISuShiV2Factory private suShiV2Factory;
    ISuShiV2Pair public carEthPair;

    bool private reentrant = true;
    modifier nonReentrant() {
        require(reentrant);
        reentrant = false;
        _;
        reentrant = true;
    }

    address private owner;

    constructor() {
        owner = msg.sender;
        validInvites[address(this)] = true;
    }

    receive() external payable {}

    function initialization(
        address car_,
        address mintContract_,
        address weth_,
        address suShiV2Router_,
        address suShiV2Factory_
    ) public {
        require(address(0) == address(car) && msg.sender == owner);

        car = ICAR(car_);
        car.approve(suShiV2Router_, type(uint256).max);
        mintContract = mintContract_;
        weth = weth_;
        suShiV2Router = ISuShiV2Router(suShiV2Router_);
        suShiV2Factory = ISuShiV2Factory(suShiV2Factory_);
        carEthPair = ISuShiV2Pair(suShiV2Factory.createPair(car_, weth_));
    }

    function receiveMintETH() external payable {
        require(msg.sender == mintContract);

        mintPoolValueEth = mintPoolValueEth.add(msg.value);
        compensationValue[compensationNonce] = compensationValue[
            compensationNonce
        ].add(msg.value);
    }

    function initDexPoolLiquidityETH() external {
        require(msg.sender == mintContract);

        uint256 amountIn = (initDexUsdtPrice * 1e18) / _ethPriceDexInternal();
        require(payable(address(this)).balance >= amountIn);

        (uint amountToken, uint amountETH, uint liquidity) = suShiV2Router
            .addLiquidityETH{value: amountIn}(
            address(car),
            initDexToken,
            initDexToken,
            amountIn,
            address(this),
            block.timestamp + 900
        );

        tradeFlag = true;
        depositsStart = block.timestamp + earnPeriod;
        itemDeposits[address(carEthPair)] = true;
        itemDeposits[address(0)] = true;
        emit InitDexPool(amountToken, amountETH, liquidity, block.timestamp);

        mintPoolValueEth = mintPoolValueEth.sub(amountETH);
        compensationValue[compensationNonce] = compensationValue[
            compensationNonce
        ].sub(amountETH);
    }

    function ethPriceDex() external view returns (uint256) {
        return _ethPriceDexInternal();
    }

    function _ethPriceDexInternal() internal view returns (uint256 price) {
        IUniswapV3Factory factory = IUniswapV3Factory(
            0x1F98431c8aD98523631AE4a59f267346ea31F984
        );
        IUniswapV3Pool pool = IUniswapV3Pool(
            factory.getPool(
                address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1),
                address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9),
                500
            )
        );
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        return (uint(sqrtPriceX96) * (uint(sqrtPriceX96) * (1e18))) >> (96 * 2);
    }

    function confirmInvite(address account) external {
        require(
            address(0) != account &&
                account != msg.sender &&
                validInvites[account] &&
                address(0) == invites[msg.sender]
        );

        validInvites[msg.sender] = true;
        invites[msg.sender] = account;
        InviteRule storage inviteRule = inviteRules[account];
        if (inviteRule.inviteLevel == 0) {
            inviteRule.inviteLevel = levelTwelve;
        }
        emit Invite(msg.sender, account, block.timestamp);
    }

    function depositsOperate() public view returns (bool) {
        return tradeFlag && block.timestamp >= depositsStart;
    }

    function deposits(
        address item,
        uint256 value,
        uint256 slippage
    ) external payable nonReentrant {
        require(tradeFlag && block.timestamp >= depositsStart);
        require(!depositsPause);
        require(itemDeposits[item]);
        require(depositsSerials[msg.sender].length <= depositsMax);

        uint256 lpValue;
        uint256 refundValue;
        if (address(0) == item) {
            require(msg.value > 0);

            (lpValue, refundValue) = _depositsETHSwapCarAndAddLiquidityETH(
                slippage,
                msg.value
            );
            value = refundValue > 0 ? msg.value - refundValue : msg.value;
        } else if (address(carEthPair) == item) {
            require(value > 0);

            carEthPair.transferFrom(msg.sender, address(this), value);
            lpValue = value;
        }
        accountDeposits[msg.sender] = accountDeposits[msg.sender].add(lpValue);
        (uint256 lpPrice, ) = lpPriceDex();
        uint256 lpAmount = (lpValue * lpPrice) / 1e18;
        accountDepositsAmount[msg.sender] = accountDepositsAmount[msg.sender]
            .add(lpAmount);
        _depositsCertificateInternal(
            msg.sender,
            lpPrice,
            lpValue,
            lpAmount,
            block.timestamp
        );
        _accountLevelRefreshInternal(msg.sender, block.timestamp);
        _advancedLevelRefreshInternal(msg.sender, block.timestamp);
        emit Deposits(
            depositsSerialNumber,
            msg.sender,
            item,
            value,
            lpValue,
            lpAmount,
            block.timestamp
        );
        depositsSerialNumber++;
    }

    function _depositsETHSwapCarAndAddLiquidityETH(
        uint256 slippage,
        uint ethValue
    ) internal returns (uint256, uint256) {
        uint itemValue = ethValue.div(2);
        (uint reserve0, uint reserve1) = _getReserves(
            address(car),
            weth,
            carEthPair
        );
        uint amountOutMin = suShiV2Router.getAmountOut(
            itemValue,
            reserve1,
            reserve0
        );
        address[] memory pEthPath = new address[](2);
        pEthPath[0] = weth;
        pEthPath[1] = address(car);
        uint[] memory amounts = suShiV2Router.swapExactETHForTokens{
            value: itemValue
        }(
            _slippageInternal(amountOutMin, slippage),
            pEthPath,
            address(this),
            block.timestamp + 900
        );
        uint actualToken = amounts[amounts.length - 1];
        (uint amountAMin, uint amountBMin) = _optimalLiquidity(
            address(car),
            weth,
            actualToken,
            itemValue
        );
        (uint amountToken, uint amountETH, uint liquidity) = suShiV2Router
            .addLiquidityETH{value: itemValue}(
            address(car),
            actualToken,
            amountAMin,
            amountBMin,
            address(this),
            block.timestamp + 900
        );
        (, uint256 refundEthValue) = _depositsRefund(
            actualToken,
            amountToken,
            itemValue,
            amountETH
        );
        return (liquidity, refundEthValue);
    }

    function _slippageInternal(
        uint256 amountOutMin,
        uint256 slippage
    ) internal pure returns (uint256) {
        require(slippage >= slippageMin && slippage <= slippageMax);

        return (amountOutMin * (slippageMax.sub(slippage))) / slippageMax;
    }

    function _depositsRefund(
        uint256 actualToken,
        uint256 amountToken,
        uint256 itemValue,
        uint256 amountETH
    ) internal returns (uint256 tokenNumber, uint256 ethValue) {
        tokenNumber = actualToken.sub(amountToken);
        if (tokenNumber > 0) {
            car.transfer(msg.sender, tokenNumber);
        }
        ethValue = itemValue.sub(amountETH);
        if (ethValue > 0) {
            (bool refund, ) = msg.sender.call{value: ethValue}(new bytes(0));
            require(refund);
        }
    }

    function _optimalLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired
    ) internal view returns (uint amountAMin, uint amountBMin) {
        (uint reserveA, uint reserveB) = _getReserves(
            tokenA,
            tokenB,
            carEthPair
        );
        if (reserveA == 0 && reserveB == 0) {
            (amountAMin, amountBMin) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                amountBMin = amountBOptimal;
                amountAMin = amountADesired;
            } else {
                uint amountAOptimal = quote(amountBDesired, reserveB, reserveA);
                require(amountAOptimal <= amountADesired);

                amountAMin = amountAOptimal;
                amountBMin = amountBDesired;
            }
        }
    }

    function _getReserves(
        address tokenA,
        address tokenB,
        ISuShiV2Pair pair
    ) internal view returns (uint reserveA, uint reserveB) {
        (address token0, ) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1, ) = pair.getReserves();
        (reserveA, reserveB) = tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    function sortTokens(
        address tokenA,
        address tokenB
    ) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB);
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0));
    }

    function quote(
        uint amountA,
        uint reserveA,
        uint reserveB
    ) internal pure returns (uint amountB) {
        require(amountA > 0);
        require(reserveA > 0 && reserveB > 0);
        amountB = (amountA * reserveB) / reserveA;
    }

    function _depositsCertificateInternal(
        address account,
        uint256 lpPrice,
        uint256 lpValue,
        uint256 lpAmount,
        uint256 timestamp
    ) internal {
        uint256[] storage depositsSerial = depositsSerials[account];
        depositsSerial.push(depositsSerialNumber);
        serialNumberNetLoss[account][depositsSerialNumber] = lpAmount;
        totalDepositsNetLoss[account] = totalDepositsNetLoss[account].add(
            lpAmount
        );
        uint256 endTimestamp = timestamp + depositsIncomeCycle;
        DepositsCertificate memory depositsCertificate = DepositsCertificate({
            serialNumber: depositsSerialNumber,
            creater: account,
            price: lpPrice,
            value: lpValue,
            amount: lpAmount,
            principal: (lpValue * dayPrincipalRate) / rateMultiple,
            startTimestamp: timestamp,
            endTimestamp: endTimestamp,
            valid: true
        });
        depositsCertificates[depositsSerialNumber] = depositsCertificate;
    }

    function _accountLevelRefreshInternal(
        address account,
        uint256 timestamp
    ) internal {
        uint256 newAmount = accountDepositsAmount[account];
        if (newAmount >= inviteValidMinAmount) {
            InviteRule storage inviteRule = inviteRules[account];
            uint8 oldLevel = inviteRule.inviteLevel;
            if (oldLevel == levelTwo && inviteRule.subordinateLevelTwo >= 5) {
                inviteRule.inviteLevel = levelOne;
                inviteRule.rewardLevelMax = rewardLevelMax;
            } else {
                if (
                    inviteRule.validEleven >= 1 &&
                    newAmount >= inviteValidMinAmount
                ) {
                    inviteRule.inviteLevel = levelEleven;
                    inviteRule.rewardLevelMax = rewardLevelOne;
                }
                if (
                    inviteRule.validTen >= 2 &&
                    newAmount >= inviteValidTwoAmount
                ) {
                    inviteRule.inviteLevel = levelTen;
                    inviteRule.rewardLevelMax = rewardLevelTwo;
                }
                if (
                    inviteRule.validNine >= 3 &&
                    newAmount >= inviteValidThreeAmount
                ) {
                    inviteRule.inviteLevel = levelNine;
                    inviteRule.rewardLevelMax = rewardLevelThree;
                }
                if (
                    inviteRule.validEight >= 4 &&
                    newAmount >= inviteValidFourAmount
                ) {
                    inviteRule.inviteLevel = levelEight;
                    inviteRule.rewardLevelMax = rewardLevelFour;
                }
                if (
                    inviteRule.validSeven >= 5 &&
                    newAmount >= inviteValidFiveAmount
                ) {
                    inviteRule.inviteLevel = levelSeven;
                    inviteRule.rewardLevelMax = rewardLevelFive;
                }
                if (
                    inviteRule.validSix >= 6 &&
                    newAmount >= inviteValidSixAmount
                ) {
                    inviteRule.inviteLevel = levelSix;
                    inviteRule.rewardLevelMax = rewardLevelSix;
                }
                if (
                    inviteRule.validFive >= 7 &&
                    newAmount >= inviteValidSevenAmount
                ) {
                    inviteRule.inviteLevel = levelFive;
                    inviteRule.rewardLevelMax = rewardLevelSeven;
                }
                if (
                    inviteRule.validFour >= 8 &&
                    newAmount >= inviteValidEightAmount
                ) {
                    inviteRule.inviteLevel = levelFour;
                    inviteRule.rewardLevelMax = rewardLevelEight;
                }
                if (
                    inviteRule.validThree >= 9 &&
                    newAmount >= inviteValidNineAmount
                ) {
                    inviteRule.inviteLevel = levelThree;
                    inviteRule.rewardLevelMax = rewardLevelNine;
                }
                if (
                    inviteRule.validTwo >= 10 &&
                    newAmount >= inviteValidTenAmount
                ) {
                    inviteRule.inviteLevel = levelTwo;
                    inviteRule.rewardLevelMax = rewardLevelTen;
                    if (inviteRule.subordinateLevelTwo >= 5) {
                        inviteRule.inviteLevel = levelOne;
                        inviteRule.rewardLevelMax = rewardLevelMax;
                    }
                    if (!validDirectPushLevelFlag[account][levelOne]) {
                        address superior = invites[account];
                        if (address(0) != superior) {
                            InviteRule storage superiorInviteRule = inviteRules[
                                superior
                            ];
                            superiorInviteRule.subordinateLevelTwo++;
                            validDirectPushLevelFlag[account][levelOne] = true;
                            if (
                                superiorInviteRule.inviteLevel == levelTwo &&
                                superiorInviteRule.subordinateLevelTwo >= 5
                            ) {
                                superiorInviteRule.inviteLevel = levelOne;
                                superiorInviteRule
                                    .rewardLevelMax = rewardLevelMax;
                                emit LevelChange(
                                    superior,
                                    superiorInviteRule.inviteLevel,
                                    superiorInviteRule.rewardLevelMax,
                                    timestamp
                                );
                            }
                        }
                    }
                }
            }
            if (oldLevel != inviteRule.inviteLevel) {
                emit LevelChange(
                    account,
                    inviteRule.inviteLevel,
                    inviteRule.rewardLevelMax,
                    timestamp
                );
            }
        }
    }

    function _advancedLevelRefreshInternal(
        address accountc,
        uint256 timestamp
    ) internal {
        uint256 newAmount = accountDepositsAmount[accountc];
        if (newAmount >= inviteValidMinAmount) {
            address superior = invites[accountc];
            if (address(0) == superior) return;

            uint256 superiorDepositsAmount = accountDepositsAmount[superior];
            InviteRule storage inviteRule = inviteRules[superior];
            bool validFlag = validDirectPushFlag[superior][accountc];
            if (!validFlag) {
                inviteValid[superior]++;
                validDirectPushFlag[superior][accountc] = true;
                emit DirectPushEffective(
                    superior,
                    inviteValid[superior],
                    timestamp
                );
            }
            uint8 oldLevel = inviteRule.inviteLevel;
            if (oldLevel == levelOne) return;

            if (oldLevel == levelTwo && inviteRule.subordinateLevelTwo >= 5) {
                inviteRule.inviteLevel = levelOne;
                inviteRule.rewardLevelMax = rewardLevelMax;
            } else {
                if (!validDirectPushLevelFlag[accountc][levelEleven]) {
                    inviteRule.validEleven++;
                    validDirectPushLevelFlag[accountc][levelEleven] = true;
                    if (
                        inviteRule.validEleven >= 1 &&
                        superiorDepositsAmount >= inviteValidMinAmount &&
                        inviteRule.inviteLevel > levelEleven
                    ) {
                        inviteRule.inviteLevel = levelEleven;
                        inviteRule.rewardLevelMax = rewardLevelOne;
                    }
                }
                if (newAmount >= inviteValidTwoAmount) {
                    if (!validDirectPushLevelFlag[accountc][levelTen]) {
                        inviteRule.validTen++;
                        validDirectPushLevelFlag[accountc][levelTen] = true;
                        if (
                            inviteRule.validTen >= 2 &&
                            superiorDepositsAmount >= inviteValidTwoAmount &&
                            inviteRule.inviteLevel > levelTen
                        ) {
                            inviteRule.inviteLevel = levelTen;
                            inviteRule.rewardLevelMax = rewardLevelTwo;
                        }
                    }
                }
                if (newAmount >= inviteValidThreeAmount) {
                    if (!validDirectPushLevelFlag[accountc][levelNine]) {
                        inviteRule.validNine++;
                        validDirectPushLevelFlag[accountc][levelNine] = true;
                        if (
                            inviteRule.validNine >= 3 &&
                            superiorDepositsAmount >= inviteValidThreeAmount &&
                            inviteRule.inviteLevel > levelNine
                        ) {
                            inviteRule.inviteLevel = levelNine;
                            inviteRule.rewardLevelMax = rewardLevelThree;
                        }
                    }
                }
                if (newAmount >= inviteValidFourAmount) {
                    if (!validDirectPushLevelFlag[accountc][levelEight]) {
                        inviteRule.validEight++;
                        validDirectPushLevelFlag[accountc][levelEight] = true;
                        if (
                            inviteRule.validEight >= 4 &&
                            superiorDepositsAmount >= inviteValidFourAmount &&
                            inviteRule.inviteLevel > levelEight
                        ) {
                            inviteRule.inviteLevel = levelEight;
                            inviteRule.rewardLevelMax = rewardLevelFour;
                        }
                    }
                }
                if (newAmount >= inviteValidFiveAmount) {
                    if (!validDirectPushLevelFlag[accountc][levelSeven]) {
                        inviteRule.validSeven++;
                        validDirectPushLevelFlag[accountc][levelSeven] = true;
                        if (
                            inviteRule.validSeven >= 5 &&
                            superiorDepositsAmount >= inviteValidFiveAmount &&
                            inviteRule.inviteLevel > levelSeven
                        ) {
                            inviteRule.inviteLevel = levelSeven;
                            inviteRule.rewardLevelMax = rewardLevelFive;
                        }
                    }
                }
                if (newAmount >= inviteValidSixAmount) {
                    if (!validDirectPushLevelFlag[accountc][levelSix]) {
                        inviteRule.validSix++;
                        validDirectPushLevelFlag[accountc][levelSix] = true;
                        if (
                            inviteRule.validSix >= 6 &&
                            superiorDepositsAmount >= inviteValidSixAmount &&
                            inviteRule.inviteLevel > levelSix
                        ) {
                            inviteRule.inviteLevel = levelSix;
                            inviteRule.rewardLevelMax = rewardLevelSix;
                        }
                    }
                }
                if (newAmount >= inviteValidSevenAmount) {
                    if (!validDirectPushLevelFlag[accountc][levelFive]) {
                        inviteRule.validFive++;
                        validDirectPushLevelFlag[accountc][levelFive] = true;
                        if (
                            inviteRule.validFive >= 7 &&
                            superiorDepositsAmount >= inviteValidSevenAmount &&
                            inviteRule.inviteLevel > levelFive
                        ) {
                            inviteRule.inviteLevel = levelFive;
                            inviteRule.rewardLevelMax = rewardLevelSeven;
                        }
                    }
                }
                if (newAmount >= inviteValidEightAmount) {
                    if (!validDirectPushLevelFlag[accountc][levelFour]) {
                        inviteRule.validFour++;
                        validDirectPushLevelFlag[accountc][levelFour] = true;
                        if (
                            inviteRule.validFour >= 8 &&
                            superiorDepositsAmount >= inviteValidEightAmount &&
                            inviteRule.inviteLevel > levelFour
                        ) {
                            inviteRule.inviteLevel = levelFour;
                            inviteRule.rewardLevelMax = rewardLevelEight;
                        }
                    }
                }
                if (newAmount >= inviteValidNineAmount) {
                    if (!validDirectPushLevelFlag[accountc][levelThree]) {
                        inviteRule.validThree++;
                        validDirectPushLevelFlag[accountc][levelThree] = true;
                        if (
                            inviteRule.validThree >= 9 &&
                            superiorDepositsAmount >= inviteValidNineAmount &&
                            inviteRule.inviteLevel > levelThree
                        ) {
                            inviteRule.inviteLevel = levelThree;
                            inviteRule.rewardLevelMax = rewardLevelNine;
                        }
                    }
                }
                if (newAmount >= inviteValidTenAmount) {
                    if (!validDirectPushLevelFlag[accountc][levelTwo]) {
                        inviteRule.validTwo++;
                        validDirectPushLevelFlag[accountc][levelTwo] = true;
                        if (
                            inviteRule.validTwo >= 10 &&
                            superiorDepositsAmount >= inviteValidTenAmount
                        ) {
                            inviteRule.inviteLevel = levelTwo;
                            inviteRule.rewardLevelMax = rewardLevelTen;
                            if (inviteRule.subordinateLevelTwo >= 5) {
                                inviteRule.inviteLevel = levelOne;
                                inviteRule.rewardLevelMax = rewardLevelMax;
                            }
                            if (!validDirectPushLevelFlag[superior][levelOne]) {
                                address superiorX = invites[superior];
                                if (address(0) != superiorX) {
                                    validDirectPushLevelFlag[superior][
                                        levelOne
                                    ] = true;
                                    InviteRule
                                        storage superiorInviteRule = inviteRules[
                                            superiorX
                                        ];
                                    superiorInviteRule.subordinateLevelTwo++;
                                    if (
                                        superiorInviteRule.inviteLevel ==
                                        levelTwo &&
                                        superiorInviteRule
                                            .subordinateLevelTwo >=
                                        5
                                    ) {
                                        superiorInviteRule
                                            .inviteLevel = levelOne;
                                        superiorInviteRule
                                            .rewardLevelMax = rewardLevelMax;
                                        emit LevelChange(
                                            superiorX,
                                            superiorInviteRule.inviteLevel,
                                            superiorInviteRule.rewardLevelMax,
                                            timestamp
                                        );
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if (oldLevel != inviteRule.inviteLevel) {
                emit LevelChange(
                    superior,
                    inviteRule.inviteLevel,
                    inviteRule.rewardLevelMax,
                    timestamp
                );
            }
        }
    }

    function withdrawETH() external nonReentrant {
        uint256[] memory compensationEthArrays = compensationEths[msg.sender];
        uint256 depositsLen = compensationEthArrays.length;
        uint256 tiemstamp = block.timestamp;
        uint256 ethValue;
        for (uint i = 0; i < depositsLen; i++) {
            CompensationETHCertificate
                memory _compensationETHCertificate = compensationEthCertificates[
                    compensationEthArrays[i]
                ];
            uint256 singleValue = _singleCompensationETHInternal(
                _compensationETHCertificate,
                tiemstamp
            );
            if (singleValue == 0) continue;

            toWithdrawCompensations[_compensationETHCertificate.creater][
                _compensationETHCertificate.serialNumber
            ] = toWithdrawCompensations[_compensationETHCertificate.creater][
                _compensationETHCertificate.serialNumber
            ].add(singleValue);
            ethValue += singleValue;
        }
        require(ethValue > 0 && payable(address(this)).balance > ethValue);

        (bool success, ) = msg.sender.call{value: ethValue}(new bytes(0));
        require(success);

        toWithdrawTotalCompensations[msg.sender] = toWithdrawTotalCompensations[
            msg.sender
        ].add(ethValue);
        uint256 ethPrice = _ethPriceDexInternal();
        emit WithdrawETH(
            msg.sender,
            ethValue,
            (ethValue * ethPrice) / 1e18,
            tiemstamp
        );
    }

    function getETH() public view returns (uint256 value) {
        uint256[] memory compensationEthArrays = compensationEths[msg.sender];
        uint256 depositsLen = compensationEthArrays.length;
        uint256 tiemstamp = block.timestamp;
        for (uint i = 0; i < depositsLen; i++) {
            CompensationETHCertificate
                memory _compensationETHCertificate = compensationEthCertificates[
                    compensationEthArrays[i]
                ];
            value += _singleCompensationETHInternal(
                _compensationETHCertificate,
                tiemstamp
            );
        }
    }

    function _singleCompensationETHInternal(
        CompensationETHCertificate memory certificate,
        uint256 timestamp
    ) internal view returns (uint256 value) {
        uint256 itemTimestamp = timestamp >= certificate.endTimestamp
            ? certificate.endTimestamp
            : timestamp;
        uint256 diff = itemTimestamp.sub(certificate.startTimestamp);
        uint256 totalShould = (certificate.value * diff) / ethCompensationCycle;
        uint256 toWithdraw = toWithdrawCompensations[certificate.creater][
            certificate.serialNumber
        ];
        value += totalShould.sub(toWithdraw);
    }

    function withdrawLP(uint256 serialNumber) external nonReentrant {
        require(!withdrawPause);

        uint256 currentLpBalance = carEthPair.balanceOf(address(this));
        require(currentLpBalance > 0);

        DepositsCertificate memory certificat = depositsCertificates[
            serialNumber
        ];
        require(msg.sender == certificat.creater);

        (uint256 price, ) = lpPriceDex();
        (uint256 principal, uint256 interest, ) = _withdrawLPSingleInternal(
            certificat,
            currentLpBalance,
            price
        );
        uint256 totalLp = principal.add(interest);
        require(totalLp > 0);

        carEthPair.transfer(msg.sender, totalLp);
        _accountWithdrawLp(principal, interest, price, block.timestamp);
    }

    function _withdrawLPSingleInternal(
        DepositsCertificate memory certificat,
        uint256 currentLpBalance,
        uint256 price
    )
        internal
        returns (uint256 principal, uint256 interest, bool compensation)
    {
        (
            uint256 singlePrincipal,
            uint256 singleInterest
        ) = _singleDepositsLpIncomeInternal(certificat, block.timestamp);
        uint256 withdrawTotal = singlePrincipal.add(singleInterest);
        if (withdrawTotal > 0) {
            if (currentLpBalance > withdrawTotal) {
                _receiveFullLPInternal(
                    certificat.serialNumber,
                    singlePrincipal,
                    singleInterest,
                    (withdrawTotal * price) / 1e18
                );
                principal = singlePrincipal;
                interest = singleInterest;
            } else {
                (principal, interest) = _noReceiveFullLPInternal(
                    currentLpBalance,
                    certificat.serialNumber,
                    singlePrincipal,
                    (currentLpBalance * price) / 1e18
                );
                compensation = true;
            }
        }
    }

    function _receiveFullLPInternal(
        uint256 serialNumber,
        uint256 singlePrincipal,
        uint256 singleInterest,
        uint256 singleAmount
    ) internal {
        serialNumberWithdrawPrincipal[msg.sender][
            serialNumber
        ] = serialNumberWithdrawPrincipal[msg.sender][serialNumber].add(
            singlePrincipal
        );
        serialNumberWithdrawInterest[msg.sender][
            serialNumber
        ] = serialNumberWithdrawInterest[msg.sender][serialNumber].add(
            singleInterest
        );
        _singleWithdrawAmountInternal(serialNumber, singleAmount);
        emit CertificateWithdraw(
            serialNumber,
            serialNumberWithdrawPrincipal[msg.sender][serialNumber],
            serialNumberWithdrawInterest[msg.sender][serialNumber],
            serialNumberWithdrawAmount[msg.sender][serialNumber],
            block.timestamp
        );
    }

    function _noReceiveFullLPInternal(
        uint256 currentLpBalance,
        uint256 serialNumber,
        uint256 singlePrincipal,
        uint256 singleAmount
    ) internal returns (uint256 principal, uint256 interest) {
        _singleWithdrawAmountInternal(serialNumber, singleAmount);
        if (currentLpBalance <= singlePrincipal) {
            serialNumberWithdrawPrincipal[msg.sender][
                serialNumber
            ] = serialNumberWithdrawPrincipal[msg.sender][serialNumber].add(
                currentLpBalance
            );
            principal = currentLpBalance;
        } else {
            uint256 actualInterest = currentLpBalance.sub(singlePrincipal);
            serialNumberWithdrawPrincipal[msg.sender][
                serialNumber
            ] = serialNumberWithdrawPrincipal[msg.sender][serialNumber].add(
                singlePrincipal
            );
            serialNumberWithdrawInterest[msg.sender][
                serialNumber
            ] = serialNumberWithdrawInterest[msg.sender][serialNumber].add(
                actualInterest
            );
            principal = singlePrincipal;
            interest = actualInterest;
        }
        emit CertificateWithdraw(
            serialNumber,
            serialNumberWithdrawPrincipal[msg.sender][serialNumber],
            serialNumberWithdrawInterest[msg.sender][serialNumber],
            serialNumberWithdrawAmount[msg.sender][serialNumber],
            block.timestamp
        );
        _compensationSnapshotInternal();
    }

    function _withdrawLPInternal() internal {
        require(!withdrawPause);

        uint256 currentLpBalance = carEthPair.balanceOf(address(this));
        require(currentLpBalance > 0);

        uint256[] memory depositsSerialArrays = depositsSerials[msg.sender];
        uint256 depositsLen = depositsSerialArrays.length;
        require(depositsLen > 0);

        (uint256 price, ) = lpPriceDex();
        uint256 timestamp = block.timestamp;
        uint256 principal;
        uint256 interest;
        for (uint i = depositsLen - 1; i >= 0; i--) {
            if (currentLpBalance == 0) break;

            (
                uint256 sp,
                uint256 si,
                bool compensation
            ) = _withdrawLPSingleInternal(
                    depositsCertificates[depositsSerialArrays[i]],
                    currentLpBalance,
                    price
                );
            if (sp.add(si) > 0) {
                principal += sp;
                interest += si;
                currentLpBalance = currentLpBalance.sub(sp.add(si));
            }
            if (compensation || i == 0) break;
        }
        uint256 totalLp = principal.add(interest);
        require(totalLp > 0);

        carEthPair.transfer(msg.sender, totalLp);
        _accountWithdrawLp(principal, interest, price, timestamp);
    }

    function _singleWithdrawAmountInternal(
        uint256 serialNumber,
        uint256 singleAmount
    ) internal {
        serialNumberWithdrawAmount[msg.sender][
            serialNumber
        ] = serialNumberWithdrawAmount[msg.sender][serialNumber].add(
            singleAmount
        );
        uint256 netLoss = serialNumberNetLoss[msg.sender][serialNumber];
        if (netLoss <= singleAmount) {
            serialNumberNetLoss[msg.sender][serialNumber] = 0;
        } else {
            serialNumberNetLoss[msg.sender][serialNumber] = netLoss.sub(
                singleAmount
            );
        }
        uint256 totalNetLoss = totalDepositsNetLoss[msg.sender];
        if (totalNetLoss <= singleAmount) {
            totalDepositsNetLoss[msg.sender] = 0;
        } else {
            totalDepositsNetLoss[msg.sender] = totalNetLoss.sub(singleAmount);
        }
    }

    function _accountWithdrawLp(
        uint256 principal,
        uint256 interest,
        uint256 price,
        uint256 timestamp
    ) internal {
        if (interest > 0) {
            (bool _next, address superior) = _sharerAwardInternal(interest);
            if (!_next) {
                _sharerAwardLevelOneInternal(superior, interest);
            }
        }
        emit WithdrawLP(
            msg.sender,
            principal,
            interest,
            ((principal.add(interest)) * price) / 1e18,
            timestamp
        );
    }

    function _compensationSnapshotInternal() internal {
        withdrawPause = true;
        depositsPause = true;
        (uint256 lpPrice, ) = lpPriceDex();
        compensationCheckPoints[compensationNonce] = CompensationCheckPoint(
            depositsSerialNumber - 1,
            _ethPriceDexInternal(),
            lpPrice,
            compensationValue[compensationNonce],
            compensationValue[compensationNonce],
            0
        );
        emit CompensationETH(
            block.timestamp,
            compensationNonce,
            depositsSerialNumber - 1
        );
        compensationNonce++;
    }

    function _shareLPInternal(
        uint8 recommendedLevel,
        address superior,
        uint256 value
    ) internal returns (address) {
        if (inviteRules[superior].rewardLevelMax >= recommendedLevel) {
            sharerIncomes[superior] = sharerIncomes[superior].add(value);
            emit SharerLP(msg.sender, superior, value, block.timestamp);
        }
        return invites[superior];
    }

    function _sharerAwardLevelOneInternal(
        address superior,
        uint256 interest
    ) internal {
        uint256 superiorValue = (interest * elevenToTwentyRate).div(
            rateMultiple
        );
        address superiorTwelve = _shareLPInternal(20, superior, superiorValue);
        if (address(0) == superiorTwelve) return;

        address superiorThirteen = _shareLPInternal(
            20,
            superiorTwelve,
            superiorValue
        );
        if (address(0) == superiorThirteen) return;

        address superiorFourteen = _shareLPInternal(
            20,
            superiorThirteen,
            superiorValue
        );
        if (address(0) == superiorFourteen) return;

        address superiorFifteen = _shareLPInternal(
            20,
            superiorFourteen,
            superiorValue
        );
        if (address(0) == superiorFifteen) return;

        address superiorSixteen = _shareLPInternal(
            20,
            superiorFifteen,
            superiorValue
        );
        if (address(0) == superiorSixteen) return;

        address superiorSeventeen = _shareLPInternal(
            20,
            superiorSixteen,
            superiorValue
        );
        if (address(0) == superiorSeventeen) return;

        address superiorEighteen = _shareLPInternal(
            20,
            superiorSeventeen,
            superiorValue
        );
        if (address(0) == superiorEighteen) return;

        address superiorNineteen = _shareLPInternal(
            20,
            superiorEighteen,
            superiorValue
        );
        if (address(0) == superiorNineteen) return;

        address superiorTwenty = _shareLPInternal(
            20,
            superiorNineteen,
            superiorValue
        );
        if (address(0) == superiorTwenty) return;

        _shareLPInternal(20, superiorTwenty, superiorValue);
    }

    function _sharerAwardInternal(
        uint256 interest
    ) internal returns (bool, address) {
        address superior = invites[msg.sender];
        if (address(0) == superior) return (true, superior);

        uint256 superiorValue = (interest * oneTwoTenRate).div(rateMultiple);
        address superiorTwo = _shareLPInternal(1, superior, superiorValue);
        if (address(0) == superiorTwo) return (true, superiorTwo);

        address superiorThree = _shareLPInternal(2, superiorTwo, superiorValue);
        if (address(0) == superiorThree) return (true, superiorThree);

        address superiorFour = _shareLPInternal(
            3,
            superiorThree,
            superiorValue
        );
        if (address(0) == superiorFour) return (true, superiorFour);

        address superiorFive = _shareLPInternal(4, superiorFour, superiorValue);
        if (address(0) == superiorFive) return (true, superiorFive);

        address superiorSix = _shareLPInternal(5, superiorFive, superiorValue);
        if (address(0) == superiorSix) return (true, superiorSix);

        address superiorSeven = _shareLPInternal(6, superiorSix, superiorValue);
        if (address(0) == superiorSeven) return (true, superiorSeven);

        address superiorEight = _shareLPInternal(
            7,
            superiorSeven,
            superiorValue
        );
        if (address(0) == superiorEight) return (true, superiorEight);

        address superiorNine = _shareLPInternal(
            8,
            superiorEight,
            superiorValue
        );
        if (address(0) == superiorNine) return (true, superiorNine);

        address superiorTen = _shareLPInternal(9, superiorNine, superiorValue);
        if (address(0) == superiorTen) return (true, superiorTen);

        address superiorEleven = _shareLPInternal(
            10,
            superiorTen,
            superiorValue
        );
        return (address(0) == superiorEleven, superiorEleven);
    }

    function getLP()
        public
        view
        returns (
            uint256 principal,
            uint256 interest,
            DepositsIncome[] memory depositsIncome
        )
    {
        uint256[] memory depositsSerialArrays = depositsSerials[msg.sender];
        uint256 depositsLen = depositsSerialArrays.length;
        uint256 timestamp = block.timestamp;
        depositsIncome = new DepositsIncome[](depositsLen);
        if (depositsLen > 0) {
            for (uint i = depositsLen - 1; i >= 0; i--) {
                DepositsCertificate memory certificat = depositsCertificates[
                    depositsSerialArrays[i]
                ];
                (
                    uint256 singlePrincipal,
                    uint256 singleInterest
                ) = _singleDepositsLpIncomeInternal(certificat, timestamp);
                DepositsIncome memory income = DepositsIncome(
                    certificat.serialNumber,
                    singlePrincipal,
                    singleInterest
                );
                depositsIncome[i] = income;
                principal += singlePrincipal;
                interest += singleInterest;
                if (i == 0) break;
            }
        }
    }

    function dayDiff(uint256 diff) internal pure returns (uint256, uint256) {
        return (diff / depositsSilentPeriod, diff % depositsSilentPeriod);
    }

    function _singleDepositsLpIncomeInternal(
        DepositsCertificate memory certificat,
        uint256 timestamp
    ) internal view returns (uint256 principal, uint256 interest) {
        if (certificat.valid && timestamp > certificat.startTimestamp) {
            timestamp = timestamp > certificat.endTimestamp
                ? certificat.endTimestamp
                : timestamp;
            uint256 diff = timestamp - certificat.startTimestamp;
            (uint256 d, uint256 s) = dayDiff(diff);
            uint256 oldDiffPrincipal;
            uint256 oldDiffInterest;
            uint256 nowPrincipal;
            uint256 nowInterest;
            if (d > 0) {
                oldDiffPrincipal = certificat.principal * d;
                for (uint256 j = 0; j < d; j++) {
                    oldDiffInterest += (((certificat.value -
                        (certificat.principal * j)) * yieldRate) /
                        rateMultiple);
                }
                nowPrincipal =
                    (certificat.principal * s) /
                    depositsSilentPeriod;
                nowInterest =
                    ((((certificat.value - (certificat.principal * d)) *
                        yieldRate) / rateMultiple) * s) /
                    depositsSilentPeriod;
            } else {
                nowPrincipal =
                    (certificat.principal * s) /
                    depositsSilentPeriod;
                nowInterest =
                    (((certificat.value * yieldRate) / rateMultiple) * s) /
                    depositsSilentPeriod;
            }
            principal +=
                oldDiffPrincipal +
                nowPrincipal -
                serialNumberWithdrawPrincipal[certificat.creater][
                    certificat.serialNumber
                ];
            interest +=
                oldDiffInterest +
                nowInterest -
                serialNumberWithdrawInterest[certificat.creater][
                    certificat.serialNumber
                ];
        }
    }

    function getShareLP() external view returns (uint256) {
        return _shareLPInternal();
    }

    function _shareLPInternal() internal view returns (uint256 value) {
        uint256 sharerIncome = sharerIncomes[msg.sender];
        value = (sharerIncome > 0)
            ? sharerIncome.sub(extractedSharerIncomes[msg.sender])
            : 0;
    }

    function withdrawShareLP() external nonReentrant {
        require(!withdrawPause);

        uint256 actual = _shareLPInternal();
        require(actual > 0);

        uint256 totalLpBalance = carEthPair.balanceOf(address(this));
        require(totalLpBalance > 0);

        if (totalLpBalance > actual) {
            _withdrawLPTransferActialInternal(actual);
        } else {
            _withdrawLPTransferActialInternal(totalLpBalance);
            _compensationSnapshotInternal();
        }
    }

    function _withdrawLPTransferActialInternal(uint256 actual) internal {
        carEthPair.transfer(msg.sender, actual);
        extractedSharerIncomes[msg.sender] = extractedSharerIncomes[msg.sender]
            .add(actual);
        (uint256 price, ) = lpPriceDex();
        uint256 amount = (actual * price) / 1e18;

        uint256 totalNetLoss = totalDepositsNetLoss[msg.sender];
        if (totalNetLoss <= amount) {
            totalDepositsNetLoss[msg.sender] = 0;
        } else {
            totalDepositsNetLoss[msg.sender] = totalNetLoss.sub(amount);
        }
        emit WithdrawShare(msg.sender, actual, amount, block.timestamp);
    }

    function withdrawAll() external {
        _withdrawLPInternal();
    }

    function lpPriceDex() public view returns (uint256, uint256) {
        (uint256 reserve0, uint256 reserve1) = _getReserves(
            address(car),
            weth,
            carEthPair
        );
        (uint256 ethPrice, uint256 tokenPrice) = tokenPriceDex(
            reserve0,
            reserve1
        );
        uint256 lpTotalPrice = (reserve0 * tokenPrice) /
            1e18 +
            (reserve1 * ethPrice) /
            1e18;
        return ((lpTotalPrice * 1e18) / carEthPair.totalSupply(), tokenPrice);
    }

    function tokenPriceDex(
        uint256 reserve0,
        uint256 reserve1
    ) internal view returns (uint256 ethPrice, uint256 tokenPrice) {
        uint256 amount = (reserve1 * (1e18)) / reserve0;
        ethPrice = _ethPriceDexInternal();
        tokenPrice = ((amount * ethPrice)) / (1e18);
    }

    function acceptCompensationETH(uint256 singleCompensationMax) public {
        require(depositsPause && withdrawPause);

        CompensationCheckPoint
            storage compensationCheckPoint = compensationCheckPoints[
                compensationNonce - 1
            ];
        uint256 serialNumberItem = compensationCheckPoint.serialNumber;
        uint256 compensationMax = serialNumberItem > singleCompensationMax
            ? serialNumberItem - singleCompensationMax
            : 0;
        for (
            uint256 index = serialNumberItem;
            index > compensationMax;
            index--
        ) {
            DepositsCertificate
                storage depositsCertificate = depositsCertificates[index];
            if (!depositsCertificate.valid) continue;

            if (
                sharerIncomes[depositsCertificate.creater] !=
                extractedSharerIncomes[depositsCertificate.creater]
            ) {
                sharerIncomes[
                    depositsCertificate.creater
                ] = extractedSharerIncomes[depositsCertificate.creater];
            }
            uint256 totalNetLoss = totalDepositsNetLoss[
                depositsCertificate.creater
            ];
            if (totalNetLoss == 0) {
                depositsCertificate.valid = false;
                emit CertificateEnd(depositsCertificate.serialNumber);
                continue;
            }

            uint256 currentETHValue = compensationCheckPoint.remainingValue;
            if (currentETHValue == 0) {
                uint256 newPrincipal = (serialNumberNetLoss[
                    depositsCertificate.creater
                ][depositsCertificate.serialNumber] * 1e18) /
                    depositsCertificate.price;
                depositsCertificate.value = newPrincipal;
                depositsCertificate.amount =
                    (newPrincipal * depositsCertificate.price) /
                    1e18;
                depositsCertificate.startTimestamp = block.timestamp;
                depositsCertificate.principal =
                    (newPrincipal * dayPrincipalRate) /
                    rateMultiple;
                depositsCertificate.endTimestamp =
                    block.timestamp +
                    depositsIncomeCycle;
                _updatePrincipalInternal(
                    depositsCertificate.creater,
                    depositsCertificate.serialNumber,
                    newPrincipal,
                    depositsCertificate.amount
                );
            } else {
                uint256 netLoss = serialNumberNetLoss[
                    depositsCertificate.creater
                ][depositsCertificate.serialNumber];
                uint256 currentETHAmount = (currentETHValue *
                    compensationCheckPoint.ethPrice) / 1e18;
                if (netLoss == 0) {
                    depositsCertificate.valid = false;
                    emit CertificateEnd(depositsCertificate.serialNumber);
                } else {
                    if (netLoss <= totalNetLoss) {
                        if (currentETHAmount >= netLoss) {
                            depositsCertificate.valid = false;
                            uint256 compensationETHValue = (netLoss * 1e18) /
                                compensationCheckPoint.ethPrice;
                            _compensationETHAdequateInternal(
                                depositsCertificate.creater,
                                depositsCertificate.serialNumber,
                                0,
                                totalNetLoss - netLoss,
                                compensationETHValue
                            );
                            compensationCheckPoint.remainingValue =
                                currentETHValue -
                                compensationETHValue;
                            compensationCheckPoint.actuallyPaid =
                                compensationCheckPoint.actuallyPaid +
                                compensationETHValue;
                            emit CertificateEnd(
                                depositsCertificate.serialNumber
                            );
                        } else {
                            _compensationETHPartInternal(
                                depositsCertificate,
                                netLoss,
                                currentETHAmount,
                                currentETHValue
                            );
                            compensationCheckPoint.remainingValue = 0;
                            compensationCheckPoint.actuallyPaid =
                                compensationCheckPoint.actuallyPaid +
                                currentETHValue;
                        }
                    } else {
                        if (currentETHAmount >= totalNetLoss) {
                            depositsCertificate.valid = false;
                            uint256 compensationETHValue = (totalNetLoss *
                                1e18) / compensationCheckPoint.ethPrice;
                            _compensationETHAdequateInternal(
                                depositsCertificate.creater,
                                depositsCertificate.serialNumber,
                                0,
                                0,
                                compensationETHValue
                            );
                            compensationCheckPoint.remainingValue =
                                currentETHValue -
                                compensationETHValue;
                            compensationCheckPoint.actuallyPaid =
                                compensationCheckPoint.actuallyPaid +
                                compensationETHValue;
                            emit CertificateEnd(
                                depositsCertificate.serialNumber
                            );
                        } else {
                            _compensationETHPartInternal(
                                depositsCertificate,
                                totalNetLoss,
                                currentETHAmount,
                                currentETHValue
                            );
                            compensationCheckPoint.remainingValue = 0;
                            compensationCheckPoint.actuallyPaid =
                                compensationCheckPoint.actuallyPaid +
                                currentETHValue;
                        }
                    }
                }
            }
        }
        compensationCheckPoint.serialNumber = compensationMax;
        if (compensationCheckPoint.serialNumber == 0) {
            depositsPause = false;
            withdrawPause = false;
            if (compensationCheckPoint.remainingValue > 0) {
                compensationValue[compensationNonce] =
                    compensationValue[compensationNonce] +
                    compensationCheckPoint.remainingValue;
            }
        }
    }

    function _updatePrincipalInternal(
        address creater,
        uint256 serialNumber,
        uint256 newPrincipal,
        uint256 amount
    ) internal {
        serialNumberWithdrawPrincipal[creater][serialNumber] = 0;
        serialNumberWithdrawInterest[creater][serialNumber] = 0;
        emit CompensationDeposits(serialNumber, newPrincipal, amount);
    }

    function _compensationETHAdequateInternal(
        address account,
        uint256 serialNumber,
        uint256 netLoss,
        uint256 totalNetLoss,
        uint256 compensationETHValue
    ) internal {
        serialNumberNetLoss[account][serialNumber] = netLoss;
        totalDepositsNetLoss[account] = totalNetLoss;
        _compensationETHInternal(serialNumber, account, compensationETHValue);
    }

    function _compensationETHPartInternal(
        DepositsCertificate storage depositsCertificate,
        uint256 standardETHAmount,
        uint256 compensationETHAmount,
        uint256 compensationETHValue
    ) internal {
        serialNumberNetLoss[depositsCertificate.creater][
            depositsCertificate.serialNumber
        ] = standardETHAmount - compensationETHAmount;
        totalDepositsNetLoss[depositsCertificate.creater] =
            totalDepositsNetLoss[depositsCertificate.creater] -
            compensationETHAmount;
        _compensationETHInternal(
            depositsCertificate.serialNumber,
            depositsCertificate.creater,
            compensationETHValue
        );
        uint256 newPrincipal = (serialNumberNetLoss[
            depositsCertificate.creater
        ][depositsCertificate.serialNumber] * 1e18) / depositsCertificate.price;
        depositsCertificate.value = newPrincipal;
        depositsCertificate.amount =
            (newPrincipal * depositsCertificate.price) /
            1e18;
        depositsCertificate.startTimestamp = block.timestamp;
        depositsCertificate.principal =
            (newPrincipal * dayPrincipalRate) /
            rateMultiple;
        depositsCertificate.endTimestamp =
            block.timestamp +
            depositsIncomeCycle;
        serialNumberNetLoss[depositsCertificate.creater][
            depositsCertificate.serialNumber
        ] = newPrincipal;
        _updatePrincipalInternal(
            depositsCertificate.creater,
            depositsCertificate.serialNumber,
            newPrincipal,
            depositsCertificate.amount
        );
    }

    function _compensationETHInternal(
        uint256 serialNumber,
        address account,
        uint256 value
    ) internal {
        CompensationETHCertificate
            memory compensationETHCertificate = CompensationETHCertificate({
                serialNumber: serialNumber,
                creater: account,
                value: value,
                startTimestamp: block.timestamp,
                endTimestamp: block.timestamp + ethCompensationCycle
            });
        compensationEthCertificates[serialNumber] = compensationETHCertificate;
        uint256[] storage compensationEthArrays = compensationEths[account];
        compensationEthArrays.push(serialNumber);
        actualCompensationEthValue = actualCompensationEthValue + value;
        totalAccountCompensation[account] = totalAccountCompensation[account]
            .add(value);
    }
}

interface IUniswapV3Pool {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
}

interface IUniswapV3Factory {
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);
}
