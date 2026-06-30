// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MerklClaimer} from "../../../src/contracts/adapters/common/MerklClaimer.sol";

contract MerklClaimerTest is Test {
    function test_ClaimForwardsMerklDistributorClaimCalldataForClaimer() public {
        MerklDistributorMock distributor = new MerklDistributorMock();
        MerklClaimerHarness claimer = new MerklClaimerHarness(address(distributor));

        address user = makeAddr("user");
        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("token");
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 123;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = keccak256("proof");

        vm.prank(user);
        claimer.claim(tokens, amounts, proofs);

        assertEq(distributor.calls(), 1);
        assertEq(distributor.lastUser(), address(claimer));
        assertEq(distributor.lastToken(), tokens[0]);
        assertEq(distributor.lastAmount(), amounts[0]);
        assertEq(distributor.lastProof(), proofs[0][0]);
    }
}

contract MerklClaimerHarness is MerklClaimer {
    constructor(address distributor) MerklClaimer(distributor) {}
}

contract MerklDistributorMock {
    uint256 public calls;
    address public lastUser;
    address public lastToken;
    uint256 public lastAmount;
    bytes32 public lastProof;

    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external {
        ++calls;
        lastUser = users[0];
        lastToken = tokens[0];
        lastAmount = amounts[0];
        lastProof = proofs[0][0];
    }
}
