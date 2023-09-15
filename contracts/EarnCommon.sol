// SPDX-License-Identifier:  Unlicense
pragma solidity ^0.8.17;

contract EarnCommon {
    uint256 internal depositsStart;
    bool public depositsPause = false;
    bool public withdrawPause = false;

    uint256 public constant peakRate = 3_000;
    uint256 public lpHistoricalPeak;
    uint256 public earnLpBalances;
    uint256 internal constant initDexToken = 1_000_000e18;
    uint256 internal constant initDexUsdtPrice = 325_000_000_000;
    uint8 internal constant depositsMax = 30;
    uint256 internal constant slippageMin = 1000;
    uint256 internal constant slippageMax = 1_000_000;
    uint256 internal constant dayPrincipalRate = 50;
    uint256 internal constant yieldRate = 150;
    uint256 internal constant oneTwoTenRate = 1_000;
    uint256 internal constant elevenToTwentyRate = 300;
    uint256 internal constant rateMultiple = 10_000;

    uint256 internal constant earnPeriod = 1 days;
    uint256 internal constant depositsSilentPeriod = 1 days;
    uint256 internal constant depositsIncomeCycle = 200 days;
    uint256 internal constant ethCompensationCycle = 30 days;

    address internal mintContract;
    address internal weth;

    mapping(address => bool) internal itemDeposits;
    mapping(address => uint256[]) internal depositsSerials;
    mapping(address => mapping(uint256 => uint256))
        internal serialNumberNetLoss;
    mapping(address => mapping(uint256 => uint256))
        internal serialNumberWithdrawPrincipal;
    mapping(address => mapping(uint256 => uint256))
        internal serialNumberWithdrawInterest;
    mapping(address => mapping(uint256 => uint256))
        internal serialNumberWithdrawAmount;
    mapping(address => uint256) internal totalDepositsNetLoss;
    mapping(address => uint256[]) internal compensationEths;
    mapping(address => mapping(uint256 => bool)) internal compensationEthFlags;

    uint256 public depositsSerialNumber = 1;
    mapping(address => bool) public validInvites;
    mapping(address => address) public invites;
    mapping(address => uint256) public accountDeposits;
    mapping(address => uint256) public accountDepositsAmount;
    mapping(address => uint256) public sharerIncomes;
    mapping(address => uint256) public extractedSharerIncomes;
    mapping(address => uint256) public extractedSharerIncomesAmount;
    mapping(uint256 => DepositsCertificate) public depositsCertificates;
    uint256 public mintPoolValueEth;
    uint256 public compensationNonce = 1;
    mapping(uint256 => uint256) public compensationValue;
    mapping(uint256 => CompensationCheckPoint) public compensationCheckPoints;
    mapping(uint256 => CompensationETHCertificate)
        public compensationEthCertificates;
    mapping(address => uint256) public totalAccountCompensation;
    mapping(address => uint256) public toWithdrawTotalCompensations;
    mapping(address => mapping(uint256 => uint256))
        public toWithdrawCompensations;

    mapping(address => mapping(address => bool)) internal validDirectPushFlag;
    mapping(address => mapping(uint8 => bool))
        internal validDirectPushLevelFlag;
    mapping(address => uint256) public inviteValid;
    mapping(address => InviteRule) public inviteRules;
    struct DepositsIncome {
        uint256 serialNumber;
        uint256 principal;
        uint256 interest;
    }
    struct DepositsCertificate {
        uint256 serialNumber;
        address creater;
        uint256 price;
        uint256 value;
        uint256 amount;
        uint256 principal;
        uint256 startTimestamp;
        uint256 endTimestamp;
        bool valid;
    }
    struct CompensationCheckPoint {
        uint256 serialNumber;
        uint256 ethPrice;
        uint256 lpPrice;
        uint256 totalVale;
        uint256 remainingValue;
        uint256 actuallyPaid;
    }
    struct CompensationETHCertificate {
        uint256 serialNumber;
        address creater;
        uint256 value;
        uint256 remaining;
        uint256 startTimestamp;
        uint256 endTimestamp;
    }
    struct InviteRule {
        uint8 inviteLevel;
        uint8 rewardLevelMax;
        uint256 validEleven;
        uint256 validTen;
        uint256 validNine;
        uint256 validEight;
        uint256 validSeven;
        uint256 validSix;
        uint256 validFive;
        uint256 validFour;
        uint256 validThree;
        uint256 validTwo;
        uint256 subordinateLevelTwo;
    }

    uint256 internal constant inviteValidMinAmount = 100_000_000;
    uint256 internal constant inviteValidTwoAmount = 200_000_000;
    uint256 internal constant inviteValidThreeAmount = 300_000_000;
    uint256 internal constant inviteValidFourAmount = 400_000_000;
    uint256 internal constant inviteValidFiveAmount = 500_000_000;
    uint256 internal constant inviteValidSixAmount = 600_000_000;
    uint256 internal constant inviteValidSevenAmount = 700_000_000;
    uint256 internal constant inviteValidEightAmount = 800_000_000;
    uint256 internal constant inviteValidNineAmount = 900_000_000;
    uint256 internal constant inviteValidTenAmount = 1_000_000_000;

    uint8 internal constant levelTwelve = 12;
    uint8 internal constant levelEleven = 11;
    uint8 internal constant levelTen = 10;
    uint8 internal constant levelNine = 9;
    uint8 internal constant levelEight = 8;
    uint8 internal constant levelSeven = 7;
    uint8 internal constant levelSix = 6;
    uint8 internal constant levelFive = 5;
    uint8 internal constant levelFour = 4;
    uint8 internal constant levelThree = 3;
    uint8 internal constant levelTwo = 2;
    uint8 internal constant levelOne = 1;

    uint8 internal constant rewardLevelOne = 1;
    uint8 internal constant rewardLevelTwo = 2;
    uint8 internal constant rewardLevelThree = 3;
    uint8 internal constant rewardLevelFour = 4;
    uint8 internal constant rewardLevelFive = 5;
    uint8 internal constant rewardLevelSix = 6;
    uint8 internal constant rewardLevelSeven = 7;
    uint8 internal constant rewardLevelEight = 8;
    uint8 internal constant rewardLevelNine = 9;
    uint8 internal constant rewardLevelTen = 10;
    uint8 internal constant rewardLevelMax = 20;

    event InitDexPool(
        uint256 amountToken,
        uint256 amountETH,
        uint256 liquidity,
        uint256 timestamp
    );
    event Invite(address account, address invite, uint256 timestamp);
    event Deposits(
        uint256 serialNumber,
        address account,
        address item,
        uint256 value,
        uint256 lpValue,
        uint256 lpAmount,
        uint256 timestamp
    );
    event LevelChange(
        address account,
        uint8 inviteLevel,
        uint8 rewardLevelMax,
        uint256 timestamp
    );
    event DirectPushEffective(
        address account,
        uint256 number,
        uint256 timestamp
    );
    event CompensationETH(
        uint256 timestamp,
        uint256 compensationNonce,
        uint256 serialNumber
    );
    event WithdrawLP(
        address account,
        uint256 principal,
        uint256 interest,
        uint256 amount,
        uint256 timestamp
    );
    event CertificateWithdraw(
        uint256 serialNumber,
        uint256 principal,
        uint256 interest,
        uint256 amount,
        uint256 timestamp
    );
    event SharerLP(
        address account,
        address sharer,
        uint256 value,
        uint256 timestamp
    );
    event WithdrawETH(
        address account,
        uint256 value,
        uint256 amount,
        uint256 timestamp
    );
    event WithdrawShare(
        address account,
        uint256 value,
        uint256 amount,
        uint256 timestamp
    );
    event CompensationDeposits(
        uint256 serialNumber,
        uint256 principal,
        uint256 amount
    );
    event CertificateEnd(uint256 serialNumber);
    event AddLiquidity(address account, uint256 liquidity, uint256 timestamp);
}
