// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import "../SymbioticCoreInit.sol";
import "../SymbioticCoreImports.sol";
import "../base/SymbioticCoreInitBase.sol";
import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";
import {UniversalDelegatorIndex} from "../../../src/contracts/libraries/UniversalDelegatorIndex.sol";
import {Vault as VaultV1} from "../../../src/contracts/vault/Vault.sol";
import {VaultTokenized} from "../../../src/contracts/vault/VaultTokenized.sol";
import {VaultV2} from "../../../src/contracts/vault/VaultV2.sol";
import {NetworkRestakeDelegator} from "../../../src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "../../../src/contracts/delegator/FullRestakeDelegator.sol";
import {OperatorSpecificDelegator} from "../../../src/contracts/delegator/OperatorSpecificDelegator.sol";
import {OperatorNetworkSpecificDelegator} from "../../../src/contracts/delegator/OperatorNetworkSpecificDelegator.sol";
import {UniversalDelegator} from "../../../src/contracts/delegator/UniversalDelegator.sol";
import {Slasher} from "../../../src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "../../../src/contracts/slasher/VetoSlasher.sol";
import {UniversalSlasher} from "../../../src/contracts/slasher/UniversalSlasher.sol";

import {IEntity} from "../../../src/interfaces/common/IEntity.sol";
import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {
    CREATE_SLOT_ROLE,
    IUniversalDelegator,
    REMOVE_SLOT_ROLE,
    SET_SIZE_ROLE,
    SWAP_SLOTS_ROLE,
    UNIVERSAL_DELEGATOR_TYPE
} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher, UNIVERSAL_SLASHER_TYPE} from "../../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {VAULT_V2_VERSION} from "../../../src/interfaces/vault/IVaultV2.sol";

import {ScriptBase} from "../../../script/utils/ScriptBase.s.sol";
import {MigrateToVaultV2BaseScript} from "../../../script/actions/base/MigrateToVaultV2Base.s.sol";
import {ScriptBaseHarness} from "./ScriptBaseHarness.s.sol";
import {MockRewards} from "../../mocks/MockRewards.sol";

contract MigrateToVaultV2ScriptHarness is MigrateToVaultV2BaseScript, ScriptBaseHarness {
    constructor(address broadcaster_) ScriptBaseHarness(broadcaster_) {}

    function _getScriptCaller() internal override returns (address caller) {
        caller = broadcaster;
    }

    function sendTransaction(address target, bytes memory data) public override(ScriptBase, ScriptBaseHarness) {
        ScriptBaseHarness.sendTransaction(target, data);
    }
}

