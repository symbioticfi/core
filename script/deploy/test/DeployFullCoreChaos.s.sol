// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Logs} from "../../utils/Logs.sol";
import {DeployAaveV3AdapterBaseScript} from "../base/DeployAaveV3AdapterBase.s.sol";
import {DeployAppAdapterBaseScript} from "../base/DeployAppAdapterBase.s.sol";
import {DeployCoreBaseScript} from "../base/DeployCoreBase.s.sol";
import {DeployMorphoVaultV2AdapterBaseScript} from "../base/DeployMorphoVaultV2AdapterBase.s.sol";
import {DeployV2BaseScript} from "../base/DeployV2Base.s.sol";
import {DeployAaveV3MocksBaseScript} from "../testnet/base/DeployAaveV3MocksBase.s.sol";
import {DeployMorphoVaultV2MocksBaseScript} from "../testnet/base/DeployMorphoVaultV2MocksBase.s.sol";

import {Token} from "../../../test/mocks/Token.sol";
import {SymbioticCoreConstants} from "../../../test/integration/SymbioticCoreConstants.sol";
import {AdapterFactory} from "../../../src/contracts/adapters/AdapterFactory.sol";
import {LiquidLaneAdapter} from "../../../src/contracts/adapters/LiquidLaneAdapter.sol";
import {AccountRegistry} from "../../../src/contracts/adapters/ll-adapter/AccountRegistry.sol";
import {
    mFONE_Account,
    mFONE_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mFONE_Account.sol";
import {
    mGLOBAL_Account,
    mGLOBAL_AccountFactory
} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/mGLOBAL_Account.sol";
import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";
import {IAdapterRegistry} from "../../../src/interfaces/IAdapterRegistry.sol";
import {IProtocolFeeRegistry} from "../../../src/interfaces/IProtocolFeeRegistry.sol";
import {IVaultConfigurator} from "../../../src/interfaces/IVaultConfigurator.sol";
import {IAdapter} from "../../../src/interfaces/adapters/IAdapter.sol";
import {IAaveV3Adapter} from "../../../src/interfaces/adapters/IAaveV3Adapter.sol";
import {IAppAdapter} from "../../../src/interfaces/adapters/IAppAdapter.sol";
import {ILiquidLaneAdapter} from "../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IMorphoVaultV2Adapter} from "../../../src/interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {ICoWSwapConverter} from "../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";
import {IConverter} from "../../../src/interfaces/adapters/common/IConverter.sol";
import {IMerklClaimer} from "../../../src/interfaces/adapters/common/IMerklClaimer.sol";
import {
    ADD_ADAPTER_ROLE,
    ALLOCATE_ROLE,
    DEALLOCATE_ROLE,
    FORCE_DEALLOCATE_ROLE,
    IUniversalDelegator,
    MAX_SHARE,
    REMOVE_ADAPTER_ROLE,
    SET_ADAPTER_LIMITS_ROLE,
    SET_AUTO_ALLOCATE_ADAPTERS_ROLE,
    SWAP_ADAPTERS_ROLE,
    UNIVERSAL_DELEGATOR_TYPE
} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IBaseDelegator} from "../../../src/interfaces/delegator/IBaseDelegator.sol";
import {IFullRestakeDelegator} from "../../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {INetworkRestakeDelegator} from "../../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {
    IOperatorNetworkSpecificDelegator
} from "../../../src/interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {IOperatorSpecificDelegator} from "../../../src/interfaces/delegator/IOperatorSpecificDelegator.sol";
import {IBaseSlasher} from "../../../src/interfaces/slasher/IBaseSlasher.sol";
import {ISlasher} from "../../../src/interfaces/slasher/ISlasher.sol";
import {IVetoSlasher} from "../../../src/interfaces/slasher/IVetoSlasher.sol";
import {IOptInService} from "../../../src/interfaces/service/IOptInService.sol";
import {IVault, VAULT_VERSION} from "../../../src/interfaces/vault/IVault.sol";
import {IVaultTokenized, VAULT_TOKENIZED_VERSION} from "../../../src/interfaces/vault/IVaultTokenized.sol";
import {
    DEPOSIT_LIMIT_SET_ROLE,
    DEPOSIT_WHITELIST_SET_ROLE,
    DEPOSITOR_WHITELIST_ROLE,
    IS_DEPOSIT_LIMIT_SET_ROLE,
    IVaultV2,
    MANAGEMENT_FEE_ROLE,
    MAX_MANAGEMENT_FEE,
    MAX_PERFORMANCE_FEE,
    PERFORMANCE_FEE_ROLE,
    VAULT_V2_VERSION
} from "../../../src/interfaces/vault/IVaultV2.sol";
import {IWithdrawalQueue} from "../../../src/interfaces/vault/IWithdrawalQueue.sol";

contract DeployFullCoreChaosV2Script is DeployV2BaseScript {
    SymbioticCoreConstants.Core internal _localCore;

    constructor(SymbioticCoreConstants.Core memory core_) {
        _localCore = core_;
    }

    function _core() internal view override returns (SymbioticCoreConstants.Core memory) {
        return _localCore;
    }
}

contract DeployFullCoreChaosAaveV3AdapterScript is DeployAaveV3AdapterBaseScript {
    address internal immutable _vaultFactory;

    constructor(address vaultFactory) {
        _vaultFactory = vaultFactory;
    }

    function _coreVaultFactory() internal view override returns (address) {
        return _vaultFactory;
    }
}

contract DeployFullCoreChaosMorphoVaultV2AdapterScript is DeployMorphoVaultV2AdapterBaseScript {
    address internal immutable _vaultFactory;

    constructor(address vaultFactory) {
        _vaultFactory = vaultFactory;
    }

    function _coreVaultFactory() internal view override returns (address) {
        return _vaultFactory;
    }
}

contract DeployFullCoreChaosAppAdapterScript is DeployAppAdapterBaseScript {
    address internal immutable _vaultFactory;

    constructor(address vaultFactory) {
        _vaultFactory = vaultFactory;
    }

    function _coreVaultFactory() internal view override returns (address) {
        return _vaultFactory;
    }
}

