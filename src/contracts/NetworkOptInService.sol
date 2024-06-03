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
    address public immutable VAULT_REGISTRY;

    /**
     * @inheritdoc INetworkOptInService
     */
    mapping(address network => mapping(address resolver => mapping(address vault => bool value))) public isOptedIn;

    /**
     * @inheritdoc INetworkOptInService
     */
    mapping(address network => mapping(address resolver => mapping(address vault => uint48 timestamp))) public
        lastOptOut;

    constructor(address networkRegistry, address vaultRegistry) {
        NETWORK_REGISTRY = networkRegistry;
        VAULT_REGISTRY = vaultRegistry;
    }

    /**
     * @inheritdoc INetworkOptInService
     */
    function wasOptedInAfter(
        address network,
        address resolver,
        address vault,
        uint48 timestamp
    ) external view returns (bool) {
        return isOptedIn[network][resolver][vault] || lastOptOut[network][resolver][vault] >= timestamp;
    }

    /**
     * @inheritdoc INetworkOptInService
     */
    function optIn(address resolver, address vault) external {
        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        if (!IRegistry(VAULT_REGISTRY).isEntity(vault)) {
            revert NotVault();
        }

        if (isOptedIn[msg.sender][resolver][vault]) {
            revert AlreadyOptedIn();
        }

        isOptedIn[msg.sender][resolver][vault] = true;

        emit OptIn(msg.sender, resolver, vault);
    }

    /**
     * @inheritdoc INetworkOptInService
     */
    function optOut(address resolver, address vault) external {
        if (!isOptedIn[msg.sender][resolver][vault]) {
            revert NotOptedIn();
        }

        isOptedIn[msg.sender][resolver][vault] = false;
        lastOptOut[msg.sender][resolver][vault] = Time.timestamp();

        emit OptOut(msg.sender, resolver, vault);
    }
}
