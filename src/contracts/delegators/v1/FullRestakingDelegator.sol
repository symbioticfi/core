// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {NonMigratableEntity} from "src/contracts/base/NonMigratableEntity.sol";

import {IFullRestakingDelegator} from "src/interfaces/delegators/v1/IFullRestakingDelegator.sol";
import {IDelegator} from "src/interfaces/delegators/v1/IDelegator.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";
import {IVault} from "src/interfaces/vault/v1/IVault.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract FullRestakingDelegator is NonMigratableEntity, AccessControlUpgradeable, IFullRestakingDelegator {
    /**
     * @inheritdoc IDelegator
     */
    uint64 public constant VERSION = 1;

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
    bytes32 public constant NETWORK_RESOLVER_LIMIT_SET_ROLE = keccak256("NETWORK_RESOLVER_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    bytes32 public constant OPERATOR_NETWORK_LIMIT_SET_ROLE = keccak256("OPERATOR_NETWORK_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IDelegator
     */
    address public vault;

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    mapping(address network => mapping(address resolver => uint256 amount)) public
        maxNetworkResolverLimit;

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    mapping(address network => mapping(address resolver => DelayedLimit)) public
        nextNetworkResolverLimit;

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    mapping(address operator => mapping(address network => DelayedLimit)) public
        nextOperatorNetworkLimit;

    mapping(address network => mapping(address resolver => Limit limit)) internal
        _networkResolverLimit;

     mapping(address operator => mapping(address network => Limit limit)) internal
        _operatorNetworkLimit;

    modifier onlySlasher() {
        if (IVault(vault).slasher() != msg.sender) {
            revert NotSlasher();
        }
        _;
    }

    constructor(address networkRegistry, address vaultFactory) {
        NETWORK_REGISTRY = networkRegistry;
        VAULT_FACTORY = vaultFactory;
    }

    /**
     * @inheritdoc IDelegator
     */
    function networkResolverLimitIn(
        address network,
        address resolver,
        uint48 duration
    ) public view returns (uint256) {
        return _getLimitAt(
            _networkResolverLimit[network][resolver],
            nextNetworkResolverLimit[network][resolver],
            Time.timestamp() + duration
        );
    }

    /**
     * @inheritdoc IDelegator
     */
    function networkResolverLimit(address network, address resolver) public view returns (uint256) {
        return networkResolverLimitIn(network, resolver, 0);
    }

    /**
     * @inheritdoc IDelegator
     */
    function operatorNetworkLimitIn(
        address operator,
        address network,
        uint48 duration
    ) public view returns (uint256) {
        return _getLimitAt(
            _operatorNetworkLimit[operator][network],
            nextOperatorNetworkLimit[operator][network],
            Time.timestamp() + duration
        );
    }

    /**
     * @inheritdoc IDelegator
     */
    function operatorNetworkLimit(address operator, address network) public view returns (uint256) {
        return operatorNetworkLimitIn(operator, network, 0);
    }

    /**
     * @inheritdoc IDelegator
     */
    function slashableAmountIn(
        address network,
        address resolver,
        address operator,
        uint48 duration
    ) public view returns (uint256) {
        return Math.min(
            IVault(vault).totalSupplyIn(duration),
            Math.min(
                networkResolverLimitIn(network, resolver, duration),
                operatorNetworkLimitIn(operator, network, duration)
            )
        );
    }

    /**
     * @inheritdoc IDelegator
     */
    function slashableAmount(address network, address resolver, address operator) public view returns (uint256) {
        return Math.min(
            IVault(vault).totalSupply(),
            Math.min(
                networkResolverLimit(network, resolver),
                operatorNetworkLimit(operator, network)
            )
        );
    }

    /**
     * @inheritdoc IDelegator
     */
    function minStakeDuring(
        address network,
        address resolver,
        address operator,
        uint48 duration
    ) external view returns (uint256) {
        return Math.min(
            IVault(vault).activeSupply(),
            Math.min(
                Math.min(
                    networkResolverLimit(network, resolver),
                    networkResolverLimitIn(network, resolver, duration)
                ),
                Math.min(
                    operatorNetworkLimit(operator, network),
                    operatorNetworkLimitIn(operator, network, duration)
                )
            )
        );
    }

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    function setMaxNetworkResolverLimit(address resolver, uint256 amount) external {
        if (maxNetworkResolverLimit[msg.sender][resolver] == amount) {
            revert AlreadySet();
        }

        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        maxNetworkResolverLimit[msg.sender][resolver] = amount;

        Limit storage limit = _networkResolverLimit[msg.sender][resolver];
        DelayedLimit storage nextLimit = nextNetworkResolverLimit[msg.sender][resolver];

        _updateLimit(limit, nextLimit);

        if (limit.amount > amount) {
            limit.amount = amount;
        }
        if (nextLimit.amount > amount) {
            nextLimit.amount = amount;
        }

        emit SetMaxNetworkResolverLimit(msg.sender, resolver, amount);
    }

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    function setNetworkResolverLimit(
        address network,
        address resolver,
        uint256 amount
    ) external onlyRole(NETWORK_RESOLVER_LIMIT_SET_ROLE) {
        if (amount > maxNetworkResolverLimit[network][resolver]) {
            revert ExceedsMaxNetworkResolverLimit();
        }

        Limit storage limit = _networkResolverLimit[network][resolver];
        DelayedLimit storage nextLimit = nextNetworkResolverLimit[network][resolver];

        _setLimit(limit, nextLimit, amount);

        emit SetNetworkResolverLimit(network, resolver, amount);
    }

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    function setOperatorNetworkLimit(
        address operator,
        address network,
        uint256 amount
    ) external onlyRole(OPERATOR_NETWORK_LIMIT_SET_ROLE) {
        Limit storage limit = _operatorNetworkLimit[operator][network];
        DelayedLimit storage nextLimit = nextOperatorNetworkLimit[operator][network];

        _setLimit(limit, nextLimit, amount);

        emit SetOperatorNetworkLimit(operator, network, amount);
    }

    /**
     * @inheritdoc IDelegator
     */
    function onSlash(
        address network,
        address resolver,
        address operator,
        uint256 slashedAmount
    ) external onlySlasher {
        uint256 networkResolverLimit_ = networkResolverLimit(network, resolver);
        uint256 operatorNetworkLimit_ = operatorNetworkLimit(operator, network);

        _updateLimit(
            _networkResolverLimit[network][resolver], nextNetworkResolverLimit[network][resolver]
        );
        _updateLimit(
            _operatorNetworkLimit[operator][network], nextOperatorNetworkLimit[operator][network]
        );

        if (networkResolverLimit_ != type(uint256).max) {
            _networkResolverLimit[network][resolver].amount = networkResolverLimit_ - slashedAmount;
        }
        if (operatorNetworkLimit_ != type(uint256).max) {
            _operatorNetworkLimit[operator][network].amount = operatorNetworkLimit_ - slashedAmount;
        }
    }

    function _initialize(bytes memory data) internal override {
        (IFullRestakingDelegator.InitParams memory params) = abi.decode(data, (IFullRestakingDelegator.InitParams));

        if (!IRegistry(VAULT_FACTORY).isEntity(params.vault)) {
            revert NotVault();
        }

        vault = params.vault;

        address vaultOwner = Ownable(params.vault).owner();
        _grantRole(DEFAULT_ADMIN_ROLE, vaultOwner);
        _grantRole(NETWORK_RESOLVER_LIMIT_SET_ROLE, vaultOwner);
        _grantRole(OPERATOR_NETWORK_LIMIT_SET_ROLE, vaultOwner);
    }

    function _getLimitAt(
        Limit storage limit,
        DelayedLimit storage nextLimit,
        uint48 timestamp
    ) private view returns (uint256) {
        if (nextLimit.timestamp == 0 || timestamp < nextLimit.timestamp) {
            return limit.amount;
        }
        return nextLimit.amount;
    }

    function _setLimit(Limit storage limit, DelayedLimit storage nextLimit, uint256 amount) private {
        _updateLimit(limit, nextLimit);

        if (amount < limit.amount) {
            nextLimit.amount = amount;
            nextLimit.timestamp = IVault(vault).currentEpochStart() + 2 * IVault(vault).epochDuration();
        } else {
            limit.amount = amount;
            nextLimit.amount = 0;
            nextLimit.timestamp = 0;
        }
    }

    function _updateLimit(Limit storage limit, DelayedLimit storage nextLimit) internal {
        if (nextLimit.timestamp != 0 && nextLimit.timestamp <= Time.timestamp()) {
            limit.amount = nextLimit.amount;
            nextLimit.timestamp = 0;
            nextLimit.amount = 0;
        }
    }
}
