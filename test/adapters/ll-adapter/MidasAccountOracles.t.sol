// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MidasCompAccount, MidasNonCompAccount} from "../../../src/contracts/adapters/ll-adapter/MidasAccount.sol";
import {ChainlinkOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ChainlinkOracle.sol";
import {MidasOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/MidasOracle.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {IConverter} from "../../../src/interfaces/adapters/common/IConverter.sol";
import {ICoWSwapConverter} from "../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IAccount} from "../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IChainlinkOracle} from "../../../src/interfaces/adapters/ll-adapter/oracles/IChainlinkOracle.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MidasAccountOraclesTest is Test {
    uint256 internal constant MAX_EXPECTED_REQUESTS = 17;

    address internal adapter = makeAddr("adapter");
    address internal oracle = makeAddr("oracle");
    address internal vault = makeAddr("vault");
    address internal cowSettlement = makeAddr("cowSettlement");
    address internal cowRelayer = makeAddr("cowRelayer");

    function testMidasCompAccountPricesPendingRequestsAtCurrentRateUntilProcessed() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasDataFeed mTokenDataFeed = new MockMidasDataFeed(1e18);
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(mTokenDataFeed));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasCompAccount account =
            _deployCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        tokenToRedeem.mint(address(account), 100 ether);

        assertEq(account.ORACLE(), oracle);
        assertEq(account.vault(), vault);
        assertEq(account.converters(0), address(this));
        assertEq(account.totalAssets(), 100 ether);
        account.sync();

        mTokenDataFeed.setAnswer(2e18);

        assertEq(account.totalAssets(), 200 ether);

        redemptionVault.approveRequest(0, 2e18);

        account.sync();
        assertEq(asset.balanceOf(address(account)), 200 ether);
        assertEq(account.totalAssets(), 200 ether);
    }

    function testMidasNonCompAccountLocksPendingRequestValueAtCreationRate() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasDataFeed mTokenDataFeed = new MockMidasDataFeed(1e18);
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(mTokenDataFeed));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        tokenToRedeem.mint(address(account), 100 ether);

        account.sync();

        mTokenDataFeed.setAnswer(2e18);

        assertEq(account.totalAssets(), 100 ether);

        redemptionVault.approveRequest(0, 2e18);

        account.sync();
        assertEq(asset.balanceOf(address(account)), 200 ether);
        assertEq(account.totalAssets(), 200 ether);
    }

    function testMidasAccountRealizesProceedsOnDeallocate() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasDataFeed mTokenDataFeed = new MockMidasDataFeed(1e18);
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(mTokenDataFeed));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasCompAccount account =
            _deployCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        tokenToRedeem.mint(address(account), 100 ether);
        account.sync();

        redemptionVault.approveRequest(0, 2e18);

        account.sync();

        assertEq(asset.balanceOf(address(account)), 200 ether);
        assertEq(asset.allowance(address(account), adapter), type(uint256).max);
    }

    function testMidasAccountHandlesCanceledRequestByReturningTokenToRedeem() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasCompAccount account =
            _deployCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        tokenToRedeem.mint(address(account), 100 ether);
        account.sync();

        assertEq(account.totalAssets(), 100 ether);

        // Midas cancels the request and returns the token-to-redeem to the account.
        redemptionVault.cancelRequest(0);
        assertEq(tokenToRedeem.balanceOf(address(account)), 100 ether);

        // sync() prunes the canceled request and re-batches the returned token-to-redeem into a new request.
        account.sync();
        assertEq(asset.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.balanceOf(address(account)), 0);

        // No value lost or double-counted: the re-submitted request is valued back at 100.
        assertEq(account.totalAssets(), 100 ether);
    }

    function testMidasAccountRedeemsIntoConfiguredAsset() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockERC20 fallbackToken = new MockERC20("Fallback", "FB");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(fallbackToken), redemptionVault);
        tokenToRedeem.mint(address(account), 100 ether);

        account.sync();

        assertEq(redemptionVault.lastTokenOut(), address(asset));
        assertEq(redemptionVault.lastAmountMTokenIn(), 100 ether);
        assertEq(tokenToRedeem.balanceOf(address(redemptionVault)), 100 ether);
        assertEq(account.totalAssets(), 100 ether);
    }

    function testMidasAccountRedeemsIntoFallbackTokenWhenAssetIsUnsupported() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockERC20 fallbackToken = new MockERC20("Fallback", "FALLBACK");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        redemptionVault.setDataFeed(address(fallbackToken), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(fallbackToken), redemptionVault);
        tokenToRedeem.mint(address(account), 100 ether);

        account.sync();

        assertEq(redemptionVault.lastTokenOut(), address(fallbackToken));
        assertEq(redemptionVault.lastAmountMTokenIn(), 100 ether);
    }

    function testMidasAccountNormalizesHeldFallbackTokenToAssetDecimals() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockERC20Decimals fallbackToken = new MockERC20Decimals("Fallback", "FALLBACK", 6);
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(fallbackToken), redemptionVault);

        fallbackToken.mint(address(account), 100e6);

        assertEq(account.totalAssets(), 100 ether);
    }

    function testMidasAccountRedeemDoesNothingWithNoBalance() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        account.sync();
        assertEq(redemptionVault.lastTokenOut(), address(0));
    }

    function testMidasAccountSkipsTokenToRedeemOracleWhenBalanceIsZero() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(0)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        assertEq(account.totalAssets(), 0);
    }

    function testMidasCompAccountSkipsPendingOracleWhenNoRequests() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(0)));
        MidasCompAccount account =
            _deployCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        assertEq(account.totalAssets(), 0);
    }

    function testMidasAccountDoesNotExposeRequestRedeem() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        (bool success,) = address(account).call(abi.encodeWithSignature("requestRedeem()"));
        assertFalse(success);
    }

    function testMidasAccountDoesNotExposeTotalRequests() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        (bool success,) = address(account).staticcall(abi.encodeWithSignature("totalRequests()"));
        assertFalse(success);
    }

    function testMidasAccountDoesNotCapPendingRequests() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        for (uint256 i; i < 25; ++i) {
            tokenToRedeem.mint(address(account), 1 ether);
            account.sync();
        }

        assertEq(redemptionVault.currentRequestId(), 25);
        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 25 ether);
    }

    function testBenchmarkMidasRequestIdsMaxExpectedRequests() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        for (uint256 i; i < MAX_EXPECTED_REQUESTS - 1; ++i) {
            tokenToRedeem.mint(address(account), 1 ether);
            account.sync();
        }

        tokenToRedeem.mint(address(account), 1 ether);
        uint256 gasBefore = gasleft();
        account.sync();
        uint256 requestGas = gasBefore - gasleft();

        gasBefore = gasleft();
        uint256 assets = account.totalAssets();
        uint256 totalAssetsGas = gasBefore - gasleft();

        for (uint256 i; i < MAX_EXPECTED_REQUESTS; ++i) {
            redemptionVault.approveRequest(i, 1e18);
        }

        gasBefore = gasleft();
        account.sync();
        uint256 finalizeGas = gasBefore - gasleft();

        assertEq(assets, MAX_EXPECTED_REQUESTS * 1 ether);
        assertEq(asset.balanceOf(address(account)), MAX_EXPECTED_REQUESTS * 1 ether);

        emit log_named_uint("maxExpectedRequests", MAX_EXPECTED_REQUESTS);
        emit log_named_uint("requestGas", requestGas);
        emit log_named_uint("totalAssetsGas", totalAssetsGas);
        emit log_named_uint("finalizeGas", finalizeGas);
    }

    function testMidasAccountOwnerSyncBypassesCooldown() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account = _deployNonCompAccount(
            tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault, 1 days
        );

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();

        tokenToRedeem.mint(address(account), 1 ether);
        account.sync();

        assertEq(redemptionVault.currentRequestId(), 2);
        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
    }

    function testMidasAccountPermissionlessSyncRespectsCooldown() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        redemptionVault.setDataFeed(address(asset), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account = _deployNonCompAccount(
            tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault, 1 days
        );

        tokenToRedeem.mint(address(account), 1 ether);
        vm.prank(makeAddr("keeper"));
        account.sync();

        tokenToRedeem.mint(address(account), 1 ether);
        vm.prank(makeAddr("keeper"));
        account.sync();

        assertEq(redemptionVault.currentRequestId(), 1);
        assertEq(tokenToRedeem.balanceOf(address(account)), 1 ether);

        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.prank(makeAddr("keeper"));
        account.sync();

        assertEq(redemptionVault.currentRequestId(), 2);
        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
    }

    function testConvertRejectsNonAssetTokenOut() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        vm.expectRevert(IConverter.InvalidTokenOut.selector);
        account.convert(makeAddr("redemptionToken"), 1 ether, makeAddr("notAsset"), "");
    }

    function testConvertRejectsAssetTokenIn() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        vm.expectRevert(ICoWSwapConverter.InvalidTokenIn.selector);
        account.convert(address(asset), 1 ether, address(asset), "");
    }

    function testConvertRejectsTokenToRedeemTokenIn() public {
        MockERC20 tokenToRedeem = new MockERC20("Midas Token", "mTKN");
        MockERC20 asset = new MockERC20("Asset", "ASSET");
        MockMidasRedemptionVault redemptionVault =
            new MockMidasRedemptionVault(address(tokenToRedeem), address(new MockMidasDataFeed(1e18)));
        MidasNonCompAccount account =
            _deployNonCompAccount(tokenToRedeem, asset, address(new MockERC20("Fallback", "FB")), redemptionVault);

        vm.expectRevert(ICoWSwapConverter.InvalidTokenIn.selector);
        account.convert(address(tokenToRedeem), 1 ether, address(asset), "");
    }

    function testChainlinkOracleReturnsLatestPriceInBase18() public {
        MockChainlinkAggregator aggregator = new MockChainlinkAggregator(8);
        aggregator.setLatestRoundData(1, 123e8, uint48(vm.getBlockTimestamp()), 1);
        ChainlinkOracle oracle = new ChainlinkOracle([address(aggregator), address(0)], [uint48(1 days), uint48(0)]);

        assertEq(oracle.getPrice(), 123e18);
    }

    function testChainlinkOracleMultipliesSecondAggregatorHop() public {
        MockChainlinkAggregator aggregator0 = new MockChainlinkAggregator(8);
        MockChainlinkAggregator aggregator1 = new MockChainlinkAggregator(18);
        aggregator0.setLatestRoundData(1, 2e8, uint48(vm.getBlockTimestamp()), 1);
        aggregator1.setLatestRoundData(1, 3e18, uint48(vm.getBlockTimestamp()), 1);
        ChainlinkOracle oracle =
            new ChainlinkOracle([address(aggregator0), address(aggregator1)], [uint48(1 days), uint48(1 days)]);

        assertEq(oracle.getPrice(), 6e18);
    }

    function testChainlinkOracleReturnsZeroForStalePrice() public {
        vm.warp(10 days);
        MockChainlinkAggregator aggregator = new MockChainlinkAggregator(8);
        aggregator.setLatestRoundData(1, 123e8, uint48(vm.getBlockTimestamp() - 2 days), 1);
        ChainlinkOracle oracle = new ChainlinkOracle([address(aggregator), address(0)], [uint48(1 days), uint48(0)]);

        assertEq(oracle.getPrice(), 0);
    }

    function testChainlinkOracleRevertsWithNoFirstAggregator() public {
        vm.expectRevert(IChainlinkOracle.InvalidAggregator.selector);
        new ChainlinkOracle([address(0), makeAddr("aggregator")], [uint48(1 days), uint48(0)]);
    }

    function testMidasOracleReturnsFeedPrice() public {
        MockMidasDataFeed dataFeed = new MockMidasDataFeed(42e18);
        MidasOracle oracle = new MidasOracle(address(dataFeed));

        assertEq(oracle.getPrice(), 42e18);
    }

    function _deployCompAccount(
        MockERC20 tokenToRedeem,
        MockERC20 asset,
        address fallbackToken,
        MockMidasRedemptionVault redemptionVault
    ) internal returns (MidasCompAccount account) {
        vault = address(new MockVault(address(asset)));
        oracle = address(new MidasOracle(redemptionVault.mTokenDataFeed()));
        MigratablesFactory factory = new MigratablesFactory(address(this));
        MidasCompAccount implementation = new MidasCompAccount(
            oracle,
            address(factory),
            0,
            address(tokenToRedeem),
            fallbackToken,
            address(redemptionVault),
            cowSettlement,
            cowRelayer
        );
        factory.whitelist(address(implementation));
        account = MidasCompAccount(factory.create(1, address(this), _initData(address(tokenToRedeem))));
    }

    function _deployNonCompAccount(
        MockERC20 tokenToRedeem,
        MockERC20 asset,
        address fallbackToken,
        MockMidasRedemptionVault redemptionVault
    ) internal returns (MidasNonCompAccount account) {
        account = _deployNonCompAccount(tokenToRedeem, asset, fallbackToken, redemptionVault, 0);
    }

    function _deployNonCompAccount(
        MockERC20 tokenToRedeem,
        MockERC20 asset,
        address fallbackToken,
        MockMidasRedemptionVault redemptionVault,
        uint48 cooldown
    ) internal returns (MidasNonCompAccount account) {
        vault = address(new MockVault(address(asset)));
        oracle = address(new MidasOracle(redemptionVault.mTokenDataFeed()));
        MigratablesFactory factory = new MigratablesFactory(address(this));
        MidasNonCompAccount implementation = new MidasNonCompAccount(
            oracle,
            address(factory),
            cooldown,
            address(tokenToRedeem),
            fallbackToken,
            address(redemptionVault),
            cowSettlement,
            cowRelayer
        );
        factory.whitelist(address(implementation));
        account = MidasNonCompAccount(factory.create(1, address(this), _initData(address(tokenToRedeem))));
    }

    function _initData(address) internal view returns (bytes memory) {
        return abi.encode(vault, adapter);
    }
}

