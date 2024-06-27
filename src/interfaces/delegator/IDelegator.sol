// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IDelegator {
    /**
     * @notice Get a version of the delegator (different versions mean different interfaces).
     * @return version of the delegator
     * @dev Must return 1 for this one.
     */
    function VERSION() external view returns (uint64);

    event OnSlash(address indexed network, address indexed operator, uint256 slashedAmount);

    /**
     * @notice Get the vault's address.
     * @return address of the vault
     */
    function vault() external view returns (address);

    function maxNetworkLimit(address network) external view returns (uint256);

    function networkStakeIn(address network, uint48 duration) external view returns (uint256);

    function networkStake(address network) external view returns (uint256);

    /**
     * @notice Get a maximum amount of collateral that can be slashed
     *         for a particular network and operator in `duration` seconds.
     * @param network address of the network
     * @param operator address of the operator
     * @param duration duration to get the slashable amount in
     * @return maximum amount of the collateral that can be slashed in `duration` seconds
     */
    function operatorNetworkStakeIn(
        address network,
        address operator,
        uint48 duration
    ) external view returns (uint256);

    /**
     * @notice Get a maximum amount of collateral that can be slashed for a particular network, and operator.
     * @param network address of the network
     * @param operator address of the operator
     * @return maximum amount of the collateral that can be slashed
     */
    function operatorNetworkStake(address network, address operator) external view returns (uint256);

    /**
     * @notice Get a minimum stake that a given network will be able to slash
     *         for a certain operator during `duration` (if no cross-slashing).
     * @param network address of the network
     * @param operator address of the operator
     * @param duration duration to get the minimum slashable stake during
     * @return minimum slashable stake during `duration`
     */
    function minOperatorNetworkStakeDuring(
        address network,
        address operator,
        uint48 duration
    ) external view returns (uint256);

    /**
     * @notice Slashing callback for limits decreasing.
     * @param slashedAmount a
     */
    function onSlash(address network, address operator, uint256 slashedAmount) external;
}
