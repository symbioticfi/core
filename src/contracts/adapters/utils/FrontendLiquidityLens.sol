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
    IOwnable,
    MorphoMarket,
    MorphoMarketParams,
    SourceLiquidity
} from "../../../interfaces/adapters/utils/ILiquidityLensDependencies.sol";
import {IAaveV3Pool} from "../../../interfaces/adapters/aave_v3_adapter/IAaveV3AdapterDependencies.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title FrontendLiquidityLens
/// @notice Stateless frontend lens for 3F and Liquid Lane adapters.
/// @dev Call the overloaded `getMaxAssets` functions with `eth_call`/simulation. The calculation
///      intentionally simulates permissionless delegator state transitions and is therefore not `view`.
/// @dev Deploy behind an OpenZeppelin `TransparentUpgradeableProxy` so integrators can keep one address
///      as the source liquidity modelling evolves; the owning `ProxyAdmin` performs upgrades. The lens
///      holds no state, so no initializer is needed: deploy with empty proxy init data, and a later
///      version may append state (and add a reinitializer) without disturbing this layout.
contract FrontendLiquidityLens {
    using Math for uint256;

    /// @dev Aave reserve configuration bit positions.
    uint256 internal constant AAVE_ACTIVE_MASK = 1 << 56;
    uint256 internal constant AAVE_PAUSED_MASK = 1 << 60;
    /// @dev Morpho Blue shares math virtual amounts and WAD.
    uint256 internal constant MORPHO_VIRTUAL_ASSETS = 1;
    uint256 internal constant MORPHO_VIRTUAL_SHARES = 1e6;
    uint256 internal constant WAD = 1e18;

    /* FRONTEND API */

    /// @notice Returns the maximum assets currently allocatable to a 3F adapter.
    /// @dev Use `eth_call`; sending a transaction is unnecessary.
    function getMaxAssets(address adapter) external returns (uint256) {
        return _getMaxAssets(adapter);
    }

    /// @notice Returns the maximum assets currently swappable through a Liquid Lane adapter.
    /// @dev Use `eth_call`; sending a transaction is unnecessary.
    function getMaxAssets(address adapter, address tokenToRedeem) external returns (uint256) {
        address owner = IOwnable(adapter).owner();
        uint256 acquired = ILiquidLaneAdapter(adapter).acquireBalance(tokenToRedeem, owner);
        address marketMaker = ILiquidLaneAdapter(adapter).marketMaker();
        if (marketMaker != owner) {
            acquired += ILiquidLaneAdapter(adapter).acquireBalance(tokenToRedeem, marketMaker);
        }

        // `_getMaxAssets` sweeps before measuring, and a sweep moves realized account balances out to the
        // vault. The lane headroom is therefore read afterwards, exactly as `ILiquidLaneAdapter.getMaxAssets`
        // does; reading it first would understate the headroom by the amount the sweep is about to release.
        uint256 maxAssets = _getMaxAssets(adapter);
        if (maxAssets == 0) {
            return acquired;
        }

        uint256 accountCapacity = ILiquidLaneAdapter(adapter).limit(tokenToRedeem)
            .saturatingSub(IAccount(ILiquidLaneAdapter(adapter).accounts(tokenToRedeem)).totalAssets());
        return acquired + Math.min(maxAssets, accountCapacity);
    }

    /* VIEW FUNCTIONS */

    /// @notice Returns the instant-liquidity decomposition of an adapter for the deallocation cascade.
    /// @param adapter Adapter address.
    /// @param asset Vault asset address.
    /// @return leg Source decomposition (see `SourceLiquidity`).
    /// @dev External so cascade probing can degrade a misbehaving adapter to zero via try/catch.
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
            // Trusts the wrapped vault's liquidity-aware `maxWithdraw`; private, as it exposes no cash getter.
            leg.free = IERC20(asset).balanceOf(adapter);
            leg.position = IERC4626(erc4626Vault).maxWithdraw(adapter);
            leg.clamp = leg.position;
            leg.partialFill = true;
            return leg;
        } catch {}
        try ILiquidLaneAdapter(adapter).getTokensToRedeemLength() returns (uint256 length) {
            // Liquid lane deallocation sweeps the accounts' realized balances only, regardless of the ask.
            for (uint256 i; i < length; ++i) {
                leg.free += IERC20(asset)
                    .balanceOf(ILiquidLaneAdapter(adapter).accounts(ILiquidLaneAdapter(adapter).tokensToRedeem(i)));
            }
            leg.partialFill = true;
            return leg;
        } catch {}
        // 3F, app, and unknown adapters deliver their idle balance only.
        leg.free = IAdapter(adapter).freeAssets();
        leg.partialFill = true;
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
            IVaultV2(vault).freeAssets() + _maxDeallocatable(delegator, IERC4626(vault).asset())
        );
    }

    /// @dev Returns the maximum assets the greedy deallocation cascade can cover in a single exact ask.
    function _maxDeallocatable(address delegator, address asset) internal view returns (uint256) {
        uint256 length = IUniversalDelegator(delegator).getAdaptersLength();
        SourceLiquidity[] memory legs = new SourceLiquidity[](length);
        bytes32[] memory keys = new bytes32[](2 * length);
        uint256[] memory cash = new uint256[](2 * length);
        uint256 sources;
        uint256 hi;
        for (uint256 i; i < length; ++i) {
            SourceLiquidity memory leg;
            try this.sourceLiquidity(IUniversalDelegator(delegator).adapters(i), asset) returns (
                SourceLiquidity memory probed
            ) {
                leg = probed;
            } catch {}
            legs[i] = leg;
            hi = hi.saturatingAdd(leg.free).saturatingAdd(leg.position);
            sources = _register(keys, cash, sources, leg.key1, leg.cash1);
            sources = _register(keys, cash, sources, leg.key2, leg.cash2);
        }

        // Binary search the largest ask the cascade fully covers (the fundable set is downward closed).
        uint256 lo;
        while (lo < hi) {
            uint256 mid = (lo + hi + 1) >> 1;
            if (_coverable(legs, keys, cash, sources, mid)) {
                lo = mid;
            } else {
                hi = mid - 1;
            }
        }
        return lo;
    }

    /// @dev Records a shared source key with its cash once (first occurrence wins); returns the new count.
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
                return count;
            }
        }
        keys[count] = key;
        cash[count] = sourceCash;
        return count + 1;
    }

    /// @dev Replays the cascade for a target ask against the per-source-capped leg model.
    function _coverable(
        SourceLiquidity[] memory legs,
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
        for (uint256 i; i < legs.length && unmet > 0; ++i) {
            unmet = _deliver(legs[i], keys, remaining, sources, unmet);
        }
        return unmet == 0;
    }

    /// @dev Applies one adapter's delivery to the outstanding ask, consuming shared source cash in order.
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

        uint256 first = leg.key1 == bytes32(0) ? type(uint256).max : _find(keys, sources, leg.key1);
        uint256 second = leg.key2 == bytes32(0) ? type(uint256).max : _find(keys, sources, leg.key2);
        uint256 firstCash = first == type(uint256).max ? type(uint256).max : remaining[first];
        uint256 secondCash = second == type(uint256).max ? 0 : Math.min(remaining[second], leg.position2);

        uint256 available = Math.min(leg.position, firstCash.saturatingAdd(secondCash));
        uint256 draw;
        if (leg.partialFill) {
            draw = Math.min(need, available);
        } else {
            uint256 request = Math.min(need, leg.clamp);
            draw = request <= available ? request : 0;
        }

        if (draw != 0) {
            uint256 fromFirst = Math.min(draw, firstCash);
            if (first != type(uint256).max) {
                remaining[first] -= fromFirst;
            }
            if (second != type(uint256).max && draw > fromFirst) {
                remaining[second] -= draw - fromFirst;
            }
        }

        uint256 delivered = leg.free + draw;
        return delivered >= unmet ? 0 : unmet - delivered;
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

    /// @dev Aave supply: partial-fill capped by the shared reserve's virtual balance, zero if inactive or paused.
    function _aaveLeg(address adapter, address aToken, address asset)
        internal
        view
        returns (SourceLiquidity memory leg)
    {
        leg.free = IERC20(asset).balanceOf(adapter);
        leg.position = IERC20(aToken).balanceOf(adapter);
        leg.clamp = leg.position;
        leg.partialFill = true;

        address pool = IAaveAToken(aToken).POOL();
        uint256 configuration = IAaveV3PoolConfiguration(pool).getConfiguration(asset);
        if (configuration & AAVE_ACTIVE_MASK != 0 && configuration & AAVE_PAUSED_MASK == 0) {
            leg.key1 = keccak256(abi.encode("aave", aToken));
            leg.cash1 = IAaveV3Pool(pool).getVirtualUnderlyingBalance(asset);
        }
    }

    /// @dev Euler supply: partial-fill capped by the shared EVK vault cash, private if `cash()` is unavailable.
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
        leg.clamp = leg.position;
        leg.partialFill = true;
        try IEVaultCash(lendVault).cash() returns (uint256 sourceCash) {
            leg.key1 = keccak256(abi.encode("euler", lendVault));
            leg.cash1 = sourceCash;
        } catch {}
    }

    /// @dev Morpho supply: an all-or-nothing withdrawal drawing the vault's private idle then the shared exit
    ///      market's cash. `clamp` uses the liquidity adapter's optimistic `realAssets`, so it exceeds the
    ///      truly available idle plus market cash exactly when the market is under-liquid, yielding zero.
    function _morphoLeg(address adapter, address morphoVault, address asset)
        internal
        view
        returns (SourceLiquidity memory leg)
    {
        leg.free = IERC20(asset).balanceOf(adapter);
        leg.position = IERC4626(morphoVault).previewRedeem(IMorphoVaultV2Adapter(adapter).totalShares());

        uint256 vaultIdle = IERC20(asset).balanceOf(morphoVault);
        address liquidityAdapter = IMorphoVaultV2(morphoVault).liquidityAdapter();
        uint256 realAssets = liquidityAdapter == address(0) ? 0 : IMorphoLiquidityAdapter(liquidityAdapter).realAssets();

        leg.clamp = Math.min(leg.position, vaultIdle + realAssets);
        leg.key1 = keccak256(abi.encode("morphoIdle", morphoVault));
        leg.cash1 = vaultIdle;
        if (liquidityAdapter != address(0)) {
            (leg.key2, leg.cash2, leg.position2) = _morphoMarket(morphoVault, liquidityAdapter);
        }
    }

    /// @dev Returns the shared exit-source key and instant cash reachable through a Morpho liquidity adapter,
    ///      mirroring the vault's forced exit from the single market encoded in `liquidityData`. Follows
    ///      morpho-org/morpho-snippets `VaultV2LiquidityLib`: accrued market supply minus borrow, capped by
    ///      the loan token held in the Morpho singleton. Unlike the reference, which returns the two already
    ///      combined as one vault's withdrawable, the shared market cash and the liquidity adapter's own
    ///      supply are returned separately, so two vaults exiting the same market consume one shared pool
    ///      instead of each counting the whole of it.
    function _morphoMarket(address morphoVault, address liquidityAdapter)
        internal
        view
        returns (bytes32 key, uint256 cash, uint256 position)
    {
        try IMorphoMarketV1Adapter(liquidityAdapter).morpho() returns (address morpho) {
            bytes memory liquidityData = IMorphoVaultV2(morphoVault).liquidityData();
            if (liquidityData.length == 0) {
                return (bytes32(0), 0, 0);
            }
            MorphoMarketParams memory marketParams = abi.decode(liquidityData, (MorphoMarketParams));
            bytes32 marketId = keccak256(abi.encode(marketParams));
            uint256 shares = IMorphoMarketV1Adapter(liquidityAdapter).supplyShares(marketId);
            if (shares == 0) {
                return (bytes32(0), 0, 0);
            }
            MorphoMarket memory market = IMorphoBlue(morpho).market(marketId);
            _morphoAccrueInterest(marketParams, market);
            return (
                keccak256(abi.encode("morphoMarket", morpho, marketId)),
                Math.min(
                    uint256(market.totalSupplyAssets).saturatingSub(market.totalBorrowAssets),
                    IERC20(marketParams.loanToken).balanceOf(morpho)
                ),
                shares.mulDiv(
                    uint256(market.totalSupplyAssets) + MORPHO_VIRTUAL_ASSETS,
                    uint256(market.totalSupplyShares) + MORPHO_VIRTUAL_SHARES
                )
            );
        } catch {}
        try IMorphoVaultV1Adapter(liquidityAdapter).morphoVaultV1() returns (address morphoVaultV1) {
            try IMorphoVaultV2(morphoVaultV1).liquidityAdapter() returns (address) {
                // Nested Vault V2: conservatively ignored.
                return (bytes32(0), 0, 0);
            } catch {
                // Morpho Vault V1 `maxWithdraw` walks its withdraw queue and is liquidity-aware.
                uint256 withdrawable = IERC4626(morphoVaultV1).maxWithdraw(liquidityAdapter);
                return (keccak256(abi.encode("morphoVaultV1", morphoVaultV1)), withdrawable, withdrawable);
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
        uint256 secondTerm = firstTerm.mulDiv(firstTerm, 2 * WAD);
        uint256 interest = uint256(market.totalBorrowAssets)
            .mulDiv(firstTerm + secondTerm + secondTerm.mulDiv(firstTerm, 3 * WAD), WAD);
        market.totalSupplyAssets += uint128(interest);
        market.totalBorrowAssets += uint128(interest);
        if (market.fee != 0) {
            uint256 feeAmount = interest.mulDiv(market.fee, WAD);
            market.totalSupplyShares += uint128(
                feeAmount.mulDiv(
                    uint256(market.totalSupplyShares) + MORPHO_VIRTUAL_SHARES,
                    uint256(market.totalSupplyAssets) - feeAmount + MORPHO_VIRTUAL_ASSETS
                )
            );
        }
    }
}
