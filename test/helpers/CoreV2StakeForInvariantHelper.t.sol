// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {CoreV2StakeForInvariantHelper} from "./CoreV2StakeForInvariantHelper.sol";

contract MockStakeForDelegator {
    mapping(uint64 => mapping(uint48 => uint256)) internal _allocated;

    function setAllocated(uint64 slot, uint48 duration, uint256 amount) external {
        _allocated[slot][duration] = amount;
    }

    function getAllocated(uint64 slot, uint48 duration) external view returns (uint256) {
        return _allocated[slot][duration];
    }
}

contract MockInvariantVault {
    uint256 internal _activeStake;
    uint256 internal _totalStake;
    mapping(uint48 => uint256) internal _activeWithdrawalsFor;

    function setActiveStake(uint256 value) external {
        _activeStake = value;
    }

    function setTotalStake(uint256 value) external {
        _totalStake = value;
    }

    function setActiveWithdrawalsFor(uint48 duration, uint256 value) external {
        _activeWithdrawalsFor[duration] = value;
    }

    function activeStake() external view returns (uint256) {
        return _activeStake;
    }

    function activeWithdrawalsFor(uint48 duration) external view returns (uint256) {
        return _activeWithdrawalsFor[duration];
    }

    function totalStake() external view returns (uint256) {
        return _totalStake;
    }
}

contract CoreV2StakeForInvariantHarness is CoreV2StakeForInvariantHelper {
    function assertInvariantForThreeSlots(
        address vault_,
        address delegator_,
        uint64 slot1,
        uint64 slot2,
        uint64 slot3,
        uint48 epochDuration
    ) external view {
        _assertStakeForInvariantForThreeSlots(vault_, delegator_, slot1, slot2, slot3, epochDuration);
    }
}

contract CoreV2StakeForInvariantHelperTest is Test {
    uint48 internal constant EPOCH_DURATION = 3;

    MockStakeForDelegator internal delegator;
    MockInvariantVault internal vault;
    CoreV2StakeForInvariantHarness internal harness;

    function setUp() public {
        delegator = new MockStakeForDelegator();
        vault = new MockInvariantVault();
        harness = new CoreV2StakeForInvariantHarness();
    }

    function test_invariant_allowsWhenPerDurationCapacityUsesActiveWithdrawals() public {
        vault.setActiveStake(50);
        vault.setTotalStake(50);
        vault.setActiveWithdrawalsFor(0, 50);

        delegator.setAllocated(1, 0, 50);
        delegator.setAllocated(1, EPOCH_DURATION / 2, 20);
        delegator.setAllocated(1, EPOCH_DURATION - 1, 10);
        delegator.setAllocated(1, EPOCH_DURATION, 0);

        delegator.setAllocated(2, 0, 50);
        delegator.setAllocated(2, EPOCH_DURATION / 2, 20);
        delegator.setAllocated(2, EPOCH_DURATION - 1, 20);
        delegator.setAllocated(2, EPOCH_DURATION, 0);

        harness.assertInvariantForThreeSlots(address(vault), address(delegator), 1, 2, 0, EPOCH_DURATION);
    }

    function test_invariant_revertsWhenStakeForIncreasesWithDuration() public {
        vault.setActiveStake(50);
        vault.setTotalStake(50);

        delegator.setAllocated(1, 0, 10);
        delegator.setAllocated(1, EPOCH_DURATION / 2, 20);
        delegator.setAllocated(1, EPOCH_DURATION - 1, 20);
        delegator.setAllocated(1, EPOCH_DURATION, 20);

        vm.expectRevert(
            abi.encodeWithSelector(
                CoreV2StakeForInvariantHelper.StakeForDecreasesWithDuration.selector,
                uint64(1),
                uint48(0),
                uint256(10),
                uint48(EPOCH_DURATION / 2),
                uint256(20)
            )
        );
        harness.assertInvariantForThreeSlots(address(vault), address(delegator), 1, 0, 0, EPOCH_DURATION);
    }
}
