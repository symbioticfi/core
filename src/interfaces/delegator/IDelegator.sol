// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IDelegator
 * @notice Common vault hook interface implemented by VaultV2 delegators.
 */
interface IDelegator {
    /**
     * @notice Emitted when vault deposit accounting is handled by the delegator.
     * @param caller Account that supplied the collateral to the vault.
     * @param receiver Account that received vault shares.
     * @param assets Amount of collateral deposited.
     * @param shares Amount of vault shares minted.
     */
    event OnDeposit(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);

    /**
     * @notice Emitted when vault withdrawal request accounting is handled by the delegator.
     * @param caller Account that requested the withdrawal.
     * @param receiver Account that received the withdrawal request.
     * @param assets Amount of collateral requested.
     * @param shares Amount of vault shares requested.
     */
    event OnRequestWithdraw(address indexed caller, address indexed receiver, uint256 assets, uint256 shares);

    /**
     * @notice Emitted when vault withdrawal accounting is handled by the delegator.
     * @param caller Account that initiated the withdrawal.
     * @param receiver Account that received the collateral.
     * @param owner Account that owned the burned vault shares.
     * @param assets Amount of collateral withdrawn.
     * @param shares Amount of vault shares burned.
     */
    event OnWithdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /**
     * @notice Get the associated vault address.
     * @return vaultAddress Address of the vault.
     */
    function vault() external view returns (address vaultAddress);

    /**
     * @notice Get total assets observed by the delegator for vault accounting.
     * @return assets Total assets.
     */
    function totalAssets() external view returns (uint256 assets);

    /**
     * @notice Handle a vault deposit.
     * @param caller Account that supplied the collateral to the vault.
     * @param receiver Account that received vault shares.
     * @param assets Amount of collateral deposited.
     * @param shares Amount of vault shares minted.
     * @dev Only the vault can call this function.
     */
    function onDeposit(address caller, address receiver, uint256 assets, uint256 shares) external;

    /**
     * @notice Handle a vault withdrawal request.
     * @param caller Account that requested the withdrawal.
     * @param receiver Account that received the withdrawal request.
     * @param assets Amount of collateral requested.
     * @param shares Amount of vault shares requested.
     * @dev Only the vault's withdrawal queue can call this function.
     */
    function onRequestWithdraw(address caller, address receiver, uint256 assets, uint256 shares) external;

    /**
     * @notice Handle a vault withdrawal.
     * @param caller Account that initiated the withdrawal.
     * @param receiver Account that received the collateral.
     * @param owner Account that owned the burned vault shares.
     * @param assets Amount of collateral withdrawn.
     * @param shares Amount of vault shares burned.
     * @dev Only the vault can call this function.
     */
    function onWithdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares) external;
}
