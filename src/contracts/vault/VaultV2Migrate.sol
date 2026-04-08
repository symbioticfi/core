// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {DelegatorFactory} from "../DelegatorFactory.sol";
import {SlasherFactory} from "../SlasherFactory.sol";
import {UniversalDelegator} from "../delegator/UniversalDelegator.sol";
import {UniversalSlasher} from "../slasher/UniversalSlasher.sol";
import {VaultV2Storage} from "./VaultV2Storage.sol";
import {Checkpoints as CheckpointsV2} from "../libraries/CheckpointsV2.sol";
import {Checkpoints} from "../libraries/Checkpoints.sol";

import {
    IVaultV2,
    MAX_DURATION,
    SET_ADAPTER_LIMIT_ROLE,
    SWAP_ADAPTERS_ROLE,
    ALLOCATE_ADAPTER_ROLE,
    DEALLOCATE_ADAPTER_ROLE
} from "../../interfaces/vault/IVaultV2.sol";
import {UNIVERSAL_DELEGATOR_TYPE} from "../../interfaces/delegator/IUniversalDelegator.sol";
import {UNIVERSAL_SLASHER_TYPE} from "../../interfaces/slasher/IUniversalSlasher.sol";
import {VAULT_VERSION} from "../../interfaces/vault/IVault.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import {SafeTransferLib as SafeERC20} from "@solady/src/utils/SafeTransferLib.sol";

/// @title VaultV2Migrate
/// @notice Delegatecall helper that executes VaultV2 migration logic out of the main runtime bytecode.
contract VaultV2Migrate is VaultV2Storage, AccessControlUpgradeable, ERC20Upgradeable {
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
        unchecked {
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

            address oldDelegator = delegator;
            delegator = DelegatorFactory(DELEGATOR_FACTORY)
                .create(UNIVERSAL_DELEGATOR_TYPE, abi.encode(address(this), params.delegatorParams));
            UniversalDelegator(delegator).migrate(oldDelegator);

            if (slasher != address(0)) {
                address oldSlasher = slasher;
                slasher = SlasherFactory(SLASHER_FACTORY)
                    .create(UNIVERSAL_SLASHER_TYPE, abi.encode(address(this), params.slasherParams));
                UniversalSlasher(slasher).migrate(oldSlasher);
            }
        }
    }

    function _grantRoleIfNotZero(bytes32 role, address holder) internal {
        if (holder != address(0)) {
            _grantRole(role, holder);
        }
    }
}
