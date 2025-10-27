// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../test/integration/SymbioticCoreImports.sol";

import "./SymbioticInit.sol";
import {SymbioticCoreConstants} from "../../test/integration/SymbioticCoreConstants.sol";
import {SymbioticCoreBindingsScript} from "./SymbioticCoreBindings.sol";
import {SymbioticCoreInitBase} from "../../test/integration/base/SymbioticCoreInitBase.sol";

import {Token} from "../../test/mocks/Token.sol";
import {FeeOnTransferToken} from "../../test/mocks/FeeOnTransferToken.sol";

import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {VmSafe} from "forge-std/Vm.sol";

contract SymbioticCoreInit is SymbioticCoreInitBase, SymbioticInit, SymbioticCoreBindingsScript {
    function run(uint256 seed) public virtual override {
        SymbioticInit.run(seed);

        SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT = true;

        _initCore_SymbioticCore(SYMBIOTIC_CORE_USE_EXISTING_DEPLOYMENT);
    }

    function _getStaker_SymbioticCore(address[] memory possibleTokens)
        internal
        virtual
        override
        returns (Vm.Wallet memory)
    {
        Vm.Wallet memory staker = _getAccount_Symbiotic();

        for (uint256 i; i < possibleTokens.length; ++i) {
            _deal_Symbiotic(
                possibleTokens[i],
                staker.addr,
                _normalizeForToken_Symbiotic(SYMBIOTIC_CORE_TOKENS_TO_SET_TIMES_1e18, possibleTokens[i])
            );
        }

        return staker;
    }

    // ------------------------------------------------------------ BROADCAST HELPERS ------------------------------------------------------------ //

    function _stopBroadcastWhenCallerModeIsSingle(Vm.CallerMode callerMode) internal virtual override {
        if (callerMode == VmSafe.CallerMode.Broadcast) {
            vm.stopBroadcast();
        }
    }

    function _startBroadcastWhenCallerModeIsNotRecurrent(Vm.CallerMode callerMode, address deployer)
        internal
        virtual
        override
    {
        if (callerMode != VmSafe.CallerMode.RecurrentBroadcast) {
            vm.startBroadcast(deployer);
        }
    }

    function _stopBroadcastWhenCallerModeIsNotRecurrent(Vm.CallerMode callerMode) internal virtual override {
        if (callerMode != VmSafe.CallerMode.RecurrentBroadcast) {
            vm.stopBroadcast();
        }
    }

    function _startBroadcastWhenCallerModeIsRecurrent(Vm.CallerMode callerMode, address deployer)
        internal
        virtual
        override
    {
        if (callerMode == VmSafe.CallerMode.RecurrentBroadcast) {
            vm.startBroadcast(deployer);
        }
    }

    function _stopBroadcastWhenCallerModeIsSingleOrRecurrent(Vm.CallerMode callerMode) internal virtual override {
        if (callerMode == VmSafe.CallerMode.Broadcast || callerMode == VmSafe.CallerMode.RecurrentBroadcast) {
            vm.stopBroadcast();
        }
    }
}
