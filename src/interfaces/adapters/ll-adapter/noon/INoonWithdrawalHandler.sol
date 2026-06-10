// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title INoonWithdrawalHandler
 * @notice Interface for Noon sUSN withdrawal requests.
 */
interface INoonWithdrawalHandler {
    /* STRUCTS */

    /**
     * @notice Noon withdrawal request data.
     * @param amount The requested USN amount.
     * @param timestamp The request timestamp.
     * @param claimed Whether the request has been claimed.
     */
    struct WithdrawalRequest {
        uint256 amount;
        uint256 timestamp;
        bool claimed;
    }

    /* FUNCTIONS */

    /**
     * @notice Claims a matured withdrawal request.
     * @param requestId The request id.
     */
    function claimWithdrawal(uint256 requestId) external;

    /**
     * @notice Returns a user's next withdrawal request id.
     * @param user The request owner.
     * @return requestId The next request id.
     */
    function getUserNextRequestId(address user) external view returns (uint256 requestId);

    /**
     * @notice Returns a withdrawal request.
     * @param user The request owner.
     * @param requestId The request id.
     * @return request The withdrawal request.
     */
    function getWithdrawalRequest(address user, uint256 requestId)
        external
        view
        returns (WithdrawalRequest memory request);

    /**
     * @notice Returns the USN token paid out by withdrawals.
     * @return token The USN token.
     */
    function usn() external view returns (address token);

    /**
     * @notice Returns the withdrawal waiting period.
     * @return period The withdrawal period.
     */
    function withdrawPeriod() external view returns (uint256 period);
}
