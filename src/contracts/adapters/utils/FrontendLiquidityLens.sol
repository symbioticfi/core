// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {IAdapter} from "../../../interfaces/adapters/IAdapter.sol";
import {IAaveV3Adapter} from "../../../interfaces/adapters/IAaveV3Adapter.sol";
import {IERC4626Adapter} from "../../../interfaces/adapters/IERC4626Adapter.sol";
import {IEulerAdapter} from "../../../interfaces/adapters/IEulerAdapter.sol";
import {ILiquidLaneAdapter} from "../../../interfaces/adapters/ILiquidLaneAdapter.sol";
import {IAccount} from "../../../interfaces/adapters/ll-adapter/IAccount.sol";
import {IMorphoLiquidityAdapter} from "../../../interfaces/adapters/morpho_vaultv2_adapter/IMorphoLiquidityAdapter.sol";
import {IMorphoVaultV2} from "../../../interfaces/adapters/morpho_vaultv2_adapter/IMorphoVaultV2.sol";
import {IMorphoVaultV2Adapter} from "../../../interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {IUniversalDelegator} from "../../../interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../../interfaces/vault/IVaultV2.sol";
import {
    IAaveAToken,
    IAaveV3PoolConfiguration,
    IEVaultCash,
    IMorphoBlue,
    IMorphoIrm,
    IMorphoMarketV1Adapter,
    IMorphoVaultV1Adapter,
    MorphoMarket,
    MorphoMarketParams,
    SourceLiquidity
} from "../../../interfaces/adapters/utils/ILiquidityLensDependencies.sol";
import {IAaveV3Pool} from "../../../interfaces/adapters/aave_v3_adapter/IAaveV3AdapterDependencies.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title FrontendLiquidityLens
/// @notice Stateless frontend lens for 3F and Liquid Lane adapters: the maximum assets `allocateExact`
///         can actually fund, modelling the delegator's greedy deallocation cascade with shared pools.
/// @dev `eth_call` only: the calculation runs permissionless delegator state transitions (`sweepPending`).
///      Deploy behind a `TransparentUpgradeableProxy` with empty init data; the lens holds no state.
/// @dev Accepted imprecision (each bounded): generic ERC4626 sources shared by two adapters are not
///      de-duplicated (no cash getter); the result can overstate by dust when the share-based adapter
///      limit binds exactly; Morpho Vault V1 exit liquidity is pooled per V1 vault (understates sharing)
///      and is not de-duplicated against a direct exit on one of its underlying markets.
contract FrontendLiquidityLens {
    using Math for uint256;

    /// @dev Aave reserve configuration bits: active (56) and paused (60).
    uint256 internal constant AAVE_ACTIVE_MASK = 1 << 56;
    uint256 internal constant AAVE_PAUSED_MASK = 1 << 60;

    /* FRONTEND API */

    /// @notice Returns the maximum assets currently allocatable to a 3F adapter.
    function getMaxAssets(address adapter) external returns (uint256) {
        return _getMaxAssets(adapter);
    }

    /// @notice Returns the maximum assets currently swappable through a Liquid Lane adapter.
    function getMaxAssets(address adapter, address tokenToRedeem) external returns (uint256) {
        address owner = Ownable(adapter).owner();
        uint256 acquired = ILiquidLaneAdapter(adapter).acquireBalance(tokenToRedeem, owner);
        address marketMaker = ILiquidLaneAdapter(adapter).marketMaker();
        if (marketMaker != owner) {
            acquired += ILiquidLaneAdapter(adapter).acquireBalance(tokenToRedeem, marketMaker);
        }

        // The lane headroom is read after `_getMaxAssets`, whose sweep releases account balances —
        // reading it first would understate the headroom, diverging from the adapter's own getter.
        uint256 maxAssets = _getMaxAssets(adapter);
        if (maxAssets == 0) {
            return acquired;
        }

        uint256 headroom = ILiquidLaneAdapter(adapter).limit(tokenToRedeem)
            .saturatingSub(IAccount(ILiquidLaneAdapter(adapter).accounts(tokenToRedeem)).totalAssets());
        return acquired + Math.min(maxAssets, headroom);
    }

    /* VIEW FUNCTIONS */

    /// @notice Returns the instant-liquidity decomposition of an adapter for the deallocation cascade.
    /// @param adapter Adapter address.
    /// @param asset Vault asset address.
    /// @return leg Source decomposition (see `SourceLiquidity`).
    /// @dev External so the cascade can catch a revert here as the real cascade's halting point.
    function sourceLiquidity(address adapter, address asset) external view returns (SourceLiquidity memory leg) {
        try IMorphoVaultV2Adapter(adapter).morphoVault() returns (address morphoVault) {
            return _morphoLeg(adapter, morphoVault, asset);
        } catch {}
        try IAaveV3Adapter(adapter).aToken() returns (address aToken) {
            return _aaveLeg(adapter, aToken, asset);
        } catch {}
        try IEulerAdapter(adapter).lendVault() returns (address lendVault) {
            return _eulerLeg(adapter, lendVault, asset);
        } catch {}
        try IERC4626Adapter(adapter).erc4626Vault() returns (address erc4626Vault) {
            // Trusts the wrapped vault's liquidity-aware `maxWithdraw`; private, as it has no cash getter.
            leg.free = IERC20(asset).balanceOf(adapter);
            leg.position = IERC4626(erc4626Vault).maxWithdraw(adapter);
            return leg;
        } catch {}
        try ILiquidLaneAdapter(adapter).getTokensToRedeemLength() returns (uint256 length) {
            // Liquid lane deallocation sweeps the accounts' realized balances only, regardless of the ask.
            for (uint256 i; i < length; ++i) {
                leg.free += IERC20(asset)
                    .balanceOf(ILiquidLaneAdapter(adapter).accounts(ILiquidLaneAdapter(adapter).tokensToRedeem(i)));
            }
            return leg;
        } catch {}
        // 3F, app, and unknown adapters deliver their idle balance only.
        leg.free = IAdapter(adapter).freeAssets();
    }

    /* INTERNAL FUNCTIONS */

    /// @dev Returns the maximum assets `allocateExact(adapter, assets)` can fund, ignoring per-request caps.
    function _getMaxAssets(address adapter) internal returns (uint256) {
        address vault = IAdapter(adapter).vault();
        address delegator = IVaultV2(vault).delegator();
        if (IUniversalDelegator(delegator).sweepPending() > 0) {
            return 0;
        }
        return Math.min(
            IUniversalDelegator(delegator).limitOf(adapter).saturatingSub(IAdapter(adapter).totalAssets()),
            IVaultV2(vault).freeAssets().saturatingAdd(_maxDeallocatable(delegator, IERC4626(vault).asset()))
        );
    }

    /// @dev Returns the maximum assets the greedy deallocation cascade can cover in a single exact ask.
    function _maxDeallocatable(address delegator, address asset) internal view returns (uint256) {
        uint256 length = IUniversalDelegator(delegator).getAdaptersLength();
        SourceLiquidity[] memory legs = new SourceLiquidity[](length);
        bytes32[] memory keys = new bytes32[](3 * length);
        uint256[] memory cash = new uint256[](3 * length);
        uint256 count;
        uint256 sources;
        uint256 hi;
        for (uint256 i; i < length; ++i) {
            try this.sourceLiquidity(IUniversalDelegator(delegator).adapters(i), asset) returns (
                SourceLiquidity memory leg
            ) {
                legs[count++] = leg;
                hi = hi.saturatingAdd(leg.free).saturatingAdd(leg.position);
                sources = _register(keys, cash, sources, leg.key1, leg.cash1);
                sources = _register(keys, cash, sources, leg.key2, leg.cash2);
                sources = _register(keys, cash, sources, leg.key3, leg.cash3);
            } catch {
                // The real cascade calls `deallocate` uncaught and the reads that just reverted are its
                // pre-clamp reads: any ask reaching this adapter reverts, so nothing after it is fundable.
                break;
            }
        }

        // Binary search the largest ask the cascade fully covers (the fundable set is downward closed).
        uint256 lo;
        while (lo < hi) {
            uint256 mid = hi - (hi - lo) / 2;
            if (_coverable(legs, count, keys, cash, sources, mid)) {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }
        return lo;
    }

    /// @dev Records a shared pool key once; a duplicate keeps the larger cash (registrations may be
    ///      owner-capped views of one pool, and every draw stays bounded by its leg's own position).
    function _register(bytes32[] memory keys, uint256[] memory cash, uint256 count, bytes32 key, uint256 sourceCash)
        private
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

    /// @dev Replays the cascade for a target ask against the pool-capped leg model.
    function _coverable(
        SourceLiquidity[] memory legs,
        uint256 count,
        bytes32[] memory keys,
        uint256[] memory cash,
        uint256 sources,
        uint256 target
    ) private pure returns (bool) {
        uint256[] memory remaining = new uint256[](sources);
        for (uint256 j; j < sources; ++j) {
            remaining[j] = cash[j];
        }
        uint256 unmet = target;
        for (uint256 i; i < count && unmet > 0; ++i) {
            unmet = _deliver(legs[i], keys, remaining, sources, unmet);
        }
        return unmet == 0;
    }

    /// @dev Applies one adapter's delivery to the outstanding ask.
    function _deliver(
        SourceLiquidity memory leg,
        bytes32[] memory keys,
        uint256[] memory remaining,
        uint256 sources,
        uint256 unmet
    ) private pure returns (uint256) {
        if (leg.free >= unmet) {
            return 0;
        }
        uint256 need = unmet - leg.free;

        (uint256 firstCash, uint256 secondCash) = _capacities(leg, keys, remaining, sources);
        uint256 available = Math.min(leg.position, firstCash.saturatingAdd(secondCash));
        uint256 draw;
        if (leg.allOrNothing) {
            uint256 request = Math.min(need, leg.clamp);
            draw = request <= available ? request : 0;
        } else {
            draw = Math.min(need, available);
        }
        if (draw != 0) {
            _consume(leg, keys, remaining, sources, draw, firstCash);
        }

        uint256 delivered = leg.free + draw;
        return delivered >= unmet ? 0 : unmet - delivered;
    }

    /// @dev Returns the remaining first-pool and second-source capacities for a leg.
    function _capacities(SourceLiquidity memory leg, bytes32[] memory keys, uint256[] memory remaining, uint256 sources)
        private
        pure
        returns (uint256 firstCash, uint256 secondCash)
    {
        firstCash = leg.key1 == bytes32(0) ? type(uint256).max : remaining[_find(keys, sources, leg.key1)];
        if (leg.key2 != bytes32(0)) {
            secondCash = remaining[_find(keys, sources, leg.key2)];
            if (leg.key3 != bytes32(0)) {
                secondCash = Math.min(secondCash, remaining[_find(keys, sources, leg.key3)]);
            }
        }
    }

    /// @dev Consumes a draw: the first pool up to its cash, the rest from both second-source pools.
    ///      A remainder past the first pool implies a keyed second source (`secondCash` was nonzero).
    function _consume(
        SourceLiquidity memory leg,
        bytes32[] memory keys,
        uint256[] memory remaining,
        uint256 sources,
        uint256 draw,
        uint256 firstCash
    ) private pure {
        uint256 fromFirst = Math.min(draw, firstCash);
        if (leg.key1 != bytes32(0)) {
            remaining[_find(keys, sources, leg.key1)] -= fromFirst;
        }
        if (draw > fromFirst) {
            remaining[_find(keys, sources, leg.key2)] -= draw - fromFirst;
            if (leg.key3 != bytes32(0)) {
                remaining[_find(keys, sources, leg.key3)] -= draw - fromFirst;
            }
        }
    }

    /// @dev Returns the index of a registered source key.
    function _find(bytes32[] memory keys, uint256 sources, bytes32 key) private pure returns (uint256) {
        for (uint256 j; j < sources; ++j) {
            if (keys[j] == key) {
                return j;
            }
        }
        return type(uint256).max;
    }

    /// @dev Aave supply: capped by the shared reserve's virtual balance. An inactive or paused reserve
    ///      reverts withdrawals, so it contributes no position (a keyless leg is privately unbounded).
    function _aaveLeg(address adapter, address aToken, address asset)
        internal
        view
        returns (SourceLiquidity memory leg)
    {
        leg.free = IERC20(asset).balanceOf(adapter);

        address pool = IAaveAToken(aToken).POOL();
        uint256 configuration = IAaveV3PoolConfiguration(pool).getConfiguration(asset);
        if (configuration & AAVE_ACTIVE_MASK != 0 && configuration & AAVE_PAUSED_MASK == 0) {
            leg.position = IERC20(aToken).balanceOf(adapter);
            leg.key1 = keccak256(abi.encode("aave", aToken));
            leg.cash1 = IAaveV3Pool(pool).getVirtualUnderlyingBalance(asset);
        }
    }

    /// @dev Euler supply: capped by the shared EVK vault cash, private if `cash()` is unavailable
    ///      (`maxWithdraw` already embeds the cash cap in `position`).
    function _eulerLeg(address adapter, address lendVault, address asset)
        internal
        view
        returns (SourceLiquidity memory leg)
    {
        leg.free = IERC20(asset).balanceOf(adapter);
        leg.position = Math.min(
            IERC4626(lendVault).previewRedeem(IEulerAdapter(adapter).totalShares()),
            IERC4626(lendVault).maxWithdraw(adapter)
        );
        try IEVaultCash(lendVault).cash() returns (uint256 sourceCash) {
            leg.key1 = keccak256(abi.encode("euler", lendVault));
            leg.cash1 = sourceCash;
        } catch {}
    }

    /// @dev Morpho supply: an all-or-nothing withdrawal drawing the vault's idle then the exit route.
    ///      `clamp` mirrors the adapter's own cap (idle plus optimistic `realAssets`): a request within
    ///      it still yields zero when the route's true cash cannot cover it.
    function _morphoLeg(address adapter, address morphoVault, address asset)
        internal
        view
        returns (SourceLiquidity memory leg)
    {
        leg.free = IERC20(asset).balanceOf(adapter);
        leg.position = IERC4626(morphoVault).previewRedeem(IMorphoVaultV2Adapter(adapter).totalShares());
        leg.allOrNothing = true;

        uint256 vaultIdle = IERC20(asset).balanceOf(morphoVault);
        address liquidityAdapter = IMorphoVaultV2(morphoVault).liquidityAdapter();
        uint256 realAssets = liquidityAdapter == address(0) ? 0 : IMorphoLiquidityAdapter(liquidityAdapter).realAssets();

        leg.clamp = Math.min(leg.position, vaultIdle + realAssets);
        leg.key1 = keccak256(abi.encode("morphoIdle", morphoVault));
        leg.cash1 = vaultIdle;
        if (liquidityAdapter != address(0)) {
            (leg.key2, leg.cash2, leg.key3, leg.cash3) = _morphoExit(morphoVault, liquidityAdapter);
        }
    }

    /// @dev Returns the shared pools a forced Morpho exit draws in lockstep: the exit route's cash (the
    ///      Blue market per morpho-org/morpho-snippets `VaultV2LiquidityLib`, or the wrapped Vault V1)
    ///      and the liquidity adapter's own exit position — so two vaults exiting the same market consume
    ///      its cash once, and two adapters wrapping one vault consume the one exit position once.
    function _morphoExit(address morphoVault, address liquidityAdapter)
        internal
        view
        returns (bytes32 routeKey, uint256 routeCash, bytes32 positionKey, uint256 positionCash)
    {
        try IMorphoMarketV1Adapter(liquidityAdapter).morpho() returns (address morpho) {
            bytes memory liquidityData = IMorphoVaultV2(morphoVault).liquidityData();
            if (liquidityData.length == 0) {
                return (bytes32(0), 0, bytes32(0), 0);
            }
            MorphoMarketParams memory marketParams = abi.decode(liquidityData, (MorphoMarketParams));
            bytes32 marketId = keccak256(abi.encode(marketParams));
            uint256 shares = IMorphoMarketV1Adapter(liquidityAdapter).supplyShares(marketId);
            if (shares == 0) {
                return (bytes32(0), 0, bytes32(0), 0);
            }
            MorphoMarket memory market = IMorphoBlue(morpho).market(marketId);
            _morphoAccrueInterest(marketParams, market);
            return (
                keccak256(abi.encode("morphoMarket", morpho, marketId)),
                Math.min(
                    uint256(market.totalSupplyAssets).saturatingSub(market.totalBorrowAssets),
                    IERC20(marketParams.loanToken).balanceOf(morpho)
                ),
                keccak256(abi.encode("morphoLiquidityAdapter", liquidityAdapter)),
                // Morpho shares to assets, rounding down (virtual amounts 1 and 1e6).
                shares.mulDiv(uint256(market.totalSupplyAssets) + 1, uint256(market.totalSupplyShares) + 1e6)
            );
        } catch {}
        try IMorphoVaultV1Adapter(liquidityAdapter).morphoVaultV1() returns (address morphoVaultV1) {
            try IMorphoVaultV2(morphoVaultV1).liquidityAdapter() returns (address) {
                // Nested Vault V2: conservatively ignored.
                return (bytes32(0), 0, bytes32(0), 0);
            } catch {
                // Vault V1 `maxWithdraw` walks its withdraw queue and is liquidity-aware. The V1 pool is
                // keyed per vault with owner-capped cash (`_register` keeps the largest view).
                uint256 withdrawable = IERC4626(morphoVaultV1).maxWithdraw(liquidityAdapter);
                return (
                    keccak256(abi.encode("morphoVaultV1", morphoVaultV1)),
                    withdrawable,
                    keccak256(abi.encode("morphoLiquidityAdapter", liquidityAdapter)),
                    withdrawable
                );
            }
        } catch {}
    }

    /// @dev Accrues pending interest on a stored Morpho Blue market in memory, mirroring
    ///      `Morpho._accrueInterest` and `MorphoBalancesLib.expectedMarketBalances`.
    function _morphoAccrueInterest(MorphoMarketParams memory marketParams, MorphoMarket memory market) internal view {
        uint256 elapsed = block.timestamp - market.lastUpdate;
        if (elapsed == 0 || market.totalBorrowAssets == 0 || marketParams.irm == address(0)) {
            return;
        }
        uint256 firstTerm;
        try IMorphoIrm(marketParams.irm).borrowRateView(marketParams, market) returns (uint256 borrowRate) {
            firstTerm = borrowRate * elapsed;
        } catch {
            return;
        }
        uint256 secondTerm = firstTerm.mulDiv(firstTerm, 2e18);
        uint256 interest =
            uint256(market.totalBorrowAssets).mulDiv(firstTerm + secondTerm + secondTerm.mulDiv(firstTerm, 3e18), 1e18);
        market.totalSupplyAssets += uint128(interest);
        market.totalBorrowAssets += uint128(interest);
        if (market.fee != 0) {
            uint256 feeAmount = interest.mulDiv(market.fee, 1e18);
            market.totalSupplyShares += uint128(
                feeAmount.mulDiv(
                    uint256(market.totalSupplyShares) + 1e6, uint256(market.totalSupplyAssets) - feeAmount + 1
                )
            );
        }
    }
}
