// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {AppAdapter} from "../../src/contracts/adapters/AppAdapter.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";
import {AdapterRegistry} from "../../src/contracts/AdapterRegistry.sol";
import {DelegatorFactory} from "../../src/contracts/DelegatorFactory.sol";
import {VaultFactory} from "../../src/contracts/VaultFactory.sol";
import {Entity} from "../../src/contracts/common/Entity.sol";
import {MigratableEntity} from "../../src/contracts/common/MigratableEntity.sol";
import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {ProtocolFeeRegistry} from "../../src/contracts/ProtocolFeeRegistry.sol";
import {VaultV2} from "../../src/contracts/vault/VaultV2.sol";
import {WithdrawalQueue} from "../../src/contracts/vault/WithdrawalQueue.sol";
import {WithdrawalQueueFactory} from "../../src/contracts/WithdrawalQueueFactory.sol";
import {IAppAdapter} from "../../src/interfaces/adapters/IAppAdapter.sol";
import {
    IUniversalDelegator,
    UNIVERSAL_DELEGATOR_TYPE,
    MAX_SHARE
} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../../src/interfaces/vault/IVaultV2.sol";
import {Token} from "../mocks/Token.sol";

contract AppAdapterUniversalMigratableEntityMock is MigratableEntity {
    constructor(address factory) MigratableEntity(factory) {}
}

contract AppAdapterUniversalAdapterFactoryMock is AdapterFactory {
    constructor(address owner) AdapterFactory(owner) {
        _addEntity(address(this));
    }
}

contract AppAdapterUniversalEntityMock is Entity {
    constructor(address factory, uint64 type_) Entity(factory, type_) {}
}

contract AppAdapterUniversalNetworkMiddlewareServiceMock {
    mapping(address network => address middleware) public middleware;

    function setMiddleware(address network, address middleware_) external {
        middleware[network] = middleware_;
    }
}

