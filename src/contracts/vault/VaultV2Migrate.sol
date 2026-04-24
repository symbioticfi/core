// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {DelegatorFactory} from "../DelegatorFactory.sol";
import {SlasherFactory} from "../SlasherFactory.sol";
import {UniversalDelegator} from "../delegator/UniversalDelegator.sol";
import {UniversalSlasher} from "../slasher/UniversalSlasher.sol";
import {VaultV2Storage} from "./VaultV2Storage.sol";
import {VaultV2} from "./VaultV2.sol";

import {Checkpoints as CheckpointsV2} from "../libraries/CheckpointsV2.sol";
import {Checkpoints} from "../libraries/Checkpoints.sol";
import {Subnetwork} from "../libraries/Subnetwork.sol";

import {IEntity} from "../../interfaces/common/IEntity.sol";
import {
    IOperatorNetworkSpecificDelegator,
    OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE
} from "../../interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {
    IUniversalDelegator,
    CREATE_SLOT_ROLE,
    MIGRATE_SUBVAULT_INDEX,
    UNIVERSAL_DELEGATOR_TYPE
} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {
    IVaultV2,
    MAX_DURATION,
    SET_ADAPTER_LIMIT_ROLE,
    SWAP_ADAPTERS_ROLE,
    ALLOCATE_ADAPTER_ROLE,
    DEALLOCATE_ADAPTER_ROLE
} from "../../interfaces/vault/IVaultV2.sol";
import {UNIVERSAL_SLASHER_TYPE} from "../../interfaces/slasher/IUniversalSlasher.sol";
import {VAULT_VERSION} from "../../interfaces/vault/IVault.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {FixedPointMathLib as Math} from "@solady/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib as SafeERC20} from "@solady/src/utils/SafeTransferLib.sol";

