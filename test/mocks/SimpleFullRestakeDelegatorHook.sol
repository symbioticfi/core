// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IFullRestakeDelegator} from "../../src/interfaces/delegator/IFullRestakeDelegator.sol";
import {IDelegatorHook} from "../../src/interfaces/delegator/IDelegatorHook.sol";

contract SimpleFullRestakeDelegatorHook is IDelegatorHook {
    uint256 counter1;
    uint256 counter2;
    uint256 counter3;

    function onSlash(bytes32 subnetwork, address operator, uint256, uint48, bytes calldata) external {
        ++counter1;
        ++counter2;
        ++counter3;
        if (counter1 == 2) {
            IFullRestakeDelegator(msg.sender).setOperatorNetworkLimit(subnetwork, operator, 0);
        }
    }
}
