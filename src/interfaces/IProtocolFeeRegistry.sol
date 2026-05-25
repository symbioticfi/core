// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

uint256 constant MAX_PROTOCOL_FEE = 25e16; // 25%

interface IProtocolFeeRegistry {
    /* ERRORS */

    /**
     * @notice Raised when a configured protocol fee exceeds MAX_PROTOCOL_FEE.
     */
    error FeeTooHigh();

    /**
     * @notice Raised when the global receiver is the zero address.
     */
    error InvalidReceiver();

    /* EVENTS */

    /**
     * @notice Emitted when the global protocol fee is set.
     * @param fee Global protocol fee scaled by MAX_FEE.
     */
    event SetGlobalFee(uint256 fee);

    /**
     * @notice Emitted when a vault-specific protocol fee is set.
     * @param vault Vault address.
     * @param fee Vault-specific protocol fee scaled by MAX_FEE.
     */
    event SetVaultFee(address indexed vault, uint256 fee);

    /**
     * @notice Emitted when the global protocol fee receiver is set.
     * @param receiver Global protocol fee receiver.
     */
    event SetGlobalReceiver(address indexed receiver);

    /**
     * @notice Emitted when a vault-specific protocol fee receiver is set.
     * @param vault Vault address.
     * @param receiver Vault-specific protocol fee receiver.
     */
    event SetVaultReceiver(address indexed vault, address indexed receiver);

    /* FUNCTIONS */

    /**
     * @notice Get the global protocol fee.
     * @return fee Global protocol fee scaled by MAX_FEE.
     */
    function globalFee() external view returns (uint256 fee);

    /**
     * @notice Get a vault-specific protocol fee.
     * @param vault Vault address.
     * @return fee Vault-specific protocol fee scaled by MAX_FEE.
     */
    function vaultFee(address vault) external view returns (uint256 fee);

    /**
     * @notice Get the global protocol fee receiver.
     * @return receiver Global protocol fee receiver.
     */
    function globalReceiver() external view returns (address receiver);

    /**
     * @notice Get a vault-specific protocol fee receiver.
     * @param vault Vault address.
     * @return receiver Vault-specific protocol fee receiver.
     */
    function vaultReceiver(address vault) external view returns (address receiver);

    /**
     * @notice Set the global protocol fee.
     * @param newGlobalFee New global protocol fee scaled by MAX_FEE.
     */
    function setGlobalFee(uint256 newGlobalFee) external;

    /**
     * @notice Set a vault-specific protocol fee.
     * @param vault Vault address.
     * @param isEnabled Whether the vault-specific protocol fee override is enabled.
     * @param newVaultFee New vault-specific protocol fee scaled by MAX_FEE.
     */
    function setVaultFee(address vault, bool isEnabled, uint256 newVaultFee) external;

    /**
     * @notice Set the global protocol fee receiver.
     * @param newGlobalReceiver New global protocol fee receiver.
     */
    function setGlobalReceiver(address newGlobalReceiver) external;

    /**
     * @notice Set a vault-specific protocol fee receiver.
     * @param vault Vault address.
     * @param newVaultReceiver New vault-specific protocol fee receiver.
     */
    function setVaultReceiver(address vault, address newVaultReceiver) external;

    /**
     * @notice Get the protocol fee for a vault.
     * @param vault Vault address.
     * @return fee Protocol fee scaled by MAX_FEE.
     */
    function getFee(address vault) external view returns (uint256 fee);

    /**
     * @notice Get the protocol fee receiver for a vault.
     * @param vault Vault address.
     * @return receiver Protocol fee receiver.
     */
    function getReceiver(address vault) external view returns (address receiver);
}
