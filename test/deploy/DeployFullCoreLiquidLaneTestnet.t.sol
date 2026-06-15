// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {DeployFullCoreLiquidLaneTestnetScript} from "../../script/deploy/testnet/DeployFullCoreLiquidLaneTestnet.s.sol";
import {TestnetVaultFactory} from "../../script/deploy/testnet/TestnetVaultFactory.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {MigratableEntity} from "../../src/contracts/common/MigratableEntity.sol";
import {MigratableEntityProxy} from "../../src/contracts/common/MigratableEntityProxy.sol";
import {IMigratableEntity} from "../../src/interfaces/common/IMigratableEntity.sol";
import {IMigratablesFactory} from "../../src/interfaces/common/IMigratablesFactory.sol";
import {IAaveV3Adapter} from "../../src/interfaces/adapters/IAaveV3Adapter.sol";
import {IAppAdapter} from "../../src/interfaces/adapters/IAppAdapter.sol";
import {ILiquidLaneAdapter} from "../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IMorphoVaultV2Adapter} from "../../src/interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {IAccountRegistry} from "../../src/interfaces/adapters/ll-adapter/IAccountRegistry.sol";
import {IUniversalDelegator, MAX_SHARE} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../../src/interfaces/vault/IVaultV2.sol";
import {MockAavePool, MockMorphoVaultFactory} from "../mocks/HoodiScenarioProtocolMocks.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DeployFullCoreLiquidLaneTestnetScriptHarness is DeployFullCoreLiquidLaneTestnetScript {
    function _broadcast() internal pure override returns (bool) {
        return false;
    }

    function _scriptOwner() internal view override returns (address) {
        return address(this);
    }
}

contract TestnetRegistryStateEntity is MigratableEntity {
    bool public wasEntityDuringInitialize;
    uint256 public totalEntitiesDuringInitialize;

    constructor(address factory) MigratableEntity(factory) {}

    function _initialize(uint64, address, bytes memory) internal override {
        wasEntityDuringInitialize = IMigratablesFactory(FACTORY).isEntity(address(this));
        totalEntitiesDuringInitialize = IMigratablesFactory(FACTORY).totalEntities();
    }
}

