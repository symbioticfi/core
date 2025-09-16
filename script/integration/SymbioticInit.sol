// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SymbioticUtils} from "../../test/integration/SymbioticUtils.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Script} from "forge-std/Script.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";

contract SymbioticInit is Script {
    using Math for uint256;
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------ GENERAL HELPERS ------------------------------------------------------------ //

    function _deal_Symbiotic(address token, address to, uint256 give) public virtual {
        (Vm.CallerMode callerMode,, address txOrigin) = vm.readCallers();
        if (callerMode == VmSafe.CallerMode.Broadcast) {
            vm.stopBroadcast();
        }
        if (callerMode != VmSafe.CallerMode.RecurrentBroadcast) {
            vm.startBroadcast(txOrigin);
        }
        IERC20(token).safeTransfer(to, give);
        if (callerMode != VmSafe.CallerMode.RecurrentBroadcast) {
            vm.stopBroadcast();
        }
    }

    function _deal_Symbiotic(address to, uint256 give) public virtual {
        (Vm.CallerMode callerMode,, address txOrigin) = vm.readCallers();
        if (callerMode == VmSafe.CallerMode.Broadcast) {
            vm.stopBroadcast();
        }
        if (callerMode != VmSafe.CallerMode.RecurrentBroadcast) {
            vm.startBroadcast(txOrigin);
        }
        to.call{value: give}("");
        if (callerMode != VmSafe.CallerMode.RecurrentBroadcast) {
            vm.stopBroadcast();
        }
    }
}
