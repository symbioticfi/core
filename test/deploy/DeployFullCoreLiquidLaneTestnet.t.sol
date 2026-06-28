// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {
    DeployFullCoreLiquidLaneTestnetScript,
    TestnetBurnerRouterFactoryMock,
    TestnetERC20Mock
} from "../../script/deploy/testnet/DeployFullCoreLiquidLaneTestnet.s.sol";
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
import {IRestakingAppAdapter} from "../../src/interfaces/adapters/IRestakingAppAdapter.sol";
import {IMerklClaimer} from "../../src/interfaces/adapters/common/IMerklClaimer.sol";
import {IAccountRegistry} from "../../src/interfaces/adapters/ll-adapter/IAccountRegistry.sol";
import {IUniversalDelegator, MAX_SHARE} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../../src/interfaces/vault/IVaultV2.sol";
import {
    MockAaveAToken,
    MockAavePool,
    MockAavePoolDataProvider,
    MockMorphoAdapterRegistry,
    MockMorphoVaultFactory
} from "../mocks/HoodiScenarioProtocolMocks.sol";
import {Token} from "../mocks/Token.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    struct ExtraVault {
        address vault;
        address delegator;
        address appAdapter;
        address aaveAdapter;
        address morphoAdapter;
    }

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
                merklDistributor: address(0),
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
        _assertVault(
            data.fullAdapters.usdcRestakingVault, data.liquidLane.usdcVault, data.fullAdapters.usdcRestakingDelegator
        );
        _assertVault(
            data.fullAdapters.aUsdRestakingVault, data.liquidLane.aUsdVault, data.fullAdapters.aUsdRestakingDelegator
        );
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
        _assertMockProtocolsAreOwnerConfigurable(data.fullAdapters, owner);
    }

    function test_FullStackSupportsAdditionalConfiguredVaultsAndAllocatedAdapters() public {
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
                merklDistributor: address(0),
                mintAmount: 1_000_000e18,
                liquidLaneLimit: 500_000e6,
                minDiscount: 1000
            })
        );

        _assertLiquidLaneCanAllocateThroughSwap(data, owner);

        Token diversifiedAsset = new Token("Diversified Asset");
        ExtraVault memory diversifiedVault = _deployExtraVault(
            data,
            owner,
            address(diversifiedAsset),
            "Diversified Testnet Vault",
            "tDIV-V",
            false,
            address(0),
            400 ether,
            true
        );
        _configureAaveReserve(data.fullAdapters, owner, address(diversifiedAsset));
        address diversifiedMorphoVault = _configureMorphoVault(data.fullAdapters, owner, address(diversifiedAsset));
        diversifiedVault.aaveAdapter =
            _createAaveAdapter(data.fullAdapters.aaveAdapterFactory, owner, diversifiedVault.vault);
        diversifiedVault.morphoAdapter = _createMorphoAdapter(
            data.fullAdapters.morphoAdapterFactory, owner, diversifiedVault.vault, diversifiedMorphoVault
        );
        _attachAdapters(
            data,
            owner,
            diversifiedVault.vault,
            diversifiedVault.delegator,
            _twoAdapters(diversifiedVault.aaveAdapter, diversifiedVault.morphoAdapter),
            _twoLimits(120 ether, 280 ether),
            _twoAdapters(diversifiedVault.aaveAdapter, diversifiedVault.morphoAdapter)
        );

        diversifiedAsset.approve(diversifiedVault.vault, 300 ether);
        IERC4626(diversifiedVault.vault).deposit(300 ether, address(this));

        assertEq(IAaveV3Adapter(diversifiedVault.aaveAdapter).totalAssets(), 120 ether);
        assertEq(IMorphoVaultV2Adapter(diversifiedVault.morphoAdapter).totalAssets(), 180 ether);
        assertEq(IERC4626(diversifiedVault.vault).totalAssets(), 300 ether);

        Token appOnlyAsset = new Token("Whitelisted App Asset");
        ExtraVault memory appOnlyVault = _deployExtraVault(
            data,
            owner,
            address(appOnlyAsset),
            "Whitelisted App Testnet Vault",
            "tAPP-V",
            true,
            address(this),
            80 ether,
            true
        );
        appOnlyVault.appAdapter = _createAppAdapter(
            data.fullAdapters.appAdapterFactory, owner, appOnlyVault.vault, data.fullAdapters.usdcBurner, 7
        );
        _attachAdapters(
            data,
            owner,
            appOnlyVault.vault,
            appOnlyVault.delegator,
            _oneAdapter(appOnlyVault.appAdapter),
            _oneLimit(80 ether),
            _oneAdapter(appOnlyVault.appAdapter)
        );

        appOnlyAsset.approve(appOnlyVault.vault, 75 ether);
        IERC4626(appOnlyVault.vault).deposit(75 ether, address(this));

        assertEq(IAppAdapter(appOnlyVault.appAdapter).totalAssets(), 75 ether);
        assertEq(IAppAdapter(appOnlyVault.appAdapter).slashable(), 75 ether);
        assertEq(IERC4626(appOnlyVault.vault).totalAssets(), 75 ether);
        assertEq(IVaultV2(appOnlyVault.vault).depositWhitelist(), true);
        assertEq(IVaultV2(appOnlyVault.vault).depositLimit(), 80 ether);
        assertEq(IVaultV2(diversifiedVault.vault).depositWhitelist(), false);
        assertEq(IVaultV2(diversifiedVault.vault).depositLimit(), 400 ether);
    }

    function test_FullStackSupportsRestakingAppAdapterVaultSets() public {
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
                merklDistributor: address(0),
                mintAmount: 1_000_000e18,
                liquidLaneLimit: 500_000e6,
                minDiscount: 1000
            })
        );

        _assertRestakingSet(
            data.fullAdapters.usdcRestakingVault,
            data.fullAdapters.usdcRestakingDelegator,
            data.fullAdapters.usdcRestakingAppAdapter,
            data.liquidLane.usdcVault,
            data.tokens.usdc,
            data.fullAdapters.usdcBurner,
            data.liquidLaneLimit
        );
        _assertRestakingSet(
            data.fullAdapters.aUsdRestakingVault,
            data.fullAdapters.aUsdRestakingDelegator,
            data.fullAdapters.aUsdRestakingAppAdapter,
            data.liquidLane.aUsdVault,
            data.tokens.aUsd,
            data.fullAdapters.aUsdBurner,
            data.liquidLaneLimit
        );

        Token baseAsset = new Token("Nested Restaking Base Asset");
        ExtraVault memory baseVault = _deployExtraVault(
            data, owner, address(baseAsset), "Nested Restaking Base Vault", "tNRB-V", false, address(0), 500 ether, true
        );
        _configureLiquidLaneAccounts(data, owner, address(baseAsset));
        baseVault.appAdapter =
            _createLiquidLaneAdapter(data, owner, baseVault.vault, data.liquidLaneLimit, data.minDiscount);
        address baseMorphoVault = _configureMorphoVault(data.fullAdapters, owner, address(baseAsset));
        baseVault.morphoAdapter =
            _createMorphoAdapter(data.fullAdapters.morphoAdapterFactory, owner, baseVault.vault, baseMorphoVault);
        _attachAdapters(
            data,
            owner,
            baseVault.vault,
            baseVault.delegator,
            _twoAdapters(baseVault.appAdapter, baseVault.morphoAdapter),
            _twoLimits(200 ether, 300 ether),
            _oneAdapter(baseVault.morphoAdapter)
        );

        baseAsset.approve(baseVault.vault, 150 ether);
        uint256 baseVaultShares = IERC4626(baseVault.vault).deposit(150 ether, address(this));
        assertEq(IMorphoVaultV2Adapter(baseVault.morphoAdapter).totalAssets(), 150 ether);
        assertEq(ILiquidLaneAdapter(baseVault.appAdapter).vault(), baseVault.vault);

        ExtraVault memory restakingVault = _deployExtraVault(
            data,
            owner,
            baseVault.vault,
            "Nested Restaking App Vault",
            "tNRA-V",
            false,
            address(0),
            baseVaultShares,
            true
        );
        address baseBurner = _createBurner(data.fullAdapters.burnerRouterFactory, owner, address(baseAsset));
        restakingVault.appAdapter = _createRestakingAppAdapter(
            data.fullAdapters.restakingAppAdapterFactory,
            owner,
            restakingVault.vault,
            address(baseAsset),
            baseBurner,
            11
        );
        _attachAdapters(
            data,
            owner,
            restakingVault.vault,
            restakingVault.delegator,
            _oneAdapter(restakingVault.appAdapter),
            _oneLimit(baseVaultShares),
            _oneAdapter(restakingVault.appAdapter)
        );

        IERC20(baseVault.vault).approve(restakingVault.vault, baseVaultShares);
        IERC4626(restakingVault.vault).deposit(baseVaultShares, address(this));

        assertEq(IRestakingAppAdapter(restakingVault.appAdapter).underlyingVaults(0), baseVault.vault);
        assertEq(IAppAdapter(restakingVault.appAdapter).asset(), address(baseAsset));
        assertEq(IAppAdapter(restakingVault.appAdapter).burner(), baseBurner);
        assertEq(IRestakingAppAdapter(restakingVault.appAdapter).totalAssets(), baseVaultShares);
        assertEq(IRestakingAppAdapter(restakingVault.appAdapter).stake(), 150 ether);
        assertEq(IRestakingAppAdapter(restakingVault.appAdapter).slashable(), 150 ether);
        assertEq(IERC20(baseVault.vault).balanceOf(restakingVault.appAdapter), baseVaultShares);
    }

    function test_TestnetVaultFactoryCreate2AddressUsesConstructorInitializeCalldata() public {
        TestnetVaultFactory factory = new TestnetVaultFactory(address(this));
        TestnetRegistryStateEntity implementation = new TestnetRegistryStateEntity(address(factory));
        factory.whitelist(address(implementation));

        address owner = address(0xBEEF);
        bytes memory data = abi.encode("constructor initialized");
        address expected =
            _computeProxyAddressWithConstructorInitialize(address(factory), address(implementation), 0, 1, owner, data);
        address legacyExpected = _computeProxyAddress(address(factory), address(implementation), 0, 1, owner, data);

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
        address expected = _computeProxyAddressWithConstructorInitialize(
            address(data.core.vaultFactory), address(data.v2.vaultV2), entityIndex, VAULT_V2_VERSION, owner, vaultParams
        );
        address legacyExpected = _computeProxyAddress(
            address(data.core.vaultFactory), address(data.v2.vaultV2), entityIndex, VAULT_V2_VERSION, owner, vaultParams
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
        bytes memory data
    ) internal view returns (address) {
        bytes32 salt = keccak256(abi.encode(entityIndex, version, owner, data));
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(type(MigratableEntityProxy).creationCode, abi.encode(implementation, bytes("")))
        );
        return vm.computeCreate2Address(salt, initCodeHash, factory);
    }

    function _computeProxyAddressWithConstructorInitialize(
        address factory,
        address implementation,
        uint256 entityIndex,
        uint64 version,
        address owner,
        bytes memory data
    ) internal view returns (address) {
        bytes32 salt = keccak256(abi.encode(entityIndex, version, owner, data));
        bytes32 initCodeHash = keccak256(
            abi.encodePacked(
                type(MigratableEntityProxy).creationCode,
                abi.encode(implementation, abi.encodeCall(IMigratableEntity.initialize, (version, owner, data)))
            )
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
                depositWhitelistSetRoleHolder: owner,
                delegatorParams: abi.encode(_delegatorParams(owner))
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
        assertGt(data.fullAdapters.restakingAppAdapterFactory.code.length, 0);
        assertGt(data.fullAdapters.restakingAppAdapterImplementation.code.length, 0);
        assertGt(data.fullAdapters.merklDistributor.code.length, 0);
        assertEq(Ownable(data.fullAdapters.appAdapterFactory).owner(), owner);
        assertEq(Ownable(data.fullAdapters.aaveAdapterFactory).owner(), owner);
        assertEq(Ownable(data.fullAdapters.morphoAdapterFactory).owner(), owner);
        assertEq(Ownable(data.fullAdapters.restakingAppAdapterFactory).owner(), owner);
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
        assertEq(
            AdapterFactory(data.fullAdapters.restakingAppAdapterFactory).implementation(1),
            data.fullAdapters.restakingAppAdapterImplementation
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
        assertEq(
            IMerklClaimer(data.fullAdapters.usdcAaveAdapter).MERKL_DISTRIBUTOR(), data.fullAdapters.merklDistributor
        );
        assertEq(
            IMerklClaimer(data.fullAdapters.aUsdAaveAdapter).MERKL_DISTRIBUTOR(), data.fullAdapters.merklDistributor
        );

        assertTrue(
            MockMorphoVaultFactory(data.fullAdapters.mockMorphoVaultFactory)
                .isVaultV2(data.fullAdapters.mockMorphoVaultUsdc)
        );
        assertTrue(
            MockMorphoVaultFactory(data.fullAdapters.mockMorphoVaultFactory)
                .isVaultV2(data.fullAdapters.mockMorphoVaultAusd)
        );
        _assertMorphoRegistryContains(
            data.fullAdapters.mockMorphoAdapterRegistry, data.fullAdapters.mockMorphoVaultUsdc
        );
        _assertMorphoRegistryContains(
            data.fullAdapters.mockMorphoAdapterRegistry, data.fullAdapters.mockMorphoVaultAusd
        );
        assertEq(
            IMorphoVaultV2Adapter(data.fullAdapters.usdcMorphoAdapter).morphoVault(),
            data.fullAdapters.mockMorphoVaultUsdc
        );
        assertEq(
            IMorphoVaultV2Adapter(data.fullAdapters.aUsdMorphoAdapter).morphoVault(),
            data.fullAdapters.mockMorphoVaultAusd
        );
        assertEq(
            IMerklClaimer(data.fullAdapters.usdcMorphoAdapter).MERKL_DISTRIBUTOR(), data.fullAdapters.merklDistributor
        );
        assertEq(
            IMerklClaimer(data.fullAdapters.aUsdMorphoAdapter).MERKL_DISTRIBUTOR(), data.fullAdapters.merklDistributor
        );

        assertEq(IAppAdapter(data.fullAdapters.usdcAppAdapter).asset(), data.tokens.usdc);
        assertEq(IAppAdapter(data.fullAdapters.aUsdAppAdapter).asset(), data.tokens.aUsd);
        assertEq(IAppAdapter(data.fullAdapters.usdcAppAdapter).burner(), data.fullAdapters.usdcBurner);
        assertEq(IAppAdapter(data.fullAdapters.aUsdAppAdapter).burner(), data.fullAdapters.aUsdBurner);
        _assertRestakingSet(
            data.fullAdapters.usdcRestakingVault,
            data.fullAdapters.usdcRestakingDelegator,
            data.fullAdapters.usdcRestakingAppAdapter,
            data.liquidLane.usdcVault,
            data.tokens.usdc,
            data.fullAdapters.usdcBurner,
            data.liquidLaneLimit
        );
        _assertRestakingSet(
            data.fullAdapters.aUsdRestakingVault,
            data.fullAdapters.aUsdRestakingDelegator,
            data.fullAdapters.aUsdRestakingAppAdapter,
            data.liquidLane.aUsdVault,
            data.tokens.aUsd,
            data.fullAdapters.aUsdBurner,
            data.liquidLaneLimit
        );

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

    function _assertMockProtocolsAreOwnerConfigurable(
        DeployFullCoreLiquidLaneTestnetScript.FullAdapterDeployments memory fullAdapters,
        address owner
    ) internal {
        address nonOwner = makeAddr("fullCoreMockProtocolNonOwner");
        Token extraAaveAsset = new Token("Extra Aave Asset");
        MockAaveAToken extraAToken = new MockAaveAToken(address(extraAaveAsset), owner);

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        MockAavePool(fullAdapters.mockAavePool).setReserveToken(address(extraAaveAsset), address(extraAToken));

        vm.startPrank(owner);
        MockAavePool(fullAdapters.mockAavePool).setReserveToken(address(extraAaveAsset), address(extraAToken));
        extraAToken.setPool(fullAdapters.mockAavePool);
        MockAavePoolDataProvider(fullAdapters.mockAaveDataProvider)
            .setReserveToken(address(extraAaveAsset), address(extraAToken));
        vm.stopPrank();

        assertEq(
            MockAavePool(fullAdapters.mockAavePool).getReserveAToken(address(extraAaveAsset)), address(extraAToken)
        );
        (address configuredAToken,,) = MockAavePoolDataProvider(fullAdapters.mockAaveDataProvider)
            .getReserveTokensAddresses(address(extraAaveAsset));
        assertEq(configuredAToken, address(extraAToken));

        Token extraMorphoAsset = new Token("Extra Morpho Asset");

        vm.prank(nonOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner));
        MockMorphoAdapterRegistry(fullAdapters.mockMorphoAdapterRegistry).setInRegistry(address(0xBEEF), true);

        vm.prank(owner);
        (bool success, bytes memory returnData) = fullAdapters.mockMorphoVaultFactory
            .call(abi.encodeCall(MockMorphoVaultFactory.createVault, (address(extraMorphoAsset))));
        assertTrue(success);
        (, address extraMorphoVault) = abi.decode(returnData, (address, address));

        vm.prank(owner);
        MockMorphoAdapterRegistry(fullAdapters.mockMorphoAdapterRegistry).setInRegistry(extraMorphoVault, true);

        assertTrue(MockMorphoVaultFactory(fullAdapters.mockMorphoVaultFactory).isVaultV2(extraMorphoVault));
        _assertMorphoRegistryContains(fullAdapters.mockMorphoAdapterRegistry, extraMorphoVault);
    }

    function _assertLiquidLaneCanAllocateThroughSwap(
        DeployFullCoreLiquidLaneTestnetScript.DeploymentData memory data,
        address owner
    ) internal {
        uint256 depositAssets = 200e6;
        uint256 amountIn = 100 ether;
        uint256 amountOut = 99e6;

        _mint(data.tokens.usdc, address(this), depositAssets);
        IERC20(data.tokens.usdc).approve(data.liquidLane.usdcVault, depositAssets);
        IERC4626(data.liquidLane.usdcVault).deposit(depositAssets, address(this));

        _mint(data.tokens.mFone, owner, amountIn);
        vm.startPrank(owner);
        IERC20(data.tokens.mFone).transfer(data.liquidLane.usdcAdapter, amountIn);
        ILiquidLaneAdapter.Swap memory swap = ILiquidLaneAdapter.Swap({
            recipient: address(this), tokenIn: data.tokens.mFone, amountIn: amountIn, amountOut: amountOut
        });
        ILiquidLaneAdapter(data.liquidLane.usdcAdapter).swap(swap);
        vm.stopPrank();

        assertEq(IERC20(data.tokens.usdc).balanceOf(address(this)), amountOut);
        assertGt(ILiquidLaneAdapter(data.liquidLane.usdcAdapter).totalAssets(), 0);
    }

    function _assertRestakingSet(
        address restakingVault,
        address restakingDelegator,
        address restakingAdapter,
        address underlyingVault,
        address baseAsset,
        address burner,
        uint256 limit
    ) internal view {
        _assertVault(restakingVault, underlyingVault, restakingDelegator);
        assertEq(IUniversalDelegator(restakingDelegator).getAdaptersLength(), 1);
        assertEq(IUniversalDelegator(restakingDelegator).adapters(0), restakingAdapter);
        _assertDelegatorLimit(restakingDelegator, restakingAdapter, limit);
        assertEq(IRestakingAppAdapter(restakingAdapter).vault(), restakingVault);
        assertEq(IRestakingAppAdapter(restakingAdapter).underlyingVaults(0), underlyingVault);
        assertEq(IAppAdapter(restakingAdapter).asset(), baseAsset);
        assertEq(IAppAdapter(restakingAdapter).burner(), burner);
    }

    function _deployExtraVault(
        DeployFullCoreLiquidLaneTestnetScript.DeploymentData memory data,
        address owner,
        address asset,
        string memory name,
        string memory symbol,
        bool depositWhitelist,
        address depositorToWhitelist,
        uint256 depositLimit,
        bool isDepositLimit
    ) internal returns (ExtraVault memory deployed) {
        deployed.vault = data.core.vaultFactory
            .create(
                VAULT_V2_VERSION,
                owner,
                abi.encode(
                    IVaultV2.InitParams({
                        name: name,
                        symbol: symbol,
                        asset: asset,
                        depositWhitelist: depositWhitelist,
                        depositorToWhitelist: depositorToWhitelist,
                        depositLimit: depositLimit,
                        isDepositLimit: isDepositLimit,
                        defaultAdminRoleHolder: owner,
                        managementFeeRoleHolder: owner,
                        performanceFeeRoleHolder: owner,
                        depositLimitSetRoleHolder: owner,
                        depositorWhitelistRoleHolder: owner,
                        isDepositLimitSetRoleHolder: owner,
                        depositWhitelistSetRoleHolder: owner,
                        delegatorParams: abi.encode(_delegatorParams(owner))
                    })
                )
            );
        deployed.delegator = IVaultV2(deployed.vault).delegator();
    }

    function _configureAaveReserve(
        DeployFullCoreLiquidLaneTestnetScript.FullAdapterDeployments memory fullAdapters,
        address owner,
        address asset
    ) internal returns (address aToken) {
        aToken = address(new MockAaveAToken(asset, owner));

        vm.startPrank(owner);
        MockAavePool(fullAdapters.mockAavePool).setReserveToken(asset, aToken);
        MockAaveAToken(aToken).setPool(fullAdapters.mockAavePool);
        MockAavePoolDataProvider(fullAdapters.mockAaveDataProvider).setReserveToken(asset, aToken);
        vm.stopPrank();
    }

    function _configureMorphoVault(
        DeployFullCoreLiquidLaneTestnetScript.FullAdapterDeployments memory fullAdapters,
        address owner,
        address asset
    ) internal returns (address morphoVault) {
        vm.startPrank(owner);
        (, morphoVault) = MockMorphoVaultFactory(fullAdapters.mockMorphoVaultFactory).createVault(asset);
        MockMorphoAdapterRegistry(fullAdapters.mockMorphoAdapterRegistry).setInRegistry(morphoVault, true);
        vm.stopPrank();
    }

    function _configureLiquidLaneAccounts(
        DeployFullCoreLiquidLaneTestnetScript.DeploymentData memory data,
        address owner,
        address asset
    ) internal {
        vm.startPrank(owner);
        IAccountRegistry(data.accounts.accountRegistry)
            .setAccountFactory(asset, data.tokens.mFone, data.accounts.mFoneAccountFactory);
        IAccountRegistry(data.accounts.accountRegistry)
            .setAccountFactory(asset, data.tokens.mGlobal, data.accounts.mGlobalAccountFactory);
        vm.stopPrank();
    }

    function _createAppAdapter(address factory, address owner, address vault, address burner, uint96 subnetworkId)
        internal
        returns (address)
    {
        address[] memory converters = new address[](0);
        IAppAdapter.InitParams memory params = IAppAdapter.InitParams({
            burner: burner,
            duration: 1 days,
            operator: owner,
            converters: converters,
            subnetwork: _testnetSubnetwork(owner, subnetworkId)
        });
        return AdapterFactory(factory).create(1, owner, abi.encode(vault, abi.encode(params)));
    }

    function _createAaveAdapter(address factory, address owner, address vault) internal returns (address) {
        address[] memory converters = new address[](0);
        return AdapterFactory(factory)
            .create(1, owner, abi.encode(vault, abi.encode(IAaveV3Adapter.InitParams({converters: converters}))));
    }

    function _createLiquidLaneAdapter(
        DeployFullCoreLiquidLaneTestnetScript.DeploymentData memory data,
        address owner,
        address vault,
        uint256 limit,
        uint256 minDiscount
    ) internal returns (address adapter) {
        adapter = AdapterFactory(data.liquidLane.adapterFactory)
            .create(
                1, owner, abi.encode(vault, abi.encode(ILiquidLaneAdapter.InitParams({pauser: owner, unpauser: owner})))
            );

        vm.startPrank(owner);
        ILiquidLaneAdapter(adapter).addTokenToRedeem(data.tokens.mFone);
        ILiquidLaneAdapter(adapter).addTokenToRedeem(data.tokens.mGlobal);
        ILiquidLaneAdapter(adapter).setLimit(data.tokens.mFone, limit);
        ILiquidLaneAdapter(adapter).setLimit(data.tokens.mGlobal, limit);
        ILiquidLaneAdapter(adapter).setMinDiscount(data.tokens.mFone, minDiscount);
        ILiquidLaneAdapter(adapter).setMinDiscount(data.tokens.mGlobal, minDiscount);
        ILiquidLaneAdapter(adapter).setMarketMaker(owner, true);
        vm.stopPrank();
    }

    function _createMorphoAdapter(address factory, address owner, address vault, address morphoVault)
        internal
        returns (address)
    {
        address[] memory converters = new address[](0);
        return AdapterFactory(factory)
            .create(
                1,
                owner,
                abi.encode(
                    vault,
                    abi.encode(IMorphoVaultV2Adapter.InitParams({morphoVault: morphoVault, converters: converters}))
                )
            );
    }

    function _createRestakingAppAdapter(
        address factory,
        address owner,
        address vault,
        address asset,
        address burner,
        uint96 subnetworkId
    ) internal returns (address) {
        address[] memory converters = new address[](0);
        IRestakingAppAdapter.RestakingInitParams memory params = IRestakingAppAdapter.RestakingInitParams({
            asset: asset,
            initParams: IAppAdapter.InitParams({
                burner: burner,
                duration: 1 days,
                operator: owner,
                converters: converters,
                subnetwork: _testnetSubnetwork(owner, subnetworkId)
            })
        });
        return AdapterFactory(factory).create(1, owner, abi.encode(vault, abi.encode(params)));
    }

    function _createBurner(address burnerRouterFactory, address owner, address collateral) internal returns (address) {
        TestnetBurnerRouterFactoryMock.NetworkReceiver[] memory networkReceivers =
            new TestnetBurnerRouterFactoryMock.NetworkReceiver[](0);
        TestnetBurnerRouterFactoryMock.OperatorNetworkReceiver[] memory operatorNetworkReceivers =
            new TestnetBurnerRouterFactoryMock.OperatorNetworkReceiver[](0);
        return TestnetBurnerRouterFactoryMock(burnerRouterFactory)
            .create(
                TestnetBurnerRouterFactoryMock.InitParams({
                owner: owner,
                collateral: collateral,
                delay: 0,
                globalReceiver: owner,
                networkReceivers: networkReceivers,
                operatorNetworkReceivers: operatorNetworkReceivers
            })
            );
    }

    function _attachAdapters(
        DeployFullCoreLiquidLaneTestnetScript.DeploymentData memory data,
        address owner,
        address vault,
        address delegator,
        address[] memory adapters,
        uint256[] memory limits,
        address[] memory autoAllocateAdapters
    ) internal {
        vm.startPrank(owner);
        for (uint256 i; i < adapters.length; ++i) {
            data.v2.adapterRegistry.setWhitelistedStatus(vault, adapters[i], true);
            IUniversalDelegator(delegator).addAdapter(adapters[i]);
            IUniversalDelegator(delegator).setLimits(adapters[i], limits[i], MAX_SHARE);
        }
        IUniversalDelegator(delegator).setAutoAllocateAdapters(autoAllocateAdapters);
        vm.stopPrank();
    }

    function _oneAdapter(address adapter) internal pure returns (address[] memory adapters) {
        adapters = new address[](1);
        adapters[0] = adapter;
    }

    function _twoAdapters(address adapter1, address adapter2) internal pure returns (address[] memory adapters) {
        adapters = new address[](2);
        adapters[0] = adapter1;
        adapters[1] = adapter2;
    }

    function _oneLimit(uint256 limit) internal pure returns (uint256[] memory limits) {
        limits = new uint256[](1);
        limits[0] = limit;
    }

    function _twoLimits(uint256 limit1, uint256 limit2) internal pure returns (uint256[] memory limits) {
        limits = new uint256[](2);
        limits[0] = limit1;
        limits[1] = limit2;
    }

    function _delegatorParams(address owner) internal pure returns (IUniversalDelegator.InitParams memory params) {
        params = IUniversalDelegator.InitParams({
            allocateRoleHolder: owner,
            deallocateRoleHolder: owner,
            addAdapterRoleHolder: owner,
            swapAdaptersRoleHolder: owner,
            defaultAdminRoleHolder: owner,
            removeAdapterRoleHolder: owner,
            forceDeallocateRoleHolder: owner,
            setAdapterLimitsRoleHolder: owner,
            setAutoAllocateAdaptersRoleHolder: owner
        });
    }

    function _testnetSubnetwork(address network, uint96 identifier) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(network)) << 96 | identifier);
    }

    function _mint(address token, address to, uint256 amount) internal {
        (bool success,) = token.call(abi.encodeCall(TestnetERC20Mock.mint, (to, amount)));
        assertTrue(success);
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

    function _assertMorphoRegistryContains(address registry, address account) internal view {
        (bool success, bytes memory data) =
            registry.staticcall(abi.encodeCall(MockMorphoAdapterRegistry.isInRegistry, (account)));
        assertTrue(success);
        assertTrue(abi.decode(data, (bool)));
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
