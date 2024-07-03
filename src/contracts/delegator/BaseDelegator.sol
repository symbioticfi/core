// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Entity} from "src/contracts/common/Entity.sol";

import {IBaseDelegator} from "src/interfaces/delegator/IBaseDelegator.sol";
import {IRegistry} from "src/interfaces/common/IRegistry.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";
import {IOptInService} from "src/interfaces/service/IOptInService.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
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
    mapping(address network => uint256 value) public maxNetworkLimit;

    constructor(
        address networkRegistry,
        address vaultFactory,
        address operatorVaultOptInService,
        address operatorNetworkOptInService,
        address delegatorFactory
    ) Entity(delegatorFactory) {
        NETWORK_REGISTRY = networkRegistry;
        VAULT_FACTORY = vaultFactory;
        OPERATOR_VAULT_OPT_IN_SERVICE = operatorVaultOptInService;
        OPERATOR_NETWORK_OPT_IN_SERVICE = operatorNetworkOptInService;
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function networkStakeIn(address network, uint48 duration) public view virtual returns (uint256) {}

    /**
     * @inheritdoc IBaseDelegator
     */
    function networkStake(address network) public view virtual returns (uint256) {}

    /**
     * @inheritdoc IBaseDelegator
     */
    function operatorNetworkStakeIn(
        address network,
        address operator,
        uint48 duration
    ) public view virtual returns (uint256) {}

    /**
     * @inheritdoc IBaseDelegator
     */
    function operatorNetworkStake(address network, address operator) public view virtual returns (uint256) {}

    /**
     * @inheritdoc IBaseDelegator
     */
    function minOperatorNetworkStakeDuring(
        address network,
        address operator,
        uint48 duration
    ) external view returns (uint256 minOperatorNetworkStakeDuring_) {
        if (
            !IOptInService(OPERATOR_VAULT_OPT_IN_SERVICE).isOptedIn(operator, vault)
                || !IOptInService(OPERATOR_NETWORK_OPT_IN_SERVICE).isOptedIn(operator, network)
        ) {
            return 0;
        }

        minOperatorNetworkStakeDuring_ = Math.min(IVault(vault).activeSupply(), operatorNetworkStake(network, operator));

        uint48 epochDuration = IVault(vault).epochDuration();
        uint48 nextEpochStart = IVault(vault).currentEpochStart() + epochDuration;
        uint48 delta = nextEpochStart - Time.timestamp();
        if (Time.timestamp() + duration >= nextEpochStart) {
            minOperatorNetworkStakeDuring_ =
                Math.min(minOperatorNetworkStakeDuring_, operatorNetworkStakeIn(network, operator, delta));
        }
        if (Time.timestamp() + duration >= nextEpochStart + epochDuration) {
            minOperatorNetworkStakeDuring_ = Math.min(
                minOperatorNetworkStakeDuring_, operatorNetworkStakeIn(network, operator, delta + epochDuration)
            );
        }
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

    /**
     * @inheritdoc IBaseDelegator
     */
    function onSlash(address network, address operator, uint256 slashedAmount) external {
        if (IVault(vault).slasher() != msg.sender) {
            revert NotSlasher();
        }

        if (slashedAmount > operatorNetworkStake(network, operator)) {
            revert TooMuchSlash();
        }

        _onSlash(network, operator, slashedAmount);

        emit OnSlash(network, operator, slashedAmount);
    }

    function _setMaxNetworkLimit(uint256 amount) internal virtual {}

    function _onSlash(address network, address operator, uint256 slashedAmount) internal virtual {}

    function _insertCheckpoint(Checkpoints.Trace256 storage checkpoints, uint48 key, uint256 value) internal {
        (, uint48 latestTimestamp1, uint256 latestValue1) = checkpoints.latestCheckpoint();
        if (key < latestTimestamp1) {
            checkpoints.pop();
            (, uint48 latestTimestamp2, uint256 latestValue2) = checkpoints.latestCheckpoint();
            if (key < latestTimestamp2) {
                checkpoints.pop();
                checkpoints.push(key, value);
                checkpoints.push(latestTimestamp2, latestValue2);
            } else {
                checkpoints.push(key, value);
            }
            checkpoints.push(latestTimestamp1, latestValue1);
        } else {
            checkpoints.push(key, value);
        }
    }

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
    }
}
