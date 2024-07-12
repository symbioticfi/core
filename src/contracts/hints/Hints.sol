// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {StaticDelegateCallable} from "src/contracts/common/StaticDelegateCallable.sol";

abstract contract Hints {
    function _selfStaticDelegateCall(address target, bytes memory innerData) internal returns (bytes memory) {
        (, bytes memory returnDataInner) = target.call(
            abi.encodeWithSelector(StaticDelegateCallable.staticDelegateCall.selector, address(this), innerData)
        );
        (bool success, bytes memory returnData) = abi.decode(returnDataInner, (bool, bytes));
        if (!success) {
            if (returnData.length == 0) revert();
            assembly {
                revert(add(32, returnData), mload(returnData))
            }
        }
        return returnData;
    }
}
