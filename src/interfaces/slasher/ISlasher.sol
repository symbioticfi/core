// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

interface ISlasher {
    error InsufficientSlash();
    error InvalidCaptureTimestamp();

    struct SlashHints {
        bytes optInHints;
        bytes slashableStakeHints;
        bytes onSlashHints;
    }

    /**
     * @notice Emitted when a slash is performed.
     * @param network network that requested the slash
     * @param operator operator that is slashed
     * @param slashedAmount amount of the collateral slashed
     * @param captureTimestamp time point when the stake was captured
     */
    event Slash(address indexed network, address indexed operator, uint256 slashedAmount, uint48 captureTimestamp);

    /**
     * @notice Perform a slash using a network for a particular operator by a given amount using hints.
     * @param network address of the network
     * @param operator address of the operator
     * @param amount maximum amount of the collateral to be slashed
     * @param captureTimestamp time point when the stake was captured
     * @param hints hints for checkpoints' indexes
     * @return slashedAmount amount of the collateral slashed
     * @dev Only a network middleware can call this function.
     */
    function slash(
        address network,
        address operator,
        uint256 amount,
        uint48 captureTimestamp,
        bytes memory hints
    ) external returns (uint256 slashedAmount);
}
