// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {MigratablesRegistry} from "src/contracts/MigratablesRegistry.sol";
import {NonMigratablesRegistry} from "src/contracts/NonMigratablesRegistry.sol";
import {MetadataPlugin} from "src/contracts/plugins/MetadataPlugin.sol";
import {MiddlewarePlugin} from "src/contracts/plugins/MiddlewarePlugin.sol";
import {NetworkOptInPlugin} from "src/contracts/plugins/NetworkOptInPlugin.sol";

import {Vault} from "src/contracts/Vault.sol";
import {IVault} from "src/interfaces/IVault.sol";

import {Token} from "./mocks/Token.sol";
import {FeeOnTransferToken} from "test/mocks/FeeOnTransferToken.sol";
import {SimpleCollateral} from "./mocks/SimpleCollateral.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract VaultTest is Test {
    using Math for uint256;

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
    NetworkOptInPlugin networkOptInPlugin;

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
        networkOptInPlugin = new NetworkOptInPlugin(address(operatorRegistry), address(networkRegistry));

        vaultRegistry.whitelist(
            address(
                new Vault(
                    address(networkRegistry),
                    address(operatorRegistry),
                    address(networkMiddlewarePlugin),
                    address(networkOptInPlugin)
                )
            )
        );

        Token token = new Token("Token");
        collateral = new SimpleCollateral(address(token));

        collateral.mint(token.totalSupply());
    }

    function test_Create(
        uint48 epochDuration,
        uint48 slashDuration,
        uint48 vetoDuration,
        bool hasDepositWhitelist
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));
        slashDuration = uint48(bound(slashDuration, 0, type(uint48).max / 2));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration + slashDuration <= epochDuration);

        string memory metadataURL = "";
        vault = IVault(
            vaultRegistry.create(
                vaultRegistry.maxVersion(),
                abi.encode(
                    IVault.InitParams({
                        owner: alice,
                        metadataURL: metadataURL,
                        collateral: address(collateral),
                        epochDuration: epochDuration,
                        slashDuration: slashDuration,
                        vetoDuration: vetoDuration,
                        hasDepositWhitelist: hasDepositWhitelist
                    })
                )
            )
        );

        assertEq(vault.NETWORK_LIMIT_SET_ROLE(), keccak256("NETWORK_LIMIT_SET_ROLE"));
        assertEq(vault.OPERATOR_LIMIT_SET_ROLE(), keccak256("OPERATOR_LIMIT_SET_ROLE"));
        assertEq(vault.NETWORK_REGISTRY(), address(networkRegistry));
        assertEq(vault.OPERATOR_REGISTRY(), address(operatorRegistry));

        assertEq(vault.metadataURL(), metadataURL);
        assertEq(vault.collateral(), address(collateral));
        assertEq(vault.epochStart(), block.timestamp);
        assertEq(vault.epochDuration(), epochDuration);
        assertEq(vault.currentEpoch(), 0);
        assertEq(vault.currentEpochStart(), block.timestamp);
        assertEq(vault.slashDuration(), slashDuration);
        assertEq(vault.vetoDuration(), vetoDuration);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.activeSharesAt(uint48(block.timestamp)), 0);
        assertEq(vault.activeShares(), 0);
        assertEq(vault.activeSupplyAt(uint48(block.timestamp)), 0);
        assertEq(vault.activeSupply(), 0);
        assertEq(vault.activeSharesOfAt(alice, uint48(block.timestamp)), 0);
        assertEq(vault.activeSharesOf(alice), 0);
        assertEq(vault.activeBalanceOfAt(alice, uint48(block.timestamp)), 0);
        assertEq(vault.activeBalanceOf(alice), 0);
        assertEq(vault.withdrawals(0), 0);
        assertEq(vault.withdrawalsShares(0), 0);
        assertEq(vault.withdrawalsSharesOf(0, alice), 0);
        assertEq(vault.firstDepositAt(alice), 0);
        assertEq(vault.maxSlash(address(0), address(0), address(0)), 0);
        assertEq(vault.slashRequestsLength(), 0);
        vm.expectRevert();
        vault.slashRequests(0);
        assertEq(vault.rewardsLength(alice), 0);
        vm.expectRevert();
        vault.rewards(address(0), 0);
        assertEq(vault.lastUnclaimedReward(alice, address(0)), 0);
        assertEq(vault.isNetworkOptedIn(address(0), address(0)), false);
        assertEq(vault.isOperatorOptedIn(address(0)), false);
        assertEq(vault.operatorOptOutAt(address(0)), 0);
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
        assertEq(vault.hasDepositWhitelist(), hasDepositWhitelist);
        assertEq(vault.isDepositorWhitelisted(alice), false);

        string memory metadataURL1 = "1";

        vm.startPrank(alice);
        vault.setMetadataURL(metadataURL1);
        vm.stopPrank();

        assertEq(vault.metadataURL(), metadataURL1);
    }

    function test_DepositTwice(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

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
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1)), amount1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp)), amount1 + amount2);
        assertEq(vault.activeBalanceOf(alice), amount1 + amount2);
        assertEq(vault.firstDepositAt(alice), uint48(blockTimestamp - 1));
    }

    function test_DepositBoth(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

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
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1)), amount1);
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp)), amount1);
        assertEq(vault.activeBalanceOf(alice), amount1);
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp - 1)), 0);
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp)), shares2);
        assertEq(vault.activeSharesOf(bob), shares2);
        assertEq(vault.activeBalanceOfAt(bob, uint48(blockTimestamp - 1)), 0);
        assertEq(vault.activeBalanceOfAt(bob, uint48(blockTimestamp)), amount2);
        assertEq(vault.activeBalanceOf(bob), amount2);
    }

    function test_DepositRevertInsufficientDeposit() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

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

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

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

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.InsufficientWithdrawal.selector);
        _withdraw(alice, 0);
    }

    function test_WithdrawRevertTooMuchWithdraw(uint256 amount1) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        _deposit(alice, amount1);

        vm.expectRevert(IVault.TooMuchWithdraw.selector);
        _withdraw(alice, amount1 + 1);
    }

    function test_Claim(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);
        vm.assume(amount1 >= amount2);

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

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

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

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

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

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

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

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

    function test_RequestSlashRevertNotNetwork(
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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.NotNetwork.selector);
        _requestSlash(bob, address(0), resolver, operator, toSlash);
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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.NotNetworkMiddleware.selector);
        _requestSlash(alice, network, resolver, operator, toSlash);
    }

    function test_RequestSlashRevertNotOperator(
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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.NotOperator.selector);
        _requestSlash(bob, network, resolver, address(0), toSlash);
    }

    function test_RequestSlashRevertInsufficientSlash(
        uint256 amount1,
        uint256 amount2,
        uint256 networkLimit,
        uint256 operatorLimit
    ) public {
        amount1 = bound(amount1, 1, 100 * 10 ** 18);
        amount2 = bound(amount2, 1, 100 * 10 ** 18);

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _optOutNetwork(network, resolver);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.NetworkNotOptedIn.selector);
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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

        _networkOptOut(operator, network);

        blockTimestamp = blockTimestamp + vault.epochDuration() + 1;
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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = address(1);
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _optOutOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

        blockTimestamp = vault.currentEpochStart() + 2 * vault.epochDuration();
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.OperatorNotOptedInVault.selector);
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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares1 = _deposit(alice, amount1);

        uint256 shares2 = _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

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
        assertEq(vault.activeBalanceOfAt(alice, uint48(blockTimestamp - 1)), amount1);
        assertEq(
            vault.activeBalanceOfAt(alice, uint48(blockTimestamp)),
            shares1.mulDiv(vault.activeSupply() + 1, vault.activeShares() + 10 ** 3)
        );
        assertEq(vault.activeBalanceOf(alice), shares1.mulDiv(vault.activeSupply() + 1, vault.activeShares() + 10 ** 3));
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp - 1)), shares2);
        assertEq(vault.activeSharesOfAt(bob, uint48(blockTimestamp)), shares2);
        assertEq(vault.activeSharesOf(bob), shares2);
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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        uint256 slashIndex = _requestSlash(bob, network, resolver, operator, toSlash);

        _vetoSlash(resolver, slashIndex);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.SlashCompleted.selector);
        _executeSlash(address(1), slashIndex);
    }

    function test_ExecuteSlashRevertOperatorNotOptedInVault(
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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        _deposit(alice, amount1);

        _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _optOutOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

        blockTimestamp = blockTimestamp + 2 * vault.epochDuration() - 1;
        vm.warp(blockTimestamp);

        uint256 slashIndex = _requestSlash(bob, network, resolver, operator, toSlash);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        vm.expectRevert(IVault.OperatorNotOptedInVault.selector);
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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

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

        string memory metadataURL = "";
        uint48 epochDuration = 3;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 1;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 shares = _deposit(alice, amount1);

        shares += _deposit(bob, amount2);

        address network = bob;
        _registerNetwork(network, bob);

        address operator = bob;
        _registerOperator(operator);

        address resolver = alice;
        _optInNetwork(network, resolver, type(uint256).max);

        _optInOperator(operator);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        _setOperatorLimit(alice, operator, network, operatorLimit);

        _networkOptIn(operator, network);

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

        string memory metadataURL = "";
        uint256 maxVersion = vaultRegistry.maxVersion();
        vm.expectRevert(IVault.InvalidEpochDuration.selector);
        vault = IVault(
            vaultRegistry.create(
                maxVersion,
                abi.encode(
                    IVault.InitParams({
                        owner: alice,
                        metadataURL: metadataURL,
                        collateral: address(collateral),
                        epochDuration: epochDuration,
                        slashDuration: slashDuration,
                        vetoDuration: vetoDuration,
                        hasDepositWhitelist: false
                    })
                )
            )
        );
    }

    function test_CreateRevertInvalidSlashDuration(
        uint48 epochDuration,
        uint48 slashDuration,
        uint48 vetoDuration
    ) public {
        epochDuration = uint48(bound(epochDuration, 1, type(uint48).max));
        slashDuration = uint48(bound(slashDuration, 0, type(uint48).max / 2));
        vetoDuration = uint48(bound(vetoDuration, 0, type(uint48).max / 2));
        vm.assume(vetoDuration + slashDuration > epochDuration);

        string memory metadataURL = "";
        uint256 maxVersion = vaultRegistry.maxVersion();
        vm.expectRevert(IVault.InvalidSlashDuration.selector);
        vault = IVault(
            vaultRegistry.create(
                maxVersion,
                abi.encode(
                    IVault.InitParams({
                        owner: alice,
                        metadataURL: metadataURL,
                        collateral: address(collateral),
                        epochDuration: epochDuration,
                        slashDuration: slashDuration,
                        vetoDuration: vetoDuration,
                        hasDepositWhitelist: false
                    })
                )
            )
        );
    }

    function test_OptInNetwork(uint256 networkLimit, uint256 maxNetworkLimit) public {
        maxNetworkLimit = bound(maxNetworkLimit, 1, type(uint256).max);
        vm.assume(networkLimit <= maxNetworkLimit);

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = address(1);
        _optInNetwork(network, resolver, maxNetworkLimit);

        assertTrue(vault.isNetworkOptedIn(network, resolver));
        (uint256 nextNetworkLimitAmount, uint256 nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
        assertEq(nextNetworkLimitAmount, 0);
        assertEq(nextNetworkLimitTimestamp, 0);
        assertEq(vault.networkLimit(network, resolver), 0);
        assertEq(vault.maxNetworkLimit(network, resolver), maxNetworkLimit);

        _setNetworkLimit(alice, network, resolver, networkLimit);

        assertEq(vault.networkLimit(network, resolver), networkLimit);
        assertEq(vault.maxNetworkLimit(network, resolver), maxNetworkLimit);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _optOutNetwork(network, resolver);

        assertTrue(!vault.isNetworkOptedIn(network, resolver));
        (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
        assertEq(nextNetworkLimitAmount, 0);
        assertEq(nextNetworkLimitTimestamp, vault.currentEpochStart() + 2 * vault.epochDuration());
        assertEq(vault.networkLimit(network, resolver), networkLimit);
        assertEq(vault.maxNetworkLimit(network, resolver), 0);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
        assertEq(nextNetworkLimitAmount, 0);
        assertEq(nextNetworkLimitTimestamp, vault.currentEpochStart());
        assertEq(vault.networkLimit(network, resolver), 0);
        assertEq(vault.maxNetworkLimit(network, resolver), 0);

        _optInNetwork(network, resolver, type(uint256).max);

        assertTrue(vault.isNetworkOptedIn(network, resolver));
        (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
        assertEq(nextNetworkLimitAmount, 0);
        assertEq(nextNetworkLimitTimestamp, 0);
        assertEq(vault.networkLimit(network, resolver), 0);
        assertEq(vault.maxNetworkLimit(network, resolver), type(uint256).max);

        blockTimestamp = blockTimestamp + 3;
        vm.warp(blockTimestamp);

        (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
        assertEq(nextNetworkLimitAmount, 0);
        assertEq(nextNetworkLimitTimestamp, 0);
        assertEq(vault.networkLimit(network, resolver), 0);
        assertEq(vault.maxNetworkLimit(network, resolver), type(uint256).max);

        _optOutNetwork(network, resolver);

        assertTrue(!vault.isNetworkOptedIn(network, resolver));
        (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
        assertEq(nextNetworkLimitAmount, 0);
        assertEq(nextNetworkLimitTimestamp, vault.currentEpochStart() + 2 * vault.epochDuration());
        assertEq(vault.networkLimit(network, resolver), 0);
        assertEq(vault.maxNetworkLimit(network, resolver), 0);
    }

    function test_OptInNetworkRevertInvalidMaxNetworkLimit() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = address(1);
        vm.expectRevert(IVault.InvalidMaxNetworkLimit.selector);
        _optInNetwork(network, resolver, 0);
    }

    function test_OptInNetworkRevertNetworkAlreadyOptedIn() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = address(1);
        _optInNetwork(network, resolver, type(uint256).max);

        vm.expectRevert(IVault.NetworkAlreadyOptedIn.selector);
        _optInNetwork(network, resolver, type(uint256).max);
    }

    function test_OptInNetworkRevertNotNetwork() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address resolver = address(1);
        vm.expectRevert(IVault.NotNetwork.selector);
        _optInNetwork(address(0), resolver, type(uint256).max);
    }

    function test_OptOutNetworkRevertNotNetwork() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = address(1);
        _optInNetwork(network, resolver, type(uint256).max);

        vm.expectRevert(IVault.NotNetwork.selector);
        _optOutNetwork(address(0), resolver);
    }

    function test_OptInNetworkRevertNetworkNotOptedIn() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = address(1);
        vm.expectRevert(IVault.NetworkNotOptedIn.selector);
        _optOutNetwork(network, resolver);
    }

    function test_OptInOperator() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address operator = bob;
        _registerOperator(operator);

        _optInOperator(operator);

        assertTrue(vault.isOperatorOptedIn(operator));
        assertEq(vault.operatorOptOutAt(operator), 0);

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        _optOutOperator(operator);

        assertTrue(vault.isOperatorOptedIn(operator));
        assertEq(vault.operatorOptOutAt(operator), blockTimestamp + 2);

        blockTimestamp = blockTimestamp + 2;
        vm.warp(blockTimestamp);

        assertTrue(!vault.isOperatorOptedIn(operator));
        assertEq(vault.operatorOptOutAt(operator), blockTimestamp);

        _optInOperator(operator);

        assertTrue(vault.isOperatorOptedIn(operator));
        assertEq(vault.operatorOptOutAt(operator), 0);

        blockTimestamp = blockTimestamp + 3;
        vm.warp(blockTimestamp);

        _optOutOperator(operator);

        assertTrue(vault.isOperatorOptedIn(operator));
        assertEq(vault.operatorOptOutAt(operator), blockTimestamp + 2);
    }

    function test_OptInOperatorRevertOperatorAlreadyOptedIn() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address operator = bob;
        _registerOperator(operator);

        _optInOperator(operator);

        vm.expectRevert(IVault.OperatorAlreadyOptedIn.selector);
        _optInOperator(operator);
    }

    function test_OptInOperatorRevertNotOperator() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        vm.expectRevert(IVault.NotOperator.selector);
        _optInOperator(address(0));
    }

    function test_OptOutOperatorRevertOperatorNotOptedIn() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address operator = bob;
        _registerOperator(operator);

        vm.expectRevert(IVault.OperatorNotOptedIn.selector);
        _optOutOperator(operator);
    }

    function test_OptOutOperatorRevertNotOperator() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address operator = bob;
        _registerOperator(operator);

        _optInOperator(operator);

        vm.expectRevert(IVault.NotOperator.selector);
        _optOutOperator(address(0));
    }

    function test_SetNetworkLimit(uint48 epochDuration, uint256 amount1, uint256 amount2, uint256 amount3) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        vm.assume(amount3 < amount2);

        string memory metadataURL = "";
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = address(1);
        _optInNetwork(network, resolver, type(uint256).max);

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

        _optOutNetwork(network, resolver);

        (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
        assertEq(nextNetworkLimitAmount, 0);
        assertEq(nextNetworkLimitTimestamp, vault.currentEpochStart() + 2 * vault.epochDuration());
        assertEq(vault.networkLimit(network, resolver), amount2);

        blockTimestamp = vault.currentEpochStart() + 2 * vault.epochDuration() - 1;
        vm.warp(blockTimestamp);

        assertEq(vault.networkLimit(network, resolver), amount2);
        (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
        assertEq(nextNetworkLimitAmount, 0);
        assertEq(nextNetworkLimitTimestamp, vault.currentEpochStart() + vault.epochDuration());

        blockTimestamp = blockTimestamp + 1;
        vm.warp(blockTimestamp);

        assertEq(vault.networkLimit(network, resolver), 0);
        (nextNetworkLimitAmount, nextNetworkLimitTimestamp) = vault.nextNetworkLimit(network, resolver);
        assertEq(nextNetworkLimitAmount, 0);
        assertEq(nextNetworkLimitTimestamp, vault.currentEpochStart());
    }

    function test_SetNetworkLimitRevertOnlyRole(uint48 epochDuration, uint256 amount1) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        string memory metadataURL = "";
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = address(1);
        _optInNetwork(network, resolver, type(uint256).max);

        vm.expectRevert();
        _setNetworkLimit(bob, network, resolver, amount1);
    }

    function test_SetNetworkLimitRevertNetworkNotOptedIn(uint48 epochDuration, uint256 amount1) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        string memory metadataURL = "";
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = address(1);
        vm.expectRevert(IVault.NetworkNotOptedIn.selector);
        _setNetworkLimit(alice, network, resolver, amount1);
    }

    function test_SetNetworkLimitRevertExceedsMaxNetworkLimit(
        uint48 epochDuration,
        uint256 amount1,
        uint256 maxNetworkLimit
    ) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        maxNetworkLimit = bound(maxNetworkLimit, 1, type(uint256).max);
        vm.assume(amount1 > maxNetworkLimit);

        string memory metadataURL = "";
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address network = bob;
        _registerNetwork(network, bob);

        address resolver = address(1);
        _optInNetwork(network, resolver, maxNetworkLimit);

        vm.expectRevert(IVault.ExceedsMaxNetworkLimit.selector);
        _setNetworkLimit(alice, network, resolver, amount1);
    }

    function test_SetOperatorLimit(uint48 epochDuration, uint256 amount1, uint256 amount2, uint256 amount3) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        vm.assume(amount3 < amount2);

        string memory metadataURL = "";
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        address operator = bob;
        _registerOperator(operator);

        address network = address(1);
        _optInOperator(operator);

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

        _optOutOperator(operator);

        assertEq(vault.operatorLimit(operator, network), amount2);
        (nextOperatorLimitAmount, nextOperatorLimitTimestamp) = vault.nextOperatorLimit(operator, network);
        assertEq(nextOperatorLimitAmount, 0);
        assertEq(nextOperatorLimitTimestamp, 0);
    }

    function test_SetOperatorLimitRevertOnlyRole(uint48 epochDuration, uint256 amount1) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        string memory metadataURL = "";
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address operator = bob;
        _registerOperator(operator);

        address network = address(1);
        _optInOperator(operator);

        vm.expectRevert();
        _setOperatorLimit(bob, operator, network, amount1);
    }

    function test_SetOperatorLimitRevertOperatorNotOptedIn(uint48 epochDuration, uint256 amount1) public {
        epochDuration = uint48(bound(uint256(epochDuration), 1, 100 days));
        string memory metadataURL = "";
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address operator = bob;
        _registerOperator(operator);

        address network = address(1);
        if (amount1 > 0) {
            vm.expectRevert(IVault.OperatorNotOptedIn.selector);
        }
        _setOperatorLimit(alice, operator, network, amount1);
    }

    function test_DistributeReward(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 2, 100 * 10 ** 18);

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address network = bob;
        _registerNetwork(network, bob);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        for (uint256 i; i < 10; ++i) {
            _deposit(alice, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 feeOnTransferToken = IERC20(new FeeOnTransferToken("FeeOnTransferToken"));
        feeOnTransferToken.transfer(bob, 100_000 * 1e18);
        vm.startPrank(bob);
        feeOnTransferToken.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        uint256 balanceBefore = feeOnTransferToken.balanceOf(address(vault));
        uint256 balanceBeforeBob = feeOnTransferToken.balanceOf(bob);
        uint48 timestamp = 3;
        _ditributeReward(bob, network, address(feeOnTransferToken), ditributeAmount, timestamp);
        assertEq(feeOnTransferToken.balanceOf(address(vault)) - balanceBefore, ditributeAmount - 1);
        assertEq(balanceBeforeBob - feeOnTransferToken.balanceOf(bob), ditributeAmount);

        assertEq(vault.rewardsLength(address(feeOnTransferToken)), 1);
        (uint256 amount_, uint48 timestamp_, uint48 creation) = vault.rewards(address(feeOnTransferToken), 0);
        assertEq(amount_, ditributeAmount - 1);
        assertEq(timestamp_, timestamp);
        assertEq(creation, blockTimestamp);
    }

    function test_DistributeRewardRevertInvalidRewardTimestamp(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 2, 100 * 10 ** 18);

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address network = bob;
        _registerNetwork(network, bob);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        for (uint256 i; i < 10; ++i) {
            _deposit(alice, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 feeOnTransferToken = IERC20(new FeeOnTransferToken("FeeOnTransferToken"));
        feeOnTransferToken.transfer(bob, 100_000 * 1e18);
        vm.startPrank(bob);
        feeOnTransferToken.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        vm.expectRevert(IVault.InvalidRewardTimestamp.selector);
        _ditributeReward(bob, network, address(feeOnTransferToken), ditributeAmount, uint48(blockTimestamp));
    }

    function test_DistributeRewardRevertInsufficientReward(uint256 amount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address network = bob;
        _registerNetwork(network, bob);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        for (uint256 i; i < 10; ++i) {
            _deposit(alice, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 feeOnTransferToken = IERC20(new FeeOnTransferToken("FeeOnTransferToken"));
        feeOnTransferToken.transfer(bob, 100_000 * 1e18);
        vm.startPrank(bob);
        feeOnTransferToken.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        uint48 timestamp = 3;
        vm.expectRevert(IVault.InsufficientReward.selector);
        _ditributeReward(bob, network, address(feeOnTransferToken), 1, timestamp);
    }

    function test_ClaimRewards(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address network = bob;
        _registerNetwork(network, bob);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        for (uint256 i; i < 10; ++i) {
            _deposit(alice, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 token = IERC20(new Token("Token"));
        token.transfer(bob, 100_000 * 1e18);
        vm.startPrank(bob);
        token.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        uint48 timestamp = 3;
        _ditributeReward(bob, network, address(token), ditributeAmount, timestamp);

        IVault.RewardClaim[] memory rewardClaims = new IVault.RewardClaim[](1);
        rewardClaims[0] = IVault.RewardClaim({
            token: address(token),
            amountIndexes: type(uint256).max,
            activeSharesOfHints: new uint32[](1)
        });

        uint256 balanceBefore = token.balanceOf(alice);
        _claimRewards(alice, rewardClaims);
        assertEq(token.balanceOf(alice) - balanceBefore, ditributeAmount);

        assertEq(vault.lastUnclaimedReward(alice, address(token)), 1);
    }

    // function test_ClaimRewardsManyWithoutHints(uint256 amount, uint256 ditributeAmount) public {
    //     amount = bound(amount, 1, 100 * 10 ** 18);
    //     ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

    //     string memory metadataURL = "";
    //     uint48 epochDuration = 1;
    //     uint48 slashDuration = 1;
    //     uint48 vetoDuration = 0;
    //     vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

    //     address network = bob;
    //     _registerNetwork(network, bob);

    //     uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

    //     for (uint256 i; i < 105; ++i) {
    //         _deposit(alice, amount);

    //         blockTimestamp = blockTimestamp + 1;
    //         vm.warp(blockTimestamp);
    //     }

    //     IERC20 token = IERC20(new Token("Token"));
    //     token.transfer(bob, 100_000 * 1e18);
    //     vm.startPrank(bob);
    //     token.approve(address(vault), type(uint256).max);
    //     vm.stopPrank();

    //     uint256 numRewards = 50;
    //     for (uint48 i = 1; i < numRewards + 1; ++i) {
    //         _ditributeReward(bob, network, address(token), ditributeAmount, i);
    //     }

    //     IVault.RewardClaim[] memory rewardClaims = new IVault.RewardClaim[](1);
    //     uint32[] memory activeSharesOfHints = new uint32[](0);
    //     rewardClaims[0] = IVault.RewardClaim({
    //         token: address(token),
    //         amountIndexes: type(uint256).max,
    //         activeSharesOfHints: activeSharesOfHints
    //     });

    //     uint256 gasLeft = gasleft();
    //     _claimRewards(alice, rewardClaims);
    //     uint256 gasLeft2 = gasleft();
    //     console2.log("Gas1", gasLeft - gasLeft2 - 100);
    // }

    // function test_ClaimRewardsManyWithHints(uint256 amount, uint256 ditributeAmount) public {
    //     amount = bound(amount, 1, 100 * 10 ** 18);
    //     ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

    //     string memory metadataURL = "";
    //     uint48 epochDuration = 1;
    //     uint48 slashDuration = 1;
    //     uint48 vetoDuration = 0;
    //     vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

    //     address network = bob;
    //     _registerNetwork(network, bob);

    //     uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

    //     for (uint256 i; i < 105; ++i) {
    //         _deposit(alice, amount);

    //         blockTimestamp = blockTimestamp + 1;
    //         vm.warp(blockTimestamp);
    //     }

    //     IERC20 token = IERC20(new Token("Token"));
    //     token.transfer(bob, 100_000 * 1e18);
    //     vm.startPrank(bob);
    //     token.approve(address(vault), type(uint256).max);
    //     vm.stopPrank();

    //     uint256 numRewards = 50;
    //     for (uint48 i = 1; i < numRewards + 1; ++i) {
    //         _ditributeReward(bob, network, address(token), ditributeAmount, i);
    //     }

    //     IVault.RewardClaim[] memory rewardClaims = new IVault.RewardClaim[](1);
    //     uint32[] memory activeSharesOfHints = new uint32[](numRewards);
    //     for (uint32 i; i < numRewards; ++i) {
    //         activeSharesOfHints[i] = i;
    //     }
    //     rewardClaims[0] = IVault.RewardClaim({
    //         token: address(token),
    //         amountIndexes: type(uint256).max,
    //         activeSharesOfHints: activeSharesOfHints
    //     });

    //     uint256 gasLeft = gasleft();
    //     _claimRewards(alice, rewardClaims);
    //     uint256 gasLeft2 = gasleft();
    //     console2.log("Gas2", gasLeft - gasLeft2 - 100);
    // }

    function test_ClaimRewardsRevertNoRewardsToClaim(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        for (uint256 i; i < 10; ++i) {
            _deposit(alice, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 token = IERC20(new Token("Token"));

        IVault.RewardClaim[] memory rewardClaims = new IVault.RewardClaim[](1);
        rewardClaims[0] = IVault.RewardClaim({
            token: address(token),
            amountIndexes: type(uint256).max,
            activeSharesOfHints: new uint32[](1)
        });

        vm.expectRevert(IVault.NoRewardsToClaim.selector);
        _claimRewards(alice, rewardClaims);
    }

    function test_ClaimRewardsRevertNoRewardClaims(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address network = bob;
        _registerNetwork(network, bob);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        for (uint256 i; i < 10; ++i) {
            _deposit(alice, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 token = IERC20(new Token("Token"));
        token.transfer(bob, 100_000 * 1e18);
        vm.startPrank(bob);
        token.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        uint48 timestamp = 3;
        _ditributeReward(bob, network, address(token), ditributeAmount, timestamp);

        IVault.RewardClaim[] memory rewardClaims = new IVault.RewardClaim[](0);

        vm.expectRevert(IVault.NoRewardClaims.selector);
        _claimRewards(alice, rewardClaims);
    }

    function test_ClaimRewardsRevertNoDeposits(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address network = bob;
        _registerNetwork(network, bob);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        for (uint256 i; i < 10; ++i) {
            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 token = IERC20(new Token("Token"));
        token.transfer(bob, 100_000 * 1e18);
        vm.startPrank(bob);
        token.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        uint48 timestamp = 3;
        _ditributeReward(bob, network, address(token), ditributeAmount, timestamp);

        IVault.RewardClaim[] memory rewardClaims = new IVault.RewardClaim[](1);
        rewardClaims[0] = IVault.RewardClaim({
            token: address(token),
            amountIndexes: type(uint256).max,
            activeSharesOfHints: new uint32[](1)
        });

        vm.expectRevert(IVault.NoDeposits.selector);
        _claimRewards(alice, rewardClaims);
    }

    function test_ClaimRewardsRevertInvalidHintsLength(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        address network = bob;
        _registerNetwork(network, bob);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        for (uint256 i; i < 10; ++i) {
            _deposit(alice, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 token = IERC20(new Token("Token"));
        token.transfer(bob, 100_000 * 1e18);
        vm.startPrank(bob);
        token.approve(address(vault), type(uint256).max);
        vm.stopPrank();

        uint48 timestamp = 3;
        _ditributeReward(bob, network, address(token), ditributeAmount, timestamp);

        IVault.RewardClaim[] memory rewardClaims = new IVault.RewardClaim[](1);
        rewardClaims[0] = IVault.RewardClaim({
            token: address(token),
            amountIndexes: type(uint256).max,
            activeSharesOfHints: new uint32[](2)
        });

        vm.expectRevert(IVault.InvalidHintsLength.selector);
        _claimRewards(alice, rewardClaims);
    }

    function test_SetHasDepositWhitelist() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        _setHasDepositWhitelist(alice, true);
        assertEq(vault.hasDepositWhitelist(), true);

        _setHasDepositWhitelist(alice, false);
        assertEq(vault.hasDepositWhitelist(), false);
    }

    function test_SetHasDepositWhitelistRevertNotWhitelistedDepositor() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        _deposit(alice, 1);

        _setHasDepositWhitelist(alice, true);

        vm.startPrank(alice);
        vm.expectRevert(IVault.NotWhitelistedDepositor.selector);
        vault.deposit(alice, 1);
        vm.stopPrank();
    }

    function test_SetHasDepositWhitelistRevertAlreadySet() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        _setHasDepositWhitelist(alice, true);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setHasDepositWhitelist(alice, true);
    }

    function test_SetDepositorWhitelistStatus() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        _setHasDepositWhitelist(alice, true);

        _grantDepositorWhitelistRole(alice, alice);

        _setDepositorWhitelistStatus(alice, bob, true);
        assertEq(vault.isDepositorWhitelisted(bob), true);

        _deposit(bob, 1);

        _setHasDepositWhitelist(alice, false);

        _deposit(bob, 1);
    }

    function test_SetDepositorWhitelistStatusRevertNoDepositWhitelist() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        _grantDepositorWhitelistRole(alice, alice);

        vm.expectRevert(IVault.NoDepositWhitelist.selector);
        _setDepositorWhitelistStatus(alice, bob, true);
    }

    function test_SetDepositorWhitelistStatusRevertAlreadySet() public {
        string memory metadataURL = "";
        uint48 epochDuration = 1;
        uint48 slashDuration = 0;
        uint48 vetoDuration = 0;

        vault = _getVault(metadataURL, epochDuration, slashDuration, vetoDuration);

        _setHasDepositWhitelist(alice, true);

        _grantDepositorWhitelistRole(alice, alice);

        _setDepositorWhitelistStatus(alice, bob, true);

        vm.expectRevert(IVault.AlreadySet.selector);
        _setDepositorWhitelistStatus(alice, bob, true);
    }

    function _getVault(
        string memory metadataURL,
        uint48 epochDuration,
        uint48 slashDuration,
        uint48 vetoDuration
    ) internal returns (IVault) {
        return IVault(
            vaultRegistry.create(
                vaultRegistry.maxVersion(),
                abi.encode(
                    IVault.InitParams({
                        owner: alice,
                        metadataURL: metadataURL,
                        collateral: address(collateral),
                        epochDuration: epochDuration,
                        slashDuration: slashDuration,
                        vetoDuration: vetoDuration,
                        hasDepositWhitelist: false
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

    function _optInNetwork(address user, address resolver, uint256 maxNetworkLimit) internal {
        vm.startPrank(user);
        vault.optInNetwork(resolver, maxNetworkLimit);
        vm.stopPrank();
    }

    function _optOutNetwork(address user, address resolver) internal {
        vm.startPrank(user);
        vault.optOutNetwork(resolver);
        vm.stopPrank();
    }

    function _optInOperator(address user) internal {
        vm.startPrank(user);
        vault.optInOperator();
        vm.stopPrank();
    }

    function _optOutOperator(address user) internal {
        vm.startPrank(user);
        vault.optOutOperator();
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

    function _ditributeReward(
        address user,
        address network,
        address token,
        uint256 amount,
        uint48 timestamp
    ) internal {
        vm.startPrank(user);
        vault.distributeReward(network, token, amount, timestamp);
        vm.stopPrank();
    }

    function _claimRewards(address user, IVault.RewardClaim[] memory rewardClaims) internal {
        vm.startPrank(user);
        vault.claimRewards(user, rewardClaims);
        vm.stopPrank();
    }

    function _setHasDepositWhitelist(address user, bool hasDepositWhitelist) internal {
        vm.startPrank(user);
        vault.setHasDepositWhitelist(hasDepositWhitelist);
        vm.stopPrank();
    }

    function _setDepositorWhitelistStatus(address user, address depositor, bool status) internal {
        vm.startPrank(user);
        vault.setDepositorWhitelistStatus(depositor, status);
        vm.stopPrank();
    }

    function _networkOptIn(address user, address network) internal {
        vm.startPrank(user);
        networkOptInPlugin.optIn(network);
        vm.stopPrank();
    }

    function _networkOptOut(address user, address network) internal {
        vm.startPrank(user);
        networkOptInPlugin.optOut(network);
        vm.stopPrank();
    }
}
