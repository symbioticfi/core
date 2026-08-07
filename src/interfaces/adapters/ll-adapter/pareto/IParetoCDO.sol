// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IParetoCDO
 * @notice Interface for Pareto CDO topology, eligibility, and tranche pricing.
 */
interface IParetoCDO {
    /**
     * @notice Returns the AA tranche token.
     * @return tranche The AA tranche address.
     */
    function AATranche() external view returns (address tranche);

    /**
     * @notice Claims a ready normal withdrawal receipt for the caller.
     */
    function claimWithdrawRequest() external;

    /**
     * @notice Claims a ready instant withdrawal receipt for the caller.
     */
    function claimInstantWithdrawRequest() external;

    /**
     * @notice Returns whether the CDO has defaulted.
     * @return isDefaulted Whether the CDO has defaulted.
     */
    function defaulted() external view returns (bool isDefaulted);

    /**
     * @notice Returns whether an epoch is currently running.
     * @return running Whether the epoch is running.
     */
    function isEpochRunning() external view returns (bool running);

    /**
     * @notice Returns whether an account satisfies the configured Keyring policy.
     * @param account The account to check.
     * @return allowed Whether the account is allowed.
     */
    function isWalletAllowed(address account) external view returns (bool allowed);

    /**
     * @notice Returns the configured Keyring contract.
     * @return keyringAddress The Keyring address.
     */
    function keyring() external view returns (address keyringAddress);

    /**
     * @notice Returns the configured Keyring policy.
     * @return policy The Keyring policy identifier.
     */
    function keyringPolicyId() external view returns (uint256 policy);

    /**
     * @notice Returns the underlying-token unit used by the CDO.
     * @return unit The underlying unit.
     */
    function oneToken() external view returns (uint256 unit);

    /**
     * @notice Returns the tranche-token unit used by the CDO.
     * @return unit The tranche unit.
     */
    function ONE_TRANCHE_TOKEN() external view returns (uint256 unit);

    /**
     * @notice Submits tranche tokens for withdrawal directly through the CDO.
     * @param amount The tranche-token amount.
     * @param tranche The tranche token to withdraw.
     * @return assets The underlying amount represented by the withdrawal receipt.
     */
    function requestWithdraw(uint256 amount, address tranche) external returns (uint256 assets);

    /**
     * @notice Returns the withdrawal receipt token.
     * @return receiptToken The receipt token address.
     */
    function strategy() external view returns (address receiptToken);

    /**
     * @notice Returns the withdrawal receipt token configured by the CDO.
     * @return receiptToken The receipt-token address.
     */
    function strategyToken() external view returns (address receiptToken);

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
