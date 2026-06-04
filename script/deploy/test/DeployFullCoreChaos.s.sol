// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Script} from "forge-std/Script.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

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
import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";
import {IAdapterRegistry} from "../../../src/interfaces/IAdapterRegistry.sol";
import {IProtocolFeeRegistry} from "../../../src/interfaces/IProtocolFeeRegistry.sol";
import {IVaultConfigurator} from "../../../src/interfaces/IVaultConfigurator.sol";
import {IAaveV3Adapter} from "../../../src/interfaces/adapters/IAaveV3Adapter.sol";
import {IAppAdapter} from "../../../src/interfaces/adapters/IAppAdapter.sol";
import {IMorphoVaultV2Adapter} from "../../../src/interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {
    IUniversalDelegator,
    MAX_SHARE,
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
import {IVaultV2, VAULT_V2_VERSION} from "../../../src/interfaces/vault/IVaultV2.sol";
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

    struct Actors {
        address burner;
        address staker;
        address network;
        address operator;
        address middleware;
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
    }

    struct AdapterDeployments {
        address appFactory;
        address aaveFactory;
        address morphoFactory;
        address appAdapter;
        address aaveAdapter;
        address morphoAdapter;
    }

    event ChaosCall(bytes32 indexed label, bool success);

    function run() public {
        run(vm.envOr("CHAOS_SEED", uint256(0xC0A5)));
    }

    function run(uint256 seed) public {
        address owner = _scriptOwner();
        require(owner != address(0), "invalid owner");

        Logs.log(string.concat("Full core chaos seed: ", vm.toString(seed)));

        DeployCoreBaseScript.CoreDeploymentData memory coreData = new DeployCoreBaseScript().run(owner);
        SymbioticCoreConstants.Core memory core = _coreFrom(coreData);
        DeployV2BaseScript.DeploymentData memory v2 = new DeployFullCoreChaosV2Script(core).runBase(owner, owner);

        Token[3] memory tokens = [new Token("Chaos Alpha"), new Token("Chaos Beta"), new Token("Chaos Gamma")];
        Actors memory actors = _actors(seed);

        _fund(actors, tokens);
        _register(core, actors);
        _configureProtocolFee(owner, address(v2.protocolFeeRegistry));

        V1Vault[] memory v1Vaults = _createV1Vaults(core, owner, actors, tokens, seed);
        V2Vault[] memory v2Vaults = _createV2Vaults(core, owner, actors, tokens, seed);
        AdapterDeployments memory adapters = _deployAdapters(core, v2, owner, actors, v2Vaults[0], seed);

        _exerciseV1(owner, actors, v1Vaults, seed);
        _exerciseV2(owner, actors, v2Vaults, adapters, seed);

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
        uint256 seed
    ) internal returns (V2Vault[] memory vaults) {
        vaults = new V2Vault[](4);

        for (uint64 i; i < uint64(vaults.length); ++i) {
            address asset = address(tokens[(i + 1) % tokens.length]);
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
                            depositorToWhitelist: actors.staker,
                            isDepositLimit: _flip(seed, i + 100),
                            depositLimit: _amount(seed, i, 10_000 ether, 40_000 ether),
                            defaultAdminRoleHolder: owner,
                            depositWhitelistSetRoleHolder: owner,
                            depositorWhitelistRoleHolder: owner,
                            isDepositLimitSetRoleHolder: owner,
                            depositLimitSetRoleHolder: owner,
                            managementFeeRoleHolder: owner,
                            performanceFeeRoleHolder: owner
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
                                deallocateRoleHolder: owner
                            })
                        )
                    )
                );
            vaults[i].asset = asset;

            vm.prank(owner);
            IVaultV2(vaults[i].vault).setDelegator(vaults[i].delegator);
        }
    }

    function _deployAdapters(
        SymbioticCoreConstants.Core memory core,
        DeployV2BaseScript.DeploymentData memory v2,
        address owner,
        Actors memory actors,
        V2Vault memory vault,
        uint256 seed
    ) internal returns (AdapterDeployments memory adapters) {
        DeployAaveV3MocksBaseScript.DeploymentData memory aaveMocks =
            new DeployAaveV3MocksBaseScript().runBase(vault.asset);
        DeployMorphoVaultV2MocksBaseScript.DeploymentData memory morphoMocks = new DeployMorphoVaultV2MocksBaseScript()
            .runBase(
                DeployMorphoVaultV2MocksBaseScript.DeployParams({adapterRegistryOwner: owner, collateral: vault.asset})
            );

        adapters.appFactory =
        new DeployFullCoreChaosAppAdapterScript(address(core.vaultFactory))
        .runBase(
            DeployAppAdapterBaseScript.DeployParams({
                adapterFactoryOwner: owner,
                cowSwapSettlement: address(0xC05E7),
                cowSwapVaultRelayer: address(0xC0A7),
                networkMiddlewareService: address(core.networkMiddlewareService)
            })
        )
        .adapterFactory;
        adapters.aaveFactory =
        new DeployFullCoreChaosAaveV3AdapterScript(address(core.vaultFactory))
        .runBase(
            DeployAaveV3AdapterBaseScript.DeployParams({
                adapterFactoryOwner: owner,
                aavePool: aaveMocks.aavePool,
                cowSwapSettlement: address(0xA11CE),
                cowSwapVaultRelayer: address(0xA11CE2),
                merklDistributor: owner
            })
        )
        .adapterFactory;
        adapters.morphoFactory =
        new DeployFullCoreChaosMorphoVaultV2AdapterScript(address(core.vaultFactory))
        .runBase(
            DeployMorphoVaultV2AdapterBaseScript.DeployParams({
                adapterFactoryOwner: owner,
                morphoVaultFactory: morphoMocks.morphoVaultFactory,
                morphoAdapterRegistry: morphoMocks.morphoAdapterRegistry,
                cowSwapSettlement: address(0xBEEF1),
                cowSwapVaultRelayer: address(0xBEEF2),
                merklDistributor: owner
            })
        )
        .adapterFactory;

        address[] memory converters = _singleton(owner);
        adapters.appAdapter = AdapterFactory(adapters.appFactory)
            .create(
                1,
                owner,
                abi.encode(
                    vault.vault,
                    abi.encode(
                        IAppAdapter.InitParams({
                        burner: actors.burner,
                        duration: uint48(10 + seed % 100),
                        operator: actors.operator,
                        subnetwork: actors.network.subnetwork(uint96(seed)),
                        converters: converters
                    })
                    )
                )
            );
        adapters.aaveAdapter = AdapterFactory(adapters.aaveFactory)
            .create(1, owner, abi.encode(vault.vault, abi.encode(IAaveV3Adapter.InitParams({converters: converters}))));
        adapters.morphoAdapter = AdapterFactory(adapters.morphoFactory)
            .create(
                1,
                owner,
                abi.encode(
                    vault.vault,
                    abi.encode(
                        IMorphoVaultV2Adapter.InitParams({morphoVault: morphoMocks.morphoVault, converters: converters})
                    )
                )
            );

        vm.startPrank(owner);
        IAdapterRegistry(address(v2.adapterRegistry)).setWhitelistedStatus(vault.vault, adapters.appAdapter, true);
        IAdapterRegistry(address(v2.adapterRegistry)).setWhitelistedStatus(vault.vault, adapters.aaveAdapter, true);
        IAdapterRegistry(address(v2.adapterRegistry)).setWhitelistedStatus(vault.vault, adapters.morphoAdapter, true);
        vm.stopPrank();
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
        address owner,
        Actors memory actors,
        V2Vault[] memory vaults,
        AdapterDeployments memory adapters,
        uint256 seed
    ) internal {
        address[] memory route = new address[](3);
        route[0] = adapters.appAdapter;
        route[1] = adapters.aaveAdapter;
        route[2] = adapters.morphoAdapter;

        for (uint256 i; i < vaults.length; ++i) {
            uint256 amount = _amount(seed, i + 400, 50 ether, 200 ether);

            vm.startPrank(owner);
            _try(vaults[i].vault, abi.encodeCall(IVaultV2.setDepositWhitelist, (_flip(seed, i + 300))), "v2-whitelist");
            _try(vaults[i].vault, abi.encodeCall(IVaultV2.setDepositorWhitelistStatus, (actors.staker, true)), "v2-dep");
            _try(vaults[i].vault, abi.encodeCall(IVaultV2.setIsDepositLimit, (true)), "v2-limit-on");
            _try(vaults[i].vault, abi.encodeCall(IVaultV2.setDepositLimit, (amount * 4)), "v2-limit");
            _try(vaults[i].vault, abi.encodeCall(IVaultV2.setManagementFee, (uint96(1), owner)), "v2-mgmt-fee");
            _try(vaults[i].vault, abi.encodeCall(IVaultV2.setPerformanceFee, (uint96(1), owner)), "v2-perf-fee");
            vm.stopPrank();

            vm.startPrank(actors.staker);
            IERC20(vaults[i].asset).approve(vaults[i].vault, amount);
            _try(vaults[i].vault, abi.encodeCall(IERC4626.deposit, (amount, actors.staker)), "v2-deposit");
            _try(
                vaults[i].vault,
                abi.encodeCall(IERC4626.withdraw, (amount / 5, actors.staker, actors.staker)),
                "v2-withdraw"
            );
            _try(
                vaults[i].vault,
                abi.encodeCall(IERC4626.redeem, (amount / 10, actors.staker, actors.staker)),
                "v2-redeem"
            );
            vm.stopPrank();
        }

        vm.startPrank(owner);
        _try(vaults[0].delegator, abi.encodeCall(IUniversalDelegator.addAdapter, (adapters.appAdapter)), "add-app");
        _try(vaults[0].delegator, abi.encodeCall(IUniversalDelegator.addAdapter, (adapters.aaveAdapter)), "add-aave");
        _try(
            vaults[0].delegator, abi.encodeCall(IUniversalDelegator.addAdapter, (adapters.morphoAdapter)), "add-morpho"
        );
        _try(
            vaults[0].delegator,
            abi.encodeCall(IUniversalDelegator.setLimits, (adapters.appAdapter, 100 ether, MAX_SHARE)),
            "limit-app"
        );
        _try(
            vaults[0].delegator,
            abi.encodeCall(IUniversalDelegator.setLimits, (adapters.aaveAdapter, 100 ether, MAX_SHARE / 2)),
            "limit-aave"
        );
        _try(
            vaults[0].delegator,
            abi.encodeCall(IUniversalDelegator.setLimits, (adapters.morphoAdapter, 100 ether, MAX_SHARE / 2)),
            "limit-morpho"
        );
        _try(vaults[0].delegator, abi.encodeCall(IUniversalDelegator.setAutoAllocateAdapters, (route)), "auto-route");
        _try(vaults[0].delegator, abi.encodeCall(IUniversalDelegator.allocateAll, (type(uint256).max)), "allocate-all");
        _try(vaults[0].delegator, abi.encodeWithSignature("deallocatable()"), "deallocatable");
        _try(
            vaults[0].delegator,
            abi.encodeWithSignature("deallocatable(address)", adapters.appAdapter),
            "deallocatable-app"
        );
        _try(vaults[0].delegator, abi.encodeCall(IUniversalDelegator.deallocateAll, (10 ether)), "deallocate-all");
        _try(vaults[0].delegator, abi.encodeCall(IUniversalDelegator.deallocateExact, (10 ether)), "deallocate-exact");
        _try(
            vaults[0].delegator,
            abi.encodeCall(IUniversalDelegator.forceDeallocate, (adapters.appAdapter, 10 ether)),
            "force-deallocate"
        );
        _try(vaults[0].delegator, abi.encodeCall(IUniversalDelegator.sweepPending, ()), "sweep");
        _try(
            vaults[0].delegator,
            abi.encodeCall(IUniversalDelegator.swapAdapters, (adapters.appAdapter, adapters.aaveAdapter)),
            "swap"
        );
        _try(vaults[0].delegator, abi.encodeCall(IUniversalDelegator.removeAdapter, (adapters.morphoAdapter)), "remove");
        vm.stopPrank();

        vm.prank(actors.middleware);
        _try(adapters.appAdapter, abi.encodeCall(IAppAdapter.slash, (1 ether)), "app-slash");

        vm.prank(actors.network);
        _try(adapters.appAdapter, abi.encodeCall(IAppAdapter.release, (1 ether)), "app-release");

        vm.startPrank(actors.staker);
        IERC20(vaults[0].asset).approve(vaults[0].vault, 10 ether);
        _try(vaults[0].vault, abi.encodeCall(IERC4626.deposit, (10 ether, actors.staker)), "v2-second-deposit");
        _try(
            IVaultV2(vaults[0].vault).withdrawalQueue(),
            abi.encodeCall(IWithdrawalQueue.requestRedeem, (1 ether, actors.staker)),
            "queue-request"
        );
        vm.stopPrank();

        _try(vaults[0].delegator, abi.encodeCall(IUniversalDelegator.sweepPending, ()), "queue-sweep");
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

    function _fund(Actors memory actors, Token[3] memory tokens) internal {
        for (uint256 i; i < tokens.length; ++i) {
            IERC20(address(tokens[i])).transfer(actors.staker, 100_000 ether);
            IERC20(address(tokens[i])).transfer(actors.burner, 1 ether);
        }
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
