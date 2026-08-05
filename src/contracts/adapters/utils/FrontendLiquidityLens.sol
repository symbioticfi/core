// SPDX-License-Identifier: BUSL-1.1
// Copyright (c) 2026 Symbiotic
pragma solidity ^0.8.28;

import {
    IAaveAToken,
    IAaveV3PoolConfiguration,
    IEVaultCash,
    IMorphoBlue,
    IMorphoMarketV1Adapter,
    IMorphoVaultV1Adapter,
    MorphoMarket,
    MorphoMarketParams
} from "../../../interfaces/adapters/utils/ILiquidityLensDependencies.sol";
import {IAaveV3Adapter} from "../../../interfaces/adapters/IAaveV3Adapter.sol";
import {IAaveV3Pool} from "../../../interfaces/adapters/aave_v3_adapter/IAaveV3AdapterDependencies.sol";
import {IAccount} from "../../../interfaces/adapters/ll-adapter/IAccount.sol";
import {IAdapter} from "../../../interfaces/adapters/IAdapter.sol";
import {IERC4626Adapter} from "../../../interfaces/adapters/IERC4626Adapter.sol";
import {IEulerAdapter} from "../../../interfaces/adapters/IEulerAdapter.sol";
import {ILiquidLaneAdapter} from "../../../interfaces/adapters/ILiquidLaneAdapter.sol";
import {IMorphoLiquidityAdapter} from "../../../interfaces/adapters/morpho_vaultv2_adapter/IMorphoLiquidityAdapter.sol";
import {IMorphoVaultV2Adapter} from "../../../interfaces/adapters/IMorphoVaultV2Adapter.sol";
import {IMorphoVaultV2} from "../../../interfaces/adapters/morpho_vaultv2_adapter/IMorphoVaultV2.sol";
import {IUniversalDelegator} from "../../../interfaces/delegator/IUniversalDelegator.sol";
import {IVaultV2} from "../../../interfaces/vault/IVaultV2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IMorphoMarketV1ExpectedAssets {
    function expectedSupplyAssets(bytes32 marketId) external view returns (uint256);
}

