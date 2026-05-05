// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import "../SymbioticCoreInit.sol";
import "../SymbioticCoreImports.sol";
import "../base/SymbioticCoreInitBase.sol";
import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";
import {Vault as VaultV1} from "../../../src/contracts/vault/Vault.sol";
import {VaultTokenized} from "../../../src/contracts/vault/VaultTokenized.sol";
import {VaultV2} from "../../../src/contracts/vault/VaultV2.sol";
import {VaultV2Migrate} from "../../../src/contracts/vault/VaultV2Migrate.sol";
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
import {IVaultV2, VAULT_V2_VERSION} from "../../../src/interfaces/vault/IVaultV2.sol";

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

    uint96 internal constant IDENTIFIER = 0;

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
        address vaultV2Migrate =
            address(new VaultV2Migrate(delegatorFactory, slasherFactory, address(0), rewards, address(0)));

        symbioticCore.vaultFactory.whitelist(address(new VaultV1(delegatorFactory, slasherFactory, vaultFactory)));
        symbioticCore.vaultFactory
            .whitelist(address(new VaultTokenized(delegatorFactory, slasherFactory, vaultFactory)));
        symbioticCore.vaultFactory
            .whitelist(
                address(
                    new VaultV2(
                        delegatorFactory, slasherFactory, vaultFactory, address(0), rewards, address(0), vaultV2Migrate
                    )
                )
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
        IERC20(collateral).transfer(curator.addr, 100 ether);
        _deposit_SymbioticCore(curator.addr, vault, 100 ether);
        _withdraw_SymbioticCore(curator.addr, vault, 20 ether);
        vm.warp(vm.getBlockTimestamp() + IVault(vault).epochDuration());

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
        assertEq(IVaultV2(vault).adaptersAllowDelay(), 8 days, "adapters allow delay mismatch");

        address newDelegator = IVault(vault).delegator();
        address newSlasher = IVault(vault).slasher();

        assertEq(IEntity(newDelegator).TYPE(), UNIVERSAL_DELEGATOR_TYPE, "delegator type mismatch");
        assertEq(IEntity(newSlasher).TYPE(), UNIVERSAL_SLASHER_TYPE, "slasher type mismatch");

        IUniversalDelegator delegator = IUniversalDelegator(newDelegator);

        bytes32 subnetwork1 = network1.addr.subnetwork(IDENTIFIER);
        bytes32 subnetwork2 = network2.addr.subnetwork(IDENTIFIER);

        uint32 operatorSlot1 = delegator.getSlotOf(subnetwork1, operator1.addr);
        uint32 operatorSlot2 = delegator.getSlotOf(subnetwork1, operator2.addr);
        uint32 operatorSlot3 = delegator.getSlotOf(subnetwork2, operator2.addr);

        assertEq(UniversalDelegator(newDelegator).totalSlots(), 3, "slot count mismatch");
        assertEq(operatorSlot1, 1, "operator1 slot mismatch");
        assertEq(operatorSlot2, 2, "operator2 slot mismatch");
        assertEq(operatorSlot3, 3, "operator3 slot mismatch");

        _assertSlot(delegator, operatorSlot1, subnetwork1, operator1.addr, 40 ether, "operator1");
        _assertSlot(delegator, operatorSlot2, subnetwork1, operator2.addr, 60 ether, "operator2");
        _assertSlot(delegator, operatorSlot3, subnetwork2, operator2.addr, 60 ether, "operator3");

        uint48 migrateTimestamp = IVaultV2(vault).migrateTimestamp();
        uint48 epochDuration = IVaultV2(vault).epochDuration();
        assertGt(IVaultV2(vault).withdrawalsOfLength(curator.addr), 0, "legacy withdrawals length missing");
        assertGt(
            IVaultV2(vault).activeWithdrawalSharesOfAt(curator.addr, migrateTimestamp),
            0,
            "legacy active withdrawal shares missing"
        );
        assertGt(IVaultV2(vault).withdrawalSharesOf(1, curator.addr), 0, "legacy withdrawal shares missing");
        assertEq(
            IVaultV2(vault).withdrawalUnlockAt(1, curator.addr),
            migrateTimestamp + epochDuration,
            "legacy current unlock mismatch"
        );
        assertEq(
            IVaultV2(vault).withdrawalUnlockAt(2, curator.addr),
            migrateTimestamp + epochDuration,
            "legacy next unlock mismatch"
        );
        assertEq(IVaultV2(vault).withdrawalsOf(0, curator.addr), 0, "legacy past withdrawal mismatch");
        assertGt(IVaultV2(vault).withdrawalsOf(1, curator.addr), 0, "legacy current withdrawal missing");

        _assertAllocatorRoles(newDelegator, operator1.addr);
    }

    function test_MigrateToVaultV2_DoesNotAutoSeedOperatorNetworkSpecificSlot() public {
        SymbioticCoreInitBase.VaultParams memory vaultParams = SymbioticCoreInitBase.VaultParams({
            owner: operator1.addr,
            collateral: collateral,
            burner: address(0x000000000000000000000000000000000000dEaD),
            epochDuration: uint48(7 days),
            whitelistedDepositors: new address[](0),
            depositLimit: 0,
            delegatorIndex: 3,
            hook: address(0),
            network: network1.addr,
            withSlasher: false,
            slasherIndex: 0,
            vetoDuration: uint48(0)
        });
        address operatorNetworkSpecificVault = _getVault_SymbioticCore(vaultParams);
        address oldDelegator = IVault(operatorNetworkSpecificVault).delegator();
        bytes32 subnetwork = network1.addr.subnetwork(IDENTIFIER);

        _networkSetMaxNetworkLimit_SymbioticCore(network1.addr, operatorNetworkSpecificVault, IDENTIFIER, 1 ether);
        assertGt(
            OperatorNetworkSpecificDelegator(oldDelegator).maxNetworkLimit(subnetwork), 0, "old delegator not allocated"
        );

        MigrateToVaultV2BaseScript.Config memory config = _config();
        config.vault = operatorNetworkSpecificVault;
        IVaultV2.MigrateParams memory migrateParams = IVaultV2.MigrateParams({
            name: config.name,
            symbol: config.symbol,
            adaptersAllowDelay: config.adaptersAllowDelay,
            defaultAdminRoleHolder: config.defaultAdminRoleHolder,
            setAdapterLimitRoleHolder: config.setAdapterLimitRoleHolder,
            swapAdaptersRoleHolder: config.swapAdaptersRoleHolder,
            allocateAdapterRoleHolder: config.allocateAdapterRoleHolder,
            deallocateAdapterRoleHolder: config.deallocateAdapterRoleHolder,
            delegatorParams: abi.encode(config.delegatorParams),
            slasherParams: abi.encode(config.slasherParams)
        });

        vm.prank(operator1.addr);
        symbioticCore.vaultFactory.migrate(operatorNetworkSpecificVault, VAULT_V2_VERSION, abi.encode(migrateParams));

        address newDelegator = IVault(operatorNetworkSpecificVault).delegator();
        assertEq(UniversalDelegator(newDelegator).oldDelegator(), oldDelegator, "old delegator mismatch");
        assertEq(UniversalDelegator(newDelegator).totalSlots(), 0, "unexpected migrated slot");
        assertEq(IUniversalDelegator(newDelegator).getSlotOf(subnetwork, operator1.addr), 0, "unexpected pair slot");
        assertTrue(IAccessControl(newDelegator).hasRole(CREATE_SLOT_ROLE, curator.addr), "missing create role");

        vm.prank(curator.addr);
        uint32 slot = IUniversalDelegator(newDelegator).createSlot(subnetwork, operator1.addr, uint128(1 ether));

        assertEq(slot, 1, "manual slot index mismatch");
        _assertSlot(IUniversalDelegator(newDelegator), slot, subnetwork, operator1.addr, 1 ether, "manual");
    }

    function test_MigrateToVaultV2_RunBaseMigratesOperatorNetworkSpecificWithSplitAdmin() public {
        SymbioticCoreInitBase.VaultParams memory vaultParams = SymbioticCoreInitBase.VaultParams({
            owner: operator1.addr,
            collateral: collateral,
            burner: address(0x000000000000000000000000000000000000dEaD),
            epochDuration: uint48(7 days),
            whitelistedDepositors: new address[](0),
            depositLimit: 0,
            delegatorIndex: 3,
            hook: address(0),
            network: network1.addr,
            withSlasher: false,
            slasherIndex: 0,
            vetoDuration: uint48(0)
        });
        address operatorNetworkSpecificVault = _getVault_SymbioticCore(vaultParams);
        address oldDelegator = IVault(operatorNetworkSpecificVault).delegator();
        bytes32 subnetwork = network1.addr.subnetwork(IDENTIFIER);

        _networkSetMaxNetworkLimit_SymbioticCore(network1.addr, operatorNetworkSpecificVault, IDENTIFIER, 1 ether);

        MigrateToVaultV2BaseScript.Config memory config = _config();
        config.vault = operatorNetworkSpecificVault;

        MigrateToVaultV2BaseScript.NetworkAllocation[] memory networks =
            new MigrateToVaultV2BaseScript.NetworkAllocation[](1);
        networks[0].network = network1.addr;
        networks[0].identifier = IDENTIFIER;
        networks[0].size = uint128(1 ether);
        networks[0].operators = new MigrateToVaultV2BaseScript.OperatorAllocation[](1);
        networks[0].operators[0] =
            MigrateToVaultV2BaseScript.OperatorAllocation({operator: operator1.addr, size: uint128(1 ether)});

        address[] memory allocators = new address[](1);
        allocators[0] = operator2.addr;

        MigrateToVaultV2ScriptHarness script = new MigrateToVaultV2ScriptHarness(operator1.addr);
        script.runBase(config, networks, allocators);

        address newDelegator = IVault(operatorNetworkSpecificVault).delegator();

        assertEq(UniversalDelegator(newDelegator).oldDelegator(), oldDelegator, "old delegator mismatch");

        IUniversalDelegator delegator = IUniversalDelegator(newDelegator);
        uint32 slot = delegator.getSlotOf(subnetwork, operator1.addr);
        assertEq(UniversalDelegator(newDelegator).totalSlots(), 1, "slot count mismatch");
        assertEq(slot, 1, "operator slot mismatch");
        _assertSlot(delegator, slot, subnetwork, operator1.addr, 1 ether, "script manual");

        assertTrue(IAccessControl(newDelegator).hasRole(bytes32(0), curator.addr), "missing final admin");
        assertFalse(IAccessControl(newDelegator).hasRole(bytes32(0), operator1.addr), "temporary admin remains");
        assertFalse(IAccessControl(newDelegator).hasRole(CREATE_SLOT_ROLE, operator1.addr), "temporary creator remains");
        _assertAllocatorRoles(newDelegator, curator.addr);
        _assertAllocatorRoles(newDelegator, operator2.addr);
    }

    function _assertSlot(
        IUniversalDelegator delegator,
        uint32 slotIndex,
        bytes32 subnetwork,
        address operator,
        uint256 size,
        string memory label
    ) internal view {
        IUniversalDelegator.Slot memory slot = delegator.getSlot(slotIndex);
        assertTrue(slot.exists, string.concat(label, " slot missing"));
        assertEq(slot.subnetwork, subnetwork, string.concat(label, " subnetwork mismatch"));
        assertEq(slot.operator, operator, string.concat(label, " operator mismatch"));
        assertEq(uint256(slot.size), size, string.concat(label, " size mismatch"));
    }

    function _config() internal view returns (MigrateToVaultV2BaseScript.Config memory) {
        return MigrateToVaultV2BaseScript.Config({
            vault: vault,
            name: "Migrated Vault V2",
            symbol: "mV2",
            adaptersAllowDelay: 8 days,
            defaultAdminRoleHolder: curator.addr,
            setAdapterLimitRoleHolder: curator.addr,
            swapAdaptersRoleHolder: curator.addr,
            allocateAdapterRoleHolder: curator.addr,
            deallocateAdapterRoleHolder: curator.addr,
            delegatorParams: IUniversalDelegator.InitParams({
                defaultAdminRoleHolder: curator.addr,
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
