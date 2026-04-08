// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {VaultV2SolvencyHandler} from "./handlers/VaultV2SolvencyHandler.sol";

contract VaultV2SolvencyInvariantsTest is StdInvariant, Test {
    VaultV2SolvencyHandler internal handler;

    function setUp() public {
        handler = new VaultV2SolvencyHandler();

        bytes4[] memory selectors = new bytes4[](13);
        selectors[0] = VaultV2SolvencyHandler.deposit.selector;
        selectors[1] = VaultV2SolvencyHandler.withdraw.selector;
        selectors[2] = VaultV2SolvencyHandler.redeem.selector;
        selectors[3] = VaultV2SolvencyHandler.claim.selector;
        selectors[4] = VaultV2SolvencyHandler.instantWithdraw.selector;
        selectors[5] = VaultV2SolvencyHandler.donate.selector;
        selectors[6] = VaultV2SolvencyHandler.addAdapterYield.selector;
        selectors[7] = VaultV2SolvencyHandler.skim.selector;
        selectors[8] = VaultV2SolvencyHandler.allocate.selector;
        selectors[9] = VaultV2SolvencyHandler.deallocate.selector;
        selectors[10] = VaultV2SolvencyHandler.slash.selector;
        selectors[11] = VaultV2SolvencyHandler.setAdapterFailure.selector;
        selectors[12] = VaultV2SolvencyHandler.syncOwedSlash.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_TrackedInflowsMatchTrackedOutflowsAndHoldings() public view {
        assertEq(handler.systemHoldings() + handler.trackedOutflows(), handler.trackedInflows());
    }

    function invariant_SystemHoldingsAlwaysCoverLiveStake() public view {
        assertGe(handler.systemHoldings(), handler.vault().totalStake());
    }

    function invariant_AdapterBalanceAlwaysCoversAdapterAccounting() public view {
        assertEq(handler.vault().adaptersAllocated(), handler.vault().adapterAllocated(address(handler.adapter())));
        assertGe(handler.adapterBalance(), handler.vault().adapterAllocated(address(handler.adapter())));
    }

    function invariant_NoAdaptersSlashableStakeAlwaysLiquid() public view {
        assertLe(handler.noAdaptersSlashableStake(), handler.vaultBalance());
    }

    function invariant_MaxSyncableOwedSlashStillKeepsNoAdaptersLiquid() public view {
        assertGe(handler.vaultBalance(), handler.noAdaptersSlashableStake() + handler.syncableOwedSlashCapacity());
    }

    function invariant_SystemHoldingsAlwaysCoverLiveStakeAndClaimableBacking() public view {
        assertGe(handler.systemHoldings(), handler.vault().totalStake() + handler.claimableBacking());
    }

    function invariant_LastSuccessfulClaimPreservesHigherPriorityReserve() public view {
        if (!handler.sawSuccessfulClaim()) {
            return;
        }

        assertGe(handler.lastClaimPostClaimableBacking(), handler.lastClaimPostUnclaimableReserve());
        assertGe(handler.lastClaimPostVaultBalance(), handler.lastClaimPostNoAdaptersSlashableStake());
    }

    function invariant_LastSuccessfulSyncPreservesNoAdaptersLiquidity() public view {
        if (!handler.sawSuccessfulSync()) {
            return;
        }

        assertEq(handler.lastSyncPostTotalOwed(), handler.lastSyncPreTotalOwed() - handler.lastSyncedAmount());
        assertGe(handler.lastSyncPostVaultBalance(), handler.lastSyncPostNoAdaptersSlashableStake());
    }
}
