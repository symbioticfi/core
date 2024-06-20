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
    bytes32 public constant OPERATOR_NETWORK_LIMIT_SET_ROLE = keccak256("OPERATOR_NETWORK_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IDelegator
     */
    address public vault;

    /**
     * @inheritdoc IFullRestakingDelegator
     */
    mapping(address operator => mapping(address network => DelayedLimit)) public nextOperatorNetworkLimit;

    mapping(address operator => mapping(address network => Limit limit)) internal _operatorNetworkLimit;

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
    function operatorNetworkLimitIn(address operator, address network, uint48 duration) public view returns (uint256) {
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
    function slashableAmountIn(address network, address operator, uint48 duration) public view returns (uint256) {
        return Math.min(IVault(vault).totalSupplyIn(duration), operatorNetworkLimitIn(operator, network, duration));
    }

    /**
     * @inheritdoc IDelegator
     */
    function slashableAmount(address network, address operator) public view returns (uint256) {
        return Math.min(IVault(vault).totalSupply(), operatorNetworkLimit(operator, network));
    }

    /**
     * @inheritdoc IDelegator
     */
    function minStakeDuring(address network, address operator, uint48 duration) external view returns (uint256) {
        return Math.min(
            IVault(vault).activeSupply(),
            Math.min(operatorNetworkLimit(operator, network), operatorNetworkLimitIn(operator, network, duration))
        );
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
    function onSlash(address network, address operator, uint256 slashedAmount) external onlySlasher {
        uint256 operatorNetworkLimit_ = operatorNetworkLimit(operator, network);

        _updateLimit(_operatorNetworkLimit[operator][network], nextOperatorNetworkLimit[operator][network]);

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
