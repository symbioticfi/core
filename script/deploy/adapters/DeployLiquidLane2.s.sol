// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {DeployAdapterBase} from "./base/DeployAdapterBase.sol";

import {CentrifugeAccount} from "../../../src/contracts/adapters/ll-adapter/CentrifugeAccount.sol";
import {FigureSubAccount} from "../../../src/contracts/adapters/ll-adapter/FigureAccount.sol";
import {OpenEdenAccount} from "../../../src/contracts/adapters/ll-adapter/OpenEdenAccount.sol";
import {AsyncRedeemOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/AsyncRedeemOracle.sol";
import {FigureOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/FigureOracle.sol";
import {OpenEdenOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/OpenEdenOracle.sol";
import {
    ACRDX_Account,
    ACRDX_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/ACRDX_Account.sol";
import {
    AUTO_Account,
    AUTO_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/AUTO_Account.sol";
import {
    PRIME_Account,
    PRIME_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/PRIME_Account.sol";
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
    deCRDX_Account,
    deCRDX_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/deCRDX_Account.sol";
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
import {ICoWSwapConverter, ICoWSwapSettlement} from "../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {Logs} from "../../utils/Logs.sol";

// forge script script/deploy/adapters/DeployLiquidLane2.s.sol:DeployLiquidLane2Script --rpc-url=RPC --broadcast

interface IMGlobalAdjustedAggregator {
    function underlyingFeed() external view returns (address);
}

contract DeployLiquidLane2Script is DeployAdapterBase {
    struct AccountDeploymentData {
        address oracle;
        address factory;
        address implementation;
    }

    struct LiquidLane2DeploymentData {
        AccountDeploymentData acrdx;
        AccountDeploymentData jaaa;
        AccountDeploymentData jtrsy;
        AccountDeploymentData deCRDX;
        AccountDeploymentData deJAAA;
        AccountDeploymentData deJTRSY;
        AccountDeploymentData hybond;
        AccountDeploymentData prime;
        AccountDeploymentData autoToken;
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
    address public constant AUTO = 0x997E2Efbce91D170B00EA402e35a66C887EE1da9;
    uint48 public constant HYBOND_COOLDOWN = 1 days;
    // PRIME_Account and AUTO_Account hardcode this cooldown internally; asserted post-deployment.
    uint48 public constant FIGURE_COOLDOWN = 1 days;

    address public constant MGLOBAL = 0x7433806912Eae67919e66aea853d46Fa0aef98A8;
    // Midas mGLOBAL NAV feed (exit-fee adjusted); must equal the redemption vault's mTokenDataFeed.
    address public constant MGLOBAL_DATA_FEED = 0xb468A6F63868cB6C6D99105EDfbe73d6B21f139E;
    address public constant MGLOBAL_MARKET_AGGREGATOR = 0x66Aa9fcD63DF74e1f67A9452E6E59Fbc67f75E38;
    address public constant MGLOBAL_REDEMPTION_VAULT = 0x1e0fd66753198c7b8bA64edEe8d41D8628Bf20D7;
    // mGLOBAL_Account hardcodes this cooldown internally; asserted post-deployment.
    uint48 public constant MGLOBAL_COOLDOWN = 12 hours;

    address public constant ACRDX = 0x9477724Bb54AD5417de8Baff29e59DF3fB4DA74f;
    address public constant JAAA = 0x5a0F93D040De44e78F251b03c43be9CF317Dcf64;
    address public constant JTRSY = 0x8c213ee79581Ff4984583C6a801e5263418C4b86;
    address public constant DECRDX = 0x9E2679eABFF131b8b1b48fF7566140794E0eEdc4;
    address public constant DEJAAA = 0xAAA0008C8CF3A7Dca931adaF04336A5D808C82Cc;
    address public constant DEJTRSY = 0xA6233014B9b7aaa74f38fa1977ffC7A89642dC72;

    uint256 public constant ACRDX_MIN_PRICE = 255_048_500_000_000_000;
    uint256 public constant ACRDX_MAX_PRICE = 3_570_679_000_000_000_000;
    uint256 public constant JAAA_MIN_PRICE = 260_227_750_000_000_000;
    uint256 public constant JAAA_MAX_PRICE = 3_643_188_500_000_000_000;
    uint256 public constant JTRSY_MIN_PRICE = 277_407_000_000_000_000;
    uint256 public constant JTRSY_MAX_PRICE = 3_883_698_000_000_000_000;
    uint256 public constant DECRDX_MIN_PRICE = 249_774_250_000_000_000;
    uint256 public constant DECRDX_MAX_PRICE = 3_496_839_500_000_000_000;
    uint256 public constant DEJAAA_MIN_PRICE = 259_851_500_000_000_000;
    uint256 public constant DEJAAA_MAX_PRICE = 3_637_921_000_000_000_000;
    uint256 public constant DEJTRSY_MIN_PRICE = 257_720_000_000_000_000;
    uint256 public constant DEJTRSY_MAX_PRICE = 3_608_080_000_000_000_000;
    uint256 public constant HYBOND_MIN_PRICE = 867_172_000_000_000_000;
    uint256 public constant HYBOND_MAX_PRICE = 12_140_408_000_000_000_000;
    uint256 public constant PRIME_MIN_PRICE = 524_708_500_000_000_000;
    uint256 public constant PRIME_MAX_PRICE = 7_345_919_000_000_000_000;
    uint256 public constant AUTO_MIN_PRICE = 502_733_000_000_000_000;
    uint256 public constant AUTO_MAX_PRICE = 7_038_262_000_000_000_000;

    function run() public returns (LiquidLane2DeploymentData memory data) {
        _validateDeploymentParams();

        _startBroadcast();

        data.acrdx = _deployACRDX();
        data.jaaa = _deployJAAA();
        data.jtrsy = _deployJTRSY();
        data.deCRDX = _deployDeCRDX();
        data.deJAAA = _deployDeJAAA();
        data.deJTRSY = _deployDeJTRSY();
        data.hybond = _deployHYBOND();
        data.prime = _deployPRIME();
        data.autoToken = _deployAUTO();
        data.mGlobal = _deployMGlobal();

        _stopBroadcast();

        _validateDeployment(data);
        _logDeployment(data);
    }

    function _deployACRDX() internal returns (AccountDeploymentData memory data) {
        data.factory = address(new ACRDX_AccountFactory(_scriptOwner()));
        address asyncRedeemVault = IERC7575Share(ACRDX).vault(USDC);
        data.oracle = address(new AsyncRedeemOracle(ACRDX_MIN_PRICE, ACRDX_MAX_PRICE, ACRDX, asyncRedeemVault));
        data.implementation =
            address(new ACRDX_Account(data.oracle, data.factory, USDC, asyncRedeemVault, COW_SWAP_SETTLEMENT));
        _whitelistAndTransferOwnership(data);
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

    function _deployDeCRDX() internal returns (AccountDeploymentData memory data) {
        data.factory = address(new deCRDX_AccountFactory(_scriptOwner()));
        address asyncRedeemVault = IERC7575Share(DECRDX).vault(USDC);
        data.oracle = address(new AsyncRedeemOracle(DECRDX_MIN_PRICE, DECRDX_MAX_PRICE, DECRDX, asyncRedeemVault));
        data.implementation =
            address(new deCRDX_Account(data.oracle, data.factory, USDC, asyncRedeemVault, COW_SWAP_SETTLEMENT));
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

    function _deployAUTO() internal returns (AccountDeploymentData memory data) {
        data.factory = address(new AUTO_AccountFactory(_scriptOwner()));
        data.oracle = address(new FigureOracle(AUTO_MIN_PRICE, AUTO_MAX_PRICE, AUTO));
        data.implementation = address(
            new AUTO_Account(data.oracle, data.factory, AUTO, address(new FigureSubAccount(AUTO)), COW_SWAP_SETTLEMENT)
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

    function _validateDeploymentParams() internal pure {
        require(FACTORIES_OWNER != address(0), "invalid factories owner");
        require(COW_SWAP_SETTLEMENT != address(0), "invalid cow swap settlement");
        require(USDC != address(0), "invalid usdc");
    }

    function _validateDeployment(LiquidLane2DeploymentData memory data) internal view {
        _validateAccountDeployment(ACRDX, ACRDX_MIN_PRICE, ACRDX_MAX_PRICE, data.acrdx);
        _validateAccountDeployment(JAAA, JAAA_MIN_PRICE, JAAA_MAX_PRICE, data.jaaa);
        _validateAccountDeployment(JTRSY, JTRSY_MIN_PRICE, JTRSY_MAX_PRICE, data.jtrsy);
        _validateAccountDeployment(DECRDX, DECRDX_MIN_PRICE, DECRDX_MAX_PRICE, data.deCRDX);
        _validateAccountDeployment(DEJAAA, DEJAAA_MIN_PRICE, DEJAAA_MAX_PRICE, data.deJAAA);
        _validateAccountDeployment(DEJTRSY, DEJTRSY_MIN_PRICE, DEJTRSY_MAX_PRICE, data.deJTRSY);
        _validateHYBONDDeployment(data.hybond);
        _validateFigureDeployment(PRIME, PRIME_MIN_PRICE, PRIME_MAX_PRICE, data.prime);
        _validateFigureDeployment(AUTO, AUTO_MIN_PRICE, AUTO_MAX_PRICE, data.autoToken);
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

        _validateCommonAccountDeployment(data);
        assert(IAccount(data.implementation).TOKEN_TO_REDEEM() == tokenToRedeem);
        assert(IAsyncRedeemAccount(data.implementation).REDEMPTION_TOKEN() == USDC);
        assert(CentrifugeAccount(data.implementation).ASYNC_REDEEM_VAULT() == asyncRedeemVault);
        assert(ICooldownAccount(data.implementation).COOLDOWN() == 0);
        assert(IAsyncRedeemVault(asyncRedeemVault).asset() == USDC);
        assert(oracle.ASYNC_REDEEM_VAULT() == asyncRedeemVault);
        assert(oracle.MIN_PRICE() == minPrice);
        assert(oracle.MAX_PRICE() == maxPrice);
        assert(oracle.getPrice() > 0);
    }

    function _validateHYBONDDeployment(AccountDeploymentData memory data) internal view {
        OpenEdenOracle oracle = OpenEdenOracle(data.oracle);

        _validateCommonAccountDeployment(data);
        assert(IAccount(data.implementation).TOKEN_TO_REDEEM() == HYBOND);
        assert(IOpenEdenAccount(data.implementation).EXPRESS() == HYBOND_EXPRESS);
        assert(ICooldownAccount(data.implementation).COOLDOWN() == HYBOND_COOLDOWN);
        assert(IOpenEdenExpress(HYBOND_EXPRESS).redeemAsset() == USDC);
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
        assert(IFigureYieldVault(asyncRedeemVault).asset() == USDC);
        assert(oracle.TOKEN_TO_REDEEM() == tokenToRedeem);
        assert(oracle.ASYNC_REDEEM_VAULT() == asyncRedeemVault);
        assert(oracle.MIN_PRICE() == minPrice);
        assert(oracle.MAX_PRICE() == maxPrice);
        assert(oracle.getPrice() > 0);
    }

    function _validateMGlobalDeployment(AccountDeploymentData memory data) internal view {
        _validateCommonAccountDeployment(data);
        assert(IAccount(data.implementation).TOKEN_TO_REDEEM() == MGLOBAL);
        assert(ICooldownAccount(data.implementation).COOLDOWN() == MGLOBAL_COOLDOWN);
        assert(IMidasAccount(data.implementation).REDEMPTION_VAULT() == MGLOBAL_REDEMPTION_VAULT);
        assert(IMidasAccount(data.implementation).REDEMPTION_TOKEN() == USDC);
        assert(IMidasOracle(data.oracle).DATA_FEED() == MGLOBAL_DATA_FEED);
        assert(address(IMidasRedemptionVault(MGLOBAL_REDEMPTION_VAULT).mTokenDataFeed()) == MGLOBAL_DATA_FEED);
        assert(
            IMGlobalAdjustedAggregator(IMidasDataFeed(MGLOBAL_DATA_FEED).aggregator()).underlyingFeed()
                == MGLOBAL_MARKET_AGGREGATOR
        );
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
        _logAccountDeployment("ACRDX", data.acrdx);
        _logAccountDeployment("JAAA", data.jaaa);
        _logAccountDeployment("JTRSY", data.jtrsy);
        _logAccountDeployment("deCRDX", data.deCRDX);
        _logAccountDeployment("deJAAA", data.deJAAA);
        _logAccountDeployment("deJTRSY", data.deJTRSY);
        _logAccountDeployment("HYBOND", data.hybond);
        _logAccountDeployment("PRIME", data.prime);
        _logAccountDeployment("AUTO", data.autoToken);
        _logAccountDeployment("mGLOBAL", data.mGlobal);
        Logs.log(
            "Next: register each token -> factory in the AccountRegistry, then for HYBOND have OpenEden KYC-list the"
            " LiquidLaneAdapter proxy, every created account proxy, and all HYBOND transfer counterparties before"
            " enabling a limit (HYBOND transfers and Express redemptions revert for non-KYC'd addresses)."
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
