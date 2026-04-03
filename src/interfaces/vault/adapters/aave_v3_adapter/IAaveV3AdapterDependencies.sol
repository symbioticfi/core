// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

struct AaveV3ReserveConfigurationMap {
    uint256 data;
}

struct AaveV3ReserveData {
    AaveV3ReserveConfigurationMap configuration;
    uint128 liquidityIndex;
    uint128 currentLiquidityRate;
    uint128 variableBorrowIndex;
    uint128 currentVariableBorrowRate;
    uint128 currentStableBorrowRate;
    uint40 lastUpdateTimestamp;
    uint16 id;
    address aTokenAddress;
    address stableDebtTokenAddress;
    address variableDebtTokenAddress;
    address interestRateStrategyAddress;
    uint128 accruedToTreasury;
    uint128 unbacked;
    uint128 isolationModeTotalDebt;
}

/**
 * @title IAaveV3Pool
 * @notice Minimal Aave V3 pool interface used by the adapter.
 */
interface IAaveV3Pool {
    /**
     * @notice Returns reserve data for an asset.
     * @param asset Asset address.
     * @return reserveData Reserve data.
     */
    function getReserveData(address asset) external view returns (AaveV3ReserveData memory reserveData);

    /**
     * @notice Supplies assets to Aave.
     * @param asset Asset address.
     * @param amount Asset amount.
     * @param onBehalfOf Receiver of the position.
     * @param referralCode Referral code.
     */
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    /**
     * @notice Withdraws assets from Aave.
     * @param asset Asset address.
     * @param amount Asset amount.
     * @param to Recipient of withdrawn assets.
     * @return withdrawn Withdrawn amount.
     */
    function withdraw(address asset, uint256 amount, address to) external returns (uint256 withdrawn);
}

/**
 * @title IAaveV3AToken
 * @notice Minimal Aave V3 aToken interface used by the adapter.
 */
interface IAaveV3AToken is IERC20 {
    /**
     * @notice Returns the underlying asset for the aToken.
     * @return asset Underlying asset address.
     */
    function UNDERLYING_ASSET_ADDRESS() external view returns (address asset);
}
