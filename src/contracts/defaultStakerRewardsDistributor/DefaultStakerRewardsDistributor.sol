// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IDefaultStakerRewardsDistributor} from
    "src/interfaces/defaultStakerRewardsDistributor/IDefaultStakerRewardsDistributor.sol";
import {INetworkMiddlewareService} from "src/interfaces/service/INetworkMiddlewareService.sol";
import {IRegistry} from "src/interfaces/common/IRegistry.sol";
import {IStakerRewardsDistributor} from "src/interfaces/stakerRewardsDistributor/IStakerRewardsDistributor.sol";
import {IVault} from "src/interfaces/vault/IVault.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract DefaultStakerRewardsDistributor is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    IDefaultStakerRewardsDistributor
{
    using SafeERC20 for IERC20;
    using Math for uint256;

    /**
     * @inheritdoc IStakerRewardsDistributor
     */
    uint64 public constant version = 1;

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    uint256 public constant ADMIN_FEE_BASE = 10_000;

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    bytes32 public constant ADMIN_FEE_CLAIM_ROLE = keccak256("ADMIN_FEE_CLAIM_ROLE");

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    bytes32 public constant NETWORK_WHITELIST_ROLE = keccak256("NETWORK_WHITELIST_ROLE");

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    bytes32 public constant ADMIN_FEE_SET_ROLE = keccak256("ADMIN_FEE_SET_ROLE");

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    address public immutable NETWORK_REGISTRY;

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    address public immutable VAULT_FACTORY;

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    address public immutable NETWORK_MIDDLEWARE_SERVICE;

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    address public VAULT;

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    uint256 public adminFee;

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    mapping(address account => bool values) public isNetworkWhitelisted;

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    mapping(address token => RewardDistribution[] rewards_) public rewards;

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    mapping(address account => mapping(address token => uint256 rewardIndex)) public lastUnclaimedReward;

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    mapping(address token => uint256 amount) public claimableAdminFee;

    mapping(uint48 timestamp => uint256 amount) private _activeSharesCache;

    modifier onlyVaultOwner() {
        if (Ownable(VAULT).owner() != msg.sender) {
            revert NotVaultOwner();
        }
        _;
    }

    constructor(address networkRegistry, address vaultFactory, address networkMiddlewareService) {
        _disableInitializers();

        NETWORK_REGISTRY = networkRegistry;
        VAULT_FACTORY = vaultFactory;
        NETWORK_MIDDLEWARE_SERVICE = networkMiddlewareService;
    }

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    function rewardsLength(address token) external view returns (uint256) {
        return rewards[token].length;
    }

    function initialize(address vault) external initializer {
        if (!IRegistry(VAULT_FACTORY).isEntity(vault)) {
            revert NotVault();
        }

        __ReentrancyGuard_init();

        VAULT = vault;

        address vaultOwner = Ownable(vault).owner();
        _grantRole(DEFAULT_ADMIN_ROLE, vaultOwner);
        _grantRole(ADMIN_FEE_CLAIM_ROLE, vaultOwner);
        _grantRole(NETWORK_WHITELIST_ROLE, vaultOwner);
        _grantRole(ADMIN_FEE_SET_ROLE, vaultOwner);
    }

    /**
     * @inheritdoc IStakerRewardsDistributor
     */
    function distributeReward(address network, address token, uint256 amount, uint48 timestamp) external nonReentrant {
        if (INetworkMiddlewareService(NETWORK_MIDDLEWARE_SERVICE).middleware(network) != msg.sender) {
            revert NotNetworkMiddleware();
        }

        if (!isNetworkWhitelisted[network]) {
            revert NotWhitelistedNetwork();
        }

        if (timestamp >= Time.timestamp()) {
            revert InvalidRewardTimestamp();
        }

        if (_activeSharesCache[timestamp] == 0) {
            uint256 activeShares_ = IVault(VAULT).activeSharesAt(timestamp);
            uint256 activeSupply_ = IVault(VAULT).activeSupplyAt(timestamp);

            if (activeShares_ == 0 || activeSupply_ == 0) {
                revert InvalidRewardTimestamp();
            }

            _activeSharesCache[timestamp] = activeShares_;
        }

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        amount = IERC20(token).balanceOf(address(this)) - balanceBefore;

        if (amount == 0) {
            revert InsufficientReward();
        }

        uint256 adminFeeAmount = amount.mulDiv(adminFee, ADMIN_FEE_BASE);
        claimableAdminFee[token] += adminFeeAmount;

        rewards[token].push(
            RewardDistribution({
                network: network,
                amount: amount - adminFeeAmount,
                timestamp: timestamp,
                creation: Time.timestamp()
            })
        );

        emit DistributeReward(network, token, amount, timestamp);
    }

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    function claimRewards(
        address recipient,
        address token,
        uint256 maxRewards,
        uint32[] calldata activeSharesOfHints
    ) external {
        RewardDistribution[] storage rewardsByToken = rewards[token];
        uint256 rewardIndex = lastUnclaimedReward[msg.sender][token];

        uint256 rewardsToClaim = Math.min(maxRewards, rewardsByToken.length - rewardIndex);

        if (rewardsToClaim == 0) {
            revert NoRewardsToClaim();
        }

        bool hasHints = activeSharesOfHints.length == rewardsToClaim;
        if (!hasHints && activeSharesOfHints.length != 0) {
            revert InvalidHintsLength();
        }

        uint256 amount;
        for (uint256 j; j < rewardsToClaim;) {
            RewardDistribution storage reward = rewardsByToken[rewardIndex];

            uint256 activeSharesOf_ = hasHints
                ? IVault(VAULT).activeSharesOfAtHint(msg.sender, reward.timestamp, activeSharesOfHints[j])
                : IVault(VAULT).activeSharesOfAt(msg.sender, reward.timestamp);

            uint256 claimedAmount = activeSharesOf_.mulDiv(reward.amount, _activeSharesCache[reward.timestamp]);
            amount += claimedAmount;

            emit ClaimReward(token, rewardIndex, msg.sender, recipient, claimedAmount);

            unchecked {
                ++j;
                ++rewardIndex;
            }
        }

        lastUnclaimedReward[msg.sender][token] = rewardIndex;

        if (amount != 0) {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    function claimAdminFee(address recipient, address token) external onlyRole(ADMIN_FEE_CLAIM_ROLE) {
        uint256 claimableAdminFee_ = claimableAdminFee[token];
        if (claimableAdminFee_ == 0) {
            revert InsufficientAdminFee();
        }

        claimableAdminFee[token] = 0;

        IERC20(token).safeTransfer(recipient, claimableAdminFee_);

        emit ClaimAdminFee(token, claimableAdminFee_);
    }

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
     */
    function setNetworkWhitelistStatus(address network, bool status) external onlyRole(NETWORK_WHITELIST_ROLE) {
        if (!IRegistry(NETWORK_REGISTRY).isEntity(network)) {
            revert NotNetwork();
        }

        if (isNetworkWhitelisted[network] == status) {
            revert AlreadySet();
        }

        isNetworkWhitelisted[network] = status;

        emit SetNetworkWhitelistStatus(network, status);
    }

    /**
     * @inheritdoc IDefaultStakerRewardsDistributor
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
}
