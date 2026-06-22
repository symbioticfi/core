// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {AppAdapter} from "../../src/contracts/adapters/AppAdapter.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";

import {IAdapter} from "../../src/interfaces/adapters/IAdapter.sol";
import {IAppAdapter, BURNER_GAS_LIMIT} from "../../src/interfaces/adapters/IAppAdapter.sol";
import {MAX_SHARE} from "../../src/interfaces/delegator/IUniversalDelegator.sol";

import {Token} from "../mocks/Token.sol";

contract AppAdapterTest is Test {
    using Subnetwork for address;

    AppAdapterRegistryMock internal vaultFactory;
    AdapterFactory internal factory;
    AppAdapterVaultMock internal vault;
    AppAdapterDelegatorMock internal delegator;
    AppAdapterNetworkMiddlewareServiceMock internal networkMiddlewareService;
    Token internal assetToken;
    IAppAdapter internal adapter;

    bytes32 internal subnetwork;
    address internal network = makeAddr("network");
    address internal networkMiddleware = makeAddr("networkMiddleware");
    address internal operator = makeAddr("operator");
    address internal curator = makeAddr("curator");
    address internal burner = makeAddr("burner");
    address internal relayer = makeAddr("relayer");
    address internal settlement = makeAddr("settlement");
    uint48 internal duration = 10;

    function setUp() public {
        vm.warp(100);

        vaultFactory = new AppAdapterRegistryMock();
        factory = new AdapterFactory(address(this));
        delegator = new AppAdapterDelegatorMock();
        networkMiddlewareService = new AppAdapterNetworkMiddlewareServiceMock();
        assetToken = new Token("Asset");
        vault = new AppAdapterVaultMock(address(assetToken), address(delegator));
        vaultFactory.add(address(vault));

        subnetwork = network.subnetwork(1);
        networkMiddlewareService.setMiddleware(network, networkMiddleware);

        vm.mockCall(settlement, abi.encodeWithSignature("vaultRelayer()"), abi.encode(relayer));
        AppAdapter implementation =
            new AppAdapter(address(vaultFactory), address(factory), settlement, address(networkMiddlewareService));
        factory.whitelist(address(implementation));

        adapter = _createAdapter();
    }

    function test_StakeUsesDurationShiftedCheckpoint() public {
        uint48 timestamp = uint48(vm.getBlockTimestamp());

        _allocate(100);

        assertEq(adapter.stake(), 100);
        assertEq(adapter.stakeAt(timestamp), 100);
        assertEq(adapter.stakeAt(timestamp - 1), 0);
    }

    function test_InitializeStoresConfiguredBurner() public view {
        assertEq(adapter.burner(), burner);
        assertEq(AppAdapter(address(adapter)).owner(), curator);
        assertEq(adapter.converters(0), curator);
    }

    function test_InitializeRejectsZeroBurner() public {
        vm.expectRevert(IAppAdapter.NoBurner.selector);

        factory.create(1, curator, _initData(address(0)));
    }

    function test_InitializeRejectsInvalidNetworkOperatorAndDuration() public {
        vm.expectRevert(IAppAdapter.InvalidNetOrOp.selector);
        factory.create(1, curator, _initData(bytes32(0), operator, duration, burner));

        vm.expectRevert(IAppAdapter.InvalidNetOrOp.selector);
        factory.create(1, curator, _initData(subnetwork, address(0), duration, burner));

        vm.expectRevert(IAppAdapter.InvalidDuration.selector);
        factory.create(1, curator, _initData(subnetwork, operator, 0, burner));
    }

    function test_RewardTransfersAssetsFromCallerToAdapter() public {
        address rewarder = makeAddr("rewarder");
        uint256 amount = 123;

        assetToken.transfer(rewarder, amount);

        vm.startPrank(rewarder);
        assetToken.approve(address(adapter), amount);
        adapter.reward(address(assetToken), amount);
        vm.stopPrank();

        assertEq(assetToken.balanceOf(rewarder), 0);
        assertEq(assetToken.balanceOf(address(adapter)), amount);
    }

    function test_DeallocationPreservesStakeUntilDurationAndSettlesAfterDuration() public {
        _allocate(100);

        delegator.requestDeallocate(address(adapter), 40);

        assertEq(adapter.stake(), 100);

        vm.warp(vm.getBlockTimestamp() + duration);

        assertEq(adapter.stake(), 60);

        uint256 deallocated = delegator.deallocate(address(adapter), 40);

        assertEq(deallocated, 40);
        assertEq(adapter.stake(), 60);
    }

    function test_RequestDeallocateDoesNotDecreaseStakeInSameBlock() public {
        _allocate(100);

        uint256 beforeStake = adapter.stake();

        delegator.requestDeallocate(address(adapter), 40);

        assertGe(adapter.stake(), beforeStake);
    }

    function test_StakeAtPreservesEndOfBlockStakeAfterLaterRequestDeallocate() public {
        _allocate(100);

        uint48 timestamp = uint48(vm.getBlockTimestamp());
        uint256 endOfBlockStake = adapter.stake();

        vm.warp(vm.getBlockTimestamp() + 1);
        delegator.requestDeallocate(address(adapter), 40);

        assertEq(adapter.stakeAt(timestamp), endOfBlockStake);
    }

    function test_GuaranteeRemainsSlashableUntilHalfOpenExpiry() public {
        _allocate(100);

        uint48 timestamp = uint48(vm.getBlockTimestamp());
        uint256 guaranteed = adapter.stake();

        delegator.requestDeallocate(address(adapter), 40);

        for (uint48 dt; dt < duration; ++dt) {
            vm.warp(timestamp + dt);
            assertGe(adapter.slashable(), guaranteed);
        }

        vm.warp(timestamp + duration);

        assertEq(adapter.slashable(), guaranteed - 40);
    }

    function test_DeallocationDebtUsesCurrentAssetsWhenLimitExceedsAssets() public {
        _allocate(100);
        delegator.setLimit(type(uint256).max);

        delegator.requestDeallocate(address(adapter), 40);

        assertEq(adapter.stake(), 100);
        assertEq(adapter.freeAssets(), 0);

        vm.warp(vm.getBlockTimestamp() + duration);

        assertEq(adapter.stake(), 60);
        assertEq(adapter.freeAssets(), 40);

        uint256 deallocated = delegator.deallocate(address(adapter), 40);

        assertEq(deallocated, 40);
        assertEq(adapter.totalAssets(), 60);
    }

    function test_DeallocateReturnsAllCurrentlyFreeAssets() public {
        _allocate(100);

        delegator.requestDeallocate(address(adapter), 80);
        vm.warp(vm.getBlockTimestamp() + duration);

        uint256 vaultBalanceBefore = assetToken.balanceOf(address(vault));
        uint256 adapterAssetsBefore = adapter.totalAssets();

        uint256 deallocated = delegator.deallocate(address(adapter), 1);

        assertEq(deallocated, 80);
        assertEq(adapter.totalAssets(), adapterAssetsBefore - 80);
        assertEq(assetToken.balanceOf(address(vault)), vaultBalanceBefore + 80);
    }

    function test_RequestDeallocateKeepsRemainingAssetsSlashableWhenLimitIsLower() public {
        _allocate(100);
        delegator.setLimit(30);

        delegator.requestDeallocate(address(adapter), 60);
        vm.warp(vm.getBlockTimestamp() + duration);

        assertEq(adapter.slashable(), 40);
        assertEq(adapter.freeAssets(), 60);
        assertEq(delegator.deallocate(address(adapter), 1), 60);
        assertEq(adapter.totalAssets(), 40);
    }

    function test_ZeroRequestKeepsImmatureDebtWhenLimitIsBelowCurrentSlashable() public {
        _allocate(100);
        uint48 requestedAt = uint48(vm.getBlockTimestamp());

        delegator.requestDeallocate(address(adapter), 40);
        delegator.setLimit(60);

        assertEq(adapter.slashable(), 100);
        assertEq(adapter.stake(), 100);

        delegator.requestDeallocate(address(adapter), 0);

        assertEq(adapter.slashable(), 100);
        assertEq(adapter.stake(), 100);

        vm.warp(requestedAt + duration);

        assertEq(adapter.slashable(), 60);
        assertEq(adapter.freeAssets(), 40);
        assertEq(delegator.deallocate(address(adapter), 1), 40);
        assertEq(adapter.totalAssets(), 60);
    }

    function testFuzz_ZeroRequestKeepsImmatureDebtWhenLimitIsBelowCurrentSlashable(
        uint256 totalSeed,
        uint256 amountSeed,
        uint256 limitSeed,
        uint256 elapsedSeed
    ) public {
        uint256 total = bound(totalSeed, 2, 1_000_000);
        uint256 amount = bound(amountSeed, 1, total - 1);
        uint256 limit = bound(limitSeed, 0, total - 1);
        uint256 elapsed = bound(elapsedSeed, 0, duration - 1);

        _allocate(total);
        uint48 requestedAt = uint48(vm.getBlockTimestamp());

        delegator.requestDeallocate(address(adapter), amount);
        delegator.setLimit(limit);

        vm.warp(requestedAt + elapsed);
        delegator.requestDeallocate(address(adapter), 0);

        assertEq(adapter.slashable(), total);

        vm.warp(requestedAt + duration);

        assertEq(adapter.slashable(), total - amount);
        assertEq(adapter.freeAssets(), amount);
        assertEq(delegator.deallocate(address(adapter), 1), amount);
        assertEq(adapter.totalAssets(), total - amount);
    }

    function test_RequestDeallocateDecreaseCapsRestakedAssetsAtLimit() public {
        _allocate(100);
        delegator.setLimit(30);

        delegator.requestDeallocate(address(adapter), 80);
        vm.warp(vm.getBlockTimestamp() + duration);

        assertEq(adapter.slashable(), 20);

        delegator.requestDeallocate(address(adapter), 60);

        assertEq(adapter.slashable(), 30);
        assertEq(adapter.freeAssets(), 70);
        assertEq(delegator.deallocate(address(adapter), 1), 70);
        assertEq(adapter.totalAssets(), 30);
    }

    function testFuzz_RequestDeallocateDecreaseCapsRestakedAssetsAtLimit(
        uint256 totalSeed,
        uint256 limitSeed,
        uint256 firstSeed,
        uint256 secondSeed
    ) public {
        uint256 total = bound(totalSeed, 3, 1_000_000);
        uint256 limit = bound(limitSeed, 1, total - 2);
        uint256 first = bound(firstSeed, total - limit + 1, total);
        uint256 second = bound(secondSeed, 1, total - limit - 1);

        _allocate(total);
        delegator.setLimit(limit);

        delegator.requestDeallocate(address(adapter), first);
        vm.warp(vm.getBlockTimestamp() + duration);

        assertLt(adapter.slashable(), limit);

        delegator.requestDeallocate(address(adapter), second);

        assertEq(adapter.slashable(), limit);
        assertEq(adapter.freeAssets(), adapter.totalAssets() - limit);
        assertLe(adapter.slashable(), delegator.limitOf(address(adapter)));
        assertEq(delegator.deallocate(address(adapter), 1), total - limit);
        assertEq(adapter.totalAssets(), limit);
    }

    function test_RequestDeallocateDecreaseCapsRestakedAssetsWhenLimitEqualsSlashable() public {
        _allocate(100);
        delegator.setLimit(20);

        delegator.requestDeallocate(address(adapter), 80);
        vm.warp(vm.getBlockTimestamp() + duration);

        assertEq(adapter.slashable(), 20);

        delegator.requestDeallocate(address(adapter), 60);

        assertEq(adapter.slashable(), 20);
        assertEq(adapter.freeAssets(), 80);
        assertEq(delegator.deallocate(address(adapter), 1), 80);
        assertEq(adapter.totalAssets(), 20);
    }

    function test_RequestDeallocateAddsDebtAfterPreviousDebtSettledAndAssetsLeft() public {
        _allocate(100);

        delegator.requestDeallocate(address(adapter), 60);
        vm.warp(vm.getBlockTimestamp() + duration);

        assertEq(delegator.deallocate(address(adapter), 60), 60);
        assertEq(adapter.totalAssets(), 40);
        assertEq(adapter.slashable(), 40);
        assertEq(adapter.freeAssets(), 0);

        delegator.requestDeallocate(address(adapter), 40);
        vm.warp(vm.getBlockTimestamp() + duration);

        assertEq(adapter.slashable(), 0);
        assertEq(adapter.freeAssets(), 40);
        assertEq(delegator.deallocate(address(adapter), 40), 40);
        assertEq(adapter.totalAssets(), 0);
    }

    function test_SyncClosesPendingByRestoringStake() public {
        _allocate(100);

        delegator.requestDeallocate(address(adapter), 40);

        assertEq(adapter.stake(), 100);

        delegator.sync(address(adapter));
        assertEq(adapter.stake(), 100);
    }

    function test_SlashRejectsCallerOutsideConfiguredNetworkMiddleware() public {
        _allocate(100);

        address otherNetwork = makeAddr("otherNetwork");
        address otherMiddleware = makeAddr("otherMiddleware");
        networkMiddlewareService.setMiddleware(otherNetwork, otherMiddleware);

        vm.expectRevert(IAppAdapter.NotNetworkMiddleware.selector);
        vm.prank(otherMiddleware);
        adapter.slash(100);
    }

    function test_SlashUsesConfiguredPairAndBurnsSlashedAmount() public {
        _allocate(100);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit IAppAdapter.Slash(40);

        vm.prank(networkMiddleware);
        adapter.slash(40);

        assertEq(adapter.totalAssets(), 60);
        assertEq(adapter.slashable(), 60);
        assertEq(delegator.decreaseLimitsCalls(), 1);
        assertEq(delegator.lastDecreaseAssets(), 40);
        assertEq(delegator.lastDecreaseShare(), 0);
        assertEq(assetToken.balanceOf(burner), 40);
    }

    function test_SlashSweepsPendingBeforeDecreasingLimits() public {
        _allocate(100);

        vm.prank(networkMiddleware);
        adapter.slash(40);

        assertEq(delegator.sweepPendingCalls(), 1);
        assertTrue(delegator.sweepPendingBeforeDecrease());
    }

    function test_SlashSaturatesAtCurrentSlashable() public {
        _allocate(100);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit IAppAdapter.Slash(100);

        vm.prank(networkMiddleware);
        adapter.slash(150);

        assertEq(adapter.totalAssets(), 0);
        assertEq(adapter.slashable(), 0);
        assertEq(adapter.stake(), 0);
        assertEq(assetToken.balanceOf(burner), 100);
        assertEq(delegator.lastDecreaseAssets(), 100);
        assertEq(delegator.lastDecreaseShare(), 0);
    }

    function test_ReleaseCanBeCalledByNetworkAndReleasesRequestedSlashableWithoutMovingAssets() public {
        _allocate(100);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit IAppAdapter.Release(40);

        vm.prank(network);
        adapter.release(40);

        assertEq(adapter.totalAssets(), 100);
        assertEq(adapter.slashable(), 60);
        assertEq(adapter.stake(), 60);
        assertEq(adapter.freeAssets(), 40);
        assertEq(assetToken.balanceOf(burner), 0);
        assertEq(delegator.decreaseLimitsCalls(), 1);
        assertEq(delegator.lastDecreaseAssets(), 40);
        assertEq(delegator.lastDecreaseShare(), 0);
    }

    function test_ReleaseSaturatesAtSlashableAndClearsWithoutMovingAssets() public {
        _allocate(100);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit IAppAdapter.Release(100);

        vm.prank(network);
        adapter.release(150);

        assertEq(adapter.totalAssets(), 100);
        assertEq(adapter.slashable(), 0);
        assertEq(adapter.stake(), 0);
        assertEq(adapter.freeAssets(), 100);
        assertEq(assetToken.balanceOf(burner), 0);
        assertEq(delegator.decreaseLimitsCalls(), 1);
        assertEq(delegator.lastDecreaseAssets(), 100);
        assertEq(delegator.lastDecreaseShare(), 0);
    }

    function test_ReleaseCanBeCalledByNetworkMiddleware() public {
        _allocate(100);

        vm.prank(networkMiddleware);
        adapter.release(40);

        assertEq(adapter.slashable(), 60);
        assertEq(adapter.freeAssets(), 40);
    }

    function test_ReleaseRejectsCallerOutsideNetworkAndMiddleware() public {
        _allocate(100);

        vm.expectRevert(IAppAdapter.NotNetworkOrMiddleware.selector);
        adapter.release(40);
    }

    function test_ReleaseCanBeCalledWithoutExistingSlashable() public {
        vm.expectEmit(true, true, true, true, address(adapter));
        emit IAppAdapter.Release(0);

        vm.prank(network);
        adapter.release(type(uint256).max);

        assertEq(adapter.totalAssets(), 0);
        assertEq(adapter.slashable(), 0);
        assertEq(adapter.stake(), 0);
        assertEq(adapter.freeAssets(), 0);
        assertEq(delegator.decreaseLimitsCalls(), 1);
        assertEq(delegator.lastDecreaseAssets(), 0);
        assertEq(delegator.lastDecreaseShare(), 0);
    }

    function test_ReleaseCanBeCalledAfterSlashableWasAlreadyCleared() public {
        _allocate(100);
        vm.prank(network);
        adapter.release(type(uint256).max);

        assertEq(adapter.totalAssets(), 100);
        assertEq(adapter.slashable(), 0);
        assertEq(adapter.stake(), 0);
        assertEq(adapter.freeAssets(), 100);

        vm.prank(network);
        adapter.release(type(uint256).max);

        assertEq(adapter.totalAssets(), 100);
        assertEq(adapter.slashable(), 0);
        assertEq(adapter.stake(), 0);
        assertEq(adapter.freeAssets(), 100);
    }

    function test_SlashTransfersToBurnerAndCallsHook() public {
        AppAdapterBurnerMock burnerMock = new AppAdapterBurnerMock();
        IAppAdapter localAdapter = _createAdapter(address(burnerMock));
        _allocate(localAdapter, 100);

        vm.prank(networkMiddleware);
        localAdapter.slash(40);

        assertEq(burnerMock.calls(), 1);
        assertEq(burnerMock.lastSubnetwork(), subnetwork);
        assertEq(burnerMock.lastOperator(), operator);
        assertEq(burnerMock.lastAmount(), 40);
        assertEq(burnerMock.lastCaptureTimestamp(), 0);
        assertEq(assetToken.balanceOf(address(burnerMock)), 40);
    }

    function test_RepeatedSlashInSameBlockUpdatesSlashedCheckpoint() public {
        _allocate(100);

        vm.startPrank(networkMiddleware);
        adapter.slash(10);
        adapter.slash(15);
        vm.stopPrank();

        assertEq(adapter.stake(), 75);
        assertEq(adapter.slashable(), 75);
        assertEq(assetToken.balanceOf(burner), 25);
    }

    function test_SlashRevertsWithInsufficientBurnerGas() public {
        _allocate(100);

        vm.expectRevert(IAppAdapter.InsufficientBurnerGas.selector);
        vm.prank(networkMiddleware);
        adapter.slash{gas: BURNER_GAS_LIMIT + 80_000}(40);
    }

    function test_ZeroStateViewsReturnZeroAndSlashReverts() public {
        assertEq(adapter.stake(), 0);
        assertEq(adapter.slashable(), 0);
        assertEq(adapter.freeAssets(), 0);

        vm.expectRevert(IAppAdapter.InsufficientSlash.selector);
        vm.prank(networkMiddleware);
        adapter.slash(0);

        vm.expectRevert(IAppAdapter.InsufficientSlash.selector);
        vm.prank(networkMiddleware);
        adapter.slash(1);
    }

    function test_MigrateRevertsBecauseUnsupported() public {
        vm.mockCall(settlement, abi.encodeWithSignature("vaultRelayer()"), abi.encode(relayer));
        AppAdapter implementation =
            new AppAdapter(address(vaultFactory), address(factory), settlement, address(networkMiddlewareService));
        factory.whitelist(address(implementation));
        uint64 version = factory.lastVersion();

        vm.expectRevert();
        vm.prank(curator);
        factory.migrate(address(adapter), version, "");
    }

    function _allocate(uint256 amount) internal {
        _allocate(adapter, amount);
    }

    function _allocate(IAppAdapter targetAdapter, uint256 amount) internal {
        assetToken.transfer(address(targetAdapter), amount);

        delegator.allocate(address(targetAdapter), amount);
    }

    function _createAdapter() internal returns (IAppAdapter) {
        return _createAdapter(burner);
    }

    function _createAdapter(address initBurner) internal returns (IAppAdapter) {
        return IAppAdapter(factory.create(1, curator, _initData(initBurner)));
    }

    function _initData() internal view returns (bytes memory) {
        return _initData(burner);
    }

    function _initData(address initBurner) internal view returns (bytes memory) {
        return _initData(subnetwork, operator, duration, initBurner);
    }

    function _initData(bytes32 initSubnetwork, address initOperator, uint48 initDuration, address initBurner)
        internal
        view
        returns (bytes memory)
    {
        address[] memory converters = new address[](1);
        converters[0] = curator;
        return abi.encode(
            address(vault),
            abi.encode(
                IAppAdapter.InitParams({
                    subnetwork: initSubnetwork,
                    operator: initOperator,
                    duration: initDuration,
                    burner: initBurner,
                    converters: converters
                })
            )
        );
    }
}

