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

        adapterFactory.whitelist(
            address(
                new AppAdapter(
                    address(vaultFactory),
                    address(adapterFactory),
                    address(0),
                    address(0),
                    address(networkMiddlewareService)
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

        assertEq(delegator.allocatable(address(adapter)), 50);
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

        queue.claim(tokenId);

        assertEq(assetToken.balanceOf(alice), aliceBalanceBefore + claimableAssets);
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

        queue.claim(tokenId);

        assertEq(assetToken.balanceOf(address(0xA11CE)), aliceBalanceBefore + assetsFilled);
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
