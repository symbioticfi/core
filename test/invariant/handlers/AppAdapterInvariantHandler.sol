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
    AppAdapterUniversalAdapterFactoryMock,
    AppAdapterUniversalEntityMock,
    AppAdapterUniversalMigratableEntityMock,
    AppAdapterUniversalNetworkMiddlewareServiceMock
} from "../../adapters/AppAdapterUniversalDelegator.t.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract AppAdapterInvariantHandler is Test {
    using Subnetwork for address;
    using Math for uint256;

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

    Token public assetToken;
    VaultV2 public vault;
    UniversalDelegator public delegator;
    WithdrawalQueue public queue;
    IAppAdapter public adapter;

    address internal network = makeAddr("network");
    address internal networkMiddleware = makeAddr("networkMiddleware");
    address internal operator = makeAddr("operator");
    address internal relayer = makeAddr("relayer");
    address internal settlement = makeAddr("settlement");
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
    bool internal limitChanged;
    bool internal limitLockViolated;
    bool internal allocationLimitViolated;
    bool internal debtMaturityDrainViolated;
    bool internal immatureDebtWipeViolated;
    bool internal slashMaturedExitViolated;

    constructor() {
        _initialize();
        lastTimestamp = vm.getBlockTimestamp();
        lastStake = adapter.stake();
        _rememberHistory(uint48(lastTimestamp), lastStake);
        _rememberObservation(uint48(lastTimestamp));
    }

    function deposit(uint256 actorSeed, uint256 assets) external {
        address actor = _actor(actorSeed);
        assets = bound(assets, 1, 1000 ether);
        uint256 adapterAssetsBefore = adapter.totalAssets();

        deal(address(assetToken), actor, assets);
        vm.startPrank(actor);
        assetToken.approve(address(vault), assets);
        try vault.deposit(assets, actor) {} catch {}
        vm.stopPrank();

        _checkAllocationLimit(adapterAssetsBefore);
        _afterAction(false);
    }

    function mint(uint256 actorSeed, uint256 shares) external {
        address actor = _actor(actorSeed);
        shares = bound(shares, 1, 1000 ether);
        uint256 assets = vault.previewMint(shares);
        uint256 adapterAssetsBefore = adapter.totalAssets();

        deal(address(assetToken), actor, assets);
        vm.startPrank(actor);
        assetToken.approve(address(vault), assets);
        try vault.mint(shares, actor) {} catch {}
        vm.stopPrank();

        _checkAllocationLimit(adapterAssetsBefore);
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
        uint256 adapterAssetsBefore = adapter.totalAssets();
        mode %= 2;
        if (mode == 0) {
            try delegator.allocate(address(adapter), assets) {} catch {}
        } else {
            try delegator.allocateAll(assets) {} catch {}
        }

        _checkAllocationLimit(adapterAssetsBefore);
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

    function limitReductionWithdrawalPressure(
        uint256 actorSeed,
        uint256 assetsSeed,
        uint256 limitSeed,
        uint256 sharesSeed
    ) external {
        address actor = _actor(actorSeed);
        uint256 assets = bound(assetsSeed, 2, 1000 ether);

        deal(address(assetToken), actor, assets);
        vm.startPrank(actor);
        assetToken.approve(address(vault), assets);
        try vault.deposit(assets, actor) {} catch {}
        vm.stopPrank();

        try delegator.allocate(address(adapter), type(uint256).max) {} catch {}

        uint256 adapterAssets = adapter.totalAssets();
        if (adapterAssets > 0) {
            uint256 limit = bound(limitSeed, 0, adapterAssets - 1);
            try delegator.setLimits(address(adapter), limit, MAX_SHARE) {
                limitChanged = true;
            } catch {}
        }

        uint256 balance = vault.balanceOf(actor);
        if (balance > 1) {
            uint256 shares = bound(sharesSeed, 1, balance - 1);
            vm.startPrank(actor);
            vault.approve(address(queue), shares);
            try queue.requestRedeem(shares, actor) returns (uint256 tokenId) {
                requestTokenIds.push(tokenId);
            } catch {}
            vm.stopPrank();
        }

        _afterAction(false);
    }

    function debtMaturityDrainPressure(uint256 actorSeed, uint256 assetsSeed, uint256 firstSeed, uint256 secondSeed)
        external
    {
        uint256 snapshotId = vm.snapshotState();
        bool violated = _debtMaturityDrainPressure(actorSeed, assetsSeed, firstSeed, secondSeed);
        bool reverted = vm.revertToState(snapshotId);
        if (!reverted || violated) {
            debtMaturityDrainViolated = true;
        }
        _afterAction(false);
    }

    function immatureDebtCleanupPressure(uint256 actorSeed, uint256 assetsSeed, uint256 amountSeed) external {
        uint256 snapshotId = vm.snapshotState();
        bool violated = _immatureDebtCleanupPressure(actorSeed, assetsSeed, amountSeed);
        bool reverted = vm.revertToState(snapshotId);
        if (!reverted || violated) {
            immatureDebtWipeViolated = true;
        }
        _afterAction(false);
    }

    function slashMaturedExitPressure(uint256 actorSeed, uint256 assetsSeed, uint256 sharesSeed, uint256 slashSeed)
        external
    {
        uint256 snapshotId = vm.snapshotState();
        bool violated = _slashMaturedExitPressure(actorSeed, assetsSeed, sharesSeed, slashSeed);
        bool reverted = vm.revertToState(snapshotId);
        if (!reverted || violated) {
            slashMaturedExitViolated = true;
        }
        _afterAction(false);
    }

    function _debtMaturityDrainPressure(uint256 actorSeed, uint256 assetsSeed, uint256 firstSeed, uint256 secondSeed)
        internal
        returns (bool)
    {
        uint256 snapshotId = vm.snapshotState();
        bool violated = _forceDeallocateDebtMaturityDrain(actorSeed, assetsSeed, firstSeed, secondSeed);
        bool reverted = vm.revertToState(snapshotId);
        if (!reverted || violated) {
            return true;
        }

        snapshotId = vm.snapshotState();
        violated = _directRequestDebtMaturityDrain(actorSeed, assetsSeed, firstSeed, secondSeed);
        reverted = vm.revertToState(snapshotId);
        if (!reverted || violated) {
            return true;
        }

        snapshotId = vm.snapshotState();
        violated = _queuedWithdrawalDebtMaturityDrain(actorSeed, assetsSeed, firstSeed, secondSeed);
        reverted = vm.revertToState(snapshotId);
        return !reverted || violated;
    }

    function _forceDeallocateDebtMaturityDrain(
        uint256 actorSeed,
        uint256 assetsSeed,
        uint256 firstSeed,
        uint256 secondSeed
    ) internal returns (bool) {
        if (!_prepareDebtPressure(actorSeed, assetsSeed, 3)) {
            return false;
        }

        uint256 total = adapter.totalAssets();
        if (total < 2) {
            return false;
        }

        uint256 first = bound(firstSeed, 1, total - 1);
        uint256 vaultBalanceBefore = assetToken.balanceOf(address(vault));

        try delegator.forceDeallocate(address(adapter), first) {}
        catch {
            return true;
        }

        vm.warp(vm.getBlockTimestamp() + duration);
        if (adapter.slashable() != total - first || adapter.freeAssets() != first) {
            return true;
        }

        try delegator.sweepPending() {}
        catch {
            return true;
        }

        uint256 afterFirst = adapter.totalAssets();
        if (
            afterFirst != total - first || adapter.slashable() != afterFirst || adapter.freeAssets() != 0
                || assetToken.balanceOf(address(vault)) < vaultBalanceBefore + first
        ) {
            return true;
        }

        if (afterFirst == 0) {
            return false;
        }

        uint256 second = bound(secondSeed, 1, Math.min(first, afterFirst));
        try delegator.forceDeallocate(address(adapter), second) {}
        catch {
            return true;
        }

        vm.warp(vm.getBlockTimestamp() + duration);
        if (adapter.slashable() != afterFirst - second || adapter.freeAssets() != second) {
            return true;
        }

        try delegator.sweepPending() {}
        catch {
            return true;
        }

        uint256 afterSecond = adapter.totalAssets();
        if (
            afterSecond != afterFirst - second || adapter.slashable() != afterSecond || adapter.freeAssets() != 0
                || assetToken.balanceOf(address(vault)) < vaultBalanceBefore + first + second
        ) {
            return true;
        }

        return false;
    }

    function _directRequestDebtMaturityDrain(
        uint256 actorSeed,
        uint256 assetsSeed,
        uint256 firstSeed,
        uint256 secondSeed
    ) internal returns (bool) {
        if (!_prepareDebtPressure(actorSeed, assetsSeed, 3)) {
            return false;
        }

        uint256 total = adapter.totalAssets();
        if (total < 2) {
            return false;
        }

        uint256 first = bound(firstSeed, 1, total - 1);
        uint256 vaultBalanceBefore = assetToken.balanceOf(address(vault));

        vm.prank(address(delegator));
        try adapter.requestDeallocate(first) {}
        catch {
            return true;
        }

        vm.warp(vm.getBlockTimestamp() + duration);
        if (adapter.slashable() != total - first || adapter.freeAssets() != first) {
            return true;
        }

        try delegator.sweepPending() {}
        catch {
            return true;
        }

        uint256 afterFirst = adapter.totalAssets();
        if (
            afterFirst != total - first || adapter.slashable() != afterFirst || adapter.freeAssets() != 0
                || assetToken.balanceOf(address(vault)) < vaultBalanceBefore + first
        ) {
            return true;
        }

        if (afterFirst == 0) {
            return false;
        }

        uint256 second = bound(secondSeed, 1, Math.min(first, afterFirst));
        vm.prank(address(delegator));
        try adapter.requestDeallocate(second) {}
        catch {
            return true;
        }

        vm.warp(vm.getBlockTimestamp() + duration);
        if (adapter.slashable() != afterFirst - second || adapter.freeAssets() != second) {
            return true;
        }

        try delegator.sweepPending() {}
        catch {
            return true;
        }

        uint256 afterSecond = adapter.totalAssets();
        if (
            afterSecond != afterFirst - second || adapter.slashable() != afterSecond || adapter.freeAssets() != 0
                || assetToken.balanceOf(address(vault)) < vaultBalanceBefore + first + second
        ) {
            return true;
        }

        return false;
    }

    function _queuedWithdrawalDebtMaturityDrain(
        uint256 actorSeed,
        uint256 assetsSeed,
        uint256 firstSeed,
        uint256 secondSeed
    ) internal returns (bool) {
        if (!_prepareDebtPressure(actorSeed, assetsSeed, 3)) {
            return false;
        }

        address actor = _actor(actorSeed);
        uint256 balance = vault.balanceOf(actor);
        if (balance < 2) {
            return false;
        }

        uint256 firstShares = bound(firstSeed, 1, balance - 1);
        if (_requestAndSettleMaturedExit(actor, firstShares)) {
            return true;
        }

        balance = vault.balanceOf(actor);
        if (balance == 0) {
            return false;
        }

        uint256 secondShares = bound(secondSeed, 1, Math.min(firstShares, balance));
        return _requestAndSettleMaturedExit(actor, secondShares);
    }

    function _immatureDebtCleanupPressure(uint256 actorSeed, uint256 assetsSeed, uint256 amountSeed)
        internal
        returns (bool)
    {
        for (uint256 mode; mode < 3; ++mode) {
            uint256 snapshotId = vm.snapshotState();
            bool violated = _immatureDebtCleanupScenario(actorSeed, assetsSeed, amountSeed, mode);
            bool reverted = vm.revertToState(snapshotId);
            if (!reverted || violated) {
                return true;
            }
        }

        return false;
    }

    function _immatureDebtCleanupScenario(
        uint256 actorSeed,
        uint256 assetsSeed,
        uint256 amountSeed,
        uint256 cleanupMode
    ) internal returns (bool) {
        if (!_prepareDebtPressure(actorSeed, assetsSeed, 2)) {
            return false;
        }

        uint256 total = adapter.totalAssets();
        if (total < 2) {
            return false;
        }

        uint256 amount = bound(amountSeed, 1, total - 1);
        uint48 requestedAt = uint48(vm.getBlockTimestamp());

        try delegator.forceDeallocate(address(adapter), amount) {}
        catch {
            return true;
        }

        try delegator.setLimits(address(adapter), total - amount, MAX_SHARE) {
            limitChanged = true;
        } catch {
            return true;
        }

        if (adapter.slashable() <= delegator.limitOf(address(adapter))) {
            return false;
        }

        uint256 stakeBefore = adapter.stake();
        uint256 slashableBefore = adapter.slashable();
        uint256 adapterAssetsBefore = adapter.totalAssets();

        cleanupMode %= 3;
        if (cleanupMode == 0) {
            try delegator.sweepPending() {}
            catch {
                return true;
            }
        } else if (cleanupMode == 1) {
            address actor = _actor(actorSeed + 1);
            deal(address(assetToken), actor, 1);
            vm.startPrank(actor);
            assetToken.approve(address(vault), 1);
            try vault.deposit(1, actor) {} catch {}
            vm.stopPrank();
        } else {
            vm.prank(address(delegator));
            try adapter.requestDeallocate(0) {}
            catch {
                return true;
            }
        }

        if (adapter.stake() > stakeBefore || adapter.slashable() != slashableBefore) {
            return true;
        }

        vm.warp(requestedAt + duration);
        try delegator.sweepPending() {}
        catch {
            return true;
        }

        if (
            adapter.totalAssets() != adapterAssetsBefore - amount || adapter.slashable() != adapterAssetsBefore - amount
        ) {
            return true;
        }

        return false;
    }

    function _slashMaturedExitPressure(uint256 actorSeed, uint256 assetsSeed, uint256 sharesSeed, uint256 slashSeed)
        internal
        returns (bool)
    {
        for (uint256 mode; mode < 3; ++mode) {
            uint256 snapshotId = vm.snapshotState();
            bool violated = _slashMaturedExitScenario(actorSeed, assetsSeed, sharesSeed, slashSeed, mode);
            bool reverted = vm.revertToState(snapshotId);
            if (!reverted || violated) {
                return true;
            }
        }

        return false;
    }

    function _slashMaturedExitScenario(
        uint256 actorSeed,
        uint256 assetsSeed,
        uint256 sharesSeed,
        uint256 slashSeed,
        uint256 slashMode
    ) internal returns (bool) {
        if (!_prepareDebtPressure(actorSeed, assetsSeed, 3)) {
            return false;
        }

        address actor = _actor(actorSeed);
        uint256 balance = vault.balanceOf(actor);
        if (balance < 2) {
            return false;
        }

        uint256 shares = bound(sharesSeed, 1, balance - 1);
        vm.startPrank(actor);
        vault.approve(address(queue), shares);
        uint256 tokenId;
        try queue.requestRedeem(shares, actor) returns (uint256 newTokenId) {
            tokenId = newTokenId;
            requestTokenIds.push(newTokenId);
        } catch {
            vm.stopPrank();
            return false;
        }
        vm.stopPrank();

        if (queue.pendingShares() == 0) {
            return false;
        }

        vm.warp(vm.getBlockTimestamp() + duration);
        uint256 pendingAssetsBefore = queue.pendingAssets();
        uint256 adapterAssetsBefore = adapter.totalAssets();
        if (pendingAssetsBefore == 0) {
            return false;
        }

        uint256 slashable = adapter.slashable();
        if (slashable == 0) {
            return false;
        }

        uint256 amount;
        if (slashMode == 0) {
            if (slashable < 2) {
                return false;
            }
            amount = bound(slashSeed, 1, slashable - 1);
        } else if (slashMode == 1) {
            amount = slashable;
        } else {
            amount = slashable + bound(slashSeed, 1, 1000 ether);
        }
        vm.prank(networkMiddleware);
        try adapter.slash(amount) {
            _clearObservations();
        } catch {
            return false;
        }

        uint256 expectedSlash = Math.min(amount, slashable);
        (uint256 claimableAssets, uint256 claimableShares) = queue.claimable(tokenId);
        if (
            claimableAssets != pendingAssetsBefore || claimableShares != shares || queue.pendingShares() != 0
                || queue.pendingAssets() != 0
                || adapter.totalAssets()
                    != adapterAssetsBefore.saturatingSub(pendingAssetsBefore).saturatingSub(expectedSlash)
        ) {
            return true;
        }

        return false;
    }

    function _requestAndSettleMaturedExit(address actor, uint256 shares) internal returns (bool) {
        vm.startPrank(actor);
        vault.approve(address(queue), shares);
        uint256 tokenId;
        try queue.requestRedeem(shares, actor) returns (uint256 newTokenId) {
            tokenId = newTokenId;
            requestTokenIds.push(newTokenId);
        } catch {
            vm.stopPrank();
            return false;
        }
        vm.stopPrank();

        if (queue.pendingShares() == 0) {
            return false;
        }

        uint256 pendingAssetsBefore = queue.pendingAssets();
        uint256 adapterAssetsBefore = adapter.totalAssets();

        vm.warp(vm.getBlockTimestamp() + duration);
        if (
            adapter.slashable() != adapterAssetsBefore.saturatingSub(pendingAssetsBefore)
                || adapter.freeAssets() != pendingAssetsBefore
        ) {
            return true;
        }

        try delegator.sweepPending() {}
        catch {
            return true;
        }

        (uint256 claimableAssets, uint256 claimableShares) = queue.claimable(tokenId);
        uint256 pendingShares = queue.pendingShares();
        if (
            claimableAssets != pendingAssetsBefore || claimableShares != shares
                || adapter.totalAssets() != adapterAssetsBefore.saturatingSub(claimableAssets)
                || adapter.slashable() != adapter.totalAssets() || adapter.freeAssets() != 0
                || (pendingShares != 0 && queue.pendingAssets() != 0)
        ) {
            return true;
        }

        return false;
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
        try queue.ownerOf(tokenId) returns (address owner) {
            vm.prank(owner);
            try queue.claim(tokenId, owner) {} catch {}
        } catch {}

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
        try delegator.setLimits(address(adapter), assets, share) {
            limitChanged = true;
        } catch {}

        _afterAction(false);
    }

    function adapterDecreaseLimits(uint256 assets, uint256 share) external {
        assets = bound(assets, 0, adapter.totalAssets() + 1000 ether);
        share = bound(share, 0, MAX_SHARE);
        vm.prank(address(adapter));
        try delegator.decreaseLimits(assets, share) {
            limitChanged = true;
        } catch {}

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

    function release(uint256 amount, uint256 callerSeed) external {
        amount = bound(amount, 0, adapter.slashable() + 1000 ether);

        vm.prank(callerSeed % 2 == 0 ? network : networkMiddleware);
        try adapter.release(amount) {
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
        vm.warp(vm.getBlockTimestamp() + timeJump);

        _afterAction(false);
    }

    function warpToBoundary(uint256 boundarySeed) external {
        uint256 boundary = boundarySeed % 4;
        if (boundary == 0) {
            vm.warp(vm.getBlockTimestamp() + 1);
        } else if (boundary == 1) {
            vm.warp(vm.getBlockTimestamp() + duration - 1);
        } else if (boundary == 2) {
            vm.warp(vm.getBlockTimestamp() + duration);
        } else {
            vm.warp(vm.getBlockTimestamp() + duration + 1);
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
        assertEq(assetToken.balanceOf(address(adapter)), adapterTotalAssets);
        assertLe(adapter.stake(), adapterSlashable);
        assertLe(adapterSlashable, adapterTotalAssets);
        assertEq(delegator.totalAssets(), adapterTotalAssets);
        assertEq(vault.totalAssets(), assetToken.balanceOf(address(vault)) + adapterTotalAssets);
        assertEq(adapter.stake(), adapter.stakeAt(uint48(vm.getBlockTimestamp())));
    }

    function assertQueueInvariant() external view {
        uint256 claimableAssets;
        for (uint256 i; i < requestTokenIds.length; ++i) {
            (uint256 assets,) = queue.claimable(requestTokenIds[i]);
            claimableAssets += assets;
        }

        assertFalse(emptyQueuePendingRouteViolated);
        assertLe(claimableAssets, assetToken.balanceOf(address(queue)));
        assertLe(queue.totalFilled(), queue.totalRequested());
        assertEq(queue.pendingShares(), queue.totalRequested() - queue.totalFilled());
    }

    function assertLimitLockInvariant() external view {
        assertFalse(limitLockViolated);
    }

    function assertAllocationLimitInvariant() external view {
        assertFalse(allocationLimitViolated);
    }

    function assertDebtMaturityDrainInvariant() external view {
        assertFalse(debtMaturityDrainViolated);
    }

    function assertNoImmatureDebtWipeInvariant() external view {
        assertFalse(immatureDebtWipeViolated);
    }

    function assertSlashSettlesMaturedExitInvariant() external view {
        assertFalse(slashMaturedExitViolated);
    }

    function _prepareDebtPressure(uint256 actorSeed, uint256 assetsSeed, uint256 minAssets) internal returns (bool) {
        if (!_settleQueueBestEffort()) {
            return false;
        }

        _normalizeDebtPressure();

        address actor = _actor(actorSeed);
        uint256 assets = bound(assetsSeed, minAssets, 1000 ether);

        deal(address(assetToken), actor, assets);
        vm.startPrank(actor);
        assetToken.approve(address(vault), assets);
        try vault.deposit(assets, actor) {}
        catch {
            vm.stopPrank();
            return adapter.totalAssets() >= minAssets && queue.pendingShares() == 0;
        }
        vm.stopPrank();

        try delegator.allocate(address(adapter), type(uint256).max) {} catch {}

        return adapter.totalAssets() >= minAssets && queue.pendingShares() == 0;
    }

    function _settleQueueBestEffort() internal returns (bool) {
        for (uint256 i; i < 4; ++i) {
            try delegator.sweepPending() {} catch {}
            try queue.fill() {} catch {}

            if (queue.pendingShares() == 0) {
                return true;
            }

            vm.warp(vm.getBlockTimestamp() + duration);
        }

        return queue.pendingShares() == 0;
    }

    function _normalizeDebtPressure() internal {
        try vault.setDepositWhitelist(false) {} catch {}
        try vault.setIsDepositLimit(false) {} catch {}
        try vault.setDepositLimit(type(uint256).max) {} catch {}
        try vault.setManagementFee(0, address(0)) {} catch {}
        try vault.setPerformanceFee(0, address(0)) {} catch {}
        try vault.accrueInterest() {} catch {}
        try delegator.addAdapter(address(adapter)) {} catch {}
        try delegator.setLimits(address(adapter), type(uint256).max, MAX_SHARE) {
            limitChanged = true;
        } catch {}

        address[] memory autoAllocateAdapters = new address[](1);
        autoAllocateAdapters[0] = address(adapter);
        try delegator.setAutoAllocateAdapters(autoAllocateAdapters) {} catch {}
    }

    function _afterAction(bool slashAction) internal {
        uint256 currentTimestamp = vm.getBlockTimestamp();
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
        _checkLimitLockRecovery();
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
        uint256 currentTimestamp = vm.getBlockTimestamp();
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

    function _checkLimitLockRecovery() internal {
        if (limitLockViolated || !limitChanged || queue.pendingAssets() == 0 || adapter.totalAssets() == 0) {
            return;
        }

        uint256 snapshotId = vm.snapshotState();
        bool canRecover = _canRecoverPendingWithoutLimitIncrease();
        bool reverted = vm.revertToState(snapshotId);

        if (!reverted || !canRecover) {
            limitLockViolated = true;
        }
    }

    function _canRecoverPendingWithoutLimitIncrease() internal returns (bool) {
        try delegator.sweepPending() {} catch {}

        for (uint256 i; i < 6; ++i) {
            if (queue.pendingAssets() == 0 || adapter.totalAssets() == 0) {
                return true;
            }

            uint256 adapterAssetsBefore = adapter.totalAssets();

            vm.warp(vm.getBlockTimestamp() + duration);
            try delegator.sweepPending() {} catch {}
            try queue.fill() {} catch {}

            if (queue.pendingAssets() == 0 || adapter.totalAssets() == 0) {
                return true;
            }
            if (adapter.totalAssets() >= adapterAssetsBefore) {
                return false;
            }
        }

        return queue.pendingAssets() == 0 || adapter.totalAssets() == 0;
    }

    function _checkAllocationLimit(uint256 adapterAssetsBefore) internal {
        if (allocationLimitViolated) {
            return;
        }

        uint256 limit = delegator.limitOf(address(adapter));
        uint256 adapterAssetsAfter = adapter.totalAssets();
        if (adapterAssetsBefore >= limit) {
            if (adapterAssetsAfter > adapterAssetsBefore) {
                allocationLimitViolated = true;
            }
        } else if (adapterAssetsAfter > limit) {
            allocationLimitViolated = true;
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function _initialize() internal {
        vm.warp(100);

        assetToken = new Token("Asset");
        VaultFactory vaultFactory = new VaultFactory(address(this));
        WithdrawalQueueFactory withdrawalQueueFactory = new WithdrawalQueueFactory(address(this));
        DelegatorFactory delegatorFactory = new DelegatorFactory(address(this));
        AdapterRegistry adapterRegistry = new AdapterRegistry(address(this));
        AdapterFactory adapterFactory = new AppAdapterUniversalAdapterFactoryMock(address(this));
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

        vault = _createVault(vaultFactory);
        delegator = _createDelegator(delegatorFactory, vault);
        vault.setDelegator(address(delegator));
        queue = WithdrawalQueue(vault.withdrawalQueue());

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
