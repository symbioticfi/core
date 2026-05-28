// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {VaultHandler} from "./handlers/VaultHandler.sol";

contract VaultInvariantsTest is Test {
    VaultHandler public handler;

    function setUp() public {
        handler = new VaultHandler();

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = VaultHandler.deposit.selector;
        selectors[1] = VaultHandler.withdraw.selector;
        selectors[2] = VaultHandler.redeem.selector;
        selectors[3] = VaultHandler.claim.selector;
        selectors[4] = VaultHandler.claimBatch.selector;
        selectors[5] = VaultHandler.slash.selector;
        selectors[6] = VaultHandler.setDepositControls.selector;
        selectors[7] = VaultHandler.setNetworkLimits.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_Totals() public {
        assert(handler.totalDeposited() >= handler.totalWithdrawn());
        assert(handler.totalWithdrawn() >= handler.totalClaimed());
        assert(handler.vaultBalance() + handler.totalClaimed() + handler.totalSlashed() == handler.totalDeposited());
    }

    function invariant_UserBalance() public {
        address[] memory depositors = handler.getDepositors();
        for (uint256 i = 0; i < depositors.length; i++) {
            address account = depositors[i];
            assert(handler.totalClaimedOf(account) <= handler.totalDepositOf(account));
        }
    }
}