contract MockVault {
    address public asset;

    constructor(address asset_) {
        asset = asset_;
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address account, uint256 value) public {
        _mint(account, value);
    }
}

contract MockERC20Decimals is MockERC20 {
    uint8 internal immutable _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) MockERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
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

    address public immutable tokenToRedeem;
    address public immutable mTokenDataFeed;
    address public lastTokenOut;
    uint256 public lastAmountMTokenIn;
    uint256 public currentRequestId;

    mapping(address token => address dataFeed) public dataFeedOf;
    mapping(address token => bool stable) public stableOf;
    mapping(uint256 requestId => Request request) public requests;

    constructor(address tokenToRedeem_, address mTokenDataFeed_) {
        tokenToRedeem = tokenToRedeem_;
        mTokenDataFeed = mTokenDataFeed_;
    }

    function setDataFeed(address token, address dataFeed) public {
        dataFeedOf[token] = dataFeed;
    }

    function tokensConfig(address token)
        public
        view
        returns (address dataFeed, uint256 fee, uint256 allowance, bool stable)
    {
        dataFeed = dataFeedOf[token];
        stable = stableOf[token];
    }

    function redeemRequest(address tokenOut, uint256 amountMTokenIn) public returns (uint256 requestId) {
        lastTokenOut = tokenOut;
        lastAmountMTokenIn = amountMTokenIn;
        IERC20(tokenToRedeem).transferFrom(msg.sender, address(this), amountMTokenIn);
        requestId = currentRequestId++;
        requests[requestId] = Request({
            sender: msg.sender,
            tokenOut: tokenOut,
            status: PENDING,
            amountMToken: amountMTokenIn,
            mTokenRate: MockMidasDataFeed(mTokenDataFeed).getDataInBase18(),
            tokenOutRate: _tokenRate(tokenOut)
        });
    }

    function approveRequest(uint256 requestId, uint256 newMTokenRate) public {
        Request storage request = requests[requestId];
        request.status = PROCESSED;
        request.mTokenRate = newMTokenRate;
        MockERC20(request.tokenOut).mint(request.sender, request.amountMToken * newMTokenRate / request.tokenOutRate);
    }

    function cancelRequest(uint256 requestId) public {
        Request storage request = requests[requestId];
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
        Request storage request = requests[requestId];
        return (
            request.sender,
            request.tokenOut,
            request.status,
            request.amountMToken,
            request.mTokenRate,
            request.tokenOutRate
        );
    }

    function _tokenRate(address token) internal view returns (uint256) {
        if (stableOf[token]) {
            return 1e18;
        }
        return MockMidasDataFeed(dataFeedOf[token]).getDataInBase18();
    }
}

