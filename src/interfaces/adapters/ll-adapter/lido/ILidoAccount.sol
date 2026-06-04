// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ILidoAccount
 * @notice Interface for Lido liquidity lane accounts.
 */
interface ILidoAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the Lido withdrawal queue address.
     * @return queue The withdrawal queue address.
     */
    function WITHDRAWAL_QUEUE() external view returns (address queue);

    /**
     * @notice Returns the wstETH token address.
     * @return wstETH The wstETH token address.
     */
    function WSTETH() external view returns (address wstETH);

    /**
     * @notice Returns the stETH token address.
     * @return stETH The stETH token address.
     */
    function STETH() external view returns (address stETH);

    /**
     * @notice Returns pending requested-withdrawal value in vault assets.
     * @return assets The pending vault-asset value.
     */
    function pendingAssets() external view returns (uint256 assets);

    /**
     * @notice Receives ETH from Lido withdrawal claims.
     */
    receive() external payable;
}
