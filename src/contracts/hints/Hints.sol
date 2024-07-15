// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {StaticDelegateCallable} from "src/contracts/common/StaticDelegateCallable.sol";

import {Address} from "@openzeppelin/contracts/utils/Address.sol";

abstract contract Hints {
    using Address for address;

    address private immutable _SELF;

    constructor() {
        _SELF = address(this);
    }

    error ExternalCall();

    modifier internalFunction() {
        if (msg.sender != _SELF) {
            revert ExternalCall();
        }
        _;
    }

    function _selfStaticDelegateCall(address target, bytes memory dataInternal) internal returns (bytes memory) {
        (, bytes memory returnDataInternal) = target.call(
            abi.encodeWithSelector(StaticDelegateCallable.staticDelegateCall.selector, address(this), dataInternal)
        );
        (bool success, bytes memory returnData) = abi.decode(returnDataInternal, (bool, bytes));
        if (!success) {
            if (returnData.length == 0) revert();
            assembly {
                revert(add(32, returnData), mload(returnData))
            }
        }
        return returnData;
    }

    function _estimateGas(address target, bytes memory data) private view returns (uint256) {
        uint256 gasLeft = gasleft();
        target.functionStaticCall(data);
        return gasLeft - gasleft();
    }

    function _optimizeHint(
        address target,
        bytes memory dataWithoutHint,
        bytes memory dataWithHint,
        bytes memory hint
    ) internal view returns (bytes memory) {
        uint256 gasSpentWithoutHint = _estimateGas(target, dataWithoutHint);
        uint256 gasSpentWithHint = _estimateGas(target, dataWithHint);
        return gasSpentWithHint < gasSpentWithoutHint ? hint : new bytes(0);
    }
}
