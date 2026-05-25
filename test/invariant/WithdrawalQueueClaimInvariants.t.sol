// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {WithdrawalQueueClaimHandler} from "./handlers/WithdrawalQueueClaimHandler.sol";

contract WithdrawalQueueClaimInvariantsTest is Test {
    WithdrawalQueueClaimHandler public handler;

    function setUp() public {
        handler = new WithdrawalQueueClaimHandler();

        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = WithdrawalQueueClaimHandler.request.selector;
        selectors[1] = WithdrawalQueueClaimHandler.increaseAssets.selector;
        selectors[2] = WithdrawalQueueClaimHandler.decreaseAssets.selector;
        selectors[3] = WithdrawalQueueClaimHandler.fill.selector;
        selectors[4] = WithdrawalQueueClaimHandler.claim.selector;
        selectors[5] = WithdrawalQueueClaimHandler.claimLimited.selector;
        selectors[6] = WithdrawalQueueClaimHandler.transferPosition.selector;
        selectors[7] = WithdrawalQueueClaimHandler.reduceLiquidity.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_ClaimableMatchesFillPriceModel() public {
        handler.assertClaimableMatchesModel();
    }

    function invariant_ClaimTransfersMatchFillPriceModel() public {
        handler.assertActorBalancesMatchClaims();
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
}
