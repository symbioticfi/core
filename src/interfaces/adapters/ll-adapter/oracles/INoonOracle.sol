// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "../IOracle.sol";

/**
 * @title INoonOracle
 * @notice Interface for Noon rate-provider oracle adapters.
 */
interface INoonOracle is IOracle {
    /* FUNCTIONS */

    /**
     * @notice Returns the Noon rate provider.
     * @return rateProvider The rate-provider address.
     */
    function RATE_PROVIDER() external view returns (address rateProvider);

    /**
     * @notice Returns the token priced by the oracle.
     * @return token The base-token address.
     */
    function TOKEN_TO_REDEEM() external view returns (address token);

    /**
     * @notice Returns the quote token used by the rate provider.
     * @return token The quote-token address.
     */
    function QUOTE_TOKEN() external view returns (address token);
}
