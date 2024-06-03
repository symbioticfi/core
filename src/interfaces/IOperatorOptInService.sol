// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IOperatorOptInService {
    error AlreadyOptedIn();
    error NotOperator();
    error NotOptedIn();
    error NotWhereEntity();

    /**
     * @notice Emitted when an operator opts into a "where" entity.
     * @param operator address of the operator
     * @param where address of the "where" entity
     */
    event OptIn(address indexed operator, address indexed where);

    /**
     * @notice Emitted when an operator opts out from a "where" entity.
     * @param operator address of the operator
     * @param where address of the "where" entity
     */
    event OptOut(address indexed operator, address indexed where);

    /**
     * @notice Get the operator registry's address.
     * @return address of the operator registry
     */
    function OPERATOR_REGISTRY() external view returns (address);

    /**
     * @notice Get the address of the registry where to opt-in.
     * @return address of the "where" registry
     */
    function WHERE_REGISTRY() external view returns (address);

    /**
     * @notice Check if a given operator is opted-in to a particular "where" entity.
     * @param operator address of the operator
     * @param where address of the "where" registry
     */
    function isOptedIn(address operator, address where) external view returns (bool);

    /**
     * @notice Get the timestamp of the last opt-out of a given operator from a particular "where" entity.
     * @param operator address of the operator
     * @param where address of the "where" registry
     */
    function lastOptOut(address operator, address where) external view returns (uint48);

    /**
     * @notice Check if a given operator was opted-in to a particular "where" entity after a given timestamp (inclusively).
     * @param operator address of the operator
     * @param where address of the "where" registry
     * @param timestamp time point to check if the operator was opted-in after
     */
    function wasOptedInAfter(address operator, address where, uint48 timestamp) external view returns (bool);

    /**
     * @notice Opt-in a calling operator to a particular "where" entity.
     * @param where address of the "where" registry
     */
    function optIn(address where) external;

    /**
     * @notice Opt-out a calling operator from a particular "where" entity.
     * @param where address of the "where" registry
     */
    function optOut(address where) external;
}
