// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";

import {ERC4626Math} from "../../../src/contracts/vault/common/ERC4626Math.sol";

contract ERC4626MathHarness is ERC4626Math {
    function previewMint(uint256 shares, uint256 totalAssets, uint256 totalShares) external view returns (uint256) {
        return _previewMint(shares, totalAssets, totalShares);
    }
}

contract VaultCommonERC4626MathTest is Test {
    function test_PreviewMintRoundsUpWithVirtualBalances() public {
        ERC4626MathHarness harness = new ERC4626MathHarness();

        assertEq(harness.previewMint(3, 10, 5), 1);
    }
}
