// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {DelegatorFactory} from "../DelegatorFactory.sol";
import {SlasherFactory} from "../SlasherFactory.sol";
import {UniversalDelegator} from "../delegator/UniversalDelegator.sol";
import {UniversalSlasher} from "../slasher/UniversalSlasher.sol";
import {VaultV2Storage} from "./VaultV2Storage.sol";

import {Checkpoints} from "../libraries/CheckpointsV2.sol";
import {ERC4626Math} from "../libraries/ERC4626MathV2.sol";

import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";

contract MigratorV1V2 is VaultV2Storage, ERC20Upgradeable {
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;
    using StorageSlot for bytes32;

    /* ERRORS */

    error AlreadyClaimed();

    error InsufficientWithdrawal();

    error MigrationNotCompleted();

    /* EVENTS */

    event MigrateWithdrawalOf(address indexed account, uint48 indexed epoch, uint256 shares);

    // keccak256(abi.encode(uint256(keccak256("symbiotic.core.MigratorV1V2")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant MIGRATE_TIMESTAMP_POSITION =
        0x7bb1d3f1242ae8a862f861e1ab906d19c5242b3ddc070e7df65c70164c3d2e00;

    /* CONSTRUCTOR */

    constructor(address delegatorFactory, address slasherFactory) VaultV2Storage(delegatorFactory, slasherFactory) {}

    function onSetPluginLimit() public view {
        if (block.timestamp <= MIGRATE_TIMESTAMP_POSITION.getUint256Slot().value + epochDuration) {
            revert MigrationNotCompleted();
        }
    }

    function migrateWithdrawalOf(address account, uint48 epoch) public {
        if (_isEpochWithdrawalsClaimed[epoch][account]) {
            revert AlreadyClaimed();
        }
        uint256 shares = _epochWithdrawalSharesOf[epoch][account];
        if (shares == 0) {
            revert InsufficientWithdrawal();
        }
        uint208 bucketIndex = epoch - 1;
        uint48 unlockAfter = uint48(block.timestamp) + epochDuration;
        if (unlockAfter >= _withdrawalSharesCumulative.at(0)._key) {
            shares = ERC4626Math.previewRedeem(shares, _epochWithdrawals[epoch], _epochWithdrawalShares[epoch]);
        } else if (_withdrawalShares[bucketIndex].latest() == 0) {
            _withdrawals[bucketIndex].push(uint48(block.timestamp), _epochWithdrawals[epoch]);
            _withdrawalShares[bucketIndex].push(uint48(block.timestamp), _epochWithdrawalShares[epoch]);
            _unlockToBucket._trace._checkpoints[bucketIndex]._key = unlockAfter;
            _unlockToBucket._trace._checkpoints[bucketIndex]._value = bucketIndex;
        }
        _withdrawalsOf[account].push(Withdrawal(false, unlockAfter, shares));
        _isEpochWithdrawalsClaimed[epoch][account] = true;

        emit MigrateWithdrawalOf(account, epoch, shares);
    }

    function migrate(uint64 oldVersion, bytes calldata data) public {
        MIGRATE_TIMESTAMP_POSITION.getUint256Slot().value = block.timestamp;

        IVaultV2.MigrateParams memory params = abi.decode(data, (IVaultV2.MigrateParams));
        if (oldVersion == 1) {
            __ERC20_init(params.name, params.symbol);
        }
        uint48 epoch = uint48((block.timestamp - _epochDurationInit) / epochDuration);
        uint48 nextEpochStart = _epochDurationInit + (epoch + 1) * epochDuration;
        uint256 epochWithdrawals;
        uint208 bucketIndex;
        if (epoch > 0) {
            epochWithdrawals = _epochWithdrawals[epoch];
            _withdrawalSharesCumulative.push(nextEpochStart, epochWithdrawals);
            bucketIndex = epoch - 1;
        }
        epochWithdrawals += _epochWithdrawals[epoch + 1];
        _withdrawalSharesCumulative.push(uint48(block.timestamp) + epochDuration, epochWithdrawals);
        assembly ("memory-safe") {
            sstore(_unlockToBucket.slot, bucketIndex)
        }
        _unlockToBucket.push(uint48(block.timestamp), bucketIndex);
        _withdrawals[epoch].push(uint48(block.timestamp), epochWithdrawals);
        _withdrawalShares[epoch].push(uint48(block.timestamp), epochWithdrawals);

        address newDelegator =
            DelegatorFactory(DELEGATOR_FACTORY).create(4, abi.encode(address(this), params.delegatorParams));
        UniversalDelegator(newDelegator).migrate();
        delegator = newDelegator;
        if (slasher != address(0)) {
            address newSlasher =
                SlasherFactory(SLASHER_FACTORY).create(2, abi.encode(address(this), params.slasherParams));
            UniversalSlasher(newSlasher).migrate();
            slasher = newSlasher;
        }

        _unclaimedRaw = int256(IERC20(collateral).balanceOf(address(this)) - activeStake() - epochWithdrawals);

        emit IVaultV2.Migrate(params, delegator, slasher);
    }
}
