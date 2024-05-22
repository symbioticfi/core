// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IVaultDelegation} from "src/interfaces/IVaultDelegation.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";
import {INetworkOptInPlugin} from "src/interfaces/plugins/INetworkOptInPlugin.sol";
import {IOperatorOptInPlugin} from "src/interfaces/plugins/IOperatorOptInPlugin.sol";

import {VaultStorage} from "./VaultStorage.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract VaultDelegation is VaultStorage, IVaultDelegation {
    using Strings for string;

    constructor(
        address networkRegistry,
        address operatorRegistry,
        address networkMiddlewarePlugin,
        address networkVaultOptInPlugin,
        address operatorVaultOptInPlugin,
        address operatorNetworkOptInPlugin
    )
        VaultStorage(
            networkRegistry,
            operatorRegistry,
            networkMiddlewarePlugin,
            networkVaultOptInPlugin,
            operatorVaultOptInPlugin,
            operatorNetworkOptInPlugin
        )
    {}

    /**
     * @inheritdoc IVaultDelegation
     */
    function networkLimit(address network, address resolver) public view returns (uint256) {
        return _getLimit(_networkLimit[network][resolver], nextNetworkLimit[network][resolver]);
    }

    /**
     * @inheritdoc IVaultDelegation
     */
    function operatorLimit(address operator, address network) public view returns (uint256) {
        return _getLimit(_operatorLimit[operator][network], nextOperatorLimit[operator][network]);
    }

    /**
     * @inheritdoc IVaultDelegation
     */
    function setMaxNetworkLimit(address resolver, uint256 amount) external {
        if (maxNetworkLimit[msg.sender][resolver] == amount) {
            revert AlreadySet();
        }

        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        maxNetworkLimit[msg.sender][resolver] = amount;

        Limit storage limit = _networkLimit[msg.sender][resolver];
        DelayedLimit storage nextLimit = nextNetworkLimit[msg.sender][resolver];

        _updateLimit(limit, nextLimit);

        if (limit.amount > amount) {
            limit.amount = amount;
        }
        if (nextLimit.timestamp != 0) {
            if (nextLimit.amount > amount) {
                nextLimit.amount = amount;
            }
        }

        emit SetMaxNetworkLimit(msg.sender, resolver, amount);
    }

    /**
     * @inheritdoc IVaultDelegation
     */
    function setMetadataURL(string calldata metadataURL_) external onlyOwner {
        if (metadataURL.equal(metadataURL_)) {
            revert AlreadySet();
        }

        metadataURL = metadataURL_;

        emit SetMetadataURL(metadataURL_);
    }

    /**
     * @inheritdoc IVaultDelegation
     */
    function setAdminFee(uint256 adminFee_) external onlyRole(ADMIN_FEE_SET_ROLE) {
        if (adminFee == adminFee_) {
            revert AlreadySet();
        }

        if (adminFee_ > ADMIN_FEE_BASE) {
            revert InvalidAdminFee();
        }

        adminFee = adminFee_;

        emit SetAdminFee(adminFee_);
    }

    /**
     * @inheritdoc IVaultDelegation
     */
    function setDepositWhitelist(bool status) external onlyRole(DEPOSIT_WHITELIST_SET_ROLE) {
        if (depositWhitelist == status) {
            revert AlreadySet();
        }

        depositWhitelist = status;

        emit SetDepositWhitelist(status);
    }

    /**
     * @inheritdoc IVaultDelegation
     */
    function setDepositorWhitelistStatus(address account, bool status) external onlyRole(DEPOSITOR_WHITELIST_ROLE) {
        if (isDepositorWhitelisted[account] == status) {
            revert AlreadySet();
        }

        if (status && !depositWhitelist) {
            revert NoDepositWhitelist();
        }

        isDepositorWhitelisted[account] = status;

        emit SetDepositorWhitelistStatus(account, status);
    }

    /**
     * @inheritdoc IVaultDelegation
     */
    function setNetworkLimit(
        address network,
        address resolver,
        uint256 amount
    ) external onlyRole(NETWORK_LIMIT_SET_ROLE) {
        if (amount > maxNetworkLimit[network][resolver]) {
            revert ExceedsMaxNetworkLimit();
        }

        Limit storage limit = _networkLimit[network][resolver];
        DelayedLimit storage nextLimit = nextNetworkLimit[network][resolver];

        if (
            INetworkOptInPlugin(NETWORK_VAULT_OPT_IN_PLUGIN).isOptedIn(network, resolver, address(this))
                || INetworkOptInPlugin(NETWORK_VAULT_OPT_IN_PLUGIN).lastOptOut(network, resolver, address(this))
                    >= previousEpochStart()
        ) {
            _setLimit(limit, nextLimit, amount);
        } else {
            if (amount != 0) {
                revert NetworkNotOptedInVault();
            } else {
                limit.amount = 0;
                nextLimit.amount = 0;
                nextLimit.timestamp = 0;
            }
        }

        emit SetNetworkLimit(network, resolver, amount);
    }

    /**
     * @inheritdoc IVaultDelegation
     */
    function setOperatorLimit(
        address operator,
        address network,
        uint256 amount
    ) external onlyRole(OPERATOR_LIMIT_SET_ROLE) {
        Limit storage limit = _operatorLimit[operator][network];
        DelayedLimit storage nextLimit = nextOperatorLimit[operator][network];

        if (
            IOperatorOptInPlugin(OPERATOR_VAULT_OPT_IN_PLUGIN).isOptedIn(operator, address(this))
                || IOperatorOptInPlugin(OPERATOR_VAULT_OPT_IN_PLUGIN).lastOptOut(operator, address(this))
                    >= previousEpochStart()
        ) {
            _setLimit(limit, nextLimit, amount);
        } else {
            if (amount != 0) {
                revert OperatorNotOptedInVault();
            } else {
                limit.amount = 0;
                nextLimit.amount = 0;
                nextLimit.timestamp = 0;
            }
        }

        emit SetOperatorLimit(operator, network, amount);
    }

    function _getLimit(Limit storage limit, DelayedLimit storage nextLimit) private view returns (uint256) {
        if (nextLimit.timestamp == 0 || clock() < nextLimit.timestamp) {
            return limit.amount;
        }
        return nextLimit.amount;
    }

    function _setLimit(Limit storage limit, DelayedLimit storage nextLimit, uint256 amount) private {
        _updateLimit(limit, nextLimit);

        if (amount < limit.amount) {
            nextLimit.amount = amount;
            nextLimit.timestamp = currentEpochStart() + 2 * epochDuration;
        } else {
            limit.amount = amount;
            nextLimit.amount = 0;
            nextLimit.timestamp = 0;
        }
    }

    function _updateLimit(Limit storage limit, DelayedLimit storage nextLimit) internal {
        if (nextLimit.timestamp != 0 && nextLimit.timestamp <= clock()) {
            limit.amount = nextLimit.amount;
            nextLimit.timestamp = 0;
            nextLimit.amount = 0;
        }
    }
}
