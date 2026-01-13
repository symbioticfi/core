// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import "./VaultV2.t.sol";

contract VaultV2TokenizedTest is VaultV2Test {
    function setUp() public override {
        super.setUp();
    }

    function test_Create2(
        address burner,
        uint48 epochDuration,
        bool depositWhitelist,
        bool isDepositLimit,
        uint256 depositLimit
    ) public override {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));
        super.test_Create2(burner, epochDuration, depositWhitelist, isDepositLimit, depositLimit);

        VaultV2 tokenizedVault = VaultV2(address(vault));
        assertEq(tokenizedVault.balanceOf(alice), 0);
        assertEq(tokenizedVault.totalSupply(), 0);
        assertEq(tokenizedVault.allowance(alice, alice), 0);
        assertEq(tokenizedVault.decimals(), collateral.decimals());
        assertEq(tokenizedVault.symbol(), "TEST");
        assertEq(tokenizedVault.name(), "Test");
    }

    function test_DepositTwice(uint256 amount1, uint256 amount2) public override {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        super.test_DepositTwice(amount1, amount2);
        uint256 shares1 = amount1 * 10 ** 0;
        uint256 shares2 = amount2 * (shares1 + 10 ** 0) / (amount1 + 1);

        VaultV2 tokenizedVault = VaultV2(address(vault));
        assertEq(tokenizedVault.balanceOf(alice), shares1 + shares2);
        assertEq(tokenizedVault.totalSupply(), shares1 + shares2);
    }

    function test_DepositBoth(uint256 amount1, uint256 amount2) public override {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        super.test_DepositBoth(amount1, amount2);
        uint256 shares1 = amount1 * 10 ** 0;
        uint256 shares2 = amount2 * (shares1 + 10 ** 0) / (amount1 + 1);

        VaultV2 tokenizedVault = VaultV2(address(vault));
        assertEq(tokenizedVault.balanceOf(alice), shares1);
        assertEq(tokenizedVault.balanceOf(bob), shares2);
        assertEq(tokenizedVault.totalSupply(), shares1 + shares2);
    }

    function test_WithdrawTwice(uint256 amount1, uint256 amount2, uint256 amount3) public override {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        super.test_WithdrawTwice(amount1, amount2, amount3);

        VaultV2 tokenizedVault = VaultV2(address(vault));
        assertEq(tokenizedVault.balanceOf(alice), amount1 - amount2 - amount3);
        assertEq(tokenizedVault.totalSupply(), amount1 - amount2 - amount3);
    }

    function test_Transfer(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint256 blockTimestamp = vm.getBlockTimestamp();
        blockTimestamp = blockTimestamp + 1_720_700_948;
        vm.warp(blockTimestamp);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        (, uint256 mintedShares) = _deposit(alice, amount1);

        VaultV2 tokenizedVault = VaultV2(address(vault));
        assertEq(tokenizedVault.balanceOf(alice), mintedShares);
        assertEq(tokenizedVault.totalSupply(), mintedShares);
        assertEq(vault.activeSharesOf(alice), mintedShares);
        assertEq(vault.activeShares(), mintedShares);

        if (amount2 > mintedShares) {
            vm.startPrank(alice);

            vm.expectRevert();
            tokenizedVault.transfer(bob, amount2);

            vm.stopPrank();
        } else {
            vm.startPrank(alice);

            tokenizedVault.transfer(bob, amount2);

            assertEq(tokenizedVault.balanceOf(alice), mintedShares - amount2);
            assertEq(tokenizedVault.totalSupply(), mintedShares);
            assertEq(vault.activeSharesOf(alice), mintedShares - amount2);
            assertEq(vault.activeShares(), mintedShares);

            assertEq(tokenizedVault.balanceOf(bob), amount2);
            assertEq(vault.activeSharesOf(bob), amount2);

            vm.stopPrank();

            vm.startPrank(bob);
            tokenizedVault.approve(alice, amount2);
            vm.stopPrank();

            assertEq(tokenizedVault.allowance(bob, alice), amount2);

            vm.startPrank(alice);
            tokenizedVault.transferFrom(bob, alice, amount2);
            vm.stopPrank();

            assertEq(tokenizedVault.balanceOf(alice), mintedShares);
            assertEq(tokenizedVault.totalSupply(), mintedShares);
            assertEq(vault.activeSharesOf(alice), mintedShares);
            assertEq(vault.activeShares(), mintedShares);
        }
    }

}
