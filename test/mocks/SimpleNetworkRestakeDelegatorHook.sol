// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {INetworkRestakeDelegator} from "src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {INetworkRestakeDelegatorHook} from "src/interfaces/delegator/hook/INetworkRestakeDelegatorHook.sol";

contract SimpleNetworkRestakeDelegatorHook is INetworkRestakeDelegatorHook {
    uint256 counter;

    function onSlash(
        address network,
        address operator,
        uint256 slashedAmount,
        uint48 captureTimestamp
    ) external returns (bool, uint256, uint256) {
        ++counter;
        if (counter == 2) {
            return (true, INetworkRestakeDelegator(msg.sender).networkLimit(network), 0);
        }
        return (false, 0, 0);
    }
}