contract DeployFullCoreChaosScript is Script {
    using Subnetwork for address;

    address internal constant CHAOS_USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant CHAOS_MFONE = 0x238a700eD6165261Cf8b2e544ba797BC11e466Ba;
    address internal constant CHAOS_MGLOBAL = 0x7433806912Eae67919e66aea853d46Fa0aef98A8;
    address internal constant CHAOS_MFONE_REDEMPTION_VAULT = 0x44b0440e35c596e858cEA433D0d82F5a985fD19C;
    address internal constant CHAOS_MGLOBAL_REDEMPTION_VAULT = 0x1e0fd66753198c7b8bA64edEe8d41D8628Bf20D7;
    address internal constant CHAOS_COW_SETTLEMENT = address(0xCC05E7);
    address internal constant CHAOS_COW_VAULT_RELAYER = address(0xCC0A7);

    struct Actors {
        address burner;
        address staker;
        address network;
        address operator;
        address middleware;
    }

    struct ChaosContext {
        address owner;
        uint256 seed;
        Actors actors;
    }

    struct V1Vault {
        address vault;
        address delegator;
        address slasher;
        address asset;
        uint64 delegatorType;
        uint64 slasherType;
    }

    struct V2Vault {
        address vault;
        address delegator;
        address asset;
        address withdrawalQueue;
    }

    struct AdapterDeployments {
        V2AdapterSet[] sets;
    }

    struct LiquidLaneAssets {
        address usdc;
        address aUsd;
        address mFone;
        address mGlobal;
    }

    struct V2Infra {
        address adapterRegistry;
        address protocolFeeRegistry;
    }

    struct V2AdapterSet {
        address appFactory;
        address aaveFactory;
        address morphoFactory;
        address liquidLaneFactory;
        address accountRegistry;
        address mFoneAccountFactory;
        address mGlobalAccountFactory;
        address appAdapter;
        address aaveAdapter;
        address morphoAdapter;
        address liquidLaneAdapter;
    }

    event ChaosCall(bytes32 indexed label, bool success);

    function run() public {
        run(vm.envOr("CHAOS_SEED", uint256(0xC0A5)));
    }

    function run(uint256 seed) public {
        ChaosContext memory ctx = ChaosContext({owner: _scriptOwner(), seed: seed, actors: _actors(seed)});
        require(ctx.owner != address(0), "invalid owner");

        Logs.log(string.concat("Full core chaos seed: ", vm.toString(seed)));

        SymbioticCoreConstants.Core memory core = _coreFrom(new DeployCoreBaseScript().run(ctx.owner));
        DeployV2BaseScript.DeploymentData memory v2 =
            new DeployFullCoreChaosV2Script(core).runBase(ctx.owner, ctx.owner);
        V2Infra memory infra = V2Infra({
            adapterRegistry: address(v2.adapterRegistry), protocolFeeRegistry: address(v2.protocolFeeRegistry)
        });

        Token[3] memory tokens = [new Token("Chaos Alpha"), new Token("Chaos Beta"), new Token("Chaos Gamma")];
        LiquidLaneAssets memory liquidLaneAssets = _deployLiquidLaneAssets();

        _fund(ctx.actors, tokens);
        _fundLiquidLaneAssets(ctx.actors, liquidLaneAssets);
        _register(core, ctx.actors);
        _configureProtocolFee(ctx.owner, infra.protocolFeeRegistry);

        V1Vault[] memory v1Vaults = _createV1Vaults(core, ctx.owner, ctx.actors, tokens, seed);
        V2Vault[] memory v2Vaults = _createV2Vaults(core, ctx.owner, ctx.actors, tokens, liquidLaneAssets, seed);
        AdapterDeployments memory adapters = _deployAdapters(core, infra, ctx, v2Vaults, liquidLaneAssets);

        _exerciseV1(ctx.owner, ctx.actors, v1Vaults, seed);
        _exerciseV2(core, ctx, infra, v2Vaults, adapters, liquidLaneAssets);

        Logs.log("Full core chaos deployment finished");
    }

    function _createV1Vaults(
        SymbioticCoreConstants.Core memory core,
        address owner,
        Actors memory actors,
        Token[3] memory tokens,
        uint256 seed
    ) internal returns (V1Vault[] memory vaults) {
        vaults = new V1Vault[](6);

        for (uint64 i; i < uint64(vaults.length); ++i) {
            bool tokenized = i % 2 == 1;
            uint64 delegatorType = i % 4;
            uint64 slasherType = i % 2;
            address asset = address(tokens[i % tokens.length]);
            bytes memory vaultParams = tokenized
                ? abi.encode(
                    IVaultTokenized.InitParamsTokenized({
                        baseParams: _v1VaultParams(asset, owner, actors.burner, i, seed),
                        name: string.concat("Chaos Vault ", vm.toString(i)),
                        symbol: string.concat("cV", vm.toString(i))
                    })
                )
                : abi.encode(_v1VaultParams(asset, owner, actors.burner, i, seed));

            (vaults[i].vault, vaults[i].delegator, vaults[i].slasher) = core.vaultConfigurator
                .create(
                    IVaultConfigurator.InitParams({
                        version: tokenized ? VAULT_TOKENIZED_VERSION : VAULT_VERSION,
                        owner: owner,
                        vaultParams: vaultParams,
                        delegatorIndex: delegatorType,
                        delegatorParams: _delegatorParams(owner, actors, delegatorType),
                        withSlasher: i % 3 > 0,
                        slasherIndex: slasherType,
                        slasherParams: _slasherParams(slasherType, i)
                    })
                );
            vaults[i].asset = asset;
            vaults[i].delegatorType = delegatorType;
            vaults[i].slasherType = slasherType;

            vm.startPrank(actors.operator);
            _try(
                address(core.operatorVaultOptInService),
                abi.encodeWithSignature("optIn(address)", vaults[i].vault),
                "opt-in-vault"
            );
            _try(
                address(core.operatorNetworkOptInService),
                abi.encodeWithSignature("optIn(address)", actors.network),
                "opt-in-network"
            );
            vm.stopPrank();
        }
    }

    function _createV2Vaults(
        SymbioticCoreConstants.Core memory core,
        address owner,
        Actors memory actors,
        Token[3] memory tokens,
        LiquidLaneAssets memory liquidLaneAssets,
        uint256 seed
    ) internal returns (V2Vault[] memory vaults) {
        vaults = new V2Vault[](10);

        for (uint64 i; i < uint64(vaults.length); ++i) {
            address asset = _v2VaultAsset(tokens, liquidLaneAssets, i);
            vaults[i].vault = core.vaultFactory
                .create(
                    VAULT_V2_VERSION,
                    owner,
                    abi.encode(
                        IVaultV2.InitParams({
                            name: string.concat("Chaos V2 Vault ", vm.toString(i)),
                            symbol: string.concat("cV2-", vm.toString(i)),
                            asset: asset,
                            depositWhitelist: _flip(seed, i),
                            depositorToWhitelist: _nonZeroHolder(owner, actors, i + 10),
                            isDepositLimit: _flip(seed, i + 100),
                            depositLimit: i % 4 == 0 ? 0 : _amount(seed, i, 1000 ether, 80_000 ether),
                            defaultAdminRoleHolder: owner,
                            managementFeeRoleHolder: _holder(owner, actors, i + 20),
                            performanceFeeRoleHolder: _holder(owner, actors, i + 30),
                            depositLimitSetRoleHolder: _holder(owner, actors, i + 40),
                            depositorWhitelistRoleHolder: _holder(owner, actors, i + 50),
                            isDepositLimitSetRoleHolder: _holder(owner, actors, i + 60),
                            depositWhitelistSetRoleHolder: _holder(owner, actors, i + 70)
                        })
                    )
                );
            vaults[i].delegator = core.delegatorFactory
                .create(
                    UNIVERSAL_DELEGATOR_TYPE,
                    abi.encode(
                        vaults[i].vault,
                        abi.encode(
                            IUniversalDelegator.InitParams({
                                defaultAdminRoleHolder: owner,
                                addAdapterRoleHolder: owner,
                                removeAdapterRoleHolder: owner,
                                setAdapterLimitsRoleHolder: owner,
                                setAutoAllocateAdaptersRoleHolder: owner,
                                swapAdaptersRoleHolder: owner,
                                allocateRoleHolder: owner,
                                deallocateRoleHolder: owner,
                                forceDeallocateRoleHolder: owner
                            })
                        )
                    )
                );
            vaults[i].asset = asset;

            vm.prank(owner);
            IVaultV2(vaults[i].vault).setDelegator(vaults[i].delegator);
            vaults[i].withdrawalQueue = IVaultV2(vaults[i].vault).withdrawalQueue();
        }
    }

    function _deployAdapters(
        SymbioticCoreConstants.Core memory core,
        V2Infra memory infra,
        ChaosContext memory ctx,
        V2Vault[] memory vaults,
        LiquidLaneAssets memory liquidLaneAssets
    ) internal returns (AdapterDeployments memory adapters) {
        adapters.sets = new V2AdapterSet[](vaults.length);

        for (uint256 i; i < vaults.length; ++i) {
            V2AdapterSet memory set = _deployAdapterSet(core, ctx, vaults[i], liquidLaneAssets, i);

            vm.startPrank(ctx.owner);
            IAdapterRegistry(infra.adapterRegistry).setWhitelistedStatus(vaults[i].vault, set.appAdapter, true);
            IAdapterRegistry(infra.adapterRegistry).setWhitelistedStatus(vaults[i].vault, set.aaveAdapter, true);
            IAdapterRegistry(infra.adapterRegistry).setWhitelistedStatus(vaults[i].vault, set.morphoAdapter, true);
            if (set.liquidLaneAdapter != address(0)) {
                IAdapterRegistry(infra.adapterRegistry)
                    .setWhitelistedStatus(vaults[i].vault, set.liquidLaneAdapter, true);
            }
            vm.stopPrank();

            adapters.sets[i] = set;
        }
    }

    function _deployAdapterSet(
        SymbioticCoreConstants.Core memory core,
        ChaosContext memory ctx,
        V2Vault memory vault,
        LiquidLaneAssets memory liquidLaneAssets,
        uint256 i
    ) internal returns (V2AdapterSet memory set) {
        (set.appFactory, set.appAdapter) = _deployAppAdapter(core, ctx, vault, i);
        (set.aaveFactory, set.aaveAdapter) = _deployAaveAdapter(core, ctx, vault);
        (set.morphoFactory, set.morphoAdapter) = _deployMorphoAdapter(core, ctx, vault);

        if (_isLiquidLaneVaultAsset(vault.asset, liquidLaneAssets)) {
            (
                set.liquidLaneFactory,
                set.accountRegistry,
                set.mFoneAccountFactory,
                set.mGlobalAccountFactory,
                set.liquidLaneAdapter
            ) = _deployLiquidLaneSet(core, ctx, vault, liquidLaneAssets);
        }
    }

    function _deployAppAdapter(
        SymbioticCoreConstants.Core memory core,
        ChaosContext memory ctx,
        V2Vault memory vault,
        uint256 i
    ) internal returns (address factory, address adapter) {
        factory =
        new DeployFullCoreChaosAppAdapterScript(address(core.vaultFactory))
        .runBase(
            DeployAppAdapterBaseScript.DeployParams({
                adapterFactoryOwner: ctx.owner, networkMiddlewareService: address(core.networkMiddlewareService)
            })
        )
        .adapterFactory;
        adapter = AdapterFactory(factory)
            .create(
                1,
                ctx.owner,
                abi.encode(
                    vault.vault,
                    abi.encode(
                        IAppAdapter.InitParams({
                        burner: ctx.actors.burner,
                        duration: uint48(1 + (ctx.seed + i) % 365 days),
                        operator: ctx.actors.operator,
                        subnetwork: ctx.actors.network.subnetwork(uint96(ctx.seed + i))
                    })
                    )
                )
            );
    }

    function _deployAaveAdapter(SymbioticCoreConstants.Core memory core, ChaosContext memory ctx, V2Vault memory vault)
        internal
        returns (address factory, address adapter)
    {
        DeployAaveV3MocksBaseScript.DeploymentData memory aaveMocks =
            new DeployAaveV3MocksBaseScript().runBase(vault.asset);
        factory =
        new DeployFullCoreChaosAaveV3AdapterScript(address(core.vaultFactory))
        .runBase(
            DeployAaveV3AdapterBaseScript.DeployParams({adapterFactoryOwner: ctx.owner, aavePool: aaveMocks.aavePool})
        )
        .adapterFactory;
        adapter = AdapterFactory(factory).create(1, ctx.owner, abi.encode(vault.vault, ""));
    }

    function _deployMorphoAdapter(
        SymbioticCoreConstants.Core memory core,
        ChaosContext memory ctx,
        V2Vault memory vault
    ) internal returns (address factory, address adapter) {
        DeployMorphoVaultV2MocksBaseScript.DeploymentData memory morphoMocks = new DeployMorphoVaultV2MocksBaseScript()
            .runBase(
                DeployMorphoVaultV2MocksBaseScript.DeployParams({
                collateral: vault.asset, adapterRegistryOwner: ctx.owner
            })
            );
        factory =
        new DeployFullCoreChaosMorphoVaultV2AdapterScript(address(core.vaultFactory))
        .runBase(
            DeployMorphoVaultV2AdapterBaseScript.DeployParams({
                adapterFactoryOwner: ctx.owner,
                morphoVaultFactory: morphoMocks.morphoVaultFactory,
                morphoAdapterRegistry: morphoMocks.morphoAdapterRegistry
            })
        )
        .adapterFactory;
        adapter =
            AdapterFactory(factory).create(1, ctx.owner, abi.encode(vault.vault, abi.encode(morphoMocks.morphoVault)));
    }

    function _v2VaultAsset(Token[3] memory tokens, LiquidLaneAssets memory liquidLaneAssets, uint64 i)
        internal
        pure
        returns (address)
    {
        if (i == 8) {
            return liquidLaneAssets.usdc;
        }
        if (i == 9) {
            return liquidLaneAssets.aUsd;
        }
        return address(tokens[(i + 1) % tokens.length]);
    }

    function _isLiquidLaneVaultAsset(address asset, LiquidLaneAssets memory liquidLaneAssets)
        internal
        pure
        returns (bool)
    {
        return asset == liquidLaneAssets.usdc || asset == liquidLaneAssets.aUsd;
    }

    function _deployLiquidLaneSet(
        SymbioticCoreConstants.Core memory core,
        ChaosContext memory ctx,
        V2Vault memory vault,
        LiquidLaneAssets memory liquidLaneAssets
    )
        internal
        returns (
            address liquidLaneFactory,
            address accountRegistry,
            address mFoneAccountFactory,
            address mGlobalAccountFactory,
            address liquidLaneAdapter
        )
    {
        liquidLaneFactory = address(new AdapterFactory(ctx.owner));
        accountRegistry = address(new AccountRegistry(ctx.owner));
        mFoneAccountFactory = _deployMFoneAccountFactory(ctx.owner);
        mGlobalAccountFactory = _deployMGlobalAccountFactory(ctx.owner);

        vm.startPrank(ctx.owner);
        AccountRegistry(accountRegistry).setAccountFactory(vault.asset, liquidLaneAssets.mFone, mFoneAccountFactory);
        AccountRegistry(accountRegistry).setAccountFactory(vault.asset, liquidLaneAssets.mGlobal, mGlobalAccountFactory);
        vm.stopPrank();

        LiquidLaneAdapter liquidLaneImplementation =
            new LiquidLaneAdapter(address(core.vaultFactory), liquidLaneFactory, accountRegistry);
        vm.prank(ctx.owner);
        AdapterFactory(liquidLaneFactory).whitelist(address(liquidLaneImplementation));

        liquidLaneAdapter = AdapterFactory(liquidLaneFactory)
            .create(
                1,
                ctx.owner,
                abi.encode(
                    vault.vault, abi.encode(ILiquidLaneAdapter.InitParams({pauser: ctx.owner, unpauser: ctx.owner}))
                )
            );
    }

    function _deployMFoneAccountFactory(address owner) internal returns (address factory) {
        factory = address(new mFONE_AccountFactory(owner));
        vm.mockCall(
            CHAOS_COW_SETTLEMENT, abi.encodeWithSignature("vaultRelayer()"), abi.encode(CHAOS_COW_VAULT_RELAYER)
        );
        mFONE_Account implementation = new mFONE_Account(factory, CHAOS_COW_SETTLEMENT);
        vm.prank(owner);
        mFONE_AccountFactory(factory).whitelist(address(implementation));
    }

    function _deployMGlobalAccountFactory(address owner) internal returns (address factory) {
        factory = address(new mGLOBAL_AccountFactory(owner));
        vm.mockCall(
            CHAOS_COW_SETTLEMENT, abi.encodeWithSignature("vaultRelayer()"), abi.encode(CHAOS_COW_VAULT_RELAYER)
        );
        mGLOBAL_Account implementation = new mGLOBAL_Account(factory, CHAOS_COW_SETTLEMENT);
        vm.prank(owner);
        mGLOBAL_AccountFactory(factory).whitelist(address(implementation));
    }

    function _exerciseV1(address owner, Actors memory actors, V1Vault[] memory vaults, uint256 seed) internal {
        bytes32 subnetwork = actors.network.subnetwork(uint96(seed));

        for (uint256 i; i < vaults.length; ++i) {
            uint256 amount = _amount(seed, i, 10 ether, 100 ether);

            vm.startPrank(owner);
            _try(vaults[i].vault, abi.encodeCall(IVault.setDepositWhitelist, (_flip(seed, i + 200))), "v1-whitelist");
            _try(vaults[i].vault, abi.encodeCall(IVault.setDepositorWhitelistStatus, (actors.staker, true)), "v1-dep");
            _try(vaults[i].vault, abi.encodeCall(IVault.setIsDepositLimit, (true)), "v1-limit-on");
            _try(vaults[i].vault, abi.encodeCall(IVault.setDepositLimit, (amount * 5)), "v1-limit");
            _try(vaults[i].delegator, abi.encodeCall(IBaseDelegator.setHook, (address(0))), "v1-hook");
            vm.stopPrank();

            vm.prank(actors.network);
            _try(
                vaults[i].delegator,
                abi.encodeCall(IBaseDelegator.setMaxNetworkLimit, (uint96(seed), amount * 4)),
                "v1-max"
            );

            vm.startPrank(owner);
            if (vaults[i].delegatorType == 0) {
                _try(
                    vaults[i].delegator,
                    abi.encodeCall(INetworkRestakeDelegator.setNetworkLimit, (subnetwork, amount * 3)),
                    "v1-net-limit"
                );
                _try(
                    vaults[i].delegator,
                    abi.encodeCall(INetworkRestakeDelegator.setOperatorNetworkShares, (subnetwork, actors.operator, 1)),
                    "v1-op-shares"
                );
            } else if (vaults[i].delegatorType == 1) {
                _try(
                    vaults[i].delegator,
                    abi.encodeCall(IFullRestakeDelegator.setNetworkLimit, (subnetwork, amount * 3)),
                    "v1-full-net"
                );
                _try(
                    vaults[i].delegator,
                    abi.encodeCall(
                        IFullRestakeDelegator.setOperatorNetworkLimit, (subnetwork, actors.operator, amount * 2)
                    ),
                    "v1-full-op"
                );
            } else if (vaults[i].delegatorType == 2) {
                _try(
                    vaults[i].delegator,
                    abi.encodeCall(IOperatorSpecificDelegator.setNetworkLimit, (subnetwork, amount * 3)),
                    "v1-op-net"
                );
            }
            vm.stopPrank();

            vm.startPrank(actors.staker);
            IERC20(vaults[i].asset).approve(vaults[i].vault, amount);
            _try(vaults[i].vault, abi.encodeCall(IVault.deposit, (actors.staker, amount)), "v1-deposit");
            _try(vaults[i].vault, abi.encodeCall(IVault.withdraw, (actors.staker, amount / 3)), "v1-withdraw");
            _try(vaults[i].vault, abi.encodeCall(IVault.redeem, (actors.staker, amount / 5)), "v1-redeem");
            vm.stopPrank();

            if (vaults[i].slasher != address(0)) {
                vm.startPrank(actors.middleware);
                _try(
                    vaults[i].slasher,
                    abi.encodeCall(ISlasher.slash, (subnetwork, actors.operator, amount / 10, _past(), "")),
                    "v1-slash"
                );
                _try(
                    vaults[i].slasher,
                    abi.encodeCall(IVetoSlasher.requestSlash, (subnetwork, actors.operator, amount / 10, _past(), "")),
                    "v1-request-slash"
                );
                _try(vaults[i].slasher, abi.encodeCall(IVetoSlasher.executeSlash, (0, "")), "v1-execute-slash");
                vm.stopPrank();
            }
        }

        vm.warp(vm.getBlockTimestamp() + 8 days);
        for (uint256 i; i < vaults.length; ++i) {
            vm.startPrank(actors.staker);
            _try(vaults[i].vault, abi.encodeCall(IVault.claim, (actors.staker, 0)), "v1-claim-0");
            _try(vaults[i].vault, abi.encodeCall(IVault.claim, (actors.staker, 1)), "v1-claim-1");
            vm.stopPrank();
        }
    }

    function _exerciseV2(
        SymbioticCoreConstants.Core memory core,
        ChaosContext memory ctx,
        V2Infra memory infra,
        V2Vault[] memory vaults,
        AdapterDeployments memory adapters,
        LiquidLaneAssets memory liquidLaneAssets
    ) internal {
        _exerciseV2ProtocolFeeRegistry(ctx.owner, infra.protocolFeeRegistry, vaults);

        for (uint256 i; i < vaults.length; ++i) {
            uint256 amount = _amount(ctx.seed, i + 400, 50 ether, 250 ether);
            V2AdapterSet memory set = adapters.sets[i];

            _exerciseV2AdapterRegistry(ctx.owner, ctx.actors, infra.adapterRegistry, vaults[i], set);
            _exerciseV2VaultConfiguration(ctx.owner, ctx.actors, vaults[i], amount, i);
            _exerciseV2DelegatorSetup(ctx.owner, ctx.actors, vaults[i], set, amount);
            _exerciseV2TokenFlows(ctx.actors, vaults[i], amount);
            _exerciseV2LiquidLane(ctx.owner, ctx.actors, set, liquidLaneAssets, amount);
            _exerciseV2AdapterHooks(ctx.owner, ctx.actors, vaults[i], set, amount, ctx.seed + i);
            _exerciseV2QueueAndDeallocation(ctx.owner, ctx.actors, vaults[i], set, amount);
        }

        _exerciseV2Factories(core, ctx.owner, vaults, adapters);
    }

    function _exerciseV2ProtocolFeeRegistry(address owner, address protocolFeeRegistry, V2Vault[] memory vaults)
        internal
    {
        vm.startPrank(owner);
        _try(
            protocolFeeRegistry,
            abi.encodeCall(IProtocolFeeRegistry.globalReceiver, ()),
            "v2-protocol-global-receiver-view"
        );
        _try(
            protocolFeeRegistry,
            abi.encodeCall(IProtocolFeeRegistry.globalManagementFee, ()),
            "v2-protocol-global-mgmt-view"
        );
        _try(
            protocolFeeRegistry,
            abi.encodeCall(IProtocolFeeRegistry.globalPerformanceFee, ()),
            "v2-protocol-global-perf-view"
        );
        _try(
            protocolFeeRegistry,
            abi.encodeCall(IProtocolFeeRegistry.setGlobalReceiver, (owner)),
            "v2-protocol-global-receiver"
        );
        _try(
            protocolFeeRegistry,
            abi.encodeCall(IProtocolFeeRegistry.setGlobalFee, (MAX_MANAGEMENT_FEE / 10, MAX_PERFORMANCE_FEE / 10)),
            "v2-protocol-global-fee"
        );
        for (uint256 i; i < vaults.length; ++i) {
            _try(
                protocolFeeRegistry,
                abi.encodeCall(
                    IProtocolFeeRegistry.setVaultFee,
                    (vaults[i].vault, true, owner, MAX_MANAGEMENT_FEE / 20, MAX_PERFORMANCE_FEE / 20)
                ),
                "v2-protocol-vault-fee-on"
            );
            _try(
                protocolFeeRegistry,
                abi.encodeCall(IProtocolFeeRegistry.vaultFee, (vaults[i].vault)),
                "v2-protocol-vault-fee-view"
            );
            _try(
                protocolFeeRegistry,
                abi.encodeCall(IProtocolFeeRegistry.getFee, (vaults[i].vault)),
                "v2-protocol-get-fee"
            );
            _try(
                protocolFeeRegistry,
                abi.encodeCall(IProtocolFeeRegistry.setVaultFee, (vaults[i].vault, false, address(0), 0, 0)),
                "v2-protocol-vault-fee-off"
            );
        }
        vm.stopPrank();

        vm.prank(vaults[0].asset);
        _try(
            protocolFeeRegistry,
            abi.encodeCall(IProtocolFeeRegistry.setGlobalReceiver, (owner)),
            "v2-protocol-unauthorized"
        );
    }

    function _exerciseV2AdapterRegistry(
        address owner,
        Actors memory actors,
        address adapterRegistry,
        V2Vault memory vault,
        V2AdapterSet memory set
    ) internal {
        vm.startPrank(owner);
        _try(
            adapterRegistry,
            abi.encodeCall(IAdapterRegistry.setWhitelistedStatus, (vault.vault, set.appAdapter, false)),
            "v2-reg-app-off"
        );
        _try(
            adapterRegistry,
            abi.encodeCall(IAdapterRegistry.setWhitelistedStatus, (vault.vault, set.appAdapter, true)),
            "v2-reg-app-on"
        );
        _try(
            adapterRegistry,
            abi.encodeCall(IAdapterRegistry.setWhitelistedStatus, (vault.vault, set.aaveAdapter, true)),
            "v2-reg-aave-on"
        );
        _try(
            adapterRegistry,
            abi.encodeCall(IAdapterRegistry.setWhitelistedStatus, (vault.vault, set.morphoAdapter, true)),
            "v2-reg-morpho-on"
        );
        if (set.liquidLaneAdapter != address(0)) {
            _try(
                adapterRegistry,
                abi.encodeCall(IAdapterRegistry.setWhitelistedStatus, (vault.vault, set.liquidLaneAdapter, true)),
                "v2-reg-ll-on"
            );
        }
        _try(
            adapterRegistry,
            abi.encodeCall(IAdapterRegistry.setWhitelistedStatus, (vault.vault, address(0), false)),
            "v2-reg-zero"
        );
        vm.stopPrank();

        _try(
            adapterRegistry,
            abi.encodeCall(IAdapterRegistry.isWhitelisted, (vault.vault, set.appAdapter)),
            "v2-reg-view-app"
        );
        if (set.liquidLaneAdapter != address(0)) {
            _try(
                adapterRegistry,
                abi.encodeCall(IAdapterRegistry.isWhitelisted, (vault.vault, set.liquidLaneAdapter)),
                "v2-reg-view-ll"
            );
        }

        vm.prank(actors.staker);
        _try(
            adapterRegistry,
            abi.encodeCall(IAdapterRegistry.setWhitelistedStatus, (vault.vault, set.appAdapter, false)),
            "v2-reg-unauthorized"
        );
    }

    function _exerciseV2VaultConfiguration(
        address owner,
        Actors memory actors,
        V2Vault memory vault,
        uint256 amount,
        uint256 i
    ) internal {
        vm.startPrank(owner);
        _grantV2Roles(vault.vault, owner);
        _grantV2Roles(vault.vault, actors.staker);
        _try(vault.vault, abi.encodeCall(IVaultV2.setDepositWhitelist, (true)), "v2-whitelist-on");
        _try(vault.vault, abi.encodeCall(IVaultV2.setDepositWhitelist, (false)), "v2-whitelist-off");
        _try(vault.vault, abi.encodeCall(IVaultV2.setDepositorWhitelistStatus, (actors.staker, true)), "v2-dep-staker");
        _try(vault.vault, abi.encodeCall(IVaultV2.setDepositorWhitelistStatus, (actors.burner, true)), "v2-dep-burner");
        _try(vault.vault, abi.encodeCall(IVaultV2.setDepositorWhitelistStatus, (address(0), true)), "v2-dep-zero");
        _try(vault.vault, abi.encodeCall(IVaultV2.setIsDepositLimit, (true)), "v2-limit-on");
        _try(vault.vault, abi.encodeCall(IVaultV2.setDepositLimit, (amount * 10)), "v2-limit-high");
        _try(vault.vault, abi.encodeCall(IVaultV2.setIsDepositLimit, (i % 2 == 0)), "v2-limit-toggle");
        _try(vault.vault, abi.encodeCall(IVaultV2.setManagementFee, (uint96(0), address(0))), "v2-mgmt-zero");
        _try(
            vault.vault,
            abi.encodeCall(IVaultV2.setManagementFee, (uint96(MAX_MANAGEMENT_FEE / 10), owner)),
            "v2-mgmt-set"
        );
        _try(vault.vault, abi.encodeCall(IVaultV2.setPerformanceFee, (uint96(0), address(0))), "v2-perf-zero");
        _try(
            vault.vault,
            abi.encodeCall(IVaultV2.setPerformanceFee, (uint96(MAX_PERFORMANCE_FEE / 10), owner)),
            "v2-perf-set"
        );
        _try(vault.vault, abi.encodeCall(IVaultV2.setSlasher, (actors.burner)), "v2-set-slasher");
        _try(vault.vault, abi.encodeCall(IVaultV2.accrueInterest, ()), "v2-accrue");
        _try(vault.vault, abi.encodeCall(IVaultV2.withdrawalQueue, ()), "v2-withdrawal-queue");
        _try(vault.vault, abi.encodeCall(IVaultV2.delegator, ()), "v2-delegator-view");
        _try(vault.vault, abi.encodeCall(IVaultV2.lastUpdate, ()), "v2-last-update");
        _try(vault.vault, abi.encodeCall(IVaultV2.isDepositLimit, ()), "v2-limit-status");
        _try(vault.vault, abi.encodeCall(IVaultV2.depositWhitelist, ()), "v2-whitelist-status");
        _try(vault.vault, abi.encodeCall(IVaultV2.depositLimit, ()), "v2-deposit-limit-view");
        _try(vault.vault, abi.encodeCall(IVaultV2.isDepositorWhitelisted, (actors.staker)), "v2-depositor-whitelisted");
        _try(vault.vault, abi.encodeCall(IVaultV2.managementFee, ()), "v2-mgmt-fee-view");
        _try(vault.vault, abi.encodeCall(IVaultV2.managementFeeReceiver, ()), "v2-mgmt-receiver-view");
        _try(vault.vault, abi.encodeCall(IVaultV2.performanceFee, ()), "v2-perf-fee-view");
        _try(vault.vault, abi.encodeCall(IVaultV2.performanceFeeReceiver, ()), "v2-perf-receiver-view");
        _try(vault.vault, abi.encodeCall(IVaultV2.lastProtocolManagementFee, ()), "v2-last-protocol-mgmt");
        _try(vault.vault, abi.encodeCall(IVaultV2.lastProtocolPerformanceFee, ()), "v2-last-protocol-perf");
        _try(vault.vault, abi.encodeCall(IVaultV2.lastProtocolFeeReceiver, ()), "v2-last-protocol-receiver");
        _try(vault.vault, abi.encodeCall(IVaultV2.isInitialized, ()), "v2-initialized");
        _try(vault.vault, abi.encodeCall(IVaultV2.getAccrueInterest, ()), "v2-get-accrue");
        _try(vault.vault, abi.encodeCall(IVaultV2.withdrawable, ()), "v2-withdrawable");
        _try(vault.vault, abi.encodeCall(IVaultV2.redeemable, ()), "v2-redeemable");
        _try(vault.vault, abi.encodeCall(IVaultV2.freeAssets, ()), "v2-free-assets");
        _try(vault.vault, abi.encodeCall(IVaultV2.totalSupplyAt, (_past())), "v2-supply-at");
        _try(vault.vault, abi.encodeCall(IVaultV2.balanceOfAt, (actors.staker, _past())), "v2-balance-at");
        _try(vault.vault, abi.encodeCall(IERC20.totalSupply, ()), "v2-share-total-supply");
        _try(vault.vault, abi.encodeCall(IERC20.balanceOf, (actors.staker)), "v2-share-balance");
        _try(vault.vault, abi.encodeWithSignature("name()"), "v2-name");
        _try(vault.vault, abi.encodeWithSignature("symbol()"), "v2-symbol");
        _try(vault.vault, abi.encodeWithSignature("decimals()"), "v2-decimals");
        _try(vault.vault, abi.encodeCall(IVaultV2.setDelegator, (vault.delegator)), "v2-set-delegator-again");

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(IVaultV2.setDepositLimit, (amount * 12));
        calls[1] = abi.encodeCall(IVaultV2.setDepositWhitelist, (false));
        _try(vault.vault, abi.encodeWithSignature("multicall(bytes[])", calls), "v2-vault-multicall");

        _try(
            vault.vault,
            abi.encodeWithSignature("grantRole(bytes32,address)", DEPOSIT_LIMIT_SET_ROLE, actors.network),
            "v2-grant-network-limit"
        );
        vm.stopPrank();

        vm.prank(actors.network);
        _try(vault.vault, abi.encodeCall(IVaultV2.setDepositLimit, (amount * 11)), "v2-network-limit");

        vm.startPrank(owner);
        _try(
            vault.vault,
            abi.encodeWithSignature("revokeRole(bytes32,address)", DEPOSIT_LIMIT_SET_ROLE, actors.network),
            "v2-revoke-network-limit"
        );
        _try(
            vault.vault,
            abi.encodeWithSignature("grantRole(bytes32,address)", DEPOSITOR_WHITELIST_ROLE, actors.staker),
            "v2-grant-staker-dep"
        );
        vm.stopPrank();

        vm.prank(actors.staker);
        _try(
            vault.vault,
            abi.encodeWithSignature("renounceRole(bytes32,address)", DEPOSITOR_WHITELIST_ROLE, actors.staker),
            "v2-renounce-staker-dep"
        );

        vm.prank(actors.operator);
        _try(vault.vault, abi.encodeCall(IVaultV2.setDepositLimit, (amount)), "v2-unauthorized-limit");
    }

    function _exerciseV2DelegatorSetup(
        address owner,
        Actors memory actors,
        V2Vault memory vault,
        V2AdapterSet memory set,
        uint256 amount
    ) internal {
        vm.startPrank(owner);
        _grantDelegatorRoles(vault.delegator, owner);
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.addAdapter, (set.appAdapter)), "v2-add-app");
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.addAdapter, (set.aaveAdapter)), "v2-add-aave");
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.addAdapter, (set.morphoAdapter)), "v2-add-morpho");
        if (set.liquidLaneAdapter != address(0)) {
            _try(vault.delegator, abi.encodeCall(IUniversalDelegator.addAdapter, (set.liquidLaneAdapter)), "v2-add-ll");
        }
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.addAdapter, (set.appAdapter)), "v2-add-duplicate");
        _try(
            vault.delegator,
            abi.encodeCall(IUniversalDelegator.setLimits, (set.appAdapter, amount * 4, MAX_SHARE)),
            "v2-limit-app"
        );
        _try(
            vault.delegator,
            abi.encodeCall(IUniversalDelegator.setLimits, (set.aaveAdapter, amount * 3, MAX_SHARE / 2)),
            "v2-limit-aave"
        );
        _try(
            vault.delegator,
            abi.encodeCall(IUniversalDelegator.setLimits, (set.morphoAdapter, amount * 2, MAX_SHARE / 3)),
            "v2-limit-morpho"
        );
        if (set.liquidLaneAdapter != address(0)) {
            _try(
                vault.delegator,
                abi.encodeCall(IUniversalDelegator.setLimits, (set.liquidLaneAdapter, amount * 4, MAX_SHARE)),
                "v2-limit-ll"
            );
        }
        _try(
            vault.delegator,
            abi.encodeCall(IUniversalDelegator.setLimits, (set.morphoAdapter, amount, MAX_SHARE + 1)),
            "v2-limit-invalid-share"
        );

        address[] memory emptyRoute = new address[](0);
        _try(
            vault.delegator, abi.encodeCall(IUniversalDelegator.setAutoAllocateAdapters, (emptyRoute)), "v2-auto-empty"
        );
        _try(
            vault.delegator,
            abi.encodeCall(IUniversalDelegator.setAutoAllocateAdapters, (_route(set, 0))),
            "v2-auto-forward"
        );
        _try(
            vault.delegator,
            abi.encodeCall(IUniversalDelegator.setAutoAllocateAdapters, (_route(set, 1))),
            "v2-auto-reverse"
        );

        address[] memory duplicateRoute = new address[](2);
        duplicateRoute[0] = set.appAdapter;
        duplicateRoute[1] = set.appAdapter;
        _try(
            vault.delegator,
            abi.encodeCall(IUniversalDelegator.setAutoAllocateAdapters, (duplicateRoute)),
            "v2-auto-duplicate"
        );

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(IUniversalDelegator.setLimits, (set.appAdapter, amount * 5, MAX_SHARE));
        calls[1] = abi.encodeCall(IUniversalDelegator.setAutoAllocateAdapters, (_route(set, 0)));
        _try(vault.delegator, abi.encodeWithSignature("multicall(bytes[])", calls), "v2-delegator-multicall");

        _try(
            vault.delegator,
            abi.encodeWithSignature("grantRole(bytes32,address)", ALLOCATE_ROLE, actors.staker),
            "v2-grant-staker-allocate"
        );
        vm.stopPrank();

        vm.prank(actors.staker);
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.allocateAll, (amount)), "v2-staker-allocate");

        vm.prank(actors.operator);
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.addAdapter, (set.appAdapter)), "v2-add-unauthorized");
    }

    function _exerciseV2TokenFlows(Actors memory actors, V2Vault memory vault, uint256 amount) internal {
        _try(vault.vault, abi.encodeCall(IERC4626.asset, ()), "v2-erc4626-asset");
        _try(vault.vault, abi.encodeCall(IERC4626.totalAssets, ()), "v2-erc4626-total-assets");
        _try(vault.vault, abi.encodeCall(IERC4626.convertToShares, (amount)), "v2-convert-shares");
        _try(vault.vault, abi.encodeCall(IERC4626.convertToAssets, (amount)), "v2-convert-assets");
        _try(vault.vault, abi.encodeCall(IERC4626.maxDeposit, (actors.staker)), "v2-max-deposit");
        _try(vault.vault, abi.encodeCall(IERC4626.maxMint, (actors.staker)), "v2-max-mint");
        _try(vault.vault, abi.encodeCall(IERC4626.maxWithdraw, (actors.staker)), "v2-max-withdraw");
        _try(vault.vault, abi.encodeCall(IERC4626.maxRedeem, (actors.staker)), "v2-max-redeem");
        _try(vault.vault, abi.encodeCall(IERC4626.previewDeposit, (amount)), "v2-preview-deposit");
        _try(vault.vault, abi.encodeCall(IERC4626.previewMint, (amount / 4)), "v2-preview-mint");
        _try(vault.vault, abi.encodeCall(IERC4626.previewWithdraw, (amount / 4)), "v2-preview-withdraw");
        _try(vault.vault, abi.encodeCall(IERC4626.previewRedeem, (amount / 4)), "v2-preview-redeem");

        vm.startPrank(actors.staker);
        IERC20(vault.asset).approve(vault.vault, amount * 4);
        _try(vault.vault, abi.encodeCall(IERC4626.deposit, (amount, actors.staker)), "v2-deposit");
        _try(vault.vault, abi.encodeCall(IERC4626.mint, (amount / 4, actors.staker)), "v2-mint");
        _try(vault.vault, abi.encodeCall(IERC20.approve, (actors.network, amount / 5)), "v2-share-approve");
        _try(vault.vault, abi.encodeCall(IERC20.transfer, (actors.burner, amount / 10)), "v2-share-transfer");
        vm.stopPrank();

        vm.prank(vault.delegator);
        _try(vault.vault, abi.encodeCall(IVaultV2.pull, (amount / 100, actors.network)), "v2-pull-valid");

        vm.prank(vault.delegator);
        _try(vault.vault, abi.encodeCall(IVaultV2.push, (amount / 100, actors.staker)), "v2-push-valid");

        vm.prank(actors.network);
        _try(
            vault.vault,
            abi.encodeCall(IERC20.transferFrom, (actors.staker, actors.network, amount / 20)),
            "v2-share-transfer-from"
        );

        vm.startPrank(actors.staker);
        _try(vault.vault, abi.encodeCall(IERC4626.withdraw, (amount / 5, actors.staker, actors.staker)), "v2-withdraw");
        _try(vault.vault, abi.encodeCall(IERC4626.redeem, (amount / 10, actors.staker, actors.staker)), "v2-redeem");
        _try(vault.vault, abi.encodeCall(IERC4626.deposit, (amount / 2, actors.staker)), "v2-redeposit");
        vm.stopPrank();
    }

    function _exerciseV2LiquidLane(
        address owner,
        Actors memory actors,
        V2AdapterSet memory set,
        LiquidLaneAssets memory liquidLaneAssets,
        uint256 amount
    ) internal {
        if (set.liquidLaneAdapter == address(0)) {
            return;
        }

        vm.startPrank(owner);
        _try(
            set.liquidLaneAdapter,
            abi.encodeCall(ILiquidLaneAdapter.setMarketMaker, (actors.staker, false)),
            "v2-ll-market-maker"
        );
        _try(
            set.liquidLaneAdapter,
            abi.encodeCall(ILiquidLaneAdapter.setFiller, (actors.middleware, true)),
            "v2-ll-filler"
        );
        _try(
            set.liquidLaneAdapter,
            abi.encodeCall(ILiquidLaneAdapter.addTokenToRedeem, (liquidLaneAssets.mFone)),
            "v2-ll-add-mfone"
        );
        _try(
            set.liquidLaneAdapter,
            abi.encodeCall(ILiquidLaneAdapter.addTokenToRedeem, (liquidLaneAssets.mGlobal)),
            "v2-ll-add-mglobal"
        );
        _try(
            set.liquidLaneAdapter,
            abi.encodeCall(ILiquidLaneAdapter.setLimit, (liquidLaneAssets.mFone, amount * 10)),
            "v2-ll-limit-mfone"
        );
        _try(
            set.liquidLaneAdapter,
            abi.encodeCall(ILiquidLaneAdapter.setLimit, (liquidLaneAssets.mGlobal, amount * 10)),
            "v2-ll-limit-mglobal"
        );
        _try(
            set.liquidLaneAdapter,
            abi.encodeCall(ILiquidLaneAdapter.setMinDiscount, (liquidLaneAssets.mFone, 0)),
            "v2-ll-discount-mfone"
        );
        _try(
            set.liquidLaneAdapter,
            abi.encodeCall(ILiquidLaneAdapter.setMinDiscount, (liquidLaneAssets.mGlobal, 0)),
            "v2-ll-discount-mglobal"
        );
        vm.stopPrank();

        _exerciseV2LiquidLaneSwap(actors, set, liquidLaneAssets.mFone, amount / 10);
        _exerciseV2LiquidLaneSwap(actors, set, liquidLaneAssets.mGlobal, amount / 12);

        _try(set.liquidLaneAdapter, abi.encodeCall(ILiquidLaneAdapter.getTokensToRedeemLength, ()), "v2-ll-tokens");
        _try(
            set.liquidLaneAdapter,
            abi.encodeCall(ILiquidLaneAdapter.getMaxAssets, (liquidLaneAssets.mFone)),
            "v2-ll-max-assets"
        );
        _try(
            set.liquidLaneAdapter,
            abi.encodeCall(ILiquidLaneAdapter.getMaxRate, (liquidLaneAssets.mGlobal)),
            "v2-ll-max-rate"
        );
    }

    function _exerciseV2LiquidLaneSwap(
        Actors memory actors,
        V2AdapterSet memory set,
        address tokenToRedeem,
        uint256 amountIn
    ) internal {
        uint256 quotedOut = ILiquidLaneAdapter(set.liquidLaneAdapter).getAmountOut(tokenToRedeem, amountIn);
        if (quotedOut == 0) {
            return;
        }

        ChaosERC20Mock(tokenToRedeem).mint(actors.staker, amountIn);

        vm.startPrank(actors.staker);
        IERC20(tokenToRedeem).transfer(set.liquidLaneAdapter, amountIn);
        _try(
            set.liquidLaneAdapter,
            abi.encodeWithSignature(
                "swap((address,address,uint256,uint256))",
                ILiquidLaneAdapter.Swap({
                    recipient: actors.staker, tokenIn: tokenToRedeem, amountIn: amountIn, amountOut: quotedOut / 2
                })
            ),
            "v2-ll-swap"
        );
        vm.stopPrank();
    }

    function _exerciseV2AdapterHooks(
        address owner,
        Actors memory actors,
        V2Vault memory vault,
        V2AdapterSet memory set,
        uint256 amount,
        uint256 salt
    ) internal {
        address[] memory list = _route(set, 0);
        bytes memory order = abi.encode(
            ICoWSwapConverter.OrderParams({
                buyAmount: amount / 100,
                validTo: uint32(vm.getBlockTimestamp() + 10 minutes),
                appData: keccak256(abi.encode(salt, "cow"))
            })
        );

        for (uint256 i; i < list.length; ++i) {
            _exerciseV2AdapterViews(list[i]);
            _exerciseV2AdapterConverterHooks(owner, actors.staker, list[i], vault.asset, amount, order);
            _exerciseV2AdapterMerklAndDeallocation(owner, list[i], amount);
        }

        _try(set.aaveAdapter, abi.encodeCall(IAaveV3Adapter.aToken, ()), "v2-aave-token");
        _try(set.morphoAdapter, abi.encodeCall(IMorphoVaultV2Adapter.morphoVault, ()), "v2-morpho-vault");
        _try(set.morphoAdapter, abi.encodeWithSignature("deposit(uint256)", amount / 100), "v2-morpho-direct-deposit");
        _try(set.appAdapter, abi.encodeCall(IAppAdapter.asset, ()), "v2-app-asset");
        _try(set.appAdapter, abi.encodeCall(IAppAdapter.burner, ()), "v2-app-burner");
        _try(set.appAdapter, abi.encodeCall(IAppAdapter.duration, ()), "v2-app-duration");
        _try(set.appAdapter, abi.encodeCall(IAppAdapter.operator, ()), "v2-app-operator");
        _try(set.appAdapter, abi.encodeCall(IAppAdapter.subnetwork, ()), "v2-app-subnetwork");
        _try(set.appAdapter, abi.encodeCall(IAppAdapter.stake, ()), "v2-app-stake");
        _try(set.appAdapter, abi.encodeCall(IAppAdapter.stakeAt, (_past())), "v2-app-stake-at");
        _try(set.appAdapter, abi.encodeCall(IAppAdapter.slashable, ()), "v2-app-slashable");

        vm.prank(actors.middleware);
        _try(set.appAdapter, abi.encodeCall(IAppAdapter.slash, (amount / 20)), "v2-app-slash");

        vm.prank(actors.network);
        _try(set.appAdapter, abi.encodeCall(IAppAdapter.release, (amount / 20)), "v2-app-release");

        vm.prank(owner);
        _try(set.appAdapter, abi.encodeCall(IAdapter.allocate, (amount / 10)), "v2-adapter-direct-allocate");
    }

    function _exerciseV2AdapterViews(address adapter) internal {
        _try(adapter, abi.encodeCall(IAdapter.vault, ()), "v2-adapter-vault");
        _try(adapter, abi.encodeCall(IAdapter.allocatable, ()), "v2-adapter-allocatable");
        _try(adapter, abi.encodeCall(IAdapter.totalAssets, ()), "v2-adapter-total-assets");
        _try(adapter, abi.encodeCall(IAdapter.freeAssets, ()), "v2-adapter-free-assets");

        bytes[] memory calls = new bytes[](2);
        calls[0] = abi.encodeCall(IAdapter.totalAssets, ());
        calls[1] = abi.encodeCall(IAdapter.freeAssets, ());
        _try(adapter, abi.encodeWithSignature("multicall(bytes[])", calls), "v2-adapter-multicall");
    }

    function _exerciseV2AdapterConverterHooks(
        address owner,
        address staker,
        address adapter,
        address asset,
        uint256 amount,
        bytes memory order
    ) internal {
        address[] memory converters = new address[](1);
        converters[0] = staker;
        address[] memory emptyConverters = new address[](0);
        vm.startPrank(owner);
        _try(adapter, abi.encodeCall(ICoWSwapConverter.setConverters, (converters)), "v2-cow-on");
        _try(adapter, abi.encodeCall(ICoWSwapConverter.setConverters, (emptyConverters)), "v2-cow-off");
        vm.stopPrank();

        vm.prank(staker);
        _try(
            adapter,
            abi.encodeCall(ICoWSwapConverter.prepareConvert, (asset, amount / 100, asset, order)),
            "v2-cow-prepare"
        );
        vm.prank(staker);
        _try(adapter, abi.encodeCall(IConverter.convert, (asset, amount / 100, asset, order)), "v2-cow-convert");
    }

    function _exerciseV2AdapterMerklAndDeallocation(address owner, address adapter, uint256 amount) internal {
        address[] memory rewardTokens = new address[](0);
        uint256[] memory rewardAmounts = new uint256[](0);
        bytes32[][] memory rewardProofs = new bytes32[][](0);
        _try(adapter, abi.encodeCall(IMerklClaimer.claim, (rewardTokens, rewardAmounts, rewardProofs)), "v2-merkl");

        vm.prank(owner);
        _try(adapter, abi.encodeCall(IAdapter.deallocate, (amount / 100)), "v2-adapter-direct-deallocate");

        vm.prank(owner);
        _try(adapter, abi.encodeCall(IAdapter.requestDeallocate, (amount / 100)), "v2-adapter-direct-request");
    }

    function _exerciseV2QueueAndDeallocation(
        address owner,
        Actors memory actors,
        V2Vault memory vault,
        V2AdapterSet memory set,
        uint256 amount
    ) internal {
        vm.startPrank(owner);
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.totalAssets, ()), "v2-delegator-total-assets");
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.VERSION, ()), "v2-delegator-version");
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.vault, ()), "v2-delegator-vault");
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.totalAdapters, ()), "v2-total-adapters");
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.adapters, (0)), "v2-adapters-0");
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.adaptersWithPending, (0)), "v2-pending-adapter-0");
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.autoAllocateAdapters, (0)), "v2-auto-0");
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.indexToAdapter, (uint16(1))), "v2-index-adapter");
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.adapterToIndex, (set.appAdapter)), "v2-adapter-index");
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.shareLimitOf, (set.appAdapter)), "v2-share-limit");
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.absoluteLimitOf, (set.appAdapter)), "v2-abs-limit");
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.limitOf, (set.appAdapter)), "v2-limit-of");
        _try(
            vault.delegator,
            abi.encodeCall(IUniversalDelegator.allocate, (set.appAdapter, amount / 4)),
            "v2-allocate-app"
        );
        _try(
            vault.delegator,
            abi.encodeCall(IUniversalDelegator.allocate, (set.aaveAdapter, amount / 4)),
            "v2-allocate-aave"
        );
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.allocateAll, (type(uint256).max)), "v2-allocate-all");
        _try(vault.delegator, abi.encodeWithSignature("deallocatable()"), "v2-deallocatable");
        _try(
            vault.delegator,
            abi.encodeCall(IUniversalDelegator.deallocate, (set.aaveAdapter, amount / 8)),
            "v2-dealloc-aave"
        );
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.deallocateAll, (amount / 8)), "v2-dealloc-all");
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.deallocateExact, (amount / 10)), "v2-dealloc-exact");
        _try(
            vault.delegator,
            abi.encodeCall(IUniversalDelegator.forceDeallocate, (set.appAdapter, amount / 6)),
            "v2-force-dealloc"
        );
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.sweepPending, ()), "v2-sweep");
        _try(
            vault.delegator,
            abi.encodeCall(IUniversalDelegator.swapAdapters, (set.appAdapter, set.aaveAdapter)),
            "v2-swap-app-aave"
        );
        _try(
            vault.delegator, abi.encodeCall(IUniversalDelegator.removeAdapter, (set.morphoAdapter)), "v2-remove-morpho"
        );
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.addAdapter, (set.morphoAdapter)), "v2-readd-morpho");
        _try(
            vault.delegator,
            abi.encodeCall(IUniversalDelegator.setAutoAllocateAdapters, (_route(set, 0))),
            "v2-auto-reset"
        );
        vm.stopPrank();

        vm.prank(set.appAdapter);
        _try(
            vault.delegator,
            abi.encodeCall(IUniversalDelegator.decreaseLimits, (amount / 100, MAX_SHARE / 100)),
            "v2-decrease-limits"
        );

        vm.prank(owner);
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.onDeposit, ()), "v2-on-deposit-direct");

        vm.prank(owner);
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.onWithdraw, (amount / 10)), "v2-on-withdraw-direct");

        _try(vault.delegator, abi.encodeWithSignature("__deallocateAll()"), "v2-self-deallocate-all-direct");

        uint256 tokenId = IWithdrawalQueue(vault.withdrawalQueue).totalRequests();
        uint256 requestShares = IERC20(vault.vault).balanceOf(actors.staker) / 4;
        vm.startPrank(actors.staker);
        IERC20(vault.vault).approve(vault.withdrawalQueue, requestShares * 2);
        _try(
            vault.withdrawalQueue,
            abi.encodeCall(IWithdrawalQueue.requestRedeem, (requestShares, actors.staker)),
            "v2-queue-request-staker"
        );
        _try(
            vault.withdrawalQueue,
            abi.encodeCall(IWithdrawalQueue.requestRedeem, (requestShares / 2, owner)),
            "v2-queue-request-owner"
        );
        vm.stopPrank();

        _try(vault.withdrawalQueue, abi.encodeCall(IWithdrawalQueue.vault, ()), "v2-queue-vault");
        _try(vault.withdrawalQueue, abi.encodeCall(IWithdrawalQueue.totalRequested, ()), "v2-queue-total-requested");
        _try(vault.withdrawalQueue, abi.encodeCall(IWithdrawalQueue.totalRequests, ()), "v2-queue-total-requests");
        _try(vault.withdrawalQueue, abi.encodeCall(IWithdrawalQueue.totalFilled, ()), "v2-queue-total-filled");
        _try(vault.withdrawalQueue, abi.encodeCall(IWithdrawalQueue.pendingShares, ()), "v2-queue-pending-shares");
        _try(vault.withdrawalQueue, abi.encodeCall(IWithdrawalQueue.pendingAssets, ()), "v2-queue-pending-assets");
        _try(vault.withdrawalQueue, abi.encodeCall(IWithdrawalQueue.requests, (tokenId)), "v2-queue-request-view");
        _try(vault.withdrawalQueue, abi.encodeCall(IWithdrawalQueue.claimable, (tokenId)), "v2-queue-claimable");
        _try(vault.withdrawalQueue, abi.encodeCall(IWithdrawalQueue.fill, ()), "v2-queue-fill");
        _try(vault.delegator, abi.encodeCall(IUniversalDelegator.sweepPending, ()), "v2-queue-sweep");
        vm.prank(actors.staker);
        _try(vault.withdrawalQueue, abi.encodeCall(IWithdrawalQueue.claim, (tokenId, actors.staker)), "v2-queue-claim");
        _try(vault.withdrawalQueue, abi.encodeCall(IWithdrawalQueue.isClaimed, (tokenId)), "v2-queue-claimed");
        _try(vault.withdrawalQueue, abi.encodeWithSignature("ownerOf(uint256)", tokenId), "v2-queue-owner-of");
        _try(vault.withdrawalQueue, abi.encodeWithSignature("tokenURI(uint256)", tokenId), "v2-queue-token-uri");
    }

    function _exerciseV2Factories(
        SymbioticCoreConstants.Core memory core,
        address owner,
        V2Vault[] memory vaults,
        AdapterDeployments memory adapters
    ) internal {
        vm.startPrank(owner);
        _try(address(core.vaultFactory), abi.encodeWithSignature("lastVersion()"), "v2-vault-factory-last");
        _try(address(core.vaultFactory), abi.encodeWithSignature("totalEntities()"), "v2-vault-factory-total");
        _try(address(core.vaultFactory), abi.encodeWithSignature("entity(uint256)", 0), "v2-vault-factory-entity");
        _try(
            address(core.vaultFactory),
            abi.encodeWithSignature("isEntity(address)", vaults[0].vault),
            "v2-vault-factory-is-entity"
        );
        _try(
            address(core.vaultFactory),
            abi.encodeWithSignature("implementation(uint64)", VAULT_V2_VERSION),
            "v2-vault-factory-impl"
        );
        _try(
            address(core.vaultFactory),
            abi.encodeWithSignature("blacklisted(uint64)", VAULT_V2_VERSION),
            "v2-vault-factory-blacklisted"
        );
        _try(
            address(core.vaultFactory),
            abi.encodeWithSignature("migrate(address,uint64,bytes)", vaults[0].vault, VAULT_V2_VERSION, bytes("")),
            "v2-vault-factory-migrate-same"
        );
        _try(address(core.delegatorFactory), abi.encodeWithSignature("lastVersion()"), "v2-delegator-factory-last");
        _try(address(core.delegatorFactory), abi.encodeWithSignature("totalTypes()"), "v2-delegator-factory-types");
        _try(address(core.delegatorFactory), abi.encodeWithSignature("totalEntities()"), "v2-delegator-factory-total");
        _try(
            address(core.delegatorFactory), abi.encodeWithSignature("entity(uint256)", 0), "v2-delegator-factory-entity"
        );
        _try(
            address(core.delegatorFactory),
            abi.encodeWithSignature("isEntity(address)", vaults[0].delegator),
            "v2-delegator-factory-is-entity"
        );
        _try(
            address(core.delegatorFactory),
            abi.encodeWithSignature("implementation(uint64)", UNIVERSAL_DELEGATOR_TYPE),
            "v2-delegator-factory-impl"
        );
        _try(
            address(core.delegatorFactory),
            abi.encodeWithSignature("blacklisted(uint64)", UNIVERSAL_DELEGATOR_TYPE),
            "v2-delegator-factory-blacklisted"
        );
        _try(
            address(core.delegatorFactory),
            abi.encodeWithSignature(
                "migrate(address,uint64,bytes)", vaults[0].delegator, UNIVERSAL_DELEGATOR_TYPE, bytes("")
            ),
            "v2-delegator-factory-migrate-same"
        );

        for (uint256 i; i < adapters.sets.length; ++i) {
            _try(adapters.sets[i].appFactory, abi.encodeWithSignature("lastVersion()"), "v2-app-factory-last");
            _try(adapters.sets[i].aaveFactory, abi.encodeWithSignature("lastVersion()"), "v2-aave-factory-last");
            _try(adapters.sets[i].morphoFactory, abi.encodeWithSignature("lastVersion()"), "v2-morpho-factory-last");
            if (adapters.sets[i].liquidLaneFactory != address(0)) {
                _exerciseV2LiquidLaneFactories(adapters.sets[i]);
            }
            _try(adapters.sets[i].appFactory, abi.encodeWithSignature("totalEntities()"), "v2-app-factory-total");
            _try(adapters.sets[i].aaveFactory, abi.encodeWithSignature("totalEntities()"), "v2-aave-factory-total");
            _try(adapters.sets[i].morphoFactory, abi.encodeWithSignature("totalEntities()"), "v2-morpho-factory-total");
            _try(adapters.sets[i].appFactory, abi.encodeWithSignature("entity(uint256)", 0), "v2-app-factory-entity");
            _try(adapters.sets[i].aaveFactory, abi.encodeWithSignature("entity(uint256)", 0), "v2-aave-factory-entity");
            _try(
                adapters.sets[i].morphoFactory,
                abi.encodeWithSignature("entity(uint256)", 0),
                "v2-morpho-factory-entity"
            );
            _try(
                adapters.sets[i].appFactory,
                abi.encodeWithSignature("isEntity(address)", adapters.sets[i].appAdapter),
                "v2-app-factory-is-entity"
            );
            _try(
                adapters.sets[i].aaveFactory,
                abi.encodeWithSignature("isEntity(address)", adapters.sets[i].aaveAdapter),
                "v2-aave-factory-is-entity"
            );
            _try(
                adapters.sets[i].morphoFactory,
                abi.encodeWithSignature("isEntity(address)", adapters.sets[i].morphoAdapter),
                "v2-morpho-factory-is-entity"
            );
            _try(
                adapters.sets[i].appFactory, abi.encodeWithSignature("implementation(uint64)", 1), "v2-app-factory-impl"
            );
            _try(
                adapters.sets[i].aaveFactory,
                abi.encodeWithSignature("implementation(uint64)", 1),
                "v2-aave-factory-impl"
            );
            _try(
                adapters.sets[i].morphoFactory,
                abi.encodeWithSignature("implementation(uint64)", 1),
                "v2-morpho-factory-impl"
            );
            _try(
                adapters.sets[i].appFactory,
                abi.encodeWithSignature("blacklisted(uint64)", 1),
                "v2-app-factory-blacklisted"
            );
            _try(
                adapters.sets[i].aaveFactory,
                abi.encodeWithSignature("blacklisted(uint64)", 1),
                "v2-aave-factory-blacklisted"
            );
            _try(
                adapters.sets[i].morphoFactory,
                abi.encodeWithSignature("blacklisted(uint64)", 1),
                "v2-morpho-factory-blacklisted"
            );
            _try(
                adapters.sets[i].appFactory,
                abi.encodeWithSignature("migrate(address,uint64,bytes)", adapters.sets[i].appAdapter, 1, bytes("")),
                "v2-app-factory-migrate-same"
            );
            _try(
                adapters.sets[i].aaveFactory,
                abi.encodeWithSignature("migrate(address,uint64,bytes)", adapters.sets[i].aaveAdapter, 1, bytes("")),
                "v2-aave-factory-migrate-same"
            );
            _try(
                adapters.sets[i].morphoFactory,
                abi.encodeWithSignature("migrate(address,uint64,bytes)", adapters.sets[i].morphoAdapter, 1, bytes("")),
                "v2-morpho-factory-migrate-same"
            );
            _try(
                adapters.sets[i].appFactory,
                abi.encodeWithSignature("whitelist(address)", address(0)),
                "v2-app-factory-whitelist-zero"
            );
            _try(
                adapters.sets[i].aaveFactory,
                abi.encodeWithSignature("blacklist(uint64)", 0),
                "v2-aave-factory-blacklist-zero"
            );
            _try(
                adapters.sets[i].morphoFactory,
                abi.encodeWithSignature("blacklist(uint64)", 1),
                "v2-morpho-factory-blacklist"
            );
        }
        vm.stopPrank();
    }

    function _exerciseV2LiquidLaneFactories(V2AdapterSet memory set) internal {
        _try(set.liquidLaneFactory, abi.encodeWithSignature("lastVersion()"), "v2-ll-factory-last");
        _try(set.liquidLaneFactory, abi.encodeWithSignature("totalEntities()"), "v2-ll-factory-total");
        _try(set.liquidLaneFactory, abi.encodeWithSignature("entity(uint256)", 0), "v2-ll-factory-entity");
        _try(
            set.liquidLaneFactory,
            abi.encodeWithSignature("isEntity(address)", set.liquidLaneAdapter),
            "v2-ll-factory-is-entity"
        );
        _try(set.liquidLaneFactory, abi.encodeWithSignature("implementation(uint64)", 1), "v2-ll-factory-impl");
        _try(set.liquidLaneFactory, abi.encodeWithSignature("blacklisted(uint64)", 1), "v2-ll-factory-blacklisted");
        _try(
            set.liquidLaneFactory,
            abi.encodeWithSignature("migrate(address,uint64,bytes)", set.liquidLaneAdapter, 1, bytes("")),
            "v2-ll-factory-migrate-same"
        );
        _try(set.mFoneAccountFactory, abi.encodeWithSignature("lastVersion()"), "v2-mfone-factory-last");
        _try(set.mGlobalAccountFactory, abi.encodeWithSignature("lastVersion()"), "v2-mglobal-factory-last");
        _try(set.mFoneAccountFactory, abi.encodeWithSignature("totalEntities()"), "v2-mfone-factory-total");
        _try(set.mGlobalAccountFactory, abi.encodeWithSignature("totalEntities()"), "v2-mglobal-factory-total");
        _try(set.mFoneAccountFactory, abi.encodeWithSignature("entity(uint256)", 0), "v2-mfone-factory-entity");
        _try(set.mGlobalAccountFactory, abi.encodeWithSignature("entity(uint256)", 0), "v2-mglobal-factory-entity");
        _try(set.accountRegistry, abi.encodeWithSignature("owner()"), "v2-ll-reg-owner");
    }

    function _grantV2Roles(address vault, address account) internal {
        _try(
            vault, abi.encodeWithSignature("grantRole(bytes32,address)", MANAGEMENT_FEE_ROLE, account), "v2-grant-mgmt"
        );
        _try(
            vault, abi.encodeWithSignature("grantRole(bytes32,address)", PERFORMANCE_FEE_ROLE, account), "v2-grant-perf"
        );
        _try(
            vault,
            abi.encodeWithSignature("grantRole(bytes32,address)", DEPOSIT_LIMIT_SET_ROLE, account),
            "v2-grant-limit"
        );
        _try(
            vault,
            abi.encodeWithSignature("grantRole(bytes32,address)", DEPOSITOR_WHITELIST_ROLE, account),
            "v2-grant-dep"
        );
        _try(
            vault,
            abi.encodeWithSignature("grantRole(bytes32,address)", IS_DEPOSIT_LIMIT_SET_ROLE, account),
            "v2-grant-limit-toggle"
        );
        _try(
            vault,
            abi.encodeWithSignature("grantRole(bytes32,address)", DEPOSIT_WHITELIST_SET_ROLE, account),
            "v2-grant-whitelist-toggle"
        );
    }

    function _grantDelegatorRoles(address delegator, address account) internal {
        _try(
            delegator,
            abi.encodeWithSignature("grantRole(bytes32,address)", ADD_ADAPTER_ROLE, account),
            "v2-grant-add-adapter"
        );
        _try(
            delegator,
            abi.encodeWithSignature("grantRole(bytes32,address)", REMOVE_ADAPTER_ROLE, account),
            "v2-grant-remove-adapter"
        );
        _try(
            delegator,
            abi.encodeWithSignature("grantRole(bytes32,address)", SET_ADAPTER_LIMITS_ROLE, account),
            "v2-grant-set-limits"
        );
        _try(
            delegator,
            abi.encodeWithSignature("grantRole(bytes32,address)", SET_AUTO_ALLOCATE_ADAPTERS_ROLE, account),
            "v2-grant-set-auto"
        );
        _try(
            delegator,
            abi.encodeWithSignature("grantRole(bytes32,address)", SWAP_ADAPTERS_ROLE, account),
            "v2-grant-swap"
        );
        _try(
            delegator,
            abi.encodeWithSignature("grantRole(bytes32,address)", ALLOCATE_ROLE, account),
            "v2-grant-allocate"
        );
        _try(
            delegator,
            abi.encodeWithSignature("grantRole(bytes32,address)", DEALLOCATE_ROLE, account),
            "v2-grant-deallocate"
        );
        _try(
            delegator,
            abi.encodeWithSignature("grantRole(bytes32,address)", FORCE_DEALLOCATE_ROLE, account),
            "v2-grant-force-deallocate"
        );
    }

    function _route(V2AdapterSet memory set, uint256 mode) internal pure returns (address[] memory route) {
        uint256 routeLength = set.liquidLaneAdapter == address(0) ? 3 : 4;
        route = new address[](routeLength);
        if (mode == 1) {
            route[0] = set.morphoAdapter;
            route[1] = set.aaveAdapter;
            route[2] = set.appAdapter;
        } else {
            route[0] = set.appAdapter;
            route[1] = set.aaveAdapter;
            route[2] = set.morphoAdapter;
        }
        if (set.liquidLaneAdapter != address(0)) {
            route[3] = set.liquidLaneAdapter;
        }
    }

    function _v1VaultParams(address asset, address owner, address burner, uint64 i, uint256 seed)
        internal
        pure
        returns (IVault.InitParams memory)
    {
        return IVault.InitParams({
            collateral: asset,
            burner: burner,
            epochDuration: uint48(1 days + i * 1 hours),
            depositWhitelist: _flip(seed, i + 10),
            isDepositLimit: _flip(seed, i + 20),
            depositLimit: _amount(seed, i + 30, 1000 ether, 10_000 ether),
            defaultAdminRoleHolder: owner,
            depositWhitelistSetRoleHolder: owner,
            depositorWhitelistRoleHolder: owner,
            isDepositLimitSetRoleHolder: owner,
            depositLimitSetRoleHolder: owner
        });
    }

    function _delegatorParams(address owner, Actors memory actors, uint64 delegatorType)
        internal
        pure
        returns (bytes memory)
    {
        IBaseDelegator.BaseParams memory baseParams =
            IBaseDelegator.BaseParams({defaultAdminRoleHolder: owner, hook: address(0), hookSetRoleHolder: owner});

        if (delegatorType == 0) {
            return abi.encode(
                INetworkRestakeDelegator.InitParams({
                    baseParams: baseParams,
                    networkLimitSetRoleHolders: _singleton(owner),
                    operatorNetworkSharesSetRoleHolders: _singleton(owner)
                })
            );
        }
        if (delegatorType == 1) {
            return abi.encode(
                IFullRestakeDelegator.InitParams({
                    baseParams: baseParams,
                    networkLimitSetRoleHolders: _singleton(owner),
                    operatorNetworkLimitSetRoleHolders: _singleton(owner)
                })
            );
        }
        if (delegatorType == 2) {
            return abi.encode(
                IOperatorSpecificDelegator.InitParams({
                    baseParams: baseParams, networkLimitSetRoleHolders: _singleton(owner), operator: actors.operator
                })
            );
        }
        return abi.encode(
            IOperatorNetworkSpecificDelegator.InitParams({
                baseParams: baseParams, network: actors.network, operator: actors.operator
            })
        );
    }

    function _slasherParams(uint64 slasherType, uint64 i) internal pure returns (bytes memory) {
        IBaseSlasher.BaseParams memory baseParams = IBaseSlasher.BaseParams({isBurnerHook: i % 2 == 1});

        if (slasherType == 0) {
            return abi.encode(ISlasher.InitParams({baseParams: baseParams}));
        }
        return abi.encode(
            IVetoSlasher.InitParams({
                baseParams: baseParams, vetoDuration: uint48(2 hours + i * 5 minutes), resolverSetEpochsDelay: 3
            })
        );
    }

    function _register(SymbioticCoreConstants.Core memory core, Actors memory actors) internal {
        vm.prank(actors.network);
        core.networkRegistry.registerNetwork();

        vm.prank(actors.network);
        core.networkMiddlewareService.setMiddleware(actors.middleware);

        vm.prank(actors.operator);
        core.operatorRegistry.registerOperator();
    }

    function _deployLiquidLaneAssets() internal returns (LiquidLaneAssets memory assets) {
        ChaosERC20Mock tokenImplementation = new ChaosERC20Mock();
        _installChaosToken(CHAOS_USDC, address(tokenImplementation), "USD Coin", "USDC", 6);
        _installChaosToken(CHAOS_MFONE, address(tokenImplementation), "Midas mF-ONE", "mFONE", 18);
        _installChaosToken(CHAOS_MGLOBAL, address(tokenImplementation), "Midas mGLOBAL", "mGLOBAL", 18);

        ChaosERC20Mock aUsd = new ChaosERC20Mock();
        aUsd.initialize("Chaos aUSD", "aUSD", 18);

        assets = LiquidLaneAssets({usdc: CHAOS_USDC, aUsd: address(aUsd), mFone: CHAOS_MFONE, mGlobal: CHAOS_MGLOBAL});

        ChaosMidasDataFeedMock mFoneFeed = new ChaosMidasDataFeedMock(1e18);
        ChaosMidasDataFeedMock mGlobalFeed = new ChaosMidasDataFeedMock(1e18);
        ChaosMidasRedemptionVaultMock redemptionVaultImplementation = new ChaosMidasRedemptionVaultMock();
        _installMidasRedemptionVault(
            CHAOS_MFONE_REDEMPTION_VAULT,
            address(redemptionVaultImplementation),
            assets.mFone,
            assets.usdc,
            address(mFoneFeed)
        );
        _installMidasRedemptionVault(
            CHAOS_MGLOBAL_REDEMPTION_VAULT,
            address(redemptionVaultImplementation),
            assets.mGlobal,
            assets.usdc,
            address(mGlobalFeed)
        );
    }

    function _installChaosToken(
        address token,
        address implementation,
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) internal {
        vm.etch(token, implementation.code);
        ChaosERC20Mock(token).initialize(name, symbol, decimals_);
    }

    function _installMidasRedemptionVault(
        address redemptionVault,
        address implementation,
        address tokenToRedeem,
        address redemptionToken,
        address dataFeed
    ) internal {
        vm.etch(redemptionVault, implementation.code);
        ChaosMidasRedemptionVaultMock(redemptionVault).initialize(tokenToRedeem, redemptionToken, dataFeed);
    }

    function _fund(Actors memory actors, Token[3] memory tokens) internal {
        for (uint256 i; i < tokens.length; ++i) {
            IERC20(address(tokens[i])).transfer(actors.staker, 100_000 ether);
            IERC20(address(tokens[i])).transfer(actors.burner, 1 ether);
        }
    }

    function _fundLiquidLaneAssets(Actors memory actors, LiquidLaneAssets memory liquidLaneAssets) internal {
        uint256 amount = 1_000_000_000 ether;
        ChaosERC20Mock(liquidLaneAssets.usdc).mint(actors.staker, amount);
        ChaosERC20Mock(liquidLaneAssets.usdc).mint(actors.burner, amount);
        ChaosERC20Mock(liquidLaneAssets.aUsd).mint(actors.staker, amount);
        ChaosERC20Mock(liquidLaneAssets.aUsd).mint(actors.burner, amount);
        ChaosERC20Mock(liquidLaneAssets.mFone).mint(actors.staker, amount);
        ChaosERC20Mock(liquidLaneAssets.mGlobal).mint(actors.staker, amount);
    }

    function _configureProtocolFee(address owner, address protocolFeeRegistry) internal {
        vm.startPrank(owner);
        IProtocolFeeRegistry(protocolFeeRegistry).setGlobalReceiver(owner);
        IProtocolFeeRegistry(protocolFeeRegistry).setGlobalFee(1, 1);
        vm.stopPrank();
    }

    function _actors(uint256 seed) internal pure returns (Actors memory actors) {
        actors = Actors({
            burner: address(uint160(uint256(keccak256(abi.encode(seed, "burner"))))),
            staker: address(uint160(uint256(keccak256(abi.encode(seed, "staker"))))),
            network: address(uint160(uint256(keccak256(abi.encode(seed, "network"))))),
            operator: address(uint160(uint256(keccak256(abi.encode(seed, "operator"))))),
            middleware: address(uint160(uint256(keccak256(abi.encode(seed, "middleware")))))
        });
    }

    function _holder(address owner, Actors memory actors, uint64 salt) internal pure returns (address) {
        uint64 mode = salt % 5;
        if (mode == 0) {
            return address(0);
        }
        if (mode == 1) {
            return owner;
        }
        if (mode == 2) {
            return actors.staker;
        }
        if (mode == 3) {
            return actors.burner;
        }
        return actors.network;
    }

    function _nonZeroHolder(address owner, Actors memory actors, uint64 salt) internal pure returns (address holder) {
        holder = _holder(owner, actors, salt);
        if (holder == address(0)) {
            holder = owner;
        }
    }

    function _converterSet(address owner, Actors memory actors, uint256 salt)
        internal
        pure
        returns (address[] memory converters)
    {
        converters = new address[](3);
        converters[0] = owner;
        converters[1] = salt % 2 == 0 ? actors.staker : actors.network;
        converters[2] = salt % 3 == 0 ? actors.burner : actors.middleware;
    }

    function _coreFrom(DeployCoreBaseScript.CoreDeploymentData memory data)
        internal
        pure
        returns (SymbioticCoreConstants.Core memory core)
    {
        core = SymbioticCoreConstants.Core({
            vaultFactory: data.vaultFactory,
            delegatorFactory: data.delegatorFactory,
            slasherFactory: data.slasherFactory,
            networkRegistry: data.networkRegistry,
            networkMetadataService: data.networkMetadataService,
            networkMiddlewareService: data.networkMiddlewareService,
            operatorRegistry: data.operatorRegistry,
            operatorMetadataService: data.operatorMetadataService,
            operatorVaultOptInService: data.operatorVaultOptInService,
            operatorNetworkOptInService: data.operatorNetworkOptInService,
            vaultConfigurator: data.vaultConfigurator
        });
    }

    function _try(address target, bytes memory data, string memory label) internal returns (bool success) {
        (success,) = target.call(data);
        emit ChaosCall(keccak256(bytes(label)), success);
    }

    function _singleton(address value) internal pure returns (address[] memory values) {
        values = new address[](1);
        values[0] = value;
    }

    function _amount(uint256 seed, uint256 salt, uint256 min, uint256 max) internal pure returns (uint256) {
        return min + uint256(keccak256(abi.encode(seed, salt))) % (max - min + 1);
    }

    function _flip(uint256 seed, uint256 salt) internal pure returns (bool) {
        return uint256(keccak256(abi.encode(seed, salt))) % 2 == 1;
    }

    function _past() internal view returns (uint48) {
        uint256 timestamp = vm.getBlockTimestamp();
        return uint48(timestamp > 0 ? timestamp - 1 : 0);
    }

    function _scriptOwner() internal view returns (address owner) {
        (,, address origin) = vm.readCallers();
        owner = origin == address(0) ? msg.sender : origin;
    }
}

