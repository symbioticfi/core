// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

import {IMakinaMachine} from "../../../src/interfaces/adapters/ll-adapter/makina/IMakinaMachine.sol";
import {IMakinaRedeemer} from "../../../src/interfaces/adapters/ll-adapter/makina/IMakinaRedeemer.sol";
import {IOracle} from "../../../src/interfaces/adapters/ll-adapter/IOracle.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MakinaAccountTest is AccountsBase {
    function testMakinaAccountRequestsAndClaimsRedeemerReceipt() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 tokenToRedeem = new MockERC20("Dialectic USD", "DUSD", 18);
        MockMakinaMachine machine = new MockMakinaMachine(tokenToRedeem, asset, 1_028_683);
        MockMakinaRedeemer redeemer = new MockMakinaRedeemer(machine);
        MockOracle oracle = new MockOracle(1_028_683e12);
        MakinaAccount account = _deployMakina(tokenToRedeem, asset, redeemer, oracle, 0);

        tokenToRedeem.mint(address(account), 3 ether);

        assertEq(account.totalAssets(), 3_086_049);

        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.balanceOf(address(redeemer)), 3 ether);
        assertEq(redeemer.ownerOf(1), address(account));
        assertEq(account.totalAssets(), 3_086_049);

        redeemer.finalize(1, 3_000_000);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 3_000_000);
        assertEq(account.totalAssets(), 3_000_000);
    }

    function testMakinaAccountPermissionlessSyncRespectsCooldown() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 tokenToRedeem = new MockERC20("Dialectic USD", "DUSD", 18);
        MockMakinaMachine machine = new MockMakinaMachine(tokenToRedeem, asset, 1e6);
        MockMakinaRedeemer redeemer = new MockMakinaRedeemer(machine);
        MockOracle oracle = new MockOracle(1e18);
        MakinaAccount account = _deployMakina(tokenToRedeem, asset, redeemer, oracle, 1 days);
        address keeper = makeAddr("keeper");

        tokenToRedeem.mint(address(account), 1 ether);
        vm.prank(keeper);
        account.sync();

        tokenToRedeem.mint(address(account), 1 ether);
        vm.prank(keeper);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 1 ether);
        assertEq(redeemer.getShares(1), 1 ether);
        assertEq(account.totalAssets(), 2e6);

        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.prank(keeper);
        account.sync();

        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(redeemer.getShares(2), 1 ether);
        assertEq(account.totalAssets(), 2e6);
    }

    function testMakinaPendingRequestValueIsCappedAtRequestTimeQuote() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 tokenToRedeem = new MockERC20("Dialectic USD", "DUSD", 18);
        MockMakinaMachine machine = new MockMakinaMachine(tokenToRedeem, asset, 1e6);
        MockMakinaRedeemer redeemer = new MockMakinaRedeemer(machine);
        MockOracle oracle = new MockOracle(1e18);
        MakinaAccount account = _deployMakina(tokenToRedeem, asset, redeemer, oracle, 0);

        tokenToRedeem.mint(address(account), 2 ether);
        account.sync();

        assertEq(account.requestQuotes(1), 2e6);
        assertEq(account.totalAssets(), 2e6);

        // 1) price rises 1.5x: pending value stays capped at the request-time quote
        oracle.setPrice(1.5e18);
        assertEq(account.totalAssets(), 2e6);

        // 2) price falls to 0.5x: pending value follows the live (lower) value
        oracle.setPrice(0.5e18);
        assertEq(account.totalAssets(), 1e6);

        // finalized claimable amount is fixed by the redeemer and is not capped by the quote
        redeemer.finalize(1, 2_500_000);
        assertEq(account.totalAssets(), 2_500_000);

        account.sync();

        assertEq(account.requestQuotes(1), 0);
        assertEq(asset.balanceOf(address(account)), 2_500_000);
        assertEq(account.totalAssets(), 2_500_000);
    }

    function testMakinaAccountDoesNotExposeTotalRequests() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 tokenToRedeem = new MockERC20("Dialectic USD", "DUSD", 18);
        MockMakinaMachine machine = new MockMakinaMachine(tokenToRedeem, asset, 1e6);
        MockMakinaRedeemer redeemer = new MockMakinaRedeemer(machine);
        MockOracle oracle = new MockOracle(1e18);
        MakinaAccount account = _deployMakina(tokenToRedeem, asset, redeemer, oracle, 0);

        (bool success,) = address(account).staticcall(abi.encodeCall(ILegacyTotalRequests.totalRequests, ()));
        assertFalse(success);
    }

    function testMakinaOracleUsesSharePrice() public {
        MockMakinaSharePriceOracle source = new MockMakinaSharePriceOracle(8, 102_868_300);
        MockMakinaAccountingClock machine = new MockMakinaAccountingClock();
        machine.setLastGlobalAccountingTime(block.timestamp);
        MakinaOracle oracle = new MakinaOracle(1, type(uint256).max, address(source), address(machine), 48 hours);

        assertEq(oracle.SHARE_PRICE_ORACLE(), address(source));
        assertEq(oracle.MACHINE(), address(machine));
        assertEq(oracle.STALENESS_DURATION(), 48 hours);
        assertEq(oracle.getPrice(), 1_028_683e12);
    }

    function testMakinaOracleRejectsStaleAccounting() public {
        vm.warp(10 days);
        MockMakinaSharePriceOracle source = new MockMakinaSharePriceOracle(18, 1.03e18);
        MockMakinaAccountingClock machine = new MockMakinaAccountingClock();
        machine.setLastGlobalAccountingTime(block.timestamp - 48 hours - 1);
        MakinaOracle oracle = new MakinaOracle(0.5e18, 2.5e18, address(source), address(machine), 48 hours);

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testMakinaOracleRejectsFutureAccountingTimestamp() public {
        vm.warp(10 days);
        MockMakinaSharePriceOracle source = new MockMakinaSharePriceOracle(18, 1.03e18);
        MockMakinaAccountingClock machine = new MockMakinaAccountingClock();
        machine.setLastGlobalAccountingTime(block.timestamp + 1);
        MakinaOracle oracle = new MakinaOracle(0.5e18, 2.5e18, address(source), address(machine), 48 hours);

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }

    function testMakinaOracleRejectsZeroSharePrice() public {
        _assertMakinaOracleRejectsPrice(0);
    }

    function testMakinaOracleRejectsSharePriceBelowBound() public {
        _assertMakinaOracleRejectsPrice(0.5e18 - 1);
    }

    function testMakinaOracleRejectsSharePriceAboveBound() public {
        _assertMakinaOracleRejectsPrice(2.5e18 + 1);
    }

    function testDUSDAccountHardcodesMainnetTokenRedeemerAndOracle() public {
        vm.mockCall(DUSD_TOKEN_ADDRESS, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(uint8(18)));
        vm.mockCall(
            DUSD_REDEEMER_ADDRESS, abi.encodeCall(IMakinaRedeemer.machine, ()), abi.encode(DUSD_MACHINE_ADDRESS)
        );
        vm.mockCall(
            DUSD_MACHINE_ADDRESS, abi.encodeCall(IMakinaMachine.accountingToken, ()), abi.encode(USDC_TOKEN_ADDRESS)
        );
        vm.mockCall(DUSD_SHARE_PRICE_ORACLE_ADDRESS, abi.encodeCall(IERC20Metadata.decimals, ()), abi.encode(uint8(18)));

        MigratablesFactory factory = new MigratablesFactory(address(this));
        DUSD_Account implementation = new DUSD_Account(address(factory), cowSwapSettlement);
        MakinaOracle oracle = MakinaOracle(implementation.ORACLE());

        assertEq(implementation.TOKEN_TO_REDEEM(), DUSD_TOKEN_ADDRESS);
        assertEq(implementation.REDEEMER(), DUSD_REDEEMER_ADDRESS);
        assertEq(implementation.COOLDOWN(), DUSD_TOKEN_COOLDOWN);
        assertEq(oracle.SHARE_PRICE_ORACLE(), DUSD_SHARE_PRICE_ORACLE_ADDRESS);
        assertEq(oracle.MACHINE(), DUSD_MACHINE_ADDRESS);
        assertEq(oracle.STALENESS_DURATION(), 48 hours);
    }

    function _assertMakinaOracleRejectsPrice(uint256 price) internal {
        MockMakinaSharePriceOracle source = new MockMakinaSharePriceOracle(18, price);
        MockMakinaAccountingClock machine = new MockMakinaAccountingClock();
        machine.setLastGlobalAccountingTime(block.timestamp);
        MakinaOracle oracle = new MakinaOracle(0.5e18, 2.5e18, address(source), address(machine), 48 hours);

        vm.expectRevert(IOracle.InvalidPrice.selector);
        oracle.getPrice();
    }
}

contract MockMakinaAccountingClock {
    uint256 public lastGlobalAccountingTime;

    function setLastGlobalAccountingTime(uint256 timestamp) external {
        lastGlobalAccountingTime = timestamp;
    }
}
