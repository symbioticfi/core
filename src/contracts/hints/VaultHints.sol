// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Hints} from "./Hints.sol";
import {VaultStorage} from "src/contracts/vault/VaultStorage.sol";
import {Vault} from "src/contracts/vault/Vault.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

contract VaultHints is Hints, Vault {
    using Checkpoints for Checkpoints.Trace256;

    constructor() Vault(address(0), address(0), address(0)) {}

    function activeStakeHintInternal(uint48 timestamp)
        external
        view
        internalFunction
        returns (bool exists, uint32 hint)
    {
        (exists,,, hint) = _activeStake.upperLookupRecentCheckpoint(timestamp);
    }

    function activeStakeHint(address vault, uint48 timestamp) public returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                vault, abi.encodeWithSelector(VaultHints.activeStakeHintInternal.selector, timestamp)
            ),
            (bool, uint32)
        );
        bytes memory hint;
        if (exists) {
            hint = abi.encode(hint_);
        }

        uint256 N = 2;
        bytes[] memory hints = new bytes[](N);
        hints[0] = new bytes(0);
        hints[1] = hint;
        bytes[] memory datas = new bytes[](N);
        for (uint256 i; i < N; ++i) {
            datas[i] = abi.encodeWithSelector(VaultStorage.activeStakeAt.selector, timestamp, hints[i]);
        }

        return _optimizeHint(vault, datas, hints);
    }

    function activeSharesHintInternal(uint48 timestamp)
        external
        view
        internalFunction
        returns (bool exists, uint32 hint)
    {
        (exists,,, hint) = _activeShares.upperLookupRecentCheckpoint(timestamp);
    }

    function activeSharesHint(address vault, uint48 timestamp) public returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                vault, abi.encodeWithSelector(VaultHints.activeSharesHintInternal.selector, timestamp)
            ),
            (bool, uint32)
        );
        bytes memory hint;
        if (exists) {
            hint = abi.encode(hint_);
        }

        uint256 N = 2;
        bytes[] memory hints = new bytes[](N);
        hints[0] = new bytes(0);
        hints[1] = hint;
        bytes[] memory datas = new bytes[](N);
        for (uint256 i; i < N; ++i) {
            datas[i] = abi.encodeWithSelector(VaultStorage.activeSharesAt.selector, timestamp, hints[i]);
        }

        return _optimizeHint(vault, datas, hints);
    }

    function activeSharesOfHintInternal(
        address account,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _activeSharesOf[account].upperLookupRecentCheckpoint(timestamp);
    }

    function activeSharesOfHint(address vault, address account, uint48 timestamp) public returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                vault, abi.encodeWithSelector(VaultHints.activeSharesOfHintInternal.selector, account, timestamp)
            ),
            (bool, uint32)
        );
        bytes memory hint;
        if (exists) {
            hint = abi.encode(hint_);
        }

        uint256 N = 2;
        bytes[] memory hints = new bytes[](N);
        hints[0] = new bytes(0);
        hints[1] = hint;
        bytes[] memory datas = new bytes[](N);
        for (uint256 i; i < N; ++i) {
            datas[i] = abi.encodeWithSelector(VaultStorage.activeSharesOfAt.selector, account, timestamp, hints[i]);
        }

        return _optimizeHint(vault, datas, hints);
    }

    function activeBalanceOfHints(address vault, address account, uint48 timestamp) external returns (bytes memory) {
        bytes memory activeSharesOfHint_ = activeSharesOfHint(vault, account, timestamp);
        bytes memory activeStakeHint_ = activeStakeHint(vault, timestamp);
        bytes memory activeSharesHint_ = activeSharesHint(vault, timestamp);

        if (activeSharesOfHint_.length > 0 || activeStakeHint_.length > 0 || activeSharesHint_.length > 0) {
            uint256 N = 2;
            bytes[] memory hints = new bytes[](N);
            hints[0] = new bytes(0);
            hints[1] = abi.encode(
                ActiveBalanceOfHints({
                    activeSharesOfHint: activeSharesOfHint_,
                    activeStakeHint: activeStakeHint_,
                    activeSharesHint: activeSharesHint_
                })
            );
            bytes[] memory datas = new bytes[](N);
            for (uint256 i; i < N; ++i) {
                datas[i] = abi.encodeWithSelector(Vault.activeBalanceOfAt.selector, account, timestamp, hints[i]);
            }

            return _optimizeHint(vault, datas, hints);
        }
    }
}
