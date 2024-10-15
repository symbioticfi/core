// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Hints} from "./Hints.sol";
import {Vault} from "../vault/Vault.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";

contract VaultHints is Hints, Vault {
    using Checkpoints for Checkpoints.Trace256;

    constructor() Vault(address(0), address(0), address(0)) {}

    function activeStakeHintInternal(
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _activeStake.upperLookupRecentCheckpoint(timestamp);
    }

    function activeStakeHint(address vault, uint48 timestamp) public view returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultHints.activeStakeHintInternal, (timestamp))),
            (bool, uint32)
        );

        if (exists) {
            return abi.encode(hint_);
        }
    }

    function activeSharesHintInternal(
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _activeShares.upperLookupRecentCheckpoint(timestamp);
    }

    function activeSharesHint(address vault, uint48 timestamp) public view returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultHints.activeSharesHintInternal, (timestamp))),
            (bool, uint32)
        );

        if (exists) {
            return abi.encode(hint_);
        }
    }

    function activeSharesOfHintInternal(
        address account,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _activeSharesOf[account].upperLookupRecentCheckpoint(timestamp);
    }

    function activeSharesOfHint(address vault, address account, uint48 timestamp) public view returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(vault, abi.encodeCall(VaultHints.activeSharesOfHintInternal, (account, timestamp))),
            (bool, uint32)
        );

        if (exists) {
            return abi.encode(hint_);
        }
    }

    function activeBalanceOfHints(
        address vault,
        address account,
        uint48 timestamp
    ) external view returns (bytes memory) {
        bytes memory activeSharesOfHint_ = activeSharesOfHint(vault, account, timestamp);
        bytes memory activeStakeHint_ = activeStakeHint(vault, timestamp);
        bytes memory activeSharesHint_ = activeSharesHint(vault, timestamp);

        if (activeSharesOfHint_.length > 0 || activeStakeHint_.length > 0 || activeSharesHint_.length > 0) {
            return abi.encode(
                ActiveBalanceOfHints({
                    activeSharesOfHint: activeSharesOfHint_,
                    activeStakeHint: activeStakeHint_,
                    activeSharesHint: activeSharesHint_
                })
            );
        }
    }
}
