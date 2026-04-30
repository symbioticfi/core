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
import {UniversalDelegatorIndex} from "../../../src/contracts/libraries/UniversalDelegatorIndex.sol";
import {Logs} from "../../utils/Logs.sol";
import {ScriptBase} from "../../utils/ScriptBase.s.sol";

contract MigrateToVaultV2BaseScript is ScriptBase {
    using Subnetwork for address;
    using UniversalDelegatorIndex for uint96;

    uint96 internal constant MIGRATED_SUBVAULT_INDEX = uint96(1) << 64;

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
        uint96 operatorNetworkSpecificSubnetworkId;
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

        address scriptCaller = _getScriptCaller();
        bool shouldRenounceTemporaryCreateRole = scriptCaller != config.delegatorParams.createSlotRoleHolder;
        if (shouldRenounceTemporaryCreateRole) {
            config.delegatorParams.createSlotRoleHolder = scriptCaller;
        }

        (migrateData, migrateTarget) = _migrateToVaultV2(config);

        address delegator = IVault(config.vault).delegator();
        (createSlotsData, createSlotsTarget) = _createSlots(config.vault, delegator, networks);

        _cleanupTemporaryCreateRole(delegator, scriptCaller, shouldRenounceTemporaryCreateRole);
        (grantAllocatorRolesData, grantAllocatorRolesTarget) = _grantAllocatorRoles(delegator, allocators);
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
                operatorNetworkSpecificSubnetworkId: config.operatorNetworkSpecificSubnetworkId,
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
        IUniversalDelegator.Slot memory root = IUniversalDelegator(delegator).getSlot(0);
        assert(root.existChildren == 1);

        IUniversalDelegator.Slot memory migratedSubvault =
            IUniversalDelegator(delegator).getSlot(MIGRATED_SUBVAULT_INDEX);
        assert(migratedSubvault.exists);
        uint32 firstNetworkChild = migratedSubvault.totalChildren + 1;

        uint256 totalCalls;
        for (uint256 i; i < networks.length; ++i) {
            totalCalls += 1 + networks[i].operators.length;
        }

        calls = new bytes[](totalCalls);

        uint256 callIndex;
        for (uint32 i; i < networks.length; ++i) {
            NetworkAllocation memory networkAllocation = networks[i];
            bytes32 subnetwork = networkAllocation.network.subnetwork(networkAllocation.identifier);
            uint96 networkSlotIndex = MIGRATED_SUBVAULT_INDEX.createIndex(firstNetworkChild + i);

            calls[callIndex++] = abi.encodeCall(
                IUniversalDelegator.createSlot, (subnetwork, MIGRATED_SUBVAULT_INDEX, false, networkAllocation.size)
            );

            for (uint32 j; j < networkAllocation.operators.length; ++j) {
                OperatorAllocation memory operatorAllocation = networkAllocation.operators[j];

                calls[callIndex++] = abi.encodeCall(
                    IUniversalDelegator.createSlot,
                    (_operatorKey(operatorAllocation.operator), networkSlotIndex, false, operatorAllocation.size)
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

    function _cleanupTemporaryCreateRole(
        address delegator,
        address scriptCaller,
        bool shouldRenounceTemporaryCreateRole
    ) internal {
        if (!shouldRenounceTemporaryCreateRole) {
            return;
        }

        bytes memory cleanupData = abi.encodeCall(IAccessControl.renounceRole, (CREATE_SLOT_ROLE, scriptCaller));
        sendTransaction(delegator, cleanupData);

        Logs.log(
            string.concat(
                "Renounce temporary CREATE_SLOT_ROLE",
                "\n    delegator:",
                vm.toString(delegator),
                "\n    scriptCaller:",
                vm.toString(scriptCaller)
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
