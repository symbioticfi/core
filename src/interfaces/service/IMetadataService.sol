// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IMetadataService
 * @notice Interface for the MetadataService contract.
 */
interface IMetadataService {
    error AlreadySet();
    error NotEntity();

    /**
     * @notice Emitted when a metadata URL is set for an entity.
     * @param entity Address of the entity.
     * @param metadataURL New metadata URL of the entity.
     */
    event SetMetadataURL(address indexed entity, string metadataURL);

    /**
     * @notice Get the registry's address.
     * @return Address Of the registry.
     */
    function REGISTRY() external view returns (address);

    /**
     * @notice Get a URL with an entity's metadata.
     * @param entity Address of the entity.
     * @return Metadata URL of the entity.
     */
    function metadataURL(address entity) external view returns (string memory);

    /**
     * @notice Set a new metadata URL for a calling entity.
     * @param metadataURL New metadata URL of the entity.
     */
    function setMetadataURL(string calldata metadataURL) external;
}
