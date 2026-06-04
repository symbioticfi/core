// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {UniversalDelegator} from "../../src/contracts/delegator/UniversalDelegator.sol";
import {
    IUniversalDelegator,
    UNIVERSAL_DELEGATOR_TYPE,
    MAX_ADAPTERS,
    MAX_SHARE,
    ADD_ADAPTER_ROLE,
    ALLOCATE_ROLE,
    REMOVE_ADAPTER_ROLE,
    SET_ADAPTER_LIMITS_ROLE,
    SET_AUTO_ALLOCATE_ADAPTERS_ROLE,
    SWAP_ADAPTERS_ROLE
} from "../../src/interfaces/delegator/IUniversalDelegator.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";

contract UniversalDelegatorSweepToken is ERC20 {
    constructor() ERC20("Token", "TKN") {}

    function mint(address account, uint256 assets) external {
        _mint(account, assets);
    }
}

contract UniversalDelegatorSweepHarness is UniversalDelegator {
    constructor(address adapterRegistry)
        UniversalDelegator(UNIVERSAL_DELEGATOR_TYPE, address(0x1), adapterRegistry, address(0x3))
    {}

    function setVault(address vault_) external {
        vault = vault_;
    }

    function addAdapterForTest(address adapter) external returns (uint16) {
        return addAdapter(adapter);
    }

    function adaptersWithPendingLength() external view returns (uint256) {
        return adaptersWithPending.length;
    }

    function autoAllocateAdaptersLength() external view returns (uint256) {
        return autoAllocateAdapters.length;
    }

    function grantRoleForTest(bytes32 role, address account) external {
        _grantRole(role, account);
    }
}

contract UniversalDelegatorAdapterFactoryMock {
    mapping(address entity => bool status) public isEntity;

    function setEntity(address entity, bool status) external {
        isEntity[entity] = status;
    }
}

contract UniversalDelegatorAdapterRegistryMock {
    mapping(address vault => mapping(address adapter => bool status)) public isWhitelisted;

    function setWhitelisted(address vault, address adapter, bool status) external {
        isWhitelisted[vault][adapter] = status;
    }
}

contract UniversalDelegatorSweepQueue {
    uint256 public pendingAssets;
    uint256 public pendingAfterFill;
    uint256 public fillCalls;

    constructor(uint256 pendingAssets_) {
        pendingAssets = pendingAssets_;
    }

    function setPendingAfterFill(uint256 pendingAfterFill_) external {
        pendingAfterFill = pendingAfterFill_;
    }

    function fill() external returns (uint256 assets, uint256 shares) {
        ++fillCalls;
        pendingAssets = pendingAfterFill;
    }
}

contract UniversalDelegatorSweepVault {
    address public withdrawalQueue;
    address public immutable asset;
    uint256 public pushedAssets;
    uint256 public pulledAssets;
    address public lastPushAdapter;
    address public lastPullAdapter;

    constructor(address withdrawalQueue_) {
        withdrawalQueue = withdrawalQueue_;
        asset = address(new UniversalDelegatorSweepToken());
    }

    function mintFreeAssets(uint256 assets) external {
        UniversalDelegatorSweepToken(asset).mint(address(this), assets);
    }

    function freeAssets() external view returns (uint256) {
        return UniversalDelegatorSweepToken(asset).balanceOf(address(this));
    }

    function totalAssets() external view returns (uint256) {
        return UniversalDelegatorSweepToken(asset).balanceOf(address(this));
    }

    function pull(uint256 assets, address adapter) external {
        pulledAssets += assets;
        lastPullAdapter = adapter;
        UniversalDelegatorSweepToken(asset).transfer(adapter, assets);
    }

    function push(uint256 assets, address adapter) external {
        pushedAssets += assets;
        lastPushAdapter = adapter;
        UniversalDelegatorSweepToken(asset).mint(address(this), assets);
    }
}

