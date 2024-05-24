// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {INetworkOptInService} from "src/interfaces/INetworkOptInService.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";

import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract NetworkOptInService is INetworkOptInService {
    /**
     * @inheritdoc INetworkOptInService
     */
    address public immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc INetworkOptInService
     */
    address public immutable WHERE_REGISTRY;

    /**
     * @inheritdoc INetworkOptInService
     */
    mapping(address network => mapping(address resolver => mapping(address where => bool value))) public isOptedIn;

    /**
     * @inheritdoc INetworkOptInService
     */
    mapping(address network => mapping(address resolver => mapping(address where => uint48 timestamp))) public
        lastOptOut;

    constructor(address networkRegistry, address whereRegistry) {
        NETWORK_REGISTRY = networkRegistry;
        WHERE_REGISTRY = whereRegistry;
    }

    /**
     * @inheritdoc INetworkOptInService
     */
    function wasOptedIn(
        address network,
        address resolver,
        address where,
        uint256 edgeTimestamp
    ) external view returns (bool) {
        return isOptedIn[network][resolver][where] || lastOptOut[network][resolver][where] >= edgeTimestamp;
    }

    /**
     * @inheritdoc INetworkOptInService
     */
    function optIn(address resolver, address where) external {
        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        if (!IRegistry(WHERE_REGISTRY).isEntity(where)) {
            revert NotWhereEntity();
        }

        if (isOptedIn[msg.sender][resolver][where]) {
            revert AlreadyOptedIn();
        }

        isOptedIn[msg.sender][resolver][where] = true;

        emit OptIn(msg.sender, resolver, where);
    }

    /**
     * @inheritdoc INetworkOptInService
     */
    function optOut(address resolver, address where) external {
        if (!isOptedIn[msg.sender][resolver][where]) {
            revert NotOptedIn();
        }

        isOptedIn[msg.sender][resolver][where] = false;
        lastOptOut[msg.sender][resolver][where] = Time.timestamp();

        emit OptOut(msg.sender, resolver, where);
    }
}
