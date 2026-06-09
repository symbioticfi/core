// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

import {IGaibAccount} from "../../../src/interfaces/adapters/ll-adapter/gaib/IGaibAccount.sol";

contract GaibAccountTest is AccountsBase {
    function testGaibAccountRejectsVaultAssetMismatch() public {
        MockERC20 asset = new MockERC20("AI Dollar", "AID", 18);
        MockERC20 wrongAsset = new MockERC20("Wrong USD", "wUSD", 18);
        MockSaidVault said = new MockSaidVault(asset, 103e16);
        MockOracle oracle = new MockOracle(103e16);
        MigratablesFactory factory = new MigratablesFactory(address(this));
        GaibAccount implementation =
            new GaibAccount(address(oracle), address(factory), 0, address(said), cowSwapSettlement);
        factory.whitelist(address(implementation));
        bytes memory data = _initData(address(wrongAsset), address(said));

        vm.expectRevert(IGaibAccount.InvalidAsset.selector);
        factory.create(1, address(this), data);
    }

    function testGaibAccountUnstakesAndTracksPendingAid() public {
        MockERC20 asset = new MockERC20("AI Dollar", "AID", 18);
        MockSaidVault said = new MockSaidVault(asset, 103e16);
        MockOracle oracle = new MockOracle(103e16);
        GaibAccount account = _deployGaib(said, asset, oracle, 0);

        said.mint(address(account), 10 ether);

        assertEq(account.totalAssets(), 103e17);

        account.sync();

        address subAccount = account.subAccounts(0);

        (, uint256 pendingAssets) = said.getUnstakeRequest(subAccount);
        assertEq(said.balanceOf(address(account)), 0);
        assertEq(pendingAssets, 103e17);
        assertEq(account.totalAssets(), 103e17);

        said.fulfill(subAccount, 103e17);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 103e17);
        assertEq(account.totalAssets(), 103e17);
    }

    function testGaibAccountCreatesOneSubAccountRequestPerCooldown() public {
        MockERC20 asset = new MockERC20("AI Dollar", "AID", 18);
        MockSaidVault said = new MockSaidVault(asset, 1e18);
        MockOracle oracle = new MockOracle(1e18);
        GaibAccount account = _deployGaib(said, asset, oracle, 1 days);
        address keeper = makeAddr("keeper");

        said.mint(address(account), 1 ether);
        vm.prank(keeper);
        account.sync();

        address firstSubAccount = account.subAccounts(0);

        said.mint(address(account), 1 ether);
        vm.prank(keeper);
        account.sync();

        (, uint256 firstPendingAssets) = said.getUnstakeRequest(firstSubAccount);
        assertEq(firstPendingAssets, 1 ether);
        assertEq(said.balanceOf(address(account)), 1 ether);
        assertEq(account.totalAssets(), 2 ether);

        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.prank(keeper);
        account.sync();

        address secondSubAccount = account.subAccounts(1);

        (, firstPendingAssets) = said.getUnstakeRequest(firstSubAccount);
        (, uint256 secondPendingAssets) = said.getUnstakeRequest(secondSubAccount);
        assertEq(firstPendingAssets, 1 ether);
        assertEq(secondPendingAssets, 1 ether);
        assertEq(said.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 2 ether);
    }

    function testGaibAccountPermissionlessSyncRespectsCooldownAfterRequestSettles() public {
        MockERC20 asset = new MockERC20("AI Dollar", "AID", 18);
        MockSaidVault said = new MockSaidVault(asset, 1e18);
        MockOracle oracle = new MockOracle(1e18);
        GaibAccount account = _deployGaib(said, asset, oracle, 1 days);
        address keeper = makeAddr("keeper");

        said.mint(address(account), 1 ether);
        vm.prank(keeper);
        account.sync();

        address subAccount = account.subAccounts(0);

        said.mint(address(account), 1 ether);
        said.fulfill(subAccount, 1 ether);
        vm.prank(keeper);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 1 ether);
        assertEq(said.balanceOf(address(account)), 1 ether);

        vm.warp(vm.getBlockTimestamp() + 1 days);
        vm.prank(keeper);
        account.sync();

        subAccount = account.subAccounts(0);

        (, uint256 pendingAssets) = said.getUnstakeRequest(subAccount);
        assertEq(pendingAssets, 1 ether);
        assertEq(said.balanceOf(address(account)), 0);
        assertEq(account.totalAssets(), 2 ether);
    }

    function testSaidOracleUsesLossAwareConversion() public {
        MockERC20 asset = new MockERC20("AI Dollar", "AID", 18);
        MockSaidVault said = new MockSaidVault(asset, 987e15);
        SaidOracle oracle = new SaidOracle(address(said));

        assertEq(oracle.VAULT(), address(said));
        assertEq(oracle.getPrice(), 987e15);
    }

    function testSAIDAccountHardcodesMainnetTokenAndOracle() public {
        vm.mockCall(SAID_TOKEN_ADDRESS, abi.encodeWithSignature("asset()"), abi.encode(AID_TOKEN_ADDRESS));
        vm.mockCall(SAID_TOKEN_ADDRESS, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));
        vm.mockCall(AID_TOKEN_ADDRESS, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));

        MigratablesFactory factory = new MigratablesFactory(address(this));
        sAID_Account implementation = new sAID_Account(address(factory), cowSwapSettlement);
        SaidOracle oracle = SaidOracle(implementation.ORACLE());

        assertEq(implementation.TOKEN_TO_REDEEM(), SAID_TOKEN_ADDRESS);
        assertEq(implementation.COOLDOWN(), SAID_TOKEN_COOLDOWN);
        assertEq(oracle.VAULT(), SAID_TOKEN_ADDRESS);
    }
}
