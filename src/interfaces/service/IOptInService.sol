// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

interface IOptInService {
    error AlreadyOptedIn();
    error NotWho();
    error NotOptedIn();
    error NotWhereEntity();

    /**
     * @notice Emitted when an who opts into a "where" entity.
     * @param who address of the who
     * @param where address of the "where" entity
     */
    event OptIn(address indexed who, address indexed where);

    /**
     * @notice Emitted when an who opts out from a "where" entity.
     * @param who address of the who
     * @param where address of the "where" entity
     */
    event OptOut(address indexed who, address indexed where);

    /**
     * @notice Get the who registry's address.
     * @return address of the who registry
     */
    function WHO_REGISTRY() external view returns (address);

    /**
     * @notice Get the address of the registry where to opt-in.
     * @return address of the "where" registry
     */
    function WHERE_REGISTRY() external view returns (address);

    /**
     * @notice Check if a given who is opted-in to a particular "where" entity.
     * @param who address of the who
     * @param where address of the "where" registry
     */
    function isOptedIn(address who, address where) external view returns (bool);

    /**
     * @notice Get the timestamp of the last opt-out of a given who from a particular "where" entity.
     * @param who address of the who
     * @param where address of the "where" registry
     */
    function lastOptOut(address who, address where) external view returns (uint48);

    /**
     * @notice Check if a given who was opted-in to a particular "where" entity after a given timestamp (inclusively).
     * @param who address of the who
     * @param where address of the "where" registry
     * @param timestamp time point to check if the who was opted-in after
     */
    function wasOptedInAfter(address who, address where, uint48 timestamp) external view returns (bool);

    /**
     * @notice Opt-in a calling who to a particular "where" entity.
     * @param where address of the "where" registry
     */
    function optIn(address where) external;

    /**
     * @notice Opt-out a calling who from a particular "where" entity.
     * @param where address of the "where" registry
     */
    function optOut(address where) external;
}
