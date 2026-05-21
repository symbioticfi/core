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

        bytes memory initData = abi.encode(
            address(vault),
            abi.encode(
                IAppAdapter.InitParams({
                    subnetwork: subnetwork, operator: operator, duration: duration, isBurnerHook: false
                })
            )
        );
        adapter = IAppAdapter(factory.create(1, curator, initData));
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

    function _allocate(uint256 amount) internal {
        collateral.transfer(address(adapter), amount);

        delegator.allocate(address(adapter), amount);
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
