// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IFullRestakeDelegator} from "src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IDelegatorHook} from "src/interfaces/delegator/IDelegatorHook.sol";

contract SimpleFullRestakeDelegatorHook is IDelegatorHook {
    uint256 counter;

    function onSlash(address network, address operator, uint256, uint48) external {
        ++counter;
        if (counter == 2) {
            IFullRestakeDelegator(msg.sender).setOperatorNetworkLimit(network, operator, 0);
        }
    }
}
