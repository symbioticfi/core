// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {Entity} from "src/contracts/common/Entity.sol";
import {StaticDelegateCallable} from "src/contracts/common/StaticDelegateCallable.sol";

import {IBaseDelegator} from "src/interfaces/delegator/IBaseDelegator.sol";
import {IDelegatorHook} from "src/interfaces/delegator/IDelegatorHook.sol";
import {IOptInService} from "src/interfaces/service/IOptInService.sol";
import {IRegistry} from "src/interfaces/common/IRegistry.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";
import {Subnetwork} from "src/contracts/libraries/Subnetwork.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract BaseDelegator is Entity, StaticDelegateCallable, AccessControlUpgradeable, IBaseDelegator {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;
    using Subnetwork for bytes32;
    using Subnetwork for address;

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
    mapping(bytes32 subnetwork => uint256 value) public maxNetworkLimit;

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
    function stakeAt(
        bytes32 subnetwork,
        address operator,
        uint48 timestamp,
        bytes memory hints
    ) public view returns (uint256) {
        (uint256 stake_, bytes memory baseHints) = _stakeAt(subnetwork, operator, timestamp, hints);
        StakeBaseHints memory stakeBaseHints;
        if (baseHints.length > 0) {
            stakeBaseHints = abi.decode(baseHints, (StakeBaseHints));
        }

        if (
            stake_ == 0
                || !IOptInService(OPERATOR_VAULT_OPT_IN_SERVICE).isOptedInAt(
                    operator, vault, timestamp, stakeBaseHints.operatorVaultOptInHint
                )
                || !IOptInService(OPERATOR_NETWORK_OPT_IN_SERVICE).isOptedInAt(
                    operator, subnetwork.network(), timestamp, stakeBaseHints.operatorNetworkOptInHint
                )
        ) {
            return 0;
        }

        return stake_;
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function stake(bytes32 subnetwork, address operator) external view returns (uint256) {
        if (
            !IOptInService(OPERATOR_VAULT_OPT_IN_SERVICE).isOptedIn(operator, vault)
                || !IOptInService(OPERATOR_NETWORK_OPT_IN_SERVICE).isOptedIn(operator, subnetwork.network())
        ) {
            return 0;
        }

        return _stake(subnetwork, operator);
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function setMaxNetworkLimit(uint96 identifier, uint256 amount) external {
        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        bytes32 subnetwork = (msg.sender).subnetwork(identifier);
        if (maxNetworkLimit[subnetwork] == amount) {
            revert AlreadySet();
        }

        maxNetworkLimit[subnetwork] = amount;

        _setMaxNetworkLimit(subnetwork, amount);

        emit SetMaxNetworkLimit(subnetwork, amount);
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function setHook(address hook_) external onlyRole(HOOK_SET_ROLE) {
        hook = hook_;

        emit SetHook(hook_);
    }

    /**
     * @inheritdoc IBaseDelegator
     */
    function onSlash(
        bytes32 subnetwork,
        address operator,
        uint256 slashedAmount,
        uint48 captureTimestamp,
        bytes memory data
    ) external {
        if (IVault(vault).slasher() != msg.sender) {
            revert NotSlasher();
        }

        address hook_ = hook;
        if (hook_ != address(0)) {
            bytes memory calldata_ = abi.encodeWithSelector(
                IDelegatorHook.onSlash.selector, subnetwork, operator, slashedAmount, captureTimestamp, data
            );
            /// @solidity memory-safe-assembly
            assembly {
                pop(call(250000, hook_, 0, add(calldata_, 0x20), mload(calldata_), 0, 0))
            }
        }

        emit OnSlash(subnetwork, operator, slashedAmount);
    }

    function _initialize(bytes calldata data) internal override {
        (address vault_, bytes memory data_) = abi.decode(data, (address, bytes));

        if (!IRegistry(VAULT_FACTORY).isEntity(vault_)) {
            revert NotVault();
        }

        vault = vault_;

        IBaseDelegator.BaseParams memory baseParams = ___initialize(vault_, data_);

        hook = baseParams.hook;

        if (baseParams.defaultAdminRoleHolder != address(0)) {
            _grantRole(DEFAULT_ADMIN_ROLE, baseParams.defaultAdminRoleHolder);
        }

        if (baseParams.hookSetRoleHolder != address(0)) {
            _grantRole(HOOK_SET_ROLE, baseParams.hookSetRoleHolder);
        }
    }

    function _stakeAt(
        bytes32 subnetwork,
        address operator,
        uint48 timestamp,
        bytes memory hints
    ) internal view virtual returns (uint256, bytes memory) {}

    function _stake(bytes32 subnetwork, address operator) internal view virtual returns (uint256) {}

    function _setMaxNetworkLimit(bytes32 subnetwork, uint256 amount) internal virtual {}

    function ___initialize(
        address vault_,
        bytes memory data
    ) internal virtual returns (IBaseDelegator.BaseParams memory) {}
}
