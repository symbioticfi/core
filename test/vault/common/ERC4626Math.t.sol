// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {ERC4626Math} from "../../../src/contracts/libraries/ERC4626Math.sol";

contract VaultCommonERC4626MathTest is Test {
    function test_PreviewMintRoundsUpWithVirtualBalances() public {
        assertEq(ERC4626Math.previewMint(3, 10, 5), 6);
    }
}
