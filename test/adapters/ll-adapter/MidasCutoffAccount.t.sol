// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {CutoffMidasAccount} from "../../../src/contracts/adapters/ll-adapter/MidasAccount.sol";
import {MidasOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/MidasOracle.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {ICoWSwapSettlement} from "../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MidasCutoffAccountTest is Test {
    uint48 internal constant COOLDOWN = 6 days;
    uint48 internal constant PRE_CUTOFF_WINDOW = 3 days;
    uint48 internal constant JULY_20_2026 = 1_784_505_600;
    uint48 internal constant JULY_23_2026 = 1_784_764_800;
    uint48 internal constant JULY_26_2026 = 1_785_024_000;
    uint48 internal constant JULY_26_2026_PLUS_ONE = 1_785_024_001;
    uint48 internal constant AUGUST_23_2026 = 1_787_443_200;
    uint48 internal constant AUGUST_26_2026 = 1_787_702_400;

    address internal adapter = makeAddr("adapter");
    address internal cowSettlement = makeAddr("cowSettlement");
    address internal cowRelayer = makeAddr("cowRelayer");

    MockERC20 internal usdc;
    MockERC20 internal mGlobal;
    MockAggregator internal aggregator;
    MockMidasDataFeed internal dataFeed;
    MockMidasRedemptionVault internal redemptionVault;
    CutoffMidasAccount internal account;

    uint48 internal CUTOFF;

    function setUp() public {
        vm.warp(JULY_23_2026);
        CUTOFF = JULY_26_2026;

        usdc = new MockERC20("USD Coin", "USDC", 6);
        mGlobal = new MockERC20("Midas Global", "mGLOBAL", 18);
        aggregator = new MockAggregator();
        aggregator.setRound(0.93e8, vm.getBlockTimestamp());
        dataFeed = new MockMidasDataFeed(address(aggregator));
        redemptionVault = new MockMidasRedemptionVault(address(mGlobal), address(dataFeed));
        redemptionVault.setTokenConfig(address(usdc), makeAddr("usdcDataFeed"));

        MigratablesFactory factory = new MigratablesFactory(address(this));
        vm.mockCall(cowSettlement, abi.encodeCall(ICoWSwapSettlement.vaultRelayer, ()), abi.encode(cowRelayer));
        CutoffMidasAccount implementation = new CutoffMidasAccount(
            address(new MidasOracle(1, type(uint256).max, address(dataFeed))),
            address(factory),
            COOLDOWN,
            CUTOFF,
            address(mGlobal),
            PRE_CUTOFF_WINDOW,
            address(usdc),
            address(redemptionVault),
            cowSettlement
        );
        factory.whitelist(address(implementation));
        account = CutoffMidasAccount(
            factory.create(1, address(this), abi.encode(address(new MockVault(address(usdc))), adapter))
        );
    }

    function testRequestRegistersBucketAndValuesLive() public {
        mGlobal.mint(address(account), 100e18);
        account.sync();

        assertEq(account.requestIds(0), 0);
        assertEq(account.requestToBucket(0), 0);
        assertEq(account.totalAssets(), 93e6);

        aggregator.setRound(0.95e8, vm.getBlockTimestamp());
        assertEq(account.totalAssets(), 95e6);
    }

    function testMonthlyBucketConversionUsesTwentySixthCutoff() public view {
        uint48 julyBucketIndex = account.timestampToBucket(JULY_20_2026);

        assertEq(julyBucketIndex, 0);
        assertEq(account.bucketToTimestamp(julyBucketIndex), 0);
        assertEq(account.timestampToBucket(JULY_26_2026 - 1), julyBucketIndex);
        assertEq(account.timestampToBucket(JULY_26_2026), 1);
        assertEq(account.timestampToBucket(JULY_26_2026_PLUS_ONE), 1);
        assertEq(account.bucketToTimestamp(account.timestampToBucket(JULY_26_2026_PLUS_ONE)), JULY_26_2026);
        assertEq(account.bucketToTimestamp(2), AUGUST_26_2026);
    }

    function testDoesNotRequestBeforePreCutoffWindow() public {
        address caller = makeAddr("caller");

        vm.warp(JULY_20_2026);
        mGlobal.mint(address(account), 100e18);

        vm.prank(caller);
        account.sync();

        vm.expectRevert();
        account.requestIds(0);
        assertEq(mGlobal.balanceOf(address(account)), 100e18);

        vm.warp(JULY_23_2026);
        vm.prank(caller);
        account.sync();

        assertEq(account.requestIds(0), 0);
        assertEq(account.requestToBucket(0), 0);
    }

    function testUsesLastOracleReportBeforeNextBucket() public {
        mGlobal.mint(address(account), 100e18);
        account.sync();

        aggregator.setRound(2, 0.94e8, uint256(CUTOFF) - 1);
        aggregator.setRound(3, 0.97e8, uint256(CUTOFF) + 1);
        assertEq(account.totalAssets(), 94e6);
    }

    function testFulfilledRequestNotDoubleCountedBeforeSync() public {
        mGlobal.mint(address(account), 100e18);
        account.sync();

        redemptionVault.process(0);
        usdc.mint(address(account), 93e6);
        assertEq(account.totalAssets(), 93e6);

        account.sync();

        vm.expectRevert();
        account.requestIds(0);
        assertEq(account.totalAssets(), 93e6);
    }

    function testSecondRequestJoinsNextCohort() public {
        mGlobal.mint(address(account), 100e18);
        account.sync();

        // a request submitted in the next pre-cutoff window joins the next monthly bucket
        vm.warp(AUGUST_23_2026);
        mGlobal.mint(address(account), 50e18);
        account.sync();

        assertEq(account.requestIds(1), 1);
        assertEq(account.requestToBucket(1), 1);
        assertEq(account.bucketToTimestamp(account.requestToBucket(1)), JULY_26_2026);
    }

    function testCurrentBucketReturnsCurrentMonthlyBucket() public view {
        assertEq(account.bucketToTimestamp(account.currentBucket()), 0);
        assertEq(account.nextCutoff(), CUTOFF);
    }

    function testRegistersVaultStoredNetAmount() public {
        redemptionVault.setFeeBps(100); // 1% redemption fee
        mGlobal.mint(address(account), 100e18);
        account.sync();

        // the vault stores the net-of-fee amount, which defines the payout and thus the cohort value
        (,,, uint256 amountMToken,,) = redemptionVault.redeemRequests(0);
        assertEq(amountMToken, 99e18);
        assertEq(account.requestToBucket(0), 0);
        assertEq(account.totalAssets(), 92.07e6);
    }

    function testCanceledRequestReturnsTokensAndClearsCohort() public {
        mGlobal.mint(address(account), 100e18);
        account.sync();

        // Midas cancels the request and returns the token-to-redeem to the account
        redemptionVault.cancelRequest(0);
        assertEq(mGlobal.balanceOf(address(account)), 100e18);

        // sync prunes the canceled cohort and re-registers the returned tokens under a new request
        account.sync();

        assertEq(mGlobal.balanceOf(address(account)), 0);
        assertEq(account.requestIds(0), 1);
        assertEq(account.requestToBucket(1), 0);

        // no value lost or double-counted: the re-submitted request is valued back at 93e6
        assertEq(account.totalAssets(), 93e6);
    }
}

