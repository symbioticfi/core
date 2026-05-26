// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IProtocolFeeRegistry {
    /* ERRORS */

    /**
     * @notice Raised when a configured protocol fee exceeds its maximum.
     */
    error FeeTooHigh();

    /**
     * @notice Raised when the global receiver is the zero address.
     */
    error InvalidReceiver();

    /* STRUCTS */

    struct Fee {
        bool isEnabled;
        address receiver;
        uint96 managementFee;
        uint96 performanceFee;
    }

    /* EVENTS */

    /**
     * @notice Emitted when global protocol fees are set.
     * @param managementFee Global protocol management fee per second scaled by MAX_FEE.
     * @param performanceFee Global protocol performance fee scaled by MAX_FEE.
     */
    event SetGlobalFee(uint256 managementFee, uint256 performanceFee);

    /**
     * @notice Emitted when a vault-specific protocol fee override is set.
     * @param vault Vault address.
     * @param isEnabled Whether the vault-specific protocol fee override is enabled.
     * @param receiver Vault-specific protocol fee receiver.
     * @param managementFee Vault-specific protocol management fee per second scaled by MAX_FEE.
     * @param performanceFee Vault-specific protocol performance fee scaled by MAX_FEE.
     */
    event SetVaultFee(
        address indexed vault, bool isEnabled, address indexed receiver, uint256 managementFee, uint256 performanceFee
    );

    /**
     * @notice Emitted when the global protocol fee receiver is set.
     * @param receiver Global protocol fee receiver.
     */
    event SetGlobalReceiver(address indexed receiver);

    /* FUNCTIONS */

    /**
     * @notice Get the global protocol management fee.
     * @return fee Global protocol management fee per second scaled by MAX_FEE.
     */
    function globalManagementFee() external view returns (uint96 fee);

    /**
     * @notice Get the global protocol performance fee.
     * @return fee Global protocol performance fee scaled by MAX_FEE.
     */
    function globalPerformanceFee() external view returns (uint96 fee);

    /**
     * @notice Get a vault-specific protocol fee override.
     * @param vault Vault address.
     * @return isEnabled Whether the vault-specific override is enabled.
     * @return receiver Vault-specific protocol fee receiver.
     * @return managementFee Vault-specific protocol management fee per second scaled by MAX_FEE.
     * @return performanceFee Vault-specific protocol performance fee scaled by MAX_FEE.
     */
    function vaultFee(address vault)
        external
        view
        returns (bool isEnabled, address receiver, uint96 managementFee, uint96 performanceFee);

    /**
     * @notice Get the global protocol fee receiver.
     * @return receiver Global protocol fee receiver.
     */
    function globalReceiver() external view returns (address receiver);

    /**
     * @notice Set global protocol fees.
     * @param newGlobalManagementFee New global protocol management fee per second scaled by MAX_FEE.
     * @param newGlobalPerformanceFee New global protocol performance fee scaled by MAX_FEE.
     */
    function setGlobalFee(uint96 newGlobalManagementFee, uint96 newGlobalPerformanceFee) external;

    /**
     * @notice Set a vault-specific protocol fee override.
     * @param vault Vault address.
     * @param isEnabled Whether the vault-specific protocol fee override is enabled.
     * @param newVaultReceiver New vault-specific protocol fee receiver.
     * @param newVaultManagementFee New vault-specific protocol management fee per second scaled by MAX_FEE.
     * @param newVaultPerformanceFee New vault-specific protocol performance fee scaled by MAX_FEE.
     */
    function setVaultFee(
        address vault,
        bool isEnabled,
        address newVaultReceiver,
        uint96 newVaultManagementFee,
        uint96 newVaultPerformanceFee
    ) external;

    /**
     * @notice Set the global protocol fee receiver.
     * @param newGlobalReceiver New global protocol fee receiver.
     */
    function setGlobalReceiver(address newGlobalReceiver) external;

    /**
     * @notice Get the protocol fee receiver and fees for a vault.
     * @param vault Vault address.
     * @return receiver Protocol fee receiver.
     * @return managementFee Protocol management fee per second scaled by MAX_FEE.
     * @return performanceFee Protocol performance fee scaled by MAX_FEE.
     */
    function getFee(address vault) external view returns (address receiver, uint96 managementFee, uint96 performanceFee);
}
