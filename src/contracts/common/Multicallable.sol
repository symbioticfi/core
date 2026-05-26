// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.25;

import {IMulticallable} from "../../interfaces/common/IMulticallable.sol";

/// @title Multicallable
/// @notice Abstract contract for contracts that support multicall.
abstract contract Multicallable is IMulticallable {
    /// @inheritdoc IMulticallable
    function multicall(bytes[] calldata data) external {
        for (uint256 i; i < data.length; ++i) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
    }
}