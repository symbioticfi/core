// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {INetworkOptInExtension} from "src/interfaces/extensions/INetworkOptInExtension.sol";
import {IFactory} from "src/interfaces/IFactory.sol";

import {Extension} from "src/contracts/Extension.sol";
import {ERC6372} from "src/contracts/utils/ERC6372.sol";

contract NetworkOptInExtension is Extension, ERC6372, INetworkOptInExtension {
    /**
     * @inheritdoc INetworkOptInExtension
     */
    address public immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc INetworkOptInExtension
     */
    mapping(address operator => mapping(address network => bool value)) public isOperatorOptedIn;

    /**
     * @inheritdoc INetworkOptInExtension
     */
    mapping(address operator => mapping(address network => uint48 timestamp)) public lastOperatorOptOut;

    modifier isNetwork(address network) {
        if (!IFactory(NETWORK_REGISTRY).isEntity(network)) {
            revert NotNetwork();
        }
        _;
    }

    constructor(address operatorRegistry, address networkRegistry) Extension(operatorRegistry) {
        NETWORK_REGISTRY = networkRegistry;
    }

    /**
     * @inheritdoc INetworkOptInExtension
     */
    function optIn(address network) external onlyEntity isNetwork(network) {
        if (isOperatorOptedIn[msg.sender][network]) {
            revert OperatorAlreadyOptedIn();
        }

        isOperatorOptedIn[msg.sender][network] = true;
    }

    /**
     * @inheritdoc INetworkOptInExtension
     */
    function optOut(address network) external onlyEntity isNetwork(network) {
        if (!isOperatorOptedIn[msg.sender][network]) {
            revert OperatorNotOptedIn();
        }

        isOperatorOptedIn[msg.sender][network] = false;
        lastOperatorOptOut[msg.sender][network] = clock();
    }
}
