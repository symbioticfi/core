// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {MidasCutoffAccount} from "../../../src/contracts/adapters/ll-adapter/MidasAccount.sol";
import {MidasOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/MidasOracle.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MidasCutoffAccountTest is Test {
    uint48 internal constant COOLDOWN = 6 days;
    uint48 internal constant PERIOD = 30 days;
    uint48 internal constant VALUATION_DELAY = 5 days;
    uint48 internal constant SETTLEMENT_DURATION = 45 days;

    address internal adapter = makeAddr("adapter");
    address internal cowSettlement = makeAddr("cowSettlement");
    address internal cowRelayer = makeAddr("cowRelayer");

    MockERC20 internal usdc;
    MockERC20 internal mGlobal;
    MockAggregator internal aggregator;
    MockMidasDataFeed internal dataFeed;
    MockMidasRedemptionVault internal redemptionVault;
    MidasCutoffAccount internal account;

    uint48 internal CUTOFF;

    function setUp() public {
        CUTOFF = uint48(vm.getBlockTimestamp()) + 10 days;

        usdc = new MockERC20("USD Coin", "USDC", 6);
        mGlobal = new MockERC20("Midas Global", "mGLOBAL", 18);
        aggregator = new MockAggregator();
        aggregator.setRound(0.93e8, vm.getBlockTimestamp());
        dataFeed = new MockMidasDataFeed(address(aggregator));
        redemptionVault = new MockMidasRedemptionVault(address(mGlobal), address(dataFeed));
        redemptionVault.setTokenConfig(address(usdc), makeAddr("usdcDataFeed"));

        MigratablesFactory factory = new MigratablesFactory(address(this));
        vm.mockCall(cowSettlement, abi.encodeWithSignature("vaultRelayer()"), abi.encode(cowRelayer));
        MidasCutoffAccount implementation = new MidasCutoffAccount(
            address(new MidasOracle(address(dataFeed))),
            address(factory),
            COOLDOWN,
            address(mGlobal),
            address(usdc),
            address(redemptionVault),
            CUTOFF,
            PERIOD,
            VALUATION_DELAY,
            SETTLEMENT_DURATION,
            cowSettlement
        );
        factory.whitelist(address(implementation));
        account = MidasCutoffAccount(
            factory.create(1, address(this), abi.encode(address(new MockVault(address(usdc))), adapter))
        );
    }

    function testRequestRegistersCohortAndValuesLive() public {
        mGlobal.mint(address(account), 100e18);
        account.sync();

        assertEq(account.requestIds(0), 0);
        (uint128 amount, uint128 frozenRate, uint48 cohortCutoff) = account.pendingCohorts(0);
        assertEq(amount, 100e18);
        assertEq(frozenRate, 0);
        assertEq(cohortCutoff, CUTOFF);
        assertEq(account.totalAssets(), 93e6);

        // pending value tracks the live oracle until the cohort rate freezes
        aggregator.setRound(0.95e8, vm.getBlockTimestamp());
        assertEq(account.totalAssets(), 95e6);
    }

    function testFreezesAtFirstPrintAfterPricingDate() public {
        mGlobal.mint(address(account), 100e18);
        account.sync();

        uint256 pricingTime = uint256(CUTOFF) + VALUATION_DELAY;

        // a print from before the pricing date cannot freeze the cohort: it stays live
        vm.warp(pricingTime + 1);
        account.sync();
        (, uint128 frozenRate,) = account.pendingCohorts(0);
        assertEq(frozenRate, 0);
        aggregator.setRound(0.9e8, pricingTime - 1);
        assertEq(account.totalAssets(), 90e6);

        // the first print at/after the pricing date freezes the cohort rate on the next sync
        vm.warp(pricingTime + 2);
        aggregator.setRound(0.94e8, pricingTime + 2);
        account.sync();
        (, frozenRate,) = account.pendingCohorts(0);
        assertEq(frozenRate, 0.94e18);

        // later prints no longer move the cohort value
        aggregator.setRound(1e8, vm.getBlockTimestamp());
        assertEq(account.totalAssets(), 94e6);
    }

    function testWriteOffAndLateFulfillment() public {
        mGlobal.mint(address(account), 100e18);
        account.sync();

        // unsettled past the settlement duration: the pending value is written off
        vm.warp(uint256(CUTOFF) + VALUATION_DELAY + SETTLEMENT_DURATION);
        assertEq(account.totalAssets(), 0);

        // a late fulfillment still clears the request and realizes the received assets
        redemptionVault.process(0);
        usdc.mint(address(account), 93e6);
        account.sync();

        (uint128 amount,,) = account.pendingCohorts(0);
        assertEq(amount, 0);
        vm.expectRevert();
        account.requestIds(0);
        assertEq(account.totalAssets(), 93e6);
    }

    function testSecondRequestJoinsNextCohort() public {
        mGlobal.mint(address(account), 100e18);
        account.sync();

        // a request submitted after the cutoff joins the next cohort (owner sync bypasses the cooldown)
        vm.warp(uint256(CUTOFF) + 1);
        mGlobal.mint(address(account), 50e18);
        account.sync();

        assertEq(account.requestIds(1), 1);
        (uint128 amount,, uint48 cohortCutoff) = account.pendingCohorts(1);
        assertEq(amount, 50e18);
        assertEq(cohortCutoff, CUTOFF + PERIOD);
        assertEq(account.cutoff(), CUTOFF + PERIOD);
    }

    function testSetCutoffScheduleOnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        account.setCutoffSchedule(CUTOFF + 7 days, 91 days);

        account.setCutoffSchedule(CUTOFF + 7 days, 91 days);
        assertEq(account.cutoff(), CUTOFF + 7 days);
        assertEq(account.cutoffPeriod(), 91 days);
    }

    function testCanceledRequestReturnsTokensAndClearsCohort() public {
        mGlobal.mint(address(account), 100e18);
        account.sync();

        // Midas cancels the request and returns the token-to-redeem to the account
        redemptionVault.cancelRequest(0);
        assertEq(mGlobal.balanceOf(address(account)), 100e18);

        // sync prunes the canceled cohort and re-registers the returned tokens under a new request
        account.sync();

        (uint128 amount,,) = account.pendingCohorts(0);
        assertEq(amount, 0);
        assertEq(mGlobal.balanceOf(address(account)), 0);
        assertEq(account.requestIds(0), 1);
        (uint128 newAmount,, uint48 cohortCutoff) = account.pendingCohorts(1);
        assertEq(newAmount, 100e18);
        assertEq(cohortCutoff, CUTOFF);

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
    int256 public answer;
    uint256 public updatedAt;

    function setRound(int256 answer_, uint256 updatedAt_) public {
        answer = answer_;
        updatedAt = updatedAt_;
    }

    function latestRoundData()
        public
        view
        returns (uint80 roundId, int256 answer_, uint256 startedAt, uint256 updatedAt_, uint80 answeredInRound)
    {
        return (1, answer, updatedAt, updatedAt, 1);
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

    mapping(address token => TokenConfig config) internal _tokensConfig;
    mapping(uint256 requestId => Request request) internal _requests;

    constructor(address tokenToRedeem_, address mTokenDataFeed_) {
        tokenToRedeem = tokenToRedeem_;
        mTokenDataFeed = mTokenDataFeed_;
    }

    function setTokenConfig(address token, address dataFeed) public {
        _tokensConfig[token] = TokenConfig({dataFeed: dataFeed, fee: 0, allowance: 0, stable: true});
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
            amountMToken: amountMTokenIn,
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
