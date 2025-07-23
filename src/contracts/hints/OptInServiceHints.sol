// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Hints} from "./Hints.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";

contract OptInServiceHints is Hints {
    using Checkpoints for Checkpoints.Trace208;

    mapping(address who => mapping(address where => uint256 nonce)) public nonces;
    mapping(address who => mapping(address where => Checkpoints.Trace208 value)) internal _isOptedIn;

    function optInHintInternal(
        address who,
        address where,
        uint48 timestamp
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _isOptedIn[who][where].upperLookupRecentCheckpoint(timestamp);
    }

    function optInHint(
        address optInService,
        address who,
        address where,
        uint48 timestamp
    ) external view returns (bytes memory hint) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                optInService, abi.encodeCall(OptInServiceHints.optInHintInternal, (who, where, timestamp))
            ),
            (bool, uint32)
        );

        if (exists) {
            hint = abi.encode(hint_);
        }
    }
}