contract MockVault {
    address public immutable asset;

    constructor(address asset_) {
        asset = asset_;
    }
}

contract MockERC20 is ERC20 {
    uint8 internal immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockAggregator {
    uint8 public constant decimals = 8;

    int256 public answer;
    uint80 public latestRoundId;
    uint256 public updatedAt;

    struct Round {
        int256 answer;
        uint256 updatedAt;
    }

    mapping(uint80 roundId => Round round) internal _rounds;

    function setRound(int256 answer_, uint256 updatedAt_) public {
        setRound(latestRoundId + 1, answer_, updatedAt_);
    }

    function setRound(uint80 roundId, int256 answer_, uint256 updatedAt_) public {
        answer = answer_;
        updatedAt = updatedAt_;
        latestRoundId = roundId;
        _rounds[roundId] = Round({answer: answer_, updatedAt: updatedAt_});
    }

    function latestRoundData()
        public
        view
        returns (uint80 roundId, int256 answer_, uint256 startedAt, uint256 updatedAt_, uint80 answeredInRound)
    {
        return getRoundData(latestRoundId);
    }

    function getRoundData(uint80 roundId)
        public
        view
        returns (uint80, int256 answer_, uint256 startedAt, uint256 updatedAt_, uint80 answeredInRound)
    {
        Round memory round = _rounds[roundId];
        return (roundId, round.answer, round.updatedAt, round.updatedAt, roundId);
    }
}

contract MockMidasDataFeed {
    address public aggregator;

    constructor(address aggregator_) {
        aggregator = aggregator_;
    }

    function getDataInBase18() public view returns (uint256) {
        return uint256(MockAggregator(aggregator).answer()) * 1e10; // 8 -> 18 decimals
    }
}

contract MockMidasRedemptionVault {
    uint8 internal constant PENDING = 0;
    uint8 internal constant PROCESSED = 1;
    uint8 internal constant CANCELED = 2;

    struct Request {
        address sender;
        address tokenOut;
        uint8 status;
        uint256 amountMToken;
        uint256 mTokenRate;
        uint256 tokenOutRate;
    }

    struct TokenConfig {
        address dataFeed;
        uint256 fee;
        uint256 allowance;
        bool stable;
    }

    address public immutable tokenToRedeem;
    address public immutable mTokenDataFeed;
    uint256 public currentRequestId;
    uint256 public feeBps;

    mapping(address token => TokenConfig config) internal _tokensConfig;
    mapping(uint256 requestId => Request request) internal _requests;

    constructor(address tokenToRedeem_, address mTokenDataFeed_) {
        tokenToRedeem = tokenToRedeem_;
        mTokenDataFeed = mTokenDataFeed_;
    }

    function setTokenConfig(address token, address dataFeed) public {
        _tokensConfig[token] = TokenConfig({dataFeed: dataFeed, fee: 0, allowance: 0, stable: true});
    }

    function setFeeBps(uint256 feeBps_) public {
        feeBps = feeBps_;
    }

    function tokensConfig(address token)
        public
        view
        returns (address dataFeed, uint256 fee, uint256 allowance, bool stable)
    {
        TokenConfig memory config = _tokensConfig[token];
        return (config.dataFeed, config.fee, config.allowance, config.stable);
    }

    function redeemRequest(address tokenOut, uint256 amountMTokenIn) public returns (uint256 requestId) {
        IERC20(tokenToRedeem).transferFrom(msg.sender, address(this), amountMTokenIn);
        requestId = currentRequestId++;
        _requests[requestId] = Request({
            sender: msg.sender,
            tokenOut: tokenOut,
            status: PENDING,
            amountMToken: amountMTokenIn - (amountMTokenIn * feeBps) / 10_000,
            mTokenRate: MockMidasDataFeed(mTokenDataFeed).getDataInBase18(),
            tokenOutRate: 1e18
        });
    }

    function process(uint256 requestId) public {
        _requests[requestId].status = PROCESSED;
    }

    function cancelRequest(uint256 requestId) public {
        Request storage request = _requests[requestId];
        request.status = CANCELED;
        IERC20(tokenToRedeem).transfer(request.sender, request.amountMToken);
    }

    function redeemRequests(uint256 requestId)
        public
        view
        returns (
            address sender,
            address tokenOut,
            uint8 status,
            uint256 amountMToken,
            uint256 mTokenRate,
            uint256 tokenOutRate
        )
    {
        Request storage request = _requests[requestId];
        return (
            request.sender,
            request.tokenOut,
            request.status,
            request.amountMToken,
            request.mTokenRate,
            request.tokenOutRate
        );
    }
}
