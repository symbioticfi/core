// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBaseDelegator} from "./IBaseDelegator.sol";

import {Checkpoints} from "../../contracts/libraries/Checkpoints.sol";

uint32 constant WITHDRAWAL_BUFFER_CHILD_INDEX = 1;
uint96 constant WITHDRAWAL_BUFFER_INDEX = 0x10000000000000000;

interface IUniversalDelegator is IBaseDelegator {
    error NotEnoughAvailable();
    error NotSameParent();
    error SameSlot();
    error NotSameAllocated();
    error PartiallyAllocated();
    error NotAssigned();
    error SlotAllocated();
    error MissingRoleHolders();
    error IsSharedNotChanged();
    error WrongDepth();
    error TooManyShares();
    error IsShared();
    error SlotNotCreated();
    error OldVault();
    error NotMigrating();
    error WrongMigrate();
    error InvalidDuration();
    error IsWithdrawalBuffer();
    error NotNetworkOrMiddleware();
    error AlreadyAssigned();

    struct InitParams {
        BaseParams baseParams;
        address createSlotRoleHolder;
        address setIsSharedRoleHolder;
        address setSizeRoleHolder;
        address setShareRoleHolder;
        address swapSlotsRoleHolder;
        address assignNetworkRoleHolder;
        address unassignNetworkRoleHolder;
        address assignOperatorRoleHolder;
        address unassignOperatorRoleHolder;
        uint256 withdrawalBuffer;
    }

    struct SlotStorage {
        bool exists;
        uint32 nextSlot;
        uint32 prevSlot;
        uint32 numChildren;
        uint32 firstChild;
        uint32 lastChild;
        uint32 numNetworks;
        bool isShared;
        bool noPlugins;
        Checkpoints.Trace256 size;
        Checkpoints.Trace256 prevSum;
        Checkpoints.Trace256 pendingCumulative;
        Checkpoints.Trace256 childrenPendingCumulative;
    }

    struct Slot {
        bool exists;
        uint32 nextSlot;
        uint32 prevSlot;
        uint32 numChildren;
        uint32 firstChild;
        uint32 lastChild;
        bool isShared;
        bool noPlugins;
        uint256 size;
        uint256 prevSum;
        uint256 childrenPendingCumulative;
    }

    /**
     * @notice Hints for an available balance lookup.
     * @param balanceHints hints forwarded to getBalanceAt
     * @param pendingHint hint for childrenPendingCumulative at the requested timestamp
     * @param pendingEpochHint hint for childrenPendingCumulative at (timestamp - epochDuration)
     */
    struct AvailableHints {
        bytes balanceHints;
        bytes pendingHint;
        bytes pendingEpochHint;
    }

    /**
     * @notice Hints for an allocation lookup by slot index.
     * @param sizeHint hint for the size checkpoint
     * @param availableHints hints forwarded to getAvailableAt(parentIndex,...)
     * @param isSharedHint hint for isShared
     * @param prevSumHint hint for the prevSum checkpoint
     */
    struct BaseAllocatedHints {
        bytes sizeHint;
        bytes availableHints;
        bytes isSharedHint;
        bytes prevSumHint;
    }

    /**
     * @notice Hints for an allocation lookup by subnetwork/operator.
     * @param slotOfHints hints forwarded to getSlotOfAt
     * @param allocatedHints hints forwarded to getAllocatedAt(uint96,...)
     */
    struct AllocatedHints {
        bytes slotOfHints;
        bytes allocatedHints;
    }

    /**
     * @notice Hints for a combined subnetwork/operator slot lookup.
     * @param slotOfNetworkHints hints forwarded to getSlotOfNetworkAt
     * @param slotOfOperatorHints hints forwarded to getSlotOfOperatorAt
     */
    struct SlotOfHints {
        bytes slotOfNetworkHints;
        bytes slotOfOperatorHints;
    }

    /**
     * @notice Hints for a stake.
     * @param baseHints base hints
     * @param allocatedHints hints for getAllocatedAt(subnetwork, operator, timestamp, ...)
     * @dev expects ABI-encoded AllocatedByOperatorHints
     */
    struct StakeHints {
        bytes baseHints;
        bytes allocatedHints;
    }

    event CreateSlot(uint96 indexed index, bool isShared, bool noPlugins, uint256 size);

    event SetIsShared(uint96 indexed index, bool isShared);

    event SetSize(uint96 indexed index, uint256 size);

    event SetShare(uint96 indexed index, uint256 share);

    event SwapSlots(uint96 indexed index1, uint96 indexed index2);

    event RemoveSlot(uint96 indexed index);

    event ResetAllocation(bytes32 indexed subnetwork);

    function getWithdrawalBuffer() external view returns (uint256);

    function getNoPluginsSize() external view returns (uint256);

    function getSlot(uint96 index) external view returns (Slot memory);

    function stakeForAt(bytes32 subnetwork, address operator, uint48 duration, uint48 timestamp, bytes memory hints)
        external
        view
        returns (uint256);

    function stakeFor(bytes32 subnetwork, address operator, uint48 duration) external view returns (uint256);

    function getBalanceAt(uint96 index, uint48 timestamp, uint48 duration, bytes memory hints)
        external
        view
        returns (uint256);

    function getBalance(uint96 index, uint48 duration) external view returns (uint256);

    function getAvailableAt(uint96 index, uint48 timestamp, uint48 duration, bytes memory hints)
        external
        view
        returns (uint256);

    function getAvailable(uint96 index, uint48 duration) external view returns (uint256);

    function getAllocatedAt(uint96 index, uint48 timestamp, uint48 duration, bytes memory hints)
        external
        view
        returns (uint256);

    function getAllocated(uint96 index, uint48 duration) external view returns (uint256);

    function getAllocatedAt(bytes32 subnetwork, address operator, uint48 timestamp, uint48 duration, bytes memory hints)
        external
        view
        returns (uint256);

    function getAllocated(bytes32 subnetwork, address operator, uint48 duration) external view returns (uint256);

    function getSlotOfNetworkAt(bytes32 subnetwork, uint48 timestamp, bytes memory hint) external view returns (uint96);

    function getSlotOfNetwork(bytes32 subnetwork) external view returns (uint96);

    function getSlotOfOperatorAt(uint96 parentIndex, address operator, uint48 timestamp, bytes memory hint)
        external
        view
        returns (uint96);

    function getSlotOfOperator(uint96 parentIndex, address operator) external view returns (uint96);

    function getSlotOfAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        external
        view
        returns (uint96);

    function getSlotOf(bytes32 subnetwork, address operator) external view returns (uint96);

    function getIsShared(bytes32 subnetwork) external view returns (bool);

    function getIsNoPlugins(bytes32 subnetwork) external view returns (bool);

    function createSlot(bytes32 subnetworkOrOperator, uint96 parentIndex, bool isShared, bool noPlugins, uint256 size)
        external
        returns (uint96 index);

    function setSize(uint96 index, uint256 size) external returns (uint256 pending);

    function swapSlots(uint96 index1, uint96 index2) external;

    function removeSlot(uint96 index) external;
}
