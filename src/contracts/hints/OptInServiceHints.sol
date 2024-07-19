// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Hints} from "./Hints.sol";
import {OptInService} from "src/contracts/service/OptInService.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

contract OptInServiceHints is Hints, OptInService {
    using Checkpoints for Checkpoints.Trace208;

    constructor() OptInService(address(0), address(0)) {}

    function optInHintInternal(
        address who,
        address where,
        uint48 timestamp
    ) external view internalFunction returns (uint32 hint) {
        (,,, hint) = _isOptedIn[who][where].upperLookupRecentCheckpoint(timestamp);
    }

    function optInHint(
        address optInService,
        address who,
        address where,
        uint48 timestamp
    ) external returns (bytes memory) {
        bytes memory hint = _selfStaticDelegateCall(
            optInService, abi.encodeWithSelector(OptInServiceHints.optInHintInternal.selector, who, where, timestamp)
        );

        return _optimizeHint(
            optInService,
            abi.encodeWithSelector(OptInService.isOptedInAt.selector, who, where, timestamp, ""),
            abi.encodeWithSelector(OptInService.isOptedInAt.selector, who, where, timestamp, hint),
            hint
        );
    }
}