contract AppAdapterUniversalDelegatorTest is Test {
    using Subnetwork for address;

    address internal constant BURNER = address(0xB);
    address internal constant CURATOR = address(0xC);

    Token internal assetToken;
    VaultFactory internal vaultFactory;
    DelegatorFactory internal delegatorFactory;
    WithdrawalQueueFactory internal withdrawalQueueFactory;
    AdapterRegistry internal adapterRegistry;
    AdapterFactory internal adapterFactory;
    ProtocolFeeRegistry internal protocolFee;
    AppAdapterUniversalNetworkMiddlewareServiceMock internal networkMiddlewareService;

    VaultV2 internal vault;
    UniversalDelegator internal delegator;
    IAppAdapter internal adapter;

    address internal network = makeAddr("network");
    address internal networkMiddleware = makeAddr("networkMiddleware");
    address internal operator = makeAddr("operator");
    address internal relayer = makeAddr("relayer");
    address internal settlement = makeAddr("settlement");
    uint48 internal duration = 10;

    function setUp() public {
        vm.warp(100);

        assetToken = new Token("Asset");
        vaultFactory = new VaultFactory(address(this));
        withdrawalQueueFactory = new WithdrawalQueueFactory(address(this));
        delegatorFactory = new DelegatorFactory(address(this));
        adapterRegistry = new AdapterRegistry(address(this));
        adapterFactory = new AppAdapterUniversalAdapterFactoryMock(address(this));
        protocolFee = new ProtocolFeeRegistry(address(this));
        protocolFee.setGlobalReceiver(address(this));
        networkMiddlewareService = new AppAdapterUniversalNetworkMiddlewareServiceMock();
        networkMiddlewareService.setMiddleware(network, networkMiddleware);

        withdrawalQueueFactory.whitelist(address(new WithdrawalQueue(address(withdrawalQueueFactory))));

        vaultFactory.whitelist(address(new AppAdapterUniversalMigratableEntityMock(address(vaultFactory))));
        vaultFactory.whitelist(address(new AppAdapterUniversalMigratableEntityMock(address(vaultFactory))));
        vaultFactory.whitelist(
            address(
                new VaultV2(
                    address(vaultFactory),
                    address(delegatorFactory),
                    address(protocolFee),
                    address(withdrawalQueueFactory)
                )
            )
        );

        for (uint64 i; i < UNIVERSAL_DELEGATOR_TYPE; ++i) {
            delegatorFactory.whitelist(address(new AppAdapterUniversalEntityMock(address(delegatorFactory), i)));
        }
        delegatorFactory.whitelist(
            address(
                new UniversalDelegator(
                    UNIVERSAL_DELEGATOR_TYPE, address(vaultFactory), address(adapterRegistry), address(delegatorFactory)
                )
            )
        );

        vm.mockCall(settlement, abi.encodeWithSignature("vaultRelayer()"), abi.encode(relayer));
        adapterFactory.whitelist(
            address(
                new AppAdapter(
                    address(vaultFactory), address(adapterFactory), settlement, address(networkMiddlewareService)
                )
            )
        );

        vault = _createVault();
        delegator = _createDelegator(vault);
        vault.setDelegator(address(delegator));

        address[] memory converters = new address[](1);
        converters[0] = CURATOR;
        adapter = IAppAdapter(
            adapterFactory.create(
                1,
                CURATOR,
                abi.encode(
                    address(vault),
                    abi.encode(
                        IAppAdapter.InitParams({
                            subnetwork: network.subnetwork(1),
                            operator: operator,
                            duration: duration,
                            burner: BURNER,
                            converters: converters
                        })
                    )
                )
            )
        );
        adapterRegistry.setWhitelistedStatus(address(vault), address(adapter), true);
        delegator.addAdapter(address(adapter));
        delegator.setLimits(address(adapter), 100, MAX_SHARE);

        assetToken.approve(address(vault), 100);
        vault.deposit(100, address(this));
        delegator.allocate(address(adapter), 100);
    }

    function test_StakeDoesNotDecreaseInSameBlockAfterRealDelegatorForceDeallocate() public {
        uint256 observedStake = adapter.stake();

        delegator.forceDeallocate(address(adapter), 40);

        assertEq(adapter.stake(), observedStake);

        vm.warp(vm.getBlockTimestamp() + duration);

        assertEq(adapter.stake(), observedStake - 40);
    }

    function test_StakeDropsOneSecondAfterRealDelegatorForceDeallocate() public {
        uint256 observedStake = adapter.stake();

        delegator.forceDeallocate(address(adapter), 40);
        vm.warp(vm.getBlockTimestamp() + 1);

        assertEq(adapter.stake(), observedStake - 40);
    }

    function test_ObservedStakeAtSurvivesRealDelegatorForceDeallocateUntilDurationExpires() public {
        uint48 observedAt = uint48(vm.getBlockTimestamp());
        uint256 observedStake = adapter.stakeAt(observedAt);

        delegator.forceDeallocate(address(adapter), 40);

        assertEq(adapter.stakeAt(observedAt), observedStake);

        vm.warp(observedAt + duration - 1);

        assertEq(adapter.stakeAt(observedAt), observedStake);
    }

    function test_QueuedWithdrawalDoesNotFillBeforeAppAdapterDebtMatures() public {
        (WithdrawalQueue queue, uint256 tokenId, uint256 shares) = _requestAllocatedWithdrawal(1000);
        uint48 requestedAt = uint48(vm.getBlockTimestamp());
        uint256 observedStake = adapter.stakeAt(requestedAt);
        uint256 adapterAssets = adapter.totalAssets();
        uint16 adapterIndex = delegator.adapterToIndex(address(adapter));

        assertEq(queue.totalFilled(), 0);
        assertEq(queue.pendingShares(), shares);
        assertEq(delegator.adaptersWithPending(0), adapterIndex);

        delegator.sweepPending();

        assertEq(queue.totalFilled(), 0);
        assertEq(queue.pendingShares(), shares);
        assertEq(adapter.totalAssets(), adapterAssets);
        assertEq(adapter.stakeAt(requestedAt), observedStake);
        assertEq(delegator.adaptersWithPending(0), adapterIndex);

        vm.warp(requestedAt + duration - 1);
        delegator.sweepPending();

        assertEq(queue.totalFilled(), 0);
        assertEq(queue.pendingShares(), shares);
        assertEq(adapter.totalAssets(), adapterAssets);
        assertEq(adapter.stakeAt(requestedAt), observedStake);
        (, uint256 claimableShares) = queue.claimable(tokenId);

        assertEq(claimableShares, 0);
    }

    function test_SlashCanConsumeFullStakeInSameBlockAfterForceDeallocate() public {
        uint256 observedStake = adapter.stake();
        uint256 burnerBalanceBefore = assetToken.balanceOf(BURNER);

        delegator.forceDeallocate(address(adapter), 40);

        vm.prank(networkMiddleware);
        adapter.slash(observedStake);

        assertEq(assetToken.balanceOf(BURNER), burnerBalanceBefore + observedStake);
        assertEq(adapter.totalAssets(), 0);
        assertEq(adapter.slashable(), 0);
        assertEq(adapter.stake(), 0);

        vm.warp(vm.getBlockTimestamp() + duration);

        assertEq(adapter.totalAssets(), 0);
        assertEq(adapter.slashable(), 0);
        assertEq(adapter.stake(), 0);
    }

    function test_SlashDoesNotReduceMaxShareLimit() public {
        delegator.setLimits(address(adapter), type(uint256).max, MAX_SHARE);

        assetToken.approve(address(vault), 50);
        vault.deposit(50, address(this));
        assertEq(vault.freeAssets(), 50);

        vm.prank(networkMiddleware);
        adapter.slash(40);

        assertGt(delegator.limitOf(address(adapter)), adapter.totalAssets());
    }

    function test_DeallocateReturnsAllCurrentlyFreeAssetsAfterDebtMatures() public {
        delegator.forceDeallocate(address(adapter), 80);
        vm.warp(vm.getBlockTimestamp() + duration);

        uint256 freeAssetsBefore = vault.freeAssets();
        uint256 adapterAssetsBefore = adapter.totalAssets();
        uint256 adapterFreeAssetsBefore = adapter.freeAssets();

        uint256 deallocated = delegator.deallocate(address(adapter), 1);

        assertEq(deallocated, adapterFreeAssetsBefore);
        assertEq(vault.freeAssets(), freeAssetsBefore + adapterFreeAssetsBefore);
        assertEq(adapter.totalAssets(), adapterAssetsBefore - adapterFreeAssetsBefore);
    }

    function testFuzz_CumulativeDebtSmallerSecondForceDeallocate(uint256 firstSeed, uint256 secondSeed) public {
        uint256 total = adapter.totalAssets();
        uint256 first = bound(firstSeed, 1, total - 1);
        uint256 remaining = total - first;
        uint256 second = bound(secondSeed, 1, _min(first, remaining));

        delegator.forceDeallocate(address(adapter), first);
        vm.warp(vm.getBlockTimestamp() + duration);

        assertEq(delegator.deallocate(address(adapter), 1), first);
        assertEq(adapter.totalAssets(), remaining);
        assertEq(adapter.slashable(), remaining);
        assertEq(adapter.freeAssets(), 0);

        delegator.forceDeallocate(address(adapter), second);
        vm.warp(vm.getBlockTimestamp() + duration);

        assertEq(adapter.slashable(), remaining - second);
        assertEq(adapter.freeAssets(), second);
        assertEq(delegator.deallocate(address(adapter), 1), second);
        assertEq(adapter.totalAssets(), remaining - second);
    }

    function testFuzz_CumulativeDebtLargerSecondForceDeallocate(uint256 firstSeed, uint256 secondSeed) public {
        uint256 total = adapter.totalAssets();
        uint256 first = bound(firstSeed, 1, (total - 1) / 2);
        uint256 second = bound(secondSeed, first + 1, total - first);
        uint256 remaining = total - first;

        delegator.forceDeallocate(address(adapter), first);
        vm.warp(vm.getBlockTimestamp() + duration);

        assertEq(delegator.deallocate(address(adapter), 1), first);
        assertEq(adapter.totalAssets(), remaining);
        assertEq(adapter.slashable(), remaining);
        assertEq(adapter.freeAssets(), 0);

        delegator.forceDeallocate(address(adapter), second);
        vm.warp(vm.getBlockTimestamp() + duration);

        assertEq(adapter.slashable(), total - first - second);
        assertEq(adapter.freeAssets(), second);
        assertEq(delegator.deallocate(address(adapter), 1), second);
        assertEq(adapter.totalAssets(), total - first - second);
    }

    function test_ZeroRequestDoesNotRestoreSlashableWhenLimitIsBelowCurrentSlashable() public {
        uint256 total = adapter.totalAssets();

        delegator.forceDeallocate(address(adapter), 40);
        vm.warp(vm.getBlockTimestamp() + duration);
        delegator.setLimits(address(adapter), 30, MAX_SHARE);

        vm.prank(address(delegator));
        adapter.requestDeallocate(0);

        assertEq(adapter.slashable(), total - 40);
        assertEq(adapter.freeAssets(), 40);
    }

    function test_ZeroRequestPreservesImmatureForceDeallocateDebtWhenLimitWasReduced() public {
        uint256 total = adapter.totalAssets();
        uint256 amount = 40;
        uint48 requestedAt = uint48(vm.getBlockTimestamp());

        delegator.forceDeallocate(address(adapter), amount);

        assertEq(delegator.limitOf(address(adapter)), total - amount);
        assertEq(adapter.slashable(), total);
        assertEq(adapter.stake(), total);

        vm.prank(address(delegator));
        adapter.requestDeallocate(0);

        assertEq(adapter.slashable(), total);
        assertEq(adapter.stake(), total);

        vm.warp(requestedAt + 1);
        assertEq(adapter.stake(), total - amount);

        vm.warp(requestedAt + duration);
        assertEq(adapter.slashable(), total - amount);
        assertEq(adapter.freeAssets(), amount);
    }

    function test_ZeroRequestRestakesMatureFreeAssetsOnlyUpToLimit() public {
        uint256 total = adapter.totalAssets();

        delegator.forceDeallocate(address(adapter), 40);
        vm.warp(vm.getBlockTimestamp() + duration);

        assertEq(adapter.slashable(), 60);
        assertEq(adapter.freeAssets(), 40);

        delegator.setLimits(address(adapter), 70, MAX_SHARE);

        vm.prank(address(delegator));
        adapter.requestDeallocate(0);

        assertEq(adapter.totalAssets(), total);
        assertEq(adapter.slashable(), 70);
        assertEq(adapter.freeAssets(), 30);
        assertEq(delegator.deallocate(address(adapter), 1), 30);
        assertEq(adapter.totalAssets(), 70);
    }

    function test_SweepPendingFillsQueuedWithdrawalAfterDelayedAppAdapterDebt() public {
        address alice = address(0xA11CE);
        (WithdrawalQueue queue, uint256 tokenId, uint256 shares) = _requestAllocatedWithdrawal(1000);

        assertEq(queue.totalFilled(), 0);
        assertEq(queue.pendingShares(), shares);

        uint256 adapterAssetsBefore = adapter.totalAssets();

        vm.warp(vm.getBlockTimestamp() + duration);
        delegator.sweepPending();

        assertEq(queue.pendingShares(), 0);
        assertEq(queue.totalFilled(), shares);
        assertLt(adapter.totalAssets(), adapterAssetsBefore);

        (uint256 claimableAssets, uint256 claimableShares) = queue.claimable(tokenId);
        uint256 aliceBalanceBefore = assetToken.balanceOf(alice);

        assertGt(claimableAssets, 0);
        assertEq(claimableShares, shares);

        _claim(queue, tokenId);

        assertEq(assetToken.balanceOf(alice), aliceBalanceBefore + claimableAssets);
    }

    function test_LimitReductionDoesNotLockSequentialQueuedWithdrawalsWithoutLimitIncrease() public {
        WithdrawalQueue queue = WithdrawalQueue(vault.withdrawalQueue());

        delegator.setLimits(address(adapter), 30, MAX_SHARE);

        vault.approve(address(queue), 60);
        queue.requestRedeem(60, address(this));

        vm.warp(vm.getBlockTimestamp() + duration);
        delegator.sweepPending();

        assertEq(queue.pendingShares(), 0);
        assertEq(adapter.totalAssets(), 40);
        assertEq(adapter.slashable(), 40);
        assertEq(adapter.freeAssets(), 0);
        assertEq(delegator.limitOf(address(adapter)), 30);
        assertLt(delegator.limitOf(address(adapter)), adapter.totalAssets());

        vault.approve(address(queue), 40);
        uint256 secondTokenId = queue.requestRedeem(40, address(this));

        assertEq(queue.pendingShares(), 40);

        vm.warp(vm.getBlockTimestamp() + duration);
        delegator.sweepPending();

        assertEq(queue.pendingShares(), 0);
        assertEq(adapter.totalAssets(), 0);

        (uint256 claimableAssets, uint256 claimableShares) = queue.claimable(secondTokenId);

        assertEq(claimableShares, 40);
        assertEq(claimableAssets, 40);
    }

    function testFuzz_ResetPreservesRemainingSlashableAboveLimit(uint256 firstSeed, uint256 limitSeed) public {
        WithdrawalQueue queue = WithdrawalQueue(vault.withdrawalQueue());
        uint256 total = adapter.totalAssets();
        uint256 first = bound(firstSeed, 1, total - 1);
        uint256 remaining = total - first;
        uint256 limit = bound(limitSeed, 0, remaining - 1);

        delegator.setLimits(address(adapter), limit, MAX_SHARE);

        vault.approve(address(queue), first);
        queue.requestRedeem(first, address(this));

        vm.warp(vm.getBlockTimestamp() + duration);
        delegator.sweepPending();

        assertEq(queue.pendingShares(), 0);
        assertEq(adapter.totalAssets(), remaining);
        assertEq(adapter.slashable(), remaining);
        assertEq(adapter.freeAssets(), 0);
        assertLt(delegator.limitOf(address(adapter)), adapter.totalAssets());
    }

    function testFuzz_AllocationDeltaNeverExceedsLimitHeadroom(
        uint256 limitSeed,
        uint256 freeAssetsSeed,
        uint256 amountSeed,
        uint8 mode
    ) public {
        uint256 limit = bound(limitSeed, 0, 200);
        uint256 freeAssets = bound(freeAssetsSeed, 1, 100);

        delegator.setLimits(address(adapter), limit, MAX_SHARE);
        _setAutoAllocateAdapter();
        assetToken.transfer(address(vault), freeAssets);

        uint256 adapterAssetsBefore = adapter.totalAssets();
        uint256 headroom = _headroom(delegator.limitOf(address(adapter)), adapterAssetsBefore);
        uint256 amount = bound(amountSeed, 0, freeAssets + 100);

        mode %= 3;
        if (mode == 0) {
            delegator.allocate(address(adapter), amount);
        } else if (mode == 1) {
            delegator.allocateAll(amount);
        } else {
            delegator.allocateExact(address(adapter), amount);
        }

        uint256 adapterAssetsAfter = adapter.totalAssets();
        uint256 increase = adapterAssetsAfter > adapterAssetsBefore ? adapterAssetsAfter - adapterAssetsBefore : 0;
        assertLe(increase, headroom);
    }

    function testFuzz_SequentialTailDrainsWithoutLimitIncrease(uint256 firstSeed, uint256 secondSeed, uint256 limitSeed)
        public
    {
        WithdrawalQueue queue = WithdrawalQueue(vault.withdrawalQueue());
        uint256 total = adapter.totalAssets();
        uint256 first = bound(firstSeed, 1, total - 1);
        uint256 remaining = total - first;
        uint256 second = bound(secondSeed, 1, remaining);
        uint256 limit = bound(limitSeed, 0, remaining - 1);

        delegator.setLimits(address(adapter), limit, MAX_SHARE);

        vault.approve(address(queue), first);
        queue.requestRedeem(first, address(this));

        vm.warp(vm.getBlockTimestamp() + duration);
        delegator.sweepPending();

        assertEq(queue.pendingShares(), 0);
        assertEq(adapter.totalAssets(), remaining);
        assertEq(adapter.slashable(), remaining);
        assertEq(adapter.freeAssets(), 0);
        assertLt(delegator.limitOf(address(adapter)), adapter.totalAssets());

        uint256 absoluteLimitBefore = delegator.absoluteLimitOf(address(adapter));
        uint256 shareLimitBefore = delegator.shareLimitOf(address(adapter));

        vault.approve(address(queue), second);
        uint256 secondTokenId = queue.requestRedeem(second, address(this));

        vm.warp(vm.getBlockTimestamp() + duration);
        delegator.sweepPending();

        assertEq(delegator.absoluteLimitOf(address(adapter)), absoluteLimitBefore);
        assertEq(delegator.shareLimitOf(address(adapter)), shareLimitBefore);
        assertEq(queue.pendingShares(), 0);
        assertEq(adapter.totalAssets(), remaining - second);

        (uint256 claimableAssets, uint256 claimableShares) = queue.claimable(secondTokenId);

        assertEq(claimableShares, second);
        assertEq(claimableAssets, second);
    }

    function test_DirectFillUsesVaultWithdrawableDeallocatableAndReturnsExactTuple() public {
        (WithdrawalQueue queue, uint256 tokenId, uint256 shares) = _requestAllocatedWithdrawal(1000);
        uint256 queueBalanceBefore = assetToken.balanceOf(address(queue));
        uint256 adapterAssetsBefore = adapter.totalAssets();

        vm.warp(vm.getBlockTimestamp() + duration);
        (uint256 assetsFilled, uint256 sharesFilled) = queue.fill();

        assertEq(sharesFilled, shares);
        assertEq(assetsFilled, assetToken.balanceOf(address(queue)) - queueBalanceBefore);
        assertEq(queue.totalFilled(), shares);
        assertEq(queue.pendingShares(), 0);
        assertLt(adapter.totalAssets(), adapterAssetsBefore);

        (uint256 claimableAssets, uint256 claimableShares) = queue.claimable(tokenId);
        uint256 aliceBalanceBefore = assetToken.balanceOf(address(0xA11CE));

        assertEq(claimableAssets, assetsFilled);
        assertEq(claimableShares, shares);

        _claim(queue, tokenId);

        assertEq(assetToken.balanceOf(address(0xA11CE)), aliceBalanceBefore + assetsFilled);
    }

    function test_WithdrawSweepsPendingBeforeComputingSharesToBurn() public {
        WithdrawalQueue queue = _preparePendingQueueWithYield();

        uint256 sharesBefore = vault.balanceOf(address(this));
        uint256 withdrawAssets = 15;
        uint256 expectedShares = _previewWithdrawAfterExplicitSweep(withdrawAssets);
        uint256 receiverBalanceBefore = assetToken.balanceOf(address(this));

        uint256 burnedShares = vault.withdraw(withdrawAssets, address(this), address(this));

        assertEq(queue.pendingShares(), 0);
        assertEq(burnedShares, expectedShares);
        assertEq(vault.balanceOf(address(this)), sharesBefore - expectedShares);
        assertEq(assetToken.balanceOf(address(this)), receiverBalanceBefore + withdrawAssets);
    }

    function test_RedeemSweepsPendingBeforeComputingAssetsToReturn() public {
        WithdrawalQueue queue = _preparePendingQueueWithYield();

        uint256 shares = 7;
        uint256 expectedAssets = _previewRedeemAfterExplicitSweep(shares);
        uint256 receiverBalanceBefore = assetToken.balanceOf(address(this));

        uint256 redeemedAssets = vault.redeem(shares, address(this), address(this));

        assertEq(queue.pendingShares(), 0);
        assertEq(redeemedAssets, expectedAssets);
        assertEq(vault.balanceOf(address(this)), 100 - shares);
        assertEq(assetToken.balanceOf(address(this)), receiverBalanceBefore + expectedAssets);
    }

    function _requestAllocatedWithdrawal(uint256 assets)
        internal
        returns (WithdrawalQueue queue, uint256 tokenId, uint256 shares)
    {
        address alice = address(0xA11CE);

        deal(address(assetToken), alice, assets);
        vm.startPrank(alice);
        assetToken.approve(address(vault), assets);
        shares = vault.deposit(assets, alice);
        vm.stopPrank();

        delegator.setLimits(address(adapter), type(uint256).max, MAX_SHARE);
        delegator.allocate(address(adapter), type(uint256).max);

        assertEq(vault.freeAssets(), 0);

        queue = WithdrawalQueue(vault.withdrawalQueue());

        vm.startPrank(alice);
        vault.approve(address(queue), shares);
        tokenId = queue.requestRedeem(shares, alice);
        vm.stopPrank();
    }

    function _claim(WithdrawalQueue queue, uint256 tokenId) internal returns (uint256 assets, uint256 shares) {
        address owner = queue.ownerOf(tokenId);
        vm.prank(owner);
        return queue.claim(tokenId, owner);
    }

    function _setAutoAllocateAdapter() internal {
        address[] memory autoAllocateAdapters = new address[](1);
        autoAllocateAdapters[0] = address(adapter);
        delegator.setAutoAllocateAdapters(autoAllocateAdapters);
    }

    function _headroom(uint256 limit, uint256 assets) internal pure returns (uint256) {
        return limit > assets ? limit - assets : 0;
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _preparePendingQueueWithYield() internal returns (WithdrawalQueue queue) {
        (queue,,) = _requestAllocatedWithdrawal(100);
        assetToken.transfer(address(vault), 229);

        assertGt(queue.pendingShares(), 0);
        assertEq(vault.balanceOf(address(this)), 100);
    }

    function _previewWithdrawAfterExplicitSweep(uint256 assets) internal returns (uint256 shares) {
        uint256 snapshotId = vm.snapshotState();
        delegator.sweepPending();
        shares = vault.previewWithdraw(assets);
        assertTrue(vm.revertToState(snapshotId));
    }

    function _previewRedeemAfterExplicitSweep(uint256 shares) internal returns (uint256 assets) {
        uint256 snapshotId = vm.snapshotState();
        delegator.sweepPending();
        assets = vault.previewRedeem(shares);
        assertTrue(vm.revertToState(snapshotId));
    }

    function _createVault() internal returns (VaultV2) {
        bytes memory data = abi.encode(
            IVaultV2.InitParams({
                name: "Vault",
                symbol: "vTKN",
                asset: address(assetToken),
                depositWhitelist: false,
                depositorToWhitelist: address(this),
                isDepositLimit: false,
                depositLimit: 0,
                defaultAdminRoleHolder: address(this),
                depositWhitelistSetRoleHolder: address(this),
                depositorWhitelistRoleHolder: address(this),
                isDepositLimitSetRoleHolder: address(this),
                depositLimitSetRoleHolder: address(this),
                managementFeeRoleHolder: address(this),
                performanceFeeRoleHolder: address(this)
            })
        );
        return VaultV2(vaultFactory.create(VAULT_V2_VERSION, address(this), data));
    }

    function _createDelegator(VaultV2 targetVault) internal returns (UniversalDelegator) {
        address delegatorAddress = delegatorFactory.create(
            UNIVERSAL_DELEGATOR_TYPE,
            abi.encode(
                address(targetVault),
                abi.encode(
                    IUniversalDelegator.InitParams({
                        defaultAdminRoleHolder: address(this),
                        addAdapterRoleHolder: address(this),
                        removeAdapterRoleHolder: address(this),
                        setAdapterLimitsRoleHolder: address(this),
                        setAutoAllocateAdaptersRoleHolder: address(this),
                        swapAdaptersRoleHolder: address(this),
                        allocateRoleHolder: address(this),
                        deallocateRoleHolder: address(this)
                    })
                )
            )
        );

        return UniversalDelegator(delegatorAddress);
    }
}
