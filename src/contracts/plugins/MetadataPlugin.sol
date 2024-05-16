// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMetadataPlugin} from "src/interfaces/plugins/IMetadataPlugin.sol";

import {Plugin} from "src/contracts/Plugin.sol";

contract MetadataPlugin is Plugin, IMetadataPlugin {
    /**
     * @inheritdoc IMetadataPlugin
     */
    mapping(address entity => string value) public metadataURL;

    constructor(address registry) Plugin(registry) {}

    /**
     * @inheritdoc IMetadataPlugin
     */
    function setMetadataURL(string calldata metadataURL_) external onlyEntity {
        metadataURL[msg.sender] = metadataURL_;

        emit SetMetadataURL(msg.sender, metadataURL_);
    }
}
