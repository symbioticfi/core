// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AdapterFactory} from "../../../src/contracts/adapters/AdapterFactory.sol";
import {AppAdapter} from "../../../src/contracts/adapters/AppAdapter.sol";
import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";
import {AdapterRegistry} from "../../../src/contracts/AdapterRegistry.sol";
import {DelegatorFactory} from "../../../src/contracts/DelegatorFactory.sol";
import {VaultFactory} from "../../../src/contracts/VaultFactory.sol";
import {Entity} from "../../../src/contracts/common/Entity.sol";
import {MigratableEntity} from "../../../src/contracts/common/MigratableEntity.sol";
import {UniversalDelegator} from "../../../src/contracts/delegator/UniversalDelegator.sol";
import {ProtocolFeeRegistry} from "../../../src/contracts/ProtocolFeeRegistry.sol";
import {VaultV2} from "../../../src/contracts/vault/VaultV2.sol";
import {WithdrawalQueue} from "../../../src/contracts/vault/WithdrawalQueue.sol";
import {WithdrawalQueueFactory} from "../../../src/contracts/WithdrawalQueueFactory.sol";

import {IAppAdapter} from "../../../src/interfaces/adapters/IAppAdapter.sol";
import {
    IUniversalDelegator,
    UNIVERSAL_DELEGATOR_TYPE,
    MAX_SHARE
} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../../../src/interfaces/vault/IVaultV2.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Token} from "../../mocks/Token.sol";

contract PendingQueueMigratableEntityMock is MigratableEntity {
    constructor(address factory) MigratableEntity(factory) {}
}

contract PendingQueueAdapterFactoryMock is AdapterFactory {
    constructor(address owner) AdapterFactory(owner) {
        _addEntity(address(this));
    }
}

contract PendingQueueEntityMock is Entity {
    constructor(address factory, uint64 type_) Entity(factory, type_) {}
}

contract PendingQueueNetworkMiddlewareServiceMock {
    mapping(address network => address middleware) public middleware;

    function setMiddleware(address network, address middleware_) external {
        middleware[network] = middleware_;
    }
}

