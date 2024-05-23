// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console2} from "forge-std/Test.sol";

import {MigratablesRegistry} from "src/contracts/base/MigratablesRegistry.sol";
import {NonMigratablesRegistry} from "src/contracts/base/NonMigratablesRegistry.sol";
import {MetadataPlugin} from "src/contracts/plugins/MetadataPlugin.sol";
import {MiddlewarePlugin} from "src/contracts/plugins/MiddlewarePlugin.sol";
import {NetworkOptInPlugin} from "src/contracts/plugins/NetworkOptInPlugin.sol";
import {OperatorOptInPlugin} from "src/contracts/plugins/OperatorOptInPlugin.sol";
import {RewardsPlugin} from "src/contracts/plugins/RewardsPlugin.sol";

import {Vault} from "src/contracts/Vault.sol";
import {IVault} from "src/interfaces/IVault.sol";
import {IVault} from "src/interfaces/IVault.sol";
import {IRewardsPlugin} from "src/interfaces/plugins/IRewardsPlugin.sol";

import {Token} from "test/mocks/Token.sol";
import {FeeOnTransferToken} from "test/mocks/FeeOnTransferToken.sol";
import {SimpleCollateral} from "test/mocks/SimpleCollateral.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract RewardsPluginTest is Test {
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
    IRewardsPlugin plugin;

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

    function test_Create() public {
        plugin = _getPlugin();

        assertEq(plugin.REGISTRY(), address(networkRegistry));
        assertEq(plugin.VAULT_REGISTRY(), address(vaultRegistry));

        vm.expectRevert();
        vm.expectRevert(IRewardsPlugin.NotVault.selector);
        plugin.rewardsLength(alice, alice);
        vm.expectRevert();
        plugin.rewards(alice, alice, 0);
        assertEq(plugin.lastUnclaimedReward(alice, alice, alice), 0);
        assertEq(plugin.claimableAdminFee(alice, alice), 0);
    }

    function test_DistributeReward(uint256 amount, uint256 ditributeAmount, uint256 adminFee) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 2, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);
        adminFee = bound(adminFee, 1, vault.ADMIN_FEE_BASE());

        plugin = _getPlugin();

        _grantAdminFeeSetRole(alice, alice);
        _setAdminFee(alice, adminFee);

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
        feeOnTransferToken.approve(address(plugin), type(uint256).max);
        vm.stopPrank();

        uint256 balanceBefore = feeOnTransferToken.balanceOf(address(plugin));
        uint256 balanceBeforeBob = feeOnTransferToken.balanceOf(bob);
        uint48 timestamp = 3;
        _distributeReward(bob, network, address(feeOnTransferToken), ditributeAmount, timestamp, vault.ADMIN_FEE_BASE());
        assertEq(feeOnTransferToken.balanceOf(address(plugin)) - balanceBefore, ditributeAmount - 1);
        assertEq(balanceBeforeBob - feeOnTransferToken.balanceOf(bob), ditributeAmount);

        assertEq(plugin.rewardsLength(address(vault), address(feeOnTransferToken)), 1);
        (address network_, uint256 amount_, uint48 timestamp_, uint48 creation) =
            plugin.rewards(address(vault), address(feeOnTransferToken), 0);
        assertEq(network_, network);
        uint256 amount__ = ditributeAmount - 1;
        uint256 adminFeeAmount = amount__.mulDiv(adminFee, vault.ADMIN_FEE_BASE());
        amount__ -= adminFeeAmount;
        assertEq(amount_, amount__);
        assertEq(timestamp_, timestamp);
        assertEq(creation, blockTimestamp);
        assertEq(plugin.claimableAdminFee(address(vault), address(feeOnTransferToken)), adminFeeAmount);
    }

    function test_DistributeRewardRevertNotNetwork(uint256 amount, uint256 ditributeAmount, uint256 adminFee) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 2, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);
        adminFee = bound(adminFee, 1, vault.ADMIN_FEE_BASE());

        plugin = _getPlugin();

        _grantAdminFeeSetRole(alice, alice);
        _setAdminFee(alice, adminFee);

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
        feeOnTransferToken.approve(address(plugin), type(uint256).max);
        vm.stopPrank();

        uint48 timestamp = 3;
        uint256 acceptedAdminFee = vault.ADMIN_FEE_BASE();
        vm.expectRevert(IRewardsPlugin.NotNetwork.selector);
        _distributeReward(bob, address(0), address(feeOnTransferToken), ditributeAmount, timestamp, acceptedAdminFee);
    }

    function test_DistributeRewardRevertInvalidRewardTimestamp(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 2, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        plugin = _getPlugin();

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
        feeOnTransferToken.approve(address(plugin), type(uint256).max);
        vm.stopPrank();

        uint256 acceptedAdminFee = vault.ADMIN_FEE_BASE();
        vm.expectRevert(IRewardsPlugin.InvalidRewardTimestamp.selector);
        _distributeReward(
            bob, network, address(feeOnTransferToken), ditributeAmount, uint48(blockTimestamp), acceptedAdminFee
        );
    }

    function test_DistributeRewardRevertInsufficientReward(uint256 amount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        plugin = _getPlugin();

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
        feeOnTransferToken.approve(address(plugin), type(uint256).max);
        vm.stopPrank();

        uint48 timestamp = 3;
        uint256 acceptedAdminFee = vault.ADMIN_FEE_BASE();
        vm.expectRevert(IRewardsPlugin.InsufficientReward.selector);
        _distributeReward(bob, network, address(feeOnTransferToken), 1, timestamp, acceptedAdminFee);
    }

    function test_DistributeRewardRevertUnacceptedAdminFee(uint256 amount, uint256 adminFee) public {
        amount = bound(amount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);
        adminFee = bound(adminFee, 1, vault.ADMIN_FEE_BASE());

        plugin = _getPlugin();

        _grantAdminFeeSetRole(alice, alice);
        _setAdminFee(alice, adminFee);

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
        feeOnTransferToken.approve(address(plugin), type(uint256).max);
        vm.stopPrank();

        uint48 timestamp = 3;
        uint256 acceptedAdminFee = adminFee - 1;
        vm.expectRevert(IRewardsPlugin.UnacceptedAdminFee.selector);
        _distributeReward(
            bob, network, address(feeOnTransferToken), uint48(blockTimestamp), timestamp, acceptedAdminFee
        );
    }

    function test_ClaimRewards(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        plugin = _getPlugin();

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
        token.approve(address(plugin), type(uint256).max);
        vm.stopPrank();

        uint48 timestamp = 3;
        _distributeReward(bob, network, address(token), ditributeAmount, timestamp, vault.ADMIN_FEE_BASE());

        uint256 balanceBefore = token.balanceOf(alice);
        uint32[] memory activeSharesOfHints = new uint32[](1);
        _claimRewards(alice, address(token), 1, activeSharesOfHints);
        assertEq(token.balanceOf(alice) - balanceBefore, ditributeAmount);

        assertEq(plugin.lastUnclaimedReward(address(vault), alice, address(token)), 1);
    }

    // function test_ClaimRewardsManyWithoutHints(uint256 amount, uint256 ditributeAmount) public {
    //     amount = bound(amount, 1, 100 * 10 ** 18);
    //     ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

    //
    //     uint48 epochDuration = 1;
    //     uint48 slashDuration = 1;
    //     uint48 vetoDuration = 0;
    //     vault = _getVault(epochDuration, vetoDuration, slashDuration);

    //     plugin = _getPlugin();

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
    //     token.approve(address(plugin), type(uint256).max);
    //     vm.stopPrank();

    //     uint256 numRewards = 50;
    //     for (uint48 i = 1; i < numRewards + 1; ++i) {
    //         _distributeReward(bob, network, address(token), ditributeAmount, i, vault.ADMIN_FEE_BASE());
    //     }

    //     uint32[] memory activeSharesOfHints = new uint32[](0);

    //     uint256 gasLeft = gasleft();
    //     _claimRewards(alice, address(token), type(uint256).max, activeSharesOfHints);
    //     uint256 gasLeft2 = gasleft();
    //     console2.log("Gas1", gasLeft - gasLeft2 - 100);
    // }

    // function test_ClaimRewardsManyWithHints(uint256 amount, uint256 ditributeAmount) public {
    //     amount = bound(amount, 1, 100 * 10 ** 18);
    //     ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

    //
    //     uint48 epochDuration = 1;
    //     uint48 slashDuration = 1;
    //     uint48 vetoDuration = 0;
    //     vault = _getVault(epochDuration, vetoDuration, slashDuration);

    //     plugin = _getPlugin();

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
    //     token.approve(address(plugin), type(uint256).max);
    //     vm.stopPrank();

    //     uint256 numRewards = 50;
    //     for (uint48 i = 1; i < numRewards + 1; ++i) {
    //         _distributeReward(bob, network, address(token), ditributeAmount, i, vault.ADMIN_FEE_BASE());
    //     }

    //     uint32[] memory activeSharesOfHints = new uint32[](numRewards);
    //     for (uint32 i; i < numRewards; ++i) {
    //         activeSharesOfHints[i] = i;
    //     }

    //     uint256 gasLeft = gasleft();
    //     _claimRewards(alice, address(token), type(uint256).max, activeSharesOfHints);
    //     uint256 gasLeft2 = gasleft();
    //     console2.log("Gas2", gasLeft - gasLeft2 - 100);
    // }

    function test_ClaimRewardsRevertNoRewardsToClaim1(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        plugin = _getPlugin();

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        for (uint256 i; i < 10; ++i) {
            _deposit(alice, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 token = IERC20(new Token("Token"));

        uint32[] memory activeSharesOfHints = new uint32[](1);
        vm.expectRevert(IRewardsPlugin.NoRewardsToClaim.selector);
        _claimRewards(alice, address(token), type(uint256).max, activeSharesOfHints);
    }

    function test_ClaimRewardsRevertNoRewardsToClaim2(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        plugin = _getPlugin();

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        for (uint256 i; i < 10; ++i) {
            _deposit(alice, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 token = IERC20(new Token("Token"));

        uint32[] memory activeSharesOfHints = new uint32[](1);
        vm.expectRevert(IRewardsPlugin.NoRewardsToClaim.selector);
        _claimRewards(alice, address(token), 0, activeSharesOfHints);
    }

    function test_ClaimRewardsRevertNoDeposits(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        plugin = _getPlugin();

        address network = bob;
        _registerNetwork(network, bob);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        for (uint256 i; i < 10; ++i) {
            _deposit(bob, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 token = IERC20(new Token("Token"));
        token.transfer(bob, 100_000 * 1e18);
        vm.startPrank(bob);
        token.approve(address(plugin), type(uint256).max);
        vm.stopPrank();

        uint48 timestamp = 3;
        _distributeReward(bob, network, address(token), ditributeAmount, timestamp, vault.ADMIN_FEE_BASE());

        uint32[] memory activeSharesOfHints = new uint32[](1);
        vm.expectRevert(IRewardsPlugin.NoDeposits.selector);
        _claimRewards(alice, address(token), type(uint256).max, activeSharesOfHints);
    }

    function test_ClaimRewardsRevertInvalidHintsLength(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);

        plugin = _getPlugin();

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
        token.approve(address(plugin), type(uint256).max);
        vm.stopPrank();

        uint48 timestamp = 3;
        _distributeReward(bob, network, address(token), ditributeAmount, timestamp, vault.ADMIN_FEE_BASE());

        uint32[] memory activeSharesOfHints = new uint32[](2);
        vm.expectRevert(IRewardsPlugin.InvalidHintsLength.selector);
        _claimRewards(alice, address(token), type(uint256).max, activeSharesOfHints);
    }

    function test_ClaimAdminFee(uint256 amount, uint256 ditributeAmount, uint256 adminFee) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);
        adminFee = bound(adminFee, 1, vault.ADMIN_FEE_BASE());

        plugin = _getPlugin();

        _grantAdminFeeSetRole(alice, alice);
        _setAdminFee(alice, adminFee);

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
        token.approve(address(plugin), type(uint256).max);
        vm.stopPrank();

        uint48 timestamp = 3;
        _distributeReward(bob, network, address(token), ditributeAmount, timestamp, vault.ADMIN_FEE_BASE());

        uint256 adminFeeAmount = ditributeAmount.mulDiv(adminFee, vault.ADMIN_FEE_BASE());
        vm.assume(adminFeeAmount != 0);
        uint256 balanceBefore = token.balanceOf(address(plugin));
        uint256 balanceBeforeAlice = token.balanceOf(alice);
        _claimAdminFee(alice, address(token));
        assertEq(balanceBefore - token.balanceOf(address(plugin)), adminFeeAmount);
        assertEq(token.balanceOf(alice) - balanceBeforeAlice, adminFeeAmount);
        assertEq(plugin.claimableAdminFee(address(vault), address(token)), 0);
    }

    function test_ClaimAdminFeeRevertInsufficientAdminFee(
        uint256 amount,
        uint256 ditributeAmount,
        uint256 adminFee
    ) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 slashDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, slashDuration);
        adminFee = bound(adminFee, 1, vault.ADMIN_FEE_BASE());

        plugin = _getPlugin();

        _grantAdminFeeSetRole(alice, alice);
        _setAdminFee(alice, adminFee);

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
        token.approve(address(plugin), type(uint256).max);
        vm.stopPrank();

        uint48 timestamp = 3;
        _distributeReward(bob, network, address(token), ditributeAmount, timestamp, vault.ADMIN_FEE_BASE());

        vm.assume(plugin.claimableAdminFee(address(vault), address(token)) != 0);
        _claimAdminFee(alice, address(token));

        vm.expectRevert(IRewardsPlugin.InsufficientAdminFee.selector);
        _claimAdminFee(alice, address(token));
    }

    function _getVault(uint48 epochDuration, uint48 vetoDuration, uint48 slashDuration) internal returns (IVault) {
        return IVault(
            vaultRegistry.create(
                vaultRegistry.lastVersion(),
                abi.encode(
                    IVault.InitParams({
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

    function _getPlugin() internal returns (IRewardsPlugin) {
        return IRewardsPlugin(address(new RewardsPlugin(address(networkRegistry), address(vaultRegistry))));
    }

    function _registerNetwork(address user, address middleware) internal {
        vm.startPrank(user);
        networkRegistry.register();
        networkMiddlewarePlugin.setMiddleware(middleware);
        vm.stopPrank();
    }

    function _grantAdminFeeSetRole(address user, address account) internal {
        vm.startPrank(user);
        Vault(address(vault)).grantRole(vault.ADMIN_FEE_SET_ROLE(), account);
        vm.stopPrank();
    }

    function _deposit(address user, uint256 amount) internal returns (uint256 shares) {
        collateral.transfer(user, amount);
        vm.startPrank(user);
        collateral.approve(address(vault), amount);
        shares = vault.deposit(user, amount);
        vm.stopPrank();
    }

    function _distributeReward(
        address user,
        address network,
        address token,
        uint256 amount,
        uint48 timestamp,
        uint256 acceptedAdminFee
    ) internal {
        vm.startPrank(user);
        plugin.distributeReward(address(vault), network, token, amount, timestamp, acceptedAdminFee);
        vm.stopPrank();
    }

    function _claimRewards(
        address user,
        address token,
        uint256 maxRewards,
        uint32[] memory activeSharesOfHints
    ) internal {
        vm.startPrank(user);
        plugin.claimRewards(address(vault), user, token, maxRewards, activeSharesOfHints);
        vm.stopPrank();
    }

    function _setAdminFee(address user, uint256 adminFee) internal {
        vm.startPrank(user);
        vault.setAdminFee(adminFee);
        vm.stopPrank();
    }

    function _claimAdminFee(address user, address token) internal {
        vm.startPrank(user);
        plugin.claimAdminFee(address(vault), user, token);
        vm.stopPrank();
    }
}
