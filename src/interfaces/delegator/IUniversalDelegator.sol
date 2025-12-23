// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IBaseDelegator} from "./IBaseDelegator.sol";

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

    struct InitParams {
        BaseParams baseParams;
        address curatorRoleHolder;
    }

    struct StakeHints {
        bytes baseHints;
        bytes allocatedHints;
    }

    event CreateSlot(uint96 indexed index, uint256 size);

    event SetIsShared(uint96 indexed index, bool isShared);

    event SetSize(uint96 indexed index, uint256 size);

    event SwapSlots(uint96 indexed index1, uint96 indexed index2);

    event AssignNetwork(uint96 indexed index, bytes32 indexed subnetwork);

    event UnassignNetwork(bytes32 indexed subnetwork);

    event AssignOperator(uint96 indexed index, address indexed operator);

    event UnassignOperator(uint96 indexed index, address indexed operator);
}
