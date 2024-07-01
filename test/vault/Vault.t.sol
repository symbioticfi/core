// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {VaultFactory} from "src/contracts/VaultFactory.sol";
import {DelegatorFactory} from "src/contracts/DelegatorFactory.sol";
import {SlasherFactory} from "src/contracts/SlasherFactory.sol";
import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";
import {MetadataService} from "src/contracts/service/MetadataService.sol";
import {NetworkMiddlewareService} from "src/contracts/service/NetworkMiddlewareService.sol";
import {OptInService} from "src/contracts/service/OptInService.sol";

import {Vault} from "src/contracts/vault/Vault.sol";
import {NetworkRestakeDelegator} from "src/contracts/delegator/NetworkRestakeDelegator.sol";
import {FullRestakeDelegator} from "src/contracts/delegator/FullRestakeDelegator.sol";
import {Slasher} from "src/contracts/slasher/Slasher.sol";
import {VetoSlasher} from "src/contracts/slasher/VetoSlasher.sol";

import {IVault} from "src/interfaces/vault/IVault.sol";
import {SimpleCollateral} from "test/mocks/SimpleCollateral.sol";
import {Token} from "test/mocks/Token.sol";
import {VaultConfigurator} from "src/contracts/VaultConfigurator.sol";
import {IVaultConfigurator} from "src/interfaces/IVaultConfigurator.sol";
import {INetworkRestakeDelegator} from "src/interfaces/delegator/INetworkRestakeDelegator.sol";
import {IBaseDelegator} from "src/interfaces/delegator/IBaseDelegator.sol";

import {IVaultStorage} from "src/interfaces/vault/IVaultStorage.sol";

