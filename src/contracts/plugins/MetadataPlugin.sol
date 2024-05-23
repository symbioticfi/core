// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Plugin} from "src/contracts/base/Plugin.sol";

import {IMetadataPlugin} from "src/interfaces/plugins/IMetadataPlugin.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract MetadataPlugin is Plugin, IMetadataPlugin {
    using Strings for string;

    /**
     * @inheritdoc IMetadataPlugin
     */
    mapping(address entity => string value) public metadataURL;

    constructor(address registry) Plugin(registry) {}

    /**
     * @inheritdoc IMetadataPlugin
     */
    function setMetadataURL(string calldata metadataURL_) external onlyEntity {
        if (metadataURL[msg.sender].equal(metadataURL_)) {
            revert AlreadySet();
        }

        metadataURL[msg.sender] = metadataURL_;

        emit SetMetadataURL(msg.sender, metadataURL_);
    }
}
