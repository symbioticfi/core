// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "../IOracle.sol";

/**
 * @title IParetoOracle
 * @notice Interface for Pareto tranche virtual-price oracles.
 */
interface IParetoOracle is IOracle {
    /**
     * @notice Raised when the configured token is not a tranche of the CDO.
     */
    error InvalidTranche();

    /**
     * @notice Returns the Pareto CDO.
     * @return idleCdo The CDO address.
     */
    function IDLE_CDO() external view returns (address idleCdo);

    /**
     * @notice Returns the tranche token priced by the oracle.
     * @return tokenToRedeem The tranche-token address.
     */
    function TOKEN_TO_REDEEM() external view returns (address tokenToRedeem);
}