contract DeployFullCoreLiquidLaneTestnetTest is Test {
    function test_DeploysConfigurableFullTestnetStackWithMocks() public {
        DeployFullCoreLiquidLaneTestnetScriptHarness script = new DeployFullCoreLiquidLaneTestnetScriptHarness();
        address owner = address(script);

        DeployFullCoreLiquidLaneTestnetScript.DeploymentData memory data = script.runBase(
            DeployFullCoreLiquidLaneTestnetScript.DeployParams({
                owner: owner,
                marketMaker: owner,
                cowSwapSettlement: address(0),
                cowSwapVaultRelayer: address(0),
                usdc: address(0),
                aUsd: address(0),
                mFone: address(0),
                mGlobal: address(0),
                mFoneRedemptionVault: address(0),
                mGlobalRedemptionVault: address(0),
                mintAmount: 1_000_000e18,
                liquidLaneLimit: 100_000e6,
                minDiscount: 1000
            })
        );

        assertEq(Ownable(address(data.core.vaultFactory)).owner(), owner);
        assertEq(address(data.core.vaultFactory).codehash, keccak256(type(TestnetVaultFactory).runtimeCode));
        assertEq(Ownable(address(data.core.delegatorFactory)).owner(), owner);
        assertEq(Ownable(address(data.v2.adapterRegistry)).owner(), owner);

        assertGt(data.tokens.usdc.code.length, 0);
        assertGt(data.tokens.aUsd.code.length, 0);
        assertGt(data.tokens.mFone.code.length, 0);
        assertGt(data.tokens.mGlobal.code.length, 0);
        assertGt(data.cowSwap.settlement.code.length, 0);
        assertGt(data.cowSwap.vaultRelayer.code.length, 0);

        _assertVault(data.liquidLane.usdcVault, data.tokens.usdc, data.liquidLane.usdcDelegator);
        _assertVault(data.liquidLane.aUsdVault, data.tokens.aUsd, data.liquidLane.aUsdDelegator);
        _assertTestnetVaultCreate2Address(
            data, 0, owner, data.liquidLane.usdcVault, data.tokens.usdc, "Testnet USDC Vault", "tUSDC-V"
        );
        _assertTestnetVaultCreate2Address(
            data, 1, owner, data.liquidLane.aUsdVault, data.tokens.aUsd, "Testnet aUSD Vault", "taUSD-V"
        );

        _assertAdapter(
            data.liquidLane.usdcAdapter,
            data.liquidLane.usdcVault,
            data.liquidLane.usdcDelegator,
            data.accounts.accountRegistry,
            data.tokens.usdc,
            data.tokens.mFone,
            data.tokens.mGlobal,
            data.accounts.mFoneAccountFactory,
            data.accounts.mGlobalAccountFactory,
            data.liquidLaneLimit,
            data.minDiscount
        );
        _assertAdapter(
            data.liquidLane.aUsdAdapter,
            data.liquidLane.aUsdVault,
            data.liquidLane.aUsdDelegator,
            data.accounts.accountRegistry,
            data.tokens.aUsd,
            data.tokens.mFone,
            data.tokens.mGlobal,
            data.accounts.mFoneAccountFactory,
            data.accounts.mGlobalAccountFactory,
            data.liquidLaneLimit,
            data.minDiscount
        );

        _assertFullFormDeployments(data, owner);
    }

    function test_TestnetVaultFactoryCreate2AddressUsesConstructorInitializeCalldata() public {
        TestnetVaultFactory factory = new TestnetVaultFactory(address(this));
        TestnetRegistryStateEntity implementation = new TestnetRegistryStateEntity(address(factory));
        factory.whitelist(address(implementation));

        address owner = address(0xBEEF);
        bytes memory data = abi.encode("constructor initialized");
        address expected = _computeProxyAddress(address(factory), address(implementation), 0, 1, owner, data, true);
        address legacyExpected =
            _computeProxyAddress(address(factory), address(implementation), 0, 1, owner, data, false);

        address entity = factory.create(1, owner, data);

        assertEq(entity, expected);
        assertNotEq(entity, legacyExpected);
        assertEq(factory.entity(0), entity);
    }

    function test_TestnetVaultFactoryInitializesBeforeRegisteringEntity() public {
        TestnetVaultFactory factory = new TestnetVaultFactory(address(this));
        TestnetRegistryStateEntity implementation = new TestnetRegistryStateEntity(address(factory));
        factory.whitelist(address(implementation));

        address entity = factory.create(1, address(this), "");

        assertFalse(TestnetRegistryStateEntity(entity).wasEntityDuringInitialize());
        assertEq(TestnetRegistryStateEntity(entity).totalEntitiesDuringInitialize(), 0);
        assertTrue(factory.isEntity(entity));
        assertEq(factory.totalEntities(), 1);
    }

    function _assertTestnetVaultCreate2Address(
        DeployFullCoreLiquidLaneTestnetScript.DeploymentData memory data,
        uint256 entityIndex,
        address owner,
        address vault,
        address asset,
        string memory name,
        string memory symbol
    ) internal view {
        bytes memory vaultParams = _vaultParams(owner, asset, name, symbol);
        address expected = _computeProxyAddress(
            address(data.core.vaultFactory),
            address(data.v2.vaultV2),
            entityIndex,
            VAULT_V2_VERSION,
            owner,
            vaultParams,
            true
        );
        address legacyExpected = _computeProxyAddress(
            address(data.core.vaultFactory),
            address(data.v2.vaultV2),
            entityIndex,
            VAULT_V2_VERSION,
            owner,
            vaultParams,
            false
        );

        assertEq(vault, expected);
        assertNotEq(vault, legacyExpected);
        assertEq(data.core.vaultFactory.entity(entityIndex), vault);
    }

    function _computeProxyAddress(
        address factory,
        address implementation,
        uint256 entityIndex,
        uint64 version,
        address owner,
        bytes memory data,
        bool constructorInitializes
    ) internal view returns (address) {
        bytes memory proxyConstructorData = constructorInitializes
            ? abi.encodeCall(IMigratableEntity.initialize, (version, owner, data))
            : bytes("");
        bytes32 salt = keccak256(abi.encode(entityIndex, version, owner, data));
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(MigratableEntityProxy).creationCode, abi.encode(implementation, proxyConstructorData))
        );
        return vm.computeCreate2Address(salt, initCodeHash, factory);
    }

    function _vaultParams(address owner, address asset, string memory name, string memory symbol)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(
            IVaultV2.InitParams({
                name: name,
                symbol: symbol,
                asset: asset,
                depositWhitelist: false,
                depositorToWhitelist: address(0),
                depositLimit: type(uint256).max,
                isDepositLimit: true,
                defaultAdminRoleHolder: owner,
                managementFeeRoleHolder: owner,
                performanceFeeRoleHolder: owner,
                depositLimitSetRoleHolder: owner,
                depositorWhitelistRoleHolder: owner,
                isDepositLimitSetRoleHolder: owner,
                depositWhitelistSetRoleHolder: owner
            })
        );
    }

    function _assertFullFormDeployments(DeployFullCoreLiquidLaneTestnetScript.DeploymentData memory data, address owner)
        internal
        view
    {
        assertGt(data.fullAdapters.appAdapterFactory.code.length, 0);
        assertGt(data.fullAdapters.appAdapterImplementation.code.length, 0);
        assertGt(data.fullAdapters.aaveAdapterFactory.code.length, 0);
        assertGt(data.fullAdapters.aaveAdapterImplementation.code.length, 0);
        assertGt(data.fullAdapters.morphoAdapterFactory.code.length, 0);
        assertGt(data.fullAdapters.morphoAdapterImplementation.code.length, 0);
        assertEq(Ownable(data.fullAdapters.appAdapterFactory).owner(), owner);
        assertEq(Ownable(data.fullAdapters.aaveAdapterFactory).owner(), owner);
        assertEq(Ownable(data.fullAdapters.morphoAdapterFactory).owner(), owner);
        assertEq(
            AdapterFactory(data.fullAdapters.appAdapterFactory).implementation(1),
            data.fullAdapters.appAdapterImplementation
        );
        assertEq(
            AdapterFactory(data.fullAdapters.aaveAdapterFactory).implementation(1),
            data.fullAdapters.aaveAdapterImplementation
        );
        assertEq(
            AdapterFactory(data.fullAdapters.morphoAdapterFactory).implementation(1),
            data.fullAdapters.morphoAdapterImplementation
        );

        assertGt(data.fullAdapters.burnerRouterFactory.code.length, 0);
        assertGt(data.fullAdapters.mockSwapRouter.code.length, 0);
        assertGt(data.fullAdapters.usdcBurner.code.length, 0);
        assertGt(data.fullAdapters.aUsdBurner.code.length, 0);

        assertEq(
            MockAavePool(data.fullAdapters.mockAavePool).getReserveAToken(data.tokens.usdc),
            data.fullAdapters.mockAaveUsdcAToken
        );
        assertEq(
            MockAavePool(data.fullAdapters.mockAavePool).getReserveAToken(data.tokens.aUsd),
            data.fullAdapters.mockAaveAusdAToken
        );
        assertEq(IAaveV3Adapter(data.fullAdapters.usdcAaveAdapter).aToken(), data.fullAdapters.mockAaveUsdcAToken);
        assertEq(IAaveV3Adapter(data.fullAdapters.aUsdAaveAdapter).aToken(), data.fullAdapters.mockAaveAusdAToken);

        assertTrue(
            MockMorphoVaultFactory(data.fullAdapters.mockMorphoVaultFactory)
                .isVaultV2(data.fullAdapters.mockMorphoVaultUsdc)
        );
        assertTrue(
            MockMorphoVaultFactory(data.fullAdapters.mockMorphoVaultFactory)
                .isVaultV2(data.fullAdapters.mockMorphoVaultAusd)
        );
        assertEq(
            IMorphoVaultV2Adapter(data.fullAdapters.usdcMorphoAdapter).morphoVault(),
            data.fullAdapters.mockMorphoVaultUsdc
        );
        assertEq(
            IMorphoVaultV2Adapter(data.fullAdapters.aUsdMorphoAdapter).morphoVault(),
            data.fullAdapters.mockMorphoVaultAusd
        );

        assertEq(IAppAdapter(data.fullAdapters.usdcAppAdapter).asset(), data.tokens.usdc);
        assertEq(IAppAdapter(data.fullAdapters.aUsdAppAdapter).asset(), data.tokens.aUsd);
        assertEq(IAppAdapter(data.fullAdapters.usdcAppAdapter).burner(), data.fullAdapters.usdcBurner);
        assertEq(IAppAdapter(data.fullAdapters.aUsdAppAdapter).burner(), data.fullAdapters.aUsdBurner);

        _assertDelegatorAdapters(
            data.liquidLane.usdcDelegator,
            data.liquidLane.usdcAdapter,
            data.fullAdapters.usdcAppAdapter,
            data.fullAdapters.usdcAaveAdapter,
            data.fullAdapters.usdcMorphoAdapter,
            data.liquidLaneLimit
        );
        _assertDelegatorAdapters(
            data.liquidLane.aUsdDelegator,
            data.liquidLane.aUsdAdapter,
            data.fullAdapters.aUsdAppAdapter,
            data.fullAdapters.aUsdAaveAdapter,
            data.fullAdapters.aUsdMorphoAdapter,
            data.liquidLaneLimit
        );
    }

    function _assertDelegatorAdapters(
        address delegator,
        address liquidLaneAdapter,
        address appAdapter,
        address aaveAdapter,
        address morphoAdapter,
        uint256 limit
    ) internal view {
        assertEq(IUniversalDelegator(delegator).getAdaptersLength(), 4);
        assertEq(IUniversalDelegator(delegator).adapters(0), liquidLaneAdapter);
        assertEq(IUniversalDelegator(delegator).adapters(1), appAdapter);
        assertEq(IUniversalDelegator(delegator).adapters(2), aaveAdapter);
        assertEq(IUniversalDelegator(delegator).adapters(3), morphoAdapter);

        _assertDelegatorLimit(delegator, appAdapter, limit);
        _assertDelegatorLimit(delegator, aaveAdapter, limit);
        _assertDelegatorLimit(delegator, morphoAdapter, limit);
    }

    function _assertDelegatorLimit(address delegator, address adapter, uint256 limit) internal view {
        assertEq(IUniversalDelegator(delegator).absoluteLimitOf(adapter), limit);
        assertEq(IUniversalDelegator(delegator).shareLimitOf(adapter), MAX_SHARE);
    }

    function _assertVault(address vault, address asset, address delegator) internal view {
        assertEq(IERC4626(vault).asset(), asset);
        assertEq(IVaultV2(vault).delegator(), delegator);
        assertEq(IUniversalDelegator(delegator).vault(), vault);
    }

    function _assertAdapter(
        address adapter,
        address vault,
        address delegator,
        address accountRegistry,
        address asset,
        address mFone,
        address mGlobal,
        address mFoneAccountFactory,
        address mGlobalAccountFactory,
        uint256 liquidLaneLimit,
        uint256 minDiscount
    ) internal view {
        assertEq(ILiquidLaneAdapter(adapter).vault(), vault);
        assertEq(IUniversalDelegator(delegator).adapters(0), adapter);
        assertEq(IUniversalDelegator(delegator).absoluteLimitOf(adapter), liquidLaneLimit);
        assertEq(IUniversalDelegator(delegator).shareLimitOf(adapter), MAX_SHARE);

        assertEq(IAccountRegistry(accountRegistry).accountFactories(asset, mFone), mFoneAccountFactory);
        assertEq(IAccountRegistry(accountRegistry).accountFactories(asset, mGlobal), mGlobalAccountFactory);
        assertEq(ILiquidLaneAdapter(adapter).getTokensToRedeemLength(), 2);
        assertEq(ILiquidLaneAdapter(adapter).tokensToRedeem(0), mFone);
        assertEq(ILiquidLaneAdapter(adapter).tokensToRedeem(1), mGlobal);
        assertGt(ILiquidLaneAdapter(adapter).accounts(mFone).code.length, 0);
        assertGt(ILiquidLaneAdapter(adapter).accounts(mGlobal).code.length, 0);
        assertEq(ILiquidLaneAdapter(adapter).limit(mFone), liquidLaneLimit);
        assertEq(ILiquidLaneAdapter(adapter).limit(mGlobal), liquidLaneLimit);
        assertEq(ILiquidLaneAdapter(adapter).minDiscount(mFone), minDiscount);
        assertEq(ILiquidLaneAdapter(adapter).minDiscount(mGlobal), minDiscount);
    }
}
