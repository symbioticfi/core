// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Entity} from "src/contracts/common/Entity.sol";

import {IBaseDelegator} from "src/interfaces/delegator/IBaseDelegator.sol";
import {IRegistry} from "src/interfaces/common/IRegistry.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";
import {IOptInService} from "src/interfaces/service/IOptInService.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract BaseDelegator is Entity, AccessControlUpgradeable, IBaseDelegator {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;

    /**
     * @inheritdoc IBaseDelegator
     */
    uint64 public constant VERSION = 1;

    /**
     * @inheritdoc IBaseDelegator
     */
    bytes32 public constant HOOK_SET_ROLE = keccak256("HOOK_SET_ROLE");

    /**
     * @inheritdoc IBaseDelegator
     */
    address public immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc IBaseDelegator
     */
    address public immutable VAULT_FACTORY;

    /**
     * @inheritdoc IBaseDelegator
     */
    address public immutable OPERATOR_VAULT_OPT_IN_SERVICE;

    /**
     * @inheritdoc IBaseDelegator
     */
    address public immutable OPERATOR_NETWORK_OPT_IN_SERVICE;

    /**
     * @inheritdoc IBaseDelegator
     */
    address public vault;

    /**
     * @inheritdoc IBaseDelegator
     */
    address public hook;

    /**
     * @inheritdoc IBaseDelegator
     */
    mapping(address network => uint256 value) public maxNetworkLimit;

    constructor(
        address networkRegistry,
        address vaultFactory,
        address operatorVaultOptInService,
        address operatorNetworkOptInService,
        address delegatorFactory,
        uint64 entityType
    ) Entity(delegatorFactory, entityType) {
        NETWORK_REGISTRY = networkRegistry;
        VAULT_FACTORY = vaultFactory;
        OPERATOR_VAULT_OPT_IN_SERVICE = operatorVaultOptInService;
        OPERATOR_NETWORK_OPT_IN_SERVICE = operatorNetworkOptInService;
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function networkStakeAt(address network, uint48 timestamp) external view virtual returns (uint256) {}

    /**
     * @inheritdoc IBaseDelegator
     */
    function networkStake(address network) external view virtual returns (uint256) {}

    /**
     * @inheritdoc IBaseDelegator
     */
    function stakeAt(address network, address operator, uint48 timestamp) public view returns (uint256) {
        if (
            !IOptInService(OPERATOR_VAULT_OPT_IN_SERVICE).isOptedInAt(operator, vault, timestamp)
                || !IOptInService(OPERATOR_NETWORK_OPT_IN_SERVICE).isOptedInAt(operator, network, timestamp)
        ) {
            return 0;
        }

        return _stakeAt(network, operator, timestamp);
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function stake(address network, address operator) external view returns (uint256) {
        if (
            !IOptInService(OPERATOR_VAULT_OPT_IN_SERVICE).isOptedIn(operator, vault)
                || !IOptInService(OPERATOR_NETWORK_OPT_IN_SERVICE).isOptedIn(operator, network)
        ) {
            return 0;
        }

        return _stake(network, operator);
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function setMaxNetworkLimit(uint256 amount) external {
        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        if (maxNetworkLimit[msg.sender] == amount) {
            revert AlreadySet();
        }

        maxNetworkLimit[msg.sender] = amount;

        _setMaxNetworkLimit(amount);

        emit SetMaxNetworkLimit(msg.sender, amount);
    }

    function setHook(address hook_) external onlyRole(HOOK_SET_ROLE) {
        hook = hook_;

        emit SetHook(hook_);
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function onSlash(address network, address operator, uint256 slashedAmount, uint48 captureTimestamp) external {
        if (IVault(vault).slasher() != msg.sender) {
            revert NotSlasher();
        }

        if (slashedAmount > stakeAt(network, operator, captureTimestamp)) {
            revert TooMuchSlash();
        }

        _onSlash(network, operator, slashedAmount, captureTimestamp);

        emit OnSlash(network, operator, slashedAmount);
    }

    function _stakeAt(address network, address operator, uint48 timestamp) internal view virtual returns (uint256) {}

    function _stake(address network, address operator) internal view virtual returns (uint256) {}

    function _setMaxNetworkLimit(uint256 amount) internal virtual {}

    function _onSlash(
        address network,
        address operator,
        uint256 slashedAmount,
        uint48 captureTimestamp
    ) internal virtual {}

    function _initializeInternal(
        address vault_,
        bytes memory data
    ) internal virtual returns (IBaseDelegator.BaseParams memory) {}

    function _initialize(bytes memory data) internal override {
        (address vault_, bytes memory data_) = abi.decode(data, (address, bytes));

        if (!IRegistry(VAULT_FACTORY).isEntity(vault_)) {
            revert NotVault();
        }

        vault = vault_;

        IBaseDelegator.BaseParams memory baseParams = _initializeInternal(vault_, data_);

        if (baseParams.defaultAdminRoleHolder != address(0)) {
            _grantRole(DEFAULT_ADMIN_ROLE, baseParams.defaultAdminRoleHolder);
        }

        if (baseParams.hook != address(0)) {
            hook = baseParams.hook;
        } else {
            if (baseParams.hookSetRoleHolder != address(0)) {
                _grantRole(HOOK_SET_ROLE, baseParams.hookSetRoleHolder);
            }
        }
    }
}
