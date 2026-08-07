// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC4626Oracle} from "../../../src/contracts/adapters/ll-adapter/oracles/ERC4626Oracle.sol";
import {NoonOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/NoonOracle.sol";
import {sUSN_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sUSN_Account.sol";
import {sthUSD_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/sthUSD_Account.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
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

    address internal constant SUSN = 0xE24a3DC889621612422A64E6388927901608B91D;
    address internal constant NOON_WITHDRAWAL_HANDLER = 0x0DaBc0D9B270c9B0C4C77AaCeAa712b56D0F9178;
    address internal constant NOON_RATE_PROVIDER = 0x7f741401422Afff770360fD13127F7462C6E1A79;
    address internal constant STHUSD = 0xA808Bc9775cb41c52C7842f8b50427fE7A770326;

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

    function testSUSNAccountBindsCurrentNoonEndpointsAndBoundedOracle() public {
        address usn = makeAddr("USN");
        _mockVault(SUSN, usn, 18, 18);
        vm.mockCall(
            NOON_RATE_PROVIDER,
            abi.encodeWithSignature("getQuote(uint256,address,address)", 1e18, SUSN, usn),
            abi.encode(1.2e18)
        );

        MigratablesFactory factory = new MigratablesFactory(address(this));
        sUSN_Account account = new sUSN_Account(address(factory), cowSwapSettlement);
        NoonOracle oracle = NoonOracle(account.ORACLE());

        assertEq(account.TOKEN_TO_REDEEM(), SUSN);
        assertEq(account.WITHDRAWAL_HANDLER(), NOON_WITHDRAWAL_HANDLER);
        assertEq(oracle.RATE_PROVIDER(), NOON_RATE_PROVIDER);
        assertEq(oracle.TOKEN_TO_REDEEM(), SUSN);
        assertEq(oracle.QUOTE_TOKEN(), usn);
        assertEq(oracle.MIN_PRICE(), MIN_PRICE);
        assertEq(oracle.MAX_PRICE(), MAX_PRICE);
        assertEq(oracle.getPrice(), 1.2e18);
    }

    function testSthUSDAccountBindsCurrentVaultAndBoundedOracle() public {
        address thUSD = makeAddr("thUSD");
        _mockVault(STHUSD, thUSD, 6, 6);
        vm.mockCall(STHUSD, abi.encodeWithSignature("convertToAssets(uint256)", 1e6), abi.encode(1_015_160));

        MigratablesFactory factory = new MigratablesFactory(address(this));
        sthUSD_Account account = new sthUSD_Account(address(factory), cowSwapSettlement);
        ERC4626Oracle oracle = ERC4626Oracle(account.ORACLE());

        assertEq(account.TOKEN_TO_REDEEM(), STHUSD);
        assertEq(oracle.VAULT(), STHUSD);
        assertEq(oracle.MIN_PRICE(), MIN_PRICE);
        assertEq(oracle.MAX_PRICE(), MAX_PRICE);
        assertEq(oracle.getPrice(), 1_015_160_000_000_000_000);
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

    function _mockVault(address vault, address asset, uint8 shareDecimals, uint8 assetDecimals) internal {
        vm.mockCall(vault, abi.encodeWithSignature("asset()"), abi.encode(asset));
        vm.mockCall(vault, abi.encodeWithSignature("decimals()"), abi.encode(shareDecimals));
        vm.mockCall(asset, abi.encodeWithSignature("decimals()"), abi.encode(assetDecimals));
    }
}
