// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ChainlinkOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ChainlinkOracle.sol";
import {FigureOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/FigureOracle.sol";
import {MidasOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/MidasOracle.sol";
import {OpenEdenOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/OpenEdenOracle.sol";
import {Oracle} from "../../../src/contracts/adapters/ll-adapter/oracles/Oracle.sol";
import {ThreeJaneOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ThreeJaneOracle.sol";
import {IOracle} from "../../../src/interfaces/adapters/ll-adapter/IOracle.sol";

contract OracleHarness is Oracle {
    uint256 internal _price;

    constructor(uint256 minPrice, uint256 maxPrice) Oracle(minPrice, maxPrice) {}

    function setPrice(uint256 price) external {
        _price = price;
    }

    function _getPrice() internal view override returns (uint256) {
        return _price;
    }
}

contract MockAggregatorV3 {
    int256 public answer;
    uint256 public updatedAt;
    uint8 public immutable decimals;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }

    function setRound(int256 answer_, uint256 updatedAt_) external {
        answer = answer_;
        updatedAt = updatedAt_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }

    function getRoundData(uint80) external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, answer, updatedAt, updatedAt, 1);
    }
}

contract MockMidasDataFeed {
    address public aggregator;
    uint256 internal _answer;

    constructor(address aggregator_) {
        aggregator = aggregator_;
    }

    function setAnswer(uint256 answer_) external {
        _answer = answer_;
    }

    function getDataInBase18() external view returns (uint256) {
        return _answer;
    }
}

contract MockPriceOracleToken {
    uint8 public immutable decimals;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }
}

contract MockPriceOracleVault is MockPriceOracleToken {
    address public immutable asset;
    uint256 public conversionNumerator;
    uint256 public conversionDenominator;

    constructor(uint8 decimals_, address asset_) MockPriceOracleToken(decimals_) {
        asset = asset_;
    }

    function setConversionRatio(uint256 numerator, uint256 denominator) external {
        conversionNumerator = numerator;
        conversionDenominator = denominator;
    }

    function convertToAssets(uint256 shares) external view returns (uint256) {
        return shares * conversionNumerator / conversionDenominator;
    }
}

contract MockPriceOracleOpenEdenExpress {
    address public immutable redeemAsset;
    uint256 public feeNumerator;
    uint256 public grossNumerator;
    uint256 public netNumerator;
    uint256 public previewDenominator;

    constructor(address redeemAsset_) {
        redeemAsset = redeemAsset_;
    }

    function setPreviewRatio(uint256 fee, uint256 gross, uint256 net, uint256 denominator) external {
        feeNumerator = fee;
        grossNumerator = gross;
        netNumerator = net;
        previewDenominator = denominator;
    }

    function previewRedeem(uint256 tokenAmount) external view returns (uint256 fee, uint256 gross, uint256 net) {
        fee = tokenAmount * feeNumerator / previewDenominator;
        gross = tokenAmount * grossNumerator / previewDenominator;
        net = tokenAmount * netNumerator / previewDenominator;
    }
}

