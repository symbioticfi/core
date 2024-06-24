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

import {DefaultRewardsDistributorFactory} from
    "src/contracts/defaultRewardsDistributor/DefaultRewardsDistributorFactory.sol";
import {IDefaultRewardsDistributor} from "src/interfaces/defaultRewardsDistributor/IDefaultRewardsDistributor.sol";

import {DefaultRewardsDistributor} from "src/contracts/defaultRewardsDistributor/DefaultRewardsDistributor.sol";

import {Token} from "test/mocks/Token.sol";
import {FeeOnTransferToken} from "test/mocks/FeeOnTransferToken.sol";
import {SimpleCollateral} from "test/mocks/SimpleCollateral.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract RewardsDistributorTest is Test {
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

    DefaultRewardsDistributorFactory defaultRewardsDistributorFactory;
    IDefaultRewardsDistributor defaultRewardsDistributor;

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

        defaultRewardsDistributorFactory = new DefaultRewardsDistributorFactory(
            address(networkRegistry), address(vaultFactory), address(networkMiddlewareService)
        );

        Token token = new Token("Token");
        collateral = new SimpleCollateral(address(token));

        collateral.mint(token.totalSupply());
    }

    function test_Create() public {
        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));
    }

    function test_ReinitRevert() public {
        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();

        vm.expectRevert();
        DefaultRewardsDistributor(address(defaultRewardsDistributor)).initialize(address(vault));
    }

    function test_SetNetworkWhitelistStatus() public {
        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

        address network = bob;
        _registerNetwork(network, bob);

        _setNetworkWhitelistStatus(alice, network, true);
        assertEq(defaultRewardsDistributor.isNetworkWhitelisted(network), true);
    }

    function test_SetNetworkWhitelistStatusRevertNotVaultOwner() public {
        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

        address network = bob;
        _registerNetwork(network, bob);

        vm.expectRevert(IDefaultRewardsDistributor.NotVaultOwner.selector);
        _setNetworkWhitelistStatus(bob, network, true);
    }

    function test_SetNetworkWhitelistStatusRevertAlreadySet() public {
        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

        address network = bob;
        _registerNetwork(network, bob);

        _setNetworkWhitelistStatus(alice, network, true);

        vm.expectRevert(IDefaultRewardsDistributor.AlreadySet.selector);
        _setNetworkWhitelistStatus(alice, network, true);
    }

    function test_DistributeReward(uint256 amount, uint256 ditributeAmount, uint256 adminFee) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 2, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);
        adminFee = bound(adminFee, 1, vault.ADMIN_FEE_BASE());

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

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
        feeOnTransferToken.approve(address(defaultRewardsDistributor), type(uint256).max);
        vm.stopPrank();

        uint256 balanceBefore = feeOnTransferToken.balanceOf(address(defaultRewardsDistributor));
        uint256 balanceBeforeBob = feeOnTransferToken.balanceOf(bob);
        _setNetworkWhitelistStatus(alice, network, true);
        uint48 timestamp = 3;
        _distributeReward(bob, network, address(feeOnTransferToken), ditributeAmount, timestamp);
        assertEq(feeOnTransferToken.balanceOf(address(defaultRewardsDistributor)) - balanceBefore, ditributeAmount - 1);
        assertEq(balanceBeforeBob - feeOnTransferToken.balanceOf(bob), ditributeAmount);

        uint256 amount__ = ditributeAmount - 1;
        uint256 adminFeeAmount = amount__.mulDiv(adminFee, vault.ADMIN_FEE_BASE());
        amount__ -= adminFeeAmount;

        if (amount__ != 0) {
            assertEq(defaultRewardsDistributor.rewardsLength(address(feeOnTransferToken)), 1);
            (address network_, uint256 amount_, uint48 timestamp_, uint48 creation) =
                defaultRewardsDistributor.rewards(address(feeOnTransferToken), 0);
            assertEq(network_, network);
            assertEq(amount_, amount__);
            assertEq(timestamp_, timestamp);
            assertEq(creation, blockTimestamp);
        } else {
            assertEq(defaultRewardsDistributor.rewardsLength(address(feeOnTransferToken)), 0);
        }

        assertEq(defaultRewardsDistributor.claimableAdminFee(address(feeOnTransferToken)), adminFeeAmount);
    }

    function test_DistributeRewardRevertNotNetworkMiddleware(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 2, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

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
        feeOnTransferToken.approve(address(defaultRewardsDistributor), type(uint256).max);
        vm.stopPrank();

        _setNetworkWhitelistStatus(alice, network, true);
        uint48 timestamp = 3;
        vm.expectRevert(IDefaultRewardsDistributor.NotNetworkMiddleware.selector);
        _distributeReward(alice, network, address(feeOnTransferToken), ditributeAmount, timestamp);
    }

    function test_DistributeRewardRevertNotWhitelistedNetwork(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 2, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

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
        feeOnTransferToken.approve(address(defaultRewardsDistributor), type(uint256).max);
        vm.stopPrank();

        uint48 timestamp = 3;
        vm.expectRevert(IDefaultRewardsDistributor.NotWhitelistedNetwork.selector);
        _distributeReward(bob, network, address(feeOnTransferToken), ditributeAmount, timestamp);
    }

    function test_DistributeRewardRevertInvalidRewardTimestamp(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 2, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

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
        feeOnTransferToken.approve(address(defaultRewardsDistributor), type(uint256).max);
        vm.stopPrank();

        _setNetworkWhitelistStatus(alice, network, true);
        vm.expectRevert(IDefaultRewardsDistributor.InvalidRewardTimestamp.selector);
        _distributeReward(bob, network, address(feeOnTransferToken), ditributeAmount, uint48(blockTimestamp));
    }

    function test_DistributeRewardRevertInsufficientReward(uint256 amount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

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
        feeOnTransferToken.approve(address(defaultRewardsDistributor), type(uint256).max);
        vm.stopPrank();

        _setNetworkWhitelistStatus(alice, network, true);
        uint48 timestamp = 3;
        vm.expectRevert(IDefaultRewardsDistributor.InsufficientReward.selector);
        _distributeReward(bob, network, address(feeOnTransferToken), 1, timestamp);
    }

    function test_ClaimRewards(uint256 amount, uint256 ditributeAmount1, uint256 ditributeAmount2) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount1 = bound(ditributeAmount1, 1, 100 * 10 ** 18);
        ditributeAmount2 = bound(ditributeAmount2, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

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
        token.approve(address(defaultRewardsDistributor), type(uint256).max);
        vm.stopPrank();

        _setNetworkWhitelistStatus(alice, network, true);

        _distributeReward(bob, network, address(token), ditributeAmount1, uint48(blockTimestamp - 1));

        uint48 timestamp = 3;
        _distributeReward(bob, network, address(token), ditributeAmount2, timestamp);

        uint256 balanceBefore = token.balanceOf(alice);
        uint32[] memory activeSharesOfHints = new uint32[](2);
        _claimRewards(alice, address(token), 2, activeSharesOfHints);
        assertEq(token.balanceOf(alice) - balanceBefore, ditributeAmount1 + ditributeAmount2);

        assertEq(defaultRewardsDistributor.lastUnclaimedReward(alice, address(token)), 2);
    }

    function test_ClaimRewardsBoth(uint256 amount, uint256 ditributeAmount1, uint256 ditributeAmount2) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount1 = bound(ditributeAmount1, 1, 100 * 10 ** 18);
        ditributeAmount2 = bound(ditributeAmount2, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

        address network = bob;
        _registerNetwork(network, bob);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        uint256 aliceN = 10;
        for (uint256 i; i < aliceN; ++i) {
            _deposit(alice, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        uint256 bobN = 3;
        for (uint256 i; i < bobN; ++i) {
            _deposit(bob, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 token = IERC20(new Token("Token"));
        token.transfer(bob, 100_000 * 1e18);
        vm.startPrank(bob);
        token.approve(address(defaultRewardsDistributor), type(uint256).max);
        vm.stopPrank();

        _setNetworkWhitelistStatus(alice, network, true);

        _distributeReward(bob, network, address(token), ditributeAmount1, uint48(blockTimestamp - 1));

        uint48 timestamp = 3;
        _distributeReward(bob, network, address(token), ditributeAmount2, timestamp);

        uint256 balanceBefore = token.balanceOf(alice);
        uint32[] memory activeSharesOfHints = new uint32[](2);
        _claimRewards(alice, address(token), 2, activeSharesOfHints);
        assertEq(
            token.balanceOf(alice) - balanceBefore, ditributeAmount1.mulDiv(aliceN, aliceN + bobN) + ditributeAmount2
        );

        balanceBefore = token.balanceOf(bob);
        _claimRewards(bob, address(token), 2, activeSharesOfHints);
        assertEq(token.balanceOf(bob) - balanceBefore, ditributeAmount1.mulDiv(bobN, aliceN + bobN));

        assertEq(defaultRewardsDistributor.lastUnclaimedReward(alice, address(token)), 2);
    }

    function test_ClaimRewardsManyWithoutHints(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

        address network = bob;
        _registerNetwork(network, bob);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        for (uint256 i; i < 105; ++i) {
            _deposit(alice, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 token = IERC20(new Token("Token"));
        token.transfer(bob, 100_000 * 1e18);
        vm.startPrank(bob);
        token.approve(address(defaultRewardsDistributor), type(uint256).max);
        vm.stopPrank();

        _setNetworkWhitelistStatus(alice, network, true);
        uint256 numRewards = 50;
        for (uint48 i = 1; i < numRewards + 1; ++i) {
            _distributeReward(bob, network, address(token), ditributeAmount, i);
        }

        uint32[] memory activeSharesOfHints = new uint32[](0);

        uint256 gasLeft = gasleft();
        _claimRewards(alice, address(token), type(uint256).max, activeSharesOfHints);
        uint256 gasLeft2 = gasleft();
        console2.log("Gas1", gasLeft - gasLeft2 - 100);
    }

    function test_ClaimRewardsManyWithHints(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 executeDuration = 1;
        uint48 vetoDuration = 0;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

        address network = bob;
        _registerNetwork(network, bob);

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        for (uint256 i; i < 105; ++i) {
            _deposit(alice, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 token = IERC20(new Token("Token"));
        token.transfer(bob, 100_000 * 1e18);
        vm.startPrank(bob);
        token.approve(address(defaultRewardsDistributor), type(uint256).max);
        vm.stopPrank();

        _setNetworkWhitelistStatus(alice, network, true);
        uint256 numRewards = 50;
        for (uint48 i = 1; i < numRewards + 1; ++i) {
            _distributeReward(bob, network, address(token), ditributeAmount, i);
        }

        uint32[] memory activeSharesOfHints = new uint32[](numRewards);
        for (uint32 i; i < numRewards; ++i) {
            activeSharesOfHints[i] = i;
        }

        uint256 gasLeft = gasleft();
        _claimRewards(alice, address(token), type(uint256).max, activeSharesOfHints);
        uint256 gasLeft2 = gasleft();
        console2.log("Gas2", gasLeft - gasLeft2 - 100);
    }

    function test_ClaimRewardsRevertInvalidRecipient(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        for (uint256 i; i < 10; ++i) {
            _deposit(alice, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 token = IERC20(new Token("Token"));

        uint32[] memory activeSharesOfHints = new uint32[](0);
        vm.startPrank(alice);
        vm.expectRevert(IDefaultRewardsDistributor.InvalidRecipient.selector);
        defaultRewardsDistributor.claimRewards(address(0), address(token), type(uint256).max, activeSharesOfHints);
        vm.stopPrank();
    }

    function test_ClaimRewardsRevertNoRewardsToClaim1(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        for (uint256 i; i < 10; ++i) {
            _deposit(alice, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 token = IERC20(new Token("Token"));

        uint32[] memory activeSharesOfHints = new uint32[](1);
        vm.expectRevert(IDefaultRewardsDistributor.NoRewardsToClaim.selector);
        _claimRewards(alice, address(token), type(uint256).max, activeSharesOfHints);
    }

    function test_ClaimRewardsRevertNoRewardsToClaim2(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

        uint256 blockTimestamp = block.timestamp * block.timestamp / block.timestamp * block.timestamp / block.timestamp;

        for (uint256 i; i < 10; ++i) {
            _deposit(alice, amount);

            blockTimestamp = blockTimestamp + 1;
            vm.warp(blockTimestamp);
        }

        IERC20 token = IERC20(new Token("Token"));

        uint32[] memory activeSharesOfHints = new uint32[](1);
        vm.expectRevert(IDefaultRewardsDistributor.NoRewardsToClaim.selector);
        _claimRewards(alice, address(token), 0, activeSharesOfHints);
    }

    function test_ClaimRewardsRevertNoDeposits(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

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
        token.approve(address(defaultRewardsDistributor), type(uint256).max);
        vm.stopPrank();

        _setNetworkWhitelistStatus(alice, network, true);
        uint48 timestamp = 3;
        _distributeReward(bob, network, address(token), ditributeAmount, timestamp);

        uint32[] memory activeSharesOfHints = new uint32[](1);
        vm.expectRevert(IDefaultRewardsDistributor.NoDeposits.selector);
        _claimRewards(alice, address(token), type(uint256).max, activeSharesOfHints);
    }

    function test_ClaimRewardsRevertInvalidHintsLength(uint256 amount, uint256 ditributeAmount) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

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
        token.approve(address(defaultRewardsDistributor), type(uint256).max);
        vm.stopPrank();

        _setNetworkWhitelistStatus(alice, network, true);
        uint48 timestamp = 3;
        _distributeReward(bob, network, address(token), ditributeAmount, timestamp);

        uint32[] memory activeSharesOfHints = new uint32[](2);
        vm.expectRevert(IDefaultRewardsDistributor.InvalidHintsLength.selector);
        _claimRewards(alice, address(token), type(uint256).max, activeSharesOfHints);
    }

    function test_ClaimAdminFee(uint256 amount, uint256 ditributeAmount, uint256 adminFee) public {
        amount = bound(amount, 1, 100 * 10 ** 18);
        ditributeAmount = bound(ditributeAmount, 1, 100 * 10 ** 18);

        uint48 epochDuration = 1;
        uint48 vetoDuration = 0;
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);
        adminFee = bound(adminFee, 1, vault.ADMIN_FEE_BASE());

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

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
        token.approve(address(defaultRewardsDistributor), type(uint256).max);
        vm.stopPrank();

        _setNetworkWhitelistStatus(alice, network, true);
        uint48 timestamp = 3;
        _distributeReward(bob, network, address(token), ditributeAmount, timestamp);

        uint256 adminFeeAmount = ditributeAmount.mulDiv(adminFee, vault.ADMIN_FEE_BASE());
        vm.assume(adminFeeAmount != 0);
        uint256 balanceBefore = token.balanceOf(address(defaultRewardsDistributor));
        uint256 balanceBeforeAlice = token.balanceOf(alice);
        _claimAdminFee(alice, address(token));
        assertEq(balanceBefore - token.balanceOf(address(defaultRewardsDistributor)), adminFeeAmount);
        assertEq(token.balanceOf(alice) - balanceBeforeAlice, adminFeeAmount);
        assertEq(defaultRewardsDistributor.claimableAdminFee(address(token)), 0);
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
        uint48 executeDuration = 1;
        vault = _getVault(epochDuration, vetoDuration, executeDuration);
        adminFee = bound(adminFee, 1, vault.ADMIN_FEE_BASE());

        defaultRewardsDistributor = _getDefaultRewardsDistributor();
        _grantRewardsDistributorSetRole(alice, alice);
        _setRewardsDistributor(alice, address(defaultRewardsDistributor));

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
        token.approve(address(defaultRewardsDistributor), type(uint256).max);
        vm.stopPrank();

        _setNetworkWhitelistStatus(alice, network, true);
        uint48 timestamp = 3;
        _distributeReward(bob, network, address(token), ditributeAmount, timestamp);

        vm.assume(defaultRewardsDistributor.claimableAdminFee(address(token)) != 0);
        _claimAdminFee(alice, address(token));

        vm.expectRevert(IDefaultRewardsDistributor.InsufficientAdminFee.selector);
        _claimAdminFee(alice, address(token));
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

    function _getDefaultRewardsDistributor() internal returns (IDefaultRewardsDistributor) {
        return IDefaultRewardsDistributor(defaultRewardsDistributorFactory.create(address(vault)));
    }

    function _registerNetwork(address user, address middleware) internal {
        vm.startPrank(user);
        networkRegistry.registerNetwork();
        networkMiddlewareService.setMiddleware(middleware);
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

    function _deposit(address user, uint256 amount) internal returns (uint256 shares) {
        collateral.transfer(user, amount);
        vm.startPrank(user);
        collateral.approve(address(vault), amount);
        shares = vault.deposit(user, amount);
        vm.stopPrank();
    }

    function _setNetworkWhitelistStatus(address user, address network, bool status) internal {
        vm.startPrank(user);
        defaultRewardsDistributor.setNetworkWhitelistStatus(network, status);
        vm.stopPrank();
    }

    function _distributeReward(
        address user,
        address network,
        address token,
        uint256 amount,
        uint48 timestamp
    ) internal {
        vm.startPrank(user);
        defaultRewardsDistributor.distributeReward(network, token, amount, timestamp);
        vm.stopPrank();
    }

    function _claimRewards(
        address user,
        address token,
        uint256 maxRewards,
        uint32[] memory activeSharesOfHints
    ) internal {
        vm.startPrank(user);
        defaultRewardsDistributor.claimRewards(user, token, maxRewards, activeSharesOfHints);
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

    function _claimAdminFee(address user, address token) internal {
        vm.startPrank(user);
        defaultRewardsDistributor.claimAdminFee(user, token);
        vm.stopPrank();
    }
}
