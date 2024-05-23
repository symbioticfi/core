// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {MigratablesRegistry} from "src/contracts/base/MigratablesRegistry.sol";
import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";
import {MetadataPlugin} from "src/contracts/plugins/MetadataPlugin.sol";
import {MiddlewarePlugin} from "src/contracts/plugins/MiddlewarePlugin.sol";
import {NetworkOptInPlugin} from "src/contracts/plugins/NetworkOptInPlugin.sol";
import {OperatorOptInPlugin} from "src/contracts/plugins/OperatorOptInPlugin.sol";

import {Vault} from "src/contracts/Vault.sol";
import {IVault} from "src/interfaces/IVault.sol";
import {IVaultDelegation} from "src/interfaces/IVaultDelegation.sol";

import {Token} from "./mocks/Token.sol";
import {FeeOnTransferToken} from "test/mocks/FeeOnTransferToken.sol";
import {SimpleCollateral} from "./mocks/SimpleCollateral.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract VaultTest is Test {
    using Math for uint256;
    using Strings for string;

    address owner;
    address alice;
    uint256 alicePrivateKey;
    address bob;
    uint256 bobPrivateKey;

    NonMigratablesRegistry operatorRegistry;
    MigratablesRegistry vaultRegistry;
    NonMigratablesRegistry networkRegistry;
    MetadataPlugin operatorMetadataPlugin;
    MetadataPlugin networkMetadataPlugin;
    MiddlewarePlugin networkMiddlewarePlugin;
    NetworkOptInPlugin networkVaultOptInPlugin;
    OperatorOptInPlugin operatorVaultOptInPlugin;
    OperatorOptInPlugin operatorNetworkOptInPlugin;

    IVault vault;

    SimpleCollateral collateral;

    function setUp() public {
        owner = address(this);
        (alice, alicePrivateKey) = makeAddrAndKey("alice");
        (bob, bobPrivateKey) = makeAddrAndKey("bob");

        operatorRegistry = new NonMigratablesRegistry();
        vaultRegistry = new MigratablesRegistry(owner);
        networkRegistry = new NonMigratablesRegistry();
        operatorMetadataPlugin = new MetadataPlugin(address(operatorRegistry));
        networkMetadataPlugin = new MetadataPlugin(address(networkRegistry));
        networkMiddlewarePlugin = new MiddlewarePlugin(address(networkRegistry));
        networkVaultOptInPlugin = new NetworkOptInPlugin(address(networkRegistry), address(vaultRegistry));
        operatorVaultOptInPlugin = new OperatorOptInPlugin(address(operatorRegistry), address(vaultRegistry));
        operatorNetworkOptInPlugin = new OperatorOptInPlugin(address(operatorRegistry), address(networkRegistry));

        vaultRegistry.whitelist(
            address(
                new Vault(
                    address(networkRegistry),
                    address(operatorRegistry),
                    address(networkMiddlewarePlugin),
                    address(networkVaultOptInPlugin),
                    address(operatorVaultOptInPlugin),
                    address(operatorNetworkOptInPlugin)
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
        uint48 slashDuration,
        uint256 adminFee,
        bool depositWhitelist
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, 50 weeks));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        slashDuration = uint48(bound(slashDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration + slashDuration <= epochDuration);
        adminFee = bound(adminFee, 0, 10_000);

        vault = IVault(
            vaultRegistry.create(
                vaultRegistry.lastVersion(),
                abi.encode(
                    IVaultDelegation.InitParams({
                        owner: alice,
                        collateral: address(collateral),
                        epochDuration: epochDuration,
                        vetoDuration: vetoDuration,
                        slashDuration: slashDuration,
                        adminFee: adminFee,
                        depositWhitelist: depositWhitelist
                    })
                )
            )
        );

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        assertEq(vault.ADMIN_FEE_BASE(), 10_000);
        assertEq(vault.NETWORK_LIMIT_SET_ROLE(), keccak256("NETWORK_LIMIT_SET_ROLE"));
        assertEq(vault.OPERATOR_LIMIT_SET_ROLE(), keccak256("OPERATOR_LIMIT_SET_ROLE"));
        assertEq(vault.NETWORK_REGISTRY(), address(networkRegistry));
        assertEq(vault.OPERATOR_REGISTRY(), address(operatorRegistry));

        assertEq(vault.collateral(), address(collateral));
        assertEq(vault.epochDurationInit(), blockTimestamp);
        assertEq(vault.epochDuration(), epochDuration);
        assertEq(vault.currentEpoch(), 0);
        assertEq(vault.currentEpochStart(), blockTimestamp);
        assertEq(vault.previousEpochStart(), blockTimestamp);
        assertEq(vault.vetoDuration(), vetoDuration);
        assertEq(vault.slashDuration(), slashDuration);
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
        assertEq(vault.withdrawalsShares(0), 0);
        assertEq(vault.withdrawalsSharesOf(0, alice), 0);
        assertEq(vault.firstDepositAt(alice), 0);
        assertEq(vault.maxSlash(address(0), address(0), address(0)), 0);
        assertEq(vault.slashRequestsLength(), 0);
        vm.expectRevert();
        vault.slashRequests(0);
        assertEq(vault.maxNetworkLimit(address(0), address(0)), 0);
        assertEq(vault.networkLimit(address(0), address(0)), 0);
        (uint256 nextNetworkLimitAmount, uint256 nextNetworkLimitTimestamp) =
            vault.nextNetworkLimit(address(0), address(0));
        assertEq(nextNetworkLimitAmount, 0);
        assertEq(nextNetworkLimitTimestamp, 0);
        assertEq(vault.operatorLimit(address(0), address(0)), 0);
        (uint256 nextOperatorLimitAmount, uint256 nextOperatorLimitTimestamp) =
            vault.nextOperatorLimit(address(0), address(0));
        assertEq(nextOperatorLimitAmount, 0);
        assertEq(nextOperatorLimitTimestamp, 0);
        assertEq(vault.adminFee(), adminFee);
        assertEq(vault.depositWhitelist(), depositWhitelist);
        assertEq(vault.isDepositorWhitelisted(alice), false);

        blockTimestamp = blockTimestamp + vault.epochDuration() - 1;
        vm.warp(blockTimestamp);

        assertEq(vault.currentEpoch(), 0);
        assertEq(vault.currentEpochStart(), blockTimestamp - (vault.epochDuration() - 1));
        assertEq(vault.previousEpochStart(), blockTimestamp - (vault.epochDuration() - 1));

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.currentEpoch(), 1);
        assertEq(vault.currentEpochStart(), blockTimestamp);
        assertEq(vault.previousEpochStart(), blockTimestamp - vault.epochDuration());

        blockTimestamp = blockTimestamp + vault.epochDuration() - 1;
        vm.warp(blockTimestamp);

        assertEq(vault.currentEpoch(), 1);
        assertEq(vault.currentEpochStart(), blockTimestamp - (vault.epochDuration() - 1));
        assertEq(vault.previousEpochStart(), blockTimestamp - (vault.epochDuration() - 1) - vault.epochDuration());
    }

    function test_DepositTwice(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 tokensBefore = collateral.balanceOf(address(vault));
        uint256 shares1 = amount1 * 10 ** 3;
        assertEq(_deposit(alice, amount1), shares1);
        assertEq(collateral.balanceOf(address(vault)) - tokensBefore, amount1);

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
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

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
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

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

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

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
        assertEq(vault.withdrawalsShares(vault.currentEpoch()), 0);
        assertEq(vault.withdrawalsShares(vault.currentEpoch() + 1), mintedShares);
        assertEq(vault.withdrawalsShares(vault.currentEpoch() + 2), 0);
        assertEq(vault.withdrawalsSharesOf(vault.currentEpoch(), alice), 0);
        assertEq(vault.withdrawalsSharesOf(vault.currentEpoch() + 1, alice), mintedShares);
        assertEq(vault.withdrawalsSharesOf(vault.currentEpoch() + 2, alice), 0);

        shares -= burnedShares;

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        burnedShares = amount3 * (shares + 10 ** 3) / (amount1 - amount2 + 1);
        mintedShares = amount3 * 10 ** 3;
        (burnedShares_, mintedShares_) = _withdraw(alice, amount3);
        assertEq(burnedShares_, burnedShares);
        assertEq(mintedShares_, mintedShares);

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
        assertEq(vault.withdrawalsShares(vault.currentEpoch() - 1), 0);
        assertEq(vault.withdrawalsShares(vault.currentEpoch()), amount2 * 10 ** 3);
        assertEq(vault.withdrawalsShares(vault.currentEpoch() + 1), amount3 * 10 ** 3);
        assertEq(vault.withdrawalsShares(vault.currentEpoch() + 2), 0);
        assertEq(vault.withdrawalsSharesOf(vault.currentEpoch() - 1, alice), 0);
        assertEq(vault.withdrawalsSharesOf(vault.currentEpoch(), alice), amount2 * 10 ** 3);
        assertEq(vault.withdrawalsSharesOf(vault.currentEpoch() + 1, alice), amount3 * 10 ** 3);
        assertEq(vault.withdrawalsSharesOf(vault.currentEpoch() + 2, alice), 0);

        shares -= burnedShares;

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.totalSupply(), amount1 - amount2);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.totalSupply(), amount1 - amount2 - amount3);
    }

    function test_WithdrawRevertInsufficientWithdrawal(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.InsufficientWithdrawal.selector);
        _withdraw(alice, 0);
    }

    function test_WithdrawRevertTooMuchWithdraw(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

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
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

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

        assertEq(vault.withdrawalsSharesOf(vault.currentEpoch() - 1, alice), 0);
    }

    function test_ClaimRevertInvalidEpoch(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

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
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

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
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

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
        uint256 networkLimit,
        uint256 operatorLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorLimit = bound(operatorLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 maxSlash_ = Math.min(amount1 + amount2, networkLimit);
        maxSlash_ = Math.min(maxSlash_, operatorLimit);
        assertEq(vault.maxSlash(network, resolver, operator), maxSlash_);

        uint256 slashIndex = 0;
        assertEq(_requestSlash(bob, network, resolver, operator, toSlash), slashIndex);
        assertEq(vault.slashRequestsLength(), 1);

        (
            address network_,
            address resolver_,
            address operator_,
            uint256 amount_,
            uint48 vetoDeadline_,
            uint48 slashDeadline_,
            bool completed_
        ) = vault.slashRequests(slashIndex);

        assertEq(network_, network);
        assertEq(resolver_, resolver);
        assertEq(operator_, operator);
        assertEq(amount_, Math.min(maxSlash_, toSlash));
        assertEq(vetoDeadline_, uint48(blockTimestamp + vetoDuration));
        assertEq(slashDeadline_, uint48(blockTimestamp + vetoDuration + slashDuration));
        assertEq(completed_, false);
    }

    function test_RequestSlashRevertNotNetworkMiddleware(
        uint256 amount1,
        uint256 amount2,
        uint256 networkLimit,
        uint256 operatorLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorLimit = bound(operatorLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.NotNetworkMiddleware.selector);
        _requestSlash(alice, network, resolver, operator, toSlash);
    }

    function test_RequestSlashRevertInsufficientSlash(
        uint256 amount1,
        uint256 amount2,
        uint256 networkLimit,
        uint256 operatorLimit
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.InsufficientSlash.selector);
        _requestSlash(bob, network, resolver, operator, 0);
    }

    function test_RequestSlashRevertNetworkNotOptedIn(
        uint256 amount1,
        uint256 amount2,
        uint256 networkLimit,
        uint256 operatorLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorLimit = bound(operatorLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _optOutNetworkVault(network, resolver);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVaultDelegation.NetworkNotOptedInVault.selector);
        _requestSlash(bob, network, resolver, operator, toSlash);
    }

    function test_RequestSlashRevertOperatorNotOptedInNetwork(
        uint256 amount1,
        uint256 amount2,
        uint256 networkLimit,
        uint256 operatorLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorLimit = bound(operatorLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

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
        uint256 networkLimit,
        uint256 operatorLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorLimit = bound(operatorLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _optOutOperatorVault(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _optInOperatorNetwork(operator, network);

        blockTimestamp = vault.currentEpochStart() + 2 * vault.epochDuration();
        vm.warp(blockTimestamp);

        vm.expectRevert(IVaultDelegation.OperatorNotOptedInVault.selector);
        _requestSlash(bob, network, resolver, operator, toSlash);
    }

    function test_ExecuteSlash(
        uint256 amount1,
        uint256 amount2,
        uint256 networkLimit,
        uint256 operatorLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorLimit = bound(operatorLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares1 = _deposit(alice, amount1);

        uint256 shares2 = _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

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
            uint48 slashDeadline_,
        ) = vault.slashRequests(slashIndex);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 activeSupply_ = vault.activeSupply();
        uint256 activeSlashed = amount_.mulDiv(vault.activeSupply(), vault.totalSupply());

        assertEq(_executeSlash(address(1), slashIndex), amount_);
        assertEq(activeSupply_ - activeSlashed, vault.activeSupply());

        (
            address network__,
            address resolver__,
            address operator__,
            uint256 amount__,
            uint48 vetoDeadline__,
            uint48 slashDeadline__,
            bool completed__
        ) = vault.slashRequests(slashIndex);

        assertEq(network__, network_);
        assertEq(resolver__, resolver_);
        assertEq(operator__, operator_);
        assertEq(amount__, amount_);
        assertEq(vetoDeadline__, vetoDeadline_);
        assertEq(slashDeadline__, slashDeadline_);
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

    function test_ExecuteSlashRevertSlashRequestNotExist(
        uint256 amount1,
        uint256 amount2,
        uint256 networkLimit,
        uint256 operatorLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorLimit = bound(operatorLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

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
        uint256 networkLimit,
        uint256 operatorLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorLimit = bound(operatorLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

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
        uint256 networkLimit,
        uint256 operatorLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorLimit = bound(operatorLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

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
        uint256 networkLimit,
        uint256 operatorLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorLimit = bound(operatorLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

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
        uint256 networkLimit,
        uint256 operatorLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorLimit = bound(operatorLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

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
            uint48 slashDeadline_,
        ) = vault.slashRequests(slashIndex);

        _vetoSlash(resolver, slashIndex);

        (
            address network__,
            address resolver__,
            address operator__,
            uint256 amount__,
            uint48 vetoDeadline__,
            uint48 slashDeadline__,
            bool completed__
        ) = vault.slashRequests(slashIndex);

        assertEq(network__, network_);
        assertEq(resolver__, resolver_);
        assertEq(operator__, operator_);
        assertEq(amount__, amount_);
        assertEq(vetoDeadline__, vetoDeadline_);
        assertEq(slashDeadline__, slashDeadline_);
        assertEq(completed__, true);
    }

    function test_VetoSlashRevertSlashRequestNotExist(
        uint256 amount1,
        uint256 amount2,
        uint256 networkLimit,
        uint256 operatorLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorLimit = bound(operatorLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

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
        uint256 networkLimit,
        uint256 operatorLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorLimit = bound(operatorLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

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
        uint256 networkLimit,
        uint256 operatorLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorLimit = bound(operatorLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

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
        uint256 networkLimit,
        uint256 operatorLimit,
        uint256 toSlash
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        networkLimit = bound(networkLimit, 1, type(uint256).max);
        operatorLimit = bound(operatorLimit, 1, type(uint256).max);
        toSlash = bound(toSlash, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _optInOperatorVault(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

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
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        uint64 lastVersion = vaultRegistry.lastVersion();
        vm.expectRevert(IVaultDelegation.InvalidEpochDuration.selector);
        vault = IVault(
            vaultRegistry.create(
                lastVersion,
                abi.encode(
                    IVaultDelegation.InitParams({
                        owner: alice,
                        collateral: address(collateral),
                        epochDuration: epochDuration,
                        vetoDuration: vetoDuration,
                        slashDuration: slashDuration,
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
        uint48 slashDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        slashDuration = uint48(bound(slashDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration + slashDuration > epochDuration);

        uint64 lastVersion = vaultRegistry.lastVersion();
        vm.expectRevert(IVaultDelegation.InvalidSlashDuration.selector);
        vault = IVault(
            vaultRegistry.create(
                lastVersion,
                abi.encode(
                    IVaultDelegation.InitParams({
                        owner: alice,
                        collateral: address(collateral),
                        epochDuration: epochDuration,
                        vetoDuration: vetoDuration,
                        slashDuration: slashDuration,
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
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        uint64 lastVersion = vaultRegistry.lastVersion();
        vm.expectRevert(IVaultDelegation.InvalidAdminFee.selector);
        vault = IVault(
            vaultRegistry.create(
                lastVersion,
                abi.encode(
                    IVaultDelegation.InitParams({
                        owner: alice,
                        collateral: address(collateral),
                        epochDuration: epochDuration,
                        vetoDuration: vetoDuration,
                        slashDuration: slashDuration,
                        adminFee: adminFee,
                        depositWhitelist: false
                    })
                )
            )
        );
    }

    function test_SetNetworkLimit(uint48 epochDuration, uint256 amount1, uint256 amount2, uint256 amount3) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        vm.assume(amount3 < amount2);

        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = address(1);
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        _setNetworkLimit(alice, network, resolver, amount1);

        assertEq(vault.networkLimit(network, resolver), amount1);
        (uint256 nextNetworkLimitAmount, uint256 nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
        assertEq(nextNetworkLimitAmount, 0);
        assertEq(nextNetworkLimitTimestamp, 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.networkLimit(network, resolver), amount1);
        assertEq(nextNetworkLimitAmount, 0);
        assertEq(nextNetworkLimitTimestamp, 0);

        _setNetworkLimit(alice, network, resolver, amount2);

        if (amount1 > amount2) {
            assertEq(vault.networkLimit(network, resolver), amount1);
            (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
            assertEq(nextNetworkLimitAmount, amount2);
            assertEq(nextNetworkLimitTimestamp, vault.currentEpochStart() + 2 * vault.epochDuration());

            blockTimestamp = vault.currentEpochStart() + 2 * vault.epochDuration() - 1;
            vm.warp(blockTimestamp);

            assertEq(vault.networkLimit(network, resolver), amount1);
            (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
            assertEq(nextNetworkLimitAmount, amount2);
            assertEq(nextNetworkLimitTimestamp, vault.currentEpochStart() + vault.epochDuration());

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);

            assertEq(vault.networkLimit(network, resolver), amount2);
            (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
            assertEq(nextNetworkLimitAmount, amount2);
            assertEq(nextNetworkLimitTimestamp, vault.currentEpochStart());

            _setNetworkLimit(alice, network, resolver, amount2);

            assertEq(vault.networkLimit(network, resolver), amount2);
            (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
            assertEq(nextNetworkLimitAmount, 0);
            assertEq(nextNetworkLimitTimestamp, 0);
        } else {
            assertEq(vault.networkLimit(network, resolver), amount2);
            (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
            assertEq(nextNetworkLimitAmount, 0);
            assertEq(nextNetworkLimitTimestamp, 0);
        }

        _setNetworkLimit(alice, network, resolver, amount3);

        assertEq(vault.networkLimit(network, resolver), amount2);
        (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
        assertEq(nextNetworkLimitAmount, amount3);
        assertEq(nextNetworkLimitTimestamp, vault.currentEpochStart() + 2 * vault.epochDuration());

        _setNetworkLimit(alice, network, resolver, amount2);

        assertEq(vault.networkLimit(network, resolver), amount2);
        (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
        assertEq(nextNetworkLimitAmount, 0);
        assertEq(nextNetworkLimitTimestamp, 0);

        _optOutNetworkVault(network, resolver);

        assertEq(vault.networkLimit(network, resolver), amount2);
        (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
        assertEq(nextNetworkLimitAmount, 0);
        assertEq(nextNetworkLimitTimestamp, 0);

        blockTimestamp = vault.currentEpochStart() + 2 * vault.epochDuration() - 1;
        vm.warp(blockTimestamp);

        assertEq(vault.networkLimit(network, resolver), amount2);
        (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
        assertEq(nextNetworkLimitAmount, 0);
        assertEq(nextNetworkLimitTimestamp, 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.networkLimit(network, resolver), amount2);
        (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
        assertEq(nextNetworkLimitAmount, 0);
        assertEq(nextNetworkLimitTimestamp, 0);
    }

    function test_SetNetworkLimitRevertOnlyRole(uint48 epochDuration, uint256 amount1) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));

        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = address(1);
        _setMaxNetworkLimit(network, resolver, type(uint256).max);
        _optInNetworkVault(network, resolver);

        vm.expectRevert();
        _setNetworkLimit(bob, network, resolver, amount1);
    }

    function test_SetNetworkLimitRevertExceedsMaxNetworkLimit(
        uint48 epochDuration,
        uint256 amount1,
        uint256 maxNetworkLimit
    ) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        maxNetworkLimit = bound(maxNetworkLimit, 1, type(uint256).max);
        vm.assume(amount1 > maxNetworkLimit);

        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = address(1);
        _setMaxNetworkLimit(network, resolver, maxNetworkLimit);
        _optInNetworkVault(network, resolver);

        vm.expectRevert(IVaultDelegation.ExceedsMaxNetworkLimit.selector);
        _setNetworkLimit(alice, network, resolver, amount1);
    }

    function test_SetOperatorLimit(uint48 epochDuration, uint256 amount1, uint256 amount2, uint256 amount3) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        vm.assume(amount3 < amount2);

        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address operator = bob;
        _registerOperator(operator);

        address network = address(1);
        _optInOperatorVault(operator);

        _setOperatorLimit(alice, operator, network, amount1);

        assertEq(vault.operatorLimit(operator, network), amount1);
        (uint256 nextOperatorLimitAmount, uint256 nextOperatorLimitTimestamp) =
            vault.nextOperatorLimit(address(0), address(0));
        assertEq(nextOperatorLimitAmount, 0);
        assertEq(nextOperatorLimitTimestamp, 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.operatorLimit(operator, network), amount1);
        assertEq(nextOperatorLimitAmount, 0);
        assertEq(nextOperatorLimitTimestamp, 0);

        _setOperatorLimit(alice, operator, network, amount2);

        if (amount1 > amount2) {
            assertEq(vault.operatorLimit(operator, network), amount1);
            (nextOperatorLimitAmount, nextOperatorLimitTimestamp) = vault.nextOperatorLimit(operator, network);
            assertEq(nextOperatorLimitAmount, amount2);
            assertEq(nextOperatorLimitTimestamp, vault.currentEpochStart() + 2 * vault.epochDuration());

            blockTimestamp = vault.currentEpochStart() + 2 * vault.epochDuration() - 1;
            vm.warp(blockTimestamp);

            assertEq(vault.operatorLimit(operator, network), amount1);
            (nextOperatorLimitAmount, nextOperatorLimitTimestamp) = vault.nextOperatorLimit(operator, network);
            assertEq(nextOperatorLimitAmount, amount2);
            assertEq(nextOperatorLimitTimestamp, vault.currentEpochStart() + vault.epochDuration());

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);

            assertEq(vault.operatorLimit(operator, network), amount2);
            (nextOperatorLimitAmount, nextOperatorLimitTimestamp) = vault.nextOperatorLimit(operator, network);
            assertEq(nextOperatorLimitAmount, amount2);
            assertEq(nextOperatorLimitTimestamp, vault.currentEpochStart());

            _setOperatorLimit(alice, operator, network, amount2);

            assertEq(vault.operatorLimit(operator, network), amount2);
            (nextOperatorLimitAmount, nextOperatorLimitTimestamp) = vault.nextOperatorLimit(operator, network);
            assertEq(nextOperatorLimitAmount, 0);
            assertEq(nextOperatorLimitTimestamp, 0);
        } else {
            assertEq(vault.operatorLimit(operator, network), amount2);
            (nextOperatorLimitAmount, nextOperatorLimitTimestamp) = vault.nextOperatorLimit(operator, network);
            assertEq(nextOperatorLimitAmount, 0);
            assertEq(nextOperatorLimitTimestamp, 0);
        }

        _setOperatorLimit(alice, operator, network, amount3);

        assertEq(vault.operatorLimit(operator, network), amount2);
        (nextOperatorLimitAmount, nextOperatorLimitTimestamp) = vault.nextOperatorLimit(operator, network);
        assertEq(nextOperatorLimitAmount, amount3);
        assertEq(nextOperatorLimitTimestamp, vault.currentEpochStart() + 2 * vault.epochDuration());

        _setOperatorLimit(alice, operator, network, amount2);

        assertEq(vault.operatorLimit(operator, network), amount2);
        (nextOperatorLimitAmount, nextOperatorLimitTimestamp) = vault.nextOperatorLimit(operator, network);
        assertEq(nextOperatorLimitAmount, 0);
        assertEq(nextOperatorLimitTimestamp, 0);

        _optOutOperatorVault(operator);

        assertEq(vault.operatorLimit(operator, network), amount2);
        (nextOperatorLimitAmount, nextOperatorLimitTimestamp) = vault.nextOperatorLimit(operator, network);
        assertEq(nextOperatorLimitAmount, 0);
        assertEq(nextOperatorLimitTimestamp, 0);
    }

    function test_SetOperatorLimitRevertOnlyRole(uint48 epochDuration, uint256 amount1) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));

        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        address operator = bob;
        _registerOperator(operator);

        address network = address(1);
        _optInOperatorVault(operator);

        vm.expectRevert();
        _setOperatorLimit(bob, operator, network, amount1);
    }

    function test_SetMaxNetworkLimit(uint256 amount1, uint256 amount2, uint256 networkLimit) public {
        amount1 = bound(amount1, 1, type(uint256).max);
        vm.assume(amount1 != amount2);
        networkLimit = bound(networkLimit, 1, amount1);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = alice;

        _setMaxNetworkLimit(network, resolver, amount1);
        assertEq(vault.maxNetworkLimit(network, resolver), amount1);

        _optInNetworkVault(network, resolver);

        _setNetworkLimit(alice, network, resolver, networkLimit);
        _setNetworkLimit(alice, network, resolver, networkLimit - 1);

        _setMaxNetworkLimit(network, resolver, amount2);

        assertEq(vault.maxNetworkLimit(network, resolver), amount2);
        assertEq(vault.networkLimit(network, resolver), Math.min(networkLimit, amount2));
        (uint256 nextNetworkLimitAmount, uint256 nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
        assertEq(nextNetworkLimitAmount, Math.min(networkLimit - 1, amount2));
        assertEq(nextNetworkLimitTimestamp, vault.currentEpochStart() + 2 * vault.epochDuration());
    }

    function test_SetMaxNetworkLimitRevertAlreadySet(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = alice;

        _setMaxNetworkLimit(network, resolver, amount);

        vm.expectRevert(IVaultDelegation.AlreadySet.selector);
        _setMaxNetworkLimit(network, resolver, amount);
    }

    function test_SetMaxNetworkLimitRevertNotNetwork(uint256 amount) public {
        amount = bound(amount, 1, type(uint256).max);

        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        address network = bob;

        address resolver = alice;

        vm.expectRevert(IVaultDelegation.NotNetwork.selector);
        _setMaxNetworkLimit(network, resolver, amount);
    }

    function test_SetAdminFee(uint256 adminFee1, uint256 adminFee2) public {
        uint48 epochDuration = 1;
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, slashDuration);
        adminFee1 = bound(adminFee1, 1, vault.ADMIN_FEE_BASE());
        adminFee2 = bound(adminFee2, 0, vault.ADMIN_FEE_BASE());
        vm.assume(adminFee1 != adminFee2);

        _grantAdminFeeSetRole(alice, alice);
        _setAdminFee(alice, adminFee1);
        assertEq(vault.adminFee(), adminFee1);

        _setAdminFee(alice, adminFee2);
        assertEq(vault.adminFee(), adminFee2);
    }

    function test_SetAdminFeeReverUnauthorized(uint256 adminFee) public {
        uint48 epochDuration = 1;
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, slashDuration);
        adminFee = bound(adminFee, 1, vault.ADMIN_FEE_BASE());

        vm.expectRevert();
        _setAdminFee(bob, adminFee);
    }

    function test_SetAdminFeeRevertAlreadySet(uint256 adminFee) public {
        uint48 epochDuration = 1;
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, slashDuration);
        adminFee = bound(adminFee, 1, vault.ADMIN_FEE_BASE());

        _grantAdminFeeSetRole(alice, alice);
        _setAdminFee(alice, adminFee);

        vm.expectRevert(IVaultDelegation.AlreadySet.selector);
        _setAdminFee(alice, adminFee);
    }

    function test_SetAdminFeeRevertInvalidAdminFee(uint256 adminFee) public {
        uint48 epochDuration = 1;
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, slashDuration);
        vm.assume(adminFee > vault.ADMIN_FEE_BASE());

        _grantAdminFeeSetRole(alice, alice);
        vm.expectRevert(IVaultDelegation.InvalidAdminFee.selector);
        _setAdminFee(alice, adminFee);
    }

    function test_SetDepositWhitelist() public {
        uint48 epochDuration = 1;
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);
        assertEq(vault.depositWhitelist(), true);

        _setDepositWhitelist(alice, false);
        assertEq(vault.depositWhitelist(), false);
    }

    function test_SetDepositWhitelistRevertNotWhitelistedDepositor() public {
        uint48 epochDuration = 1;
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, slashDuration);

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
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        vm.expectRevert(IVaultDelegation.AlreadySet.selector);
        _setDepositWhitelist(alice, true);
    }

    function test_SetDepositorWhitelistStatus() public {
        uint48 epochDuration = 1;
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, slashDuration);

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
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        _grantDepositorWhitelistRole(alice, alice);

        vm.expectRevert(IVaultDelegation.NoDepositWhitelist.selector);
        _setDepositorWhitelistStatus(alice, bob, true);
    }

    function test_SetDepositorWhitelistStatusRevertAlreadySet() public {
        uint48 epochDuration = 1;
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        _grantDepositWhitelistSetRole(alice, alice);
        _setDepositWhitelist(alice, true);

        _grantDepositorWhitelistRole(alice, alice);

        _setDepositorWhitelistStatus(alice, bob, true);

        vm.expectRevert(IVaultDelegation.AlreadySet.selector);
        _setDepositorWhitelistStatus(alice, bob, true);
    }

    function _getVault(uint48 epochDuration, uint48 vetoDuration, uint48 slashDuration) internal returns (IVault) {
        return IVault(
            vaultRegistry.create(
                vaultRegistry.lastVersion(),
                abi.encode(
                    IVaultDelegation.InitParams({
                        owner: alice,
                        collateral: address(collateral),
                        epochDuration: epochDuration,
                        vetoDuration: vetoDuration,
                        slashDuration: slashDuration,
                        adminFee: 0,
                        depositWhitelist: false
                    })
                )
            )
        );
    }

    function _registerOperator(address user) internal {
        vm.startPrank(user);
        operatorRegistry.register();
        vm.stopPrank();
    }

    function _registerNetwork(address user, address middleware) internal {
        vm.startPrank(user);
        networkRegistry.register();
        networkMiddlewarePlugin.setMiddleware(middleware);
        vm.stopPrank();
    }

    function _grantDepositorWhitelistRole(address user, address account) internal {
        vm.startPrank(user);
        Vault(address(vault)).grantRole(vault.DEPOSITOR_WHITELIST_ROLE(), account);
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

    function _setMaxNetworkLimit(address user, address resolver, uint256 maxNetworkLimit) internal {
        vm.startPrank(user);
        vault.setMaxNetworkLimit(resolver, maxNetworkLimit);
        vm.stopPrank();
    }

    function _optInNetworkVault(address user, address resolver) internal {
        vm.startPrank(user);
        networkVaultOptInPlugin.optIn(resolver, address(vault));
        vm.stopPrank();
    }

    function _optOutNetworkVault(address user, address resolver) internal {
        vm.startPrank(user);
        networkVaultOptInPlugin.optOut(resolver, address(vault));
        vm.stopPrank();
    }

    function _optInOperatorVault(address user) internal {
        vm.startPrank(user);
        operatorVaultOptInPlugin.optIn(address(vault));
        vm.stopPrank();
    }

    function _optOutOperatorVault(address user) internal {
        vm.startPrank(user);
        operatorVaultOptInPlugin.optOut(address(vault));
        vm.stopPrank();
    }

    function _optInOperatorNetwork(address user, address network) internal {
        vm.startPrank(user);
        operatorNetworkOptInPlugin.optIn(network);
        vm.stopPrank();
    }

    function _optOutOperatorNetwork(address user, address network) internal {
        vm.startPrank(user);
        operatorNetworkOptInPlugin.optOut(network);
        vm.stopPrank();
    }

    function _setNetworkLimit(address user, address network, address resolver, uint256 amount) internal {
        vm.startPrank(user);
        vault.setNetworkLimit(network, resolver, amount);
        vm.stopPrank();
    }

    function _setOperatorLimit(address user, address operator, address network, uint256 amount) internal {
        vm.startPrank(user);
        vault.setOperatorLimit(operator, network, amount);
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
