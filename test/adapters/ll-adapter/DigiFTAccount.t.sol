// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./AccountsBase.t.sol";

import {bEQTY_Account} from "../../../src/contracts/adapters/ll-adapter/tokens-to-redeem/bEQTY_Account.sol";
import {ISettlementAccount} from "../../../src/interfaces/adapters/ll-adapter/ISettlementAccount.sol";
import {ISettlementSubAccount} from "../../../src/interfaces/adapters/ll-adapter/ISettlementSubAccount.sol";

contract DigiFTAccountTest is AccountsBase {
    function testDigiFTAccountRequestsNormalRedemptionThroughSubAccountAndSweepsSettlement() public {
        MockERC20 tokenToRedeem = new MockERC20("DigiFT Money Market Fund Token", "DMMF01", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(1e18);
        MockDigiFTSubRedManagement mockSubRedManagement = new MockDigiFTSubRedManagement();
        DigiFTAccount account = _deployDigiFT(tokenToRedeem, asset, oracle, address(mockSubRedManagement));

        tokenToRedeem.mint(address(account), 50 ether);

        assertEq(account.SUB_RED_MANAGEMENT(), address(mockSubRedManagement));
        assertEq(account.SETTLEMENT_DURATION(), DIGIFT_SETTLEMENT_DURATION);
        assertEq(account.COOLDOWN(), 0);
        assertEq(account.totalAssets(), 50e6);

        account.sync();

        address subAccount = account.subAccounts(0);

        assertEq(mockSubRedManagement.redeemCalls(), 1);
        assertEq(mockSubRedManagement.lastStToken(), address(tokenToRedeem));
        assertEq(mockSubRedManagement.lastCurrencyToken(), address(asset));
        assertEq(mockSubRedManagement.lastInvestor(), subAccount);
        assertEq(mockSubRedManagement.lastQuantity(), 50 ether);
        assertEq(mockSubRedManagement.lastDeadline(), vm.getBlockTimestamp());
        assertEq(tokenToRedeem.allowance(subAccount, address(mockSubRedManagement)), type(uint256).max);
        assertEq(tokenToRedeem.balanceOf(address(account)), 0);
        assertEq(tokenToRedeem.balanceOf(subAccount), 0);
        assertEq(tokenToRedeem.balanceOf(address(mockSubRedManagement)), 50 ether);
        assertEq(account.totalAssets(), 50e6);

        asset.mint(address(mockSubRedManagement), 50e6);
        mockSubRedManagement.settle(asset, subAccount, 50e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 50e6);
        assertEq(account.totalAssets(), 50e6);

        vm.expectRevert();
        account.subAccounts(0);
    }

    function testDigiFTAccountPendingTracksLiveOracleUntilFrozen() public {
        MockERC20 tokenToRedeem = new MockERC20("DigiFT Money Market Fund Token", "DMMF01", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(1e18);
        MockDigiFTSubRedManagement mockSubRedManagement = new MockDigiFTSubRedManagement();
        DigiFTAccount account = _deployDigiFT(tokenToRedeem, asset, oracle, address(mockSubRedManagement));

        tokenToRedeem.mint(address(account), 50 ether);
        account.sync();

        address subAccount = account.subAccounts(0);

        // pending value tracks the live oracle until the cohort rate freezes
        oracle.setPriceData(12e17, uint48(vm.getBlockTimestamp()));
        assertEq(account.totalAssets(), 60e6);

        // oracle print at/after the request time freezes the rate on the next sync
        account.sync();
        oracle.setPriceData(2e18, uint48(vm.getBlockTimestamp()));
        assertEq(account.totalAssets(), 60e6);

        // settlement covering the frozen cohort value is swept and releases the subaccount
        asset.mint(address(mockSubRedManagement), 60e6);
        mockSubRedManagement.settle(asset, subAccount, 60e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 60e6);
        assertEq(account.totalAssets(), 60e6);

        vm.expectRevert();
        account.subAccounts(0);
    }

    function testDigiFTAccountKeepsSubAccountPendingUntilFullySettled() public {
        MockERC20 tokenToRedeem = new MockERC20("DigiFT Money Market Fund Token", "DMMF01", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(1e18);
        MockDigiFTSubRedManagement mockSubRedManagement = new MockDigiFTSubRedManagement();
        DigiFTAccount account = _deployDigiFT(tokenToRedeem, asset, oracle, address(mockSubRedManagement));

        tokenToRedeem.mint(address(account), 50 ether);
        account.sync();

        address subAccount = account.subAccounts(0);

        // first tranche (60%): swept but the subaccount is retained until value-covered
        asset.mint(address(mockSubRedManagement), 30e6);
        mockSubRedManagement.settle(asset, subAccount, 30e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 30e6);
        assertEq(account.subAccounts(0), subAccount);
        assertEq(account.receivedValues(uint160(subAccount)), 30e6);
        assertEq(account.totalAssets(), 50e6);

        // second tranche (40%): coverage met, subaccount released
        asset.mint(address(mockSubRedManagement), 20e6);
        mockSubRedManagement.settle(asset, subAccount, 20e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 50e6);
        assertEq(account.totalAssets(), 50e6);

        vm.expectRevert();
        account.subAccounts(0);
    }

    function testDigiFTAccountWritesOffPendingButKeepsSubAccountForLateSettlement() public {
        MockERC20 tokenToRedeem = new MockERC20("DigiFT Money Market Fund Token", "DMMF01", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(1e18);
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

        // unsettled past the settlement duration: the remaining receivable is written off
        vm.warp(vm.getBlockTimestamp() + DIGIFT_SETTLEMENT_DURATION);

        assertEq(account.totalAssets(), 20e6);
        assertEq(account.subAccounts(0), subAccount);

        account.sync();

        assertEq(asset.balanceOf(address(account)), 20e6);
        assertEq(account.subAccounts(0), subAccount);
        assertEq(account.totalAssets(), 20e6);

        // a late settlement covering the frozen cohort value is still swept and releases
        asset.mint(address(mockSubRedManagement), 30e6);
        mockSubRedManagement.settle(asset, subAccount, 30e6);
        account.sync();

        assertEq(asset.balanceOf(address(account)), 50e6);
        assertEq(account.totalAssets(), 50e6);

        vm.expectRevert();
        account.subAccounts(0);
    }

    function testDigiFTAccountRollingModeAssignsPerRequestCohortsAndRequestsEverySync() public {
        MockERC20 tokenToRedeem = new MockERC20("DigiFT Money Market Fund Token", "DMMF01", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(1e18);
        MockDigiFTSubRedManagement mockSubRedManagement = new MockDigiFTSubRedManagement();
        DigiFTAccount account = _deployDigiFT(tokenToRedeem, asset, oracle, address(mockSubRedManagement));

        assertEq(account.cutoff(), 0);
        assertEq(account.cutoffPeriod(), 0);

        tokenToRedeem.mint(address(account), 30 ether);
        account.sync();

        address firstSubAccount = account.subAccounts(0);
        (uint128 firstAmount,, uint48 firstCutoff) = account.pendingCohorts(uint160(firstSubAccount));
        assertEq(firstAmount, 30 ether);
        assertEq(firstCutoff, uint48(vm.getBlockTimestamp()));

        // no cooldown: a later token arrival is tendered on the very next sync under its own cohort
        vm.warp(vm.getBlockTimestamp() + 12 hours);
        tokenToRedeem.mint(address(account), 20 ether);
        account.sync();

        address secondSubAccount = account.subAccounts(1);
        assertNotEq(secondSubAccount, firstSubAccount);
        (uint128 secondAmount,, uint48 secondCutoff) = account.pendingCohorts(uint160(secondSubAccount));
        assertEq(secondAmount, 20 ether);
        assertEq(secondCutoff, uint48(vm.getBlockTimestamp()));
        assertEq(mockSubRedManagement.redeemCalls(), 2);
        assertEq(account.totalAssets(), 50e6);
    }

    function testDigiFTSubAccountOnlyParentCanCall() public {
        MockERC20 tokenToRedeem = new MockERC20("DigiFT Money Market Fund Token", "DMMF01", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(1e18);
        MockDigiFTSubRedManagement mockSubRedManagement = new MockDigiFTSubRedManagement();
        DigiFTAccount account = _deployDigiFT(tokenToRedeem, asset, oracle, address(mockSubRedManagement));

        tokenToRedeem.mint(address(account), 50 ether);
        account.sync();

        address subAccount = account.subAccounts(0);

        vm.expectRevert(ISettlementSubAccount.NotAccount.selector);
        ISettlementSubAccount(subAccount).sync();

        vm.expectRevert(ISettlementSubAccount.NotAccount.selector);
        ISettlementSubAccount(subAccount).requestRedeem();
    }

    function testDigiFTMigrationGuardsLegacySubAccountsSlot() public {
        MockERC20 tokenToRedeem = new MockERC20("DigiFT Money Market Fund Token", "DMMF01", 18);
        MockERC20 asset = new MockERC20("USD Coin", "USDC", 6);
        MockPriceDataOracle oracle = new MockPriceDataOracle(1e18);
        MockDigiFTSubRedManagement mockSubRedManagement = new MockDigiFTSubRedManagement();

        MigratablesFactory factory = new MigratablesFactory(address(this));
        factory.whitelist(
            address(
                new DigiFTAccount(
                    address(oracle),
                    address(factory),
                    address(tokenToRedeem),
                    address(mockSubRedManagement),
                    DIGIFT_SETTLEMENT_DURATION,
                    cowSwapSettlement
                )
            )
        );
        DigiFTAccount account =
            DigiFTAccount(factory.create(1, address(this), _initData(address(asset), address(tokenToRedeem))));
        factory.whitelist(
            address(
                new DigiFTAccount(
                    address(oracle),
                    address(factory),
                    address(tokenToRedeem),
                    address(mockSubRedManagement),
                    DIGIFT_SETTLEMENT_DURATION,
                    cowSwapSettlement
                )
            )
        );

        // simulate a legacy (pre-settlement-family) instance whose subAccounts array length lived at
        // raw slot 15: a nonzero value there means in-flight legacy subaccounts -> migration refused
        vm.store(address(account), bytes32(uint256(15)), bytes32(uint256(1)));
        vm.expectRevert(ISettlementAccount.MigrationWithLiveSubAccounts.selector);
        factory.migrate(address(account), 2, "");

        // empty legacy pipeline (slot 15 zero) and no tracked subaccounts: migration succeeds
        vm.store(address(account), bytes32(uint256(15)), bytes32(uint256(0)));
        factory.migrate(address(account), 2, "");

        assertEq(account.version(), 2);
    }

    function testBEQTYAccountHardcodesMainnetTokenAndSubRedManagement() public {
        _mockDecimals(BEQTY_TOKEN_ADDRESS, 18);

        MigratablesFactory factory = new MigratablesFactory(address(this));
        MockPriceDataOracle oracle = new MockPriceDataOracle(1e18);
        bEQTY_Account account = new bEQTY_Account(address(oracle), address(factory), cowSwapSettlement);

        assertEq(account.TOKEN_TO_REDEEM(), BEQTY_TOKEN_ADDRESS);
        assertEq(account.SUB_RED_MANAGEMENT(), BEQTY_SUB_RED_MANAGEMENT_ADDRESS);
        assertEq(account.SETTLEMENT_DURATION(), 7 days);
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
