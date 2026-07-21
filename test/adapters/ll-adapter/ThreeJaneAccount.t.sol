// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

import {ICoWSwapConverter} from "../../../src/interfaces/adapters/common/ICoWSwapConverter.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract ThreeJaneAccountTest is AccountsBase {
    function testThreeJaneAccountCachesRedemptionTopology() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken tokenToRedeem = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        ThreeJaneAccount account = _deployThreeJane(tokenToRedeem, usdc, new MockOracle(1e18));

        assertEq(account.REDEMPTION_TOKEN(), address(usdc));
    }

    function testThreeJaneAccountTotalAssetsUsesCachedRedemptionTopology() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken tokenToRedeem = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        ThreeJaneAccount account = _deployThreeJane(tokenToRedeem, usdc, new MockOracle(1e18));

        vm.mockCallRevert(address(tokenToRedeem), abi.encodeCall(IERC4626.asset, ()), bytes("USD3 asset lookup"));

        assertEq(account.totalAssets(), 0);
    }

    function testThreeJaneAccountSyncUsesCachedRedemptionTopology() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken tokenToRedeem = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        ThreeJaneAccount account = _deployThreeJane(tokenToRedeem, usdc, new MockOracle(1e18));

        vm.mockCallRevert(address(tokenToRedeem), abi.encodeCall(IERC4626.asset, ()), bytes("USD3 asset lookup"));

        account.sync();
    }

    function testThreeJaneAccountSkipsUSD3MaxWithdrawForEmptyAccount() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken tokenToRedeem = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        ThreeJaneAccount account = _deployThreeJane(tokenToRedeem, usdc, new MockOracle(1e18));

        vm.mockCallRevert(
            address(tokenToRedeem),
            abi.encodeCall(IERC4626.maxWithdraw, (address(account))),
            bytes("maxWithdraw should be skipped")
        );

        account.sync();
    }

    function testThreeJaneAccountSkipsUSDCDecimalsForZeroRedemptionTokenBalance() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken tokenToRedeem = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockERC20 vaultAsset = new MockERC20("Target Stablecoin", "TARGET", 18);
        ThreeJaneAccount account = _deployThreeJane(tokenToRedeem, vaultAsset, new MockOracle(1e18));

        vm.mockCallRevert(
            address(usdc), abi.encodeCall(IERC20Metadata.decimals, ()), bytes("decimals should be skipped")
        );

        assertEq(account.totalAssets(), 0);
    }

    function testThreeJaneAccountSkipsWithdrawWhenLiquidityIsExhausted() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken tokenToRedeem = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockERC20 vaultAsset = new MockERC20("Target Stablecoin", "TARGET", 18);
        ThreeJaneAccount account = _deployThreeJane(tokenToRedeem, vaultAsset, new MockOracle(1e18));

        tokenToRedeem.setMaxWithdraw(0);
        tokenToRedeem.mint(address(account), 1000e6);
        vm.mockCallRevert(
            address(tokenToRedeem),
            abi.encodeWithSelector(IERC4626.withdraw.selector),
            bytes("withdraw should be skipped")
        );

        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 1000e6);
        assertEq(usdc.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 1000e18);
    }

    function testThreeJaneAccountRedeemsUSD3ToUSDCAndValuesUSDC() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken tokenToRedeem = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockERC20 vaultAsset = new MockERC20("Target Stablecoin", "TARGET", 18);
        ThreeJaneAccount account = _deployThreeJane(tokenToRedeem, vaultAsset, new MockOracle(1e18));

        tokenToRedeem.mint(address(account), 1000e6);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(usdc.balanceOf(address(account)), 1000e6);
        assertEq(vaultAsset.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 1000e18);
    }

    function testThreeJaneAccountAlwaysRedeemsUSD3ToUSDC() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken tokenToRedeem = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1.25e6);
        ThreeJaneAccount account = _deployThreeJane(tokenToRedeem, usdc, new MockOracle(1.25e18));

        tokenToRedeem.mint(address(account), 1000e6);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(usdc.balanceOf(address(account)), 1250e6);
        assertEq(account.totalAssets(), 1250e6);
    }

    function testThreeJaneAccountValuesHeldUSD3ThroughStablecoinOracle() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken tokenToRedeem = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1.2e6);
        ThreeJaneAccount account = _deployThreeJane(tokenToRedeem, usdc, new MockOracle(1.2e18));

        tokenToRedeem.mint(address(account), 1000e6);

        assertEq(account.totalAssets(), 1200e6);
    }

    function testThreeJaneAccountValuesPartialUSD3Redemptions() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken tokenToRedeem = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockERC20 vaultAsset = new MockERC20("Target Stablecoin", "TARGET", 18);
        ThreeJaneAccount account = _deployThreeJane(tokenToRedeem, vaultAsset, new MockOracle(1e18));

        tokenToRedeem.setMaxWithdraw(600e6);
        tokenToRedeem.mint(address(account), 1000e6);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 400e6);
        assertEq(usdc.balanceOf(address(account)), 600e6);
        assertEq(account.totalAssets(), 1000e18);

        tokenToRedeem.setMaxWithdraw(type(uint256).max);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(usdc.balanceOf(address(account)), 1000e6);
        assertEq(account.totalAssets(), 1000e18);
    }

    function testThreeJaneAccountValuesUSD3ConsistentlyBeforeAndAfterSync() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken tokenToRedeem = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1_001_000);
        MockOracle oracle = new MockOracle(1_001_000_000_000_000_000);
        ThreeJaneAccount account = _deployThreeJane(tokenToRedeem, usdc, oracle);

        tokenToRedeem.mint(address(account), 1000e6);

        assertEq(account.totalAssets(), 1001e6);

        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(usdc.balanceOf(address(account)), 1001e6);
        assertEq(account.totalAssets(), 1001e6);
    }

    function testThreeJaneAccountConvertsUSDCToVaultAssetThroughCoWSwap() public {
        MockERC20 usdc = new MockERC20("USD Coin", "USDC", 6);
        MockERC4626RedeemToken tokenToRedeem = new MockERC4626RedeemToken(usdc, "3Jane USD3", "USD3", 6, 1e6);
        MockERC20 vaultAsset = new MockERC20("Tether USD", "USDT", 6);
        ThreeJaneAccount account = _deployThreeJane(tokenToRedeem, vaultAsset, new MockOracle(1e18));

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

    function testUSD3AccountHardcodesCurrentThreeJaneSeniorToken() public {
        address usdc = makeAddr("USDC");
        _mockDecimals(USD3_TOKEN_ADDRESS, 6);
        vm.mockCall(USD3_TOKEN_ADDRESS, abi.encodeCall(IERC4626.asset, ()), abi.encode(usdc));

        MigratablesFactory factory = new MigratablesFactory(address(this));
        MockOracle oracle = new MockOracle(1e18);
        USD3_Account account = new USD3_Account(address(oracle), address(factory), cowSwapSettlement);

        assertEq(account.TOKEN_TO_REDEEM(), USD3_TOKEN_ADDRESS);
        assertEq(account.REDEMPTION_TOKEN(), usdc);
    }
}
