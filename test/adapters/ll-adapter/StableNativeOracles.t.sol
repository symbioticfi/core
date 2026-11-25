// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC4626Oracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ERC4626Oracle.sol";
import {NoonOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/NoonOracle.sol";
import {IOracle} from "../../../src/interfaces/adapters/ll-adapter/IOracle.sol";

contract MockStableNativeToken {
    uint8 public immutable decimals;

    constructor(uint8 decimals_) {
        decimals = decimals_;
    }
}

contract MockStableNativeVault is MockStableNativeToken {
    address public immutable asset;
    uint256 internal _assetsPerShareUnit;

    constructor(uint8 decimals_, address asset_) MockStableNativeToken(decimals_) {
        asset = asset_;
    }

    function setAssetsPerShareUnit(uint256 assets) external {
        _assetsPerShareUnit = assets;
    }

    function convertToAssets(uint256 shares) external view returns (uint256 assets) {
        assets = shares * _assetsPerShareUnit / 10 ** decimals;
    }
}

contract MockNoonRateProvider {
    error InvalidRoute();

    address internal _baseToken;
    address internal _quoteToken;
    uint256 internal _baseAmount;
    uint256 internal _quoteAmount;

    function setQuote(address baseToken, address quoteToken, uint256 baseAmount, uint256 quoteAmount) external {
        _baseToken = baseToken;
        _quoteToken = quoteToken;
        _baseAmount = baseAmount;
        _quoteAmount = quoteAmount;
    }

    function getQuote(uint256 baseAmount, address baseToken, address quoteToken)
        external
        view
        returns (uint256 quoteAmount)
    {
        if (baseToken != _baseToken || quoteToken != _quoteToken || baseAmount != _baseAmount) {
            revert InvalidRoute();
        }
        quoteAmount = _quoteAmount;
    }
}

contract MockStableNativeCowSettlement {
    address public immutable vaultRelayer;

    constructor(address vaultRelayer_) {
        vaultRelayer = vaultRelayer_;
    }
}

contract StableNativeOraclesTest is Test {
    uint256 internal constant MIN_PRICE = 0.5e18;
    uint256 internal constant MAX_PRICE = 2.5e18;

    address internal cowSwapSettlement;

    function setUp() public {
        cowSwapSettlement = address(new MockStableNativeCowSettlement(makeAddr("vaultRelayer")));
    }

    function testNoonOracleNormalizesTokenAndQuoteDecimals() public {
        MockStableNativeToken quoteToken = new MockStableNativeToken(8);
        MockStableNativeVault token = new MockStableNativeVault(6, address(quoteToken));
        MockNoonRateProvider rateProvider = new MockNoonRateProvider();
        rateProvider.setQuote(address(token), address(quoteToken), 1e6, 121_223_021);
        NoonOracle oracle = new NoonOracle(MIN_PRICE, MAX_PRICE, address(rateProvider), address(token));

        assertEq(oracle.getPrice(), 1_212_230_210_000_000_000);
    }

    function testNoonOracleRejectsZeroQuote() public {
        (NoonOracle oracle, MockNoonRateProvider rateProvider, address token, address quoteToken) = _deployNoonOracle();
        rateProvider.setQuote(token, quoteToken, 1e18, 0);

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testNoonOracleRejectsQuoteBelowBound() public {
        (NoonOracle oracle, MockNoonRateProvider rateProvider, address token, address quoteToken) = _deployNoonOracle();
        rateProvider.setQuote(token, quoteToken, 1e18, MIN_PRICE - 1);

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testNoonOracleRejectsQuoteAboveBound() public {
        (NoonOracle oracle, MockNoonRateProvider rateProvider, address token, address quoteToken) = _deployNoonOracle();
        rateProvider.setQuote(token, quoteToken, 1e18, MAX_PRICE + 1);

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testERC4626OracleNormalizesShareAndAssetDecimals() public {
        MockStableNativeToken asset = new MockStableNativeToken(6);
        MockStableNativeVault vault = new MockStableNativeVault(8, address(asset));
        vault.setAssetsPerShareUnit(1_015_160);
        ERC4626Oracle oracle = new ERC4626Oracle(MIN_PRICE, MAX_PRICE, address(vault));

        assertEq(oracle.getPrice(), 1_015_160_000_000_000_000);
    }

    function testERC4626OracleRejectsZeroConversion() public {
        (ERC4626Oracle oracle, MockStableNativeVault vault) = _deployERC4626Oracle();
        vault.setAssetsPerShareUnit(0);

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testERC4626OracleRejectsConversionBelowBound() public {
        (ERC4626Oracle oracle, MockStableNativeVault vault) = _deployERC4626Oracle();
        vault.setAssetsPerShareUnit(499_999);

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testERC4626OracleRejectsConversionAboveBound() public {
        (ERC4626Oracle oracle, MockStableNativeVault vault) = _deployERC4626Oracle();
        vault.setAssetsPerShareUnit(2_500_001);

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function _deployNoonOracle()
        internal
        returns (NoonOracle oracle, MockNoonRateProvider rateProvider, address token, address quoteToken)
    {
        quoteToken = address(new MockStableNativeToken(18));
        token = address(new MockStableNativeVault(18, quoteToken));
        rateProvider = new MockNoonRateProvider();
        rateProvider.setQuote(token, quoteToken, 1e18, 1e18);
        oracle = new NoonOracle(MIN_PRICE, MAX_PRICE, address(rateProvider), token);
    }

    function _deployERC4626Oracle() internal returns (ERC4626Oracle oracle, MockStableNativeVault vault) {
        MockStableNativeToken asset = new MockStableNativeToken(6);
        vault = new MockStableNativeVault(18, address(asset));
        vault.setAssetsPerShareUnit(1_000_000);
        oracle = new ERC4626Oracle(MIN_PRICE, MAX_PRICE, address(vault));
    }
}
