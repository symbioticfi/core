// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMetadataPlugin} from "src/interfaces/IMetadataPlugin.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract MetadataPlugin is IMetadataPlugin {
    using Strings for string;

    /**
     * @inheritdoc IMetadataPlugin
     */
    address public immutable REGISTRY;

    /**
     * @inheritdoc IMetadataPlugin
     */
    mapping(address entity => string value) public metadataURL;

    constructor(address registry) {
        REGISTRY = registry;
    }

    /**
     * @inheritdoc IMetadataPlugin
     */
    function setMetadataURL(string calldata metadataURL_) external {
        if (!IRegistry(REGISTRY).isEntity(msg.sender)) {
            revert NotEntity();
        }

        if (metadataURL[msg.sender].equal(metadataURL_)) {
            revert AlreadySet();
        }

        metadataURL[msg.sender] = metadataURL_;

        emit SetMetadataURL(msg.sender, metadataURL_);
    }
}
