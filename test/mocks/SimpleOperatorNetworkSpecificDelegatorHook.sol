// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOperatorNetworkSpecificDelegator} from "../../src/interfaces/delegator/IOperatorNetworkSpecificDelegator.sol";
import {IDelegatorHook} from "../../src/interfaces/delegator/IDelegatorHook.sol";

contract SimpleOperatorNetworkSpecificDelegatorHook is IDelegatorHook {
    uint256 public counter1;
    uint256 public counter2;
    uint256 public counter3;

    function onSlash(bytes32 subnetwork, address, uint256, uint48, bytes calldata) external {
        ++counter1;
        ++counter2;
        ++counter3;
    }
}
