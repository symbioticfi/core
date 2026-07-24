// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {FrontendLiquidityLens} from "../../../src/contracts/adapters/utils/FrontendLiquidityLens.sol";

import {IAdapter} from "../../../src/interfaces/adapters/IAdapter.sol";
import {IAccount} from "../../../src/interfaces/adapters/ll-adapter/IAccount.sol";
import {ILiquidLaneAdapter} from "../../../src/interfaces/adapters/ILiquidLaneAdapter.sol";
import {IUniversalDelegator} from "../../../src/interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../../src/interfaces/vault/IVaultV2.sol";
import {SourceLiquidity} from "../../../src/interfaces/adapters/utils/ILiquidityLensDependencies.sol";

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";

/// @dev Liquid lane account whose reported assets drop once its realized balance is swept out.
contract MockLaneAccount {
    uint256 public totalAssets;

    constructor(uint256 initial) {
        totalAssets = initial;
    }

    function settle(uint256 settled) external {
        totalAssets = settled;
    }
}

/// @dev Delegator whose `sweepPending` really settles the lane account, as the live one does.
contract MockSweepingDelegator {
    MockLaneAccount internal immutable ACCOUNT;
    uint256 internal immutable SETTLED;

    constructor(MockLaneAccount account, uint256 settled) {
        ACCOUNT = account;
        SETTLED = settled;
    }

    function sweepPending() external returns (uint256) {
        ACCOUNT.settle(SETTLED);
        return 0;
    }

    function limitOf(address) external pure returns (uint256) {
        return type(uint256).max;
    }

    function getAdaptersLength() external pure returns (uint256) {
        return 0;
    }
}

/// @dev A later lens implementation, used to prove the proxy keeps its address across an upgrade.
contract FrontendLiquidityLensV2 is FrontendLiquidityLens {
    function upgradedMarker() external pure returns (uint256) {
        return 42;
    }
}

