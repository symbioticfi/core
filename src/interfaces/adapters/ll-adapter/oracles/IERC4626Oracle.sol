// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "../IOracle.sol";

/**
 * @title IERC4626Oracle
 * @notice Interface for ERC-4626 conversion oracle adapters.
 */
interface IERC4626Oracle is IOracle {
    /* FUNCTIONS */

    /**
     * @notice Returns the ERC-4626 vault used as the price source.
     * @return vault The vault address.
     */
    function VAULT() external view returns (address vault);
}
