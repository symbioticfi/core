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
        selectors[5] = WithdrawalQueueClaimHandler.claimLimited.selector;
        selectors[6] = WithdrawalQueueClaimHandler.transferPosition.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_ClaimableMatchesFillPriceModel() public {
        handler.assertClaimableMatchesModel();
    }

    function invariant_ClaimTransfersMatchFillPriceModel() public {
        handler.assertActorBalancesMatchClaims();
    }
}
