// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {FrontendLiquidityLens} from "../../../src/contracts/adapters/utils/FrontendLiquidityLens.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {IAdapter} from "../../../src/interfaces/adapters/IAdapter.sol";
import {IAccount} from "../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {ILiquidLaneAdapter} from "../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IThreeFAdapter} from "../../../src/interfaces/adapters/IThreeFAdapter.sol";
import {IUniversalDelegator} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../../src/interfaces/vault/IVaultV2.sol";
import {IOwnable} from "../../../src/interfaces/adapters/utils/ILiquidityLensDependencies.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @dev Mainnet-fork regression comparing the lens against the delegator's real cascade.
/// @dev Discovery runs in `setUp` so every test can decide to skip before making any call: `vm.skip`
///      is only reported as a skip when nothing has been executed yet, otherwise it reads as a failure.
contract FrontendLiquidityLensMainnetTest is Test {
    address internal constant MAINNET_THREEF_ADAPTER = 0x037356ac97fF97BE419cc608279e4389Fa7f2cfC;

    FrontendLiquidityLens internal lens;
    address internal threeFAdapter;
    address internal liquidLaneAdapter;
    address internal liquidLaneToken;

    function setUp() public {
        string memory rpcUrl = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) {
            return;
        }
        uint256 forkBlock = vm.envOr("MAINNET_FORK_BLOCK", uint256(0));
        if (forkBlock == 0) {
            vm.createSelectFork(rpcUrl);
        } else {
            vm.createSelectFork(rpcUrl, forkBlock);
        }

        address implementation = address(new FrontendLiquidityLens());
        lens = FrontendLiquidityLens(address(new TransparentUpgradeableProxy(implementation, address(this), "")));

        address adapter = vm.envOr("MAINNET_THREEF_ADAPTER", MAINNET_THREEF_ADAPTER);
        if (adapter.code.length == 0) {
            return;
        }
        threeFAdapter = adapter;
        (liquidLaneAdapter, liquidLaneToken) = _findLiquidLane(adapter);
    }

    /* GROUND TRUTH */

    /// @dev The largest exact ask the real cascade covers, probed via `deallocateExact` (adapters hold
    ///      DEALLOCATE_ROLE) with state reverted between probes.
    function _cascadeCovers(address delegator, address caller, uint256 assets) internal returns (bool covered) {
        uint256 snapshot = vm.snapshotState();
        vm.prank(caller);
        covered = IUniversalDelegator(delegator).deallocateExact(assets) >= assets;
        vm.revertToState(snapshot);
    }

    function _trueMaxDeallocatable(address delegator, address caller, uint256 hi) internal returns (uint256 lo) {
        if (!_cascadeCovers(delegator, caller, 1)) {
            return 0;
        }
        lo = 1;
        while (lo < hi) {
            uint256 mid = (lo + hi + 1) / 2;
            if (_cascadeCovers(delegator, caller, mid)) {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }
    }

    function _bisectCascade(address adapter) internal returns (uint256) {
        address vault = IAdapter(adapter).vault();
        return _trueMaxDeallocatable(
            IVaultV2(vault).delegator(), adapter, IERC4626(vault).totalAssets() + IVaultV2(vault).freeAssets() + 1
        );
    }

    /// @dev The assets the lens should report for an adapter, sweeping first exactly as the lens does.
    ///      Must be called inside a snapshot: it leaves the sweep applied.
    function _postSweepMaxAssets(address adapter, uint256 trueCascade) internal returns (uint256) {
        address vault = IAdapter(adapter).vault();
        address delegator = IVaultV2(vault).delegator();
        if (IUniversalDelegator(delegator).sweepPending() > 0) {
            return 0;
        }
        uint256 limit = IUniversalDelegator(delegator).limitOf(adapter);
        uint256 adapterAssets = IAdapter(adapter).totalAssets();
        uint256 headroom = limit > adapterAssets ? limit - adapterAssets : 0;
        return _min(headroom, IVaultV2(vault).freeAssets() + trueCascade);
    }

    /* TESTS */

    function test_MainnetThreeFLensMatchesRealCascade() public {
        if (threeFAdapter == address(0)) {
            vm.skip(true, "ETH_RPC_URL and a deployed 3F mainnet adapter are required");
        }
        address adapter = threeFAdapter;

        uint256 snapshot = vm.snapshotState();
        uint256 lensAssets = lens.getMaxAssets(adapter);
        vm.revertToState(snapshot);

        snapshot = vm.snapshotState();
        uint256 legacyAssets = IThreeFAdapter(adapter).getMaxAssets();
        vm.revertToState(snapshot);

        // The lens recovers capacity the max-ask simulation behind `withdrawable()` drops, never less.
        assertGe(lensAssets, legacyAssets, "lens must not report less than the adapter's own getter");

        uint256 trueCascade = _bisectCascade(adapter);

        snapshot = vm.snapshotState();
        uint256 expectedAssets = _postSweepMaxAssets(adapter, trueCascade);
        vm.revertToState(snapshot);

        assertEq(lensAssets, expectedAssets, "lens must match the real cascade maximum");
    }

    function test_MainnetLiquidLaneLensMatchesRealCascade() public {
        if (liquidLaneAdapter == address(0)) {
            // Skipping keeps a vacuous run visible; a bare return would report green while asserting nothing.
            vm.skip(true, "no liquid lane adapter with a registered token on the mainnet delegator");
        }
        address adapter = liquidLaneAdapter;
        address tokenToRedeem = liquidLaneToken;

        uint256 snapshot = vm.snapshotState();
        uint256 lensAssets = lens.getMaxAssets(adapter, tokenToRedeem);
        vm.revertToState(snapshot);

        snapshot = vm.snapshotState();
        uint256 legacyAssets = ILiquidLaneAdapter(adapter).getMaxAssets(tokenToRedeem);
        vm.revertToState(snapshot);

        assertGe(lensAssets, legacyAssets, "lens must not report less than the adapter's own getter");
        assertEq(lensAssets, _expectedLaneAssets(adapter, tokenToRedeem), "lens must match the real cascade maximum");
    }

    /* LIQUID LANE EXPECTATION */

    function _expectedLaneAssets(address adapter, address tokenToRedeem) internal returns (uint256 expected) {
        // Acquire balances are read before the sweep, as the lens does; a sweep cannot change them.
        expected = _acquired(adapter, tokenToRedeem);

        uint256 trueCascade = _bisectCascade(adapter);

        uint256 snapshot = vm.snapshotState();
        uint256 maxAssets = _postSweepMaxAssets(adapter, trueCascade);
        if (maxAssets > 0) {
            expected += _min(maxAssets, _laneHeadroom(adapter, tokenToRedeem));
        }
        vm.revertToState(snapshot);
    }

    function _acquired(address adapter, address tokenToRedeem) internal view returns (uint256 acquired) {
        address owner = IOwnable(adapter).owner();
        acquired = ILiquidLaneAdapter(adapter).acquireBalance(tokenToRedeem, owner);
        address marketMaker = ILiquidLaneAdapter(adapter).marketMaker();
        if (marketMaker != owner) {
            acquired += ILiquidLaneAdapter(adapter).acquireBalance(tokenToRedeem, marketMaker);
        }
    }

    function _laneHeadroom(address adapter, address tokenToRedeem) internal view returns (uint256) {
        uint256 laneLimit = ILiquidLaneAdapter(adapter).limit(tokenToRedeem);
        uint256 laneAssets = IAccount(ILiquidLaneAdapter(adapter).accounts(tokenToRedeem)).totalAssets();
        return laneLimit > laneAssets ? laneLimit - laneAssets : 0;
    }

    function _findLiquidLane(address adapter) internal view returns (address laneAdapter, address tokenToRedeem) {
        laneAdapter = vm.envOr("MAINNET_LIQUID_LANE_ADAPTER", address(0));
        if (laneAdapter != address(0)) {
            return
                (laneAdapter, vm.envOr("MAINNET_LIQUID_LANE_TOKEN", ILiquidLaneAdapter(laneAdapter).tokensToRedeem(0)));
        }
        address delegator = IVaultV2(IAdapter(adapter).vault()).delegator();
        uint256 length = IUniversalDelegator(delegator).getAdaptersLength();
        for (uint256 i; i < length; ++i) {
            address candidate = IUniversalDelegator(delegator).adapters(i);
            try ILiquidLaneAdapter(candidate).getTokensToRedeemLength() returns (uint256 tokens) {
                if (tokens > 0) {
                    return (candidate, ILiquidLaneAdapter(candidate).tokensToRedeem(0));
                }
            } catch {}
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
