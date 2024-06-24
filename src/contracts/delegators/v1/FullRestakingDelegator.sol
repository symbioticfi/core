// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {NonMigratableEntity} from "src/contracts/base/NonMigratableEntity.sol";

import {IFullRestakingDelegator} from "src/interfaces/delegators/v1/IFullRestakingDelegator.sol";
import {IDelegator} from "src/interfaces/delegators/v1/IDelegator.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";
import {IVault} from "src/interfaces/vault/v1/IVault.sol";
import {IOptInService} from "src/interfaces/IOptInService.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract FullRestakingDelegator is NonMigratableEntity, AccessControlUpgradeable, IFullRestakingDelegator {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;

    /**
     * @inheritdoc IDelegator
     */
    uint64 public constant VERSION = 1;

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    bytes32 public constant NETWORK_LIMIT_SET_ROLE = keccak256("NETWORK_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    bytes32 public constant OPERATOR_NETWORK_LIMIT_SET_ROLE = keccak256("OPERATOR_NETWORK_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    address public immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    address public immutable VAULT_FACTORY;

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    address public immutable OPERATOR_VAULT_OPT_IN_SERVICE;

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    address public immutable OPERATOR_NETWORK_OPT_IN_SERVICE;

    /**
     * @inheritdoc IDelegator
     */
    address public vault;

    /**
     * @inheritdoc IDelegator
     */
    mapping(address network => uint256 value) public maxNetworkLimit;

    mapping(address network => Checkpoints.Trace256 value) private _networkLimit;

    mapping(address network => Checkpoints.Trace256 value) private _totalOperatorNetworkLimit;

    mapping(address network => mapping(address operator => Checkpoints.Trace256 value)) private _operatorNetworkLimit;

    modifier onlySlasher() {
        if (IVault(vault).slasher() != msg.sender) {
            revert NotSlasher();
        }
        _;
    }

    constructor(
        address networkRegistry,
        address vaultFactory,
        address operatorVaultOptInService,
        address operatorNetworkOptInService
    ) {
        NETWORK_REGISTRY = networkRegistry;
        VAULT_FACTORY = vaultFactory;
        OPERATOR_VAULT_OPT_IN_SERVICE = operatorVaultOptInService;
        OPERATOR_NETWORK_OPT_IN_SERVICE = operatorNetworkOptInService;
    }

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    function networkLimitIn(address network, uint48 duration) public view returns (uint256) {
        return _networkLimit[network].upperLookupRecent(Time.timestamp() + duration);
    }

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    function networkLimit(address network) public view returns (uint256) {
        return _networkLimit[network].upperLookupRecent(Time.timestamp());
    }

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    function totalOperatorNetworkLimitIn(address network, uint48 duration) public view returns (uint256) {
        return _totalOperatorNetworkLimit[network].upperLookupRecent(Time.timestamp() + duration);
    }

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    function totalOperatorNetworkLimit(address network) public view returns (uint256) {
        return _totalOperatorNetworkLimit[network].upperLookupRecent(Time.timestamp());
    }

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    function operatorNetworkLimitIn(address network, address operator, uint48 duration) public view returns (uint256) {
        return _operatorNetworkLimit[network][operator].upperLookupRecent(Time.timestamp() + duration);
    }

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    function operatorNetworkLimit(address network, address operator) public view returns (uint256) {
        return _operatorNetworkLimit[network][operator].upperLookupRecent(Time.timestamp());
    }

    /**
     * @inheritdoc IDelegator
     */
    function networkStakeIn(address network, uint48 duration) public view returns (uint256) {
        return Math.min(
            IVault(vault).totalSupplyIn(duration),
            Math.min(networkLimitIn(network, duration), totalOperatorNetworkLimitIn(network, duration))
        );
    }

    /**
     * @inheritdoc IDelegator
     */
    function networkStake(address network) public view returns (uint256) {
        return
            Math.min(IVault(vault).totalSupply(), Math.min(networkLimit(network), totalOperatorNetworkLimit(network)));
    }

    /**
     * @inheritdoc IDelegator
     */
    function operatorNetworkStakeIn(address network, address operator, uint48 duration) public view returns (uint256) {
        return Math.min(networkStakeIn(network, duration), operatorNetworkLimitIn(network, operator, duration));
    }

    /**
     * @inheritdoc IDelegator
     */
    function operatorNetworkStake(address network, address operator) public view returns (uint256) {
        return Math.min(networkStake(network), operatorNetworkLimit(network, operator));
    }

    /**
     * @inheritdoc IDelegator
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

        minOperatorNetworkStakeDuring_ = operatorNetworkStake(network, operator);

        uint48 epochDuration = IVault(vault).epochDuration();
        uint48 nextEpochStart = IVault(vault).currentEpochStart() + epochDuration;
        uint48 delta = nextEpochStart - Time.timestamp();
        if (Time.timestamp() + duration >= nextEpochStart) {
            minOperatorNetworkStakeDuring_ =
                Math.min(minOperatorNetworkStakeDuring_, operatorNetworkStakeIn(operator, network, delta));
        }
        if (Time.timestamp() + duration >= nextEpochStart + epochDuration) {
            minOperatorNetworkStakeDuring_ = Math.min(
                minOperatorNetworkStakeDuring_, operatorNetworkStakeIn(operator, network, delta + epochDuration)
            );
        }
    }

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    function setMaxNetworkLimit(address network, uint256 amount) external {
        if (maxNetworkLimit[msg.sender] == amount) {
            revert AlreadySet();
        }

        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        maxNetworkLimit[msg.sender] = amount;

        _normalizeExistingLimits(_networkLimit[network], amount);

        emit SetMaxNetworkLimit(network, amount);
    }

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    function setNetworkLimit(address network, uint256 amount) external onlyRole(NETWORK_LIMIT_SET_ROLE) {
        if (amount > maxNetworkLimit[network]) {
            revert ExceedsMaxNetworkLimit();
        }

        _networkLimit[network].push(IVault(vault).currentEpochStart() + 2 * IVault(vault).epochDuration(), amount);

        emit SetNetworkLimit(network, amount);
    }

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    function setOperatorNetworkLimit(
        address network,
        address operator,
        uint256 amount
    ) external onlyRole(OPERATOR_NETWORK_LIMIT_SET_ROLE) {
        uint48 timestamp = IVault(vault).currentEpochStart() + 2 * IVault(vault).epochDuration();

        _totalOperatorNetworkLimit[network].push(
            timestamp,
            _totalOperatorNetworkLimit[network].latest() + amount - _operatorNetworkLimit[network][operator].latest()
        );

        _operatorNetworkLimit[network][operator].push(timestamp, amount);

        emit SetOperatorNetworkLimit(network, operator, amount);
    }

    /**
     * @inheritdoc IDelegator
     */
    function onSlash(address network, address operator, uint256 slashedAmount) external onlySlasher {
        _networkLimit[network].push(Time.timestamp(), networkLimit(network) - slashedAmount);

        _totalOperatorNetworkLimit[network].push(Time.timestamp(), totalOperatorNetworkLimit(network) - slashedAmount);

        _operatorNetworkLimit[network][operator].push(
            Time.timestamp(), operatorNetworkLimit(network, operator) - slashedAmount
        );

        emit Slash(network, operator, slashedAmount);
    }

    function _normalizeExistingLimits(Checkpoints.Trace256 storage _networkLimit_, uint256 maxLimit) private {
        (, uint48 latestTimestamp1, uint256 latestValue1) = _networkLimit_.latestCheckpoint();
        if (Time.timestamp() < latestTimestamp1) {
            _networkLimit_.pop();
            (, uint48 latestTimestamp2, uint256 latestValue2) = _networkLimit_.latestCheckpoint();
            if (Time.timestamp() < latestTimestamp2) {
                _networkLimit_.pop();
                _networkLimit_.push(Time.timestamp(), Math.min(_networkLimit_.latest(), maxLimit));
                _networkLimit_.push(latestTimestamp2, Math.min(latestValue2, maxLimit));
            } else {
                _networkLimit_.push(Time.timestamp(), Math.min(_networkLimit_.latest(), maxLimit));
            }
            _networkLimit_.push(latestTimestamp1, Math.min(latestValue1, maxLimit));
        } else {
            _networkLimit_.push(Time.timestamp(), Math.min(_networkLimit_.latest(), maxLimit));
        }
    }

    function _initialize(bytes memory data) internal override {
        (InitParams memory params) = abi.decode(data, (InitParams));

        if (!IRegistry(VAULT_FACTORY).isEntity(params.vault)) {
            revert NotVault();
        }

        vault = params.vault;

        address vaultOwner = Ownable(params.vault).owner();
        _grantRole(DEFAULT_ADMIN_ROLE, vaultOwner);
        _grantRole(NETWORK_LIMIT_SET_ROLE, vaultOwner);
        _grantRole(OPERATOR_NETWORK_LIMIT_SET_ROLE, vaultOwner);
    }
}
