// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {DeployAdapterBase} from "./base/DeployAdapterBase.sol";

import {CentrifugeAccount} from "../../../src/contracts/adapters/ll-adapter/CentrifugeAccount.sol";
import {FigureSubAccount} from "../../../src/contracts/adapters/ll-adapter/FigureAccount.sol";
import {OpenEdenAccount} from "../../../src/contracts/adapters/ll-adapter/OpenEdenAccount.sol";
import {AsyncRedeemOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/AsyncRedeemOracle.sol";
import {FigureOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/FigureOracle.sol";
import {MidasOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/MidasOracle.sol";
import {OpenEdenOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/OpenEdenOracle.sol";
import {
    PRIME_Account,
    PRIME_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/PRIME_Account.sol";
import {
    HYB_Account,
    HYB_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/HYB_Account.sol";
import {
    JAAA_Account,
    JAAA_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JAAA_Account.sol";
import {
    mGLOBAL_Account,
    mGLOBAL_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mGLOBAL_Account.sol";
import {
    JTRSY_Account,
    JTRSY_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/JTRSY_Account.sol";
import {
    deJAAA_Account,
    deJAAA_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJAAA_Account.sol";
import {
    deJTRSY_Account,
    deJTRSY_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deJTRSY_Account.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {IAsyncRedeemAccount} from "../../../src/interfaces/adapters/ll-adapter/IAsyncRedeemAccount.sol";
import {IAsyncRedeemVault} from "../../../src/interfaces/adapters/ll-adapter/IAsyncRedeemVault.sol";
import {ICooldownAccount} from "../../../src/interfaces/adapters/ll-adapter/ICooldownAccount.sol";
import {IERC7575Share} from "../../../src/interfaces/adapters/ll-adapter/IERC7575Share.sol";
import {IFigureYieldVault} from "../../../src/interfaces/adapters/ll-adapter/figure/IFigureYieldVault.sol";
import {IMidasAccount} from "../../../src/interfaces/adapters/ll-adapter/midas/IMidasAccount.sol";
import {IMidasDataFeed, IMidasOracle} from "../../../src/interfaces/adapters/ll-adapter/midas/IMidasOracle.sol";
import {IMidasRedemptionVault} from "../../../src/interfaces/adapters/ll-adapter/midas/IMidasRedemptionVault.sol";
import {IOpenEdenAccount} from "../../../src/interfaces/adapters/ll-adapter/openeden/IOpenEdenAccount.sol";
import {IOpenEdenExpress} from "../../../src/interfaces/adapters/ll-adapter/openeden/IOpenEdenExpress.sol";
import {IAccount} from "../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IOracle} from "../../../src/interfaces/adapters/ll-adapter/IOracle.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ICoWSwapConverter, ICoWSwapSettlement} from "../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {Logs} from "../../utils/Logs.sol";
import {IGnosisSafe} from "../../utils/interfaces/IGnosisSafe.sol";

// forge script script/deploy/adapters/DeployLiquidLane2.s.sol:DeployLiquidLane2Script --rpc-url=RPC --broadcast

interface IMGlobalAdjustedAggregator {
    function underlyingFeed() external view returns (address);
    function adjustmentPercentage() external view returns (int256);
    function decimals() external view returns (uint8);
}

interface IMGlobalTokenConfig {
    function paused() external view returns (bool);
    function accessControl() external view returns (address);
    function M_GLOBAL_GREENLISTED_ROLE() external view returns (bytes32);
}

interface IMidasRedemptionVaultConfig {
    function paused() external view returns (bool);
    function fnPaused(bytes4 selector) external view returns (bool);
    function greenlistEnabled() external view returns (bool);
    function minAmount() external view returns (uint256);
    function accessControl() external view returns (address);
    function greenlistedRole() external view returns (bytes32);
}

interface ICentrifugeShareConfig {
    function hook() external view returns (address);
}

interface ICentrifugeVaultConfig {
    function share() external view returns (address);
    function root() external view returns (address);
}

interface ICentrifugeRootConfig {
    function paused() external view returns (bool);
}

interface IOpenEdenExpressConfig {
    function token() external view returns (address);
    function kycManager() external view returns (address);
    function pausedRedeem() external view returns (bool);
    function redeemFeeRate() external view returns (uint256);
}

interface IOpenEdenTokenConfig {
    function kycManager() external view returns (address);
    function paused() external view returns (bool);
}

interface IOpenEdenKycManagerConfig {
    function isKyced(address account) external view returns (bool);
}

interface IFigureTokenConfig {
    function yieldVault() external view returns (address);
    function paused() external view returns (bool);
}

interface IFigureYieldVaultConfig {
    function redeemVault() external view returns (address);
    function paused() external view returns (bool);
}

contract DeployLiquidLane2Script is DeployAdapterBase {
    struct AccountDeploymentData {
        address oracle;
        address factory;
        address implementation;
    }

    struct LiquidLane2DeploymentData {
        AccountDeploymentData jaaa;
        AccountDeploymentData jtrsy;
        AccountDeploymentData hyb;
        AccountDeploymentData deJAAA;
        AccountDeploymentData deJTRSY;
        AccountDeploymentData hybond;
        AccountDeploymentData prime;
        AccountDeploymentData mGlobal;
    }

    // Configurations - UPDATE FACTORIES_OWNER AND PRICE BOUNDS BEFORE DEPLOYMENT.

    // Address that will own all account factories after deployment.
    address public constant FACTORIES_OWNER = 0x5721ce64Ee0D772Ce613b62D411350091C544cD0;

    address public constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address public constant HYBOND = 0x1204371AC0e5176f4B8c5B2F16C2Bec551b6FC1a;
    address public constant HYBOND_EXPRESS = 0xD84C2571E05a59108Ead1c600D16133f0710E569;
    address public constant PRIME = 0x19ebb35279A16207Ec4ba82799CC64715065F7F6;
    address public constant WYLDS = 0x6aD038cA6C04e885630851278ca0a856Ad9a66Cc;
    address public constant WYLDS_REDEEM_VAULT = 0xA8C3CF6183D49d5D372f8FC149BD2cb5CFC0faCd;
    uint256 public constant HYBOND_REDEEM_MINIMUM = 100 ether;
    uint48 public constant HYBOND_COOLDOWN = 18 hours;
    // PRIME_Account hardcodes this cooldown internally; asserted post-deployment.
    uint48 public constant FIGURE_COOLDOWN = 18 hours;

    address public constant MGLOBAL = 0x7433806912Eae67919e66aea853d46Fa0aef98A8;
    // Immutable Midas mGLOBAL market-price feed used by the account oracle.
    address public constant MGLOBAL_DATA_FEED = 0x517cf115e750d02aeB978011fCE05691613d7ed7;
    // Exit-fee-adjusted feed used by the Midas redemption vault.
    address public constant MGLOBAL_REDEMPTION_DATA_FEED = 0xb468A6F63868cB6C6D99105EDfbe73d6B21f139E;
    address public constant MGLOBAL_MARKET_AGGREGATOR = 0x66Aa9fcD63DF74e1f67A9452E6E59Fbc67f75E38;
    address public constant MGLOBAL_REDEMPTION_VAULT = 0x1e0fd66753198c7b8bA64edEe8d41D8628Bf20D7;
    uint256 public constant MGLOBAL_REDEEM_MINIMUM = 1 ether;
    int256 public constant MGLOBAL_PRICE_ADJUSTMENT = -700_000_000;
    // Oracle bounds use 25% and 350% of their mainnet reference prices.
    uint256 public constant MGLOBAL_MIN_PRICE = 251_441_200_000_000_000;
    uint256 public constant MGLOBAL_MAX_PRICE = 3_520_176_800_000_000_000;
    // mGLOBAL_Account hardcodes this cooldown internally; asserted post-deployment.
    uint48 public constant MGLOBAL_COOLDOWN = 12 hours;

    address public constant JAAA = 0x5a0F93D040De44e78F251b03c43be9CF317Dcf64;
    address public constant JTRSY = 0x8c213ee79581Ff4984583C6a801e5263418C4b86;
    address public constant HYB = 0x4827C7ecce4f07ADfe44A97165f06A199e7d2505;
    address public constant DEJAAA = 0xAAA0008C8CF3A7Dca931adaF04336A5D808C82Cc;
    address public constant DEJTRSY = 0xA6233014B9b7aaa74f38fa1977ffC7A89642dC72;

    uint256 public constant JAAA_MIN_PRICE = 260_413_500_000_000_000;
    uint256 public constant JAAA_MAX_PRICE = 3_645_789_000_000_000_000;
    uint256 public constant JTRSY_MIN_PRICE = 277_562_500_000_000_000;
    uint256 public constant JTRSY_MAX_PRICE = 3_885_875_000_000_000_000;
    uint256 public constant HYB_MIN_PRICE = 250_943_250_000_000_000;
    uint256 public constant HYB_MAX_PRICE = 3_513_205_500_000_000_000;
    uint256 public constant DEJAAA_MIN_PRICE = 260_037_000_000_000_000;
    uint256 public constant DEJAAA_MAX_PRICE = 3_640_518_000_000_000_000;
    uint256 public constant DEJTRSY_MIN_PRICE = 257_864_500_000_000_000;
    uint256 public constant DEJTRSY_MAX_PRICE = 3_610_103_000_000_000_000;
    uint256 public constant HYBOND_MIN_PRICE = 433_749_000_000_000_000;
    uint256 public constant HYBOND_MAX_PRICE = 6_072_486_000_000_000_000;
    uint256 public constant PRIME_MIN_PRICE = 262_415_750_000_000_000;
    uint256 public constant PRIME_MAX_PRICE = 3_673_820_500_000_000_000;

    function run() public returns (LiquidLane2DeploymentData memory data) {
        _validateDeploymentParams();

        _startBroadcast();

        data.jaaa = _deployJAAA();
        data.jtrsy = _deployJTRSY();
        data.hyb = _deployHYB();
        data.deJAAA = _deployDeJAAA();
        data.deJTRSY = _deployDeJTRSY();
        data.hybond = _deployHYBOND();
        data.prime = _deployPRIME();
        data.mGlobal = _deployMGlobal();

        _stopBroadcast();

        _validateDeployment(data);
        _logDeployment(data);
    }

    function _deployJAAA() internal returns (AccountDeploymentData memory data) {
        data.factory = address(new JAAA_AccountFactory(_scriptOwner()));
        address asyncRedeemVault = IERC7575Share(JAAA).vault(USDC);
        data.oracle = address(new AsyncRedeemOracle(JAAA_MIN_PRICE, JAAA_MAX_PRICE, JAAA, asyncRedeemVault));
        data.implementation =
            address(new JAAA_Account(data.oracle, data.factory, USDC, asyncRedeemVault, COW_SWAP_SETTLEMENT));
        _whitelistAndTransferOwnership(data);
    }

    function _deployJTRSY() internal returns (AccountDeploymentData memory data) {
        data.factory = address(new JTRSY_AccountFactory(_scriptOwner()));
        address asyncRedeemVault = IERC7575Share(JTRSY).vault(USDC);
        data.oracle = address(new AsyncRedeemOracle(JTRSY_MIN_PRICE, JTRSY_MAX_PRICE, JTRSY, asyncRedeemVault));
        data.implementation =
            address(new JTRSY_Account(data.oracle, data.factory, USDC, asyncRedeemVault, COW_SWAP_SETTLEMENT));
        _whitelistAndTransferOwnership(data);
    }

    function _deployHYB() internal returns (AccountDeploymentData memory data) {
        data.factory = address(new HYB_AccountFactory(_scriptOwner()));
        address asyncRedeemVault = IERC7575Share(HYB).vault(USDC);
        data.oracle = address(new AsyncRedeemOracle(HYB_MIN_PRICE, HYB_MAX_PRICE, HYB, asyncRedeemVault));
        data.implementation =
            address(new HYB_Account(data.oracle, data.factory, USDC, asyncRedeemVault, COW_SWAP_SETTLEMENT));
        _whitelistAndTransferOwnership(data);
    }

    function _deployDeJAAA() internal returns (AccountDeploymentData memory data) {
        data.factory = address(new deJAAA_AccountFactory(_scriptOwner()));
        address asyncRedeemVault = IERC7575Share(DEJAAA).vault(USDC);
        data.oracle = address(new AsyncRedeemOracle(DEJAAA_MIN_PRICE, DEJAAA_MAX_PRICE, DEJAAA, asyncRedeemVault));
        data.implementation =
            address(new deJAAA_Account(data.oracle, data.factory, USDC, asyncRedeemVault, COW_SWAP_SETTLEMENT));
        _whitelistAndTransferOwnership(data);
    }

    function _deployDeJTRSY() internal returns (AccountDeploymentData memory data) {
        data.factory = address(new deJTRSY_AccountFactory(_scriptOwner()));
        address asyncRedeemVault = IERC7575Share(DEJTRSY).vault(USDC);
        data.oracle = address(new AsyncRedeemOracle(DEJTRSY_MIN_PRICE, DEJTRSY_MAX_PRICE, DEJTRSY, asyncRedeemVault));
        data.implementation =
            address(new deJTRSY_Account(data.oracle, data.factory, USDC, asyncRedeemVault, COW_SWAP_SETTLEMENT));
        _whitelistAndTransferOwnership(data);
    }

    function _deployHYBOND() internal returns (AccountDeploymentData memory data) {
        data.factory = address(new MigratablesFactory(_scriptOwner()));
        data.oracle = address(new OpenEdenOracle(HYBOND_MIN_PRICE, HYBOND_MAX_PRICE, HYBOND, HYBOND_EXPRESS));
        data.implementation = address(
            new OpenEdenAccount(data.oracle, data.factory, HYBOND_COOLDOWN, HYBOND, HYBOND_EXPRESS, COW_SWAP_SETTLEMENT)
        );
        _whitelistAndTransferOwnership(data);
    }

    function _deployPRIME() internal returns (AccountDeploymentData memory data) {
        data.factory = address(new PRIME_AccountFactory(_scriptOwner()));
        data.oracle = address(new FigureOracle(PRIME_MIN_PRICE, PRIME_MAX_PRICE, PRIME));
        data.implementation = address(
            new PRIME_Account(
                data.oracle, data.factory, PRIME, address(new FigureSubAccount(PRIME)), COW_SWAP_SETTLEMENT
            )
        );
        _whitelistAndTransferOwnership(data);
    }

    function _deployMGlobal() internal returns (AccountDeploymentData memory data) {
        data.factory = address(new mGLOBAL_AccountFactory(_scriptOwner()));
        data.implementation = address(new mGLOBAL_Account(data.factory, COW_SWAP_SETTLEMENT, MGLOBAL_DATA_FEED));
        data.oracle = IAccount(data.implementation).ORACLE();
        _whitelistAndTransferOwnership(data);
    }

    function _whitelistAndTransferOwnership(AccountDeploymentData memory data) internal {
        MigratablesFactory(data.factory).whitelist(data.implementation);
        if (FACTORIES_OWNER != _scriptOwner()) {
            Ownable(data.factory).transferOwnership(FACTORIES_OWNER);
        }
    }

    function _validateDeploymentParams() internal view {
        require(block.chainid == 1, "not ethereum mainnet");
        require(FACTORIES_OWNER != address(0), "invalid factories owner");
        require(FACTORIES_OWNER.code.length > 0, "missing factories owner");
        require(IGnosisSafe(FACTORIES_OWNER).getThreshold() > 1, "unsafe factories owner threshold");
        require(COW_SWAP_SETTLEMENT != address(0), "invalid cow swap settlement");
        require(USDC != address(0), "invalid usdc");
    }

    function _validateDeployment(LiquidLane2DeploymentData memory data) internal view {
        _validateAccountDeployment(JAAA, JAAA_MIN_PRICE, JAAA_MAX_PRICE, data.jaaa);
        _validateAccountDeployment(JTRSY, JTRSY_MIN_PRICE, JTRSY_MAX_PRICE, data.jtrsy);
        _validateAccountDeployment(HYB, HYB_MIN_PRICE, HYB_MAX_PRICE, data.hyb);
        _validateAccountDeployment(DEJAAA, DEJAAA_MIN_PRICE, DEJAAA_MAX_PRICE, data.deJAAA);
        _validateAccountDeployment(DEJTRSY, DEJTRSY_MIN_PRICE, DEJTRSY_MAX_PRICE, data.deJTRSY);
        _validateHYBONDDeployment(data.hybond);
        _validateFigureDeployment(PRIME, PRIME_MIN_PRICE, PRIME_MAX_PRICE, data.prime);
        _validateMGlobalDeployment(data.mGlobal);
    }

    function _validateAccountDeployment(
        address tokenToRedeem,
        uint256 minPrice,
        uint256 maxPrice,
        AccountDeploymentData memory data
    ) internal view {
        address asyncRedeemVault = IERC7575Share(tokenToRedeem).vault(USDC);
        AsyncRedeemOracle oracle = AsyncRedeemOracle(data.oracle);
        ICentrifugeVaultConfig vault = ICentrifugeVaultConfig(asyncRedeemVault);
        address hook = ICentrifugeShareConfig(tokenToRedeem).hook();
        address root = vault.root();

        _validateCommonAccountDeployment(data);
        assert(IAccount(data.implementation).TOKEN_TO_REDEEM() == tokenToRedeem);
        assert(IAsyncRedeemAccount(data.implementation).REDEMPTION_TOKEN() == USDC);
        assert(CentrifugeAccount(data.implementation).ASYNC_REDEEM_VAULT() == asyncRedeemVault);
        assert(ICooldownAccount(data.implementation).COOLDOWN() == 0);
        assert(IAsyncRedeemVault(asyncRedeemVault).asset() == USDC);
        assert(vault.share() == tokenToRedeem);
        assert(hook.code.length > 0);
        assert(root.code.length > 0 && !ICentrifugeRootConfig(root).paused());
        assert(oracle.ASYNC_REDEEM_VAULT() == asyncRedeemVault);
        assert(oracle.MIN_PRICE() == minPrice);
        assert(oracle.MAX_PRICE() == maxPrice);
        assert(oracle.getPrice() > 0);
    }

    function _validateHYBONDDeployment(AccountDeploymentData memory data) internal view {
        OpenEdenOracle oracle = OpenEdenOracle(data.oracle);
        address kycManager = IOpenEdenExpressConfig(HYBOND_EXPRESS).kycManager();

        _validateCommonAccountDeployment(data);
        assert(IAccount(data.implementation).TOKEN_TO_REDEEM() == HYBOND);
        assert(IOpenEdenAccount(data.implementation).EXPRESS() == HYBOND_EXPRESS);
        assert(ICooldownAccount(data.implementation).COOLDOWN() == HYBOND_COOLDOWN);
        assert(IOpenEdenExpressConfig(HYBOND_EXPRESS).token() == HYBOND);
        assert(IOpenEdenExpress(HYBOND_EXPRESS).redeemAsset() == USDC);
        assert(kycManager != address(0) && kycManager == IOpenEdenTokenConfig(HYBOND).kycManager());
        assert(IOpenEdenKycManagerConfig(kycManager).isKyced(HYBOND_EXPRESS));
        assert(!IOpenEdenExpressConfig(HYBOND_EXPRESS).pausedRedeem());
        assert(!IOpenEdenTokenConfig(HYBOND).paused());
        assert(IOpenEdenExpress(HYBOND_EXPRESS).redeemMinimum() == HYBOND_REDEEM_MINIMUM);
        assert(IOpenEdenExpressConfig(HYBOND_EXPRESS).redeemFeeRate() == 0);
        assert(IERC20Metadata(HYBOND).decimals() == 18);
        assert(IERC20Metadata(USDC).decimals() == 6);
        assert(oracle.TOKEN_TO_REDEEM() == HYBOND);
        assert(oracle.EXPRESS() == HYBOND_EXPRESS);
        assert(oracle.MIN_PRICE() == HYBOND_MIN_PRICE);
        assert(oracle.MAX_PRICE() == HYBOND_MAX_PRICE);
        assert(oracle.getPrice() > 0);
    }

    function _validateFigureDeployment(
        address tokenToRedeem,
        uint256 minPrice,
        uint256 maxPrice,
        AccountDeploymentData memory data
    ) internal view {
        address asyncRedeemVault = IERC4626(tokenToRedeem).asset();
        FigureOracle oracle = FigureOracle(data.oracle);

        _validateCommonAccountDeployment(data);
        assert(IAccount(data.implementation).TOKEN_TO_REDEEM() == tokenToRedeem);
        assert(ICooldownAccount(data.implementation).COOLDOWN() == FIGURE_COOLDOWN);
        assert(asyncRedeemVault == WYLDS);
        assert(IFigureTokenConfig(tokenToRedeem).yieldVault() == WYLDS);
        assert(!IFigureTokenConfig(tokenToRedeem).paused());
        assert(IFigureYieldVault(asyncRedeemVault).asset() == USDC);
        assert(IFigureYieldVaultConfig(asyncRedeemVault).redeemVault() == WYLDS_REDEEM_VAULT);
        assert(!IFigureYieldVaultConfig(asyncRedeemVault).paused());
        assert(IERC20Metadata(tokenToRedeem).decimals() == 6);
        assert(IERC20Metadata(asyncRedeemVault).decimals() == 6);
        assert(IERC20Metadata(USDC).decimals() == 6);
        assert(oracle.TOKEN_TO_REDEEM() == tokenToRedeem);
        assert(oracle.ASYNC_REDEEM_VAULT() == asyncRedeemVault);
        assert(oracle.MIN_PRICE() == minPrice);
        assert(oracle.MAX_PRICE() == maxPrice);
        assert(oracle.getPrice() > 0);
    }

    function _validateMGlobalDeployment(AccountDeploymentData memory data) internal view {
        IMidasRedemptionVaultConfig redemptionVault = IMidasRedemptionVaultConfig(MGLOBAL_REDEMPTION_VAULT);
        (address usdcDataFeed, uint256 fee, uint256 allowance, bool stable) =
            IMidasRedemptionVault(MGLOBAL_REDEMPTION_VAULT).tokensConfig(USDC);
        address redemptionAggregator = IMidasDataFeed(MGLOBAL_REDEMPTION_DATA_FEED).aggregator();

        _validateCommonAccountDeployment(data);
        assert(IAccount(data.implementation).TOKEN_TO_REDEEM() == MGLOBAL);
        assert(ICooldownAccount(data.implementation).COOLDOWN() == MGLOBAL_COOLDOWN);
        assert(IMidasAccount(data.implementation).REDEMPTION_VAULT() == MGLOBAL_REDEMPTION_VAULT);
        assert(IMidasAccount(data.implementation).REDEMPTION_TOKEN() == USDC);
        assert(IMidasRedemptionVault(MGLOBAL_REDEMPTION_VAULT).mToken() == MGLOBAL);
        assert(usdcDataFeed != address(0) && fee == 0 && allowance > 0 && stable);
        assert(!IMGlobalTokenConfig(MGLOBAL).paused());
        assert(!redemptionVault.paused());
        assert(!redemptionVault.fnPaused(IMidasRedemptionVault.redeemRequest.selector));
        assert(redemptionVault.minAmount() == MGLOBAL_REDEEM_MINIMUM);
        assert(IERC20Metadata(MGLOBAL).decimals() == 18);
        assert(IERC20Metadata(USDC).decimals() == 6);
        assert(redemptionVault.greenlistEnabled());
        address accessControl = redemptionVault.accessControl();
        bytes32 greenlistedRole = redemptionVault.greenlistedRole();
        assert(accessControl != address(0) && accessControl == IMGlobalTokenConfig(MGLOBAL).accessControl());
        assert(
            greenlistedRole != bytes32(0) && greenlistedRole == IMGlobalTokenConfig(MGLOBAL).M_GLOBAL_GREENLISTED_ROLE()
        );
        assert(IAccessControl(accessControl).hasRole(greenlistedRole, MGLOBAL_REDEMPTION_VAULT));
        assert(IMidasOracle(data.oracle).DATA_FEED() == MGLOBAL_DATA_FEED);
        assert(MidasOracle(data.oracle).MIN_PRICE() == MGLOBAL_MIN_PRICE);
        assert(MidasOracle(data.oracle).MAX_PRICE() == MGLOBAL_MAX_PRICE);
        assert(IMidasDataFeed(MGLOBAL_DATA_FEED).aggregator() == MGLOBAL_MARKET_AGGREGATOR);
        assert(
            address(IMidasRedemptionVault(MGLOBAL_REDEMPTION_VAULT).mTokenDataFeed()) == MGLOBAL_REDEMPTION_DATA_FEED
        );
        assert(IMGlobalAdjustedAggregator(redemptionAggregator).underlyingFeed() == MGLOBAL_MARKET_AGGREGATOR);
        assert(IMGlobalAdjustedAggregator(redemptionAggregator).adjustmentPercentage() == MGLOBAL_PRICE_ADJUSTMENT);
        assert(IMGlobalAdjustedAggregator(redemptionAggregator).decimals() == 8);
        assert(IOracle(data.oracle).getPrice() > 0);
    }

    function _validateCommonAccountDeployment(AccountDeploymentData memory data) internal view {
        assert(Ownable(data.factory).owner() == FACTORIES_OWNER);
        assert(MigratablesFactory(data.factory).implementation(1) == data.implementation);
        assert(IMigratableEntity(data.implementation).FACTORY() == data.factory);
        assert(IAccount(data.implementation).ORACLE() == data.oracle);
        assert(ICoWSwapConverter(data.implementation).COW_SWAP_SETTLEMENT() == COW_SWAP_SETTLEMENT);
        assert(
            ICoWSwapConverter(data.implementation).COW_SWAP_VAULT_RELAYER()
                == ICoWSwapSettlement(COW_SWAP_SETTLEMENT).vaultRelayer()
        );
    }

    function _logDeployment(LiquidLane2DeploymentData memory data) internal {
        _logAccountDeployment("JAAA", data.jaaa);
        _logAccountDeployment("JTRSY", data.jtrsy);
        _logAccountDeployment("HYB", data.hyb);
        _logAccountDeployment("deJAAA", data.deJAAA);
        _logAccountDeployment("deJTRSY", data.deJTRSY);
        _logAccountDeployment("HYBOND", data.hybond);
        _logAccountDeployment("PRIME", data.prime);
        _logAccountDeployment("mGLOBAL", data.mGlobal);
        Logs.log(
            "Next: register each token -> factory in the AccountRegistry; have Centrifuge permission the"
            " LiquidLaneAdapter proxy and every Centrifuge account proxy; have Midas greenlist the LiquidLaneAdapter"
            " proxy, every mGLOBAL account proxy, and all direct mGLOBAL transfer counterparties; and for HYBOND have"
            " OpenEden KYC-list the LiquidLaneAdapter proxy, every created account proxy, and all transfer"
            " counterparties. Route at least 100 HYBOND or 1 mGLOBAL per redemption request (or obtain a Midas minimum"
            " exemption). Complete these provider onboarding steps before enabling limits."
        );
    }

    function _logAccountDeployment(string memory name, AccountDeploymentData memory data) internal {
        Logs.log(
            string.concat(
                "Deployed ",
                name,
                " account",
                "\n    oracle:",
                vm.toString(data.oracle),
                "\n    accountFactory:",
                vm.toString(data.factory),
                "\n    accountImplementation:",
                vm.toString(data.implementation)
            )
        );
    }
}