/// @title VaultV2Migrate
/// @notice Delegatecall helper that executes VaultV2 migration logic out of the main runtime bytecode.
contract VaultV2Migrate is VaultV2Storage, AccessControlUpgradeable, ERC20Upgradeable {
    using Subnetwork for address;
    using SafeERC20 for address;
    using Checkpoints for Checkpoints.Trace256;
    using Checkpoints for Checkpoints.Trace208;
    using CheckpointsV2 for CheckpointsV2.Trace256;
    using CheckpointsV2 for CheckpointsV2.Trace208;

    constructor(
        address delegatorFactory,
        address slasherFactory,
        address feeRegistry,
        address rewards,
        address adapterRegistry
    ) VaultV2Storage(delegatorFactory, slasherFactory, feeRegistry, rewards, adapterRegistry) {}

    function migrate(uint64 oldVersion, bytes calldata data) external {
        if (epochDuration > MAX_DURATION) {
            revert IVaultV2.TooLongDuration();
        }

        migrateTimestamp = uint48(block.timestamp);
        uint48 migrateEpoch = uint48((block.timestamp - __epochDurationInit) / epochDuration);
        __migrateEpoch = migrateEpoch;
        uint48 migrateNextEpochTimestamp = __epochDurationInit + (migrateEpoch + 1) * epochDuration;
        __migrateNextEpochTimestamp = migrateNextEpochTimestamp;

        IVaultV2.MigrateParams memory params = abi.decode(data, (IVaultV2.MigrateParams));
        if (oldVersion == VAULT_VERSION) {
            __ERC20_init(params.name, params.symbol);
        }

        _grantRoleIfNotZero(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        _grantRoleIfNotZero(SET_ADAPTER_LIMIT_ROLE, params.setAdapterLimitRoleHolder);
        _grantRoleIfNotZero(SWAP_ADAPTERS_ROLE, params.swapAdaptersRoleHolder);
        _grantRoleIfNotZero(ALLOCATE_ADAPTER_ROLE, params.allocateAdapterRoleHolder);
        _grantRoleIfNotZero(DEALLOCATE_ADAPTER_ROLE, params.deallocateAdapterRoleHolder);

        uint256 curActiveWithdrawals;
        if (migrateEpoch > 0) {
            curActiveWithdrawals = __withdrawals[migrateEpoch];
            if (curActiveWithdrawals > 0) {
                _withdrawalSharesCumulative.push(migrateNextEpochTimestamp, curActiveWithdrawals);
            }
        }
        curActiveWithdrawals += __withdrawals[migrateEpoch + 1];
        if (curActiveWithdrawals > 0) {
            _withdrawalSharesCumulative.push(uint48(block.timestamp) + epochDuration, curActiveWithdrawals);
            _withdrawals[0].push(uint48(block.timestamp), curActiveWithdrawals);
            _withdrawalShares[0].push(uint48(block.timestamp), curActiveWithdrawals);
        }

        _unclaimedRaw = int256(collateral.balanceOf(address(this)) - activeStake() - curActiveWithdrawals);

        // Deploy and migrate delegator.
        address oldDelegator = delegator;
        uint64 oldDelegatorType = IEntity(oldDelegator).TYPE();
        IUniversalDelegator.InitParams memory initParams =
            abi.decode(params.delegatorParams, (IUniversalDelegator.InitParams));
        address defaultAdminRoleHolder = initParams.defaultAdminRoleHolder;
        address createSlotRoleHolder = initParams.createSlotRoleHolder;
        initParams.defaultAdminRoleHolder = address(this);
        initParams.createSlotRoleHolder = address(this);
        params.delegatorParams = abi.encode(initParams);

        delegator = DelegatorFactory(DELEGATOR_FACTORY)
            .create(UNIVERSAL_DELEGATOR_TYPE, abi.encode(address(this), params.delegatorParams));
        UniversalDelegator(delegator).migrate(oldDelegator);
        UniversalDelegator(delegator)
            .createSlot(
                bytes32(0),
                0,
                oldDelegatorType < OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE,
                true,
                uint128(Math.min(VaultV2(address(this)).allocatable(), type(uint128).max))
            );
        if (oldDelegatorType == OPERATOR_NETWORK_SPECIFIC_DELEGATOR_TYPE) {
            // If previous delegator is OperatorNetworkSpecificDelegator, specific migration is needed.
            bytes32 subnetwork = IOperatorNetworkSpecificDelegator(oldDelegator).network()
                .subnetwork(params.operatorNetworkSpecificSubnetworkId);
            uint256 oldMaxNetworkLimit = IOperatorNetworkSpecificDelegator(oldDelegator).maxNetworkLimit(subnetwork);
            if (oldMaxNetworkLimit == 0) {
                revert IUniversalDelegator.NotEnoughBalance();
            }
            uint96 networkIndex = UniversalDelegator(delegator)
                .createSlot(subnetwork, MIGRATE_SUBVAULT_INDEX, false, false, type(uint128).max);
            UniversalDelegator(delegator)
                .createSlot(
                    bytes32(bytes20(IOperatorNetworkSpecificDelegator(oldDelegator).operator())),
                    networkIndex,
                    false,
                    false,
                    type(uint128).max
                );
        }
        if (createSlotRoleHolder != address(this)) {
            if (createSlotRoleHolder != address(0)) {
                UniversalDelegator(delegator).grantRole(CREATE_SLOT_ROLE, createSlotRoleHolder);
            }
            UniversalDelegator(delegator).renounceRole(CREATE_SLOT_ROLE, address(this));
        }
        if (defaultAdminRoleHolder != address(this)) {
            if (defaultAdminRoleHolder != address(0)) {
                UniversalDelegator(delegator).grantRole(DEFAULT_ADMIN_ROLE, defaultAdminRoleHolder);
            }
            UniversalDelegator(delegator).renounceRole(DEFAULT_ADMIN_ROLE, address(this));
        }

        // Deploy and migrate slasher.
        if (slasher != address(0)) {
            address oldSlasher = slasher;
            slasher = SlasherFactory(SLASHER_FACTORY)
                .create(UNIVERSAL_SLASHER_TYPE, abi.encode(address(this), params.slasherParams));
            UniversalSlasher(slasher).migrate(oldSlasher);
        }

        emit IVaultV2.Migrate(params, delegator, slasher);
    }

    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }
}
