// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IRewardsPlugin} from "src/interfaces/plugins/IRewardsPlugin.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";
import {IVault} from "src/interfaces/IVault.sol";

import {ERC4626Math} from "src/contracts/libraries/ERC4626Math.sol";

import {Plugin} from "src/contracts/base/Plugin.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract RewardsPlugin is Plugin, ReentrancyGuard, IRewardsPlugin {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /**
     * @inheritdoc IRewardsPlugin
     */
    mapping(address vault => mapping(address token => RewardDistribution[] rewards_)) public rewards;

    /**
     * @inheritdoc IRewardsPlugin
     */
    mapping(address vault => mapping(address account => mapping(address token => uint256 rewardIndex))) public
        lastUnclaimedReward;

    /**
     * @inheritdoc IRewardsPlugin
     */
    mapping(address vault => mapping(address token => uint256 amount)) public claimableAdminFee;

    mapping(address vault => mapping(uint48 timestamp => uint256 amount)) internal _activeSharesCache;

    mapping(address vault => mapping(uint48 timestamp => uint256 amount)) internal _activeSuppliesCache;

    /**
     * @inheritdoc IRewardsPlugin
     */
    address public immutable VAULT_REGISTRY;

    modifier isVault(address account) {
        if (!IRegistry(VAULT_REGISTRY).isEntity(account)) {
            revert NotVault();
        }
        _;
    }

    constructor(address networkRegistry, address vaultRegistry) Plugin(networkRegistry) {
        VAULT_REGISTRY = vaultRegistry;
    }

    /**
     * @inheritdoc IRewardsPlugin
     */
    function rewardsLength(address vault, address token) external view isVault(vault) returns (uint256) {
        return rewards[vault][token].length;
    }

    /**
     * @inheritdoc IRewardsPlugin
     */
    function distributeReward(
        address vault,
        address network,
        address token,
        uint256 amount,
        uint48 timestamp,
        uint256 acceptedAdminFee
    ) external nonReentrant isVault(vault) returns (uint256 rewardIndex) {
        if (!IRegistry(REGISTRY).isEntity(network)) {
            revert NotNetwork();
        }

        if (timestamp >= Time.timestamp()) {
            revert InvalidRewardTimestamp();
        }

        if (acceptedAdminFee < IVault(vault).adminFee()) {
            revert UnacceptedAdminFee();
        }

        if (_activeSharesCache[vault][timestamp] == 0) {
            uint256 activeShares_ = IVault(vault).activeSharesAt(timestamp);
            uint256 activeSupply_ = IVault(vault).activeSupplyAt(timestamp);

            if (activeShares_ == 0 || activeSupply_ == 0) {
                revert InvalidRewardTimestamp();
            }

            _activeSharesCache[vault][timestamp] = activeShares_;
            _activeSuppliesCache[vault][timestamp] = activeSupply_;
        }

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        amount = IERC20(token).balanceOf(address(this)) - balanceBefore;

        if (amount == 0) {
            revert InsufficientReward();
        }

        uint256 adminFeeAmount = amount.mulDiv(IVault(vault).adminFee(), IVault(vault).ADMIN_FEE_BASE());
        claimableAdminFee[vault][token] += adminFeeAmount;

        rewardIndex = rewards[vault][token].length;

        rewards[vault][token].push(
            RewardDistribution({
                network: network,
                amount: amount - adminFeeAmount,
                timestamp: timestamp,
                creation: Time.timestamp()
            })
        );

        emit DistributeReward(vault, token, rewardIndex, network, amount, timestamp);
    }

    /**
     * @inheritdoc IRewardsPlugin
     */
    function claimRewards(
        address vault,
        address recipient,
        address token,
        uint256 maxRewards,
        uint32[] calldata activeSharesOfHints
    ) external {
        uint48 firstDepositAt_ = IVault(vault).firstDepositAt(msg.sender);
        if (firstDepositAt_ == 0) {
            revert NoDeposits();
        }

        RewardDistribution[] storage rewardsByToken = rewards[vault][token];
        uint256 rewardIndex = lastUnclaimedReward[vault][msg.sender][token];
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

        mapping(uint48 => uint256) storage _activeSharesCacheByVault = _activeSharesCache[vault];
        mapping(uint48 => uint256) storage _activeSuppliesCacheByVault = _activeSuppliesCache[vault];

        uint256 amount;
        for (uint256 j; j < rewardsToClaim;) {
            RewardDistribution storage reward = rewardsByToken[rewardIndex];

            uint256 claimedAmount;
            if (reward.timestamp >= firstDepositAt_) {
                uint256 activeSupply_ = _activeSuppliesCacheByVault[reward.timestamp];
                uint256 activeSharesOf_ = hasHints
                    ? IVault(vault).activeSharesOfAtHint(msg.sender, reward.timestamp, activeSharesOfHints[j])
                    : IVault(vault).activeSharesOfAt(msg.sender, reward.timestamp);
                uint256 activeBalanceOf_ = ERC4626Math.previewRedeem(
                    activeSharesOf_, activeSupply_, _activeSharesCacheByVault[reward.timestamp]
                );

                claimedAmount = activeBalanceOf_.mulDiv(reward.amount, activeSupply_);
                amount += claimedAmount;
            }

            emit ClaimReward(vault, token, rewardIndex, msg.sender, recipient, claimedAmount);

            unchecked {
                ++j;
                ++rewardIndex;
            }
        }

        lastUnclaimedReward[vault][msg.sender][token] = rewardIndex;

        if (amount != 0) {
            IERC20(token).safeTransfer(recipient, amount);
        }
    }

    /**
     * @inheritdoc IRewardsPlugin
     */
    function claimAdminFee(address vault, address recipient, address token) external {
        if (Ownable(vault).owner() != msg.sender) {
            revert NotOwner();
        }

        uint256 claimableAdminFee_ = claimableAdminFee[vault][token];
        if (claimableAdminFee_ == 0) {
            revert InsufficientAdminFee();
        }

        claimableAdminFee[vault][token] = 0;

        IERC20(token).safeTransfer(recipient, claimableAdminFee_);

        emit ClaimAdminFee(vault, token, claimableAdminFee_);
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
