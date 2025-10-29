// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./SymbioticCoreImports.sol";

import "./SymbioticInit.sol";
import {SymbioticCoreConstants} from "./SymbioticCoreConstants.sol";
import {SymbioticCoreInitBase} from "./base/SymbioticCoreInitBase.sol";
import {SymbioticCoreBindings} from "./SymbioticCoreBindings.sol";
import {Token} from "../mocks/Token.sol";
import {FeeOnTransferToken} from "../mocks/FeeOnTransferToken.sol";

import {IERC5267} from "@openzeppelin/contracts/interfaces/IERC5267.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract SymbioticCoreInit is SymbioticCoreInitBase, SymbioticInit, SymbioticCoreBindings {
    function setUp() public virtual override {
        SymbioticInit.setUp();

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
                _normalizeForToken_Symbiotic(SYMBIOTIC_CORE_TOKENS_TO_SET_TIMES_1e18, possibleTokens[i]),
                true
            ); // should cover most cases
        }

        return staker;
    }

    // ------------------------------------------------------------ BROADCAST HELPERS ------------------------------------------------------------ //

    function _stopBroadcastWhenCallerModeIsSingle(Vm.CallerMode callerMode) internal virtual override {
        if (callerMode == VmSafe.CallerMode.Prank) {
            vm.stopPrank();
        }
    }

    function _startBroadcastWhenCallerModeIsNotRecurrent(Vm.CallerMode callerMode, address deployer)
        internal
        virtual
        override
    {
        if (callerMode != VmSafe.CallerMode.RecurrentPrank) {
            vm.startPrank(deployer);
        }
    }

    function _stopBroadcastWhenCallerModeIsNotRecurrent(Vm.CallerMode callerMode) internal virtual override {
        if (callerMode != VmSafe.CallerMode.RecurrentPrank) {
            vm.stopPrank();
        }
    }

    function _startBroadcastWhenCallerModeIsRecurrent(Vm.CallerMode callerMode, address deployer)
        internal
        virtual
        override
    {
        if (callerMode == VmSafe.CallerMode.RecurrentPrank) {
            vm.startPrank(deployer);
        }
    }

    function _stopBroadcastWhenCallerModeIsSingleOrRecurrent(Vm.CallerMode callerMode) internal virtual override {
        if (callerMode == VmSafe.CallerMode.Prank || callerMode == VmSafe.CallerMode.RecurrentPrank) {
            vm.stopPrank();
        }
    }
}
