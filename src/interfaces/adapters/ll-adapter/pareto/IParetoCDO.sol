// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IParetoCDO
 * @notice Interface for Pareto credit vault withdrawal requests.
 */
interface IParetoCDO {
    /* FUNCTIONS */

    /**
     * @notice Claims an eligible normal withdrawal request.
     */
    function claimWithdrawRequest() external;

    /**
     * @notice Requests a normal tranche withdrawal.
     * @param amount The tranche token amount.
     * @param tranche The tranche token.
     * @return assets The underlying amount requested.
     */
    function requestWithdraw(uint256 amount, address tranche) external returns (uint256 assets);

    /**
     * @notice Returns the withdrawal receipt token.
     * @return receiptToken The receipt token address.
     */
    function strategy() external view returns (address receiptToken);

    /**
     * @notice Returns the underlying token.
     * @return underlying The underlying token address.
     */
    function token() external view returns (address underlying);

    /**
     * @notice Returns the tranche virtual price in underlying units per tranche unit.
     * @param tranche The tranche token.
     * @return price The tranche virtual price.
     */
    function virtualPrice(address tranche) external view returns (uint256 price);
}