contract UniversalDelegatorSweepAdapter {
    address public immutable FACTORY;
    address public immutable vault;
    address public immutable asset;
    uint256 public totalAssets;
    uint256 public deallocateReturn;
    uint256 public freeAssets;
    uint256 public allocatableValue;
    uint256 public allocateReturn;
    uint256 public lastAllocateAssets;
    uint256 public lastDeallocateAssets;
    uint256 public allocateCalls;
    uint256 public deallocateCalls;
    uint256 public lastRequestDeallocateAssets;
    uint256 public requestDeallocateCalls;

    constructor(address factory, address vault_, uint256 totalAssets_, uint256 deallocateReturn_) {
        FACTORY = factory;
        vault = vault_;
        asset = vault_.code.length == 0 ? address(0) : UniversalDelegatorSweepVault(vault_).asset();
        totalAssets = totalAssets_;
        deallocateReturn = deallocateReturn_;
    }

    function setAllocatable(uint256 allocatableValue_) external {
        allocatableValue = allocatableValue_;
    }

    function setAllocateReturn(uint256 allocateReturn_) external {
        allocateReturn = allocateReturn_;
    }

    function allocatable() external view returns (uint256) {
        return allocatableValue;
    }

    function setFreeAssets(uint256 freeAssets_) external {
        freeAssets = freeAssets_;
    }

    function setTotalAssets(uint256 totalAssets_) external {
        totalAssets = totalAssets_;
    }

    function allocate(uint256 assets) external returns (uint256 allocated) {
        ++allocateCalls;
        lastAllocateAssets = assets;
        allocated = allocateReturn > assets ? assets : allocateReturn;
        totalAssets += allocated;
    }

    function deallocate(uint256 assets) external returns (uint256 deallocated) {
        ++deallocateCalls;
        lastDeallocateAssets = assets;
        deallocated = deallocateReturn > assets ? assets : deallocateReturn;
        totalAssets -= deallocated;
    }

    function requestDeallocate(uint256 assets) external {
        lastRequestDeallocateAssets = assets;
        ++requestDeallocateCalls;
    }
}

error UniversalDelegatorSweepAdapterBoom();

contract UniversalDelegatorSweepRevertingAdapter {
    address public immutable FACTORY;
    address public immutable vault;
    address public immutable asset;
    uint256 public totalAssets;

    constructor(address factory, address vault_, uint256 totalAssets_) {
        FACTORY = factory;
        vault = vault_;
        asset = vault_.code.length == 0 ? address(0) : UniversalDelegatorSweepVault(vault_).asset();
        totalAssets = totalAssets_;
    }

    function allocatable() external pure returns (uint256) {
        return 0;
    }

    function freeAssets() external pure returns (uint256) {
        return 0;
    }

    function allocate(uint256) external pure returns (uint256) {
        return 0;
    }

    function deallocate(uint256) external pure returns (uint256) {
        revert UniversalDelegatorSweepAdapterBoom();
    }

    function requestDeallocate(uint256) external {}
}

contract UniversalDelegatorSweepReentrantAdapter {
    address public immutable FACTORY;
    address public immutable vault;
    IUniversalDelegator public immutable delegator;
    uint256 public totalAssets;
    uint256 public lastAllocateAssets;
    bool public reentered;
    bytes public reentrantRevertData;

    constructor(address factory, address vault_, IUniversalDelegator delegator_) {
        FACTORY = factory;
        vault = vault_;
        delegator = delegator_;
    }

    function allocatable() external pure returns (uint256) {
        return type(uint256).max;
    }

    function freeAssets() external pure returns (uint256) {
        return 0;
    }

    function allocate(uint256 assets) external returns (uint256) {
        lastAllocateAssets = assets;
        try delegator.decreaseLimits(0, 0) {
            reentered = true;
        } catch (bytes memory data) {
            reentrantRevertData = data;
        }
        totalAssets += assets;
        return assets;
    }

    function deallocate(uint256 assets) external returns (uint256 deallocated) {
        deallocated = assets > totalAssets ? totalAssets : assets;
        totalAssets -= deallocated;
    }

    function requestDeallocate(uint256) external {}
}

