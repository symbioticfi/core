// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

import {bEQTY_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/bEQTY_Account.sol";
import {IDigiFTSubAccount} from "../../../src/interfaces/adapters/ll-adapter/digift/IDigiFTSubAccount.sol";

contract DigiFTAccountTest is AccountsBase {
    function testDigiFTAccountRequestsNormalRedemptionThroughSubAccountAndSweepsSettlement() public {
        MockERC20 tokenToRedeem = new MockERC20("DigiFT Money Market Fund Token", "DMMF01", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockOracle oracle = new MockOracle(1e18);
        MockDigiFTSubRedManagement mockSubRedManagement = new MockDigiFTSubRedManagement();
        DigiFTAccount account = _deployDigiFT(tokenToRedeem, asset, oracle, address(mockSubRedManagement));

        tokenToRedeem.mint(address(account), 50 ether);

        assertEq(account.SUB_RED_MANAGEMENT(), address(mockSubRedManagement));
        assertEq(account.PENDING_ASSETS_DURATION(), DIGIFT_PENDING_ASSETS_DURATION);
        assertEq(account.totalAssets(), 50e6);

        account.sync();

        address subAccount = account.subAccounts(0);

        assertEq(mockSubRedManagement.redeemCalls(), 1);
        assertEq(mockSubRedManagement.lastStToken(), address(tokenToRedeem));
        assertEq(mockSubRedManagement.lastCurrencyToken(), address(asset));
        assertEq(mockSubRedManagement.lastInvestor(), subAccount);
        assertEq(mockSubRedManagement.lastQuantity(), 50 ether);
        assertEq(tokenToRedeem.allowance(subAccount, address(mockSubRedManagement)), type(uint256).max);
        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.balanceOf(subAccount), 0);
        assertEq(tokenToRedeem.balanceOf(address(mockSubRedManagement)), 50 ether);
        assertEq(account.totalAssets(), 50e6);
        assertEq(IDigiFTSubAccount(subAccount).totalAssets(), 50e6);

        asset.mint(address(mockSubRedManagement), 50e6);
        mockSubRedManagement.settle(asset, subAccount, 50e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 50e6);
        assertEq(account.totalAssets(), 50e6);

        vm.expectRevert();
        account.subAccounts(0);
    }

    function testDigiFTAccountKeepsSubAccountPendingUntilFullySettled() public {
        MockERC20 tokenToRedeem = new MockERC20("DigiFT Money Market Fund Token", "DMMF01", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockOracle oracle = new MockOracle(1e18);
        MockDigiFTSubRedManagement mockSubRedManagement = new MockDigiFTSubRedManagement();
        DigiFTAccount account = _deployDigiFT(tokenToRedeem, asset, oracle, address(mockSubRedManagement));

        tokenToRedeem.mint(address(account), 50 ether);
        account.sync();

        address subAccount = account.subAccounts(0);

        asset.mint(address(mockSubRedManagement), 20e6);
        mockSubRedManagement.settle(asset, subAccount, 20e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 20e6);
        assertEq(account.subAccounts(0), subAccount);
        assertEq(IDigiFTSubAccount(subAccount).totalAssets(), 30e6);
        assertEq(account.totalAssets(), 50e6);

        asset.mint(address(mockSubRedManagement), 30e6);
        mockSubRedManagement.settle(asset, subAccount, 30e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 50e6);
        assertEq(account.totalAssets(), 50e6);

        vm.expectRevert();
        account.subAccounts(0);
    }

    function testDigiFTAccountExpiresPendingValuationButKeepsSubAccountUntilSettled() public {
        MockERC20 tokenToRedeem = new MockERC20("DigiFT Money Market Fund Token", "DMMF01", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockOracle oracle = new MockOracle(1e18);
        MockDigiFTSubRedManagement mockSubRedManagement = new MockDigiFTSubRedManagement();
        DigiFTAccount account = _deployDigiFT(tokenToRedeem, asset, oracle, address(mockSubRedManagement));

        tokenToRedeem.mint(address(account), 50 ether);
        account.sync();

        address subAccount = account.subAccounts(0);

        asset.mint(address(mockSubRedManagement), 20e6);
        mockSubRedManagement.settle(asset, subAccount, 20e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 20e6);
        assertEq(account.totalAssets(), 50e6);

        vm.warp(vm.getBlockTimestamp() + DIGIFT_PENDING_ASSETS_DURATION);

        assertEq(IDigiFTSubAccount(subAccount).totalAssets(), 0);
        assertFalse(IDigiFTSubAccount(subAccount).isSettled());
        assertEq(account.totalAssets(), 20e6);

        account.sync();

        assertEq(asset.balanceOf(address(account)), 20e6);
        assertEq(account.subAccounts(0), subAccount);
        assertEq(account.totalAssets(), 20e6);

        asset.mint(address(mockSubRedManagement), 30e6);
        mockSubRedManagement.settle(asset, subAccount, 30e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 50e6);
        assertTrue(IDigiFTSubAccount(subAccount).isSettled());
        assertEq(account.totalAssets(), 50e6);

        vm.expectRevert();
        account.subAccounts(0);
    }

    function testDigiFTSubAccountOnlyParentCanSync() public {
        MockERC20 tokenToRedeem = new MockERC20("DigiFT Money Market Fund Token", "DMMF01", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockOracle oracle = new MockOracle(1e18);
        MockDigiFTSubRedManagement mockSubRedManagement = new MockDigiFTSubRedManagement();
        DigiFTAccount account = _deployDigiFT(tokenToRedeem, asset, oracle, address(mockSubRedManagement));

        tokenToRedeem.mint(address(account), 50 ether);
        account.sync();

        address subAccount = account.subAccounts(0);

        vm.expectRevert(IDigiFTSubAccount.NotAccount.selector);
        IDigiFTSubAccount(subAccount).sync();
    }

    function testBEQTYAccountHardcodesMainnetTokenAndSubRedManagement() public {
        _mockDecimals(BEQTY_TOKEN_ADDRESS, 18);

        MigratablesFactory factory = new MigratablesFactory(address(this));
        MockOracle oracle = new MockOracle(1e18);
        bEQTY_Account account = new bEQTY_Account(address(oracle), address(factory), cowSwapSettlement);

        assertEq(account.TOKEN_TO_REDEEM(), BEQTY_TOKEN_ADDRESS);
        assertEq(account.SUB_RED_MANAGEMENT(), BEQTY_SUB_RED_MANAGEMENT_ADDRESS);
        assertEq(account.PENDING_ASSETS_DURATION(), 1 days);
    }
}

contract MockDigiFTSubRedManagement {
    address public lastStToken;
    address public lastCurrencyToken;
    address public lastInvestor;
    uint256 public lastQuantity;
    uint256 public lastDeadline;
    uint256 public redeemCalls;

    function redeem(address stToken, address currencyToken, uint256 quantity, uint256 deadline) external {
        lastStToken = stToken;
        lastInvestor = msg.sender;
        lastQuantity = quantity;
        lastDeadline = deadline;
        ++redeemCalls;
        lastCurrencyToken = currencyToken;

        MockERC20(stToken).transferFrom(msg.sender, address(this), quantity);
    }

    function settle(MockERC20 asset, address investor, uint256 amount) external {
        asset.transfer(investor, amount);
    }
}
