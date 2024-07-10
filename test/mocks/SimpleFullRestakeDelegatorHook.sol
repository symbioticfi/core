// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IFullRestakeDelegator} from "src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IFullRestakeDelegatorHook} from "src/interfaces/delegator/hook/IFullRestakeDelegatorHook.sol";

contract SimpleFullRestakeDelegatorHook is IFullRestakeDelegatorHook {
    uint256 counter;

    function onSlash(
        address network,
        address operator,
        uint256 slashedAmount,
        uint48 captureTimestamp
    ) external returns (bool, uint256, uint256) {
        ++counter;
        if (counter == 2) {
            return (true, IFullRestakeDelegator(msg.sender).networkLimit(network), 0);
        }
        return (false, 0, 0);
    }
}
