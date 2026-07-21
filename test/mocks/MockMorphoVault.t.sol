// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import {MockMorphoVault} from "./MockMorphoVault.sol";

contract MockMorphoVaultToken is ERC20 {
    constructor() ERC20("Tok", "TOK") {
        _mint(msg.sender, 1_000_000e18);
    }
}

/// @dev Reference vault: plain OpenZeppelin ERC-4626 over the same asset.
contract ReferenceVault is ERC4626 {
    constructor(IERC20 asset_) ERC20("Ref", "REF") ERC4626(asset_) {}
}

/// @notice Guards that MockMorphoVault matches canonical ERC-4626 accounting — regression cover for
///         the previous hand-rolled share math (1:1 reset on donation, withdraw rounding down).
contract MockMorphoVaultTest is Test {
    MockMorphoVaultToken internal tok;
    MockMorphoVault internal mock;
    ReferenceVault internal ref;
    address internal user = makeAddr("user");

    function setUp() public {
        tok = new MockMorphoVaultToken();
        mock = new MockMorphoVault(address(tok));
        ref = new ReferenceVault(IERC20(address(tok)));
        tok.transfer(user, 10_000e18);
        vm.startPrank(user);
        tok.approve(address(mock), type(uint256).max);
        tok.approve(address(ref), type(uint256).max);
        vm.stopPrank();
    }

    /// A first deposit into a vault pre-seeded with idle assets must NOT mint 1:1 (inflation guard).
    function test_FirstDepositDoesNotCaptureDonatedAssets() public {
        vm.prank(user);
        mock.donateYield(1000e18); // idle assets, zero shares

        vm.prank(user);
        uint256 shares = mock.deposit(100e18, user);

        // OZ virtual-offset math prices the 100e18 deposit against the 1000e18 already idle, so the
        // depositor cannot redeem more than they put in (the old mock returned ~1100e18).
        assertEq(shares, mock.previewDeposit(100e18), "shares match ERC-4626 preview");
        assertLe(mock.previewRedeem(shares), 100e18, "depositor cannot extract donated assets");
    }

    /// A value-bearing withdrawal must burn > 0 shares and round up, exactly like OZ ERC-4626.
    function test_WithdrawRoundsSharesUpLikeReference() public {
        vm.startPrank(user);
        mock.deposit(1, user);
        mock.donateYield(9); // 1 share backed by 10 assets
        ref.deposit(1, user);
        tok.transfer(address(ref), 9);
        vm.stopPrank();

        vm.prank(user);
        uint256 burned = mock.withdraw(5, user, user);

        assertEq(burned, ref.previewWithdraw(5), "withdraw burns same shares as reference");
        assertGt(burned, 0, "value-bearing withdraw burns > 0 shares");
    }

    /// Deposit/withdraw share counts track the reference vault across a yield-bearing round trip.
    function test_MatchesReferenceAcrossRoundTrip() public {
        vm.startPrank(user);
        uint256 mockShares = mock.deposit(1000e18, user);
        uint256 refShares = ref.deposit(1000e18, user);
        assertEq(mockShares, refShares, "deposit shares match");

        mock.donateYield(250e18);
        tok.transfer(address(ref), 250e18);
        assertEq(mock.previewRedeem(mockShares), ref.previewRedeem(refShares), "valuation matches");

        assertEq(mock.maxWithdraw(user), ref.maxWithdraw(user), "maxWithdraw matches");
        vm.stopPrank();
    }
}
