// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Hints} from "./Hints.sol";
import {Vault} from "src/contracts/vault/Vault.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

contract VaultHints is Hints, Vault {
    using Checkpoints for Checkpoints.Trace256;

    constructor() Vault(address(0), address(0), address(0)) {}

    function activeStakeHintInner(uint48 timestamp) external view returns (uint32 hint) {
        (,,, hint) = _activeStake.upperLookupRecentCheckpoint(timestamp);
    }

    function activeStakeHint(address vault, uint48 timestamp) external returns (bytes memory) {
        return
            _selfStaticDelegateCall(vault, abi.encodeWithSelector(VaultHints.activeStakeHintInner.selector, timestamp));
    }
}
