// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";

import {IVaultV2} from "../../src/interfaces/vault/IVaultV2.sol";
import {VaultV2UncheckedMathHandler} from "./handlers/VaultV2UncheckedMathHandler.sol";

contract VaultV2UncheckedMathInvariantsTest is StdInvariant, Test {
    VaultV2UncheckedMathHandler internal handler;

    function setUp() public {
        handler = new VaultV2UncheckedMathHandler();

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = VaultV2UncheckedMathHandler.deposit.selector;
        selectors[1] = VaultV2UncheckedMathHandler.withdraw.selector;
        selectors[2] = VaultV2UncheckedMathHandler.claim.selector;
        selectors[3] = VaultV2UncheckedMathHandler.donate.selector;
        selectors[4] = VaultV2UncheckedMathHandler.slash.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_WithdrawalBucketAlwaysCoversActiveWithdrawals() public view {
        IVaultV2 vault = handler.vault();
        uint256 bucket = vault.withdrawalBucket();

        assertGe(vault.withdrawals(bucket), vault.activeWithdrawals());
    }

    function invariant_WithdrawalBucketAlwaysCoversActiveWithdrawalShares() public view {
        IVaultV2 vault = handler.vault();
        uint256 bucket = vault.withdrawalBucket();

        assertGe(vault.withdrawalShares(bucket), vault.activeWithdrawalShares());
    }

    function invariant_TrackedCollateralIsConserved() public view {
        assertEq(
            handler.vaultBalance() + handler.totalClaimed() + handler.totalSlashed(),
            handler.totalDeposited() + handler.totalDonated()
        );
    }

    function invariant_VaultRemainsLiquidForTrackedStake() public view {
        IVaultV2 vault = handler.vault();

        assertGe(handler.vaultBalance(), vault.activeStake() + vault.activeWithdrawals());
    }
}
