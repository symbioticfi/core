// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {MerklRedistributor} from "../../../src/contracts/adapters/common/MerklRedistributor.sol";

contract MerklRedistributorTest is Test {
    function test_ClaimForwardsMerklDistributorClaimCalldataForRedistributor() public {
        MerklDistributorMock distributor = new MerklDistributorMock();
        MerklRedistributorHarness redistributor = new MerklRedistributorHarness(address(distributor));

        address user = makeAddr("user");
        address[] memory tokens = new address[](1);
        tokens[0] = makeAddr("token");
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 123;
        bytes32[][] memory proofs = new bytes32[][](1);
        proofs[0] = new bytes32[](1);
        proofs[0][0] = keccak256("proof");

        vm.prank(user);
        redistributor.claim(tokens, amounts, proofs);

        assertEq(distributor.calls(), 1);
        assertEq(distributor.lastUser(), address(redistributor));
        assertEq(distributor.lastToken(), tokens[0]);
        assertEq(distributor.lastAmount(), amounts[0]);
        assertEq(distributor.lastProof(), proofs[0][0]);
    }
}

contract MerklRedistributorHarness is MerklRedistributor {
    constructor(address distributor) MerklRedistributor(distributor) {}
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
