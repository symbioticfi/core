// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Hints} from "./Hints.sol";
import {VaultStorage} from "src/contracts/vault/VaultStorage.sol";
import {Vault} from "src/contracts/vault/Vault.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

contract VaultHints is Hints, Vault {
    using Checkpoints for Checkpoints.Trace256;

    constructor() Vault(address(0), address(0), address(0)) {}

    function activeStakeHintInternal(uint48 timestamp) external view internalFunction returns (uint32 hint) {
        (,,, hint) = _activeStake.upperLookupRecentCheckpoint(timestamp);
    }

    function activeStakeHint(address vault, uint48 timestamp) public returns (bytes memory) {
        bytes memory hint = _selfStaticDelegateCall(
            vault, abi.encodeWithSelector(VaultHints.activeStakeHintInternal.selector, timestamp)
        );

        return _optimizeHint(
            vault,
            abi.encodeWithSelector(VaultStorage.activeStakeAt.selector, timestamp, ""),
            abi.encodeWithSelector(VaultStorage.activeStakeAt.selector, timestamp, hint),
            hint
        );
    }

    function activeSharesHintInternal(uint48 timestamp) external view internalFunction returns (uint32 hint) {
        (,,, hint) = _activeShares.upperLookupRecentCheckpoint(timestamp);
    }

    function activeSharesHint(address vault, uint48 timestamp) public returns (bytes memory) {
        bytes memory hint = _selfStaticDelegateCall(
            vault, abi.encodeWithSelector(VaultHints.activeSharesHintInternal.selector, timestamp)
        );

        return _optimizeHint(
            vault,
            abi.encodeWithSelector(VaultStorage.activeSharesAt.selector, timestamp, ""),
            abi.encodeWithSelector(VaultStorage.activeSharesAt.selector, timestamp, hint),
            hint
        );
    }

    function activeSharesOfHintInternal(
        address account,
        uint48 timestamp
    ) external view internalFunction returns (uint32 hint) {
        (,,, hint) = _activeSharesOf[account].upperLookupRecentCheckpoint(timestamp);
    }

    function activeSharesOfHint(address vault, address account, uint48 timestamp) public returns (bytes memory) {
        bytes memory hint = _selfStaticDelegateCall(
            vault, abi.encodeWithSelector(VaultHints.activeSharesOfHintInternal.selector, account, timestamp)
        );

        return _optimizeHint(
            vault,
            abi.encodeWithSelector(VaultStorage.activeSharesOfAt.selector, account, timestamp, ""),
            abi.encodeWithSelector(VaultStorage.activeSharesOfAt.selector, account, timestamp, hint),
            hint
        );
    }

    function activeBalanceOfHints(
        address vault,
        address account,
        uint48 timestamp
    ) external internalFunction returns (bytes memory) {
        bytes memory activeSharesOfHint_ = activeSharesOfHint(vault, account, timestamp);
        bytes memory activeStakeHint_ = activeStakeHint(vault, timestamp);
        bytes memory activeSharesHint_ = activeSharesHint(vault, timestamp);

        bytes memory hints;
        if (activeSharesOfHint_.length > 0 || activeStakeHint_.length > 0 || activeSharesHint_.length > 0) {
            hints = abi.encode(
                ActiveBalanceOfHints({
                    activeSharesOfHint: activeSharesOfHint_,
                    activeStakeHint: activeStakeHint_,
                    activeSharesHint: activeSharesHint_
                })
            );
        }

        return hints;
    }
}
