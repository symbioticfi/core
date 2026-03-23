// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC4626Math} from "../../src/contracts/libraries/ERC4626Math.sol";

contract ERC4626MathTest is Test {
    function test_previewFunctionsUseExpectedRounding() public pure {
        assertEq(ERC4626Math.previewDeposit(1, 10, 6), 1);
        assertEq(ERC4626Math.previewWithdraw(1, 10, 6), 2);
        assertEq(ERC4626Math.previewRedeem(3, 6, 10), 1);
        assertEq(ERC4626Math.previewMint(3, 6, 10), 2);
    }

    function test_previewFunctionsBootstrapWithVirtualBalances() public pure {
        assertEq(ERC4626Math.previewDeposit(7, 0, 0), 7);
        assertEq(ERC4626Math.previewMint(7, 0, 0), 7);
        assertEq(ERC4626Math.previewWithdraw(7, 0, 0), 7);
        assertEq(ERC4626Math.previewRedeem(7, 0, 0), 7);
    }
}
