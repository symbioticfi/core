// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./base/ClaimMerklBase.s.sol";

contract ClaimMerklScript is ClaimMerklBaseScript {
    address constant ADAPTER = 0x0000000000000000000000000000000000000000;
    address constant TOKEN = 0x0000000000000000000000000000000000000000;
    uint256 constant AMOUNT = 0;

    function run() public {
        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        bytes32[][] memory proofs = new bytes32[][](1);
        tokens[0] = TOKEN;
        amounts[0] = AMOUNT;
        proofs[0] = new bytes32[](0);
        runBase(ADAPTER, tokens, amounts, proofs);
    }
}
