// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Hints} from "./Hints.sol";
import {OptInService} from "src/contracts/service/OptInService.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

contract OptInServiceHints is Hints, OptInService {
    using Checkpoints for Checkpoints.Trace208;

    constructor() OptInService(address(0), address(0)) {}

    function optInHintInner(address who, address where, uint48 timestamp) external view returns (uint32 hint) {
        (,,, hint) = _isOptedIn[who][where].upperLookupRecentCheckpoint(timestamp);
    }

    function optInHint(
        address optInService,
        address who,
        address where,
        uint48 timestamp
    ) external returns (bytes memory) {
        return _selfStaticDelegateCall(
            optInService, abi.encodeWithSelector(OptInServiceHints.optInHintInner.selector, who, where, timestamp)
        );
    }
}
