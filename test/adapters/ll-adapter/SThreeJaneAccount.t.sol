// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

import {ICoWSwapConverter} from "../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract SThreeJaneAccountTest is AccountsBase {
    function testSThreeJaneAccountCachesRedemptionTopology() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken usd3 = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockSThreeJaneSUSD3 tokenToRedeem = new MockSThreeJaneSUSD3(usd3, 1e6, 1 days, 2 days);
        SThreeJaneAccount account = _deploySThreeJane(tokenToRedeem, usdc, new MockOracle(1e18));

        assertEq(account.USD3(), address(usd3));
        assertEq(account.REDEMPTION_TOKEN(), address(usdc));
    }

    function testSThreeJaneAccountTotalAssetsUsesCachedRedemptionTopology() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken usd3 = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockSThreeJaneSUSD3 tokenToRedeem = new MockSThreeJaneSUSD3(usd3, 1e6, 1 days, 2 days);
        SThreeJaneAccount account = _deploySThreeJane(tokenToRedeem, usdc, new MockOracle(1e18));

        vm.mockCallRevert(address(tokenToRedeem), abi.encodeCall(IERC4626.asset, ()), bytes("sUSD3 asset lookup"));
        vm.mockCallRevert(address(usd3), abi.encodeCall(IERC4626.asset, ()), bytes("USD3 asset lookup"));

        assertEq(account.totalAssets(), 0);
    }

    function testSThreeJaneAccountSyncUsesCachedRedemptionTopology() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken usd3 = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockSThreeJaneSUSD3 tokenToRedeem = new MockSThreeJaneSUSD3(usd3, 1e6, 1 days, 2 days);
        SThreeJaneAccount account = _deploySThreeJane(tokenToRedeem, usdc, new MockOracle(1e18));

        vm.mockCallRevert(address(tokenToRedeem), abi.encodeCall(IERC4626.asset, ()), bytes("sUSD3 asset lookup"));
        vm.mockCallRevert(address(usd3), abi.encodeCall(IERC4626.asset, ()), bytes("USD3 asset lookup"));

        account.sync();
    }

    function testSThreeJaneAccountSkipsSUSD3MaxWithdrawForEmptyAccount() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken usd3 = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockSThreeJaneSUSD3 tokenToRedeem = new MockSThreeJaneSUSD3(usd3, 1e6, 1 days, 2 days);
        SThreeJaneAccount account = _deploySThreeJane(tokenToRedeem, usdc, new MockOracle(1e18));

        vm.mockCallRevert(
            address(tokenToRedeem),
            abi.encodeCall(IERC4626.maxWithdraw, (address(account))),
            bytes("maxWithdraw should be skipped")
        );

        account.sync();
    }

    function testSThreeJaneAccountTotalAssetsZeroForZeroBalancesWhenAssetIsUSD3() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken usd3 = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockSThreeJaneSUSD3 tokenToRedeem = new MockSThreeJaneSUSD3(usd3, 1e6, 1 days, 2 days);
        SThreeJaneAccount account = _deploySThreeJane(tokenToRedeem, usd3, new MockOracle(1e18));

        assertEq(account.totalAssets(), 0);
    }

    function testSThreeJaneAccountSkipsUSD3ConvertToAssetsForZeroUSD3Balance() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken usd3 = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockSThreeJaneSUSD3 tokenToRedeem = new MockSThreeJaneSUSD3(usd3, 1e6, 1 days, 2 days);
        SThreeJaneAccount account = _deploySThreeJane(tokenToRedeem, usdc, new MockOracle(1e18));

        vm.mockCallRevert(address(usd3), abi.encodeCall(IERC4626.convertToAssets, (0)), bytes("zero conversion"));

        assertEq(account.totalAssets(), 0);
    }

    function testSThreeJaneAccountConvertsUSDCDecimalsIntoVaultAssetUnits() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken usd3 = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockSThreeJaneSUSD3 tokenToRedeem = new MockSThreeJaneSUSD3(usd3, 1e6, 1 days, 2 days);
        MockERC20 vaultAsset = new MockERC20("Target Stablecoin", "TARGET", 18);
        SThreeJaneAccount account = _deploySThreeJane(tokenToRedeem, vaultAsset, new MockOracle(1e18));

        assertEq(account.totalAssets(), 0);

        usdc.mint(address(account), 1000e6);

        assertEq(account.totalAssets(), 1000e18);
    }

    function testSThreeJaneAccountRedeemsThroughUSD3ToUSDCAndValuesUSDC() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken usd3 = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockSThreeJaneSUSD3 tokenToRedeem = new MockSThreeJaneSUSD3(usd3, 1e6, 1 days, 2 days);
        MockERC20 vaultAsset = new MockERC20("Target Stablecoin", "TARGET", 18);
        SThreeJaneAccount account = _deploySThreeJane(tokenToRedeem, vaultAsset, new MockOracle(1e18));

        tokenToRedeem.mint(address(account), 1000e6);
        account.sync();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(usd3.balanceOf(address(account)), 0);
        assertEq(usdc.balanceOf(address(account)), 1000e6);
        assertEq(vaultAsset.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 1000e18);
    }

    function testSThreeJaneAccountAlwaysRedeemsUSD3ToUSDC() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken usd3 = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1.25e6);
        MockSThreeJaneSUSD3 tokenToRedeem = new MockSThreeJaneSUSD3(usd3, 1e6, 1 days, 2 days);
        SThreeJaneAccount account = _deploySThreeJane(tokenToRedeem, usd3, new MockOracle(1e18));

        tokenToRedeem.mint(address(account), 1000e6);
        account.sync();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(usd3.balanceOf(address(account)), 0);
        assertEq(usdc.balanceOf(address(account)), 1250e6);
        assertEq(account.totalAssets(), 1250e6);
    }

    function testSThreeJaneAccountValuesHeldSUSD3ThroughStablecoinOracle() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken usd3 = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1.2e6);
        MockSThreeJaneSUSD3 tokenToRedeem = new MockSThreeJaneSUSD3(usd3, 1.1e6, 1 days, 2 days);
        SThreeJaneAccount account = _deploySThreeJane(tokenToRedeem, usd3, new MockOracle(1.32e18));

        tokenToRedeem.mint(address(account), 1000e6);

        assertEq(account.totalAssets(), 1320e6);
    }

    function testSThreeJaneAccountRestartsExpiredCooldown() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken usd3 = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockSThreeJaneSUSD3 tokenToRedeem = new MockSThreeJaneSUSD3(usd3, 1e6, 1 days, 2 days);
        SThreeJaneAccount account = _deploySThreeJane(tokenToRedeem, usdc, new MockOracle(1e18));

        tokenToRedeem.mint(address(account), 1000e6);
        account.sync();
        (, uint48 windowEnd,) = tokenToRedeem.getCooldownStatus(address(account));

        vm.warp(uint256(windowEnd) + 1);
        account.sync();

        (uint48 cooldownEnd, uint48 newWindowEnd, uint256 shares) = tokenToRedeem.getCooldownStatus(address(account));
        assertEq(shares, 1000e6);
        assertGt(cooldownEnd, block.timestamp);
        assertGt(newWindowEnd, cooldownEnd);
    }

    function testSThreeJaneAccountWithdrawsImmediatelyWhenCooldownIsZero() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken usd3 = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockSThreeJaneSUSD3 tokenToRedeem = new MockSThreeJaneSUSD3(usd3, 1e6, 0, 2 days);
        SThreeJaneAccount account = _deploySThreeJane(tokenToRedeem, usdc, new MockOracle(1e18));

        tokenToRedeem.mint(address(account), 1000e6);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(usd3.balanceOf(address(account)), 0);
        assertEq(usdc.balanceOf(address(account)), 1000e6);
    }

    function testSThreeJaneAccountStartsNextCooldownAfterMaturedWithdrawal() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken usd3 = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockSThreeJaneSUSD3 tokenToRedeem = new MockSThreeJaneSUSD3(usd3, 1e6, 1 days, 2 days);
        SThreeJaneAccount account = _deploySThreeJane(tokenToRedeem, usdc, new MockOracle(1e18));

        tokenToRedeem.mint(address(account), 1000e6);
        account.sync();
        tokenToRedeem.mint(address(account), 500e6);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        account.sync();

        (uint48 cooldownEnd,, uint256 shares) = tokenToRedeem.getCooldownStatus(address(account));
        assertEq(shares, 500e6);
        assertGt(cooldownEnd, block.timestamp);
        assertEq(tokenToRedeem.balanceOf(address(account)), 500e6);
        assertEq(usdc.balanceOf(address(account)), 1000e6);
    }

    function testSThreeJaneAccountValuesPartialSUSD3AndUSD3Redemptions() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken usd3 = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockSThreeJaneSUSD3 tokenToRedeem = new MockSThreeJaneSUSD3(usd3, 1e6, 1 days, 2 days);
        MockERC20 vaultAsset = new MockERC20("Target Stablecoin", "TARGET", 18);
        SThreeJaneAccount account = _deploySThreeJane(tokenToRedeem, vaultAsset, new MockOracle(1e18));

        tokenToRedeem.setAvailableWithdrawLimit(600e6);
        usd3.setMaxWithdraw(250e6);
        tokenToRedeem.mint(address(account), 1000e6);
        account.sync();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 400e6);
        assertEq(usd3.balanceOf(address(account)), 350e6);
        assertEq(usdc.balanceOf(address(account)), 250e6);
        assertEq(account.totalAssets(), 1000e18);

        tokenToRedeem.setAvailableWithdrawLimit(0);
        usd3.setMaxWithdraw(type(uint256).max);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 400e6);
        assertEq(usd3.balanceOf(address(account)), 0);
        assertEq(usdc.balanceOf(address(account)), 600e6);
        assertEq(account.totalAssets(), 1000e18);
    }

    function testSThreeJaneAccountRedeemsUSD3WhenVaultAssetDiffers() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken usd3 = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockSThreeJaneSUSD3 tokenToRedeem = new MockSThreeJaneSUSD3(usd3, 1_001_000, 1 days, 2 days);
        MockOracle oracle = new MockOracle(1_001_000_000_000_000_000);
        SThreeJaneAccount account = _deploySThreeJane(tokenToRedeem, usdc, oracle);

        tokenToRedeem.mint(address(account), 1000e6);

        assertEq(account.totalAssets(), 1001e6);

        account.sync();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(usd3.balanceOf(address(account)), 0);
        assertEq(usdc.balanceOf(address(account)), 1001e6);
        assertEq(account.totalAssets(), 1001e6);
    }

    function testSThreeJaneAccountConvertsUSDCToVaultAssetThroughCoWSwap() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken usd3 = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockSThreeJaneSUSD3 tokenToRedeem = new MockSThreeJaneSUSD3(usd3, 1e6, 1 days, 2 days);
        MockERC20 vaultAsset = new MockERC20("Tether USD", "USDT", 6);
        SThreeJaneAccount account = _deploySThreeJane(tokenToRedeem, vaultAsset, new MockOracle(1e18));

        usdc.mint(address(account), 1000e6);
        account.convert(
            address(usdc),
            1000e6,
            address(vaultAsset),
            abi.encode(
                ICoWSwapConverter.OrderParams({
                    buyAmount: 999e6, validTo: uint32(block.timestamp + 10 minutes), appData: bytes32(0)
                })
            )
        );

        AccountsCoWSwapSettlementMock settlement = AccountsCoWSwapSettlementMock(cowSwapSettlement);
        assertTrue(settlement.lastSigned());
    }

    function testSUSD3AccountHardcodesCurrentSThreeJaneJuniorToken() public {
        address usd3 = makeAddr("USD3");
        address usdc = makeAddr("USDC");
        _mockDecimals(SUSD3_TOKEN_ADDRESS, 6);
        vm.mockCall(SUSD3_TOKEN_ADDRESS, abi.encodeCall(IERC4626.asset, ()), abi.encode(usd3));
        vm.mockCall(usd3, abi.encodeCall(IERC4626.asset, ()), abi.encode(usdc));

        MigratablesFactory factory = new MigratablesFactory(address(this));
        MockOracle oracle = new MockOracle(1e18);
        sUSD3_Account account = new sUSD3_Account(address(oracle), address(factory), cowSwapSettlement);

        assertEq(account.TOKEN_TO_REDEEM(), SUSD3_TOKEN_ADDRESS);
        assertEq(account.USD3(), usd3);
        assertEq(account.REDEMPTION_TOKEN(), usdc);
    }
}
