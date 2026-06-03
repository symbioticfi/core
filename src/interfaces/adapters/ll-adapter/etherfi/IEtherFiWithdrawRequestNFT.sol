// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IEtherFiWithdrawRequestNFT
 * @notice Minimal ether.fi withdrawal request NFT interface used by weETH accounts.
 */
interface IEtherFiWithdrawRequestNFT {
    /**
     * @notice Claims an ether.fi withdrawal request.
     * @param requestId The withdrawal request id.
     */
    function claimWithdraw(uint256 requestId) external;
}
