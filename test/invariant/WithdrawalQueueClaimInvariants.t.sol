// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {WithdrawalQueueClaimHandler} from "./handlers/WithdrawalQueueClaimHandler.sol";

contract WithdrawalQueueClaimInvariantsTest is Test {
    WithdrawalQueueClaimHandler public handler;

    function setUp() public {
        handler = new WithdrawalQueueClaimHandler();

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = WithdrawalQueueClaimHandler.request.selector;
        selectors[1] = WithdrawalQueueClaimHandler.increaseAssets.selector;
        selectors[2] = WithdrawalQueueClaimHandler.decreaseAssets.selector;
        selectors[3] = WithdrawalQueueClaimHandler.fill.selector;
        selectors[4] = WithdrawalQueueClaimHandler.claim.selector;
        selectors[5] = WithdrawalQueueClaimHandler.transferPosition.selector;
        selectors[6] = WithdrawalQueueClaimHandler.reduceLiquidity.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_ClaimableMatchesFillCurveModel() public {
        handler.assertClaimableMatchesModel();
    }

    function invariant_ClaimTransfersMatchFillCurveModel() public {
        handler.assertActorBalancesMatchClaims();
    }

    function invariant_ShareConservationAndRequestLedgerHold() public view {
        handler.assertShareConservationAndRequestLedger();
    }

    function invariant_ClaimableAssetsAreBackedByQueueBalance() public view {
        handler.assertClaimableAssetsBackedByQueueBalance();
    }

    function invariant_CheckpointsMatchFillModel() public view {
        handler.assertCheckpointsMatchFillModel();
    }

    function test_HandlerKeepsModelAlignedWhenFillRedeemsNoShares() public {
        handler.request(0, 6);
        handler.decreaseAssets(type(uint256).max);

        handler.fill();

        handler.assertClaimableMatchesModel();
        handler.assertActorBalancesMatchClaims();
    }

    function test_HandlerKeepsModelAlignedWhenFillIsLiquidityLimited() public {
        handler.request(0, 100);
        handler.reduceLiquidity(40);

        handler.fill();

        assertEq(handler.modelTotalFilled(), 60);
        handler.assertClaimableMatchesModel();
        handler.assertActorBalancesMatchClaims();
    }

    function test_HandlerKeepsModelAlignedAcrossRoundingDustFill() public {
        handler.request(128, 1e9);
        handler.reduceLiquidity(14_829_656_329_139_369_085);
        handler.decreaseAssets(1317);

        handler.fill();
        handler.fill();

        handler.assertClaimableMatchesModel();
        handler.assertActorBalancesMatchClaims();
    }

    function test_PermissionlessClaimPaysCurrentWithdrawalNftOwner() public {
        address alice = address(0xA11CE);
        address bob = address(0xB0B);

        handler.request(0, 100);
        handler.transferPosition(0, 1);
        handler.fill();

        uint256 aliceBalanceBefore = handler.collateral().balanceOf(alice);
        uint256 bobBalanceBefore = handler.collateral().balanceOf(bob);
        uint256 callerBalanceBefore = handler.collateral().balanceOf(address(this));

        handler.claim(0);

        assertEq(handler.collateral().balanceOf(alice), aliceBalanceBefore);
        assertGt(handler.collateral().balanceOf(bob), bobBalanceBefore);
        assertEq(handler.collateral().balanceOf(address(this)), callerBalanceBefore);
    }
}
