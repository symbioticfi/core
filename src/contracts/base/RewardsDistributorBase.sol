// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRegistry} from "src/interfaces/base/IRegistry.sol";
import {IRewardsDistributorBase} from "src/interfaces/base/IRewardsDistributorBase.sol";

abstract contract RewardsDistributorBase is IRewardsDistributorBase {
    /**
     * @inheritdoc IRewardsDistributorBase
     */
    address public immutable NETWORK_REGISTRY;

    modifier checkNetwork(address account) {
        _checkNetwork(account);
        _;
    }

    constructor(address networkRegistry) {
        NETWORK_REGISTRY = networkRegistry;
    }

    /**
     * @inheritdoc IRewardsDistributorBase
     */
    function VAULT() public view virtual override returns (address) {}

    /**
     * @inheritdoc IRewardsDistributorBase
     */
    function version() external view virtual override returns (uint64) {}

    function _checkNetwork(address account) internal view {
        if (!IRegistry(NETWORK_REGISTRY).isEntity(account)) {
            revert NotNetwork();
        }
    }
}
