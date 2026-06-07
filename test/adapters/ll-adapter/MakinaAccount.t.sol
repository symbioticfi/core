// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

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

    function testMakinaAccountDoesNotExposeTotalRequests() public {
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockERC20 tokenToRedeem = new MockERC20("Dialectic USD", "DUSD", 18);
        MockMakinaMachine machine = new MockMakinaMachine(tokenToRedeem, asset, 1e6);
        MockMakinaRedeemer redeemer = new MockMakinaRedeemer(machine);
        MockOracle oracle = new MockOracle(1e18);
        MakinaAccount account = _deployMakina(tokenToRedeem, asset, redeemer, oracle, 0);

        (bool success,) = address(account).staticcall(abi.encodeWithSignature("totalRequests()"));
        assertFalse(success);
    }

    function testMakinaOracleUsesSharePrice() public {
        MockMakinaSharePriceOracle source = new MockMakinaSharePriceOracle(8, 102_868_300);
        MakinaOracle oracle = new MakinaOracle(address(source));

        assertEq(oracle.SHARE_PRICE_ORACLE(), address(source));
        assertEq(oracle.getPrice(), 1_028_683e12);
    }

    function testDUSDAccountHardcodesMainnetTokenRedeemerAndOracle() public {
        vm.mockCall(DUSD_TOKEN_ADDRESS, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.mockCall(DUSD_REDEEMER_ADDRESS, abi.encodeWithSignature("machine()"), abi.encode(DUSD_MACHINE_ADDRESS));
        vm.mockCall(DUSD_MACHINE_ADDRESS, abi.encodeWithSignature("accountingToken()"), abi.encode(USDC_TOKEN_ADDRESS));
        vm.mockCall(DUSD_SHARE_PRICE_ORACLE_ADDRESS, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));

        MigratablesFactory factory = new MigratablesFactory(address(this));
        DUSD_Account implementation = new DUSD_Account(address(factory), cowSwapSettlement, cowSwapVaultRelayer);
        MakinaOracle oracle = MakinaOracle(implementation.ORACLE());

        assertEq(implementation.TOKEN_TO_REDEEM(), DUSD_TOKEN_ADDRESS);
        assertEq(implementation.REDEEMER(), DUSD_REDEEMER_ADDRESS);
        assertEq(implementation.COOLDOWN(), DUSD_TOKEN_COOLDOWN);
        assertEq(oracle.SHARE_PRICE_ORACLE(), DUSD_SHARE_PRICE_ORACLE_ADDRESS);
    }
}
