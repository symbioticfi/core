// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IVaultStorage} from "src/interfaces/IVaultStorage.sol";
import {IMigratableEntity} from "src/interfaces/IMigratableEntity.sol";

import {MigratableEntity} from "./base/MigratableEntity.sol";
import {ERC6372} from "./utils/ERC6372.sol";
import {Checkpoints} from "./libraries/Checkpoints.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract VaultStorage is
    MigratableEntity,
    ERC6372,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    IVaultStorage
{
    /**
     * @dev Some dead address to transfer slashed tokens to.
     */
    address internal constant DEAD = address(0xdEaD);

    /**
     * @inheritdoc IVaultStorage
     */
    uint256 public constant ADMIN_FEE_BASE = 10_000;

    /**
     * @inheritdoc IVaultStorage
     */
    bytes32 public constant NETWORK_LIMIT_SET_ROLE = keccak256("NETWORK_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IVaultStorage
     */
    bytes32 public constant OPERATOR_LIMIT_SET_ROLE = keccak256("OPERATOR_LIMIT_SET_ROLE");

    /**
     * @inheritdoc IVaultStorage
     */
    bytes32 public constant ADMIN_FEE_SET_ROLE = keccak256("ADMIN_FEE_SET_ROLE");

    /**
     * @inheritdoc IVaultStorage
     */
    bytes32 public constant DEPOSIT_WHITELIST_SET_ROLE = keccak256("DEPOSIT_WHITELIST_SET_ROLE");
    /**
     * @inheritdoc IVaultStorage
     */
    bytes32 public constant DEPOSITOR_WHITELIST_ROLE = keccak256("DEPOSITOR_WHITELIST_ROLE");

    /**
     * @inheritdoc IVaultStorage
     */
    address public immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc IVaultStorage
     */
    address public immutable OPERATOR_REGISTRY;

    /**
     * @inheritdoc IVaultStorage
     */
    address public immutable NETWORK_MIDDLEWARE_PLUGIN;

    /**
     * @inheritdoc IVaultStorage
     */
    address public immutable NETWORK_OPT_IN_PLUGIN;

    /**
     * @inheritdoc IVaultStorage
     */
    address public collateral;

    /**
     * @inheritdoc IVaultStorage
     */
    uint48 public epochDurationInit;

    /**
     * @inheritdoc IVaultStorage
     */
    uint48 public epochDuration;

    /**
     * @inheritdoc IVaultStorage
     */
    uint48 public vetoDuration;

    /**
     * @inheritdoc IVaultStorage
     */
    uint48 public slashDuration;

    /**
     * @inheritdoc IVaultStorage
     */
    string public metadataURL;

    /**
     * @inheritdoc IVaultStorage
     */
    uint256 public adminFee;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(address token => uint256 amount) public claimableAdminFee;

    /**
     * @inheritdoc IVaultStorage
     */
    bool public depositWhitelist;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(address account => bool value) public isDepositorWhitelisted;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(address account => uint48 timestamp) public firstDepositAt;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(uint256 epoch => uint256 amount) public withdrawals;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(uint256 epoch => uint256 amount) public withdrawalsShares;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(uint256 epoch => mapping(address account => uint256 amount)) public withdrawalsSharesOf;

    /**
     * @inheritdoc IVaultStorage
     */
    SlashRequest[] public slashRequests;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(address token => RewardDistribution[] rewards_) public rewards;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(address account => mapping(address token => uint256 rewardIndex)) public lastUnclaimedReward;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(address operator => uint48 timestamp) public operatorOptOutAt;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(address network => mapping(address resolver => uint256 amount)) public maxNetworkLimit;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(address network => mapping(address resolver => DelayedLimit)) public nextNetworkLimit;

    /**
     * @inheritdoc IVaultStorage
     */
    mapping(address operator => mapping(address network => DelayedLimit)) public nextOperatorLimit;

    Checkpoints.Trace256 internal _activeShares;

    Checkpoints.Trace256 internal _activeSupplies;

    mapping(address account => Checkpoints.Trace256 shares) internal _activeSharesOf;

    mapping(uint48 timestamp => uint256 amount) internal _activeSharesCache;

    mapping(uint48 timestamp => uint256 amount) internal _activeSuppliesCache;

    mapping(address network => mapping(address resolver => bool value)) internal _isNetworkOptedIn;

    mapping(address operator => bool value) internal _isOperatorOptedIn;

    mapping(address network => mapping(address resolver => Limit limit)) internal _networkLimit;

    mapping(address operator => mapping(address network => Limit limit)) internal _operatorLimit;

    constructor(
        address networkRegistry,
        address operatorRegistry,
        address networkMiddlewarePlugin,
        address networkOptInPlugin
    ) {
        NETWORK_REGISTRY = networkRegistry;
        OPERATOR_REGISTRY = operatorRegistry;
        NETWORK_MIDDLEWARE_PLUGIN = networkMiddlewarePlugin;
        NETWORK_OPT_IN_PLUGIN = networkOptInPlugin;
    }

    /**
     * @inheritdoc IMigratableEntity
     */
    function initialize(
        uint64 version_,
        bytes memory data
    ) public override(MigratableEntity, IMigratableEntity) reinitializer(version_) {
        (IVaultStorage.InitParams memory params) = abi.decode(data, (IVaultStorage.InitParams));

        if (params.epochDuration == 0) {
            revert InvalidEpochDuration();
        }

        if (params.vetoDuration + params.slashDuration > params.epochDuration) {
            revert InvalidSlashDuration();
        }

        if (params.adminFee > ADMIN_FEE_BASE) {
            revert InvalidAdminFee();
        }

        __ReentrancyGuard_init();

        _initialize(params.owner);

        metadataURL = params.metadataURL;
        collateral = params.collateral;

        epochDurationInit = clock();
        epochDuration = params.epochDuration;

        vetoDuration = params.vetoDuration;
        slashDuration = params.slashDuration;

        adminFee = params.adminFee;
        depositWhitelist = params.depositWhitelist;

        _grantRole(DEFAULT_ADMIN_ROLE, params.owner);
        _grantRole(NETWORK_LIMIT_SET_ROLE, params.owner);
        _grantRole(OPERATOR_LIMIT_SET_ROLE, params.owner);
        if (params.depositWhitelist) {
            _grantRole(DEPOSITOR_WHITELIST_ROLE, params.owner);
        }
    }

    /**
     * @inheritdoc IMigratableEntity
     */
    function migrate(bytes memory) public override(MigratableEntity, IMigratableEntity) {
        revert();
    }
}
