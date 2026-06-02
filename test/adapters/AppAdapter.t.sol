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
    Token internal collateral;
    IAppAdapter internal adapter;

    bytes32 internal subnetwork;
    address internal network = makeAddr("network");
    address internal networkMiddleware = makeAddr("networkMiddleware");
    address internal operator = makeAddr("operator");
    address internal curator = makeAddr("curator");
    address internal burner = makeAddr("burner");
    address internal relayer = makeAddr("relayer");
    uint48 internal duration = 10;

    function setUp() public {
        vm.warp(100);

        vaultFactory = new AppAdapterRegistryMock();
        factory = new AdapterFactory(address(this));
        delegator = new AppAdapterDelegatorMock();
        networkMiddlewareService = new AppAdapterNetworkMiddlewareServiceMock();
        collateral = new Token("Collateral");
        vault = new AppAdapterVaultMock(address(collateral), address(delegator));
        vaultFactory.add(address(vault));

        subnetwork = network.subnetwork(1);
        networkMiddlewareService.setMiddleware(network, networkMiddleware);

        AppAdapter implementation = new AppAdapter(
            address(vaultFactory), address(factory), address(0), relayer, address(networkMiddlewareService)
        );
        factory.whitelist(address(implementation));

        adapter = _createAdapter();
    }

    function test_StakeUsesDurationShiftedCheckpoint() public {
        uint48 timestamp = uint48(block.timestamp);

        _allocate(100);

        assertEq(adapter.stake(), 100);
        assertEq(adapter.stakeAt(timestamp), 100);
        assertEq(adapter.stakeAt(timestamp - 1), 0);
    }

    function test_InitializeStoresConfiguredBurner() public view {
        assertEq(adapter.burner(), burner);
        assertEq(AppAdapter(address(adapter)).owner(), curator);
        assertEq(AppAdapter(address(adapter)).converters()[0], curator);
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

        collateral.transfer(rewarder, amount);

        vm.startPrank(rewarder);
        collateral.approve(address(adapter), amount);
        adapter.reward(address(collateral), amount);
        vm.stopPrank();

        assertEq(collateral.balanceOf(rewarder), 0);
        assertEq(collateral.balanceOf(address(adapter)), amount);
    }

    function test_DeallocationPreservesStakeUntilDurationAndSettlesAfterDuration() public {
        _allocate(100);

        delegator.requestDeallocate(address(adapter), 40);

        assertEq(adapter.stake(), 100);

        vm.warp(block.timestamp + duration);

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

        uint48 timestamp = uint48(block.timestamp);
        uint256 endOfBlockStake = adapter.stake();

        vm.warp(block.timestamp + 1);
        delegator.requestDeallocate(address(adapter), 40);

        assertEq(adapter.stakeAt(timestamp), endOfBlockStake);
    }

    function test_GuaranteeRemainsSlashableUntilHalfOpenExpiry() public {
        _allocate(100);

        uint48 timestamp = uint48(block.timestamp);
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

        vm.warp(block.timestamp + duration);

        assertEq(adapter.stake(), 60);
        assertEq(adapter.freeAssets(), 40);

        uint256 deallocated = delegator.deallocate(address(adapter), 40);

        assertEq(deallocated, 40);
        assertEq(adapter.totalAssets(), 60);
    }

    function test_DeallocateReturnsAllCurrentlyFreeAssets() public {
        _allocate(100);

        delegator.requestDeallocate(address(adapter), 80);
        vm.warp(block.timestamp + duration);

        uint256 vaultBalanceBefore = collateral.balanceOf(address(vault));
        uint256 adapterAssetsBefore = adapter.totalAssets();

        uint256 deallocated = delegator.deallocate(address(adapter), 1);

        assertEq(deallocated, 80);
        assertEq(adapter.totalAssets(), adapterAssetsBefore - 80);
        assertEq(collateral.balanceOf(address(vault)), vaultBalanceBefore + 80);
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

    function test_SlashUsesConfiguredPairAndReturnsSlashedAmount() public {
        _allocate(100);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit IAppAdapter.Slash(40);

        vm.prank(networkMiddleware);
        uint256 slashedAmount = adapter.slash(40);

        assertEq(slashedAmount, 40);
        assertEq(adapter.totalAssets(), 60);
        assertEq(adapter.slashable(), 60);
        assertEq(delegator.decreaseLimitsCalls(), 1);
        assertEq(delegator.lastDecreaseAssets(), 40);
        assertEq(delegator.lastDecreaseShare(), 0);
        assertEq(collateral.balanceOf(burner), 40);
    }

    function test_SlashSaturatesAtCurrentSlashable() public {
        _allocate(100);

        vm.expectEmit(true, true, true, true, address(adapter));
        emit IAppAdapter.Slash(100);

        vm.prank(networkMiddleware);
        uint256 slashedAmount = adapter.slash(150);

        assertEq(slashedAmount, 100);
        assertEq(adapter.totalAssets(), 0);
        assertEq(adapter.slashable(), 0);
        assertEq(adapter.stake(), 0);
        assertEq(collateral.balanceOf(burner), 100);
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
        assertEq(collateral.balanceOf(burner), 0);
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
        assertEq(collateral.balanceOf(burner), 0);
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
        assertEq(collateral.balanceOf(address(burnerMock)), 40);
    }

    function test_RepeatedSlashInSameBlockUpdatesSlashedCheckpoint() public {
        _allocate(100);

        vm.startPrank(networkMiddleware);
        adapter.slash(10);
        adapter.slash(15);
        vm.stopPrank();

        assertEq(adapter.stake(), 75);
        assertEq(adapter.slashable(), 75);
        assertEq(collateral.balanceOf(burner), 25);
    }

    function test_SlashRevertsWithInsufficientBurnerGas() public {
        _allocate(100);

        vm.expectRevert(IAppAdapter.InsufficientBurnerGas.selector);
        vm.prank(networkMiddleware);
        adapter.slash{gas: BURNER_GAS_LIMIT + 40_000}(40);
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
        AppAdapter implementation = new AppAdapter(
            address(vaultFactory), address(factory), address(0), relayer, address(networkMiddlewareService)
        );
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
        collateral.transfer(address(targetAdapter), amount);

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
    uint256 public lastDecreaseAssets;
    uint256 public lastDecreaseShare;
    uint256 public limitOverride;
    bool public isLimitOverride;

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

    function decreaseLimits(uint256 assets, uint256 share) external {
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
    address public immutable collateral;
    address public delegator;

    constructor(address collateral_, address delegator_) {
        collateral = collateral_;
        delegator = delegator_;
    }

    function setDelegator(address delegator_) external {
        delegator = delegator_;
    }

    function asset() external view returns (address) {
        return collateral;
    }

    function push(uint256 amount, address from) external {
        Token(collateral).transferFrom(from, address(this), amount);
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
