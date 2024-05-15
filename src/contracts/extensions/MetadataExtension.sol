// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMetadataExtension} from "src/interfaces/extensions/IMetadataExtension.sol";

import {Extension} from "src/contracts/Extension.sol";

contract MetadataExtension is Extension, IMetadataExtension {
    /**
     * @inheritdoc IMetadataExtension
     */
    mapping(address entity => string value) public metadataURL;

    constructor(address registry) Extension(registry) {}

    /**
     * @inheritdoc IMetadataExtension
     */
    function setMetadataURL(string calldata metadataURL_) external onlyEntity {
        metadataURL[msg.sender] = metadataURL_;

        emit SetMetadataURL(msg.sender, metadataURL_);
    }
}
