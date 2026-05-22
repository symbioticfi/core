// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";

import {AdapterFactory} from "../../src/contracts/adapters/AdapterFactory.sol";
import {AppAdapter} from "../../src/contracts/adapters/AppAdapter.sol";
import {Subnetwork} from "../../src/contracts/libraries/Subnetwork.sol";
import {Registry} from "../../src/contracts/common/Registry.sol";

import {IAdapter} from "../../src/interfaces/adapters/IAdapter.sol";
import {IAppAdapter} from "../../src/interfaces/adapters/IAppAdapter.sol";

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
        vault.setBurner(burner);

        subnetwork = network.subnetwork(1);
        networkMiddlewareService.setMiddleware(network, networkMiddleware);

        AppAdapter implementation =
            new AppAdapter(address(vaultFactory), address(factory), address(0), address(networkMiddlewareService));
        factory.whitelist(address(implementation));

        adapter = _createAdapter();
    }

    function test_StakeUsesDurationShiftedCheckpoint() public {
        uint48 timestamp = uint48(block.timestamp);

        _allocate(100);

        assertEq(adapter.stake(), 100);
        assertEq(adapter.stakeAt(timestamp, ""), 100);
        assertEq(adapter.stakeAt(timestamp - 1, ""), 100);
    }

    function test_DeallocationImmediatelyUpdatesCheckpointedStakeAndSettlesAfterDuration() public {
        _allocate(100);

        delegator.requestDeallocate(address(adapter), 40);

        assertEq(adapter.stake(), 60);

        vm.warp(block.timestamp + duration);

        assertEq(adapter.stake(), 60);

        uint256 deallocated = delegator.deallocate(address(adapter), 40);

        assertEq(deallocated, 40);
        assertEq(adapter.stake(), 60);
    }

    function test_SyncClosesPendingByRestoringStake() public {
        _allocate(100);

        delegator.requestDeallocate(address(adapter), 40);

        assertEq(adapter.stake(), 60);

        delegator.sync(address(adapter));
        assertEq(adapter.stake(), 60);
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
        assertEq(collateral.balanceOf(burner), 40);
    }

    function test_SlashTransfersToBurnerWithoutCallback() public {
        AppAdapterBurnerMock burnerMock = new AppAdapterBurnerMock();
        vault.setBurner(address(burnerMock));
        _allocate(100);

        vm.prank(networkMiddleware);
        adapter.slash(40);

        assertEq(burnerMock.calls(), 0);
        assertEq(collateral.balanceOf(address(burnerMock)), 40);
    }

    function test_ZeroStateViewsReturnZeroAndSlashRevertsInsufficientSlash() public {
        assertEq(adapter.stake(), 0);
        assertEq(adapter.slashable(), 0);
        assertEq(adapter.deallocatable(), 0);

        vm.expectRevert(IAppAdapter.InsufficientSlash.selector);
        vm.prank(networkMiddleware);
        adapter.slash(1);
    }

    function _allocate(uint256 amount) internal {
        _allocate(adapter, amount);
    }

    function _allocate(IAppAdapter targetAdapter, uint256 amount) internal {
        collateral.transfer(address(targetAdapter), amount);

        delegator.allocate(address(targetAdapter), amount);
    }

    function _createAdapter() internal returns (IAppAdapter) {
        return IAppAdapter(factory.create(1, curator, _initData()));
    }

    function _initData() internal view returns (bytes memory) {
        return abi.encode(
            address(vault),
            abi.encode(IAppAdapter.InitParams({subnetwork: subnetwork, operator: operator, duration: duration}))
        );
    }
}

contract AppAdapterRegistryMock is Registry {
    function add(address entity) external {
        _addEntity(entity);
    }
}

contract AppAdapterDelegatorMock {
    function allocate(address adapter, uint256 amount) external {
        IAdapter(adapter).allocate(amount);
    }

    function deallocate(address adapter, uint256 amount) external returns (uint256 deallocated) {
        return IAdapter(adapter).deallocate(amount);
    }

    function requestDeallocate(address adapter, uint256 amount) external {
        IAdapter(adapter).requestDeallocate(amount);
    }

    function sync(address adapter) external {
        IAdapter(adapter).requestDeallocate(0);
    }

    function limitOf(address adapter) external view returns (uint256) {
        return IAdapter(adapter).totalAssets();
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
    address public burner;

    constructor(address collateral_, address delegator_) {
        collateral = collateral_;
        delegator = delegator_;
    }

    function setDelegator(address delegator_) external {
        delegator = delegator_;
    }

    function setBurner(address burner_) external {
        burner = burner_;
    }

    function asset() external view returns (address) {
        return collateral;
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
