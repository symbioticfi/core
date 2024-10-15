// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Hints} from "./Hints.sol";
import {OptInService} from "../service/OptInService.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";

contract OptInServiceHints is Hints, OptInService {
    using Checkpoints for Checkpoints.Trace208;

    constructor() OptInService(address(0), address(0), "") {}

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
    ) external view returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                optInService, abi.encodeCall(OptInServiceHints.optInHintInternal, (who, where, timestamp))
            ),
            (bool, uint32)
        );

        if (exists) {
            return abi.encode(hint_);
        }
    }
}
