// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBaseDelegator} from "./IBaseDelegator.sol";

import {Checkpoints} from "../../contracts/libraries/Checkpoints.sol";

interface IUniversalDelegator is IBaseDelegator {
    error NotEnoughAvailable();
    error NotSameParent();
    error WrongOrder();
    error NotSameAllocated();
    error PartiallyAllocated();
    error NetworkAlreadyAssigned();
    error NetworkNotAssigned();
    error OperatorAlreadyAssigned();
    error OperatorNotAssigned();
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
    }

    struct SlotStorage {
        bool exists;
        uint32 nextSlot;
        uint32 prevSlot;
        uint32 totalChildren;
        uint32 firstChild;
        uint32 lastChild;
        bool isShared;
        Checkpoints.Trace256 size;
        Checkpoints.Trace256 prevSum;
        Checkpoints.Trace256 pendingFreeCumulative;
    }

    struct Slot {
        bool exists;
        uint32 nextSlot;
        uint32 prevSlot;
        uint32 totalChildren;
        uint32 firstChild;
        uint32 lastChild;
        bool isShared;
        uint256 size;
        uint256 prevSum;
        uint256 pendingFreeCumulative;
    }

    /**
     * @notice Hints for an available balance lookup.
     * @param balanceHints hints forwarded to getBalanceAt
     * @param pendingFreeHint hint for pendingFreeCumulative at the requested timestamp
     * @param pendingFreeEpochHint hint for pendingFreeCumulative at (timestamp - epochDuration)
     */
    struct AvailableHints {
        bytes balanceHints;
        bytes pendingFreeHint;
        bytes pendingFreeEpochHint;
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

    event CreateSlot(uint96 indexed index, uint256 size);

    event SetIsShared(uint96 indexed index, bool isShared);

    event SetSize(uint96 indexed index, uint256 size);

    event SetShare(uint96 indexed index, uint256 share);

    event SwapSlots(uint96 indexed index1, uint96 indexed index2);

    event RemoveSlot(uint96 indexed index);

    event AssignNetwork(uint96 indexed index, bytes32 indexed subnetwork);

    event UnassignNetwork(bytes32 indexed subnetwork);

    event AssignOperator(uint96 indexed index, address indexed operator);

    event UnassignOperator(uint96 indexed index, address indexed operator);

    function getSlot(uint96 index) external view returns (Slot memory);

    function getBalanceAt(uint96 index, uint48 timestamp, bytes memory hints) external view returns (uint256);

    function getBalance(uint96 index) external view returns (uint256);

    function getAvailableAt(uint96 index, uint48 timestamp, bytes memory hints) external view returns (uint256);

    function getAvailable(uint96 index) external view returns (uint256);

    function getAllocatedAt(uint96 index, uint48 timestamp, bytes memory hints) external view returns (uint256);

    function getAllocated(uint96 index) external view returns (uint256);

    function getAllocatedAt(bytes32 subnetwork, address operator, uint48 timestamp, bytes memory hints)
        external
        view
        returns (uint256);

    function getAllocated(bytes32 subnetwork, address operator) external view returns (uint256);

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

    function getIsShared(bytes32 subnetwork, address operator) external view returns (bool);

    function createSlot(uint96 parentIndex, bool isShared, uint256 size) external;

    function setSize(uint96 index, uint256 size) external returns (uint256 pending);

    function swapSlots(uint96 index1, uint96 index2) external;

    function removeSlot(uint96 index) external;

    function assignNetwork(uint96 index, bytes32 subnetwork) external;

    function unassignNetwork(bytes32 subnetwork) external;

    function assignOperator(uint96 index, address operator) external;

    function unassignOperator(uint96 index, address operator) external;
}
