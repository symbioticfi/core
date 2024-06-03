// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {VaultFactory} from "src/contracts/VaultFactory.sol";
import {NetworkRegistry} from "src/contracts/NetworkRegistry.sol";
import {OperatorRegistry} from "src/contracts/OperatorRegistry.sol";
import {MetadataService} from "src/contracts/MetadataService.sol";
import {NetworkMiddlewareService} from "src/contracts/NetworkMiddlewareService.sol";
import {NetworkOptInService} from "src/contracts/NetworkOptInService.sol";
import {OperatorOptInService} from "src/contracts/OperatorOptInService.sol";

import {Vault} from "src/contracts/vault/v1/Vault.sol";
import {IVault} from "src/interfaces/vault/v1/IVault.sol";
import {IVaultStorage} from "src/interfaces/vault/v1/IVaultStorage.sol";

import {Token} from "./mocks/Token.sol";
import {SimpleCollateral} from "./mocks/SimpleCollateral.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract VaultTest is Test {
    using Math for uint256;

    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    VaultFactory vaultFactory;
    NetworkRegistry networkRegistry;
    OperatorRegistry operatorRegistry;
    MetadataService operatorMetadataService;
    MetadataService networkMetadataService;
    NetworkMiddlewareService networkMiddlewareService;
    NetworkOptInService networkVaultOptInService;
    OperatorOptInService operatorVaultOptInService;
    OperatorOptInService operatorNetworkOptInService;

    IVault vault;

    SimpleCollateral collateral;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        vaultFactory = new VaultFactory(owner);
        networkRegistry = new NetworkRegistry();
        operatorRegistry = new OperatorRegistry();
        operatorMetadataService = new MetadataService(address(operatorRegistry));
        networkMetadataService = new MetadataService(address(networkRegistry));
        networkMiddlewareService = new NetworkMiddlewareService(address(networkRegistry));
        networkVaultOptInService = new NetworkOptInService(address(networkRegistry), address(vaultFactory));
        operatorVaultOptInService = new OperatorOptInService(address(operatorRegistry), address(vaultFactory));
        operatorNetworkOptInService = new OperatorOptInService(address(operatorRegistry), address(networkRegistry));

        vaultFactory.whitelist(
            address(
                new Vault(
                    address(vaultFactory),
                    address(networkRegistry),
                    address(networkMiddlewareService),
                    address(networkVaultOptInService),
                    address(operatorVaultOptInService),
                    address(operatorNetworkOptInService)
                )
            )
        );

        Token token = new Token("Token");
        collateral = new SimpleCollateral(address(token));

        collateral.mint(token.totalSupply());
    }

    function test_Create(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint48 executeDuration,
        address rewardsDistributor,
        uint256 adminFee,
        bool depositWhitelist
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        executeDuration = uint48(bound(executeDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration + executeDuration <= epochDuration);
        adminFee = bound(adminFee, 0, 10_000);

        vault = IVault(
            vaultFactory.create(
                vaultFactory.lastVersion(),
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        epochDuration: epochDuration,
                        vetoDuration: vetoDuration,
                        executeDuration: executeDuration,
                        rewardsDistributor: rewardsDistributor,
                        adminFee: adminFee,
                        depositWhitelist: depositWhitelist
                    })
                )
            )
        );

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        assertEq(vault.ADMIN_FEE_BASE(), 10_000);
        assertEq(vault.NETWORK_RESOLVER_LIMIT_SET_ROLE(), keccak256("NETWORK_RESOLVER_LIMIT_SET_ROLE"));
        assertEq(vault.OPERATOR_NETWORK_LIMIT_SET_ROLE(), keccak256("OPERATOR_NETWORK_LIMIT_SET_ROLE"));
        assertEq(vault.NETWORK_REGISTRY(), address(networkRegistry));

        assertEq(vault.collateral(), address(collateral));
        assertEq(vault.epochDurationInit(), blockTimestamp);
        assertEq(vault.epochDuration(), epochDuration);
        vm.expectRevert(IVaultStorage.InvalidTimestamp.selector);
        assertEq(vault.epochAt(0), 0);
        assertEq(vault.epochAt(uint48(blockTimestamp)), 0);
        assertEq(vault.currentEpoch(), 0);
        assertEq(vault.currentEpochStart(), blockTimestamp);
        vm.expectRevert(IVaultStorage.NoPreviousEpoch.selector);
        vault.previousEpochStart();
        assertEq(vault.vetoDuration(), vetoDuration);
        assertEq(vault.executeDuration(), executeDuration);
        assertEq(vault.totalSupplyIn(0), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp)), 0);
        assertEq(vault.activeShares(), 0);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp)), 0);
        assertEq(vault.activeSupply(), 0);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp)), 0);
        assertEq(vault.activeSharesOf(alice), 0);
        assertEq(vault.activeSharesOfCheckpointsLength(alice), 0);
        vm.expectRevert();
        vault.activeSharesOfCheckpoint(alice, 0);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp)), 0);
        assertEq(vault.activeBalanceOf(alice), 0);
        assertEq(vault.withdrawals(0), 0);
        assertEq(vault.withdrawalShares(0), 0);
        assertEq(vault.pendingWithdrawalSharesOf(0, alice), 0);
        assertEq(vault.firstDepositAt(alice), 0);
        assertEq(vault.slashableAmount(address(0), address(0), address(0)), 0);
        assertEq(vault.slashRequestsLength(), 0);
        vm.expectRevert();
        vault.slashRequests(0);
        assertEq(vault.maxNetworkResolverLimit(address(0), address(0)), 0);
        assertEq(vault.networkResolverLimitIn(address(0), address(0), 1), 0);
        assertEq(vault.networkResolverLimit(address(0), address(0)), 0);
        (uint256 nextNetworkResolverLimitAmount, uint256 nextNetworkResolverLimitTimestamp) =
            vault.nextNetworkResolverLimit(address(0), address(0));
        assertEq(nextNetworkResolverLimitAmount, 0);
        assertEq(nextNetworkResolverLimitTimestamp, 0);
        assertEq(vault.operatorNetworkLimitIn(address(0), address(0), 1), 0);
        assertEq(vault.operatorNetworkLimit(address(0), address(0)), 0);
        (uint256 nextOperatorNetworkLimitAmount, uint256 nextOperatorNetworkLimitTimestamp) =
            vault.nextOperatorNetworkLimit(address(0), address(0));
        assertEq(nextOperatorNetworkLimitAmount, 0);
        assertEq(nextOperatorNetworkLimitTimestamp, 0);
        assertEq(vault.minStakeDuring(address(0), address(0), address(0), 1), 0);
        assertEq(vault.adminFee(), adminFee);
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
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

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
        assertEq(vault.activeSharesOfCheckpointsLength(alice), 1);
        assertEq(vault.activeSharesOfAtHint(alice, uint48(blockTimestamp), 0), shares1);
        (uint48 timestampCheckpoint, uint256 valueCheckpoint) = vault.activeSharesOfCheckpoint(alice, 0);
        assertEq(timestampCheckpoint, blockTimestamp);
        assertEq(valueCheckpoint, shares1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1)), 0);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp)), amount1);
        assertEq(vault.activeBalanceOf(alice), amount1);
        assertEq(vault.firstDepositAt(alice), uint48(blockTimestamp));

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
        assertEq(vault.activeSharesOfCheckpointsLength(alice), 2);
        uint256 gasLeft = gasleft();
        assertEq(vault.activeSharesOfAtHint(alice, uint48(blockTimestamp - 1), 1), shares1);
        uint256 gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAtHint(alice, uint48(blockTimestamp - 1), 0), shares1);
        assertGt(gasSpent, gasLeft - gasleft());
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAtHint(alice, uint48(blockTimestamp), 0), shares1 + shares2);
        gasSpent = gasLeft - gasleft();
        gasLeft = gasleft();
        assertEq(vault.activeSharesOfAtHint(alice, uint48(blockTimestamp), 1), shares1 + shares2);
        assertGt(gasSpent, gasLeft - gasleft());
        (timestampCheckpoint, valueCheckpoint) = vault.activeSharesOfCheckpoint(alice, 0);
        assertEq(timestampCheckpoint, blockTimestamp - 1);
        assertEq(valueCheckpoint, shares1);
        (timestampCheckpoint, valueCheckpoint) = vault.activeSharesOfCheckpoint(alice, 1);
        assertEq(timestampCheckpoint, blockTimestamp);
        assertEq(valueCheckpoint, shares1 + shares2);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1)), amount1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp)), amount1 + amount2);
        assertEq(vault.activeBalanceOf(alice), amount1 + amount2);
        assertEq(vault.firstDepositAt(alice), uint48(blockTimestamp - 1));
    }

    function test_DepositBoth(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

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
        assertEq(vault.activeSharesOfCheckpointsLength(alice), 1);
        (uint48 timestampCheckpoint, uint256 valueCheckpoint) = vault.activeSharesOfCheckpoint(alice, 0);
        assertEq(timestampCheckpoint, blockTimestamp - 1);
        assertEq(valueCheckpoint, shares1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1)), amount1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp)), amount1);
        assertEq(vault.activeBalanceOf(alice), amount1);
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp - 1)), 0);
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp)), shares2);
        assertEq(vault.activeSharesOf(bob), shares2);
        assertEq(vault.activeSharesOfCheckpointsLength(bob), 1);
        (timestampCheckpoint, valueCheckpoint) = vault.activeSharesOfCheckpoint(bob, 0);
        assertEq(timestampCheckpoint, blockTimestamp);
        assertEq(valueCheckpoint, shares2);
        assertEq(vault.activeBalanceOfAt(bob, uint48(blockTimestamp - 1)), 0);
        assertEq(vault.activeBalanceOfAt(bob, uint48(blockTimestamp)), amount2);
        assertEq(vault.activeBalanceOf(bob), amount2);
    }

    function test_DepositRevertInsufficientDeposit() public {
        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

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
        // uint48 vetoDuration = 0;
        // uint48 executeDuration = 1;
        vault = _getVault(1, 0, 1);

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
        assertEq(vault.activeSharesOfCheckpointsLength(alice), 2);
        (uint48 timestampCheckpoint, uint256 valueCheckpoint) = vault.activeSharesOfCheckpoint(alice, 1);
        assertEq(timestampCheckpoint, blockTimestamp);
        assertEq(valueCheckpoint, shares - burnedShares);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1)), amount1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp)), amount1 - amount2);
        assertEq(vault.activeBalanceOf(alice), amount1 - amount2);
        assertEq(vault.withdrawals(vault.currentEpoch()), 0);
        assertEq(vault.withdrawals(vault.currentEpoch() + 1), amount2);
        assertEq(vault.withdrawals(vault.currentEpoch() + 2), 0);
        assertEq(vault.withdrawalShares(vault.currentEpoch()), 0);
        assertEq(vault.withdrawalShares(vault.currentEpoch() + 1), mintedShares);
        assertEq(vault.withdrawalShares(vault.currentEpoch() + 2), 0);
        assertEq(vault.pendingWithdrawalSharesOf(vault.currentEpoch(), alice), 0);
        assertEq(vault.pendingWithdrawalSharesOf(vault.currentEpoch() + 1, alice), mintedShares);
        assertEq(vault.pendingWithdrawalSharesOf(vault.currentEpoch() + 2, alice), 0);

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
        assertEq(vault.activeSharesOfCheckpointsLength(alice), 3);
        (timestampCheckpoint, valueCheckpoint) = vault.activeSharesOfCheckpoint(alice, 2);
        assertEq(timestampCheckpoint, blockTimestamp);
        assertEq(valueCheckpoint, shares - burnedShares);
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
        assertEq(vault.pendingWithdrawalSharesOf(vault.currentEpoch() - 1, alice), 0);
        assertEq(vault.pendingWithdrawalSharesOf(vault.currentEpoch(), alice), amount2 * 10 ** 3);
        assertEq(vault.pendingWithdrawalSharesOf(vault.currentEpoch() + 1, alice), amount3 * 10 ** 3);
        assertEq(vault.pendingWithdrawalSharesOf(vault.currentEpoch() + 2, alice), 0);

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
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.InsufficientWithdrawal.selector);
        _withdraw(alice, 0);
    }

    function test_WithdrawRevertTooMuchWithdraw(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.TooMuchWithdraw.selector);
        _withdraw(alice, amount1 + 1);
    }

    function test_Claim(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

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

        assertEq(vault.pendingWithdrawalSharesOf(vault.currentEpoch() - 1, alice), 0);
    }

    function test_ClaimRevertInvalidEpoch(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

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

    function test_ClaimRevertInsufficientClaim1(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        uint256 currentEpoch = vault.currentEpoch();
        _claim(alice, currentEpoch - 1);

        vm.expectRevert(IVault.InsufficientClaim.selector);
        _claim(alice, currentEpoch - 1);
    }

    function test_ClaimRevertInsufficientClaim2(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

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

    function test_RequestSlash(
        uint256 amount1,
        uint256 amount2,
        uint256 amount3,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        amount3 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount3);
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        // uint48 epochDuration = 3;
        // uint48 executeDuration = 1;
        // uint48 vetoDuration = 1;
        vault = _getVault(3, 1, 1);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        _deposit(bob, amount2);

        // address network = bob;
        _registerNetwork(bob, bob);

        // address operator = bob;
        _registerOperator(bob);

        // address resolver = address(1);
        _setMaxNetworkResolverLimit(bob, address(1), type(uint256).max);
        _optInNetworkVault(bob, address(1));

        _optInOperatorVault(bob);

        assertEq(vault.minStakeDuring(bob, address(1), bob, 3), 0);
        assertEq(vault.slashableAmountIn(bob, address(1), bob, 0), 0);
        assertEq(vault.slashableAmountIn(bob, address(1), bob, vault.epochDuration()), 0);
        assertEq(vault.slashableAmount(bob, address(1), bob), 0);

        _setNetworkResolverLimit(alice, bob, address(1), networkResolverLimit);

        assertEq(vault.minStakeDuring(bob, address(1), bob, 3), 0);
        assertEq(vault.slashableAmountIn(bob, address(1), bob, 0), 0);
        assertEq(vault.slashableAmountIn(bob, address(1), bob, vault.epochDuration()), 0);
        assertEq(vault.slashableAmount(bob, address(1), bob), 0);

        _setOperatorNetworkLimit(alice, bob, bob, operatorNetworkLimit);

        _optInOperatorNetwork(bob, bob);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _withdraw(alice, amount3);

        uint256 slashableAmount_ = Math.min(amount1 + amount2, Math.min(networkResolverLimit, operatorNetworkLimit));

        assertEq(
            vault.minStakeDuring(bob, address(1), bob, 3),
            Math.min(amount1 + amount2 - amount3, Math.min(networkResolverLimit, operatorNetworkLimit))
        );
        assertEq(vault.slashableAmountIn(bob, address(1), bob, 0), slashableAmount_);
        assertEq(vault.slashableAmountIn(bob, address(1), bob, vault.epochDuration()), slashableAmount_);
        assertEq(
            vault.slashableAmountIn(bob, address(1), bob, 2 * vault.epochDuration()),
            Math.min(amount1 + amount2 - amount3, Math.min(networkResolverLimit, operatorNetworkLimit))
        );
        assertEq(vault.slashableAmount(bob, address(1), bob), slashableAmount_);

        assertEq(_requestSlash(bob, bob, address(1), bob, toSlash), 0);
        assertEq(vault.slashRequestsLength(), 1);

        (
            address network_,
            address resolver_,
            address operator_,
            uint256 amount_,
            uint48 vetoDeadline_,
            uint48 executeDeadline_,
            bool completed_
        ) = vault.slashRequests(0);

        assertEq(network_, bob);
        assertEq(resolver_, address(1));
        assertEq(operator_, bob);
        assertEq(amount_, Math.min(slashableAmount_, toSlash));
        assertEq(vetoDeadline_, uint48(blockTimestamp + vault.vetoDuration()));
        assertEq(executeDeadline_, uint48(blockTimestamp + vault.vetoDuration() + vault.executeDuration()));
        assertEq(completed_, false);
    }

    function test_RequestSlashRevertNotNetworkMiddleware(
        uint256 amount1,
        uint256 amount2,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _setMaxNetworkResolverLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkResolverLimit(alice, network, resolver, networkResolverLimit);

        _setOperatorNetworkLimit(alice, operator, network, operatorNetworkLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.NotNetworkMiddleware.selector);
        _requestSlash(alice, network, resolver, operator, toSlash);
    }

    function test_RequestSlashRevertInsufficientSlash(
        uint256 amount1,
        uint256 amount2,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _setMaxNetworkResolverLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkResolverLimit(alice, network, resolver, networkResolverLimit);

        _setOperatorNetworkLimit(alice, operator, network, operatorNetworkLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.InsufficientSlash.selector);
        _requestSlash(bob, network, resolver, operator, 0);
    }

    function test_RequestSlashRevertNetworkNotOptedIn(
        uint256 amount1,
        uint256 amount2,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _setMaxNetworkResolverLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkResolverLimit(alice, network, resolver, networkResolverLimit);

        _optOutNetworkVault(network, resolver);

        _setOperatorNetworkLimit(alice, operator, network, operatorNetworkLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.NetworkNotOptedInVault.selector);
        _requestSlash(bob, network, resolver, operator, toSlash);
    }

    function test_RequestSlashRevertOperatorNotOptedInNetwork(
        uint256 amount1,
        uint256 amount2,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _setMaxNetworkResolverLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkResolverLimit(alice, network, resolver, networkResolverLimit);

        _setOperatorNetworkLimit(alice, operator, network, operatorNetworkLimit);

        _optInOperatorNetwork(operator, network);

        _optOutOperatorNetwork(operator, network);

        blockTimestamp = vault.currentEpochStart() + 2 * vault.epochDuration();
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.OperatorNotOptedInNetwork.selector);
        _requestSlash(bob, network, resolver, operator, toSlash);
    }

    function test_RequestSlashRevertOperatorNotOptedInVault(
        uint256 amount1,
        uint256 amount2,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _setMaxNetworkResolverLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _optOutOperatorVault(operator);

        _setNetworkResolverLimit(alice, network, resolver, networkResolverLimit);

        _setOperatorNetworkLimit(alice, operator, network, operatorNetworkLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = vault.currentEpochStart() + 2 * vault.epochDuration();
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.OperatorNotOptedInVault.selector);
        _requestSlash(bob, network, resolver, operator, toSlash);
    }

    function test_ExecuteSlash(
        uint256 amount1,
        uint256 amount2,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        // uint48 epochDuration = 3;
        // uint48 executeDuration = 1;
        // uint48 vetoDuration = 1;
        vault = _getVault(3, 1, 1);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares1 = _deposit(alice, amount1);

        uint256 shares2 = _deposit(bob, amount2);

        // address network = bob;
        _registerNetwork(bob, bob);

        // address operator = bob;
        _registerOperator(bob);

        // address resolver = alice;
        _setMaxNetworkResolverLimit(bob, alice, type(uint256).max);
        _optInNetworkVault(bob, alice);

        _optInOperatorVault(bob);

        _setNetworkResolverLimit(alice, bob, alice, networkResolverLimit);

        _setOperatorNetworkLimit(alice, bob, bob, operatorNetworkLimit);

        _optInOperatorNetwork(bob, bob);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashIndex = _requestSlash(bob, bob, alice, bob, toSlash);

        (,,, uint256 amount_,,,) = vault.slashRequests(slashIndex);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 activeSupply_ = vault.activeSupply();

        assertEq(_executeSlash(address(1), slashIndex), amount_);
        assertEq(activeSupply_ - amount_.mulDiv(activeSupply_, amount1 + amount2), vault.activeSupply());

        (,,,,,, bool completed__) = vault.slashRequests(slashIndex);

        assertEq(completed__, true);

        assertEq(vault.totalSupply(), amount1 + amount2 - amount_);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1)), shares1 + shares2);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp)), shares1 + shares2);
        assertEq(vault.activeShares(), shares1 + shares2);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp - 1)), amount1 + amount2);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp)), amount1 + amount2 - amount_);
        assertEq(vault.activeSupply(), amount1 + amount2 - amount_);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1)), shares1);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp)), shares1);
        assertEq(vault.activeSharesOf(alice), shares1);
        assertEq(vault.activeSharesOfCheckpointsLength(alice), 1);
        (uint48 timestampCheckpoint, uint256 valueCheckpoint) = vault.activeSharesOfCheckpoint(alice, 0);
        assertEq(timestampCheckpoint, blockTimestamp - 2);
        assertEq(valueCheckpoint, shares1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1)), amount1);
        assertEq(
            vault.activeBalanceOfAt(alice, uint48(blockTimestamp)),
            shares1.mulDiv(vault.activeSupply() + 1, vault.activeShares() + 10 ** 3)
        );
        assertEq(vault.activeBalanceOf(alice), shares1.mulDiv(vault.activeSupply() + 1, vault.activeShares() + 10 ** 3));
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp - 1)), shares2);
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp)), shares2);
        assertEq(vault.activeSharesOf(bob), shares2);
        assertEq(vault.activeSharesOfCheckpointsLength(bob), 1);
        (timestampCheckpoint, valueCheckpoint) = vault.activeSharesOfCheckpoint(bob, 0);
        assertEq(timestampCheckpoint, blockTimestamp - 2);
        assertEq(valueCheckpoint, shares2);
        assertEq(vault.activeBalanceOfAt(bob, uint48(blockTimestamp - 1)), amount2);
        assertEq(
            vault.activeBalanceOfAt(bob, uint48(blockTimestamp)),
            shares2.mulDiv(vault.activeSupply() + 1, vault.activeShares() + 10 ** 3)
        );
        assertEq(vault.activeBalanceOf(bob), shares2.mulDiv(vault.activeSupply() + 1, vault.activeShares() + 10 ** 3));
    }

    function test_ExecuteSlashNoResolver(
        uint256 amount1,
        uint256 amount2,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        // uint48 epochDuration = 3;
        // uint48 executeDuration = 1;
        // uint48 vetoDuration = 1;
        vault = _getVault(3, 1, 1);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares1 = _deposit(alice, amount1);

        uint256 shares2 = _deposit(bob, amount2);

        // address network = bob;
        _registerNetwork(bob, bob);

        // address operator = bob;
        _registerOperator(bob);

        // address resolver = address(0);
        _setMaxNetworkResolverLimit(bob, address(0), type(uint256).max);
        _optInNetworkVault(bob, address(0));

        _optInOperatorVault(bob);

        _setNetworkResolverLimit(alice, bob, address(0), networkResolverLimit);

        _setOperatorNetworkLimit(alice, bob, bob, operatorNetworkLimit);

        _optInOperatorNetwork(bob, bob);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashIndex = _requestSlash(bob, bob, address(0), bob, toSlash);

        (,,, uint256 amount_,,,) = vault.slashRequests(slashIndex);

        uint256 activeSupply_ = vault.activeSupply();

        assertEq(_executeSlash(address(1), slashIndex), amount_);
        assertEq(activeSupply_ - amount_.mulDiv(activeSupply_, amount1 + amount2), vault.activeSupply());

        (,,,,,, bool completed__) = vault.slashRequests(slashIndex);

        assertEq(completed__, true);

        assertEq(vault.totalSupply(), amount1 + amount2 - amount_);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1)), shares1 + shares2);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp)), shares1 + shares2);
        assertEq(vault.activeShares(), shares1 + shares2);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp - 1)), amount1 + amount2);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp)), amount1 + amount2 - amount_);
        assertEq(vault.activeSupply(), amount1 + amount2 - amount_);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1)), shares1);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp)), shares1);
        assertEq(vault.activeSharesOf(alice), shares1);
        assertEq(vault.activeSharesOfCheckpointsLength(alice), 1);
        (uint48 timestampCheckpoint, uint256 valueCheckpoint) = vault.activeSharesOfCheckpoint(alice, 0);
        assertEq(timestampCheckpoint, blockTimestamp - 1);
        assertEq(valueCheckpoint, shares1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1)), amount1);
        assertEq(
            vault.activeBalanceOfAt(alice, uint48(blockTimestamp)),
            shares1.mulDiv(vault.activeSupply() + 1, vault.activeShares() + 10 ** 3)
        );
        assertEq(vault.activeBalanceOf(alice), shares1.mulDiv(vault.activeSupply() + 1, vault.activeShares() + 10 ** 3));
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp - 1)), shares2);
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp)), shares2);
        assertEq(vault.activeSharesOf(bob), shares2);
        assertEq(vault.activeSharesOfCheckpointsLength(bob), 1);
        (timestampCheckpoint, valueCheckpoint) = vault.activeSharesOfCheckpoint(bob, 0);
        assertEq(timestampCheckpoint, blockTimestamp - 1);
        assertEq(valueCheckpoint, shares2);
        assertEq(vault.activeBalanceOfAt(bob, uint48(blockTimestamp - 1)), amount2);
        assertEq(
            vault.activeBalanceOfAt(bob, uint48(blockTimestamp)),
            shares2.mulDiv(vault.activeSupply() + 1, vault.activeShares() + 10 ** 3)
        );
        assertEq(vault.activeBalanceOf(bob), shares2.mulDiv(vault.activeSupply() + 1, vault.activeShares() + 10 ** 3));
    }

    function test_ExecuteSlashEdgeCase(uint256 networkResolverLimit, uint256 operatorNetworkLimit) public {
        uint256 toDeposit = 2;
        uint256 toWithdraw = 1;
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        uint256 toSlash = 1;

        // uint48 epochDuration = 3;
        // uint48 executeDuration = 1;
        // uint48 vetoDuration = 1;
        vault = _getVault(3, 1, 1);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, toDeposit);
        (uint256 burnedShares,) = _withdraw(alice, toWithdraw);

        // address network = bob;
        _registerNetwork(bob, bob);

        // address operator = bob;
        _registerOperator(bob);

        // address resolver = alice;
        _setMaxNetworkResolverLimit(bob, alice, type(uint256).max);
        _optInNetworkVault(bob, alice);

        _optInOperatorVault(bob);

        _setNetworkResolverLimit(alice, bob, alice, networkResolverLimit);

        _setOperatorNetworkLimit(alice, bob, bob, operatorNetworkLimit);

        _optInOperatorNetwork(bob, bob);

        blockTimestamp = blockTimestamp + 3;
        vm.warp(blockTimestamp);

        uint256 slashIndex = _requestSlash(bob, bob, alice, bob, toSlash);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(_executeSlash(address(1), slashIndex), 0);
        assertEq(1, vault.activeSupply());

        (,,,,,, bool completed__) = vault.slashRequests(slashIndex);

        assertEq(completed__, true);

        assertEq(vault.totalSupply(), 2);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp - 1)), shares - burnedShares);
        assertEq(vault.activeSharesAt(uint48(blockTimestamp)), shares - burnedShares);
        assertEq(vault.activeShares(), shares - burnedShares);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp - 1)), 1);
        assertEq(vault.activeSupplyAt(uint48(blockTimestamp)), 1);
        assertEq(vault.activeSupply(), 1);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp - 1)), shares - burnedShares);
        assertEq(vault.activeSharesOfAt(alice, uint48(blockTimestamp)), shares - burnedShares);
        assertEq(vault.activeSharesOf(alice), shares - burnedShares);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1)), 1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp)), 1);
        assertEq(vault.activeBalanceOf(alice), 1);
    }

    function test_ExecuteSlashRevertSlashRequestNotExist(
        uint256 amount1,
        uint256 amount2,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkResolverLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkResolverLimit(alice, network, resolver, networkResolverLimit);

        _setOperatorNetworkLimit(alice, operator, network, operatorNetworkLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashIndex = _requestSlash(bob, network, resolver, operator, toSlash);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.SlashRequestNotExist.selector);
        _executeSlash(address(1), slashIndex + 1);
    }

    function test_ExecuteSlashRevertVetoPeriodNotEnded(
        uint256 amount1,
        uint256 amount2,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkResolverLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkResolverLimit(alice, network, resolver, networkResolverLimit);

        _setOperatorNetworkLimit(alice, operator, network, operatorNetworkLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashIndex = _requestSlash(bob, network, resolver, operator, toSlash);

        vm.expectRevert(IVault.VetoPeriodNotEnded.selector);
        _executeSlash(address(1), slashIndex);
    }

    function test_ExecuteSlashRevertSlashPeriodEnded(
        uint256 amount1,
        uint256 amount2,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkResolverLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkResolverLimit(alice, network, resolver, networkResolverLimit);

        _setOperatorNetworkLimit(alice, operator, network, operatorNetworkLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashIndex = _requestSlash(bob, network, resolver, operator, toSlash);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.SlashPeriodEnded.selector);
        _executeSlash(address(1), slashIndex);
    }

    function test_ExecuteSlashRevertSlashCompleted(
        uint256 amount1,
        uint256 amount2,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkResolverLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkResolverLimit(alice, network, resolver, networkResolverLimit);

        _setOperatorNetworkLimit(alice, operator, network, operatorNetworkLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashIndex = _requestSlash(bob, network, resolver, operator, toSlash);

        _vetoSlash(resolver, slashIndex);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.SlashCompleted.selector);
        _executeSlash(address(1), slashIndex);
    }

    function test_VetoSlash(
        uint256 amount1,
        uint256 amount2,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkResolverLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkResolverLimit(alice, network, resolver, networkResolverLimit);

        _setOperatorNetworkLimit(alice, operator, network, operatorNetworkLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashIndex = _requestSlash(bob, network, resolver, operator, toSlash);

        (
            address network_,
            address resolver_,
            address operator_,
            uint256 amount_,
            uint48 vetoDeadline_,
            uint48 executeDeadline_,
        ) = vault.slashRequests(slashIndex);

        _vetoSlash(resolver, slashIndex);

        (
            address network__,
            address resolver__,
            address operator__,
            uint256 amount__,
            uint48 vetoDeadline__,
            uint48 executeDeadline__,
            bool completed__
        ) = vault.slashRequests(slashIndex);

        assertEq(network__, network_);
        assertEq(resolver__, resolver_);
        assertEq(operator__, operator_);
        assertEq(amount__, amount_);
        assertEq(vetoDeadline__, vetoDeadline_);
        assertEq(executeDeadline__, executeDeadline_);
        assertEq(completed__, true);
    }

    function test_VetoSlashRevertSlashRequestNotExist(
        uint256 amount1,
        uint256 amount2,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkResolverLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkResolverLimit(alice, network, resolver, networkResolverLimit);

        _setOperatorNetworkLimit(alice, operator, network, operatorNetworkLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashIndex = _requestSlash(bob, network, resolver, operator, toSlash);

        vm.expectRevert(IVault.SlashRequestNotExist.selector);
        _vetoSlash(resolver, slashIndex + 1);
    }

    function test_VetoSlashRevertNotResolver(
        uint256 amount1,
        uint256 amount2,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkResolverLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkResolverLimit(alice, network, resolver, networkResolverLimit);

        _setOperatorNetworkLimit(alice, operator, network, operatorNetworkLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashIndex = _requestSlash(bob, network, resolver, operator, toSlash);

        vm.expectRevert(IVault.NotResolver.selector);
        _vetoSlash(address(1), slashIndex);
    }

    function test_VetoSlashRevertVetoPeriodEnded(
        uint256 amount1,
        uint256 amount2,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkResolverLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkResolverLimit(alice, network, resolver, networkResolverLimit);

        _setOperatorNetworkLimit(alice, operator, network, operatorNetworkLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashIndex = _requestSlash(bob, network, resolver, operator, toSlash);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.VetoPeriodEnded.selector);
        _vetoSlash(resolver, slashIndex);
    }

    function test_VetoSlashRevertSlashCompleted(
        uint256 amount1,
        uint256 amount2,
        uint256 networkResolverLimit,
        uint256 operatorNetworkLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkResolverLimit = bound(networkResolverLimit, 1, type(uint256).max);
        operatorNetworkLimit = bound(operatorNetworkLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkResolverLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkResolverLimit(alice, network, resolver, networkResolverLimit);

        _setOperatorNetworkLimit(alice, operator, network, operatorNetworkLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashIndex = _requestSlash(bob, network, resolver, operator, toSlash);

        _vetoSlash(resolver, slashIndex);

        vm.expectRevert(IVault.SlashCompleted.selector);
        _vetoSlash(resolver, slashIndex);
    }

    function test_CreateRevertInvalidEpochDuration() public {
        uint48 epochDuration = 0;
        uint48 executeDuration = 0;
        uint48 vetoDuration = 0;

        uint64 lastVersion = vaultFactory.lastVersion();
        vm.expectRevert(IVault.InvalidEpochDuration.selector);
        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        epochDuration: epochDuration,
                        vetoDuration: vetoDuration,
                        executeDuration: executeDuration,
                        rewardsDistributor: address(0),
                        adminFee: 0,
                        depositWhitelist: false
                    })
                )
            )
        );
    }

    function test_CreateRevertInvalidSlashDuration(
        uint48 epochDuration,
        uint48 vetoDuration,
        uint48 executeDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        executeDuration = uint48(bound(executeDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration + executeDuration > epochDuration);

        uint64 lastVersion = vaultFactory.lastVersion();
        vm.expectRevert(IVault.InvalidSlashDuration.selector);
        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        epochDuration: epochDuration,
                        vetoDuration: vetoDuration,
                        executeDuration: executeDuration,
                        rewardsDistributor: address(0),
                        adminFee: 0,
                        depositWhitelist: false
                    })
                )
            )
        );
    }

    function test_CreateRevertInvalidAdminFee(uint256 adminFee) public {
        vm.assume(adminFee > 10_000);

        uint48 epochDuration = 1;
        uint48 executeDuration = 0;
        uint48 vetoDuration = 0;

        uint64 lastVersion = vaultFactory.lastVersion();
        vm.expectRevert(IVault.InvalidAdminFee.selector);
        vault = IVault(
            vaultFactory.create(
                lastVersion,
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        epochDuration: epochDuration,
                        vetoDuration: vetoDuration,
                        executeDuration: executeDuration,
                        rewardsDistributor: address(0),
                        adminFee: adminFee,
                        depositWhitelist: false
                    })
                )
            )
        );
    }

    function test_SetNetworkResolverLimit(
        uint48 epochDuration,
        uint256 amount1,
        uint256 amount2,
        uint256 amount3
    ) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        vm.assume(amount3 < amount2);

        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = address(1);
        _setMaxNetworkResolverLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _setNetworkResolverLimit(alice, network, resolver, amount1);

        assertEq(vault.networkResolverLimitIn(network, resolver, 1), amount1);
        assertEq(vault.networkResolverLimit(network, resolver), amount1);
        (uint256 nextNetworkResolverLimitAmount, uint256 nextNetworkResolverLimitTimestamp) =
            vault.nextNetworkResolverLimit(network, resolver);
        assertEq(nextNetworkResolverLimitAmount, 0);
        assertEq(nextNetworkResolverLimitTimestamp, 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.networkResolverLimitIn(network, resolver, 1), amount1);
        assertEq(vault.networkResolverLimit(network, resolver), amount1);
        (nextNetworkResolverLimitAmount, nextNetworkResolverLimitTimestamp) =
            vault.nextNetworkResolverLimit(network, resolver);
        assertEq(nextNetworkResolverLimitAmount, 0);
        assertEq(nextNetworkResolverLimitTimestamp, 0);

        _setNetworkResolverLimit(alice, network, resolver, amount2);

        if (amount1 > amount2) {
            assertEq(
                vault.networkResolverLimitIn(
                    network,
                    resolver,
                    uint48(vault.currentEpochStart() + 2 * vault.epochDuration() - 1 - blockTimestamp)
                ),
                amount1
            );
            assertEq(vault.networkResolverLimit(network, resolver), amount1);
            (nextNetworkResolverLimitAmount, nextNetworkResolverLimitTimestamp) =
                vault.nextNetworkResolverLimit(network, resolver);
            assertEq(nextNetworkResolverLimitAmount, amount2);
            assertEq(nextNetworkResolverLimitTimestamp, vault.currentEpochStart() + 2 * vault.epochDuration());

            blockTimestamp = vault.currentEpochStart() + 2 * vault.epochDuration() - 1;
            vm.warp(blockTimestamp);

            assertEq(vault.networkResolverLimitIn(network, resolver, 1), amount2);
            assertEq(vault.networkResolverLimit(network, resolver), amount1);
            (nextNetworkResolverLimitAmount, nextNetworkResolverLimitTimestamp) =
                vault.nextNetworkResolverLimit(network, resolver);
            assertEq(nextNetworkResolverLimitAmount, amount2);
            assertEq(nextNetworkResolverLimitTimestamp, vault.currentEpochStart() + vault.epochDuration());

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);

            assertEq(vault.networkResolverLimitIn(network, resolver, 1), amount2);
            assertEq(vault.networkResolverLimit(network, resolver), amount2);
            (nextNetworkResolverLimitAmount, nextNetworkResolverLimitTimestamp) =
                vault.nextNetworkResolverLimit(network, resolver);
            assertEq(nextNetworkResolverLimitAmount, amount2);
            assertEq(nextNetworkResolverLimitTimestamp, vault.currentEpochStart());

            _setNetworkResolverLimit(alice, network, resolver, amount2);

            assertEq(vault.networkResolverLimitIn(network, resolver, 1), amount2);
            assertEq(vault.networkResolverLimit(network, resolver), amount2);
            (nextNetworkResolverLimitAmount, nextNetworkResolverLimitTimestamp) =
                vault.nextNetworkResolverLimit(network, resolver);
            assertEq(nextNetworkResolverLimitAmount, 0);
            assertEq(nextNetworkResolverLimitTimestamp, 0);
        } else {
            assertEq(vault.networkResolverLimitIn(network, resolver, 1), amount2);
            assertEq(vault.networkResolverLimit(network, resolver), amount2);
            (nextNetworkResolverLimitAmount, nextNetworkResolverLimitTimestamp) =
                vault.nextNetworkResolverLimit(network, resolver);
            assertEq(nextNetworkResolverLimitAmount, 0);
            assertEq(nextNetworkResolverLimitTimestamp, 0);
        }

        _setNetworkResolverLimit(alice, network, resolver, amount3);

        assertEq(
            vault.networkResolverLimitIn(
                network, resolver, uint48(vault.currentEpochStart() + 2 * vault.epochDuration() - blockTimestamp)
            ),
            amount3
        );
        assertEq(vault.networkResolverLimit(network, resolver), amount2);
        (nextNetworkResolverLimitAmount, nextNetworkResolverLimitTimestamp) =
            vault.nextNetworkResolverLimit(network, resolver);
        assertEq(nextNetworkResolverLimitAmount, amount3);
        assertEq(nextNetworkResolverLimitTimestamp, vault.currentEpochStart() + 2 * vault.epochDuration());

        _setNetworkResolverLimit(alice, network, resolver, amount2);

        assertEq(
            vault.networkResolverLimitIn(
                network, resolver, uint48(vault.currentEpochStart() + 2 * vault.epochDuration() - blockTimestamp)
            ),
            amount2
        );
        assertEq(vault.networkResolverLimit(network, resolver), amount2);
        (nextNetworkResolverLimitAmount, nextNetworkResolverLimitTimestamp) =
            vault.nextNetworkResolverLimit(network, resolver);
        assertEq(nextNetworkResolverLimitAmount, 0);
        assertEq(nextNetworkResolverLimitTimestamp, 0);

        _optOutNetworkVault(network, resolver);

        assertEq(vault.networkResolverLimitIn(network, resolver, 1), amount2);
        assertEq(vault.networkResolverLimit(network, resolver), amount2);
        (nextNetworkResolverLimitAmount, nextNetworkResolverLimitTimestamp) =
            vault.nextNetworkResolverLimit(network, resolver);
        assertEq(nextNetworkResolverLimitAmount, 0);
        assertEq(nextNetworkResolverLimitTimestamp, 0);

        blockTimestamp = vault.currentEpochStart() + 2 * vault.epochDuration() - 1;
        vm.warp(blockTimestamp);

        assertEq(vault.networkResolverLimitIn(network, resolver, 1), amount2);
        assertEq(vault.networkResolverLimit(network, resolver), amount2);
        (nextNetworkResolverLimitAmount, nextNetworkResolverLimitTimestamp) =
            vault.nextNetworkResolverLimit(network, resolver);
        assertEq(nextNetworkResolverLimitAmount, 0);
        assertEq(nextNetworkResolverLimitTimestamp, 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.networkResolverLimitIn(network, resolver, 1), amount2);
        assertEq(vault.networkResolverLimit(network, resolver), amount2);
        (nextNetworkResolverLimitAmount, nextNetworkResolverLimitTimestamp) =
            vault.nextNetworkResolverLimit(network, resolver);
        assertEq(nextNetworkResolverLimitAmount, 0);
        assertEq(nextNetworkResolverLimitTimestamp, 0);
    }

    function test_SetNetworkResolverLimitRevertOnlyRole(uint48 epochDuration, uint256 amount1) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));

        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = address(1);
        _setMaxNetworkResolverLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        vm.expectRevert();
        _setNetworkResolverLimit(bob, network, resolver, amount1);
    }

    function test_SetNetworkResolverLimitRevertExceedsMaxNetworkResolverLimit(
        uint48 epochDuration,
        uint256 amount1,
        uint256 maxNetworkResolverLimit
    ) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        maxNetworkResolverLimit = bound(maxNetworkResolverLimit, 1, type(uint256).max);
        vm.assume(amount1 > maxNetworkResolverLimit);

        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = address(1);
        _setMaxNetworkResolverLimit(network, resolver, maxNetworkResolverLimit);
        _optInNetworkVault(network, resolver);

        vm.expectRevert(IVault.ExceedsMaxNetworkResolverLimit.selector);
        _setNetworkResolverLimit(alice, network, resolver, amount1);
    }

    function test_SetOperatorNetworkLimit(
        uint48 epochDuration,
        uint256 amount1,
        uint256 amount2,
        uint256 amount3
    ) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        vm.assume(amount3 < amount2);

        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address operator = bob;
        _registerOperator(operator);

        address network = address(1);
        _optInOperatorVault(operator);

        _setOperatorNetworkLimit(alice, operator, network, amount1);

        assertEq(vault.operatorNetworkLimitIn(operator, network, 1), amount1);
        assertEq(vault.operatorNetworkLimit(operator, network), amount1);
        (uint256 nextOperatorNetworkLimitAmount, uint256 nextOperatorNetworkLimitTimestamp) =
            vault.nextOperatorNetworkLimit(operator, network);
        assertEq(nextOperatorNetworkLimitAmount, 0);
        assertEq(nextOperatorNetworkLimitTimestamp, 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.operatorNetworkLimitIn(operator, network, 1), amount1);
        assertEq(vault.operatorNetworkLimit(operator, network), amount1);
        (nextOperatorNetworkLimitAmount, nextOperatorNetworkLimitTimestamp) =
            vault.nextOperatorNetworkLimit(operator, network);
        assertEq(nextOperatorNetworkLimitAmount, 0);
        assertEq(nextOperatorNetworkLimitTimestamp, 0);

        _setOperatorNetworkLimit(alice, operator, network, amount2);

        if (amount1 > amount2) {
            assertEq(
                vault.operatorNetworkLimitIn(
                    operator,
                    network,
                    uint48(vault.currentEpochStart() + 2 * vault.epochDuration() - 1 - blockTimestamp)
                ),
                amount1
            );
            assertEq(vault.operatorNetworkLimit(operator, network), amount1);
            (nextOperatorNetworkLimitAmount, nextOperatorNetworkLimitTimestamp) =
                vault.nextOperatorNetworkLimit(operator, network);
            assertEq(nextOperatorNetworkLimitAmount, amount2);
            assertEq(nextOperatorNetworkLimitTimestamp, vault.currentEpochStart() + 2 * vault.epochDuration());

            blockTimestamp = vault.currentEpochStart() + 2 * vault.epochDuration() - 1;
            vm.warp(blockTimestamp);

            assertEq(vault.operatorNetworkLimitIn(operator, network, 1), amount2);
            assertEq(vault.operatorNetworkLimit(operator, network), amount1);
            (nextOperatorNetworkLimitAmount, nextOperatorNetworkLimitTimestamp) =
                vault.nextOperatorNetworkLimit(operator, network);
            assertEq(nextOperatorNetworkLimitAmount, amount2);
            assertEq(nextOperatorNetworkLimitTimestamp, vault.currentEpochStart() + vault.epochDuration());

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);

            assertEq(vault.operatorNetworkLimitIn(operator, network, 1), amount2);
            assertEq(vault.operatorNetworkLimit(operator, network), amount2);
            (nextOperatorNetworkLimitAmount, nextOperatorNetworkLimitTimestamp) =
                vault.nextOperatorNetworkLimit(operator, network);
            assertEq(nextOperatorNetworkLimitAmount, amount2);
            assertEq(nextOperatorNetworkLimitTimestamp, vault.currentEpochStart());

            _setOperatorNetworkLimit(alice, operator, network, amount2);

            assertEq(vault.operatorNetworkLimitIn(operator, network, 1), amount2);
            assertEq(vault.operatorNetworkLimit(operator, network), amount2);
            (nextOperatorNetworkLimitAmount, nextOperatorNetworkLimitTimestamp) =
                vault.nextOperatorNetworkLimit(operator, network);
            assertEq(nextOperatorNetworkLimitAmount, 0);
            assertEq(nextOperatorNetworkLimitTimestamp, 0);
        } else {
            assertEq(vault.operatorNetworkLimitIn(operator, network, 1), amount2);
            assertEq(vault.operatorNetworkLimit(operator, network), amount2);
            (nextOperatorNetworkLimitAmount, nextOperatorNetworkLimitTimestamp) =
                vault.nextOperatorNetworkLimit(operator, network);
            assertEq(nextOperatorNetworkLimitAmount, 0);
            assertEq(nextOperatorNetworkLimitTimestamp, 0);
        }

        _setOperatorNetworkLimit(alice, operator, network, amount3);

        assertEq(
            vault.operatorNetworkLimitIn(
                operator, network, uint48(vault.currentEpochStart() + 2 * vault.epochDuration() - blockTimestamp)
            ),
            amount3
        );
        assertEq(vault.operatorNetworkLimit(operator, network), amount2);
        (nextOperatorNetworkLimitAmount, nextOperatorNetworkLimitTimestamp) =
            vault.nextOperatorNetworkLimit(operator, network);
        assertEq(nextOperatorNetworkLimitAmount, amount3);
        assertEq(nextOperatorNetworkLimitTimestamp, vault.currentEpochStart() + 2 * vault.epochDuration());

        _setOperatorNetworkLimit(alice, operator, network, amount2);

        assertEq(
            vault.operatorNetworkLimitIn(
                operator, network, uint48(vault.currentEpochStart() + 2 * vault.epochDuration() - blockTimestamp)
            ),
            amount2
        );
        assertEq(vault.operatorNetworkLimit(operator, network), amount2);
        (nextOperatorNetworkLimitAmount, nextOperatorNetworkLimitTimestamp) =
            vault.nextOperatorNetworkLimit(operator, network);
        assertEq(nextOperatorNetworkLimitAmount, 0);
        assertEq(nextOperatorNetworkLimitTimestamp, 0);

        _optOutOperatorVault(operator);

        assertEq(vault.operatorNetworkLimitIn(operator, network, 1), amount2);
        assertEq(vault.operatorNetworkLimit(operator, network), amount2);
        (nextOperatorNetworkLimitAmount, nextOperatorNetworkLimitTimestamp) =
            vault.nextOperatorNetworkLimit(operator, network);
        assertEq(nextOperatorNetworkLimitAmount, 0);
        assertEq(nextOperatorNetworkLimitTimestamp, 0);

        blockTimestamp = vault.currentEpochStart() + 2 * vault.epochDuration() - 1;
        vm.warp(blockTimestamp);

        assertEq(vault.operatorNetworkLimitIn(operator, network, 1), amount2);
        assertEq(vault.operatorNetworkLimit(operator, network), amount2);
        (nextOperatorNetworkLimitAmount, nextOperatorNetworkLimitTimestamp) =
            vault.nextOperatorNetworkLimit(operator, network);
        assertEq(nextOperatorNetworkLimitAmount, 0);
        assertEq(nextOperatorNetworkLimitTimestamp, 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.operatorNetworkLimitIn(operator, network, 1), amount2);
        assertEq(vault.operatorNetworkLimit(operator, network), amount2);
        (nextOperatorNetworkLimitAmount, nextOperatorNetworkLimitTimestamp) =
            vault.nextOperatorNetworkLimit(operator, network);
        assertEq(nextOperatorNetworkLimitAmount, 0);
        assertEq(nextOperatorNetworkLimitTimestamp, 0);
    }

    function test_SetOperatorNetworkLimitRevertOnlyRole(uint48 epochDuration, uint256 amount1) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));

        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        address operator = bob;
        _registerOperator(operator);

        address network = address(1);
        _optInOperatorVault(operator);

        vm.expectRevert();
        _setOperatorNetworkLimit(bob, operator, network, amount1);
    }

    function test_SetMaxNetworkResolverLimit(uint256 amount1, uint256 amount2, uint256 networkResolverLimit) public {
        amount1 = bound(amount1, 1, type(uint256).max);
        vm.assume(amount1 != amount2);
        networkResolverLimit = bound(networkResolverLimit, 1, amount1);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = alice;

        _setMaxNetworkResolverLimit(network, resolver, amount1);
        assertEq(vault.maxNetworkResolverLimit(network, resolver), amount1);

        _optInNetworkVault(network, resolver);

        _setNetworkResolverLimit(alice, network, resolver, networkResolverLimit);
        _setNetworkResolverLimit(alice, network, resolver, networkResolverLimit - 1);

        _setMaxNetworkResolverLimit(network, resolver, amount2);

        assertEq(vault.maxNetworkResolverLimit(network, resolver), amount2);
        assertEq(vault.networkResolverLimit(network, resolver), Math.min(networkResolverLimit, amount2));
        (uint256 nextNetworkResolverLimitAmount, uint256 nextNetworkResolverLimitTimestamp) =
            vault.nextNetworkResolverLimit(network, resolver);
        assertEq(nextNetworkResolverLimitAmount, Math.min(networkResolverLimit - 1, amount2));
        assertEq(nextNetworkResolverLimitTimestamp, vault.currentEpochStart() + 2 * vault.epochDuration());
    }

    function test_SetMaxNetworkResolverLimitRevertAlreadySet(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = alice;

        _setMaxNetworkResolverLimit(network, resolver, amount);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setMaxNetworkResolverLimit(network, resolver, amount);
    }

    function test_SetMaxNetworkResolverLimitRevertNotNetwork(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        address network = bob;

        address resolver = alice;

        vm.expectRevert(IVault.NotNetwork.selector);
        _setMaxNetworkResolverLimit(network, resolver, amount);
    }

    function test_SetRewardsDistributor(address rewardsDistributor1, address rewardsDistributor2) public {
        uint48 epochDuration = 1;
        uint48 executeDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, executeDuration);
        vm.assume(rewardsDistributor1 != address(0));
        vm.assume(rewardsDistributor1 != rewardsDistributor2);

        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, rewardsDistributor1);
        assertEq(vault.rewardsDistributor(), rewardsDistributor1);

        _setRewardsDistributor(alice, rewardsDistributor2);
        assertEq(vault.rewardsDistributor(), rewardsDistributor2);
    }

    function test_SetRewardsDistributorRevertUnauthorized(address rewardsDistributor) public {
        uint48 epochDuration = 1;
        uint48 executeDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, executeDuration);
        vm.assume(rewardsDistributor != address(0));

        vm.expectRevert();
        _setRewardsDistributor(alice, rewardsDistributor);
    }

    function test_SetRewardsDistributorRevertAlreadySet(address rewardsDistributor) public {
        uint48 epochDuration = 1;
        uint48 executeDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, executeDuration);
        vm.assume(rewardsDistributor != address(0));

        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, rewardsDistributor);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setRewardsDistributor(alice, rewardsDistributor);
    }

    function test_SetAdminFee(uint256 adminFee1, uint256 adminFee2) public {
        uint48 epochDuration = 1;
        uint48 executeDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, executeDuration);
        adminFee1 = bound(adminFee1, 1, vault.ADMIN_FEE_BASE());
        adminFee2 = bound(adminFee2, 0, vault.ADMIN_FEE_BASE());
        vm.assume(adminFee1 != adminFee2);

        _grantAdminFeeSetRole(alice, alice);
        _setAdminFee(alice, adminFee1);
        assertEq(vault.adminFee(), adminFee1);

        _setAdminFee(alice, adminFee2);
        assertEq(vault.adminFee(), adminFee2);
    }

    function test_SetAdminFeeRevertUnauthorized(uint256 adminFee) public {
        uint48 epochDuration = 1;
        uint48 executeDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, executeDuration);
        adminFee = bound(adminFee, 1, vault.ADMIN_FEE_BASE());

        vm.expectRevert();
        _setAdminFee(bob, adminFee);
    }

    function test_SetAdminFeeRevertAlreadySet(uint256 adminFee) public {
        uint48 epochDuration = 1;
        uint48 executeDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, executeDuration);
        adminFee = bound(adminFee, 1, vault.ADMIN_FEE_BASE());

        _grantAdminFeeSetRole(alice, alice);
        _setAdminFee(alice, adminFee);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setAdminFee(alice, adminFee);
    }

    function test_SetAdminFeeRevertInvalidAdminFee(uint256 adminFee) public {
        uint48 epochDuration = 1;
        uint48 executeDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, executeDuration);
        vm.assume(adminFee > vault.ADMIN_FEE_BASE());

        _grantAdminFeeSetRole(alice, alice);
        vm.expectRevert(IVault.InvalidAdminFee.selector);
        _setAdminFee(alice, adminFee);
    }

    function test_SetDepositWhitelist() public {
        uint48 epochDuration = 1;
        uint48 executeDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);
        assertEq(vault.depositWhitelist(), true);

        _setDepositWhitelist(alice, false);
        assertEq(vault.depositWhitelist(), false);
    }

    function test_SetDepositWhitelistRevertNotWhitelistedDepositor() public {
        uint48 epochDuration = 1;
        uint48 executeDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, executeDuration);

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
        uint48 executeDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setDepositWhitelist(alice, true);
    }

    function test_SetDepositorWhitelistStatus() public {
        uint48 epochDuration = 1;
        uint48 executeDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, executeDuration);

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
        uint48 executeDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        _grantDepositorWhitelistRole(alice, alice);

        vm.expectRevert(IVault.NoDepositWhitelist.selector);
        _setDepositorWhitelistStatus(alice, bob, true);
    }

    function test_SetDepositorWhitelistStatusRevertAlreadySet() public {
        uint48 epochDuration = 1;
        uint48 executeDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        _grantDepositorWhitelistRole(alice, alice);

        _setDepositorWhitelistStatus(alice, bob, true);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setDepositorWhitelistStatus(alice, bob, true);
    }

    function _getVault(uint48 epochDuration, uint48 vetoDuration, uint48 executeDuration) internal returns (IVault) {
        return IVault(
            vaultFactory.create(
                vaultFactory.lastVersion(),
                alice,
                abi.encode(
                    IVault.InitParams({
                        collateral: address(collateral),
                        epochDuration: epochDuration,
                        vetoDuration: vetoDuration,
                        executeDuration: executeDuration,
                        rewardsDistributor: address(0),
                        adminFee: 0,
                        depositWhitelist: false
                    })
                )
            )
        );
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

    function _grantRewardsDistributorSetRole(address user, address account) internal {
        vm.startPrank(user);
        Vault(address(vault)).grantRole(vault.REWARDS_DISTRIBUTOR_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _grantAdminFeeSetRole(address user, address account) internal {
        vm.startPrank(user);
        Vault(address(vault)).grantRole(vault.ADMIN_FEE_SET_ROLE(), account);
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

    function _requestSlash(
        address user,
        address network,
        address resolver,
        address operator,
        uint256 amount
    ) internal returns (uint256 slashIndex) {
        vm.startPrank(user);
        slashIndex = vault.requestSlash(network, resolver, operator, amount);
        vm.stopPrank();
    }

    function _executeSlash(address user, uint256 slashIndex) internal returns (uint256 slashedAmount) {
        vm.startPrank(user);
        slashedAmount = vault.executeSlash(slashIndex);
        vm.stopPrank();
    }

    function _vetoSlash(address user, uint256 slashIndex) internal {
        vm.startPrank(user);
        vault.vetoSlash(slashIndex);
        vm.stopPrank();
    }

    function _setMaxNetworkResolverLimit(address user, address resolver, uint256 maxNetworkResolverLimit) internal {
        vm.startPrank(user);
        vault.setMaxNetworkResolverLimit(resolver, maxNetworkResolverLimit);
        vm.stopPrank();
    }

    function _optInNetworkVault(address user, address resolver) internal {
        vm.startPrank(user);
        networkVaultOptInService.optIn(resolver, address(vault));
        vm.stopPrank();
    }

    function _optOutNetworkVault(address user, address resolver) internal {
        vm.startPrank(user);
        networkVaultOptInService.optOut(resolver, address(vault));
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

    function _setNetworkResolverLimit(address user, address network, address resolver, uint256 amount) internal {
        vm.startPrank(user);
        vault.setNetworkResolverLimit(network, resolver, amount);
        vm.stopPrank();
    }

    function _setOperatorNetworkLimit(address user, address operator, address network, uint256 amount) internal {
        vm.startPrank(user);
        vault.setOperatorNetworkLimit(operator, network, amount);
        vm.stopPrank();
    }

    function _setRewardsDistributor(address user, address rewardsDistributor) internal {
        vm.startPrank(user);
        vault.setRewardsDistributor(rewardsDistributor);
        vm.stopPrank();
    }

    function _setAdminFee(address user, uint256 adminFee) internal {
        vm.startPrank(user);
        vault.setAdminFee(adminFee);
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
