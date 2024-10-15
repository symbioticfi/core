// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {StaticDelegateCallable} from "../common/StaticDelegateCallable.sol";

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
            target.staticcall(abi.encodeCall(StaticDelegateCallable.staticDelegateCall, (address(this), dataInternal)));
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
        bytes[] memory datas,
        bytes[] memory hints
    ) internal view returns (bytes memory lowestHint) {
        uint256 length = datas.length;
        for (uint256 i; i < length; ++i) {
            target.functionStaticCall(datas[i]);
        }

        uint256 lowestGas = type(uint256).max;
        for (uint256 i; i < length; ++i) {
            uint256 gasSpent = _estimateGas(target, datas[i]);
            if (gasSpent < lowestGas || (gasSpent == lowestGas && datas[i].length < lowestHint.length)) {
                lowestGas = gasSpent;
                lowestHint = hints[i];
            }
        }
    }
}
