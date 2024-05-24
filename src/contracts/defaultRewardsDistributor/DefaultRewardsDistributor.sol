// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RewardsDistributorBase} from "src/contracts/base/RewardsDistributorBase.sol";
import {RewardsDistributor} from "src/contracts/base/RewardsDistributor.sol";

import {IDefaultRewardsDistributor} from "src/interfaces/defaultRewardsDistributor/IDefaultRewardsDistributor.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";
import {IRewardsDistributorBase} from "src/interfaces/base/IRewardsDistributorBase.sol";
import {IRewardsDistributor} from "src/interfaces/base/IRewardsDistributor.sol";
import {IVault} from "src/interfaces/vault/v1/IVault.sol";

import {ERC4626Math} from "src/contracts/libraries/ERC4626Math.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract DefaultRewardsDistributor is RewardsDistributor, ReentrancyGuardUpgradeable, IDefaultRewardsDistributor {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /**
     * @inheritdoc IDefaultRewardsDistributor
     */
    address public immutable VAULT_REGISTRY;

    address private _VAULT;

    /**
     * @inheritdoc IDefaultRewardsDistributor
     */
    mapping(address token => RewardDistribution[] rewards_) public rewards;

    /**
     * @inheritdoc IDefaultRewardsDistributor
     */
    mapping(address account => mapping(address token => uint256 rewardIndex)) public lastUnclaimedReward;

    /**
     * @inheritdoc IDefaultRewardsDistributor
     */
    mapping(address token => uint256 amount) public claimableAdminFee;

    mapping(uint48 timestamp => uint256 amount) internal _activeSharesCache;

    mapping(uint48 timestamp => uint256 amount) internal _activeSuppliesCache;

    constructor(address networkRegistry, address vaultRegistry) RewardsDistributor(networkRegistry) {
        _disableInitializers();

        VAULT_REGISTRY = vaultRegistry;
    }

    /**
     * @inheritdoc IRewardsDistributorBase
     */
    function VAULT() public view override(RewardsDistributorBase, IRewardsDistributorBase) returns (address) {
        return _VAULT;
    }

    function initialize(address vault) external initializer {
        if (!IRegistry(VAULT_REGISTRY).isEntity(vault)) {
            revert NotVault();
        }

        __ReentrancyGuard_init();

        _VAULT = vault;
    }

    /**
     * @inheritdoc IDefaultRewardsDistributor
     */
    function rewardsLength(address token) external view returns (uint256) {
        return rewards[token].length;
    }

    /**
     * @inheritdoc IRewardsDistributor
     */
    function distributeReward(
        address network,
        address token,
        uint256 amount,
        uint48 timestamp
    ) external override(RewardsDistributor, IRewardsDistributor) nonReentrant checkNetwork(network) {
        if (timestamp >= Time.timestamp()) {
            revert InvalidRewardTimestamp();
        }

        if (_activeSharesCache[timestamp] == 0) {
            uint256 activeShares_ = IVault(VAULT()).activeSharesAt(timestamp);
            uint256 activeSupply_ = IVault(VAULT()).activeSupplyAt(timestamp);

            if (activeShares_ == 0 || activeSupply_ == 0) {
                revert InvalidRewardTimestamp();
            }

            _activeSharesCache[timestamp] = activeShares_;
            _activeSuppliesCache[timestamp] = activeSupply_;
        }

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        amount = IERC20(token).balanceOf(address(this)) - balanceBefore;

        if (amount == 0) {
            revert InsufficientReward();
        }

        uint256 adminFeeAmount = amount.mulDiv(IVault(VAULT()).adminFee(), IVault(VAULT()).ADMIN_FEE_BASE());
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
     * @inheritdoc IDefaultRewardsDistributor
     */
    function claimRewards(
        address recipient,
        address token,
        uint256 maxRewards,
        uint32[] calldata activeSharesOfHints
    ) external {
        uint48 firstDepositAt_ = IVault(VAULT()).firstDepositAt(msg.sender);
        if (firstDepositAt_ == 0) {
            revert NoDeposits();
        }

        RewardDistribution[] storage rewardsByToken = rewards[token];
        uint256 rewardIndex = lastUnclaimedReward[msg.sender][token];
        if (rewardIndex == 0) {
            rewardIndex = _firstUnclaimedReward(rewardsByToken, firstDepositAt_);
        }

        uint256 rewardsToClaim = Math.min(maxRewards, rewardsByToken.length - rewardIndex);

        if (rewardsToClaim == 0) {
            revert NoRewardsToClaim();
        }

        bool hasHints = activeSharesOfHints.length == rewardsToClaim;
        if (!hasHints && activeSharesOfHints.length != 0) {
            revert InvalidHintsLength();
        }

        mapping(uint48 => uint256) storage _activeSharesCacheByVault = _activeSharesCache;
        mapping(uint48 => uint256) storage _activeSuppliesCacheByVault = _activeSuppliesCache;

        uint256 amount;
        for (uint256 j; j < rewardsToClaim;) {
            RewardDistribution storage reward = rewardsByToken[rewardIndex];

            uint256 claimedAmount;
            if (reward.timestamp >= firstDepositAt_) {
                uint256 activeSupply_ = _activeSuppliesCacheByVault[reward.timestamp];
                uint256 activeSharesOf_ = hasHints
                    ? IVault(VAULT()).activeSharesOfAtHint(msg.sender, reward.timestamp, activeSharesOfHints[j])
                    : IVault(VAULT()).activeSharesOfAt(msg.sender, reward.timestamp);
                uint256 activeBalanceOf_ = ERC4626Math.previewRedeem(
                    activeSharesOf_, activeSupply_, _activeSharesCacheByVault[reward.timestamp]
                );

                claimedAmount = activeBalanceOf_.mulDiv(reward.amount, activeSupply_);
                amount += claimedAmount;
            }

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
     * @inheritdoc IDefaultRewardsDistributor
     */
    function claimAdminFee(address recipient, address token) external {
        if (Ownable(VAULT()).owner() != msg.sender) {
            revert NotOwner();
        }

        uint256 claimableAdminFee_ = claimableAdminFee[token];
        if (claimableAdminFee_ == 0) {
            revert InsufficientAdminFee();
        }

        claimableAdminFee[token] = 0;

        IERC20(token).safeTransfer(recipient, claimableAdminFee_);

        emit ClaimAdminFee(token, claimableAdminFee_);
    }

    /**
     * @dev Searches a sorted by creation time `array` and returns the first index that contains
     * a RewardDistribution structure with `creation` greater or equal to `unclaimedFrom`. If no such index exists (i.e. all
     * structures in the array are with `creation` strictly less than `unclaimedFrom`), the array length is
     * returned.
     */
    function _firstUnclaimedReward(
        RewardDistribution[] storage array,
        uint48 unclaimedFrom
    ) private view returns (uint256) {
        uint256 len = array.length;
        if (len == 0) {
            return 0;
        }

        uint256 low = 0;
        uint256 high = len;

        while (low < high) {
            uint256 mid = Math.average(low, high);

            if (array[mid].creation < unclaimedFrom) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }

        if (low < len && array[low].creation >= unclaimedFrom) {
            return low;
        } else {
            return len;
        }
    }
}