contract ChaosERC20Mock {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    bool internal _initialized;

    mapping(address account => uint256 amount) public balanceOf;
    mapping(address owner => mapping(address spender => uint256 amount)) public allowance;

    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function initialize(string memory name_, string memory symbol_, uint8 decimals_) external {
        require(!_initialized, "already initialized");
        _initialized = true;
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 currentAllowance = allowance[from][msg.sender];
        if (currentAllowance != type(uint256).max) {
            allowance[from][msg.sender] = currentAllowance - amount;
            emit Approval(from, msg.sender, currentAllowance - amount);
        }

        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

contract ChaosMidasDataFeedMock {
    uint256 public answer;

    constructor(uint256 answer_) {
        answer = answer_;
    }

    function getDataInBase18() external view returns (uint256) {
        return answer;
    }
}

contract ChaosMidasRedemptionVaultMock {
    uint8 internal constant REQUEST_STATUS_PROCESSED = 1;

    struct Request {
        address sender;
        address tokenOut;
        uint8 status;
        uint256 amountMToken;
        uint256 mTokenRate;
        uint256 tokenOutRate;
    }

    address public tokenToRedeem;
    address public redemptionToken;
    address public mTokenDataFeed;
    uint256 public currentRequestId;

    bool internal _initialized;

    mapping(address token => address dataFeed) public dataFeedOf;
    mapping(uint256 requestId => Request request) internal _requests;

    function initialize(address tokenToRedeem_, address redemptionToken_, address mTokenDataFeed_) external {
        require(!_initialized, "already initialized");
        _initialized = true;
        tokenToRedeem = tokenToRedeem_;
        redemptionToken = redemptionToken_;
        mTokenDataFeed = mTokenDataFeed_;
        dataFeedOf[redemptionToken_] = mTokenDataFeed_;
    }

    function tokensConfig(address token)
        external
        view
        returns (address dataFeed, uint256 fee, uint256 allowance_, bool stable)
    {
        dataFeed = dataFeedOf[token];
        allowance_ = type(uint256).max;
        stable = token == redemptionToken;
    }

    function redeemRequest(address tokenOut, uint256 amountMTokenIn) external returns (uint256 requestId) {
        require(IERC20(tokenToRedeem).transferFrom(msg.sender, address(this), amountMTokenIn), "transfer-from");

        uint256 mTokenRate = ChaosMidasDataFeedMock(mTokenDataFeed).getDataInBase18();
        uint256 tokenOutRate = _tokenRate(tokenOut);
        requestId = currentRequestId++;
        _requests[requestId] = Request({
            sender: msg.sender,
            tokenOut: tokenOut,
            status: REQUEST_STATUS_PROCESSED,
            amountMToken: amountMTokenIn,
            mTokenRate: mTokenRate,
            tokenOutRate: tokenOutRate
        });

        uint256 redemptionAmount = amountMTokenIn * mTokenRate * 10 ** ChaosERC20Mock(redemptionToken).decimals()
            / (1e18 * 10 ** ChaosERC20Mock(tokenToRedeem).decimals());
        ChaosERC20Mock(redemptionToken).mint(msg.sender, redemptionAmount);
    }

    function redeemRequests(uint256 requestId)
        external
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
        Request memory request = _requests[requestId];
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
        address dataFeed = dataFeedOf[token];
        if (dataFeed == address(0)) {
            return 1e18;
        }
        return ChaosMidasDataFeedMock(dataFeed).getDataInBase18();
    }
}
