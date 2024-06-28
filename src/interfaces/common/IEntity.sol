// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

interface IEntity {
    /**
     * @notice Initialize this entity contract using a given data.
     * @param data some data to use
     */
    function initialize(bytes memory data) external;
}
