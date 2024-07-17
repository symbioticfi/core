// SPDX-License-Identifier: UNLICENSED
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
    ) external view internalFunction returns (bool exists, uint32 hint) {
        (exists,,, hint) = _isOptedIn[who][where].upperLookupRecentCheckpoint(timestamp);
    }

    function optInHint(
        address optInService,
        address who,
        address where,
        uint48 timestamp
    ) external returns (bytes memory) {
        (bool exists, uint32 hint_) = abi.decode(
            _selfStaticDelegateCall(
                optInService,
                abi.encodeWithSelector(OptInServiceHints.optInHintInternal.selector, who, where, timestamp)
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
            datas[i] = abi.encodeWithSelector(OptInService.isOptedInAt.selector, who, where, timestamp, hints[i]);
        }

        return _optimizeHint(optInService, datas, hints);
    }
}