contract MockChainlinkAggregator {
    uint8 public immutable decimals;
    string public constant description = "Mock";
    uint256 public constant version = 1;

    uint80 internal _roundId;
    int256 internal _answer;
    uint48 internal _updatedAt;
    uint80 internal _answeredInRound;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function setLatestRoundData(uint80 roundId, int256 answer, uint48 updatedAt, uint80 answeredInRound) public {
        _roundId = roundId;
        _answer = answer;
        _updatedAt = updatedAt;
        _answeredInRound = answeredInRound;
    }

    function getRoundData(uint80 roundId)
        public
        view
        returns (uint80, int256 answer, uint48 startedAt, uint48 updatedAt, uint80 answeredInRound)
    {
        if (roundId != _roundId) {
            revert("missing round");
        }
        return (roundId, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }

    function latestRoundData()
        public
        view
        returns (uint80 roundId, int256 answer, uint48 startedAt, uint48 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _answer, _updatedAt, _updatedAt, _answeredInRound);
    }
}

contract MockMidasDataFeed {
    uint256 public answer;

    constructor(uint256 answer_) {
        answer = answer_;
    }

    function getDataInBase18() public view returns (uint256) {
        return answer;
    }

    function setAnswer(uint256 answer_) public {
        answer = answer_;
    }
}