contract UniversalDelegatorSweepPendingTest is Test {
    UniversalDelegatorAdapterFactoryMock internal adapterFactory;
    UniversalDelegatorAdapterRegistryMock internal adapterRegistry;
    UniversalDelegatorSweepHarness internal delegator;

    function setUp() public {
        adapterFactory = new UniversalDelegatorAdapterFactoryMock();
        adapterRegistry = new UniversalDelegatorAdapterRegistryMock();
        delegator = new UniversalDelegatorSweepHarness(address(adapterRegistry));
        delegator.grantRoleForTest(ADD_ADAPTER_ROLE, address(this));
        adapterFactory.setEntity(address(adapterFactory), true);
    }

    function _newAdapter(uint256 totalAssets, uint256 deallocateReturn)
        internal
        returns (UniversalDelegatorSweepAdapter adapter)
    {
        adapter = _newWhitelistedAdapterForVault(delegator.vault(), totalAssets, deallocateReturn);
    }

    function _newAdapterForVault(address vault, uint256 totalAssets, uint256 deallocateReturn)
        internal
        returns (UniversalDelegatorSweepAdapter adapter)
    {
        adapter = new UniversalDelegatorSweepAdapter(address(adapterFactory), vault, totalAssets, deallocateReturn);
    }

    function _newWhitelistedAdapterForVault(address vault, uint256 totalAssets, uint256 deallocateReturn)
        internal
        returns (UniversalDelegatorSweepAdapter adapter)
    {
        adapter = _newAdapterForVault(vault, totalAssets, deallocateReturn);
        adapterRegistry.setWhitelisted(vault, address(adapter), true);
    }

    function _addAdapters(uint256 count, uint256 totalAssets, uint256 deallocateReturn)
        internal
        returns (address[] memory route)
    {
        route = new address[](count);
        for (uint256 i; i < count; ++i) {
            UniversalDelegatorSweepAdapter adapter = _newAdapter(totalAssets, deallocateReturn);
            delegator.addAdapterForTest(address(adapter));
            route[i] = address(adapter);
        }
    }

    function test_AddAdapterAddsToDeallocationRouteAndReusesStableIndex() public {
        UniversalDelegatorSweepAdapter adapter = _newAdapter(0, 0);

        uint16 firstIndex = delegator.addAdapterForTest(address(adapter));

        assertEq(firstIndex, 1);
        assertEq(delegator.totalAdapters(), 1);
        assertEq(delegator.adapterToIndex(address(adapter)), 1);
        assertEq(delegator.indexToAdapter(1), address(adapter));
        assertEq(delegator.adapters(0), address(adapter));

        delegator.grantRoleForTest(REMOVE_ADAPTER_ROLE, address(this));
        delegator.removeAdapter(address(adapter));

        uint16 secondIndex = delegator.addAdapterForTest(address(adapter));

        assertEq(secondIndex, firstIndex);
        assertEq(delegator.totalAdapters(), 1);
        assertEq(delegator.adapters(0), address(adapter));
    }

    function test_AddAdapterRevertsAlreadyAdded() public {
        UniversalDelegatorSweepAdapter adapter = _newAdapter(0, 0);

        delegator.addAdapterForTest(address(adapter));

        vm.expectRevert(IUniversalDelegator.AlreadyAdded.selector);
        delegator.addAdapterForTest(address(adapter));
    }

    function test_VersionReturnsUniversalDelegatorVersion() public view {
        assertEq(delegator.VERSION(), 2);
    }

    function test_AddAdapterRevertsWhenAdapterLimitIsReached() public {
        vm.pauseGasMetering();
        _addAdapters(MAX_ADAPTERS, 0, 0);
        UniversalDelegatorSweepAdapter extraAdapter = _newAdapter(0, 0);
        vm.resumeGasMetering();

        vm.expectRevert(IUniversalDelegator.TooManyAdapters.selector);
        delegator.addAdapterForTest(address(extraAdapter));
    }

    function test_RemoveAdapterRevertsInvalidAdapter() public {
        UniversalDelegatorSweepAdapter adapter = _newAdapter(0, 0);

        delegator.grantRoleForTest(REMOVE_ADAPTER_ROLE, address(this));

        vm.expectRevert(IUniversalDelegator.InvalidAdapter.selector);
        delegator.removeAdapter(address(adapter));
    }

    function test_SetLimitsRevertsInvalidAdapterAndInvalidShare() public {
        UniversalDelegatorSweepAdapter adapter = _newAdapter(0, 0);

        delegator.grantRoleForTest(SET_ADAPTER_LIMITS_ROLE, address(this));

        vm.expectRevert(IUniversalDelegator.InvalidAdapter.selector);
        delegator.setLimits(address(adapter), 1, 1);

        delegator.addAdapterForTest(address(adapter));

        vm.expectRevert(IUniversalDelegator.InvalidShareLimit.selector);
        delegator.setLimits(address(adapter), 1, MAX_SHARE + 1);
    }

    function test_RevokeAdapterRolesRevertsWhileConfigured() public {
        UniversalDelegatorSweepAdapter adapter = _newAdapter(0, 0);

        delegator.addAdapterForTest(address(adapter));
        delegator.grantRoleForTest(bytes32(0), address(this));

        vm.expectRevert(IUniversalDelegator.InvalidRole.selector);
        delegator.revokeRole(ALLOCATE_ROLE, address(adapter));
    }

    function test_MulticallAppliesCallsAndBubblesReverts() public {
        UniversalDelegatorSweepAdapter adapter = _newAdapter(0, 0);

        delegator.addAdapterForTest(address(adapter));
        delegator.grantRoleForTest(SET_ADAPTER_LIMITS_ROLE, address(this));

        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(IUniversalDelegator.setLimits, (address(adapter), 10, 20));
        delegator.multicall(calls);

        assertEq(delegator.absoluteLimitOf(address(adapter)), 10);
        assertEq(delegator.shareLimitOf(address(adapter)), 20);

        calls[0] = abi.encodeCall(IUniversalDelegator.setLimits, (address(adapter), 10, MAX_SHARE + 1));

        vm.expectRevert(IUniversalDelegator.InvalidShareLimit.selector);
        delegator.multicall(calls);
    }

    function test_OnDepositAndOnWithdrawRejectNonVault() public {
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(0));
        delegator.setVault(address(vault));

        vm.expectRevert(IUniversalDelegator.NotVault.selector);
        delegator.onDeposit();

        vm.expectRevert(IUniversalDelegator.NotVault.selector);
        delegator.onWithdraw(1);
    }

    function test_AllocateUsesLimitsAndRefundsUnallocatedAssets() public {
        UniversalDelegatorSweepQueue queue = new UniversalDelegatorSweepQueue(0);
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(queue));
        vault.mintFreeAssets(100);
        delegator.setVault(address(vault));

        UniversalDelegatorSweepAdapter adapter = _newWhitelistedAdapterForVault(address(vault), 0, 0);
        adapter.setAllocatable(70);
        adapter.setAllocateReturn(40);

        delegator.addAdapterForTest(address(adapter));
        delegator.grantRoleForTest(SET_ADAPTER_LIMITS_ROLE, address(this));
        delegator.setLimits(address(adapter), type(uint256).max, MAX_SHARE);

        vm.prank(address(adapter));
        uint256 allocated = delegator.allocate(address(adapter), 100);

        assertEq(allocated, 40);
        assertEq(adapter.lastAllocateAssets(), 70);
        assertEq(adapter.totalAssets(), 40);
        assertEq(vault.pulledAssets(), 70);
        assertEq(vault.pushedAssets(), 30);
        assertEq(vault.lastPullAdapter(), address(adapter));
        assertEq(vault.lastPushAdapter(), address(adapter));
    }

    function test_AllocateZeroAmountStillCallsAdapterAfterSweep() public {
        UniversalDelegatorSweepQueue queue = new UniversalDelegatorSweepQueue(0);
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(queue));
        vault.mintFreeAssets(100);
        delegator.setVault(address(vault));

        UniversalDelegatorSweepAdapter adapter = _newWhitelistedAdapterForVault(address(vault), 0, 0);
        adapter.setAllocatable(100);
        adapter.setAllocateReturn(100);

        delegator.addAdapterForTest(address(adapter));
        delegator.grantRoleForTest(SET_ADAPTER_LIMITS_ROLE, address(this));
        delegator.setLimits(address(adapter), type(uint256).max, MAX_SHARE);

        vm.prank(address(adapter));
        uint256 allocated = delegator.allocate(address(adapter), 0);

        assertEq(allocated, 0);
        assertEq(adapter.allocateCalls(), 1);
        assertEq(adapter.lastAllocateAssets(), 0);
        assertEq(vault.pulledAssets(), 0);
    }

    function test_AllocateExactDeallocatesRouteToFundAllocation() public {
        UniversalDelegatorSweepQueue queue = new UniversalDelegatorSweepQueue(0);
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(queue));
        vault.mintFreeAssets(20);
        delegator.setVault(address(vault));

        UniversalDelegatorSweepAdapter source = _newWhitelistedAdapterForVault(address(vault), 100, 50);
        UniversalDelegatorSweepAdapter target = _newWhitelistedAdapterForVault(address(vault), 0, 0);
        target.setAllocatable(70);
        target.setAllocateReturn(70);

        delegator.addAdapterForTest(address(source));
        delegator.addAdapterForTest(address(target));
        delegator.grantRoleForTest(SET_ADAPTER_LIMITS_ROLE, address(this));
        delegator.setLimits(address(target), type(uint256).max, MAX_SHARE);

        vm.prank(address(target));
        uint256 allocated = delegator.allocateExact(address(target), 70);

        assertEq(allocated, 70);
        assertEq(source.lastDeallocateAssets(), 50);
        assertEq(source.totalAssets(), 50);
        assertEq(target.lastAllocateAssets(), 70);
        assertEq(target.totalAssets(), 70);
        assertEq(vault.pushedAssets(), 50);
        assertEq(vault.pulledAssets(), 70);
        assertEq(vault.lastPushAdapter(), address(source));
        assertEq(vault.lastPullAdapter(), address(target));
    }

    function test_AllocateExactReturnsZeroWhenPendingAssetsRemain() public {
        UniversalDelegatorSweepQueue queue = new UniversalDelegatorSweepQueue(10);
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(queue));
        vault.mintFreeAssets(100);
        queue.setPendingAfterFill(10);
        delegator.setVault(address(vault));

        UniversalDelegatorSweepAdapter adapter = _newWhitelistedAdapterForVault(address(vault), 0, 0);
        adapter.setAllocatable(100);
        adapter.setAllocateReturn(100);

        delegator.addAdapterForTest(address(adapter));
        delegator.grantRoleForTest(SET_ADAPTER_LIMITS_ROLE, address(this));
        delegator.setLimits(address(adapter), type(uint256).max, MAX_SHARE);

        vm.prank(address(adapter));
        uint256 allocated = delegator.allocateExact(address(adapter), 50);

        assertEq(allocated, 0);
        assertEq(queue.fillCalls(), 1);
        assertEq(adapter.allocateCalls(), 0);
        assertEq(vault.pulledAssets(), 0);
    }

    function test_AllocateExactReturnsZeroWhenRouteCannotDeallocateEnough() public {
        UniversalDelegatorSweepQueue queue = new UniversalDelegatorSweepQueue(0);
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(queue));
        vault.mintFreeAssets(20);
        delegator.setVault(address(vault));

        UniversalDelegatorSweepAdapter source = _newWhitelistedAdapterForVault(address(vault), 100, 30);
        UniversalDelegatorSweepAdapter target = _newWhitelistedAdapterForVault(address(vault), 0, 0);
        target.setAllocatable(70);
        target.setAllocateReturn(70);

        delegator.addAdapterForTest(address(source));
        delegator.addAdapterForTest(address(target));
        delegator.grantRoleForTest(SET_ADAPTER_LIMITS_ROLE, address(this));
        delegator.setLimits(address(target), type(uint256).max, MAX_SHARE);

        vm.prank(address(target));
        uint256 allocated = delegator.allocateExact(address(target), 70);

        assertEq(allocated, 0);
        assertEq(source.lastDeallocateAssets(), 50);
        assertEq(source.totalAssets(), 70);
        assertEq(target.allocateCalls(), 0);
        assertEq(vault.pushedAssets(), 30);
        assertEq(vault.pulledAssets(), 0);
    }

    function test_DeallocateZeroAmountStillRunsDirectAndSweepPaths() public {
        UniversalDelegatorSweepQueue queue = new UniversalDelegatorSweepQueue(0);
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(queue));
        delegator.setVault(address(vault));

        UniversalDelegatorSweepAdapter adapter = _newWhitelistedAdapterForVault(address(vault), 100, 100);
        delegator.addAdapterForTest(address(adapter));

        vm.prank(address(adapter));
        uint256 deallocated = delegator.deallocate(address(adapter), 0);

        assertEq(deallocated, 0);
        assertEq(adapter.deallocateCalls(), 2);
        assertEq(adapter.lastDeallocateAssets(), 0);
        assertEq(vault.pushedAssets(), 0);
    }

    function test_SwapAdaptersSwapsAdaptersInRoute() public {
        UniversalDelegatorSweepAdapter adapter1 = _newAdapter(100, 0);
        UniversalDelegatorSweepAdapter adapter2 = _newAdapter(100, 0);
        UniversalDelegatorSweepAdapter adapter3 = _newAdapter(100, 0);

        delegator.addAdapterForTest(address(adapter1));
        delegator.addAdapterForTest(address(adapter2));
        delegator.addAdapterForTest(address(adapter3));
        delegator.grantRoleForTest(SWAP_ADAPTERS_ROLE, address(this));

        delegator.swapAdapters(address(adapter1), address(adapter3));

        assertEq(delegator.adapters(0), address(adapter3));
        assertEq(delegator.adapters(1), address(adapter2));
        assertEq(delegator.adapters(2), address(adapter1));
    }

    function test_SetAutoAllocateAdaptersRevertsIfAdapterIsNotInAdapters() public {
        UniversalDelegatorSweepAdapter adapter1 = _newAdapter(100, 0);
        UniversalDelegatorSweepAdapter adapter2 = _newAdapter(100, 0);

        delegator.addAdapterForTest(address(adapter1));
        delegator.grantRoleForTest(SET_AUTO_ALLOCATE_ADAPTERS_ROLE, address(this));

        address[] memory route = new address[](1);
        route[0] = address(adapter1);
        delegator.setAutoAllocateAdapters(route);
        assertEq(delegator.autoAllocateAdapters(0), address(adapter1));

        route[0] = address(adapter2);
        vm.expectRevert(IUniversalDelegator.InvalidAdapter.selector);
        delegator.setAutoAllocateAdapters(route);
    }

    function test_SetAutoAllocateAdaptersRevertsOnDuplicateAdapters() public {
        UniversalDelegatorSweepAdapter adapter = _newAdapter(100, 0);

        delegator.addAdapterForTest(address(adapter));
        delegator.grantRoleForTest(SET_AUTO_ALLOCATE_ADAPTERS_ROLE, address(this));

        address[] memory route = new address[](2);
        route[0] = address(adapter);
        route[1] = address(adapter);
        vm.expectRevert(IUniversalDelegator.InvalidAdapter.selector);
        delegator.setAutoAllocateAdapters(route);
    }

    function test_SetAutoAllocateAdaptersClearsFiftyAdapters() public {
        vm.pauseGasMetering();
        address[] memory route = _addAdapters(MAX_ADAPTERS, 0, 0);
        delegator.grantRoleForTest(SET_AUTO_ALLOCATE_ADAPTERS_ROLE, address(this));
        delegator.setAutoAllocateAdapters(route);

        assertEq(delegator.autoAllocateAdaptersLength(), MAX_ADAPTERS);

        address[] memory emptyRoute = new address[](0);
        vm.resumeGasMetering();
        delegator.setAutoAllocateAdapters(emptyRoute);
        vm.pauseGasMetering();

        assertEq(delegator.autoAllocateAdaptersLength(), 0);
        vm.resumeGasMetering();
    }

    function test_DeallocatableSimulatesFullDeallocationWithoutMutatingState() public {
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(0));
        delegator.setVault(address(vault));

        UniversalDelegatorSweepAdapter adapter1 = _newAdapter(100, 40);
        UniversalDelegatorSweepAdapter adapter2 = _newAdapter(80, 25);
        delegator.addAdapterForTest(address(adapter1));
        delegator.addAdapterForTest(address(adapter2));

        assertEq(delegator.deallocatable(), 65);
        assertEq(adapter1.totalAssets(), 100);
        assertEq(adapter2.totalAssets(), 80);
        assertEq(adapter1.lastDeallocateAssets(), 0);
        assertEq(adapter2.lastDeallocateAssets(), 0);
        assertEq(vault.pushedAssets(), 0);
    }

    function test_DeallocateAllRevertsUnlessCalledBySelf() public {
        vm.expectRevert(IUniversalDelegator.NotSelf.selector);
        delegator.__deallocateAll();
    }

    function test_DeallocatableBubblesUnexpectedAdapterRevert() public {
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(0));
        delegator.setVault(address(vault));

        UniversalDelegatorSweepRevertingAdapter adapter =
            new UniversalDelegatorSweepRevertingAdapter(address(adapterFactory), address(vault), 100);
        adapterRegistry.setWhitelisted(address(vault), address(adapter), true);
        delegator.addAdapterForTest(address(adapter));

        vm.expectRevert(UniversalDelegatorSweepAdapterBoom.selector);
        delegator.deallocatable();
    }

    function test_AllocateBlocksAdapterReentrancy() public {
        UniversalDelegatorSweepQueue queue = new UniversalDelegatorSweepQueue(0);
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(queue));
        vault.mintFreeAssets(100);
        delegator.setVault(address(vault));

        UniversalDelegatorSweepReentrantAdapter adapter =
            new UniversalDelegatorSweepReentrantAdapter(address(adapterFactory), address(vault), delegator);
        adapterRegistry.setWhitelisted(address(vault), address(adapter), true);

        delegator.addAdapterForTest(address(adapter));
        delegator.grantRoleForTest(SET_ADAPTER_LIMITS_ROLE, address(this));
        delegator.setLimits(address(adapter), type(uint256).max, MAX_SHARE);

        vm.prank(address(adapter));
        delegator.allocate(address(adapter), 100);

        assertEq(adapter.lastAllocateAssets(), 100);
        assertFalse(adapter.reentered());
        assertEq(bytes4(adapter.reentrantRevertData()), ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
    }

    function test_AddAdapterAcceptsWhitelistedAdapterEvenIfAdapterVaultDoesNotMatchDelegatorVault() public {
        delegator.setVault(address(0xBEEF));
        UniversalDelegatorSweepAdapter adapter = _newAdapterForVault(address(0xCAFE), 100, 0);
        adapterRegistry.setWhitelisted(delegator.vault(), address(adapter), true);

        uint16 index = delegator.addAdapterForTest(address(adapter));

        assertEq(index, 1);
        assertEq(delegator.adapters(0), address(adapter));
        assertEq(adapter.vault(), address(0xCAFE));
    }

    function test_AddAdapterUsesVaultWhitelistContext() public {
        address vault = address(0xBEEF);
        UniversalDelegatorSweepHarness vaultDelegator = new UniversalDelegatorSweepHarness(address(adapterRegistry));
        vaultDelegator.setVault(vault);
        vaultDelegator.grantRoleForTest(ADD_ADAPTER_ROLE, address(this));
        UniversalDelegatorSweepAdapter adapter = _newAdapterForVault(vault, 100, 0);
        adapterRegistry.setWhitelisted(vault, address(adapter), true);

        uint16 index = vaultDelegator.addAdapterForTest(address(adapter));

        assertEq(index, 1);
        assertEq(vaultDelegator.adapters(0), address(adapter));
    }

    function test_AddAdapterUsesAdapterWhitelistEntry() public {
        address vault = address(0xBEEF);
        UniversalDelegatorSweepHarness vaultDelegator = new UniversalDelegatorSweepHarness(address(adapterRegistry));
        vaultDelegator.setVault(vault);
        vaultDelegator.grantRoleForTest(ADD_ADAPTER_ROLE, address(this));
        UniversalDelegatorSweepAdapter adapter = _newAdapterForVault(vault, 100, 0);
        adapterRegistry.setWhitelisted(vault, address(adapter), true);

        uint16 index = vaultDelegator.addAdapterForTest(address(adapter));

        assertEq(index, 1);
        assertEq(vaultDelegator.adapters(0), address(adapter));
    }

    function test_AddAdapterDoesNotUseZeroVaultWhitelistAsGlobalFallback() public {
        address vault = address(0xBEEF);
        UniversalDelegatorSweepHarness vaultDelegator = new UniversalDelegatorSweepHarness(address(adapterRegistry));
        vaultDelegator.setVault(vault);
        vaultDelegator.grantRoleForTest(ADD_ADAPTER_ROLE, address(this));
        UniversalDelegatorSweepAdapter adapter = _newAdapterForVault(vault, 100, 0);
        adapterRegistry.setWhitelisted(address(0), address(adapter), true);

        vm.expectRevert(IUniversalDelegator.InvalidAdapter.selector);
        vaultDelegator.addAdapterForTest(address(adapter));
    }

    function test_AddAdapterRevertsIfAdapterIsNotWhitelisted() public {
        UniversalDelegatorSweepAdapter adapter =
            new UniversalDelegatorSweepAdapter(address(adapterFactory), delegator.vault(), 0, 0);

        vm.expectRevert(IUniversalDelegator.InvalidAdapter.selector);
        delegator.addAdapterForTest(address(adapter));
    }

    function test_AddAdapterIgnoresAdapterFactoryEntityStatus() public {
        adapterFactory.setEntity(address(adapterFactory), false);
        UniversalDelegatorSweepAdapter adapter = _newAdapterForVault(delegator.vault(), 0, 0);
        adapterRegistry.setWhitelisted(delegator.vault(), address(adapter), true);

        uint16 index = delegator.addAdapterForTest(address(adapter));

        assertEq(index, 1);
        assertEq(delegator.adapters(0), address(adapter));
    }

    function test_RemoveAdapterRevertsWhenAdapterHasAssets() public {
        UniversalDelegatorSweepAdapter adapter = _newAdapter(100, 0);

        delegator.addAdapterForTest(address(adapter));
        delegator.grantRoleForTest(REMOVE_ADAPTER_ROLE, address(this));

        vm.expectRevert(IUniversalDelegator.AdapterHasAssets.selector);
        delegator.removeAdapter(address(adapter));

        assertEq(delegator.adapters(0), address(adapter));
    }

    function test_RemoveAdapterClearsPendingIndexAndShiftsRoutes() public {
        UniversalDelegatorSweepQueue queue = new UniversalDelegatorSweepQueue(100);
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(queue));
        delegator.setVault(address(vault));
        queue.setPendingAfterFill(100);

        UniversalDelegatorSweepAdapter adapter1 = _newWhitelistedAdapterForVault(address(vault), 0, 0);
        UniversalDelegatorSweepAdapter adapter2 = _newWhitelistedAdapterForVault(address(vault), 100, 0);
        UniversalDelegatorSweepAdapter adapter3 = _newWhitelistedAdapterForVault(address(vault), 0, 0);
        delegator.addAdapterForTest(address(adapter1));
        uint16 pendingIndex = delegator.addAdapterForTest(address(adapter2));
        delegator.addAdapterForTest(address(adapter3));

        address[] memory route = new address[](3);
        route[0] = address(adapter1);
        route[1] = address(adapter2);
        route[2] = address(adapter3);
        delegator.grantRoleForTest(SET_AUTO_ALLOCATE_ADAPTERS_ROLE, address(this));
        delegator.setAutoAllocateAdapters(route);

        delegator.sweepPending();

        assertEq(delegator.adaptersWithPending(0), pendingIndex);
        assertEq(adapter1.requestDeallocateCalls(), 0);
        assertEq(adapter2.lastRequestDeallocateAssets(), 100);

        adapter2.setTotalAssets(0);
        delegator.grantRoleForTest(REMOVE_ADAPTER_ROLE, address(this));
        delegator.removeAdapter(address(adapter2));

        assertEq(delegator.adaptersWithPendingLength(), 0);
        assertEq(delegator.adapters(0), address(adapter1));
        assertEq(delegator.adapters(1), address(adapter3));
        assertEq(delegator.autoAllocateAdapters(0), address(adapter1));
        assertEq(delegator.autoAllocateAdapters(1), address(adapter3));
    }

    function test_LimitsAreStoredByAdapterAddress() public {
        UniversalDelegatorSweepAdapter adapter = _newAdapter(100, 0);

        delegator.addAdapterForTest(address(adapter));
        delegator.grantRoleForTest(SET_ADAPTER_LIMITS_ROLE, address(this));
        delegator.setLimits(address(adapter), 123, 456);

        assertEq(delegator.absoluteLimitOf(address(adapter)), 123);
        assertEq(delegator.shareLimitOf(address(adapter)), 456);
    }

    function test_DecreaseLimitsReducesCallerFiniteLimits() public {
        UniversalDelegatorSweepAdapter adapter = _newAdapter(100, 0);

        delegator.addAdapterForTest(address(adapter));
        delegator.grantRoleForTest(SET_ADAPTER_LIMITS_ROLE, address(this));
        delegator.setLimits(address(adapter), 123, MAX_SHARE / 2);

        vm.expectEmit(true, true, true, true, address(delegator));
        emit IUniversalDelegator.DecreaseLimits(23, MAX_SHARE / 4);

        vm.prank(address(adapter));
        delegator.decreaseLimits(23, MAX_SHARE / 4);

        assertEq(delegator.absoluteLimitOf(address(adapter)), 100);
        assertEq(delegator.shareLimitOf(address(adapter)), MAX_SHARE / 4);
    }

    function test_DecreaseLimitsSubtractsRequestedAmountsFromUnlimitedLimits() public {
        UniversalDelegatorSweepAdapter adapter = _newAdapter(100, 0);

        delegator.addAdapterForTest(address(adapter));
        delegator.grantRoleForTest(SET_ADAPTER_LIMITS_ROLE, address(this));
        delegator.setLimits(address(adapter), type(uint256).max, MAX_SHARE);

        vm.prank(address(adapter));
        delegator.decreaseLimits(23, MAX_SHARE);

        assertEq(delegator.absoluteLimitOf(address(adapter)), type(uint256).max - 23);
        assertEq(delegator.shareLimitOf(address(adapter)), 0);
    }

    function test_SweepPendingStoresPendingAdapterIndexes() public {
        UniversalDelegatorSweepQueue queue = new UniversalDelegatorSweepQueue(100);
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(queue));
        delegator.setVault(address(vault));
        UniversalDelegatorSweepAdapter adapter = _newAdapter(100, 0);
        queue.setPendingAfterFill(100);

        uint16 index = delegator.addAdapterForTest(address(adapter));

        uint256 pendingAssets = delegator.sweepPending();

        assertEq(pendingAssets, 100);
        assertEq(adapter.lastRequestDeallocateAssets(), 100);
        assertEq(delegator.adaptersWithPending(0), index);
    }

    function test_SweepPendingDoesNotRequestStalePendingAfterFill() public {
        UniversalDelegatorSweepQueue queue = new UniversalDelegatorSweepQueue(100);
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(queue));
        delegator.setVault(address(vault));
        UniversalDelegatorSweepAdapter adapter = _newAdapter(100, 60);

        delegator.addAdapterForTest(address(adapter));

        uint256 pendingAssets = delegator.sweepPending();

        assertEq(pendingAssets, 0);
        assertEq(queue.fillCalls(), 1);
        assertEq(vault.pushedAssets(), 60);
        assertEq(vault.lastPushAdapter(), address(adapter));
        assertEq(adapter.lastDeallocateAssets(), 100);
        assertEq(adapter.requestDeallocateCalls(), 0);
        assertEq(adapter.lastRequestDeallocateAssets(), 0);
    }

    function test_SweepPendingOnlyDeallocatesPendingAssetsNetOfVaultFreeAssets() public {
        UniversalDelegatorSweepQueue queue = new UniversalDelegatorSweepQueue(100);
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(queue));
        vault.mintFreeAssets(30);
        queue.setPendingAfterFill(0);

        delegator.setVault(address(vault));
        UniversalDelegatorSweepAdapter adapter = _newAdapter(100, 70);
        delegator.addAdapterForTest(address(adapter));

        uint256 pendingAssets = delegator.sweepPending();

        assertEq(pendingAssets, 0);
        assertEq(adapter.lastDeallocateAssets(), 70);
        assertEq(vault.pushedAssets(), 70);
    }

    function test_SweepPendingAllowsWithdrawalQueueCaller() public {
        UniversalDelegatorSweepQueue queue = new UniversalDelegatorSweepQueue(0);
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(queue));
        delegator.setVault(address(vault));

        vm.prank(address(queue));
        delegator.sweepPending();
    }

    function test_SweepPendingClearsFiftyPendingAdapters() public {
        vm.pauseGasMetering();
        UniversalDelegatorSweepQueue queue = new UniversalDelegatorSweepQueue(MAX_ADAPTERS);
        UniversalDelegatorSweepVault vault = new UniversalDelegatorSweepVault(address(queue));
        delegator.setVault(address(vault));
        queue.setPendingAfterFill(MAX_ADAPTERS);
        _addAdapters(MAX_ADAPTERS, 1, 0);

        delegator.sweepPending();

        assertEq(delegator.adaptersWithPendingLength(), MAX_ADAPTERS);

        queue.setPendingAfterFill(0);
        vm.resumeGasMetering();
        uint256 pendingAssets = delegator.sweepPending();
        vm.pauseGasMetering();

        assertEq(pendingAssets, 0);
        assertEq(delegator.adaptersWithPendingLength(), 0);
        vm.resumeGasMetering();
    }
}
