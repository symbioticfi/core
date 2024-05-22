// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IVaultDelegation} from "src/interfaces/IVaultDelegation.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";

import {VaultStorage} from "./VaultStorage.sol";

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract VaultDelegation is VaultStorage, IVaultDelegation {
    using Strings for string;

    constructor(
        address networkRegistry,
        address operatorRegistry,
        address networkMiddlewarePlugin,
        address networkOptInPlugin
    ) VaultStorage(networkRegistry, operatorRegistry, networkMiddlewarePlugin, networkOptInPlugin) {}

    /**
     * @inheritdoc IVaultDelegation
     */
    function isNetworkOptedIn(address network, address resolver) public view returns (bool) {
        return _isNetworkOptedIn[network][resolver];
    }

    /**
     * @inheritdoc IVaultDelegation
     */
    function isOperatorOptedIn(address operator) public view returns (bool) {
        if (operatorOptOutAt[operator] == 0) {
            return _isOperatorOptedIn[operator];
        }
        if (clock() < operatorOptOutAt[operator]) {
            return true;
        }
        return false;
    }

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
    function optInNetwork(address resolver, uint256 maxNetworkLimit_) external {
        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        if (isNetworkOptedIn(msg.sender, resolver)) {
            revert NetworkAlreadyOptedIn();
        }

        if (maxNetworkLimit_ == 0) {
            revert InvalidMaxNetworkLimit();
        }

        _isNetworkOptedIn[msg.sender][resolver] = true;

        _networkLimit[msg.sender][resolver].amount = 0;
        nextNetworkLimit[msg.sender][resolver].timestamp = 0;

        maxNetworkLimit[msg.sender][resolver] = maxNetworkLimit_;

        emit OptInNetwork(msg.sender, resolver);
    }

    /**
     * @inheritdoc IVaultDelegation
     */
    function optOutNetwork(address resolver) external {
        if (!isNetworkOptedIn(msg.sender, resolver)) {
            revert NetworkNotOptedIn();
        }

        _updateLimit(_networkLimit[msg.sender][resolver], nextNetworkLimit[msg.sender][resolver]);

        _isNetworkOptedIn[msg.sender][resolver] = false;

        nextNetworkLimit[msg.sender][resolver].amount = 0;
        nextNetworkLimit[msg.sender][resolver].timestamp = currentEpochStart() + 2 * epochDuration;

        maxNetworkLimit[msg.sender][resolver] = 0;

        emit OptOutNetwork(msg.sender, resolver);
    }

    /**
     * @inheritdoc IVaultDelegation
     */
    function optInOperator() external {
        if (!IRegistry(OPERATOR_REGISTRY).isEntity(msg.sender)) {
            revert NotOperator();
        }

        if (isOperatorOptedIn(msg.sender)) {
            revert OperatorAlreadyOptedIn();
        }

        if (!_isOperatorOptedIn[msg.sender]) {
            _isOperatorOptedIn[msg.sender] = true;
        } else {
            operatorOptOutAt[msg.sender] = 0;
        }

        emit OptInOperator(msg.sender);
    }

    /**
     * @inheritdoc IVaultDelegation
     */
    function optOutOperator() external {
        if (!isOperatorOptedIn(msg.sender)) {
            revert OperatorNotOptedIn();
        }

        operatorOptOutAt[msg.sender] = currentEpochStart() + 2 * epochDuration;

        emit OptOutOperator(msg.sender);
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
        if (status && !depositWhitelist) {
            revert NoDepositWhitelist();
        }

        if (isDepositorWhitelisted[account] == status) {
            revert AlreadySet();
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
        if (!isNetworkOptedIn(network, resolver)) {
            revert NetworkNotOptedIn();
        }

        if (amount > maxNetworkLimit[network][resolver]) {
            revert ExceedsMaxNetworkLimit();
        }

        _setLimit(_networkLimit[network][resolver], nextNetworkLimit[network][resolver], amount);

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

        if (!isOperatorOptedIn(operator)) {
            if (amount != 0) {
                revert OperatorNotOptedIn();
            } else {
                limit.amount = 0;
                nextLimit.amount = 0;
                nextLimit.timestamp = 0;
            }
        } else {
            _setLimit(limit, nextLimit, amount);
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
