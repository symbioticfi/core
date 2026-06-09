// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IAccount} from "../IAccount.sol";

/**
 * @title IEtherFiAccount
 * @notice Interface for ether.fi liquidity lane accounts.
 */
interface IEtherFiAccount is IAccount {
    /* ERRORS */

    /**
     * @notice Raised when an instant redemption produced no expected output token.
     */
    error InstantRedemptionUnavailable();

    /**
     * @notice Raised when the vault asset is not WETH.
     */
    error InvalidAsset();

    /* FUNCTIONS */

    /**
     * @notice Returns the ether.fi withdraw request NFT address.
     * @return withdrawRequestNft The withdraw request NFT address.
     */
    function WITHDRAW_REQUEST_NFT() external view returns (address withdrawRequestNft);

    /**
     * @notice Returns the ether.fi redemption manager address.
     * @return redemptionManager The redemption manager address.
     */
    function REDEMPTION_MANAGER() external view returns (address redemptionManager);

    /**
     * @notice Returns the ether.fi liquidity pool address.
     * @return liquidityPool The liquidity pool address.
     */
    function LIQUIDITY_POOL() external view returns (address liquidityPool);

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
     * @notice Returns pending requested-withdrawal value in vault assets.
     * @return assets The pending vault-asset value.
     */
    function pendingAssets() external view returns (uint256 assets);

    /**
     * @notice Returns an ether.fi withdrawal request id by index.
     * @param index The request index.
     * @return requestId The withdrawal request id.
     */
    function requestIds(uint256 index) external view returns (uint64 requestId);

    /**
     * @notice Claims an ether.fi withdrawal request and wraps received ETH into WETH.
     * @param requestId The withdrawal request id.
     */
    function claimWithdraw(uint256 requestId) external;

    /**
     * @notice Accepts ether.fi withdrawal request NFTs.
     * @return selector The ERC721 receiver selector.
     */
    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4 selector);

    /**
     * @notice Receives ETH from ether.fi withdrawal claims.
     */
    receive() external payable;
}
