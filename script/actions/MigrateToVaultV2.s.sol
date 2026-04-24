// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/MigrateToVaultV2Base.s.sol";
import {IUniversalDelegator} from "../../src/interfaces/delegator/IUniversalDelegator.sol";

// forge script script/actions/MigrateToVaultV2.s.sol:MigrateToVaultV2Script --rpc-url=RPC --private-key PRIVATE_KEY --broadcast
// forge script script/actions/MigrateToVaultV2.s.sol:MigrateToVaultV2Script --rpc-url=RPC --sender MULTISIG_ADDRESS --unlocked

contract MigrateToVaultV2Script is MigrateToVaultV2BaseScript {
    // Configuration constants - UPDATE THESE BEFORE EXECUTING

    // Address of the vault that will be migrated to V2.
    address constant VAULT = 0x0000000000000000000000000000000000000000;

    // ######################### SETUP ############################

    // Optional - used only if the previous vault was not already tokenized

    // Name of the VaultV2 shares token.
    string constant NAME = "Symbiotic Vault V2";
    // Symbol of the VaultV2 shares token.
    string constant SYMBOL = "svV2";

    // Delegator Params

    // Address that receives DEFAULT_ADMIN_ROLE.
    address constant ADMIN_ROLE_HOLDER = 0x0000000000000000000000000000000000000000;
    // Addresses that receive CREATE_SLOT_ROLE, SET_SIZE_ROLE, SWAP_SLOTS_ROLE, and REMOVE_SLOT_ROLE.
    address[] ALLOCATORS = [0x0000000000000000000000000000000000000000, 0x0000000000000000000000000000000000000000];
    // Initial withdrawal buffer size.
    uint128 constant WITHDRAWAL_BUFFER_SIZE = 0;
    // Optional - used only if the previous slasher was not `VetoSlasher`

    // Whether slash execution should make a call to the burner on slashing.
    bool constant IS_BURNER_HOOK = false;
    // Veto duration. Must stay below the vault epoch duration.
    uint48 constant VETO_DURATION = 1 days;
    // Delay before a resolver update becomes active. Must be greater than the vault epoch duration.
    uint48 constant RESOLVER_SET_DELAY = 21 days;

    // ######################### ALLOCATIONS ############################

    // Existing network/operator allocations can be viewed at:
    // https://app.symbiotic.fi/vault/<vault address>

    function _setAllocations() internal returns (Network storage allocation) {
        // Add subnetwork via (network - 0x0000000000000000000000000000000000000000, identifier - 0):
        // allocation = _pushAllocation(0x0000000000000000000000000000000000000000, 0);
        // Add operator to the subnetwork (operator - 0x0000000000000000000000000000000000000000, size - 100 ether):
        // _pushOperator(allocation, 0x0000000000000000000000000000000000000000, 100 ether);

        allocation = _pushAllocation(0x0000000000000000000000000000000000000000, 0);
        _pushOperator(allocation, 0x0000000000000000000000000000000000000000, 100 ether);
        _pushOperator(allocation, 0x0000000000000000000000000000000000000000, 100 ether);
        _pushOperator(allocation, 0x0000000000000000000000000000000000000000, 100 ether);

        allocation = _pushAllocation(0x0000000000000000000000000000000000000000, 0);
        _pushOperator(allocation, 0x0000000000000000000000000000000000000000, 100 ether);
        _pushOperator(allocation, 0x0000000000000000000000000000000000000000, 100 ether);
        _pushOperator(allocation, 0x0000000000000000000000000000000000000000, 100 ether);

        // ... replace/remove data above, and/or add more allocations here ...
    }

    Network[] allocations;

    struct Network {
        address network;
        uint96 identifier;
        Operator[] operators;
    }

    struct Operator {
        address operator;
        uint128 size;
    }

    function run() public {
        delete allocations;
        _setAllocations();

        Config memory config = Config({
            vault: VAULT,
            name: NAME,
            symbol: SYMBOL,
            defaultAdminRoleHolder: ADMIN_ROLE_HOLDER,
            setAdapterLimitRoleHolder: ADMIN_ROLE_HOLDER,
            swapAdaptersRoleHolder: ADMIN_ROLE_HOLDER,
            allocateAdapterRoleHolder: ADMIN_ROLE_HOLDER,
            deallocateAdapterRoleHolder: ADMIN_ROLE_HOLDER,
            operatorNetworkSpecificSubnetworkId: 0,
            delegatorParams: IUniversalDelegator.InitParams({
                defaultAdminRoleHolder: ADMIN_ROLE_HOLDER,
                createSlotRoleHolder: ADMIN_ROLE_HOLDER,
                setSizeRoleHolder: ADMIN_ROLE_HOLDER,
                swapSlotsRoleHolder: ADMIN_ROLE_HOLDER,
                removeSlotRoleHolder: ADMIN_ROLE_HOLDER,
                setWithdrawalBufferSizeRoleHolder: ADMIN_ROLE_HOLDER,
                withdrawalBufferSize: WITHDRAWAL_BUFFER_SIZE
            }),
            slasherParams: IUniversalSlasher.InitParams({
                isBurnerHook: IS_BURNER_HOOK, vetoDuration: VETO_DURATION, resolverSetDelay: RESOLVER_SET_DELAY
            })
        });

        NetworkAllocation[] memory networks = _networkAllocations();
        (
            bytes memory migrateData,
            address migrateTarget,
            bytes memory createSlotsData,
            address createSlotsTarget,
            bytes memory grantAllocatorRolesData,
            address grantAllocatorRolesTarget
        ) = runBase(config, networks, ALLOCATORS);

        Logs.log(
            string.concat(
                "MigrateToVaultV2 data:",
                "\n    migrateData:",
                vm.toString(migrateData),
                "\n    migrateTarget:",
                vm.toString(migrateTarget),
                "\n    createSlotsData:",
                vm.toString(createSlotsData),
                "\n    createSlotsTarget:",
                vm.toString(createSlotsTarget),
                "\n    grantAllocatorRolesData:",
                vm.toString(grantAllocatorRolesData),
                "\n    grantAllocatorRolesTarget:",
                vm.toString(grantAllocatorRolesTarget)
            )
        );
    }

    function _networkAllocations() internal view returns (NetworkAllocation[] memory networkAllocations) {
        // The migrated no-adapters subvault is created automatically during `VaultFactory.migrate`.
        // Fill the absolute network/operator allocations you want to recreate under that migrated subvault.
        // Existing network/operator allocations can be copied from:
        // https://app.symbiotic.fi/vault/<vault address>
        //
        // Note: if you add a network that did not have a legacy max network limit,
        // call `SetMaxNetworkLimit` for it after the migration.
        networkAllocations = new NetworkAllocation[](allocations.length);

        for (uint256 i; i < allocations.length; ++i) {
            networkAllocations[i].network = allocations[i].network;
            networkAllocations[i].identifier = allocations[i].identifier;
            networkAllocations[i].operators = new OperatorAllocation[](allocations[i].operators.length);

            uint128 networkSize;
            for (uint256 j; j < allocations[i].operators.length; ++j) {
                networkAllocations[i].operators[j] = OperatorAllocation({
                    operator: allocations[i].operators[j].operator, size: allocations[i].operators[j].size
                });
                networkSize += allocations[i].operators[j].size;
            }

            networkAllocations[i].size = networkSize;
        }
    }

    function _pushAllocation(address network, uint96 identifier) internal returns (Network storage allocation) {
        allocation = allocations.push();
        allocation.network = network;
        allocation.identifier = identifier;
    }

    function _pushOperator(Network storage allocation, address operator, uint128 size) internal {
        allocation.operators.push(Operator({operator: operator, size: size}));
    }
}