contract PriceDataOraclesTest is Test {
    function testOracleRevertsWhenMinPriceIsZero() public {
        vm.expectRevert(IOracle.InvalidPriceRange.selector);
        new OracleHarness(0, 2e18);
    }

    function testOracleRevertsWhenMinPriceEqualsMaxPrice() public {
        vm.expectRevert(IOracle.InvalidPriceRange.selector);
        new OracleHarness(1e18, 1e18);
    }

    function testOracleRevertsWhenMinPriceIsGreaterThanMaxPrice() public {
        vm.expectRevert(IOracle.InvalidPriceRange.selector);
        new OracleHarness(2e18, 1e18);
    }

    function testOracleReturnsPriceInsideConfiguredRange() public {
        OracleHarness oracle = new OracleHarness(1e18, 2e18);
        oracle.setPrice(1.5e18);

        assertEq(oracle.getPrice(), 1.5e18);
    }

    function testOracleRevertsBelowConfiguredRange() public {
        OracleHarness oracle = new OracleHarness(1e18, 2e18);
        oracle.setPrice(1e18 - 1);

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testOracleRevertsAboveConfiguredRange() public {
        OracleHarness oracle = new OracleHarness(1e18, 2e18);
        oracle.setPrice(2e18 + 1);

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testMidasOracleReturnsFeedPrice() public {
        MockAggregatorV3 aggregator = new MockAggregatorV3(8);
        MockMidasDataFeed dataFeed = new MockMidasDataFeed(address(aggregator));
        dataFeed.setAnswer(0.93e18);

        MidasOracle oracle = new MidasOracle(1, type(uint256).max, address(dataFeed));
        assertEq(oracle.getPrice(), 0.93e18);
    }

    function testFigureOraclePricesBothRedemptionLegsAndNormalizesDecimals() public {
        MockPriceOracleToken redemptionToken = new MockPriceOracleToken(6);
        MockPriceOracleVault asyncRedeemVault = new MockPriceOracleVault(6, address(redemptionToken));
        MockPriceOracleVault token = new MockPriceOracleVault(18, address(asyncRedeemVault));
        token.setConversionRatio(1_250_000, 1e18);
        asyncRedeemVault.setConversionRatio(1_500_000, 1_250_000);

        FigureOracle oracle = new FigureOracle(1, type(uint256).max, address(token));

        assertEq(oracle.TOKEN_TO_REDEEM(), address(token));
        assertEq(oracle.ASYNC_REDEEM_VAULT(), address(asyncRedeemVault));
        assertEq(oracle.getPrice(), 1.5e18);
    }

    function testFigureOracleRejectsOutOfRangeComputedPrice() public {
        MockPriceOracleToken redemptionToken = new MockPriceOracleToken(6);
        MockPriceOracleVault asyncRedeemVault = new MockPriceOracleVault(6, address(redemptionToken));
        MockPriceOracleVault token = new MockPriceOracleVault(18, address(asyncRedeemVault));
        token.setConversionRatio(1_250_000, 1e18);
        asyncRedeemVault.setConversionRatio(1_500_000, 1_250_000);

        FigureOracle oracle = new FigureOracle(1.5e18 + 1, type(uint256).max, address(token));

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testThreeJaneOraclePricesSUSD3InUSDCThroughBothVaults() public {
        MockPriceOracleToken usdc = new MockPriceOracleToken(6);
        MockPriceOracleVault usd3 = new MockPriceOracleVault(18, address(usdc));
        MockPriceOracleVault sUSD3 = new MockPriceOracleVault(18, address(usd3));
        sUSD3.setConversionRatio(1.25e18, 1e18);
        usd3.setConversionRatio(1.5e6, 1.25e18);

        ThreeJaneOracle oracle = new ThreeJaneOracle(1, type(uint256).max, address(sUSD3));

        assertEq(oracle.TOKEN_TO_REDEEM(), address(sUSD3));
        assertEq(oracle.USD3(), address(usd3));
        assertEq(oracle.getPrice(), 1.5e18);
    }

    function testThreeJaneOracleRejectsOutOfRangeComputedPrice() public {
        MockPriceOracleToken usdc = new MockPriceOracleToken(6);
        MockPriceOracleVault usd3 = new MockPriceOracleVault(18, address(usdc));
        MockPriceOracleVault sUSD3 = new MockPriceOracleVault(18, address(usd3));
        sUSD3.setConversionRatio(1.25e18, 1e18);
        usd3.setConversionRatio(1.5e6, 1.25e18);

        ThreeJaneOracle oracle = new ThreeJaneOracle(1.5e18 + 1, type(uint256).max, address(sUSD3));

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testOpenEdenOracleUsesNetPreviewAndNormalizesDecimals() public {
        MockPriceOracleToken redemptionToken = new MockPriceOracleToken(6);
        MockPriceOracleToken hybond = new MockPriceOracleToken(18);
        MockPriceOracleOpenEdenExpress express = new MockPriceOracleOpenEdenExpress(address(redemptionToken));
        express.setPreviewRatio(17_500, 1_750_000, 1_732_500, 1e18);

        OpenEdenOracle oracle = new OpenEdenOracle(1, type(uint256).max, address(hybond), address(express));

        assertEq(oracle.TOKEN_TO_REDEEM(), address(hybond));
        assertEq(oracle.EXPRESS(), address(express));
        assertEq(oracle.getPrice(), 1.7325e18);
    }

    function testOpenEdenOracleRejectsOutOfRangeComputedPrice() public {
        MockPriceOracleToken redemptionToken = new MockPriceOracleToken(6);
        MockPriceOracleToken hybond = new MockPriceOracleToken(18);
        MockPriceOracleOpenEdenExpress express = new MockPriceOracleOpenEdenExpress(address(redemptionToken));
        express.setPreviewRatio(17_500, 1_750_000, 1_732_500, 1e18);

        OpenEdenOracle oracle = new OpenEdenOracle(1, 1.7325e18 - 1, address(hybond), address(express));

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testChainlinkOracleReturnsOldestUpdatedAtOfTwoAggregators() public {
        MockAggregatorV3 aggregator0 = new MockAggregatorV3(8);
        MockAggregatorV3 aggregator1 = new MockAggregatorV3(8);
        vm.warp(2_000_000_000);
        aggregator0.setRound(1e8, 1_999_999_000);
        aggregator1.setRound(2e8, 1_999_998_000);

        ChainlinkOracle oracle = new ChainlinkOracle(
            1, type(uint256).max, [address(aggregator0), address(aggregator1)], [uint48(1 days), uint48(1 days)]
        );
        (uint256 price, uint48 updatedAt) = oracle.getPriceData();
        assertEq(price, 2e18);
        assertEq(updatedAt, 1_999_998_000);
    }

    function testChainlinkOracleSingleAggregatorUpdatedAt() public {
        MockAggregatorV3 aggregator0 = new MockAggregatorV3(8);
        vm.warp(2_000_000_000);
        aggregator0.setRound(1e8, 1_999_999_123);

        ChainlinkOracle oracle =
            new ChainlinkOracle(1, type(uint256).max, [address(aggregator0), address(0)], [uint48(1 days), uint48(0)]);
        (, uint48 updatedAt) = oracle.getPriceData();
        assertEq(updatedAt, 1_999_999_123);
    }

    function testChainlinkOracleRevertsForStaleLegBelowMinPrice() public {
        MockAggregatorV3 aggregator0 = new MockAggregatorV3(8);
        MockAggregatorV3 aggregator1 = new MockAggregatorV3(8);
        vm.warp(2_000_000_000);
        aggregator0.setRound(1e8, 1_999_999_000);
        aggregator1.setRound(2e8, 2_000_000_000 - 2 days);

        ChainlinkOracle oracle = new ChainlinkOracle(
            1, type(uint256).max, [address(aggregator0), address(aggregator1)], [uint48(1 days), uint48(1 days)]
        );
        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPriceData();
    }

    function testChainlinkOracleRevertsForNegativeAnswerBelowMinPrice() public {
        MockAggregatorV3 aggregator0 = new MockAggregatorV3(8);
        vm.warp(2_000_000_000);
        aggregator0.setRound(-1, block.timestamp);

        ChainlinkOracle oracle =
            new ChainlinkOracle(1, type(uint256).max, [address(aggregator0), address(0)], [uint48(1 days), uint48(0)]);
        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPriceData();
    }

    function testChainlinkOracleRevertsWhenZeroUpdatedAtMakesPriceInvalid() public {
        MockAggregatorV3 aggregator0 = new MockAggregatorV3(8);
        vm.warp(2_000_000_000);
        aggregator0.setRound(1e8, 0);

        ChainlinkOracle oracle =
            new ChainlinkOracle(1, type(uint256).max, [address(aggregator0), address(0)], [uint48(1 days), uint48(0)]);
        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPriceData();
    }
}