contract AppAdapterRegistryMock is Registry {
    function add(address entity) external {
        _addEntity(entity);
    }
}

contract AppAdapterDelegatorMock {
    uint256 public decreaseLimitsCalls;
    uint256 public sweepPendingCalls;
    uint256 public lastDecreaseAssets;
    uint256 public lastDecreaseShare;
    uint256 public limitOverride;
    bool public isLimitOverride;
    bool public sweepPendingBeforeDecrease;

    function allocate(address adapter, uint256 amount) external {
        IAdapter(adapter).allocate(amount);
    }

    function deallocate(address adapter, uint256 amount) external returns (uint256 deallocated) {
        deallocated = IAdapter(adapter).deallocate(amount);
        if (deallocated > 0) {
            AppAdapterVaultMock(IAdapter(adapter).vault()).push(deallocated, adapter);
        }
    }

    function requestDeallocate(address adapter, uint256 amount) external {
        IAdapter(adapter).requestDeallocate(amount);
    }

    function setLimit(uint256 limit) external {
        limitOverride = limit;
        isLimitOverride = true;
    }

    function sync(address adapter) external {
        IAdapter(adapter).requestDeallocate(0);
    }

    function limitOf(address adapter) external view returns (uint256) {
        if (isLimitOverride) {
            return limitOverride;
        }
        return IAdapter(adapter).totalAssets();
    }

    function absoluteLimitOf(address adapter) external view returns (uint256) {
        return IAdapter(adapter).totalAssets();
    }

    function sweepPending() external returns (uint256) {
        ++sweepPendingCalls;
        return 0;
    }

    function decreaseLimits(uint256 assets, uint256 share) external {
        sweepPendingBeforeDecrease = sweepPendingCalls > 0;
        ++decreaseLimitsCalls;
        lastDecreaseAssets = assets;
        lastDecreaseShare = share;
    }
}

contract AppAdapterNetworkMiddlewareServiceMock {
    mapping(address network => address middleware) public middleware;

    function setMiddleware(address network, address middleware_) external {
        middleware[network] = middleware_;
    }
}

contract AppAdapterVaultMock {
    address public immutable assetToken;
    address public delegator;

    constructor(address assetToken_, address delegator_) {
        assetToken = assetToken_;
        delegator = delegator_;
    }

    function setDelegator(address delegator_) external {
        delegator = delegator_;
    }

    function asset() external view returns (address) {
        return assetToken;
    }

    function push(uint256 amount, address from) external {
        Token(assetToken).transferFrom(from, address(this), amount);
    }
}

contract AppAdapterBurnerMock {
    uint256 public calls;
    bytes32 public lastSubnetwork;
    address public lastOperator;
    uint256 public lastAmount;
    uint48 public lastCaptureTimestamp;

    function onSlash(bytes32 subnetwork, address operator, uint256 amount, uint48 captureTimestamp) external {
        ++calls;
        lastSubnetwork = subnetwork;
        lastOperator = operator;
        lastAmount = amount;
        lastCaptureTimestamp = captureTimestamp;
    }
}