/// @notice Returns the maximum assets currently fundable by `allocateExact` for 3F and Liquid Lane adapters.
/// @dev Intended for `eth_call`: `sweepPending()` is executed before the calculation.
///      Generic ERC4626 liquidity is not de-duplicated across adapters. Morpho Vault V1 liquidity is
///      pooled per vault, but not against direct exits from its underlying markets.
contract FrontendLiquidityLens {
    using Math for uint256;

    uint256 internal constant AAVE_ACTIVE_MASK = 1 << 56;
    uint256 internal constant AAVE_PAUSED_MASK = 1 << 60;

    struct Source {
        bytes32 key;
        uint256 cash;
    }

    /// @dev `amount` is partially withdrawable unless `exact`; source IDs are 1-based and zero is unshared.
    struct Leg {
        uint256 free;
        uint256 amount;
        bool exact;
        uint256[3] sources;
    }

    function getMaxAssets(address adapter) external returns (uint256) {
        return _getMaxAssets(adapter);
    }

    function getMaxAssets(address adapter, address tokenToRedeem) external returns (uint256) {
        address owner = Ownable(adapter).owner();
        uint256 acquired = ILiquidLaneAdapter(adapter).acquireBalance(tokenToRedeem, owner);
        address marketMaker = ILiquidLaneAdapter(adapter).marketMaker();
        if (marketMaker != owner) {
            acquired += ILiquidLaneAdapter(adapter).acquireBalance(tokenToRedeem, marketMaker);
        }

        uint256 maxAssets = _getMaxAssets(adapter);
        if (maxAssets == 0) return acquired;

        return acquired
            + Math.min(
            maxAssets,
            ILiquidLaneAdapter(adapter).limit(tokenToRedeem)
                .saturatingSub(IAccount(ILiquidLaneAdapter(adapter).accounts(tokenToRedeem)).totalAssets())
        );
    }

    function _getMaxAssets(address adapter) private returns (uint256) {
        address vault = IAdapter(adapter).vault();
        address delegator = IVaultV2(vault).delegator();
        if (IUniversalDelegator(delegator).sweepPending() != 0) return 0;

        uint256 headroom =
            IUniversalDelegator(delegator).limitOf(adapter).saturatingSub(IAdapter(adapter).totalAssets());
        if (headroom == 0) return 0;

        uint256 free = IVaultV2(vault).freeAssets();
        if (free >= headroom) return headroom;
        return free + _maxDeallocatable(delegator, IERC4626(vault).asset(), headroom - free);
    }

    function _maxDeallocatable(address delegator, address asset, uint256 maxAssets) private view returns (uint256) {
        uint256 length = IUniversalDelegator(delegator).getAdaptersLength();
        Leg[] memory legs = new Leg[](length);
        Source[] memory sources = new Source[](3 * length);
        uint256 sourceCount;
        uint256 hi;

        for (uint256 i; i < length; ++i) {
            Leg memory leg;
            Source[3] memory legSources;
            (leg, legSources) = _leg(IUniversalDelegator(delegator).adapters(i), asset);
            for (uint256 j; j < 3; ++j) {
                (leg.sources[j], sourceCount) = _register(sources, sourceCount, legSources[j]);
            }
            legs[i] = leg;
            hi = Math.min(maxAssets, hi.saturatingAdd(leg.free).saturatingAdd(leg.amount));
            if (hi == maxAssets && _coverable(legs, i + 1, sources, sourceCount, maxAssets)) return maxAssets;
        }

        uint256 lo;
        while (lo < hi) {
            uint256 mid = hi - (hi - lo) / 2;
            if (_coverable(legs, length, sources, sourceCount, mid)) lo = mid;
            else hi = mid - 1;
        }
        return lo;
    }

    /// @dev The `try` statements identify adapter types only; reads after a successful getter bubble.
    function _leg(address adapter, address asset)
        internal
        view
        virtual
        returns (Leg memory leg, Source[3] memory sources)
    {
        leg.free = IAdapter(adapter).freeAssets();
        uint256 position = IAdapter(adapter).totalAssets() - leg.free;

        try IMorphoVaultV2Adapter(adapter).morphoVault() returns (address morphoVault) {
            uint256 idle = IERC20(asset).balanceOf(morphoVault);
            address liquidityAdapter = IMorphoVaultV2(morphoVault).liquidityAdapter();
            leg.amount = Math.min(
                position,
                idle.saturatingAdd(
                    liquidityAdapter == address(0) ? 0 : IMorphoLiquidityAdapter(liquidityAdapter).realAssets()
                )
            );
            leg.exact = true;
            sources[0] = Source(keccak256(abi.encode("morphoIdle", morphoVault)), idle);
            if (liquidityAdapter != address(0)) {
                (sources[1], sources[2]) = _morphoSources(morphoVault, liquidityAdapter);
            }
            return (leg, sources);
        } catch {}

        try IAaveV3Adapter(adapter).aToken() returns (address aToken) {
            address pool = IAaveAToken(aToken).POOL();
            uint256 configuration = IAaveV3PoolConfiguration(pool).getConfiguration(asset);
            if (configuration & AAVE_ACTIVE_MASK != 0 && configuration & AAVE_PAUSED_MASK == 0) {
                leg.amount = position;
                sources[0] =
                    Source(keccak256(abi.encode("aave", aToken)), IAaveV3Pool(pool).getVirtualUnderlyingBalance(asset));
            }
            return (leg, sources);
        } catch {}

        try IEulerAdapter(adapter).lendVault() returns (address lendVault) {
            leg.amount = Math.min(position, IERC4626(lendVault).maxWithdraw(adapter));
            if (leg.amount != 0) {
                try IEVaultCash(lendVault).cash() returns (uint256 cash) {
                    sources[0] = Source(keccak256(abi.encode("euler", lendVault)), cash);
                } catch {}
            }
            return (leg, sources);
        } catch {}

        try IERC4626Adapter(adapter).erc4626Vault() returns (address erc4626Vault) {
            leg.amount = Math.min(position, IERC4626(erc4626Vault).maxWithdraw(adapter));
            return (leg, sources);
        } catch {}
    }

    function _register(Source[] memory sources, uint256 count, Source memory source)
        private
        pure
        returns (uint256 id, uint256 newCount)
    {
        if (source.key == bytes32(0)) return (0, count);
        for (uint256 i; i < count; ++i) {
            if (sources[i].key == source.key) {
                sources[i].cash = Math.max(sources[i].cash, source.cash);
                return (i + 1, count);
            }
        }
        sources[count] = source;
        return (count + 1, count + 1);
    }

    function _coverable(Leg[] memory legs, uint256 count, Source[] memory sources, uint256 sourceCount, uint256 target)
        private
        pure
        returns (bool)
    {
        uint256[] memory remaining = new uint256[](sourceCount);
        for (uint256 i; i < sourceCount; ++i) {
            remaining[i] = sources[i].cash;
        }
        for (uint256 i; i < count && target != 0; ++i) {
            target = _deliver(legs[i], remaining, target);
        }
        return target == 0;
    }

    function _deliver(Leg memory leg, uint256[] memory remaining, uint256 unmet) private pure returns (uint256) {
        if (leg.free >= unmet) return 0;

        uint256 need = unmet - leg.free;
        uint256 first = leg.sources[0] == 0 ? type(uint256).max : remaining[leg.sources[0] - 1];
        uint256 second;
        if (leg.sources[1] != 0) {
            second = remaining[leg.sources[1] - 1];
            if (leg.sources[2] != 0) second = Math.min(second, remaining[leg.sources[2] - 1]);
        }

        uint256 available = first.saturatingAdd(second);
        uint256 draw;
        if (leg.exact) {
            uint256 request = Math.min(need, leg.amount);
            draw = request <= available ? request : 0;
        } else {
            draw = Math.min(need, Math.min(leg.amount, available));
        }

        uint256 fromFirst = Math.min(draw, first);
        if (leg.sources[0] != 0) remaining[leg.sources[0] - 1] -= fromFirst;
        if (draw > fromFirst) {
            remaining[leg.sources[1] - 1] -= draw - fromFirst;
            if (leg.sources[2] != 0) remaining[leg.sources[2] - 1] -= draw - fromFirst;
        }
        return need - draw;
    }

    function _morphoSources(address morphoVault, address liquidityAdapter)
        private
        view
        returns (Source memory route, Source memory position)
    {
        try IMorphoMarketV1Adapter(liquidityAdapter).morpho() returns (address morpho) {
            bytes memory liquidityData = IMorphoVaultV2(morphoVault).liquidityData();
            if (liquidityData.length == 0) return (route, position);

            MorphoMarketParams memory marketParams = abi.decode(liquidityData, (MorphoMarketParams));
            bytes32 marketId = keccak256(abi.encode(marketParams));
            uint256 assets;
            try IMorphoMarketV1ExpectedAssets(liquidityAdapter).expectedSupplyAssets(marketId) returns (
                uint256 expectedAssets
            ) {
                assets = expectedAssets;
            } catch {
                return (route, position);
            }
            if (assets == 0) return (route, position);

            MorphoMarket memory market = IMorphoBlue(morpho).market(marketId);
            route = Source(
                keccak256(abi.encode("morphoMarket", morpho, marketId)),
                Math.min(
                    uint256(market.totalSupplyAssets).saturatingSub(market.totalBorrowAssets),
                    IERC20(marketParams.loanToken).balanceOf(morpho)
                )
            );
            position = Source(keccak256(abi.encode("morphoLiquidityAdapter", liquidityAdapter)), assets);
            return (route, position);
        } catch {}

        try IMorphoVaultV1Adapter(liquidityAdapter).morphoVaultV1() returns (address morphoVaultV1) {
            try IMorphoVaultV2(morphoVaultV1).liquidityAdapter() returns (address) {
                return (route, position);
            } catch {
                uint256 assets = IERC4626(morphoVaultV1).maxWithdraw(liquidityAdapter);
                route = Source(keccak256(abi.encode("morphoVaultV1", morphoVaultV1)), assets);
                position = Source(keccak256(abi.encode("morphoLiquidityAdapter", liquidityAdapter)), assets);
            }
        } catch {}
    }
}
