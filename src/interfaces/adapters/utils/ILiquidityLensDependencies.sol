// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IAaveAToken
 * @notice Minimal Aave aToken interface.
 */
interface IAaveAToken {
    /**
     * @notice Returns the Aave pool.
     * @return pool Pool address.
     */
    // solhint-disable-next-line func-name-mixedcase
    function POOL() external view returns (address pool);
}

/**
 * @title IAaveV3PoolConfiguration
 * @notice Minimal Aave V3 pool configuration interface.
 */
interface IAaveV3PoolConfiguration {
    /**
     * @notice Returns the packed reserve configuration.
     * @param asset Reserve asset.
     * @return data Packed configuration bitmap.
     */
    function getConfiguration(address asset) external view returns (uint256 data);
}

/**
 * @title IMorphoMarketV1Adapter
 * @notice Minimal Morpho market V1 adapter interface.
 */
interface IMorphoMarketV1Adapter {
    /**
     * @notice Returns the Morpho Blue core.
     * @return morpho Morpho Blue address.
     */
    function morpho() external view returns (address morpho);

    /**
     * @notice Returns the adapter supply shares in a market.
     * @param marketId Market id.
     * @return shares Supply shares.
     */
    function supplyShares(bytes32 marketId) external view returns (uint256 shares);
}

/**
 * @title IMorphoVaultV1Adapter
 * @notice Minimal Morpho vault V1 adapter interface.
 */
interface IMorphoVaultV1Adapter {
    /**
     * @notice Returns the wrapped Morpho vault V1.
     * @return morphoVaultV1 Morpho vault V1 address.
     */
    function morphoVaultV1() external view returns (address morphoVaultV1);
}

/**
 * @notice Morpho Blue market params.
 * @param loanToken Loan token.
 * @param collateralToken Collateral token.
 * @param oracle Oracle.
 * @param irm Interest rate model.
 * @param lltv Liquidation LTV.
 */
struct MorphoMarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}

/**
 * @notice Morpho Blue market state.
 * @param totalSupplyAssets Total supply assets.
 * @param totalSupplyShares Total supply shares.
 * @param totalBorrowAssets Total borrow assets.
 * @param totalBorrowShares Total borrow shares.
 * @param lastUpdate Last accrual timestamp.
 * @param fee Market fee.
 */
struct MorphoMarket {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
}

/**
 * @title IMorphoBlue
 * @notice Minimal Morpho Blue core interface.
 */
interface IMorphoBlue {
    /**
     * @notice Returns the stored market state.
     * @param marketId Market id.
     * @return market Market state.
     */
    function market(bytes32 marketId) external view returns (MorphoMarket memory market);
}

/**
 * @title IMorphoIrm
 * @notice Minimal Morpho interest rate model interface.
 */
interface IMorphoIrm {
    /**
     * @notice Returns the current per-second borrow rate without state changes.
     * @param marketParams Market params.
     * @param market Market state.
     * @return rate Per-second borrow rate (WAD).
     */
    function borrowRateView(MorphoMarketParams memory marketParams, MorphoMarket memory market)
        external
        view
        returns (uint256 rate);
}

/**
 * @title IEVaultCash
 * @notice Minimal Euler EVK vault interface exposing the tracked cash balance.
 */
interface IEVaultCash {
    /**
     * @notice Returns the vault's tracked cash (assets available for withdrawal).
     * @return assets Cash assets.
     */
    function cash() external view returns (uint256 assets);
}

/**
 * @notice Per-adapter instant-liquidity decomposition for the deallocation cascade.
 * @param free Idle assets the adapter always delivers, independent of any shared source.
 * @param position Cap on the adapter's total source withdrawal (its own position).
 * @param clamp Requested-amount cap for all-or-nothing legs (unused for partial-fill legs).
 * @param allOrNothing Whether the source delivers the full clamped request or nothing (Morpho) rather
 *        than partial-filling (everything else).
 * @param key1 First source key, consumed first (zero means a private, unbounded source).
 * @param cash1 First source total instant cash.
 * @param key2 Second source key, consumed after the first (zero means no second source).
 * @param cash2 Second source total instant cash.
 * @param key3 Pool consumed in lockstep with the second source (zero means unbounded).
 * @param cash3 Lockstep pool total instant cash.
 * @dev Pools with the same key across adapters share one balance, so the cascade cannot withdraw the
 *      shared cash more than once (e.g. two vaults exiting the same Morpho market). A second-source
 *      draw decrements the `key2` and `key3` pools together: a forced Morpho market exit spends the
 *      market's cash and the liquidity adapter's own position in lockstep.
 */
struct SourceLiquidity {
    uint256 free;
    uint256 position;
    uint256 clamp;
    bool allOrNothing;
    bytes32 key1;
    uint256 cash1;
    bytes32 key2;
    uint256 cash2;
    bytes32 key3;
    uint256 cash3;
}
