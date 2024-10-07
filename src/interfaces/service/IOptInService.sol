// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOptInService {
    error AlreadyOptedIn();
    error ExpiredSignature();
    error InvalidSignature();
    error NotOptedIn();
    error NotWhereEntity();
    error NotWho();
    error OptOutCooldown();

    /**
     * @notice Emitted when a "who" opts into a "where" entity.
     * @param who address of the "who"
     * @param where address of the "where" entity
     */
    event OptIn(address indexed who, address indexed where);

    /**
     * @notice Emitted when a "who" opts out from a "where" entity.
     * @param who address of the "who"
     * @param where address of the "where" entity
     */
    event OptOut(address indexed who, address indexed where);

    /**
     * @notice Get the "who" registry's address.
     * @return address of the "who" registry
     */
    function WHO_REGISTRY() external view returns (address);

    /**
     * @notice Get the address of the registry where to opt-in.
     * @return address of the "where" registry
     */
    function WHERE_REGISTRY() external view returns (address);

    /**
     * @notice Get if a given "who" is opted-in to a particular "where" entity at a given timestamp using a hint.
     * @param who address of the "who"
     * @param where address of the "where" entity
     * @param timestamp time point to get if the "who" is opted-in at
     * @param hint hint for the checkpoint index
     * @return if the "who" is opted-in at the given timestamp
     */
    function isOptedInAt(
        address who,
        address where,
        uint48 timestamp,
        bytes calldata hint
    ) external view returns (bool);

    /**
     * @notice Check if a given "who" is opted-in to a particular "where" entity.
     * @param who address of the "who"
     * @param where address of the "where" entity
     * @return if the "who" is opted-in
     */
    function isOptedIn(address who, address where) external view returns (bool);

    /**
     * @notice Get the opt-in nonce of a given "who" to a particular "where" entity.
     * @param who address of the "who"
     * @param where address of the "where" entity
     * @return opt-in nonce
     */
    function optInNonces(address who, address where) external view returns (uint256);

    /**
     * @notice Get the opt-out nonce of a given "who" to a particular "where" entity.
     * @param who address of the "who"
     * @param where address of the "where" entity
     * @return opt-out nonce
     */
    function optOutNonces(address who, address where) external view returns (uint256);

    /**
     * @notice Opt-in a calling "who" to a particular "where" entity.
     * @param where address of the "where" entity
     */
    function optIn(
        address where
    ) external;

    /**
     * @notice Opt-in a "who" to a particular "where" entity with a signature.
     * @param who address of the "who"
     * @param where address of the "where" entity
     * @param deadline time point until the signature is valid (inclusively)
     * @param signature signature of the "who"
     */
    function optIn(address who, address where, uint48 deadline, bytes calldata signature) external;

    /**
     * @notice Opt-out a calling "who" from a particular "where" entity.
     * @param where address of the "where" entity
     */
    function optOut(
        address where
    ) external;

    /**
     * @notice Opt-out a "who" from a particular "where" entity with a signature.
     * @param who address of the "who"
     * @param where address of the "where" entity
     * @param deadline time point until the signature is valid (inclusively)
     * @param signature signature of the "who"
     */
    function optOut(address who, address where, uint48 deadline, bytes calldata signature) external;
}