contract PendingWithdrawalQueueHandler is Test {
    using Subnetwork for address;

    uint256 internal constant INITIAL_DEPOSIT = 1000 ether;
    uint256 internal constant MAX_ACTION_AMOUNT = 100 ether;
    uint48 internal constant DURATION = 365 days;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant DEPOSITOR = address(0xD00D);
    address internal constant BURNER = address(0xB);
    address internal constant CURATOR = address(0xC);

    Token public collateral;
    VaultV2 public vault;
    UniversalDelegator public delegator;
    WithdrawalQueue public queue;
    IAppAdapter public adapter;

    uint256 public allocatedWhilePending;
    uint256 public withdrawnWhilePending;

    VaultFactory internal vaultFactory;
    DelegatorFactory internal delegatorFactory;
    WithdrawalQueueFactory internal withdrawalQueueFactory;
    AdapterRegistry internal adapterRegistry;
    AdapterFactory internal adapterFactory;
    ProtocolFeeRegistry internal protocolFee;
    PendingQueueNetworkMiddlewareServiceMock internal networkMiddlewareService;

    address internal network = makeAddr("network");
    address internal networkMiddleware = makeAddr("networkMiddleware");
    address internal operator = makeAddr("operator");

    constructor() {
        vm.warp(100);
        _initialize();
    }

    function depositWhilePending(uint256 amountSeed) external {
        uint256 pendingBefore = queue.pendingAssets();
        if (pendingBefore == 0) {
            return;
        }

        uint256 adapterAssetsBefore = adapter.totalAssets();
        uint256 amount = _pendingBound(amountSeed, pendingBefore);

        deal(address(collateral), DEPOSITOR, amount);
        vm.startPrank(DEPOSITOR);
        collateral.approve(address(vault), amount);
        vault.deposit(amount, DEPOSITOR);
        vm.stopPrank();

        _accountAllocationIfStillPending(adapterAssetsBefore);
    }

    function mintWhilePending(uint256 sharesSeed) external {
        uint256 pendingBefore = queue.pendingAssets();
        if (pendingBefore == 0) {
            return;
        }

        uint256 adapterAssetsBefore = adapter.totalAssets();
        uint256 shares = bound(sharesSeed, 1, MAX_ACTION_AMOUNT);
        uint256 assets = vault.previewMint(shares);

        deal(address(collateral), DEPOSITOR, assets);
        vm.startPrank(DEPOSITOR);
        collateral.approve(address(vault), assets);
        try vault.mint(shares, DEPOSITOR) {} catch {}
        vm.stopPrank();

        _accountAllocationIfStillPending(adapterAssetsBefore);
    }

    function allocateWhilePending(uint256 amountSeed) external {
        uint256 pendingBefore = queue.pendingAssets();
        if (pendingBefore == 0) {
            return;
        }

        uint256 adapterAssetsBefore = adapter.totalAssets();
        uint256 amount = _pendingBound(amountSeed, pendingBefore);
        _addVaultFreeAssets(amount);

        uint256 allocated = delegator.allocate(address(adapter), amount);
        if (queue.pendingAssets() > 0) {
            allocatedWhilePending += allocated;
        }
        _accountAllocationIfStillPending(adapterAssetsBefore);
    }

    function allocateAllWhilePending(uint256 amountSeed) external {
        uint256 pendingBefore = queue.pendingAssets();
        if (pendingBefore == 0) {
            return;
        }

        uint256 adapterAssetsBefore = adapter.totalAssets();
        uint256 amount = _pendingBound(amountSeed, pendingBefore);
        _addVaultFreeAssets(amount);

        uint256 allocated = delegator.allocateAll(type(uint256).max);
        if (queue.pendingAssets() > 0) {
            allocatedWhilePending += allocated;
        }
        _accountAllocationIfStillPending(adapterAssetsBefore);
    }

    function forceDeallocateWhilePending(uint256 amountSeed) external {
        uint256 pendingBefore = queue.pendingAssets();
        if (pendingBefore == 0) {
            return;
        }

        uint256 amount = bound(amountSeed, 0, adapter.totalAssets() + MAX_ACTION_AMOUNT);
        try delegator.forceDeallocate(address(adapter), amount) {} catch {}
    }

    function deallocateWhilePending(uint256 amountSeed) external {
        _deallocateWhilePending(amountSeed, 0);
    }

    function deallocateAllWhilePending(uint256 amountSeed) external {
        _deallocateWhilePending(amountSeed, 1);
    }

    function deallocateExactWhilePending(uint256 amountSeed) external {
        _deallocateWhilePending(amountSeed, 2);
    }

    function withdrawWhilePending(uint256 amountSeed, uint256 freeAssetsSeed) external {
        uint256 pendingBefore = queue.pendingAssets();
        if (pendingBefore == 0) {
            return;
        }

        uint256 maxWithdraw = vault.maxWithdraw(BOB);
        if (maxWithdraw == 0) {
            return;
        }

        uint256 bobBalanceBefore = collateral.balanceOf(BOB);
        uint256 amount = bound(amountSeed, 1, Math.min(maxWithdraw, MAX_ACTION_AMOUNT));
        _addVaultFreeAssets(_pendingBound(freeAssetsSeed, pendingBefore));

        vm.prank(BOB);
        try vault.withdraw(amount, BOB, BOB) {} catch {}

        _accountWithdrawalIfStillPending(bobBalanceBefore);
    }

    function requestRedeemWhilePending(uint256 sharesSeed) external {
        uint256 pendingBefore = queue.pendingAssets();
        if (pendingBefore == 0) {
            return;
        }

        uint256 balance = vault.balanceOf(BOB);
        if (balance == 0) {
            return;
        }

        uint256 shares = bound(sharesSeed, 1, balance);
        vm.startPrank(BOB);
        vault.approve(address(queue), shares);
        try queue.requestRedeem(shares, BOB) {} catch {}
        vm.stopPrank();
    }

    function fillQueueWhilePending(uint256 freeAssetsSeed) external {
        uint256 pendingBefore = queue.pendingAssets();
        if (pendingBefore == 0) {
            return;
        }

        _addVaultFreeAssets(_pendingBound(freeAssetsSeed, pendingBefore));
        try queue.fill() {} catch {}
    }

    function claimQueueWhilePending() external {
        if (queue.pendingAssets() == 0) {
            return;
        }

        try queue.claim(0) {} catch {}
    }

    function sweepPendingWhilePending() external {
        if (queue.pendingAssets() == 0) {
            return;
        }

        try delegator.sweepPending() {} catch {}
    }

    function setLimitsWhilePending(uint256 assetsSeed, uint256 shareSeed) external {
        if (queue.pendingAssets() == 0) {
            return;
        }

        uint256 assets = bound(assetsSeed, 0, adapter.totalAssets() + MAX_ACTION_AMOUNT);
        uint256 share = bound(shareSeed, 0, MAX_SHARE);
        try delegator.setLimits(address(adapter), assets, share) {} catch {}
    }

    function setAutoAllocateWhilePending(uint256 enabledSeed) external {
        if (queue.pendingAssets() == 0) {
            return;
        }

        address[] memory adapters = new address[](enabledSeed % 2);
        if (adapters.length != 0) {
            adapters[0] = address(adapter);
        }
        try delegator.setAutoAllocateAdapters(adapters) {} catch {}
    }

    function redeemWhilePending(uint256 sharesSeed, uint256 freeAssetsSeed) external {
        uint256 pendingBefore = queue.pendingAssets();
        if (pendingBefore == 0) {
            return;
        }

        uint256 maxRedeem = vault.maxRedeem(BOB);
        if (maxRedeem == 0) {
            return;
        }

        uint256 bobBalanceBefore = collateral.balanceOf(BOB);
        uint256 shares = bound(sharesSeed, 1, Math.min(maxRedeem, MAX_ACTION_AMOUNT));
        _addVaultFreeAssets(_pendingBound(freeAssetsSeed, pendingBefore));

        vm.prank(BOB);
        try vault.redeem(shares, BOB, BOB) {} catch {}

        _accountWithdrawalIfStillPending(bobBalanceBefore);
    }

    function _initialize() internal {
        collateral = new Token("PendingInvariantCollateral");
        vaultFactory = new VaultFactory(address(this));
        withdrawalQueueFactory = new WithdrawalQueueFactory(address(this));
        delegatorFactory = new DelegatorFactory(address(this));
        adapterRegistry = new AdapterRegistry(address(this));
        adapterFactory = new PendingQueueAdapterFactoryMock(address(this));
        protocolFee = new ProtocolFeeRegistry(address(this));
        protocolFee.setGlobalReceiver(address(this));
        networkMiddlewareService = new PendingQueueNetworkMiddlewareServiceMock();
        networkMiddlewareService.setMiddleware(network, networkMiddleware);

        withdrawalQueueFactory.whitelist(address(new WithdrawalQueue(address(withdrawalQueueFactory))));

        vaultFactory.whitelist(address(new PendingQueueMigratableEntityMock(address(vaultFactory))));
        vaultFactory.whitelist(address(new PendingQueueMigratableEntityMock(address(vaultFactory))));
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
            delegatorFactory.whitelist(address(new PendingQueueEntityMock(address(delegatorFactory), i)));
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

        adapter = IAppAdapter(
            adapterFactory.create(
                1,
                CURATOR,
                abi.encode(
                    address(vault),
                    abi.encode(
                        IAppAdapter.InitParams({
                            subnetwork: network.subnetwork(1), operator: operator, duration: DURATION, burner: BURNER
                        })
                    )
                )
            )
        );
        adapterRegistry.setWhitelistedStatus(address(vault), address(adapter), true);

        delegator.addAdapter(address(adapter));
        delegator.setLimits(address(adapter), type(uint256).max, MAX_SHARE);
        address[] memory autoAllocateAdapters = new address[](1);
        autoAllocateAdapters[0] = address(adapter);
        delegator.setAutoAllocateAdapters(autoAllocateAdapters);

        uint256 aliceShares = _deposit(ALICE, INITIAL_DEPOSIT);
        _deposit(BOB, INITIAL_DEPOSIT);
        delegator.allocate(address(adapter), type(uint256).max);

        queue = WithdrawalQueue(vault.withdrawalQueue());
        vm.startPrank(ALICE);
        vault.approve(address(queue), aliceShares);
        queue.requestRedeem(aliceShares, ALICE);
        vm.stopPrank();

        assertGt(queue.pendingAssets(), 0);
        assertEq(vault.freeAssets(), 0);
    }

    function _createVault() internal returns (VaultV2) {
        bytes memory data = abi.encode(
            IVaultV2.InitParams({
                name: "PendingInvariantVault",
                symbol: "pivTKN",
                asset: address(collateral),
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
        return UniversalDelegator(
            delegatorFactory.create(
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
            )
        );
    }

    function _deposit(address account, uint256 amount) internal returns (uint256 shares) {
        deal(address(collateral), account, amount);
        vm.startPrank(account);
        collateral.approve(address(vault), amount);
        shares = vault.deposit(amount, account);
        vm.stopPrank();
    }

    function _pendingBound(uint256 seed, uint256 pendingBefore) internal pure returns (uint256) {
        uint256 maxAmount = Math.min(MAX_ACTION_AMOUNT, pendingBefore > 1 ? pendingBefore - 1 : pendingBefore);
        return bound(seed, 1, maxAmount);
    }

    function _addVaultFreeAssets(uint256 amount) internal {
        deal(address(collateral), address(vault), collateral.balanceOf(address(vault)) + amount);
    }

    function _deallocateWhilePending(uint256 amountSeed, uint256 mode) internal {
        if (queue.pendingAssets() == 0) {
            return;
        }

        uint256 amount = bound(amountSeed, 0, adapter.totalAssets() + MAX_ACTION_AMOUNT);
        if (mode == 0) {
            try delegator.deallocate(address(adapter), amount) {} catch {}
        } else if (mode == 1) {
            try delegator.deallocateAll(amount) {} catch {}
        } else {
            try delegator.deallocateExact(amount) {} catch {}
        }
    }

    function _accountAllocationIfStillPending(uint256 adapterAssetsBefore) internal {
        if (queue.pendingAssets() > 0 && adapter.totalAssets() > adapterAssetsBefore) {
            allocatedWhilePending += adapter.totalAssets() - adapterAssetsBefore;
        }
    }

    function _accountWithdrawalIfStillPending(uint256 bobBalanceBefore) internal {
        if (queue.pendingAssets() > 0 && collateral.balanceOf(BOB) > bobBalanceBefore) {
            withdrawnWhilePending += collateral.balanceOf(BOB) - bobBalanceBefore;
        }
    }
}
