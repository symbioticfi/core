// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {DeployAdapterBase} from "./base/DeployAdapterBase.sol";

import {AdapterFactory} from "../../../src/contracts/adapters/AdapterFactory.sol";
import {LiquidLaneAdapter} from "../../../src/contracts/adapters/LiquidLaneAdapter.sol";
import {AccountRegistry} from "../../../src/contracts/adapters/ll-adapter/AccountRegistry.sol";
import {FigureSubAccount} from "../../../src/contracts/adapters/ll-adapter/FigureAccount.sol";
import {FigureOracle} from "../../../src/contracts/adapters/ll-adapter/oracles/FigureOracle.sol";
import {
    AUTO_Account,
    AUTO_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/AUTO_Account.sol";
import {
    CarryTradeUSDTRYLeverage_Account,
    CarryTradeUSDTRYLeverage_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/CarryTradeUSDTRYLeverage_Account.sol";
import {
    StockMarketTRBasisTrade_Account,
    StockMarketTRBasisTrade_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/StockMarketTRBasisTrade_Account.sol";
import {
    mFONE_Account,
    mFONE_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mFONE_Account.sol";
import {
    mGLOBAL_Account,
    mGLOBAL_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mGLOBAL_Account.sol";
import {
    mHYPER_Account,
    mHYPER_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mHYPER_Account.sol";
import {
    mM1USD_Account,
    mM1USD_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mM1USD_Account.sol";
import {
    mROX_Account,
    mROX_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mROX_Account.sol";
import {MigratablesFactory} from "../../../src/contracts/common/MigratablesFactory.sol";
import {IAccount} from "../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {IFigureYieldVault} from "../../../src/interfaces/adapters/ll-adapter/figure/IFigureYieldVault.sol";
import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {Logs} from "../../utils/Logs.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// forge script script/deploy/adapters/DeployLiquidLane.s.sol:DeployLiquidLaneScript --rpc-url=RPC --broadcast

contract DeployLiquidLaneScript is DeployAdapterBase {
    struct AccountDeploymentData {
        address factory;
        address implementation;
    }

    struct LiquidLaneDeploymentData {
        address accountRegistry;
        address liquidLaneAdapterFactory;
        address liquidLaneAdapterImplementation;
        AccountDeploymentData mGLOBAL;
        AccountDeploymentData mFONE;
        AccountDeploymentData mROX;
        AccountDeploymentData mHYPER;
        AccountDeploymentData carryTradeUSDTRY;
        AccountDeploymentData stockMarketTRBasisTrade;
        AccountDeploymentData mM1USD;
        AccountDeploymentData autoAccount;
        address autoOracle;
        address autoSubAccountImplementation;
    }

    // Configurations - UPDATE ACCOUNT_REGISTRY_OWNER BEFORE DEPLOYMENT.

    // Address that will own the account registry after deployment.
    address public constant ACCOUNT_REGISTRY_OWNER = 0x0000000000000000000000000000000000000000;
    // Address that will own all factories after deployment.
    address public constant FACTORIES_OWNER = 0x0000000000000000000000000000000000000000;

    address public constant COW_SWAP_SETTLEMENT = 0x9008D19f58AAbD9eD0D60971565AA8510560ab41;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant AUTO = 0x997E2Efbce91D170B00EA402e35a66C887EE1da9;
    address public constant WYLDS = 0x6aD038cA6C04e885630851278ca0a856Ad9a66Cc;
    uint256 public constant AUTO_MIN_PRICE = 0.5e18;
    uint256 public constant AUTO_MAX_PRICE = 2e18;

    address public constant MGLOBAL = 0x7433806912Eae67919e66aea853d46Fa0aef98A8;
    address public constant MFONE = 0x238a700eD6165261Cf8b2e544ba797BC11e466Ba;
    address public constant MROX = 0x67E1F506B148d0Fc95a4E3fFb49068ceB6855c05;
    address public constant MHYPER = 0x9b5528528656DBC094765E2abB79F293c21191B9;
    address public constant CARRY_TRADE_USD_TRY = 0x2bf11d2E04Bc40daa95c24B8b90EC4F5c57Dd326;
    address public constant STOCK_MARKET_TR_BASIS_TRADE = 0x827Ce7E8e35861D9Ac7fE002755767b695A5594a;
    address public constant MM1_USD = 0xCc5C22C7A6BCC25e66726AeF011dDE74289ED203;

    function run() public returns (LiquidLaneDeploymentData memory data) {
        address accountRegistryOwner = ACCOUNT_REGISTRY_OWNER;
        address factoriesOwner = FACTORIES_OWNER;
        _validateDeploymentParams(accountRegistryOwner, factoriesOwner);

        address scriptOwner = _scriptOwner();
        address vaultFactory = _coreVaultFactory();

        _startBroadcast();

        data.accountRegistry = address(new AccountRegistry(scriptOwner));

        data.liquidLaneAdapterFactory = address(new AdapterFactory(scriptOwner));
        data.liquidLaneAdapterImplementation =
            address(new LiquidLaneAdapter(vaultFactory, data.liquidLaneAdapterFactory, data.accountRegistry));
        AdapterFactory(data.liquidLaneAdapterFactory).whitelist(data.liquidLaneAdapterImplementation);

        data.mGLOBAL = _deployMGlobal(data.accountRegistry);
        data.mFONE = _deployMFONE(data.accountRegistry);
        data.mROX = _deployMROX(data.accountRegistry);
        data.mHYPER = _deployMHYPER(data.accountRegistry);
        data.carryTradeUSDTRY = _deployCarryTradeUSDTRY(data.accountRegistry);
        data.stockMarketTRBasisTrade = _deployStockMarketTRBasisTrade(data.accountRegistry);
        data.mM1USD = _deployMM1USD(data.accountRegistry);
        (data.autoAccount, data.autoOracle, data.autoSubAccountImplementation) = _deployAUTO(data.accountRegistry);

        _transferOwnership(data, accountRegistryOwner, factoriesOwner);

        _stopBroadcast();

        _validateDeployment(data, accountRegistryOwner, factoriesOwner);
        _logDeployment(data);
    }

    function _deployMGlobal(address accountRegistry) internal returns (AccountDeploymentData memory data) {
        data.factory = address(new mGLOBAL_AccountFactory(_scriptOwner()));
        data.implementation = address(new mGLOBAL_Account(data.factory, COW_SWAP_SETTLEMENT));
        _whitelistAndRegister(accountRegistry, MGLOBAL, data);
    }

    function _deployMFONE(address accountRegistry) internal returns (AccountDeploymentData memory data) {
        data.factory = address(new mFONE_AccountFactory(_scriptOwner()));
        data.implementation = address(new mFONE_Account(data.factory, COW_SWAP_SETTLEMENT));
        _whitelistAndRegister(accountRegistry, MFONE, data);
    }

    function _deployMROX(address accountRegistry) internal returns (AccountDeploymentData memory data) {
        data.factory = address(new mROX_AccountFactory(_scriptOwner()));
        data.implementation = address(new mROX_Account(data.factory, COW_SWAP_SETTLEMENT));
        _whitelistAndRegister(accountRegistry, MROX, data);
    }

    function _deployMHYPER(address accountRegistry) internal returns (AccountDeploymentData memory data) {
        data.factory = address(new mHYPER_AccountFactory(_scriptOwner()));
        data.implementation = address(new mHYPER_Account(data.factory, COW_SWAP_SETTLEMENT));
        _whitelistAndRegister(accountRegistry, MHYPER, data);
    }

    function _deployCarryTradeUSDTRY(address accountRegistry) internal returns (AccountDeploymentData memory data) {
        data.factory = address(new CarryTradeUSDTRYLeverage_AccountFactory(_scriptOwner()));
        data.implementation = address(new CarryTradeUSDTRYLeverage_Account(data.factory, COW_SWAP_SETTLEMENT));
        _whitelistAndRegister(accountRegistry, CARRY_TRADE_USD_TRY, data);
    }

    function _deployStockMarketTRBasisTrade(address accountRegistry)
        internal
        returns (AccountDeploymentData memory data)
    {
        data.factory = address(new StockMarketTRBasisTrade_AccountFactory(_scriptOwner()));
        data.implementation = address(new StockMarketTRBasisTrade_Account(data.factory, COW_SWAP_SETTLEMENT));
        _whitelistAndRegister(accountRegistry, STOCK_MARKET_TR_BASIS_TRADE, data);
    }

    function _deployMM1USD(address accountRegistry) internal returns (AccountDeploymentData memory data) {
        data.factory = address(new mM1USD_AccountFactory(_scriptOwner()));
        data.implementation = address(new mM1USD_Account(data.factory, COW_SWAP_SETTLEMENT));
        _whitelistAndRegister(accountRegistry, MM1_USD, data);
    }

    function _deployAUTO(address accountRegistry)
        internal
        returns (AccountDeploymentData memory data, address oracle, address subAccountImplementation)
    {
        data.factory = address(new AUTO_AccountFactory(_scriptOwner()));
        oracle = address(new FigureOracle(AUTO_MIN_PRICE, AUTO_MAX_PRICE, AUTO));
        subAccountImplementation = address(new FigureSubAccount(AUTO));
        data.implementation =
            address(new AUTO_Account(oracle, data.factory, AUTO, subAccountImplementation, COW_SWAP_SETTLEMENT));
        _whitelistAndRegister(accountRegistry, AUTO, data);
    }

    function _whitelistAndRegister(address accountRegistry, address tokenToRedeem, AccountDeploymentData memory data)
        internal
    {
        MigratablesFactory(data.factory).whitelist(data.implementation);
        AccountRegistry(accountRegistry).setAccountFactory(USDC, tokenToRedeem, data.factory);
    }

    function _transferOwnership(
        LiquidLaneDeploymentData memory data,
        address accountRegistryOwner,
        address factoriesOwner
    ) internal {
        address scriptOwner = _scriptOwner();

        if (accountRegistryOwner != scriptOwner) {
            Ownable(data.accountRegistry).transferOwnership(accountRegistryOwner);
        }

        if (factoriesOwner == scriptOwner) {
            return;
        }

        Ownable(data.liquidLaneAdapterFactory).transferOwnership(factoriesOwner);
        _transferAccountFactoryOwnership(data.mGLOBAL, factoriesOwner);
        _transferAccountFactoryOwnership(data.mFONE, factoriesOwner);
        _transferAccountFactoryOwnership(data.mROX, factoriesOwner);
        _transferAccountFactoryOwnership(data.mHYPER, factoriesOwner);
        _transferAccountFactoryOwnership(data.carryTradeUSDTRY, factoriesOwner);
        _transferAccountFactoryOwnership(data.stockMarketTRBasisTrade, factoriesOwner);
        _transferAccountFactoryOwnership(data.mM1USD, factoriesOwner);
        _transferAccountFactoryOwnership(data.autoAccount, factoriesOwner);
    }

    function _transferAccountFactoryOwnership(AccountDeploymentData memory data, address owner) internal {
        Ownable(data.factory).transferOwnership(owner);
    }

    function _validateDeploymentParams(address accountRegistryOwner, address factoriesOwner) internal pure {
        require(accountRegistryOwner != address(0), "invalid account registry owner");
        require(factoriesOwner != address(0), "invalid factories owner");
        require(accountRegistryOwner != factoriesOwner, "owners must differ");
        require(COW_SWAP_SETTLEMENT != address(0), "invalid cow swap settlement");
        require(USDC != address(0), "invalid usdc");
        require(AUTO != address(0), "invalid auto");
        require(WYLDS != address(0), "invalid wylds");
    }

    function _validateDeployment(
        LiquidLaneDeploymentData memory data,
        address accountRegistryOwner,
        address factoriesOwner
    ) internal view {
        assert(Ownable(data.accountRegistry).owner() == accountRegistryOwner);
        assert(Ownable(data.liquidLaneAdapterFactory).owner() == factoriesOwner);
        assert(IMigratableEntity(data.liquidLaneAdapterImplementation).FACTORY() == data.liquidLaneAdapterFactory);
        assert(AdapterFactory(data.liquidLaneAdapterFactory).implementation(1) == data.liquidLaneAdapterImplementation);

        _validateAccountDeployment(data.accountRegistry, MGLOBAL, data.mGLOBAL, factoriesOwner);
        _validateAccountDeployment(data.accountRegistry, MFONE, data.mFONE, factoriesOwner);
        _validateAccountDeployment(data.accountRegistry, MROX, data.mROX, factoriesOwner);
        _validateAccountDeployment(data.accountRegistry, MHYPER, data.mHYPER, factoriesOwner);
        _validateAccountDeployment(data.accountRegistry, CARRY_TRADE_USD_TRY, data.carryTradeUSDTRY, factoriesOwner);
        _validateAccountDeployment(
            data.accountRegistry, STOCK_MARKET_TR_BASIS_TRADE, data.stockMarketTRBasisTrade, factoriesOwner
        );
        _validateAccountDeployment(data.accountRegistry, MM1_USD, data.mM1USD, factoriesOwner);
        _validateAccountDeployment(data.accountRegistry, AUTO, data.autoAccount, factoriesOwner);
        _validateAUTODeployment(data.autoAccount, data.autoOracle, data.autoSubAccountImplementation);
    }

    function _validateAUTODeployment(
        AccountDeploymentData memory data,
        address oracleAddress,
        address subAccountImplementation
    ) internal view {
        IAccount implementation = IAccount(data.implementation);
        FigureOracle oracle = FigureOracle(oracleAddress);

        assert(implementation.TOKEN_TO_REDEEM() == AUTO);
        assert(implementation.ORACLE() == oracleAddress);
        assert(oracleAddress.code.length > 0);
        assert(subAccountImplementation.code.length > 0);
        assert(IERC4626(AUTO).asset() == WYLDS);
        assert(IFigureYieldVault(WYLDS).asset() == USDC);
        assert(oracle.TOKEN_TO_REDEEM() == AUTO);
        assert(oracle.ASYNC_REDEEM_VAULT() == WYLDS);
        assert(oracle.MIN_PRICE() == AUTO_MIN_PRICE);
        assert(oracle.MAX_PRICE() == AUTO_MAX_PRICE);

        uint256 tokenUnit = 10 ** IERC20Metadata(AUTO).decimals();
        uint256 nestedShares = IERC4626(AUTO).convertToAssets(tokenUnit);
        uint256 redemptionAssets = IFigureYieldVault(WYLDS).convertToAssets(nestedShares);
        uint256 expectedPrice = Math.mulDiv(redemptionAssets, 1e18, 10 ** IERC20Metadata(USDC).decimals());
        assert(oracle.getPrice() == expectedPrice);
    }

    function _validateAccountDeployment(
        address accountRegistry,
        address tokenToRedeem,
        AccountDeploymentData memory data,
        address owner
    ) internal view {
        assert(Ownable(data.factory).owner() == owner);
        assert(IMigratableEntity(data.implementation).FACTORY() == data.factory);
        assert(MigratablesFactory(data.factory).implementation(1) == data.implementation);
        assert(AccountRegistry(accountRegistry).accountFactories(USDC, tokenToRedeem) == data.factory);
    }

    function _logDeployment(LiquidLaneDeploymentData memory data) internal {
        Logs.log(
            string.concat(
                "Deployed LiquidLane",
                "\n    accountRegistry:",
                vm.toString(data.accountRegistry),
                "\n    liquidLaneAdapterFactory:",
                vm.toString(data.liquidLaneAdapterFactory),
                "\n    liquidLaneAdapterImplementation:",
                vm.toString(data.liquidLaneAdapterImplementation)
            )
        );

        _logAccountDeployment("mGLOBAL", data.mGLOBAL);
        _logAccountDeployment("mF-ONE", data.mFONE);
        _logAccountDeployment("mROX", data.mROX);
        _logAccountDeployment("mHYPER", data.mHYPER);
        _logAccountDeployment("CarryTradeUSDTRY", data.carryTradeUSDTRY);
        _logAccountDeployment("StockMarketTRBasisTrade", data.stockMarketTRBasisTrade);
        _logAccountDeployment("mM1-USD", data.mM1USD);
        _logAUTODeployment(data.autoAccount, data.autoOracle, data.autoSubAccountImplementation);
    }

    function _logAUTODeployment(AccountDeploymentData memory data, address oracle, address subAccountImplementation)
        internal
    {
        Logs.log(
            string.concat(
                "Deployed AUTO account",
                "\n    accountFactory:",
                vm.toString(data.factory),
                "\n    accountImplementation:",
                vm.toString(data.implementation),
                "\n    oracle:",
                vm.toString(oracle),
                "\n    subAccountImplementation:",
                vm.toString(subAccountImplementation)
            )
        );
    }

    function _logAccountDeployment(string memory name, AccountDeploymentData memory data) internal {
        Logs.log(
            string.concat(
                "Deployed ",
                name,
                " account",
                "\n    accountFactory:",
                vm.toString(data.factory),
                "\n    accountImplementation:",
                vm.toString(data.implementation)
            )
        );
    }
}
