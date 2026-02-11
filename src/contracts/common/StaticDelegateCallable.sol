// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2025 Symbiotic
pragma solidity ^0.8.25;

import {IStaticDelegateCallable} from "../../interfaces/common/IStaticDelegateCallable.sol";

/// @title StaticDelegateCallable
/// @notice Base contract for static delegate-call based state reads.
abstract contract StaticDelegateCallable is IStaticDelegateCallable {
    /// @inheritdoc IStaticDelegateCallable
    function staticDelegateCall(address target, bytes calldata data) external {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        bytes memory revertData = abi.encode(success, returndata);
        assembly {
            revert(add(32, revertData), mload(revertData))
        }
    }
}
