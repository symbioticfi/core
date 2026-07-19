// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IParetoCreditVault
 * @notice Interface for Pareto credit-vault topology and epoch state.
 */
interface IParetoCreditVault {
    /**
     * @notice Returns the CDO that owns the credit vault.
     * @return idleCdo The CDO address.
     */
    function idleCDO() external view returns (address idleCdo);

    /**
     * @notice Returns the current strategy epoch.
     * @return epoch The current epoch number.
     */
    function epochNumber() external view returns (uint256 epoch);

    /**
     * @notice Returns the credit-vault underlying token.
     * @return underlying The underlying token address.
     */
    function token() external view returns (address underlying);
}
