// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface IBaseSlasher {
    error NotNetworkMiddleware();
    error NotVault();
    error OutdatedCaptureTimestamp();

    /**
     * @notice Hints for a slashable stake.
     * @param stakeHints hints for the stake checkpoints
     * @param cumulativeSlashFromHint hint for the cumulative slash amount at "from" timestamp
     */
    struct SlashableStakeHints {
        bytes stakeHints;
        bytes cumulativeSlashFromHint;
    }

    /**
     * @notice Hints for on slash actions.
     * @param delegatorOnSlashHints hints for the delegator's on-slash action
     */
    struct OnSlashHints {
        bytes delegatorOnSlashHints;
    }

    /**
     * @notice Get the vault factory's address.
     * @return address of the vault factory
     */
    function VAULT_FACTORY() external view returns (address);

    /**
     * @notice Get the network middleware service's address.
     * @return address of the network middleware service
     */
    function NETWORK_MIDDLEWARE_SERVICE() external view returns (address);

    /**
     * @notice Get the vault's address.
     * @return address of the vault to perform slashings on
     */
    function vault() external view returns (address);

    /**
     * @notice Get a latest capture timestamp that was slashed on a network.
     * @param network address of the network
     * @return latest capture timestamp that was slashed
     */
    function latestSlashedCaptureTimestamp(address network) external view returns (uint48);

    /**
     * @notice Get a cumulative slash amount for an operator on a network until a given timestamp (inclusively) using a hint.
     * @param network address of the network
     * @param operator address of the operator
     * @param timestamp time point to get the cumulative slash amount until (inclusively)
     * @param hint hint for the checkpoint index
     * @return cumulative slash amount until the given timestamp (inclusively)
     */
    function cumulativeSlashAt(
        address network,
        address operator,
        uint48 timestamp,
        bytes memory hint
    ) external view returns (uint256);

    /**
     * @notice Get a cumulative slash amount for an operator on a network.
     * @param network address of the network
     * @param operator address of the operator
     * @return cumulative slash amount
     */
    function cumulativeSlash(address network, address operator) external view returns (uint256);

    /**
     * @notice Get a slashable amount of a stake got at a given capture timestamp using hints.
     * @param network address of the network
     * @param operator address of the operator
     * @param captureTimestamp time point to get the stake amount at
     * @param hints hints for the checkpoints' indexes
     * @return slashable amount of the stake
     */
    function slashableStake(
        address network,
        address operator,
        uint48 captureTimestamp,
        bytes memory hints
    ) external view returns (uint256);
}
