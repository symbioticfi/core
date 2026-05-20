// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

uint256 constant MAX_FEE = 1_000_000;

interface IFeeRegistry {
    /**
     * @notice Get the management fee for a vault.
     * @param vault Vault address.
     * @return fee Management fee per second in WAD.
     */
    function getManagementFee(address vault) external view returns (uint256 fee);

    /**
     * @notice Get the management fee recipient for a vault.
     * @param vault Vault address.
     * @return recipient Management fee recipient.
     */
    function getManagementFeeRecipient(address vault) external view returns (address recipient);

    /**
     * @notice Get the performance fee for a vault.
     * @param vault Vault address.
     * @return fee Performance fee in WAD.
     */
    function getPerformanceFee(address vault) external view returns (uint256 fee);

    /**
     * @notice Get the performance fee recipient for a vault.
     * @param vault Vault address.
     * @return recipient Performance fee recipient.
     */
    function getPerformanceFeeRecipient(address vault) external view returns (address recipient);

    function getInstantWithdrawFee(address vault) external view returns (uint256 fee);
}
