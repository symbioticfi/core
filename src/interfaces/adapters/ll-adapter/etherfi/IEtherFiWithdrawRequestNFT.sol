// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IEtherFiWithdrawRequestNFT
 * @notice Minimal ether.fi withdrawal request NFT interface used by weETH accounts.
 */
interface IEtherFiWithdrawRequestNFT {
    /**
     * @notice ether.fi withdrawal request data.
     * @param amountOfEEth The eETH amount requested.
     * @param shareOfEEth The eETH share amount requested.
     * @param isValid True if the request is valid.
     * @param feeGwei The request fee in gwei.
     */
    struct WithdrawRequest {
        uint96 amountOfEEth;
        uint96 shareOfEEth;
        bool isValid;
        uint32 feeGwei;
    }

    /**
     * @notice Claims an ether.fi withdrawal request.
     * @param requestId The withdrawal request id.
     */
    function claimWithdraw(uint256 requestId) external;

    /**
     * @notice Returns withdrawal request data.
     * @param requestId The withdrawal request id.
     * @return request The withdrawal request data.
     */
    function getRequest(uint256 requestId) external view returns (WithdrawRequest memory request);
}
