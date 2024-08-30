// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {INetworkRestakeDelegator} from "../../src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IDelegatorHook} from "../../src/interfaces/delegator/IDelegatorHook.sol";

contract SimpleNetworkRestakeDelegatorHook is IDelegatorHook {
    uint256 counter;

    function onSlash(bytes32 subnetwork, address operator, uint256, uint48, bytes calldata) external {
        ++counter;
        if (counter == 2) {
            INetworkRestakeDelegator(msg.sender).setOperatorNetworkShares(subnetwork, operator, 0);
        }
    }
}
