// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IOracle} from "../IOracle.sol";

/**
 * @title IAsyncRedeemOracle
 * @notice Interface for ERC-7540 async redeem vault share-price oracles.
 */
interface IAsyncRedeemOracle is IOracle {
    /* FUNCTIONS */

    /**
     * @notice Returns the async redeem vault used as the price source.
     * @return vault The async redeem vault address.
     */
    function ASYNC_REDEEM_VAULT() external view returns (address vault);
}
