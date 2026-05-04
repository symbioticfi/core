// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IVaultFactory} from "../../../src/interfaces/IVaultFactory.sol";
import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {IMigratablesFactory} from "../../../src/interfaces/common/IMigratablesFactory.sol";
import {
    CREATE_SLOT_ROLE,
    IUniversalDelegator,
    REMOVE_SLOT_ROLE,
    SET_SIZE_ROLE,
    SWAP_SLOTS_ROLE
} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IUniversalSlasher} from "../../../src/interfaces/slasher/IUniversalSlasher.sol";
import {IVault} from "../../../src/interfaces/vault/IVault.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../../../src/interfaces/vault/IVaultV2.sol";
import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract MigrateToVaultV2BaseScript is ScriptBase {
    using Subnetwork for address;

    struct Config {
        address vault;
        string name;
        string symbol;
        uint48 adaptersAllowDelay;
        address defaultAdminRoleHolder;
        address setAdapterLimitRoleHolder;
        address swapAdaptersRoleHolder;
        address allocateAdapterRoleHolder;
        address deallocateAdapterRoleHolder;
        IUniversalDelegator.InitParams delegatorParams;
        IUniversalSlasher.InitParams slasherParams;
    }

    struct OperatorAllocation {
        address operator;
        uint128 size;
    }

    struct NetworkAllocation {
        address network;
        uint96 identifier;
        uint128 size;
        OperatorAllocation[] operators;
    }

    struct TemporaryDelegatorRoles {
        address scriptCaller;
        address defaultAdminRoleHolder;
        address createSlotRoleHolder;
        bool shouldRenounceTemporaryDefaultAdminRole;
        bool shouldRenounceTemporaryCreateRole;
    }

    function runBase(Config memory config, NetworkAllocation[] memory networks, address[] memory allocators)
        public
        virtual
        returns (
            bytes memory migrateData,
            address migrateTarget,
            bytes memory createSlotsData,
            address createSlotsTarget,
            bytes memory grantAllocatorRolesData,
            address grantAllocatorRolesTarget
        )
    {
        assert(config.vault != address(0));

        TemporaryDelegatorRoles memory temporaryRoles = _prepareTemporaryDelegatorRoles(config);

        (migrateData, migrateTarget) = _migrateToVaultV2(config);

        address delegator = IVault(config.vault).delegator();
        (createSlotsData, createSlotsTarget) = _createSlots(config.vault, delegator, networks);

        _cleanupTemporaryCreateRole(delegator, temporaryRoles);
        (grantAllocatorRolesData, grantAllocatorRolesTarget) = _grantAllocatorRoles(delegator, allocators);
        _cleanupTemporaryDefaultAdminRole(delegator, temporaryRoles);
    }

    function _buildMigrateData(Config memory config) internal pure returns (bytes memory) {
        return abi.encode(
            IVaultV2.MigrateParams({
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
            })
        );
    }

    function _buildCreateSlotsCalls(address delegator, NetworkAllocation[] memory networks)
        internal
        view
        returns (bytes[] memory calls)
    {
        uint256 totalCalls;
        for (uint256 i; i < networks.length; ++i) {
            totalCalls += networks[i].operators.length;
        }

        calls = new bytes[](totalCalls);

        uint256 callIndex;
        for (uint32 i; i < networks.length; ++i) {
            NetworkAllocation memory networkAllocation = networks[i];
            bytes32 subnetwork = networkAllocation.network.subnetwork(networkAllocation.identifier);

            for (uint32 j; j < networkAllocation.operators.length; ++j) {
                OperatorAllocation memory operatorAllocation = networkAllocation.operators[j];

                calls[callIndex++] = abi.encodeCall(
                    IUniversalDelegator.createSlot, (subnetwork, operatorAllocation.operator, operatorAllocation.size)
                );
            }
        }
    }

    function _migrateToVaultV2(Config memory config)
        internal
        returns (bytes memory migrateData, address migrateTarget)
    {
        migrateTarget = IMigratableEntity(config.vault).FACTORY();
        assert(IVaultFactory(migrateTarget).lastVersion() >= VAULT_V2_VERSION);
        assert(IMigratableEntity(config.vault).version() < VAULT_V2_VERSION);

        migrateData =
            abi.encodeCall(IMigratablesFactory.migrate, (config.vault, VAULT_V2_VERSION, _buildMigrateData(config)));
        sendTransaction(migrateTarget, migrateData);

        Logs.log(
            string.concat(
                "Migrate vault to VaultV2",
                "\n    vault:",
                vm.toString(config.vault),
                "\n    vaultFactory:",
                vm.toString(migrateTarget),
                "\n    newVersion:",
                vm.toString(uint256(VAULT_V2_VERSION))
            )
        );
        Logs.logSimulationLink(migrateTarget, migrateData);
    }

    function _createSlots(address vault, address delegator, NetworkAllocation[] memory networks)
        internal
        returns (bytes memory createSlotsData, address createSlotsTarget)
    {
        bytes[] memory calls = _buildCreateSlotsCalls(delegator, networks);
        if (calls.length == 0) {
            Logs.log("No VaultV2 slot allocations configured");
            return (createSlotsData, createSlotsTarget);
        }

        createSlotsTarget = delegator;
        createSlotsData = abi.encodeCall(IUniversalDelegator.multicall, (calls));
        sendTransaction(createSlotsTarget, createSlotsData);

        Logs.log(
            string.concat(
                "Create VaultV2 slots",
                "\n    vault:",
                vm.toString(vault),
                "\n    delegator:",
                vm.toString(createSlotsTarget),
                "\n    calls:",
                vm.toString(calls.length)
            )
        );
        Logs.logSimulationLink(createSlotsTarget, createSlotsData);
    }

    function _operatorKey(address operator) internal pure returns (bytes32) {
        return bytes32(bytes20(operator));
    }

    function _getScriptCaller() internal virtual returns (address caller) {
        vm.startBroadcast();
        (,, caller) = vm.readCallers();
        vm.stopBroadcast();
    }

    function _prepareTemporaryDelegatorRoles(Config memory config)
        internal
        returns (TemporaryDelegatorRoles memory temporaryRoles)
    {
        temporaryRoles.scriptCaller = _getScriptCaller();
        temporaryRoles.defaultAdminRoleHolder = config.delegatorParams.defaultAdminRoleHolder;
        temporaryRoles.createSlotRoleHolder = config.delegatorParams.createSlotRoleHolder;

        temporaryRoles.shouldRenounceTemporaryDefaultAdminRole =
            temporaryRoles.scriptCaller != temporaryRoles.defaultAdminRoleHolder;
        if (temporaryRoles.shouldRenounceTemporaryDefaultAdminRole) {
            config.delegatorParams.defaultAdminRoleHolder = temporaryRoles.scriptCaller;
        }

        temporaryRoles.shouldRenounceTemporaryCreateRole =
            temporaryRoles.scriptCaller != temporaryRoles.createSlotRoleHolder;
        if (temporaryRoles.shouldRenounceTemporaryCreateRole) {
            config.delegatorParams.createSlotRoleHolder = temporaryRoles.scriptCaller;
        }
    }

    function _cleanupTemporaryCreateRole(address delegator, TemporaryDelegatorRoles memory temporaryRoles) internal {
        if (!temporaryRoles.shouldRenounceTemporaryCreateRole) {
            return;
        }

        if (temporaryRoles.createSlotRoleHolder != address(0)) {
            bytes memory grantData =
                abi.encodeCall(IAccessControl.grantRole, (CREATE_SLOT_ROLE, temporaryRoles.createSlotRoleHolder));
            sendTransaction(delegator, grantData);

            Logs.log(
                string.concat(
                    "Grant CREATE_SLOT_ROLE",
                    "\n    delegator:",
                    vm.toString(delegator),
                    "\n    createSlotRoleHolder:",
                    vm.toString(temporaryRoles.createSlotRoleHolder)
                )
            );
            Logs.logSimulationLink(delegator, grantData);
        }

        bytes memory cleanupData =
            abi.encodeCall(IAccessControl.renounceRole, (CREATE_SLOT_ROLE, temporaryRoles.scriptCaller));
        sendTransaction(delegator, cleanupData);

        Logs.log(
            string.concat(
                "Renounce temporary CREATE_SLOT_ROLE",
                "\n    delegator:",
                vm.toString(delegator),
                "\n    scriptCaller:",
                vm.toString(temporaryRoles.scriptCaller)
            )
        );
        Logs.logSimulationLink(delegator, cleanupData);
    }

    function _cleanupTemporaryDefaultAdminRole(address delegator, TemporaryDelegatorRoles memory temporaryRoles)
        internal
    {
        if (!temporaryRoles.shouldRenounceTemporaryDefaultAdminRole) {
            return;
        }

        if (temporaryRoles.defaultAdminRoleHolder != address(0)) {
            bytes memory grantData =
                abi.encodeCall(IAccessControl.grantRole, (bytes32(0), temporaryRoles.defaultAdminRoleHolder));
            sendTransaction(delegator, grantData);

            Logs.log(
                string.concat(
                    "Grant DEFAULT_ADMIN_ROLE",
                    "\n    delegator:",
                    vm.toString(delegator),
                    "\n    defaultAdminRoleHolder:",
                    vm.toString(temporaryRoles.defaultAdminRoleHolder)
                )
            );
            Logs.logSimulationLink(delegator, grantData);
        }

        bytes memory cleanupData =
            abi.encodeCall(IAccessControl.renounceRole, (bytes32(0), temporaryRoles.scriptCaller));
        sendTransaction(delegator, cleanupData);

        Logs.log(
            string.concat(
                "Renounce temporary DEFAULT_ADMIN_ROLE",
                "\n    delegator:",
                vm.toString(delegator),
                "\n    scriptCaller:",
                vm.toString(temporaryRoles.scriptCaller)
            )
        );
        Logs.logSimulationLink(delegator, cleanupData);
    }

    function _grantAllocatorRoles(address delegator, address[] memory allocators)
        internal
        returns (bytes memory grantAllocatorRolesData, address grantAllocatorRolesTarget)
    {
        if (allocators.length == 0) {
            Logs.log("No additional allocator role grantees configured");
            return (grantAllocatorRolesData, grantAllocatorRolesTarget);
        }

        bytes[] memory calls = new bytes[](allocators.length * 4);
        uint256 callIndex;

        for (uint256 i; i < allocators.length; ++i) {
            assert(allocators[i] != address(0));

            calls[callIndex++] = abi.encodeCall(IAccessControl.grantRole, (CREATE_SLOT_ROLE, allocators[i]));
            calls[callIndex++] = abi.encodeCall(IAccessControl.grantRole, (SET_SIZE_ROLE, allocators[i]));
            calls[callIndex++] = abi.encodeCall(IAccessControl.grantRole, (SWAP_SLOTS_ROLE, allocators[i]));
            calls[callIndex++] = abi.encodeCall(IAccessControl.grantRole, (REMOVE_SLOT_ROLE, allocators[i]));
        }

        grantAllocatorRolesTarget = delegator;
        grantAllocatorRolesData = abi.encodeCall(IUniversalDelegator.multicall, (calls));
        sendTransaction(grantAllocatorRolesTarget, grantAllocatorRolesData);

        Logs.log(
            string.concat(
                "Grant allocator roles",
                "\n    delegator:",
                vm.toString(grantAllocatorRolesTarget),
                "\n    allocators:",
                vm.toString(allocators.length)
            )
        );
        Logs.logSimulationLink(grantAllocatorRolesTarget, grantAllocatorRolesData);
    }
}
