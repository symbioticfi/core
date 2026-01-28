// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {DelegatorFactory} from "../DelegatorFactory.sol";
import {SlasherFactory} from "../SlasherFactory.sol";
import {UniversalDelegator} from "../delegator/UniversalDelegator.sol";
import {UniversalSlasher} from "../slasher/UniversalSlasher.sol";
import {VaultV2Storage} from "./VaultV2Storage.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";
import {ERC4626Math} from "../libraries/ERC4626Math.sol";

import {IVaultV2} from "../../interfaces/vault/IVaultV2.sol";

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract MigratorV1V2 is VaultV2Storage, ERC20Upgradeable {
    using Checkpoints for Checkpoints.Trace208;
    using Checkpoints for Checkpoints.Trace256;
    using SafeCast for uint256;

    /* CONSTRUCTOR */

    constructor(address delegatorFactory, address slasherFactory) VaultV2Storage(delegatorFactory, slasherFactory) {}

    function migrateWithdrawalsOf(address account, uint48 epoch) public {
        if (_isEpochWithdrawalsClaimed[epoch][account]) {
            revert();
        }
        uint256 shares = _epochWithdrawalSharesOf[epoch][account];
        if (shares == 0) {
            revert();
        }
        uint208 bucketIndex = epoch - 1;
        uint48 unlockAfter = _epochDurationInit - 1 + (epoch + 1) * epochDuration;
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
    }

    function migrate(uint64 oldVersion, bytes calldata data) public {
        IVaultV2.MigrateParams memory params = abi.decode(data, (IVaultV2.MigrateParams));
        if (oldVersion == 1) {
            __ERC20_init(params.name, params.symbol);
        }
        uint48 epoch = (block.timestamp - _epochDurationInit).toUint48() / epochDuration;
        uint48 nextEpochStart = _epochDurationInit + (epoch + 1) * epochDuration;
        uint256 epochWithdrawals;
        uint208 bucketIndex;
        if (epoch > 0) {
            epochWithdrawals = _epochWithdrawals[epoch];
            _withdrawalSharesCumulative.push(nextEpochStart, epochWithdrawals);
            bucketIndex = epoch - 1;
        }
        epochWithdrawals += _epochWithdrawals[epoch + 1];
        _withdrawalSharesCumulative.push(nextEpochStart + epochDuration, epochWithdrawals);
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

        _unclaimedRaw = (IERC20(collateral).balanceOf(address(this)) - activeStake() - epochWithdrawals).toInt256();
    }
}