contract FrontendLiquidityLensTest is Test {
    FrontendLiquidityLens internal lens;
    ProxyAdmin internal proxyAdmin;
    SourceLiquidity[] internal legs;

    address internal constant PROXY_OWNER = address(0x0FFEE);
    address internal constant TARGET = address(0xA11CE);
    address internal constant VAULT = address(0x7A017);
    address internal constant DELEGATOR = address(0xDE1E6);
    address internal constant ASSET = address(0xA55E7);
    address internal constant TOKEN = address(0x70CE9);
    address internal constant ACCOUNT = address(0xACC07);

    function setUp() public {
        address implementation = address(new FrontendLiquidityLens());
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(implementation, PROXY_OWNER, "");
        lens = FrontendLiquidityLens(address(proxy));
        proxyAdmin = ProxyAdmin(_adminOf(address(proxy)));

        // Vault/delegator plumbing that leaves the cascade as the only binding term.
        vm.mockCall(TARGET, abi.encodeCall(IAdapter.vault, ()), abi.encode(VAULT));
        vm.mockCall(TARGET, abi.encodeCall(IAdapter.totalAssets, ()), abi.encode(uint256(0)));
        vm.mockCall(VAULT, abi.encodeCall(IVaultV2.delegator, ()), abi.encode(DELEGATOR));
        vm.mockCall(VAULT, abi.encodeCall(IVaultV2.freeAssets, ()), abi.encode(uint256(0)));
        vm.mockCall(VAULT, abi.encodeCall(IERC4626.asset, ()), abi.encode(ASSET));
        vm.mockCall(DELEGATOR, abi.encodeCall(IUniversalDelegator.sweepPending, ()), abi.encode(uint256(0)));
        vm.mockCall(DELEGATOR, abi.encodeCall(IUniversalDelegator.limitOf, (TARGET)), abi.encode(type(uint256).max));
        _setAdapterCount(0);
    }

    function _setAdapterCount(uint256 count) internal {
        vm.mockCall(DELEGATOR, abi.encodeCall(IUniversalDelegator.getAdaptersLength, ()), abi.encode(count));
    }

    /// @dev Reads the ProxyAdmin address a TransparentUpgradeableProxy stores in its ERC-1967 admin slot.
    function _adminOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967Utils.ADMIN_SLOT))));
    }

    function _add(SourceLiquidity memory leg) internal {
        address adapter = address(uint160(0x1000 + legs.length));
        vm.mockCall(DELEGATOR, abi.encodeCall(IUniversalDelegator.adapters, (legs.length)), abi.encode(adapter));
        vm.mockCall(
            address(lens), abi.encodeCall(FrontendLiquidityLens.sourceLiquidity, (adapter, ASSET)), abi.encode(leg)
        );
        legs.push(leg);
        _setAdapterCount(legs.length);
    }

    /* LEG BUILDERS */

    /// @dev A source that partial-fills up to `capacity`, private to this adapter.
    function _private(uint256 free, uint256 capacity) internal pure returns (SourceLiquidity memory leg) {
        leg.free = free;
        leg.position = capacity;
    }

    /// @dev A source that partial-fills, drawing its own `position` from a cash pool shared by `key`.
    function _shared(uint256 free, uint256 position, bytes32 key, uint256 cash)
        internal
        pure
        returns (SourceLiquidity memory leg)
    {
        leg = _private(free, position);
        leg.key1 = key;
        leg.cash1 = cash;
    }

    /// @dev A Morpho-shaped adapter: all-or-nothing, drawing private vault idle then the shared market
    ///      pool in lockstep with a liquidity-adapter exit-position pool (private by default).
    function _morpho(uint256 position, uint256 idle, uint256 realAssets, bytes32 marketKey, uint256 marketCash)
        internal
        view
        returns (SourceLiquidity memory leg)
    {
        leg = _morphoSharedExit(
            position, idle, realAssets, marketKey, marketCash, keccak256(abi.encode("la", legs.length))
        );
    }

    /// @dev A Morpho-shaped adapter whose liquidity-adapter exit position is shared under `laKey`.
    function _morphoSharedExit(
        uint256 position,
        uint256 idle,
        uint256 realAssets,
        bytes32 marketKey,
        uint256 marketCash,
        bytes32 laKey
    ) internal view returns (SourceLiquidity memory leg) {
        leg.position = position;
        leg.clamp = position < idle + realAssets ? position : idle + realAssets;
        leg.allOrNothing = true;
        leg.key1 = keccak256(abi.encode("idle", legs.length));
        leg.cash1 = idle;
        leg.key2 = marketKey;
        leg.cash2 = marketCash;
        leg.key3 = laKey;
        leg.cash3 = realAssets;
    }

    /* REFERENCE CASCADE */

    /// @dev Independent replay of the delegator cascade: each adapter is asked for the full remainder,
    ///      delivers its idle plus a source draw, and shared pools are consumed once across adapters.
    function _refCoverable(uint256 target) internal view returns (bool) {
        bytes32[] memory keys = new bytes32[](3 * legs.length);
        uint256[] memory cash = new uint256[](3 * legs.length);
        uint256 sources;
        for (uint256 i; i < legs.length; ++i) {
            sources = _refRegister(keys, cash, sources, legs[i].key1, legs[i].cash1);
            sources = _refRegister(keys, cash, sources, legs[i].key2, legs[i].cash2);
            sources = _refRegister(keys, cash, sources, legs[i].key3, legs[i].cash3);
        }

        uint256 unmet = target;
        for (uint256 i; i < legs.length && unmet > 0; ++i) {
            SourceLiquidity memory leg = legs[i];
            if (leg.free >= unmet) {
                return true;
            }
            uint256 need = unmet - leg.free;
            uint256 firstCash = leg.key1 == bytes32(0) ? type(uint256).max : cash[_refFind(keys, sources, leg.key1)];
            uint256 lockstepCash = leg.key3 == bytes32(0) ? type(uint256).max : cash[_refFind(keys, sources, leg.key3)];
            uint256 secondCash =
                leg.key2 == bytes32(0) ? 0 : _min(cash[_refFind(keys, sources, leg.key2)], lockstepCash);
            uint256 available = _min(leg.position, _satAdd(firstCash, secondCash));

            uint256 draw;
            if (leg.allOrNothing) {
                uint256 request = _min(need, leg.clamp);
                draw = request <= available ? request : 0;
            } else {
                draw = _min(need, available);
            }
            if (draw > 0) {
                uint256 fromFirst = _min(draw, firstCash);
                if (leg.key1 != bytes32(0)) {
                    cash[_refFind(keys, sources, leg.key1)] -= fromFirst;
                }
                if (draw > fromFirst) {
                    if (leg.key2 != bytes32(0)) {
                        cash[_refFind(keys, sources, leg.key2)] -= draw - fromFirst;
                    }
                    if (leg.key3 != bytes32(0)) {
                        cash[_refFind(keys, sources, leg.key3)] -= draw - fromFirst;
                    }
                }
            }
            uint256 delivered = leg.free + draw;
            unmet = delivered >= unmet ? 0 : unmet - delivered;
        }
        return unmet == 0;
    }

    function _refRegister(bytes32[] memory keys, uint256[] memory cash, uint256 count, bytes32 key, uint256 sourceCash)
        internal
        pure
        returns (uint256)
    {
        if (key == bytes32(0)) {
            return count;
        }
        for (uint256 j; j < count; ++j) {
            if (keys[j] == key) {
                if (sourceCash > cash[j]) {
                    cash[j] = sourceCash;
                }
                return count;
            }
        }
        keys[count] = key;
        cash[count] = sourceCash;
        return count + 1;
    }

    function _refFind(bytes32[] memory keys, uint256 sources, bytes32 key) internal pure returns (uint256) {
        for (uint256 j; j < sources; ++j) {
            if (keys[j] == key) {
                return j;
            }
        }
        revert("unregistered source");
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _satAdd(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            uint256 c = a + b;
            return c < a ? type(uint256).max : c;
        }
    }

    function _assertTight(uint256 max) internal view {
        if (max > 0) {
            assertTrue(_refCoverable(max), "cascade must cover the reported max");
        }
        assertFalse(_refCoverable(max + 1), "cascade must fail beyond the reported max");
    }

    function _max() internal returns (uint256) {
        return lens.getMaxAssets(TARGET);
    }

    /* SHARED-SOURCE TESTS */

    /// @dev Two vaults exiting the same Morpho market must consume the market's cash once, not twice.
    function test_SharedMorphoMarketAcrossTwoVaultsIsNotDoubleCounted() public {
        bytes32 market = keccak256("cbBTC/USDC");
        // Each vault holds 800k against the same market, which only has 1M of cash.
        _add(_morpho({position: 800_000e6, idle: 0, realAssets: 800_000e6, marketKey: market, marketCash: 1_000_000e6}));
        _add(_morpho({position: 800_000e6, idle: 0, realAssets: 800_000e6, marketKey: market, marketCash: 1_000_000e6}));

        uint256 max = _max();
        assertEq(max, 1_000_000e6, "shared market cash must be counted once");
        _assertTight(max);
    }

    /// @dev Independent markets are additive: the same positions on two markets fund the full 1.6M.
    function test_DistinctMorphoMarketsAreAdditive() public {
        _add(
            _morpho({
                position: 800_000e6,
                idle: 0,
                realAssets: 800_000e6,
                marketKey: keccak256("market-a"),
                marketCash: 1_000_000e6
            })
        );
        _add(
            _morpho({
                position: 800_000e6,
                idle: 0,
                realAssets: 800_000e6,
                marketKey: keccak256("market-b"),
                marketCash: 1_000_000e6
            })
        );

        uint256 max = _max();
        assertEq(max, 1_600_000e6, "distinct markets must both count");
        _assertTight(max);
    }

    /// @dev Two adapters supplying one Aave reserve cannot both withdraw the reserve's virtual balance.
    function test_SharedAaveReserveIsNotDoubleCounted() public {
        bytes32 reserve = keccak256("aUSDC");
        _add(_shared({free: 0, position: 80e6, key: reserve, cash: 100e6}));
        _add(_shared({free: 0, position: 80e6, key: reserve, cash: 100e6}));

        uint256 max = _max();
        assertEq(max, 100e6, "combined draw is capped by the reserve's cash");
        _assertTight(max);
    }

    /// @dev A shared pool caps the sum, but private idle balances on top of it still add.
    function test_SharedPoolWithPrivateIdle() public {
        bytes32 pool = keccak256("evk");
        _add(_shared({free: 5e6, position: 80e6, key: pool, cash: 100e6}));
        _add(_shared({free: 7e6, position: 80e6, key: pool, cash: 100e6}));

        uint256 max = _max();
        assertEq(max, 112e6, "idle is private, only the pool draw is shared");
        _assertTight(max);
    }

    /// @dev The market's remaining cash after the first vault bounds what the second can absorb.
    function test_SharedMarketPartiallyDrainedByEarlierAdapter() public {
        bytes32 market = keccak256("shared");
        _add(_morpho({position: 600_000e6, idle: 0, realAssets: 600_000e6, marketKey: market, marketCash: 1_000_000e6}));
        _add(_morpho({position: 900_000e6, idle: 0, realAssets: 900_000e6, marketKey: market, marketCash: 1_000_000e6}));

        uint256 max = _max();
        assertEq(max, 1_000_000e6);
        _assertTight(max);
    }

    /// @dev Two adapters wrapping the SAME morpho vault share one liquidity-adapter exit position:
    ///      even with ample market cash, the exit route can only be drawn once.
    function test_SameMorphoVaultTwoAdaptersShareExitPosition() public {
        bytes32 market = keccak256("deep-market");
        bytes32 la = keccak256("one-liquidity-adapter");
        // Market holds 1M of cash but the shared liquidity adapter's exit position is only 10k.
        _add(_morphoSharedExit(10_000e6, 0, 10_000e6, market, 1_000_000e6, la));
        _add(_morphoSharedExit(10_000e6, 0, 10_000e6, market, 1_000_000e6, la));

        uint256 max = _max();
        assertEq(max, 10_000e6, "one exit position cannot be drawn twice");
        _assertTight(max);
    }

    /// @dev Different morpho vaults on one market have their own liquidity adapters: the market cash is
    ///      the shared bound, not the exit positions.
    function test_DifferentVaultsSameMarketCapByMarketCash() public {
        bytes32 market = keccak256("tight-market");
        _add(_morpho({position: 800_000e6, idle: 0, realAssets: 800_000e6, marketKey: market, marketCash: 1_000_000e6}));
        _add(_morpho({position: 800_000e6, idle: 0, realAssets: 800_000e6, marketKey: market, marketCash: 1_000_000e6}));

        uint256 max = _max();
        assertEq(max, 1_000_000e6, "market cash is consumed once across vaults");
        _assertTight(max);
    }

    /* CASCADE TRUNCATION */

    /// @dev Registers a delegator slot pointing at a codeless adapter WITHOUT mocking the lens probe:
    ///      the real `sourceLiquidity` dispatch runs and aborts on returndata decoding.
    function _addBroken() internal {
        vm.mockCall(
            DELEGATOR,
            abi.encodeCall(IUniversalDelegator.adapters, (legs.length)),
            abi.encode(address(uint160(0xB40CE + legs.length)))
        );
        legs.push(_private({free: 0, capacity: 0}));
        _setAdapterCount(legs.length);
    }

    /// @dev The real cascade hard-reverts at a broken adapter, so nothing at or after it is fundable.
    function test_CascadeTruncatesAtBrokenAdapter() public {
        _add(_private({free: 0, capacity: 500_000e6}));
        _addBroken();
        _add(_private({free: 0, capacity: 300_000e6}));

        assertEq(_max(), 500_000e6, "legs after the broken adapter must not be counted");
    }

    /// @dev A broken first adapter blocks every ask that needs the cascade at all.
    function test_CascadeTruncatesEverythingWhenFirstAdapterBroken() public {
        _addBroken();
        _add(_private({free: 0, capacity: 500_000e6}));

        assertEq(_max(), 0, "no cascade capacity is reachable past a broken first adapter");
    }

    /* SINGLE-SOURCE TESTS */

    /// @dev The motivating example: an under-liquid 2M position (1M instant) followed by a liquid 0.5M
    ///      source supports exactly 1M, because asking 1.5M makes the first source revert to zero.
    function test_UnderLiquidThenLiquidExample() public {
        _add(
            _morpho({
                position: 2_000_000e6,
                idle: 0,
                realAssets: 2_000_000e6,
                marketKey: keccak256("under-liquid"),
                marketCash: 1_000_000e6
            })
        );
        _add(_private({free: 0, capacity: 500_000e6}));

        uint256 max = _max();
        assertEq(max, 1_000_000e6);
        _assertTight(max);
    }

    /// @dev Reversed order: the liquid source tops up the remainder before the fragile one absorbs.
    function test_LiquidThenUnderLiquidExample() public {
        _add(_private({free: 0, capacity: 500_000e6}));
        _add(
            _morpho({
                position: 2_000_000e6,
                idle: 0,
                realAssets: 2_000_000e6,
                marketKey: keccak256("under-liquid"),
                marketCash: 1_000_000e6
            })
        );

        uint256 max = _max();
        assertEq(max, 1_500_000e6);
        _assertTight(max);
    }

    function test_IdleBalancesAlwaysCount() public {
        _add(_private({free: 50e6, capacity: 0}));
        _add(_private({free: 0, capacity: 400e6}));

        uint256 max = _max();
        assertEq(max, 450e6);
        _assertTight(max);
    }

    function test_EmptyCascade() public {
        assertEq(_max(), 0);
    }

    /// @dev A pending sweep blocks allocation entirely, matching `allocateExact`'s early return.
    function test_PendingSweepReportsZero() public {
        _add(_private({free: 0, capacity: 500_000e6}));
        vm.mockCall(DELEGATOR, abi.encodeCall(IUniversalDelegator.sweepPending, ()), abi.encode(uint256(1)));

        assertEq(_max(), 0);
    }

    /// @dev The adapter's own delegator limit caps the reported maximum below the cascade capacity.
    function test_AdapterLimitCapsResult() public {
        _add(_private({free: 0, capacity: 500_000e6}));
        vm.mockCall(DELEGATOR, abi.encodeCall(IUniversalDelegator.limitOf, (TARGET)), abi.encode(uint256(120_000e6)));
        vm.mockCall(TARGET, abi.encodeCall(IAdapter.totalAssets, ()), abi.encode(uint256(20_000e6)));

        assertEq(_max(), 100_000e6);
    }

    /* LIQUID LANE OVERLOAD */

    /// @dev The liquid lane overload adds acquire balances and caps by the token's remaining lane limit.
    function test_LiquidLaneAddsAcquireAndCapsByTokenLimit() public {
        _add(_private({free: 0, capacity: 500_000e6}));

        address owner = address(0x0FFEE);
        address marketMaker = address(0x33333);
        vm.mockCall(TARGET, abi.encodeCall(Ownable.owner, ()), abi.encode(owner));
        vm.mockCall(TARGET, abi.encodeCall(ILiquidLaneAdapter.marketMaker, ()), abi.encode(marketMaker));
        vm.mockCall(
            TARGET, abi.encodeCall(ILiquidLaneAdapter.acquireBalance, (TOKEN, owner)), abi.encode(uint256(7000e6))
        );
        vm.mockCall(
            TARGET, abi.encodeCall(ILiquidLaneAdapter.acquireBalance, (TOKEN, marketMaker)), abi.encode(uint256(3000e6))
        );
        vm.mockCall(TARGET, abi.encodeCall(ILiquidLaneAdapter.limit, (TOKEN)), abi.encode(uint256(90_000e6)));
        vm.mockCall(TARGET, abi.encodeCall(ILiquidLaneAdapter.accounts, (TOKEN)), abi.encode(ACCOUNT));
        vm.mockCall(ACCOUNT, abi.encodeCall(IAccount.totalAssets, ()), abi.encode(uint256(20_000e6)));

        // acquire 7k + 3k, then min(cascade 500k, lane headroom 90k - 20k).
        assertEq(lens.getMaxAssets(TARGET, TOKEN), 80_000e6);
    }

    /// @dev When the market maker is the owner its acquire balance is counted once, not twice.
    function test_LiquidLaneDoesNotDoubleCountOwnerAcquire() public {
        _add(_private({free: 0, capacity: 0}));

        address owner = address(0x0FFEE);
        vm.mockCall(TARGET, abi.encodeCall(Ownable.owner, ()), abi.encode(owner));
        vm.mockCall(TARGET, abi.encodeCall(ILiquidLaneAdapter.marketMaker, ()), abi.encode(owner));
        vm.mockCall(
            TARGET, abi.encodeCall(ILiquidLaneAdapter.acquireBalance, (TOKEN, owner)), abi.encode(uint256(7000e6))
        );
        vm.mockCall(TARGET, abi.encodeCall(ILiquidLaneAdapter.limit, (TOKEN)), abi.encode(uint256(90_000e6)));
        vm.mockCall(TARGET, abi.encodeCall(ILiquidLaneAdapter.accounts, (TOKEN)), abi.encode(ACCOUNT));
        vm.mockCall(ACCOUNT, abi.encodeCall(IAccount.totalAssets, ()), abi.encode(uint256(0)));

        assertEq(lens.getMaxAssets(TARGET, TOKEN), 7000e6);
    }

    /// @dev The lane headroom must be measured after the sweep: a sweep releases account assets, so
    ///      reading `account.totalAssets()` first would understate the headroom by the released amount.
    function test_LiquidLaneReadsLaneHeadroomAfterTheSweep() public {
        MockLaneAccount account = new MockLaneAccount(60_000e6);
        MockSweepingDelegator sweeping = new MockSweepingDelegator(account, 20_000e6);

        vm.mockCall(VAULT, abi.encodeCall(IVaultV2.delegator, ()), abi.encode(address(sweeping)));
        vm.mockCall(VAULT, abi.encodeCall(IVaultV2.freeAssets, ()), abi.encode(uint256(500_000e6)));

        address owner = address(0x0FFEE);
        vm.mockCall(TARGET, abi.encodeCall(Ownable.owner, ()), abi.encode(owner));
        vm.mockCall(TARGET, abi.encodeCall(ILiquidLaneAdapter.marketMaker, ()), abi.encode(owner));
        vm.mockCall(TARGET, abi.encodeCall(ILiquidLaneAdapter.acquireBalance, (TOKEN, owner)), abi.encode(uint256(0)));
        vm.mockCall(TARGET, abi.encodeCall(ILiquidLaneAdapter.limit, (TOKEN)), abi.encode(uint256(90_000e6)));
        vm.mockCall(TARGET, abi.encodeCall(ILiquidLaneAdapter.accounts, (TOKEN)), abi.encode(address(account)));

        // The sweep settles 40k out of the account, so the headroom is 90k - 20k, not 90k - 60k.
        assertEq(lens.getMaxAssets(TARGET, TOKEN), 70_000e6);
        assertEq(account.totalAssets(), 20_000e6, "the sweep must have settled before the headroom read");
    }

    /// @dev With nothing allocatable the lane is never queried, matching the adapter's early return.
    function test_LiquidLaneReturnsAcquireOnlyWithoutReadingTheLane() public {
        vm.mockCall(DELEGATOR, abi.encodeCall(IUniversalDelegator.sweepPending, ()), abi.encode(uint256(1)));

        address owner = address(0x0FFEE);
        vm.mockCall(TARGET, abi.encodeCall(Ownable.owner, ()), abi.encode(owner));
        vm.mockCall(TARGET, abi.encodeCall(ILiquidLaneAdapter.marketMaker, ()), abi.encode(owner));
        vm.mockCall(
            TARGET, abi.encodeCall(ILiquidLaneAdapter.acquireBalance, (TOKEN, owner)), abi.encode(uint256(4000e6))
        );

        // `limit` and `accounts` are deliberately unmocked: reaching them would revert on the codeless target.
        assertEq(lens.getMaxAssets(TARGET, TOKEN), 4000e6);
    }

    /* SOURCE PROBES */

    function _mockAave(address adapter, address aToken, address pool, uint256 configuration) internal {
        // The adapter needs reverting code: unmatched type probes (`morphoVault()`, ...) must revert to
        // be caught by the probe's try/catch — empty success from a codeless mock would instead abort
        // `sourceLiquidity` on returndata decoding (degraded to zero by the cascade's outer try/catch).
        vm.etch(adapter, hex"60006000fd");
        vm.mockCall(adapter, abi.encodeWithSignature("aToken()"), abi.encode(aToken));
        vm.mockCall(aToken, abi.encodeWithSignature("POOL()"), abi.encode(pool));
        vm.mockCall(pool, abi.encodeWithSignature("getConfiguration(address)", ASSET), abi.encode(configuration));
        vm.mockCall(
            pool, abi.encodeWithSignature("getVirtualUnderlyingBalance(address)", ASSET), abi.encode(uint128(70e6))
        );
        vm.mockCall(ASSET, abi.encodeWithSignature("balanceOf(address)", adapter), abi.encode(uint256(3e6)));
        vm.mockCall(aToken, abi.encodeWithSignature("balanceOf(address)", adapter), abi.encode(uint256(40e6)));
    }

    /// @dev An active, unpaused reserve exposes the position against the shared virtual-balance pool.
    function test_AaveLegActiveReserve() public {
        address adapter = address(0xAA7E);
        _mockAave(adapter, address(0xA70CE), address(0x90019), 1 << 56);

        SourceLiquidity memory leg = lens.sourceLiquidity(adapter, ASSET);
        assertEq(leg.free, 3e6);
        assertEq(leg.position, 40e6);
        assertEq(leg.cash1, 70e6);
        assertTrue(leg.key1 != bytes32(0), "active reserve must be keyed to the shared pool");
    }

    /// @dev A paused reserve reverts withdrawals: the leg must carry no position, since a keyless leg
    ///      is treated as privately unbounded by the cascade.
    function test_AaveLegPausedReserveHasNoPosition() public {
        address adapter = address(0xAA7E);
        _mockAave(adapter, address(0xA70CE), address(0x90019), (1 << 56) | (1 << 60));

        SourceLiquidity memory leg = lens.sourceLiquidity(adapter, ASSET);
        assertEq(leg.free, 3e6, "idle balance is still delivered by the base wrapper");
        assertEq(leg.position, 0, "paused reserve must contribute no position");
        assertEq(leg.key1, bytes32(0));
    }

    /// @dev An inactive reserve is equally non-withdrawable.
    function test_AaveLegInactiveReserveHasNoPosition() public {
        address adapter = address(0xAA7E);
        _mockAave(adapter, address(0xA70CE), address(0x90019), 0);

        SourceLiquidity memory leg = lens.sourceLiquidity(adapter, ASSET);
        assertEq(leg.position, 0, "inactive reserve must contribute no position");
        assertEq(leg.key1, bytes32(0));
    }

    /* UPGRADEABILITY */

    /// @dev The proxy's admin is a ProxyAdmin owned by the deployer-chosen owner.
    function test_ProxyAdminOwnedByProxyOwner() public view {
        assertEq(proxyAdmin.owner(), PROXY_OWNER, "ProxyAdmin must be owned by the configured owner");
    }

    /// @dev Upgrading swaps the implementation while integrators keep querying the same proxy address.
    function test_UpgradeKeepsAddressAndAnswers() public {
        _add(_private({free: 0, capacity: 500_000e6}));
        uint256 answerBefore = lens.getMaxAssets(TARGET);

        address implementationV2 = address(new FrontendLiquidityLensV2());
        vm.prank(PROXY_OWNER);
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(lens)), implementationV2, "");

        assertEq(FrontendLiquidityLensV2(address(lens)).upgradedMarker(), 42, "new logic must be live");
        assertEq(lens.getMaxAssets(TARGET), answerBefore, "same address, same answer");
    }

    /// @dev Only the ProxyAdmin owner may upgrade the proxy.
    function test_UpgradeIsOwnerGated() public {
        address implementationV2 = address(new FrontendLiquidityLensV2());

        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(0xBAD)));
        proxyAdmin.upgradeAndCall(ITransparentUpgradeableProxy(address(lens)), implementationV2, "");
    }

    /// @dev The transparent proxy routes the admin's own calls to the ProxyAdmin, never to the lens logic,
    ///      so the admin cannot accidentally invoke lens functions; integrators (non-admin) always reach it.
    function test_AdminCannotCallLensLogic() public {
        _add(_private({free: 0, capacity: 500_000e6}));

        vm.prank(address(proxyAdmin));
        vm.expectRevert();
        lens.getMaxAssets(TARGET);

        // A normal caller reaches the logic and gets the real answer.
        assertEq(lens.getMaxAssets(TARGET), 500_000e6);
    }

    /* FUZZ */

    function testFuzz_MatchesReferenceCascade(
        uint256[6] memory frees,
        uint256[6] memory positions,
        uint256[6] memory cashes,
        uint8 sharing,
        uint8 kinds,
        uint256 probe
    ) public {
        for (uint256 i; i < 6; ++i) {
            uint256 free = frees[i] % 1000e6;
            uint256 position = positions[i] % 1000e6;
            uint256 cash = cashes[i] % 1000e6;
            // Bit i of `sharing` puts this adapter on a single shared pool instead of a private one.
            bytes32 key = (sharing >> i) & 1 == 1 ? keccak256("pool") : keccak256(abi.encode("private", i));

            if ((kinds >> i) & 1 == 1) {
                // All-or-nothing (Morpho-shaped): clamp may exceed the shared cash, creating the cliff.
                SourceLiquidity memory leg = _morpho({
                    position: position, idle: cash % 100e6, realAssets: position, marketKey: key, marketCash: cash
                });
                leg.free = free % 100e6;
                _add(leg);
            } else {
                _add(_shared({free: free, position: position, key: key, cash: cash}));
            }
        }

        uint256 max = _max();
        _assertTight(max);
        assertTrue(_refCoverable(probe % (max + 1)), "fundable set must be downward closed");
    }
}
