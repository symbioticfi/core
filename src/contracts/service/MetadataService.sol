// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IMetadataService} from "../../interfaces/service/IMetadataService.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract MetadataService is IMetadataService {
    using Strings for string;

    /**
     * @inheritdoc IMetadataService
     */
    address public immutable REGISTRY;

    /**
     * @inheritdoc IMetadataService
     */
    mapping(address entity => string value) public metadataURL;

    constructor(
        address registry
    ) {
        REGISTRY = registry;
    }

    /**
     * @inheritdoc IMetadataService
     */
    function setMetadataURL(
        string calldata metadataURL_
    ) external {
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