contract MigrateToVaultV2ActionScriptTest is SymbioticCoreInit {
    using Subnetwork for address;
    using UniversalDelegatorIndex for uint96;

    uint96 internal constant IDENTIFIER = 0;
    uint96 internal constant MIGRATED_SUBVAULT_INDEX = uint96(1) << 64;

    Vm.Wallet internal curator;
    Vm.Wallet internal network1;
    Vm.Wallet internal network2;
    Vm.Wallet internal operator1;
    Vm.Wallet internal operator2;

    address internal collateral;
    address internal vault;

    function _whitelistVaultImplementations() internal virtual override {
        address delegatorFactory = address(symbioticCore.delegatorFactory);
        address slasherFactory = address(symbioticCore.slasherFactory);
        address vaultFactory = address(symbioticCore.vaultFactory);
        address rewards = address(new MockRewards());

        symbioticCore.vaultFactory.whitelist(address(new VaultV1(delegatorFactory, slasherFactory, vaultFactory)));
        symbioticCore.vaultFactory
            .whitelist(address(new VaultTokenized(delegatorFactory, slasherFactory, vaultFactory)));
        symbioticCore.vaultFactory
            .whitelist(
                address(new VaultV2(delegatorFactory, slasherFactory, vaultFactory, address(0), rewards, address(0)))
            );
    }

    function _whitelistDelegatorImplementations() internal virtual override {
        ISymbioticDelegatorFactory factory = symbioticCore.delegatorFactory;
        address factoryAddress = address(factory);
        address networkRegistry = address(symbioticCore.networkRegistry);
        address operatorRegistry = address(symbioticCore.operatorRegistry);
        address vaultFactory = address(symbioticCore.vaultFactory);
        address operatorVaultOptInService = address(symbioticCore.operatorVaultOptInService);
        address operatorNetworkOptInService = address(symbioticCore.operatorNetworkOptInService);
        address implementation;
        uint64 typeIndex;

        typeIndex = uint64(factory.totalTypes());
        implementation = address(
            new NetworkRestakeDelegator(
                networkRegistry,
                vaultFactory,
                operatorVaultOptInService,
                operatorNetworkOptInService,
                factoryAddress,
                typeIndex
            )
        );
        factory.whitelist(implementation);

        typeIndex = uint64(factory.totalTypes());
        implementation = address(
            new FullRestakeDelegator(
                networkRegistry,
                vaultFactory,
                operatorVaultOptInService,
                operatorNetworkOptInService,
                factoryAddress,
                typeIndex
            )
        );
        factory.whitelist(implementation);

        typeIndex = uint64(factory.totalTypes());
        implementation = address(
            new OperatorSpecificDelegator(
                operatorRegistry,
                networkRegistry,
                vaultFactory,
                operatorVaultOptInService,
                operatorNetworkOptInService,
                factoryAddress,
                typeIndex
            )
        );
        factory.whitelist(implementation);

        typeIndex = uint64(factory.totalTypes());
        implementation = address(
            new OperatorNetworkSpecificDelegator(
                operatorRegistry,
                networkRegistry,
                vaultFactory,
                operatorVaultOptInService,
                operatorNetworkOptInService,
                factoryAddress,
                typeIndex
            )
        );
        factory.whitelist(implementation);

        typeIndex = uint64(factory.totalTypes());
        implementation = address(
            new UniversalDelegator(
                networkRegistry,
                vaultFactory,
                factoryAddress,
                typeIndex,
                address(symbioticCore.networkMiddlewareService)
            )
        );
        factory.whitelist(implementation);
    }

    function _whitelistSlasherImplementations() internal virtual override {
        ISymbioticSlasherFactory factory = symbioticCore.slasherFactory;
        address factoryAddress = address(factory);
        address vaultFactory = address(symbioticCore.vaultFactory);
        address networkMiddlewareService = address(symbioticCore.networkMiddlewareService);
        address networkRegistry = address(symbioticCore.networkRegistry);

        factory.whitelist(
            address(new Slasher(vaultFactory, networkMiddlewareService, factoryAddress, factory.totalTypes()))
        );
        factory.whitelist(
            address(
                new VetoSlasher(
                    vaultFactory, networkMiddlewareService, networkRegistry, factoryAddress, factory.totalTypes()
                )
            )
        );
        factory.whitelist(
            address(
                new UniversalSlasher(
                    vaultFactory, networkMiddlewareService, networkRegistry, factoryAddress, factory.totalTypes()
                )
            )
        );
    }

    function setUp() public virtual override {
        SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT = false;

        super.setUp();

        curator = _getAccount_Symbiotic();
        network1 = _getNetwork_SymbioticCore();
        network2 = _getNetwork_SymbioticCore();
        operator1 = _getOperator_SymbioticCore();
        operator2 = _getOperator_SymbioticCore();

        collateral = _getToken_SymbioticCore();

        SymbioticCoreInitBase.VaultParams memory vaultParams = SymbioticCoreInitBase.VaultParams({
            owner: curator.addr,
            collateral: collateral,
            burner: address(0x000000000000000000000000000000000000dEaD),
            epochDuration: uint48(7 days),
            whitelistedDepositors: new address[](0),
            depositLimit: 0,
            delegatorIndex: 0,
            hook: address(0),
            network: address(0),
            withSlasher: true,
            slasherIndex: 1,
            vetoDuration: uint48(1 days)
        });

        vault = _getVault_SymbioticCore(vaultParams);

        _networkSetMaxNetworkLimit_SymbioticCore(network1.addr, vault, IDENTIFIER, 1 ether);
        _networkSetMaxNetworkLimit_SymbioticCore(network2.addr, vault, IDENTIFIER, 1 ether);
    }

    function test_MigrateToVaultV2() public {
        MigrateToVaultV2ScriptHarness script = new MigrateToVaultV2ScriptHarness(curator.addr);
        MigrateToVaultV2BaseScript.Config memory config = _config();
        MigrateToVaultV2BaseScript.NetworkAllocation[] memory networks = _networkAllocations();

        (bytes memory migrateData, address migrateTarget, bytes memory createSlotsData, address createSlotsTarget,,) =
            script.runBase(config, networks, _allocators());

        assertGt(migrateData.length, 0, "missing migrate calldata");
        assertGt(createSlotsData.length, 0, "missing create slots calldata");
        assertEq(migrateTarget, IMigratableEntity(vault).FACTORY(), "factory target mismatch");
        assertEq(createSlotsTarget, IVault(vault).delegator(), "delegator target mismatch");
        assertEq(IMigratableEntity(vault).version(), VAULT_V2_VERSION, "vault version mismatch");

        address newDelegator = IVault(vault).delegator();
        address newSlasher = IVault(vault).slasher();

        assertEq(IEntity(newDelegator).TYPE(), UNIVERSAL_DELEGATOR_TYPE, "delegator type mismatch");
        assertEq(IEntity(newSlasher).TYPE(), UNIVERSAL_SLASHER_TYPE, "slasher type mismatch");

        IUniversalDelegator delegator = IUniversalDelegator(newDelegator);

        IUniversalDelegator.Slot memory root = delegator.getSlot(0);
        assertEq(root.existChildren, 1, "unexpected root children");

        IUniversalDelegator.Slot memory migratedSubvault = delegator.getSlot(MIGRATED_SUBVAULT_INDEX);
        assertTrue(migratedSubvault.exists, "migrated subvault missing");
        assertTrue(migratedSubvault.noAdapters, "migrated subvault should be no-adapters");
        assertEq(migratedSubvault.existChildren, 2, "network slot count mismatch");

        bytes32 subnetwork1 = network1.addr.subnetwork(IDENTIFIER);
        bytes32 subnetwork2 = network2.addr.subnetwork(IDENTIFIER);

        uint96 networkSlot1 = MIGRATED_SUBVAULT_INDEX.createIndex(1);
        uint96 networkSlot2 = MIGRATED_SUBVAULT_INDEX.createIndex(2);

        assertEq(delegator.getSlotOfNetwork(subnetwork1), networkSlot1, "network1 slot mismatch");
        assertEq(delegator.getSlotOfNetwork(subnetwork2), networkSlot2, "network2 slot mismatch");
        assertEq(uint256(delegator.getSlot(networkSlot1).size), 100 ether, "network1 size mismatch");
        assertEq(uint256(delegator.getSlot(networkSlot2).size), 60 ether, "network2 size mismatch");
        assertEq(delegator.maxNetworkLimit(subnetwork1), type(uint208).max, "network1 max limit mismatch");
        assertEq(delegator.maxNetworkLimit(subnetwork2), type(uint208).max, "network2 max limit mismatch");

        uint96 operatorSlot1 = networkSlot1.createIndex(1);
        uint96 operatorSlot2 = networkSlot1.createIndex(2);
        uint96 operatorSlot3 = networkSlot2.createIndex(1);

        assertEq(delegator.getSlotOfOperator(networkSlot1, operator1.addr), operatorSlot1, "operator1 slot mismatch");
        assertEq(delegator.getSlotOfOperator(networkSlot1, operator2.addr), operatorSlot2, "operator2 slot mismatch");
        assertEq(delegator.getSlotOfOperator(networkSlot2, operator2.addr), operatorSlot3, "operator3 slot mismatch");
        assertEq(uint256(delegator.getSlot(operatorSlot1).size), 40 ether, "operator1 size mismatch");
        assertEq(uint256(delegator.getSlot(operatorSlot2).size), 60 ether, "operator2 size mismatch");
        assertEq(uint256(delegator.getSlot(operatorSlot3).size), 60 ether, "operator3 size mismatch");

        _assertAllocatorRoles(newDelegator, operator1.addr);
    }

    function _config() internal view returns (MigrateToVaultV2BaseScript.Config memory) {
        return MigrateToVaultV2BaseScript.Config({
            vault: vault,
            name: "Migrated Vault V2",
            symbol: "mV2",
            delegatorParams: IUniversalDelegator.InitParams({
                defaultAdminRoleHolder: curator.addr,
                hook: address(0),
                hookSetRoleHolder: curator.addr,
                createSlotRoleHolder: curator.addr,
                setSizeRoleHolder: curator.addr,
                swapSlotsRoleHolder: curator.addr,
                removeSlotRoleHolder: curator.addr,
                setWithdrawalBufferSizeRoleHolder: curator.addr,
                withdrawalBufferSize: type(uint128).max
            }),
            slasherParams: IUniversalSlasher.InitParams({
                isBurnerHook: false, vetoDuration: 1 days, resolverSetDelay: 21 days
            })
        });
    }

    function _networkAllocations()
        internal
        view
        returns (MigrateToVaultV2BaseScript.NetworkAllocation[] memory networks)
    {
        networks = new MigrateToVaultV2BaseScript.NetworkAllocation[](2);

        networks[0].network = network1.addr;
        networks[0].identifier = IDENTIFIER;
        networks[0].size = uint128(100 ether);
        networks[0].operators = new MigrateToVaultV2BaseScript.OperatorAllocation[](2);
        networks[0].operators[0] =
            MigrateToVaultV2BaseScript.OperatorAllocation({operator: operator1.addr, size: uint128(40 ether)});
        networks[0].operators[1] =
            MigrateToVaultV2BaseScript.OperatorAllocation({operator: operator2.addr, size: uint128(60 ether)});

        networks[1].network = network2.addr;
        networks[1].identifier = IDENTIFIER;
        networks[1].size = uint128(60 ether);
        networks[1].operators = new MigrateToVaultV2BaseScript.OperatorAllocation[](1);
        networks[1].operators[0] =
            MigrateToVaultV2BaseScript.OperatorAllocation({operator: operator2.addr, size: uint128(60 ether)});
    }

    function _allocators() internal view returns (address[] memory allocators) {
        allocators = new address[](1);
        allocators[0] = operator1.addr;
    }

    function _assertAllocatorRoles(address delegator, address allocator) internal view {
        assertTrue(IAccessControl(delegator).hasRole(CREATE_SLOT_ROLE, allocator), "missing create role");
        assertTrue(IAccessControl(delegator).hasRole(SET_SIZE_ROLE, allocator), "missing set size role");
        assertTrue(IAccessControl(delegator).hasRole(SWAP_SLOTS_ROLE, allocator), "missing swap role");
        assertTrue(IAccessControl(delegator).hasRole(REMOVE_SLOT_ROLE, allocator), "missing remove role");
    }
}
