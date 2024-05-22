// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {INetworkOptInPlugin} from "src/interfaces/plugins/INetworkOptInPlugin.sol";
import {IRegistry} from "src/interfaces/IRegistry.sol";

import {Plugin} from "src/contracts/base/Plugin.sol";
import {ERC6372} from "src/contracts/utils/ERC6372.sol";

contract NetworkOptInPlugin is Plugin, ERC6372, INetworkOptInPlugin {
    /**
     * @inheritdoc INetworkOptInPlugin
     */
    address public immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc INetworkOptInPlugin
     */
    mapping(address operator => mapping(address network => bool value)) public isOperatorOptedIn;

    /**
     * @inheritdoc INetworkOptInPlugin
     */
    mapping(address operator => mapping(address network => uint48 timestamp)) public lastOperatorOptOut;

    constructor(address operatorRegistry, address networkRegistry) Plugin(operatorRegistry) {
        NETWORK_REGISTRY = networkRegistry;
    }

    /**
     * @inheritdoc INetworkOptInPlugin
     */
    function optIn(address network) external onlyEntity {
        if (!IRegistry(NETWORK_REGISTRY).isEntity(network)) {
            revert NotNetwork();
        }

        if (isOperatorOptedIn[msg.sender][network]) {
            revert OperatorAlreadyOptedIn();
        }

        isOperatorOptedIn[msg.sender][network] = true;
    }

    /**
     * @inheritdoc INetworkOptInPlugin
     */
    function optOut(address network) external {
        if (!isOperatorOptedIn[msg.sender][network]) {
            revert OperatorNotOptedIn();
        }

        isOperatorOptedIn[msg.sender][network] = false;
        lastOperatorOptOut[msg.sender][network] = clock();
    }
}
