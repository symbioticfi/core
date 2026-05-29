// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {AdapterFactory} from "../../../src/contracts/adapters/AdapterFactory.sol";
import {AppAdapter} from "../../../src/contracts/adapters/AppAdapter.sol";
import {Subnetwork} from "../../../src/contracts/libraries/Subnetwork.sol";
import {AdapterRegistry} from "../../../src/contracts/AdapterRegistry.sol";
import {DelegatorFactory} from "../../../src/contracts/DelegatorFactory.sol";
import {VaultFactory} from "../../../src/contracts/VaultFactory.sol";
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
import {
    IVaultV2,
    VAULT_V2_VERSION,
    MAX_MANAGEMENT_FEE,
    MAX_PERFORMANCE_FEE
} from "../../../src/interfaces/vault/IVaultV2.sol";
import {Token} from "../../mocks/Token.sol";
import {
    AppAdapterUniversalEntityMock,
    AppAdapterUniversalMigratableEntityMock,
    AppAdapterUniversalNetworkMiddlewareServiceMock
} from "../../adapters/AppAdapterUniversalDelegator.t.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract AppAdapterInvariantHandler is Test {
    using Subnetwork for address;

    struct Observation {
        uint48 timestamp;
        uint48 expiresAt;
        uint256 stake;
        bool active;
    }

    struct HistoryObservation {
        uint48 timestamp;
        uint256 stake;
        bool active;
    }

    uint256 internal constant OBSERVATIONS = 256;
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
    HistoryObservation[OBSERVATIONS] internal historyObservations;
    uint256[] internal requestTokenIds;
    uint256 internal nextObservation;
    uint256 internal nextHistoryObservation;
    uint256 internal lastTimestamp;
    uint256 internal lastStake;
    bool internal singleBlockViolated;
    bool internal crossTimeViolated;
    bool internal historyViolated;
    bool internal emptyQueuePendingRouteViolated;

    constructor() {
        _initialize();
        lastTimestamp = block.timestamp;
        lastStake = adapter.stake();
        _rememberHistory(uint48(lastTimestamp), lastStake);
        _rememberObservation(uint48(lastTimestamp));
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

    function mint(uint256 actorSeed, uint256 shares) external {
        address actor = _actor(actorSeed);
        shares = bound(shares, 1, 1000 ether);
        uint256 assets = vault.previewMint(shares);

        deal(address(collateral), actor, assets);
        vm.startPrank(actor);
        collateral.approve(address(vault), assets);
        try vault.mint(shares, actor) {} catch {}
        vm.stopPrank();

        _afterAction(false);
    }

    function withdraw(uint256 actorSeed, uint256 assets) external {
        address actor = _actor(actorSeed);
        uint256 maxWithdraw = vault.maxWithdraw(actor);
        if (maxWithdraw == 0) {
            _afterAction(false);
            return;
        }

        assets = bound(assets, 1, Math.min(maxWithdraw, 1000 ether));
        vm.prank(actor);
        try vault.withdraw(assets, actor, actor) {} catch {}

        _afterAction(false);
    }

    function redeem(uint256 actorSeed, uint256 shares) external {
        address actor = _actor(actorSeed);
        uint256 maxRedeem = vault.maxRedeem(actor);
        if (maxRedeem == 0) {
            _afterAction(false);
            return;
        }

        shares = bound(shares, 1, Math.min(maxRedeem, 1000 ether));
        vm.prank(actor);
        try vault.redeem(shares, actor, actor) {} catch {}

        _afterAction(false);
    }

    function transferShares(uint256 fromSeed, uint256 toSeed, uint256 shares) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed + 1);
        uint256 balance = vault.balanceOf(from);
        if (balance == 0 || from == to) {
            _afterAction(false);
            return;
        }

        shares = bound(shares, 1, balance);
        vm.prank(from);
        try vault.transfer(to, shares) {} catch {}

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

    function allocate(uint256 mode, uint256 assets) external {
        assets = bound(assets, 0, vault.freeAssets() + 1000 ether);
        mode %= 2;
        if (mode == 0) {
            try delegator.allocate(address(adapter), assets) {} catch {}
        } else {
            try delegator.allocateAll(assets) {} catch {}
        }

        _afterAction(false);
    }

    function deallocate(uint256 mode, uint256 assets) external {
        uint256 totalAssets = adapter.totalAssets();
        assets = bound(assets, 0, totalAssets + 1000 ether);
        mode %= 3;
        if (mode == 0) {
            try delegator.deallocate(address(adapter), assets) {} catch {}
        } else if (mode == 1) {
            try delegator.deallocateAll(assets) {} catch {}
        } else {
            try delegator.deallocateExact(assets) {} catch {}
        }

        _afterAction(false);
    }

    function setAutoAllocate(uint256 enabled) external {
        address[] memory autoAllocateAdapters = new address[](enabled % 2);
        if (autoAllocateAdapters.length != 0) {
            autoAllocateAdapters[0] = address(adapter);
        }
        try delegator.setAutoAllocateAdapters(autoAllocateAdapters) {} catch {}

        _afterAction(false);
    }

    function requestRedeem(uint256 actorSeed, uint256 shares) external {
        address actor = _actor(actorSeed);
        _requestRedeem(actor, actor, shares);
    }

    function requestRedeemForReceiver(uint256 actorSeed, uint256 receiverSeed, uint256 shares) external {
        _requestRedeem(_actor(actorSeed), _actor(receiverSeed), shares);
    }

    function _requestRedeem(address actor, address receiver, uint256 shares) internal {
        uint256 balance = vault.balanceOf(actor);
        if (balance == 0) {
            _afterAction(false);
            return;
        }

        shares = bound(shares, 1, balance);
        vm.startPrank(actor);
        vault.approve(address(queue), shares);
        try queue.requestRedeem(shares, receiver) returns (uint256 tokenId) {
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
        try queue.claim(tokenId) {} catch {}

        _afterAction(false);
    }

    function fillQueue() external {
        try queue.fill() {} catch {}

        _afterAction(false);
    }

    function sweepPending() external {
        try delegator.sweepPending() {} catch {}

        _afterAction(false);
    }

    function setLimits(uint256 assets, uint256 share) external {
        assets = bound(assets, 0, adapter.totalAssets() + 1000 ether);
        share = bound(share, 0, MAX_SHARE);
        try delegator.setLimits(address(adapter), assets, share) {} catch {}

        _afterAction(false);
    }

    function adapterDecreaseLimits(uint256 assets, uint256 share) external {
        assets = bound(assets, 0, adapter.totalAssets() + 1000 ether);
        share = bound(share, 0, MAX_SHARE);
        vm.prank(address(adapter));
        try delegator.decreaseLimits(assets, share) {} catch {}

        _afterAction(false);
    }

    function configureAdapter(uint256 mode) external {
        mode %= 3;
        if (mode == 0) {
            try delegator.addAdapter(address(adapter)) {} catch {}
        } else if (mode == 1) {
            try delegator.removeAdapter(address(adapter)) {} catch {}
        } else {
            try delegator.swapAdapters(address(adapter), address(adapter)) {} catch {}
        }

        _afterAction(false);
    }

    function setVaultDepositControls(uint256 mode, uint256 actorSeed, uint256 limit) external {
        address actor = _actor(actorSeed);
        mode %= 8;
        try vault.setDepositWhitelist(mode & 1 != 0) {} catch {}
        try vault.setDepositorWhitelistStatus(actor, mode & 2 != 0) {} catch {}
        try vault.setIsDepositLimit(mode & 4 != 0) {} catch {}
        try vault.setDepositLimit(bound(limit, 0, vault.totalAssets() + 1000 ether)) {} catch {}

        _afterAction(false);
    }

    function setVaultFees(uint256 managementFeeSeed, uint256 performanceFeeSeed, uint256 receiverSeed) external {
        address receiver = _actor(receiverSeed);
        try vault.setManagementFee(uint96(bound(managementFeeSeed, 0, MAX_MANAGEMENT_FEE)), receiver) {} catch {}
        try vault.setPerformanceFee(uint96(bound(performanceFeeSeed, 0, MAX_PERFORMANCE_FEE)), receiver) {} catch {}

        _afterAction(false);
    }

    function accrueInterest() external {
        try vault.accrueInterest() {} catch {}

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

    function release(uint256, uint256 callerSeed) external {
        vm.prank(callerSeed % 2 == 0 ? network : networkMiddleware);
        try adapter.release() {
            _clearObservations();
            _afterAction(true);
        } catch {
            _afterAction(false);
        }
    }

    function observeCurrentStakeAt() external {
        _afterAction(false);
    }

    function quoteWithdrawable() external {
        try vault.withdrawable() {} catch {}
        try vault.redeemable() {} catch {}

        _afterAction(false);
    }

    function warp(uint256 timeJump) external {
        timeJump = bound(timeJump, 1, duration * 2);
        vm.warp(block.timestamp + timeJump);

        _afterAction(false);
    }

    function warpToBoundary(uint256 boundarySeed) external {
        uint256 boundary = boundarySeed % 4;
        if (boundary == 0) {
            vm.warp(block.timestamp + 1);
        } else if (boundary == 1) {
            vm.warp(block.timestamp + duration - 1);
        } else if (boundary == 2) {
            vm.warp(block.timestamp + duration);
        } else {
            vm.warp(block.timestamp + duration + 1);
        }

        _afterAction(false);
    }

    function assertSingleBlockInvariant() external view {
        assertFalse(singleBlockViolated);
    }

    function assertCrossTimeInvariant() external view {
        assertFalse(crossTimeViolated);
    }

    function assertHistoryInvariant() external view {
        assertFalse(historyViolated);
    }

    function assertAccountingInvariant() external view {
        uint256 adapterTotalAssets = adapter.totalAssets();
        uint256 adapterSlashable = adapter.slashable();
        uint256 adapterFreeAssets = adapter.freeAssets();

        assertEq(adapterTotalAssets, adapterSlashable + adapterFreeAssets);
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
            (uint256 assets,) = queue.claimable(requestTokenIds[i]);
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
        _checkHistory(uint48(currentTimestamp));
        _rememberHistory(uint48(currentTimestamp), currentStake);
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

    function _rememberHistory(uint48 timestamp, uint256 stake) internal {
        for (uint256 i; i < OBSERVATIONS; ++i) {
            if (historyObservations[i].active && historyObservations[i].timestamp == timestamp) {
                historyObservations[i].stake = stake;
                return;
            }
        }

        historyObservations[nextHistoryObservation] =
            HistoryObservation({timestamp: timestamp, stake: stake, active: true});
        nextHistoryObservation = (nextHistoryObservation + 1) % OBSERVATIONS;
    }

    function _checkHistory(uint48 currentTimestamp) internal {
        for (uint256 i; i < OBSERVATIONS; ++i) {
            HistoryObservation memory observation = historyObservations[i];
            if (
                observation.active && observation.timestamp < currentTimestamp
                    && adapter.stakeAt(observation.timestamp) != observation.stake
            ) {
                historyViolated = true;
            }
        }
    }

    function _checkQueuePendingRoute() internal {
        if (queue.pendingShares() > 0) {
            return;
        }

        try delegator.sweepPending() {} catch {}
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
        WithdrawalQueueFactory withdrawalQueueFactory = new WithdrawalQueueFactory(address(this));
        DelegatorFactory delegatorFactory = new DelegatorFactory(address(this));
        AdapterRegistry adapterRegistry = new AdapterRegistry(address(this));
        AdapterFactory adapterFactory = new AdapterFactory(address(this));
        ProtocolFeeRegistry protocolFee = new ProtocolFeeRegistry(address(this));
        protocolFee.setGlobalReceiver(address(this));
        AppAdapterUniversalNetworkMiddlewareServiceMock networkMiddlewareService =
            new AppAdapterUniversalNetworkMiddlewareServiceMock();
        networkMiddlewareService.setMiddleware(network, networkMiddleware);

        withdrawalQueueFactory.whitelist(address(new WithdrawalQueue(address(withdrawalQueueFactory))));

        vaultFactory.whitelist(address(new AppAdapterUniversalMigratableEntityMock(address(vaultFactory))));
        vaultFactory.whitelist(address(new AppAdapterUniversalMigratableEntityMock(address(vaultFactory))));
        vaultFactory.whitelist(
            address(
                new VaultV2(
                    address(0x1),
                    address(vaultFactory),
                    address(0x2),
                    address(adapterRegistry),
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
            address(new AppAdapter(address(vaultFactory), address(adapterFactory), address(networkMiddlewareService)))
        );

        vault = _createVault(vaultFactory);
        delegator = _createDelegator(delegatorFactory, vault);
        vault.setDelegator(address(delegator));
        queue = WithdrawalQueue(vault.withdrawalQueue());
        adapterRegistry.setWhitelistedStatus(address(vault), address(adapterFactory), true);

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
                depositLimitSetRoleHolder: address(this),
                managementFeeRoleHolder: address(this),
                performanceFeeRoleHolder: address(this)
            })
        );
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
                        deallocateRoleHolder: address(this)
                    })
                )
            )
        );

        return UniversalDelegator(delegatorAddress);
    }
}
