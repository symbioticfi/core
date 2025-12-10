// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IVaultTokenized} from "../../src/interfaces/vault/IVaultTokenized.sol";
import {VaultTokenized} from "../../src/contracts/vault/VaultTokenized.sol";
import "./Vault.t.sol";

contract VaultTokenizedTest is VaultTest {
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

        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.allowance(alice, alice), 0);
        assertEq(vault.decimals(), collateral.decimals());
        assertEq(vault.symbol(), "TEST");
        assertEq(vault.name(), "Test");
    }

    function test_DepositTwice(uint256 amount1, uint256 amount2) public override {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        super.test_DepositTwice(amount1, amount2);
        uint256 shares1 = amount1 * 10 ** 0;
        uint256 shares2 = amount2 * (shares1 + 10 ** 0) / (amount1 + 1);

        assertEq(vault.balanceOf(alice), shares1 + shares2);
        assertEq(vault.totalSupply(), shares1 + shares2);
    }

    function test_DepositBoth(uint256 amount1, uint256 amount2) public override {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        super.test_DepositBoth(amount1, amount2);
        uint256 shares1 = amount1 * 10 ** 0;
        uint256 shares2 = amount2 * (shares1 + 10 ** 0) / (amount1 + 1);

        assertEq(vault.balanceOf(alice), shares1);
        assertEq(vault.balanceOf(bob), shares2);
        assertEq(vault.totalSupply(), shares1 + shares2);
    }

    function test_WithdrawTwice(uint256 amount1, uint256 amount2, uint256 amount3) public override {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        super.test_WithdrawTwice(amount1, amount2, amount3);

        assertEq(vault.balanceOf(alice), amount1 - amount2 - amount3);
        assertEq(vault.totalSupply(), amount1 - amount2 - amount3);
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

        assertEq(vault.balanceOf(alice), mintedShares);
        assertEq(vault.totalSupply(), mintedShares);
        assertEq(vault.activeSharesOf(alice), mintedShares);
        assertEq(vault.activeShares(), mintedShares);

        if (amount2 > mintedShares) {
            vm.startPrank(alice);

            vm.expectRevert();
            vault.transfer(bob, amount2);

            vm.stopPrank();
        } else {
            vm.startPrank(alice);

            vault.transfer(bob, amount2);

            assertEq(vault.balanceOf(alice), mintedShares - amount2);
            assertEq(vault.totalSupply(), mintedShares);
            assertEq(vault.activeSharesOf(alice), mintedShares - amount2);
            assertEq(vault.activeShares(), mintedShares);

            assertEq(vault.balanceOf(bob), amount2);
            assertEq(vault.activeSharesOf(bob), amount2);

            vm.stopPrank();

            vm.startPrank(bob);
            vault.approve(alice, amount2);
            vm.stopPrank();

            assertEq(vault.allowance(bob, alice), amount2);

            vm.startPrank(alice);
            vault.transferFrom(bob, alice, amount2);
            vm.stopPrank();

            assertEq(vault.balanceOf(alice), mintedShares);
            assertEq(vault.totalSupply(), mintedShares);
            assertEq(vault.activeSharesOf(alice), mintedShares);
            assertEq(vault.activeShares(), mintedShares);
        }
    }

    function _createVaultImpl(address delegatorFactory, address slasherFactory, address vaultFactory)
        internal
        virtual
        override
        returns (address)
    {
        return address(new VaultTokenized(delegatorFactory, slasherFactory, vaultFactory));
    }

    function _createInitializedVault(
        uint48 epochDuration,
        address[] memory networkLimitSetRoleHolders,
        address[] memory operatorNetworkSharesSetRoleHolders,
        uint64 version,
        address burner,
        bool depositWhitelist,
        bool isDepositLimit,
        uint256 depositLimit
    ) internal virtual override returns (IVaultFull, address, address) {
        (address vault_, address delegator_, address slasher_) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: version,
                owner: address(0),
                vaultParams: abi.encode(
                    IVaultTokenized.InitParamsTokenized({
                        baseParams: IVault.InitParams({
                            collateral: address(collateral),
                            burner: burner,
                            epochDuration: epochDuration,
                            depositWhitelist: depositWhitelist,
                            isDepositLimit: isDepositLimit,
                            depositLimit: depositLimit,
                            defaultAdminRoleHolder: alice,
                            depositWhitelistSetRoleHolder: alice,
                            depositorWhitelistRoleHolder: alice,
                            isDepositLimitSetRoleHolder: alice,
                            depositLimitSetRoleHolder: alice
                        }),
                        name: "Test",
                        symbol: "TEST"
                    })
                ),
                delegatorIndex: 1,
                delegatorParams: abi.encode(
                    INetworkRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({
                            defaultAdminRoleHolder: alice, hook: address(0), hookSetRoleHolder: alice
                        }),
                        networkLimitSetRoleHolders: networkLimitSetRoleHolders,
                        operatorNetworkSharesSetRoleHolders: operatorNetworkSharesSetRoleHolders
                    })
                ),
                withSlasher: true,
                slasherIndex: 0,
                slasherParams: abi.encode(
                    ISlasher.InitParams({baseParams: IBaseSlasher.BaseParams({isBurnerHook: false})})
                )
            })
        );

        return (IVaultFull(vault_), address(delegator_), address(slasher_));
    }

    function _getEncodedVaultParams(IVault.InitParams memory params) internal pure override returns (bytes memory) {
        return abi.encode(IVaultTokenized.InitParamsTokenized({baseParams: params, name: "Test", symbol: "TEST"}));
    }

    function _grantDepositorWhitelistRole(address user, address account) internal virtual override {
        vm.startPrank(user);
        VaultTokenized(address(vault)).grantRole(VaultTokenized(address(vault)).DEPOSITOR_WHITELIST_ROLE(), account);
        vm.stopPrank();
    }

    function _grantDepositWhitelistSetRole(address user, address account) internal virtual override {
        vm.startPrank(user);
        VaultTokenized(address(vault)).grantRole(vault.DEPOSIT_WHITELIST_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _grantIsDepositLimitSetRole(address user, address account) internal virtual override {
        vm.startPrank(user);
        VaultTokenized(address(vault)).grantRole(vault.IS_DEPOSIT_LIMIT_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _grantDepositLimitSetRole(address user, address account) internal virtual override {
        vm.startPrank(user);
        VaultTokenized(address(vault)).grantRole(vault.DEPOSIT_LIMIT_SET_ROLE(), account);
        vm.stopPrank();
    }
}
