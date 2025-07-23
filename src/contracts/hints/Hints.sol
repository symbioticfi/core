// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IStaticDelegateCallable} from "../../interfaces/common/IStaticDelegateCallable.sol";

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

    function _selfStaticDelegateCall(address target, bytes memory dataInternal) internal view returns (bytes memory) {
        (, bytes memory returnDataInternal) =
            target.staticcall(abi.encodeCall(IStaticDelegateCallable.staticDelegateCall, (address(this), dataInternal)));
        (bool success, bytes memory returnData) = abi.decode(returnDataInternal, (bool, bytes));
        if (!success) {
            if (returnData.length == 0) revert();
            assembly {
                revert(add(32, returnData), mload(returnData))
            }
        }
        return returnData;
    }
}
