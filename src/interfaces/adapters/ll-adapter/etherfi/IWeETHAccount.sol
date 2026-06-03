// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IWeETHAccount
 * @notice Interface for weETH liquidity lane accounts.
 */
interface IWeETHAccount {
    /* FUNCTIONS */

    /**
     * @notice Returns the eETH token address.
     * @return eETH The eETH token address.
     */
    function EETH() external view returns (address eETH);

    /**
     * @notice Returns the WETH token address.
     * @return weth The WETH token address.
     */
    function WETH() external view returns (address weth);

    /**
     * @notice Returns the stETH token address.
     * @return stETH The stETH token address.
     */
    function STETH() external view returns (address stETH);

    /**
     * @notice Returns the wstETH token address.
     * @return wstETH The wstETH token address.
     */
    function WSTETH() external view returns (address wstETH);

    /**
     * @notice Returns the ether.fi liquidity pool address.
     * @return liquidityPool The liquidity pool address.
     */
    function LIQUIDITY_POOL() external view returns (address liquidityPool);

    /**
     * @notice Returns the ether.fi redemption manager address.
     * @return redemptionManager The redemption manager address.
     */
    function REDEMPTION_MANAGER() external view returns (address redemptionManager);

    /**
     * @notice Returns the ether.fi withdraw request NFT address.
     * @return withdrawRequestNft The withdraw request NFT address.
     */
    function WITHDRAW_REQUEST_NFT() external view returns (address withdrawRequestNft);

    /**
     * @notice Returns pending requested-withdrawal value in vault assets.
     * @return assets The pending vault-asset value.
     */
    function pendingAssets() external view returns (uint256 assets);

    /**
     * @notice Claims an ether.fi withdrawal request and wraps received ETH into WETH.
     * @param requestId The withdrawal request id.
     */
    function claimWithdraw(uint256 requestId) external;

    /**
     * @notice Receives ETH from ether.fi withdrawal claims.
     */
    receive() external payable;
}