contract VaultTest is Test {
    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    VaultFactory vaultFactory;
    DelegatorFactory delegatorFactory;
    SlasherFactory slasherFactory;
    NetworkRegistry networkRegistry;
    OperatorRegistry operatorRegistry;
    MetadataService operatorMetadataService;
    MetadataService networkMetadataService;
    NetworkMiddlewareService networkMiddlewareService;
    OptInService networkVaultOptInService;
    OptInService operatorVaultOptInService;
    OptInService operatorNetworkOptInService;

    SimpleCollateral collateral;
    VaultConfigurator vaultConfigurator;

    Vault vault;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        vaultFactory = new VaultFactory(owner);
        delegatorFactory = new DelegatorFactory(owner);
        slasherFactory = new SlasherFactory(owner);
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        operatorMetadataService = new MetadataService(address(operatorRegistry));
        networkMetadataService = new MetadataService(address(networkRegistry));
        networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        networkVaultOptInService = new OptInService(address(networkRegistry), address(vaultFactory));
        operatorVaultOptInService = new OptInService(address(operatorRegistry), address(vaultFactory));
        operatorNetworkOptInService = new OptInService(address(operatorRegistry), address(networkRegistry));

        address vaultImpl =
            address(new Vault(address(delegatorFactory), address(slasherFactory), address(vaultFactory)));
        vaultFactory.whitelist(vaultImpl);

        address networkRestakeDelegatorImpl = address(
            new NetworkRestakeDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory)
            )
        );
        delegatorFactory.whitelist(networkRestakeDelegatorImpl);

        address fullRestakeDelegatorImpl = address(
            new FullRestakeDelegator(
                address(networkRegistry),
                address(vaultFactory),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(delegatorFactory)
            )
        );
        delegatorFactory.whitelist(fullRestakeDelegatorImpl);

        address slasherImpl = address(
            new Slasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkVaultOptInService),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(slasherFactory)
            )
        );
        slasherFactory.whitelist(slasherImpl);

        address vetoSlasherImpl = address(
            new VetoSlasher(
                address(vaultFactory),
                address(networkMiddlewareService),
                address(networkVaultOptInService),
                address(operatorVaultOptInService),
                address(operatorNetworkOptInService),
                address(networkRegistry),
                address(slasherFactory)
            )
        );
        slasherFactory.whitelist(vetoSlasherImpl);

        Token token = new Token("Token");
        collateral = new SimpleCollateral(address(token));

        collateral.mint(token.totalSupply());

        vaultConfigurator =
            new VaultConfigurator(address(vaultFactory), address(delegatorFactory), address(slasherFactory));
    }

    function test_Create(
        address burner,
        uint48 epochDuration,
        uint256 slasherSetEpochsDelay,
        bool depositWhitelist
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));
        slasherSetEpochsDelay = bound(slasherSetEpochsDelay, 3, 50);

        (address vault_, address delegator_,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: alice,
                vaultParams: IVault.InitParams({
                    collateral: address(collateral),
                    delegator: address(0),
                    slasher: address(0),
                    burner: burner,
                    epochDuration: epochDuration,
                    slasherSetEpochsDelay: slasherSetEpochsDelay,
                    depositWhitelist: depositWhitelist,
                    defaultAdminRoleHolder: alice,
                    slasherSetRoleHolder: alice,
                    depositorWhitelistRoleHolder: alice
                }),
                delegatorIndex: 0,
                delegatorParams: abi.encode(
                    INetworkRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({defaultAdminRoleHolder: alice}),
                        networkLimitSetRoleHolder: alice,
                        operatorNetworkSharesSetRoleHolder: alice
                    })
                ),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: ""
            })
        );

        vault = Vault(vault_);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        assertEq(vault.SLASHER_SET_ROLE(), keccak256("SLASHER_SET_ROLE"));
        assertEq(vault.DEPOSIT_WHITELIST_SET_ROLE(), keccak256("DEPOSIT_WHITELIST_SET_ROLE"));
        assertEq(vault.DEPOSITOR_WHITELIST_ROLE(), keccak256("DEPOSITOR_WHITELIST_ROLE"));
        assertEq(vault.DELEGATOR_FACTORY(), address(delegatorFactory));
        assertEq(vault.SLASHER_FACTORY(), address(slasherFactory));

        assertEq(vault.owner(), alice);
        assertEq(vault.collateral(), address(collateral));
        assertEq(vault.delegator(), delegator_);
        assertEq(vault.slasher(), address(0));
        assertEq(vault.burner(), burner);
        assertEq(vault.epochDuration(), epochDuration);
        assertEq(vault.slasherSetEpochsDelay(), slasherSetEpochsDelay);
        assertEq(vault.depositWhitelist(), depositWhitelist);
        assertEq(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), alice), true);
        assertEq(vault.hasRole(vault.SLASHER_SET_ROLE(), alice), true);
        assertEq(vault.hasRole(vault.DEPOSITOR_WHITELIST_ROLE(), alice), depositWhitelist);
        assertEq(vault.epochDurationInit(), blockTimestamp);
        assertEq(vault.epochDuration(), epochDuration);
        vm.expectRevert(IVaultStorage.InvalidTimestamp.selector);
        assertEq(vault.epochAt(0), 0);
        assertEq(vault.epochAt(uint48(blockTimestamp)), 0);
        assertEq(vault.currentEpoch(), 0);
        assertEq(vault.currentEpochStart(), blockTimestamp);
        vm.expectRevert(IVaultStorage.NoPreviousEpoch.selector);
        vault.previousEpochStart();
        assertEq(vault.totalSupplyIn(0), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp)), 0);
        assertEq(vault.activeShares(), 0);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp)), 0);
        assertEq(vault.activeSupply(), 0);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp)), 0);
        assertEq(vault.activeSharesOf(alice), 0);
        (bool checkpointExists, uint48 checkpointKey, uint256 checkpointValue) =
            vault.activeSharesOfCheckpointAt(alice, uint48(blockTimestamp));
        assertEq(checkpointExists, false);
        assertEq(checkpointKey, 0);
        assertEq(checkpointValue, 0);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp)), 0);
        assertEq(vault.activeBalanceOf(alice), 0);
        assertEq(vault.withdrawals(0), 0);
        assertEq(vault.withdrawalShares(0), 0);
        assertEq(vault.isWithdrawalsClaimed(0, alice), false);
        assertEq(vault.depositWhitelist(), depositWhitelist);
        assertEq(vault.isDepositorWhitelisted(alice), false);

        blockTimestamp = blockTimestamp + vault.epochDuration() - 1;
        vm.warp(blockTimestamp);

        assertEq(vault.epochAt(uint48(blockTimestamp)), 0);
        assertEq(vault.epochAt(uint48(blockTimestamp + 1)), 1);
        assertEq(vault.currentEpoch(), 0);
        assertEq(vault.currentEpochStart(), blockTimestamp - (vault.epochDuration() - 1));
        vm.expectRevert(IVaultStorage.NoPreviousEpoch.selector);
        vault.previousEpochStart();

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.epochAt(uint48(blockTimestamp)), 1);
        assertEq(vault.epochAt(uint48(blockTimestamp + 2 * vault.epochDuration())), 3);
        assertEq(vault.currentEpoch(), 1);
        assertEq(vault.currentEpochStart(), blockTimestamp);
        assertEq(vault.previousEpochStart(), blockTimestamp - vault.epochDuration());

        blockTimestamp = blockTimestamp + vault.epochDuration() - 1;
        vm.warp(blockTimestamp);

        assertEq(vault.epochAt(uint48(blockTimestamp)), 1);
        assertEq(vault.epochAt(uint48(blockTimestamp + 1)), 2);
        assertEq(vault.currentEpoch(), 1);
        assertEq(vault.currentEpochStart(), blockTimestamp - (vault.epochDuration() - 1));
        assertEq(vault.previousEpochStart(), blockTimestamp - (vault.epochDuration() - 1) - vault.epochDuration());
    }

    function test_DepositTwice(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 tokensBefore = collateral.balanceOf(address(vault));
        uint256 shares1 = amount1 * 10 ** 3;
        assertEq(_deposit(alice, amount1), shares1);
        assertEq(collateral.balanceOf(address(vault)) - tokensBefore, amount1);

        assertEq(vault.totalSupplyIn(0), amount1);
        assertEq(vault.totalSupplyIn(1), amount1);
        assertEq(vault.totalSupplyIn(2), amount1);
        assertEq(vault.totalSupply(), amount1);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1)), 0);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp)), shares1);
        assertEq(vault.activeShares(), shares1);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp - 1)), 0);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp)), amount1);
        assertEq(vault.activeSupply(), amount1);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1)), 0);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp)), shares1);
        assertEq(vault.activeSharesOf(alice), shares1);
        (bool checkpointExists, uint48 checkpointKey, uint256 checkpointValue) =
            vault.activeSharesOfCheckpointAt(alice, uint48(blockTimestamp));
        assertEq(checkpointExists, true);
        assertEq(checkpointKey, blockTimestamp);
        assertEq(checkpointValue, shares1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1)), 0);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp)), amount1);
        assertEq(vault.activeBalanceOf(alice), amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 shares2 = amount2 * (shares1 + 10 ** 3) / (amount1 + 1);
        assertEq(_deposit(alice, amount2), shares2);

        assertEq(vault.totalSupplyIn(0), amount1 + amount2);
        assertEq(vault.totalSupplyIn(1), amount1 + amount2);
        assertEq(vault.totalSupplyIn(2), amount1 + amount2);
        assertEq(vault.totalSupply(), amount1 + amount2);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1)), shares1);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp)), shares1 + shares2);
        assertEq(vault.activeShares(), shares1 + shares2);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp - 1)), amount1);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp)), amount1 + amount2);
        assertEq(vault.activeSupply(), amount1 + amount2);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1)), shares1);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp)), shares1 + shares2);
        assertEq(vault.activeSharesOf(alice), shares1 + shares2);
        (checkpointExists, checkpointKey, checkpointValue) =
            vault.activeSharesOfCheckpointAt(alice, uint48(blockTimestamp - 1));
        assertEq(checkpointExists, true);
        assertEq(checkpointKey, blockTimestamp - 1);
        assertEq(checkpointValue, shares1);
        (checkpointExists, checkpointKey, checkpointValue) =
            vault.activeSharesOfCheckpointAt(alice, uint48(blockTimestamp));
        assertEq(checkpointExists, true);
        assertEq(checkpointKey, blockTimestamp);
        assertEq(checkpointValue, shares1 + shares2);
        uint256 gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), 1), shares1);
        uint256 gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1), 0), shares1);
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), 0), shares1 + shares2);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp), 1), shares1 + shares2);
        assertGt(gasSpent, gasLeft - gasleft());
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1)), amount1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp)), amount1 + amount2);
        assertEq(vault.activeBalanceOf(alice), amount1 + amount2);
    }

    function test_DepositBoth(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares1 = amount1 * 10 ** 3;
        assertEq(_deposit(alice, amount1), shares1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 shares2 = amount2 * (shares1 + 10 ** 3) / (amount1 + 1);
        assertEq(_deposit(bob, amount2), shares2);

        assertEq(vault.totalSupply(), amount1 + amount2);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1)), shares1);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp)), shares1 + shares2);
        assertEq(vault.activeShares(), shares1 + shares2);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp - 1)), amount1);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp)), amount1 + amount2);
        assertEq(vault.activeSupply(), amount1 + amount2);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1)), shares1);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp)), shares1);
        assertEq(vault.activeSharesOf(alice), shares1);
        (bool checkpointExists, uint48 checkpointKey, uint256 checkpointValue) =
            vault.activeSharesOfCheckpointAt(alice, uint48(blockTimestamp));
        assertEq(checkpointExists, true);
        assertEq(checkpointKey, blockTimestamp - 1);
        assertEq(checkpointValue, shares1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1)), amount1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp)), amount1);
        assertEq(vault.activeBalanceOf(alice), amount1);
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp - 1)), 0);
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp)), shares2);
        assertEq(vault.activeSharesOf(bob), shares2);
        (checkpointExists, checkpointKey, checkpointValue) =
            vault.activeSharesOfCheckpointAt(bob, uint48(blockTimestamp));
        assertEq(checkpointExists, true);
        assertEq(checkpointKey, blockTimestamp);
        assertEq(checkpointValue, shares2);
        assertEq(vault.activeBalanceOfAt(bob, uint48(blockTimestamp - 1)), 0);
        assertEq(vault.activeBalanceOfAt(bob, uint48(blockTimestamp)), amount2);
        assertEq(vault.activeBalanceOf(bob), amount2);
    }

    function test_DepositRevertInsufficientDeposit() public {
        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        vm.startPrank(alice);
        vm.expectRevert(IVault.InsufficientDeposit.selector);
        vault.deposit(alice, 0);
        vm.stopPrank();
    }

    function test_WithdrawTwice(uint256 amount1, uint256 amount2, uint256 amount3) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount3, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2 + amount3);

        // uint48 epochDuration = 1;
        vault = _getVault(1);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 tokensBefore = collateral.balanceOf(address(vault));
        uint256 burnedShares = amount2 * (shares + 10 ** 3) / (amount1 + 1);
        uint256 mintedShares = amount2 * 10 ** 3;
        (uint256 burnedShares_, uint256 mintedShares_) = _withdraw(alice, amount2);
        assertEq(burnedShares_, burnedShares);
        assertEq(mintedShares_, mintedShares);
        assertEq(tokensBefore - collateral.balanceOf(address(vault)), 0);

        assertEq(vault.totalSupplyIn(0), amount1);
        assertEq(vault.totalSupplyIn(1), amount1);
        assertEq(vault.totalSupplyIn(2), amount1 - amount2);
        assertEq(vault.totalSupply(), amount1);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1)), shares);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp)), shares - burnedShares);
        assertEq(vault.activeShares(), shares - burnedShares);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp - 1)), amount1);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp)), amount1 - amount2);
        assertEq(vault.activeSupply(), amount1 - amount2);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1)), shares);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp)), shares - burnedShares);
        assertEq(vault.activeSharesOf(alice), shares - burnedShares);
        (bool checkpointExists, uint48 checkpointKey, uint256 checkpointValue) =
            vault.activeSharesOfCheckpointAt(alice, uint48(blockTimestamp));
        assertEq(checkpointExists, true);
        assertEq(checkpointKey, blockTimestamp);
        assertEq(checkpointValue, shares - burnedShares);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1)), amount1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp)), amount1 - amount2);
        assertEq(vault.activeBalanceOf(alice), amount1 - amount2);
        assertEq(vault.withdrawals(vault.currentEpoch()), 0);
        assertEq(vault.withdrawals(vault.currentEpoch() + 1), amount2);
        assertEq(vault.withdrawals(vault.currentEpoch() + 2), 0);
        assertEq(vault.withdrawalShares(vault.currentEpoch()), 0);
        assertEq(vault.withdrawalShares(vault.currentEpoch() + 1), mintedShares);
        assertEq(vault.withdrawalShares(vault.currentEpoch() + 2), 0);
        assertEq(vault.withdrawalSharesOf(vault.currentEpoch(), alice), 0);
        assertEq(vault.withdrawalSharesOf(vault.currentEpoch() + 1, alice), mintedShares);
        assertEq(vault.withdrawalSharesOf(vault.currentEpoch() + 2, alice), 0);

        shares -= burnedShares;

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        burnedShares = amount3 * (shares + 10 ** 3) / (amount1 - amount2 + 1);
        mintedShares = amount3 * 10 ** 3;
        (burnedShares_, mintedShares_) = _withdraw(alice, amount3);
        assertEq(burnedShares_, burnedShares);
        assertEq(mintedShares_, mintedShares);

        assertEq(vault.totalSupplyIn(0), amount1);
        assertEq(vault.totalSupplyIn(1), amount1 - amount2);
        assertEq(vault.totalSupplyIn(2), amount1 - amount2 - amount3);
        assertEq(vault.totalSupply(), amount1);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1)), shares);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp)), shares - burnedShares);
        assertEq(vault.activeShares(), shares - burnedShares);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp - 1)), amount1 - amount2);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp)), amount1 - amount2 - amount3);
        assertEq(vault.activeSupply(), amount1 - amount2 - amount3);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1)), shares);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp)), shares - burnedShares);
        assertEq(vault.activeSharesOf(alice), shares - burnedShares);
        (checkpointExists, checkpointKey, checkpointValue) =
            vault.activeSharesOfCheckpointAt(alice, uint48(blockTimestamp));
        assertEq(checkpointExists, true);
        assertEq(checkpointKey, blockTimestamp);
        assertEq(checkpointValue, shares - burnedShares);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1)), amount1 - amount2);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp)), amount1 - amount2 - amount3);
        assertEq(vault.activeBalanceOf(alice), amount1 - amount2 - amount3);
        assertEq(vault.withdrawals(vault.currentEpoch() - 1), 0);
        assertEq(vault.withdrawals(vault.currentEpoch()), amount2);
        assertEq(vault.withdrawals(vault.currentEpoch() + 1), amount3);
        assertEq(vault.withdrawals(vault.currentEpoch() + 2), 0);
        assertEq(vault.withdrawalShares(vault.currentEpoch() - 1), 0);
        assertEq(vault.withdrawalShares(vault.currentEpoch()), amount2 * 10 ** 3);
        assertEq(vault.withdrawalShares(vault.currentEpoch() + 1), amount3 * 10 ** 3);
        assertEq(vault.withdrawalShares(vault.currentEpoch() + 2), 0);
        assertEq(vault.withdrawalSharesOf(vault.currentEpoch() - 1, alice), 0);
        assertEq(vault.withdrawalSharesOf(vault.currentEpoch(), alice), amount2 * 10 ** 3);
        assertEq(vault.withdrawalSharesOf(vault.currentEpoch() + 1, alice), amount3 * 10 ** 3);
        assertEq(vault.withdrawalSharesOf(vault.currentEpoch() + 2, alice), 0);

        shares -= burnedShares;

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.totalSupplyIn(0), amount1 - amount2);
        assertEq(vault.totalSupplyIn(1), amount1 - amount2 - amount3);
        assertEq(vault.totalSupplyIn(2), amount1 - amount2 - amount3);
        assertEq(vault.totalSupply(), amount1 - amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.totalSupplyIn(0), amount1 - amount2 - amount3);
        assertEq(vault.totalSupplyIn(1), amount1 - amount2 - amount3);
        assertEq(vault.totalSupplyIn(2), amount1 - amount2 - amount3);
        assertEq(vault.totalSupply(), amount1 - amount2 - amount3);
    }

    function test_WithdrawRevertInsufficientWithdrawal(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.InsufficientWithdrawal.selector);
        _withdraw(alice, 0);
    }

    function test_WithdrawRevertTooMuchWithdraw(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.TooMuchWithdraw.selector);
        _withdraw(alice, amount1 + 1);
    }

    function test_Claim(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256 tokensBefore = collateral.balanceOf(address(vault));
        uint256 tokensBeforeAlice = collateral.balanceOf(alice);
        assertEq(_claim(alice, vault.currentEpoch() - 1), amount2);
        assertEq(tokensBefore - collateral.balanceOf(address(vault)), amount2);
        assertEq(collateral.balanceOf(alice) - tokensBeforeAlice, amount2);

        assertEq(vault.isWithdrawalsClaimed(vault.currentEpoch() - 1, alice), true);
    }

    function test_ClaimRevertInvalidEpoch(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256 currentEpoch = vault.currentEpoch();
        vm.expectRevert(IVault.InvalidEpoch.selector);
        _claim(alice, currentEpoch);
    }

    function test_ClaimRevertAlreadyClaimed(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256 currentEpoch = vault.currentEpoch();
        _claim(alice, currentEpoch - 1);

        vm.expectRevert(IVault.AlreadyClaimed.selector);
        _claim(alice, currentEpoch - 1);
    }

    function test_ClaimRevertInsufficientClaim(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint48 epochDuration = 1;
        vault = _getVault(epochDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256 currentEpoch = vault.currentEpoch();
        vm.expectRevert(IVault.InsufficientClaim.selector);
        _claim(alice, currentEpoch - 2);
    }

    function test_CreateRevertInvalidEpochDuration() public {
        uint48 epochDuration = 0;

        uint64 lastVersion = vaultFactory.lastVersion();
        vm.expectRevert(IVault.InvalidEpochDuration.selector);
        vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: lastVersion,
                owner: alice,
                vaultParams: IVault.InitParams({
                    collateral: address(collateral),
                    delegator: address(0),
                    slasher: address(0),
                    burner: address(0xdEaD),
                    epochDuration: epochDuration,
                    slasherSetEpochsDelay: 3,
                    depositWhitelist: false,
                    defaultAdminRoleHolder: alice,
                    slasherSetRoleHolder: alice,
                    depositorWhitelistRoleHolder: alice
                }),
                delegatorIndex: 0,
                delegatorParams: abi.encode(
                    INetworkRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({defaultAdminRoleHolder: alice}),
                        networkLimitSetRoleHolder: alice,
                        operatorNetworkSharesSetRoleHolder: alice
                    })
                ),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: ""
            })
        );
    }

    function test_SetDepositWhitelist() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);
        assertEq(vault.depositWhitelist(), true);

        _setDepositWhitelist(alice, false);
        assertEq(vault.depositWhitelist(), false);
    }

    function test_SetDepositWhitelistRevertNotWhitelistedDepositor() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _deposit(alice, 1);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        vm.startPrank(alice);
        vm.expectRevert(IVault.NotWhitelistedDepositor.selector);
        vault.deposit(alice, 1);
        vm.stopPrank();
    }

    function test_SetDepositWhitelistRevertAlreadySet() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setDepositWhitelist(alice, true);
    }

    function test_SetDepositorWhitelistStatus() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        _grantDepositorWhitelistRole(alice, alice);

        _setDepositorWhitelistStatus(alice, bob, true);
        assertEq(vault.isDepositorWhitelisted(bob), true);

        _deposit(bob, 1);

        _setDepositWhitelist(alice, false);

        _deposit(bob, 1);
    }

    function test_SetDepositorWhitelistStatusRevertNoDepositWhitelist() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantDepositorWhitelistRole(alice, alice);

        vm.expectRevert(IVault.NoDepositWhitelist.selector);
        _setDepositorWhitelistStatus(alice, bob, true);
    }

    function test_SetDepositorWhitelistStatusRevertAlreadySet() public {
        uint48 epochDuration = 1;

        vault = _getVault(epochDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        _grantDepositorWhitelistRole(alice, alice);

        _setDepositorWhitelistStatus(alice, bob, true);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setDepositorWhitelistStatus(alice, bob, true);
    }

    function _getVault(uint48 epochDuration) internal returns (Vault) {
        (address vault_,,) = vaultConfigurator.create(
            IVaultConfigurator.InitParams({
                version: vaultFactory.lastVersion(),
                owner: alice,
                vaultParams: IVault.InitParams({
                    collateral: address(collateral),
                    delegator: address(0),
                    slasher: address(0),
                    burner: address(0xdEaD),
                    epochDuration: epochDuration,
                    slasherSetEpochsDelay: 3,
                    depositWhitelist: false,
                    defaultAdminRoleHolder: alice,
                    slasherSetRoleHolder: alice,
                    depositorWhitelistRoleHolder: alice
                }),
                delegatorIndex: 0,
                delegatorParams: abi.encode(
                    INetworkRestakeDelegator.InitParams({
                        baseParams: IBaseDelegator.BaseParams({defaultAdminRoleHolder: alice}),
                        networkLimitSetRoleHolder: alice,
                        operatorNetworkSharesSetRoleHolder: alice
                    })
                ),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: ""
            })
        );

        return Vault(vault_);
    }

    function _registerOperator(address user) internal {
        vm.startPrank(user);
        operatorRegistry.registerOperator();
        vm.stopPrank();
    }

    function _registerNetwork(address user, address middleware) internal {
        vm.startPrank(user);
        networkRegistry.registerNetwork();
        networkMiddlewareService.setMiddleware(middleware);
        vm.stopPrank();
    }

    function _grantDepositorWhitelistRole(address user, address account) internal {
        vm.startPrank(user);
        Vault(address(vault)).grantRole(vault.DEPOSITOR_WHITELIST_ROLE(), account);
        vm.stopPrank();
    }

    function _grantDepositWhitelistSetRole(address user, address account) internal {
        vm.startPrank(user);
        Vault(address(vault)).grantRole(vault.DEPOSIT_WHITELIST_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _deposit(address user, uint256 amount) internal returns (uint256 shares) {
        collateral.transfer(user, amount);
        vm.startPrank(user);
        collateral.approve(address(vault), amount);
        shares = vault.deposit(user, amount);
        vm.stopPrank();
    }

    function _withdraw(address user, uint256 amount) internal returns (uint256 burnedShares, uint256 mintedShares) {
        vm.startPrank(user);
        (burnedShares, mintedShares) = vault.withdraw(user, amount);
        vm.stopPrank();
    }

    function _claim(address user, uint256 epoch) internal returns (uint256 amount) {
        vm.startPrank(user);
        amount = vault.claim(user, epoch);
        vm.stopPrank();
    }

    function _optInNetworkVault(address user) internal {
        vm.startPrank(user);
        networkVaultOptInService.optIn(address(vault));
        vm.stopPrank();
    }

    function _optOutNetworkVault(address user) internal {
        vm.startPrank(user);
        networkVaultOptInService.optOut(address(vault));
        vm.stopPrank();
    }

    function _optInOperatorVault(address user) internal {
        vm.startPrank(user);
        operatorVaultOptInService.optIn(address(vault));
        vm.stopPrank();
    }

    function _optOutOperatorVault(address user) internal {
        vm.startPrank(user);
        operatorVaultOptInService.optOut(address(vault));
        vm.stopPrank();
    }

    function _optInOperatorNetwork(address user, address network) internal {
        vm.startPrank(user);
        operatorNetworkOptInService.optIn(network);
        vm.stopPrank();
    }

    function _optOutOperatorNetwork(address user, address network) internal {
        vm.startPrank(user);
        operatorNetworkOptInService.optOut(network);
        vm.stopPrank();
    }

    function _setDepositWhitelist(address user, bool depositWhitelist) internal {
        vm.startPrank(user);
        vault.setDepositWhitelist(depositWhitelist);
        vm.stopPrank();
    }

    function _setDepositorWhitelistStatus(address user, address depositor, bool status) internal {
        vm.startPrank(user);
        vault.setDepositorWhitelistStatus(depositor, status);
        vm.stopPrank();
    }
}
