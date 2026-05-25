// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AdapterFactory} from "../../../src/contracts/adapters/AdapterFactory.sol";
import {AppAdapter} from "../../../src/contracts/adapters/AppAdapter.sol";
import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";
import {AdapterRegistry} from "../../../src/contracts/AdapterRegistry.sol";
import {DelegatorFactory} from "../../../src/contracts/DelegatorFactory.sol";
import {VaultFactory} from "../../../src/contracts/VaultFactory.sol";
import {MigratableEntityProxy} from "../../../src/contracts/common/MigratableEntityProxy.sol";
import {UniversalDelegator} from "../../../src/contracts/delegator/UniversalDelegator.sol";
import {VaultV2} from "../../../src/contracts/vault/VaultV2.sol";
import {WithdrawalQueue} from "../../../src/contracts/vault/WithdrawalQueue.sol";
import {IAppAdapter} from "../../../src/interfaces/adapters/IAppAdapter.sol";
import {IMigratableEntity} from "../../../src/interfaces/common/IMigratableEntity.sol";
import {
    IUniversalDelegator,
    UNIVERSAL_DELEGATOR_TYPE,
    MAX_SHARE
} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2, VAULT_V2_VERSION} from "../../../src/interfaces/vault/IVaultV2.sol";
import {Token} from "../../mocks/Token.sol";
import {
    AppAdapterUniversalEntityMock,
    AppAdapterUniversalFeeRegistryMock,
    AppAdapterUniversalMigratableEntityMock,
    AppAdapterUniversalNetworkMiddlewareServiceMock
} from "../../adapters/AppAdapterUniversalDelegator.t.sol";

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AppAdapterInvariantHandler is Test {
    using Subnetwork for address;

    struct Observation {
        uint48 timestamp;
        uint48 expiresAt;
        uint256 stake;
        bool active;
    }

    uint256 internal constant OBSERVATIONS = 16;
    address internal constant BURNER = address(0xB);
    address internal constant CURATOR = address(0xC);

    Token public collateral;
    VaultV2 public vault;
    UniversalDelegator public delegator;
    WithdrawalQueue public queue;
    IAppAdapter public adapter;

    address internal network = makeAddr("network");
    address internal networkMiddleware = makeAddr("networkMiddleware");
    address internal operator = makeAddr("operator");
    address[3] internal actors = [address(0xA11CE), address(0xB0B), address(0xCAFE)];
    uint48 internal duration = 10;

    Observation[OBSERVATIONS] internal observations;
    uint256[] internal requestTokenIds;
    uint256 internal nextObservation;
    uint256 internal lastTimestamp;
    uint256 internal lastStake;
    bool internal singleBlockViolated;
    bool internal crossTimeViolated;
    bool internal emptyQueuePendingRouteViolated;

    constructor() {
        _initialize();
        lastTimestamp = block.timestamp;
        lastStake = adapter.stake();
    }

    function deposit(uint256 actorSeed, uint256 assets) external {
        address actor = _actor(actorSeed);
        assets = bound(assets, 1, 1000 ether);

        deal(address(collateral), actor, assets);
        vm.startPrank(actor);
        collateral.approve(address(vault), assets);
        try vault.deposit(assets, actor) {} catch {}
        vm.stopPrank();

        _afterAction(false);
    }

    function forceDeallocate(uint256 assets) external {
        uint256 totalAssets = adapter.totalAssets();
        if (totalAssets == 0) {
            _afterAction(false);
            return;
        }

        assets = bound(assets, 1, totalAssets);
        try delegator.forceDeallocate(address(adapter), assets) {} catch {}

        _afterAction(false);
    }

    function requestWithdraw(uint256 actorSeed, uint256 shares) external {
        address actor = _actor(actorSeed);
        uint256 balance = vault.balanceOf(actor);
        if (balance == 0) {
            _afterAction(false);
            return;
        }

        shares = bound(shares, 1, balance);
        vm.startPrank(actor);
        vault.approve(address(queue), shares);
        try queue.requestWithdraw(shares, actor) returns (uint256 tokenId) {
            requestTokenIds.push(tokenId);
        } catch {}
        vm.stopPrank();

        _afterAction(false);
    }

    function claim(uint256 tokenSeed) external {
        if (requestTokenIds.length == 0) {
            _afterAction(false);
            return;
        }

        uint256 tokenId = requestTokenIds[tokenSeed % requestTokenIds.length];
        try queue.claim(tokenId, type(uint256).max) {} catch {}

        _afterAction(false);
    }

    function sweepPending() external {
        try delegator.sweepPending() {} catch {}

        _afterAction(false);
    }

    function setLimits(uint256 assets, uint256 share) external {
        assets = bound(assets, 0, adapter.totalAssets() + 1000 ether);
        share = bound(share, 0, MAX_SHARE);
        delegator.setLimits(address(adapter), assets, share);

        _afterAction(false);
    }

    function slash(uint256 amount) external {
        uint256 slashable = adapter.slashable();
        if (slashable == 0) {
            _afterAction(false);
            return;
        }

        amount = bound(amount, 1, slashable);
        vm.prank(networkMiddleware);
        try adapter.slash(amount) {
            _clearObservations();
            _afterAction(true);
        } catch {
            _afterAction(false);
        }
    }

    function observeCurrentStakeAt() external {
        _afterAction(false);
    }

    function warp(uint256 timeJump) external {
        timeJump = bound(timeJump, 1, duration * 2);
        vm.warp(block.timestamp + timeJump);

        _afterAction(false);
    }

    function assertSingleBlockInvariant() external view {
        assertFalse(singleBlockViolated);
    }

    function assertCrossTimeInvariant() external view {
        assertFalse(crossTimeViolated);
    }

    function assertAccountingInvariant() external view {
        uint256 adapterTotalAssets = adapter.totalAssets();
        uint256 adapterSlashable = adapter.slashable();
        uint256 adapterDeallocatable = adapter.deallocatable();

        assertEq(adapterTotalAssets, adapterSlashable + adapterDeallocatable);
        assertEq(collateral.balanceOf(address(adapter)), adapterTotalAssets);
        assertLe(adapter.stake(), adapterSlashable);
        assertLe(adapterSlashable, adapterTotalAssets);
        assertEq(delegator.totalAssets(), adapterTotalAssets);
        assertEq(vault.totalAssets(), collateral.balanceOf(address(vault)) + adapterTotalAssets);
        assertEq(adapter.stake(), adapter.stakeAt(uint48(block.timestamp)));
    }

    function assertQueueInvariant() external view {
        uint256 claimableAssets;
        for (uint256 i; i < requestTokenIds.length; ++i) {
            (uint256 assets,) = queue.claimable(requestTokenIds[i], type(uint256).max);
            claimableAssets += assets;
        }

        assertFalse(emptyQueuePendingRouteViolated);
        assertLe(claimableAssets, collateral.balanceOf(address(queue)));
        assertLe(queue.totalFilled(), queue.totalRequested());
        assertEq(queue.pendingShares(), queue.totalRequested() - queue.totalFilled());
    }

    function _afterAction(bool slashAction) internal {
        uint256 currentTimestamp = block.timestamp;
        uint256 currentStake = adapter.stake();

        if (!slashAction && currentTimestamp == lastTimestamp && currentStake < lastStake) {
            singleBlockViolated = true;
        }

        lastTimestamp = currentTimestamp;
        lastStake = currentStake;
        _checkObservations();
        _checkQueuePendingRoute();
        if (!slashAction) {
            _rememberObservation(uint48(currentTimestamp));
        }
    }

    function _rememberObservation(uint48 timestamp) internal {
        observations[nextObservation] = Observation({
            timestamp: timestamp, expiresAt: timestamp + duration, stake: adapter.stakeAt(timestamp), active: true
        });
        nextObservation = (nextObservation + 1) % OBSERVATIONS;
    }

    function _checkObservations() internal {
        uint256 currentTimestamp = block.timestamp;
        for (uint256 i; i < OBSERVATIONS; ++i) {
            Observation memory observation = observations[i];
            if (
                observation.active && currentTimestamp < observation.expiresAt
                    && adapter.stakeAt(observation.timestamp) < observation.stake
            ) {
                crossTimeViolated = true;
            }
        }
    }

    function _clearObservations() internal {
        for (uint256 i; i < OBSERVATIONS; ++i) {
            delete observations[i];
        }
    }

    function _checkQueuePendingRoute() internal {
        if (queue.pendingShares() > 0) {
            return;
        }

        try delegator.adaptersWithPending(0) returns (uint16) {
            emptyQueuePendingRouteViolated = true;
        } catch {}
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _initialize() internal {
        vm.warp(100);

        collateral = new Token("Collateral");
        VaultFactory vaultFactory = new VaultFactory(address(this));
        DelegatorFactory delegatorFactory = new DelegatorFactory(address(this));
        AdapterRegistry adapterRegistry = new AdapterRegistry();
        adapterRegistry.initialize(address(this));
        AdapterFactory adapterFactory = new AdapterFactory(address(this));
        AppAdapterUniversalFeeRegistryMock feeRegistry = new AppAdapterUniversalFeeRegistryMock();
        AppAdapterUniversalNetworkMiddlewareServiceMock networkMiddlewareService =
            new AppAdapterUniversalNetworkMiddlewareServiceMock();
        networkMiddlewareService.setMiddleware(network, networkMiddleware);

        vaultFactory.whitelist(address(new AppAdapterUniversalMigratableEntityMock(address(vaultFactory))));
        vaultFactory.whitelist(address(new AppAdapterUniversalMigratableEntityMock(address(vaultFactory))));
        vaultFactory.whitelist(
            address(
                new VaultV2(
                    address(0x1),
                    address(feeRegistry),
                    address(vaultFactory),
                    address(0x2),
                    address(adapterRegistry),
                    address(delegatorFactory),
                    address(new WithdrawalQueue())
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
                    address(vaultFactory), address(adapterFactory), address(0), address(networkMiddlewareService)
                )
            )
        );

        vault = _createVault(vaultFactory);
        delegator = _createDelegator(delegatorFactory, vault);
        vault.setDelegator(address(delegator));
        queue = WithdrawalQueue(vault.withdrawalQueue());
        adapterRegistry.whitelist(address(vault), address(adapterFactory));

        adapter = IAppAdapter(
            adapterFactory.create(
                1,
                CURATOR,
                abi.encode(
                    address(vault),
                    abi.encode(
                        IAppAdapter.InitParams({
                            subnetwork: network.subnetwork(1), operator: operator, duration: duration, burner: BURNER
                        })
                    )
                )
            )
        );
        delegator.addAdapter(address(adapter));
        delegator.setLimits(address(adapter), type(uint256).max, MAX_SHARE);

        address[] memory autoAllocateAdapters = new address[](1);
        autoAllocateAdapters[0] = address(adapter);
        delegator.setAutoAllocateAdapters(autoAllocateAdapters);
        delegator.allocate(address(adapter), type(uint256).max);
    }

    function _createVault(VaultFactory vaultFactory) internal returns (VaultV2) {
        bytes memory data = abi.encode(
            IVaultV2.InitParams({
                name: "Vault",
                symbol: "vTKN",
                asset: address(collateral),
                depositWhitelist: false,
                depositorToWhitelist: address(this),
                isDepositLimit: false,
                depositLimit: 0,
                defaultAdminRoleHolder: address(this),
                depositWhitelistSetRoleHolder: address(this),
                depositorWhitelistRoleHolder: address(this),
                isDepositLimitSetRoleHolder: address(this),
                depositLimitSetRoleHolder: address(this)
            })
        );
        IERC20(address(collateral)).approve(_predictVaultAddress(vaultFactory, data), 1e9);

        return VaultV2(vaultFactory.create(VAULT_V2_VERSION, address(this), data));
    }

    function _createDelegator(DelegatorFactory delegatorFactory, VaultV2 targetVault)
        internal
        returns (UniversalDelegator)
    {
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
                        deallocateRoleHolder: address(this),
                        adapters: new address[](0),
                        absoluteLimits: new uint256[](0),
                        shareLimits: new uint256[](0)
                    })
                )
            )
        );

        return UniversalDelegator(delegatorAddress);
    }

    function _predictVaultAddress(VaultFactory vaultFactory, bytes memory data) internal view returns (address) {
        bytes memory initData = abi.encodeCall(IMigratableEntity.initialize, (VAULT_V2_VERSION, address(this), data));
        bytes memory initCode = abi.encodePacked(
            type(MigratableEntityProxy).creationCode,
            abi.encode(vaultFactory.implementation(VAULT_V2_VERSION), initData)
        );
        bytes32 salt = keccak256(abi.encode(vaultFactory.totalEntities(), VAULT_V2_VERSION, address(this), data));
        return Create2.computeAddress(salt, keccak256(initCode), address(vaultFactory));
    }
}
