// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {NonMigratableEntity} from "src/contracts/common/NonMigratableEntity.sol";

import {INetworkRestakingDelegator} from "src/interfaces/delegator/INetworkRestakingDelegator.sol";
import {IDelegator} from "src/interfaces/delegator/IDelegator.sol";
import {IRegistry} from "src/interfaces/common/IRegistry.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";
import {IOptInService} from "src/interfaces/service/IOptInService.sol";

import {Checkpoints} from "src/contracts/libraries/Checkpoints.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract NetworkRestakingDelegator is NonMigratableEntity, AccessControlUpgradeable, INetworkRestakingDelegator {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;

    /**
     * @inheritdoc IDelegator
     */
    uint64 public constant VERSION = 1;

    /**
     * @inheritdoc INetworkRestakingDelegator
     */
    bytes32 public constant NETWORK_LIMIT_SET_ROLE = keccak256("NETWORK_LIMIT_SET_ROLE");

    /**
     * @inheritdoc INetworkRestakingDelegator
     */
    bytes32 public constant OPERATOR_NETWORK_SHARES_SET_ROLE = keccak256("OPERATOR_NETWORK_SHARES_SET_ROLE");

    /**
     * @inheritdoc INetworkRestakingDelegator
     */
    address public immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc INetworkRestakingDelegator
     */
    address public immutable VAULT_FACTORY;

    /**
     * @inheritdoc INetworkRestakingDelegator
     */
    address public immutable OPERATOR_VAULT_OPT_IN_SERVICE;

    /**
     * @inheritdoc INetworkRestakingDelegator
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

    mapping(address network => Checkpoints.Trace256 shares) private _totalOperatorNetworkShares;

    mapping(address network => mapping(address operator => Checkpoints.Trace256 shares)) private _operatorNetworkShares;

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
     * @inheritdoc INetworkRestakingDelegator
     */
    function networkLimitIn(address network, uint48 duration) public view returns (uint256) {
        return _networkLimit[network].upperLookupRecent(Time.timestamp() + duration);
    }

    /**
     * @inheritdoc INetworkRestakingDelegator
     */
    function networkLimit(address network) public view returns (uint256) {
        return _networkLimit[network].upperLookupRecent(Time.timestamp());
    }

    /**
     * @inheritdoc INetworkRestakingDelegator
     */
    function totalOperatorNetworkSharesIn(address network, uint48 duration) public view returns (uint256) {
        return _totalOperatorNetworkShares[network].upperLookupRecent(Time.timestamp() + duration);
    }

    /**
     * @inheritdoc INetworkRestakingDelegator
     */
    function totalOperatorNetworkShares(address network) public view returns (uint256) {
        return _totalOperatorNetworkShares[network].upperLookupRecent(Time.timestamp());
    }

    /**
     * @inheritdoc INetworkRestakingDelegator
     */
    function operatorNetworkSharesIn(
        address network,
        address operator,
        uint48 duration
    ) public view returns (uint256) {
        return _operatorNetworkShares[network][operator].upperLookupRecent(Time.timestamp() + duration);
    }

    /**
     * @inheritdoc INetworkRestakingDelegator
     */
    function operatorNetworkShares(address network, address operator) public view returns (uint256) {
        return _operatorNetworkShares[network][operator].upperLookupRecent(Time.timestamp());
    }

    /**
     * @inheritdoc IDelegator
     */
    function networkStakeIn(address network, uint48 duration) public view returns (uint256) {
        return Math.min(IVault(vault).totalSupplyIn(duration), networkLimitIn(network, duration));
    }

    /**
     * @inheritdoc IDelegator
     */
    function networkStake(address network) public view returns (uint256) {
        return Math.min(IVault(vault).totalSupply(), networkLimit(network));
    }

    /**
     * @inheritdoc IDelegator
     */
    function operatorNetworkStakeIn(address network, address operator, uint48 duration) public view returns (uint256) {
        return operatorNetworkSharesIn(network, operator, duration).mulDiv(
            networkStakeIn(network, duration), totalOperatorNetworkSharesIn(network, duration)
        );
    }

    /**
     * @inheritdoc IDelegator
     */
    function operatorNetworkStake(address network, address operator) public view returns (uint256) {
        return
            operatorNetworkShares(network, operator).mulDiv(networkStake(network), totalOperatorNetworkShares(network));
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
     * @inheritdoc INetworkRestakingDelegator
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
     * @inheritdoc INetworkRestakingDelegator
     */
    function setNetworkLimit(address network, uint256 amount) external onlyRole(NETWORK_LIMIT_SET_ROLE) {
        if (amount > maxNetworkLimit[network]) {
            revert ExceedsMaxNetworkLimit();
        }

        _networkLimit[network].push(IVault(vault).currentEpochStart() + 2 * IVault(vault).epochDuration(), amount);

        emit SetNetworkLimit(network, amount);
    }

    /**
     * @inheritdoc INetworkRestakingDelegator
     */
    function setOperatorNetworkShares(
        address network,
        address operator,
        uint256 shares
    ) external onlyRole(OPERATOR_NETWORK_SHARES_SET_ROLE) {
        uint48 timestamp = IVault(vault).currentEpochStart() + 2 * IVault(vault).epochDuration();

        _totalOperatorNetworkShares[network].push(
            timestamp,
            _totalOperatorNetworkShares[network].latest() + shares - _operatorNetworkShares[network][operator].latest()
        );

        _operatorNetworkShares[network][operator].push(timestamp, shares);

        emit SetOperatorNetworkShares(network, operator, shares);
    }

    /**
     * @inheritdoc IDelegator
     */
    function onSlash(address network, address operator, uint256 slashedAmount) external onlySlasher {
        _networkLimit[network].push(Time.timestamp(), networkLimit(network) - slashedAmount);

        uint256 operatorNetworkShares_ = operatorNetworkShares(network, operator);
        uint256 operatorSlashedShares =
            slashedAmount.mulDiv(operatorNetworkShares_, operatorNetworkStake(network, operator), Math.Rounding.Ceil);

        _totalOperatorNetworkShares[network].push(
            Time.timestamp(), totalOperatorNetworkShares(network) - operatorSlashedShares
        );

        _operatorNetworkShares[network][operator].push(Time.timestamp(), operatorNetworkShares_ - operatorSlashedShares);

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
        _grantRole(OPERATOR_NETWORK_SHARES_SET_ROLE, vaultOwner);
    }
}
