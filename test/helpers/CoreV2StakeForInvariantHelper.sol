// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";

interface IStakeForDelegator {
    function getAllocated(uint96 index, uint48 duration) external view returns (uint256);
}

abstract contract CoreV2StakeForInvariantHelper {
    error StakeForSumExceedsCapacity(uint48 duration, uint256 totalStakeFor, uint256 capacity);
    error StakeForDecreasesWithDuration(
        uint96 slot, uint48 shorterDuration, uint256 shorterStakeFor, uint48 longerDuration, uint256 longerStakeFor
    );

    function _assertStakeForSumLeCapacity(address vault_, address delegator_, uint96[] memory slots, uint48 duration)
        internal
        view
    {
        uint256 totalStakeFor;
        for (uint256 i = 0; i < slots.length; ++i) {
            if (slots[i] == 0) {
                continue;
            }
            totalStakeFor += IStakeForDelegator(delegator_).getAllocated(slots[i], duration);
        }

        uint256 capacity = IVaultV2(vault_).activeStake() + IVaultV2(vault_).activeWithdrawalsFor(duration);
        if (totalStakeFor > capacity) {
            revert StakeForSumExceedsCapacity(duration, totalStakeFor, capacity);
        }
    }

    function _assertStakeForNonDecreasingAcrossDurations(
        address delegator_,
        uint96[] memory slots,
        uint48 epochDuration
    ) internal view {
        uint48 halfDuration = epochDuration / 2;

        for (uint256 i = 0; i < slots.length; ++i) {
            uint96 slot = slots[i];
            if (slot == 0) {
                continue;
            }

            uint256 stakeFor0 = IStakeForDelegator(delegator_).getAllocated(slot, 0);
            uint256 stakeForHalf = IStakeForDelegator(delegator_).getAllocated(slot, halfDuration);
            if (stakeFor0 < stakeForHalf) {
                revert StakeForDecreasesWithDuration(slot, 0, stakeFor0, halfDuration, stakeForHalf);
            }

            if (epochDuration > 1) {
                uint48 maxDuration = epochDuration - 1;
                uint256 stakeForMaxDuration = IStakeForDelegator(delegator_).getAllocated(slot, maxDuration);
                if (stakeForHalf < stakeForMaxDuration) {
                    revert StakeForDecreasesWithDuration(
                        slot, halfDuration, stakeForHalf, maxDuration, stakeForMaxDuration
                    );
                }
            }

            uint256 stakeForEpoch = IStakeForDelegator(delegator_).getAllocated(slot, epochDuration);
            if (stakeForHalf < stakeForEpoch) {
                revert StakeForDecreasesWithDuration(slot, halfDuration, stakeForHalf, epochDuration, stakeForEpoch);
            }
        }
    }

    function _assertStakeForInvariantForDurations(
        address vault_,
        address delegator_,
        uint96[] memory slots,
        uint48 epochDuration
    ) internal view {
        _assertStakeForSumLeCapacity(vault_, delegator_, slots, 0);
        _assertStakeForSumLeCapacity(vault_, delegator_, slots, epochDuration / 2);
        _assertStakeForSumLeCapacity(vault_, delegator_, slots, epochDuration);

        if (epochDuration > 1) {
            _assertStakeForSumLeCapacity(vault_, delegator_, slots, epochDuration - 1);
        }

        _assertStakeForNonDecreasingAcrossDurations(delegator_, slots, epochDuration);
    }

    function _assertStakeForInvariantForThreeSlots(
        address vault_,
        address delegator_,
        uint96 slot1,
        uint96 slot2,
        uint96 slot3,
        uint48 epochDuration
    ) internal view {
        uint96[] memory slots = new uint96[](3);
        slots[0] = slot1;
        slots[1] = slot2;
        slots[2] = slot3;

        _assertStakeForInvariantForDurations(vault_, delegator_, slots, epochDuration);
    }
}
