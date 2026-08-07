// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ISpikoRedemption
 * @notice Interface for Spiko's ERC-1363 redemption manager.
 */
interface ISpikoRedemption {
    /**
     * @notice Redemption request lifecycle state.
     */
    enum Status {
        NULL,
        PENDING,
        EXECUTED,
        CANCELED
    }

    /**
     * @notice Returns the authorized settlement outputs for an input token.
     * @param input The Spiko share token.
     * @return outputs Authorized fiat/stablecoin output identifiers.
     */
    function outputsFor(IERC20 input) external view returns (address[] memory outputs);

    /**
     * @notice Returns the minimum redeemable input amount.
     * @param input The Spiko share token.
     * @return amount Minimum token amount.
     */
    function minimum(IERC20 input) external view returns (uint256 amount);

    /**
     * @notice Returns the state and cancellation deadline of a request.
     * @param id The redemption request id.
     * @return status Current request status.
     * @return deadline Timestamp after which a pending request can be canceled.
     */
    function details(bytes32 id) external view returns (Status status, uint48 deadline);

    /**
     * @notice Cancels an issuer-expired request and returns its input tokens.
     */
    function cancelRedemption(address user, IERC20 input, address output, uint256 inputValue, bytes32 salt) external;
}
