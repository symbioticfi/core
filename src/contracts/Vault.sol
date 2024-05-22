// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IVault} from "src/interfaces/IVault.sol";
import {ICollateral} from "src/interfaces/base/ICollateral.sol";
import {IRegistry} from "src/interfaces/base/IRegistry.sol";
import {IMiddlewarePlugin} from "src/interfaces/plugins/IMiddlewarePlugin.sol";
import {INetworkOptInPlugin} from "src/interfaces/plugins/INetworkOptInPlugin.sol";

import {VaultStorage} from "./VaultStorage.sol";
import {Checkpoints} from "./libraries/Checkpoints.sol";
import {ERC4626Math} from "./libraries/ERC4626Math.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MulticallUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/MulticallUpgradeable.sol";

contract Vault is VaultStorage, MulticallUpgradeable, IVault {
    using Checkpoints for Checkpoints.Trace256;
    using SafeERC20 for IERC20;
    using Math for uint256;
    using Strings for string;

    constructor(
        address networkRegistry,
        address operatorRegistry,
        address networkMiddlewarePlugin,
        address networkOptInPlugin
    ) VaultStorage(networkRegistry, operatorRegistry, networkMiddlewarePlugin, networkOptInPlugin) {}

    /**
     * @inheritdoc IVault
     */
    function currentEpoch() public view returns (uint256) {
        return (clock() - epochDurationInit) / epochDuration;
    }

    /**
     * @inheritdoc IVault
     */
    function currentEpochStart() public view returns (uint48) {
        return uint48(epochDurationInit + currentEpoch() * epochDuration);
    }

    /**
     * @inheritdoc IVault
     */
    function totalSupply() public view returns (uint256) {
        uint256 epoch = currentEpoch();
        return activeSupply() + withdrawals[epoch] + withdrawals[epoch + 1];
    }

    /**
     * @inheritdoc IVault
     */
    function activeSharesAt(uint48 timestamp) public view returns (uint256) {
        return _activeShares.upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc IVault
     */
    function activeShares() public view returns (uint256) {
        return _activeShares.latest();
    }

    /**
     * @inheritdoc IVault
     */
    function activeSupplyAt(uint48 timestamp) public view returns (uint256) {
        return _activeSupplies.upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc IVault
     */
    function activeSupply() public view returns (uint256) {
        return _activeSupplies.latest();
    }

    /**
     * @inheritdoc IVault
     */
    function activeSharesOfAt(address account, uint48 timestamp) public view returns (uint256) {
        return _activeSharesOf[account].upperLookupRecent(timestamp);
    }

    /**
     * @inheritdoc IVault
     */
    function activeSharesOf(address account) public view returns (uint256) {
        return _activeSharesOf[account].latest();
    }

    /**
     * @inheritdoc IVault
     */
    function activeSharesOfCheckpointsLength(address account) public view returns (uint256) {
        return _activeSharesOf[account].length();
    }

    /**
     * @inheritdoc IVault
     */
    function activeSharesOfCheckpoint(address account, uint32 pos) public view returns (uint48, uint256) {
        Checkpoints.Checkpoint256 memory checkpoint = _activeSharesOf[account].at(pos);
        return (checkpoint._key, checkpoint._value);
    }

    /**
     * @inheritdoc IVault
     */
    function activeBalanceOfAt(address account, uint48 timestamp) public view returns (uint256) {
        return ERC4626Math.previewRedeem(
            activeSharesOfAt(account, timestamp), activeSupplyAt(timestamp), activeSharesAt(timestamp)
        );
    }

    /**
     * @inheritdoc IVault
     */
    function activeBalanceOf(address account) public view returns (uint256) {
        return ERC4626Math.previewRedeem(activeSharesOf(account), activeSupply(), activeShares());
    }

    /**
     * @inheritdoc IVault
     */
    function withdrawalsBalanceOf(uint256 epoch, address account) public view returns (uint256) {
        return
            ERC4626Math.previewRedeem(withdrawalsSharesOf[epoch][account], withdrawals[epoch], withdrawalsShares[epoch]);
    }

    /**
     * @inheritdoc IVault
     */
    function maxSlash(address network, address resolver, address operator) public view returns (uint256) {
        return Math.min(totalSupply(), Math.min(networkLimit(network, resolver), operatorLimit(operator, network)));
    }

    function slashRequestsLength() public view returns (uint256) {
        return slashRequests.length;
    }

    function rewardsLength(address token) public view returns (uint256) {
        return rewards[token].length;
    }

    /**
     * @inheritdoc IVault
     */
    function isNetworkOptedIn(address network, address resolver) public view returns (bool) {
        return _isNetworkOptedIn[network][resolver];
    }

    /**
     * @inheritdoc IVault
     */
    function isOperatorOptedIn(address operator) public view returns (bool) {
        if (operatorOptOutAt[operator] == 0) {
            return _isOperatorOptedIn[operator];
        }
        if (clock() < operatorOptOutAt[operator]) {
            return true;
        }
        return false;
    }

    /**
     * @inheritdoc IVault
     */
    function networkLimit(address network, address resolver) public view returns (uint256) {
        return _getLimit(_networkLimit[network][resolver], nextNetworkLimit[network][resolver]);
    }

    /**
     * @inheritdoc IVault
     */
    function operatorLimit(address operator, address network) public view returns (uint256) {
        return _getLimit(_operatorLimit[operator][network], nextOperatorLimit[operator][network]);
    }

    /**
     * @inheritdoc IVault
     */
    function deposit(address onBehalfOf, uint256 amount) external returns (uint256 shares) {
        if (depositWhitelist && !isDepositorWhitelisted[msg.sender]) {
            revert NotWhitelistedDepositor();
        }

        if (amount == 0) {
            revert InsufficientDeposit();
        }

        IERC20(collateral).transferFrom(msg.sender, address(this), amount);

        uint256 activeSupply_ = activeSupply();
        uint256 activeShares_ = activeShares();

        shares = ERC4626Math.previewDeposit(amount, activeShares_, activeSupply_);

        _activeSupplies.push(clock(), activeSupply_ + amount);
        _activeShares.push(clock(), activeShares_ + shares);
        _activeSharesOf[onBehalfOf].push(clock(), activeSharesOf(onBehalfOf) + shares);

        if (firstDepositAt[onBehalfOf] == 0) {
            firstDepositAt[onBehalfOf] = clock();
        }

        emit Deposit(msg.sender, onBehalfOf, amount, shares);
    }

    /**
     * @inheritdoc IVault
     */
    function withdraw(address claimer, uint256 amount) external returns (uint256 burnedShares, uint256 mintedShares) {
        if (amount == 0) {
            revert InsufficientWithdrawal();
        }

        uint256 activeSupply_ = activeSupply();
        uint256 activeShares_ = activeShares();
        uint256 activeSharesOf_ = activeSharesOf(msg.sender);

        burnedShares = ERC4626Math.previewWithdraw(amount, activeShares_, activeSupply_);
        if (burnedShares > activeSharesOf_) {
            revert TooMuchWithdraw();
        }

        _activeSupplies.push(clock(), activeSupply_ - amount);
        _activeShares.push(clock(), activeShares_ - burnedShares);
        _activeSharesOf[msg.sender].push(clock(), activeSharesOf_ - burnedShares);

        uint256 epoch = currentEpoch() + 1;
        uint256 withdrawals_ = withdrawals[epoch];
        uint256 withdrawalsShares_ = withdrawalsShares[epoch];

        mintedShares = ERC4626Math.previewDeposit(amount, withdrawalsShares_, withdrawals_);

        withdrawals[epoch] = withdrawals_ + amount;
        withdrawalsShares[epoch] = withdrawalsShares_ + mintedShares;
        withdrawalsSharesOf[epoch][claimer] += mintedShares;

        emit Withdraw(msg.sender, claimer, amount, burnedShares, mintedShares);
    }

    /**
     * @inheritdoc IVault
     */
    function claim(address recipient, uint256 epoch) external returns (uint256 amount) {
        if (epoch >= currentEpoch()) {
            revert InvalidEpoch();
        }

        amount = withdrawalsBalanceOf(epoch, msg.sender);

        if (amount == 0) {
            revert InsufficientClaim();
        }

        withdrawalsSharesOf[epoch][msg.sender] = 0;

        IERC20(collateral).transfer(recipient, amount);

        emit Claim(msg.sender, recipient, amount);
    }

    /**
     * @inheritdoc IVault
     */
    function requestSlash(
        address network,
        address resolver,
        address operator,
        uint256 amount
    ) external returns (uint256 slashIndex) {
        if (IMiddlewarePlugin(NETWORK_MIDDLEWARE_PLUGIN).middleware(network) != msg.sender) {
            revert NotNetworkMiddleware();
        }

        uint256 maxSlash_ = maxSlash(network, resolver, operator);

        if (amount == 0 || maxSlash_ == 0) {
            revert InsufficientSlash();
        }

        if (!isNetworkOptedIn(network, resolver)) {
            revert NetworkNotOptedIn();
        }

        if (!isOperatorOptedIn(operator)) {
            revert OperatorNotOptedInVault();
        }

        if (
            !INetworkOptInPlugin(NETWORK_OPT_IN_PLUGIN).isOperatorOptedIn(operator, network)
                && INetworkOptInPlugin(NETWORK_OPT_IN_PLUGIN).lastOperatorOptOut(operator, network)
                    < block.timestamp - epochDuration
        ) {
            revert OperatorNotOptedInNetwork();
        }

        uint256 slashAmount = Math.min(amount, maxSlash_);
        uint48 vetoDeadline = clock() + vetoDuration;
        uint48 slashDeadline = vetoDeadline + slashDuration;

        slashIndex = slashRequests.length;
        slashRequests.push(
            SlashRequest({
                network: network,
                resolver: resolver,
                operator: operator,
                amount: slashAmount,
                vetoDeadline: vetoDeadline,
                slashDeadline: slashDeadline,
                completed: false
            })
        );

        emit RequestSlash(slashIndex, network, resolver, operator, slashAmount, vetoDeadline, slashDeadline);
    }

    /**
     * @inheritdoc IVault
     */
    function executeSlash(uint256 slashIndex) external returns (uint256 slashedAmount) {
        if (slashIndex >= slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest storage request = slashRequests[slashIndex];

        if (request.vetoDeadline > clock()) {
            revert VetoPeriodNotEnded();
        }

        if (request.slashDeadline <= clock()) {
            revert SlashPeriodEnded();
        }

        if (request.completed) {
            revert SlashCompleted();
        }

        if (!isOperatorOptedIn(request.operator)) {
            revert OperatorNotOptedInVault();
        }

        request.completed = true;

        slashedAmount = Math.min(request.amount, maxSlash(request.network, request.resolver, request.operator));

        uint256 epoch = currentEpoch();
        uint256 totalSupply_ = totalSupply();
        uint256 activeSupply_ = activeSupply();
        uint256 withdrawals_ = withdrawals[epoch];
        uint256 nextWithdrawals_ = withdrawals[epoch + 1];
        uint256 networkLimit_ = networkLimit(request.network, request.resolver);
        uint256 operatorLimit_ = operatorLimit(request.operator, request.network);

        uint256 activeSlashed = slashedAmount.mulDiv(activeSupply_, totalSupply_);
        uint256 withdrawalsSlashed = slashedAmount.mulDiv(withdrawals_, totalSupply_);
        uint256 nextWithdrawalsSlashed = slashedAmount - activeSlashed - withdrawalsSlashed;
        if (nextWithdrawals_ < nextWithdrawalsSlashed) {
            nextWithdrawalsSlashed = nextWithdrawals_;
            slashedAmount = activeSlashed + withdrawalsSlashed + nextWithdrawalsSlashed;
        }

        emit ExecuteSlash(slashIndex, slashedAmount);

        if (slashedAmount == 0) {
            return 0;
        }

        _activeSupplies.push(clock(), activeSupply_ - activeSlashed);
        withdrawals[epoch] = withdrawals_ - withdrawalsSlashed;
        withdrawals[epoch + 1] = nextWithdrawals_ - nextWithdrawalsSlashed;

        _updateLimit(
            _networkLimit[request.network][request.resolver], nextNetworkLimit[request.network][request.resolver]
        );
        _updateLimit(
            _operatorLimit[request.operator][request.network], nextOperatorLimit[request.operator][request.network]
        );

        if (networkLimit_ != type(uint256).max) {
            _networkLimit[request.network][request.resolver].amount = networkLimit_ - slashedAmount;
        }
        if (operatorLimit_ != type(uint256).max) {
            _operatorLimit[request.operator][request.network].amount = operatorLimit_ - slashedAmount;
        }

        ICollateral(collateral).issueDebt(DEAD, slashedAmount);
    }

    /**
     * @inheritdoc IVault
     */
    function vetoSlash(uint256 slashIndex) external {
        if (slashIndex >= slashRequests.length) {
            revert SlashRequestNotExist();
        }

        SlashRequest storage request = slashRequests[slashIndex];

        if (request.resolver != msg.sender) {
            revert NotResolver();
        }

        if (request.vetoDeadline <= clock()) {
            revert VetoPeriodEnded();
        }

        if (request.completed) {
            revert SlashCompleted();
        }

        request.completed = true;

        emit VetoSlash(slashIndex);
    }

    /**
     * @inheritdoc IVault
     */
    function distributeReward(
        address network,
        address token,
        uint256 amount,
        uint48 timestamp,
        uint256 acceptedAdminFee
    ) external nonReentrant returns (uint256 rewardIndex) {
        if (!IRegistry(NETWORK_REGISTRY).isEntity(network)) {
            revert NotNetwork();
        }

        if (timestamp >= clock()) {
            revert InvalidRewardTimestamp();
        }

        if (acceptedAdminFee < adminFee) {
            revert UnacceptedAdminFee();
        }

        if (_activeSharesCache[timestamp] == 0) {
            uint256 activeShares_ = activeSharesAt(timestamp);
            uint256 activeSupply_ = activeSupplyAt(timestamp);

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

        uint256 adminFeeAmount = amount.mulDiv(adminFee, ADMIN_FEE_BASE);
        claimableAdminFee[token] += adminFeeAmount;

        rewardIndex = rewards[token].length;

        rewards[token].push(
            RewardDistribution({
                network: network,
                amount: amount - adminFeeAmount,
                timestamp: timestamp,
                creation: clock()
            })
        );

        emit DistributeReward(token, rewardIndex, network, amount, timestamp);
    }

    /**
     * @inheritdoc IVault
     */
    function claimRewards(
        address recipient,
        address token,
        uint256 maxRewards,
        uint32[] calldata activeSharesOfHints
    ) external {
        uint48 firstDepositAt_ = firstDepositAt[msg.sender];
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

        uint256 activeSharesOfHintsLen = activeSharesOfHints.length;
        if (activeSharesOfHintsLen != 0 && activeSharesOfHintsLen != rewardsToClaim) {
            revert InvalidHintsLength();
        }

        uint256 amount;
        for (uint256 j; j < rewardsToClaim;) {
            RewardDistribution storage reward = rewardsByToken[rewardIndex];

            uint256 claimedAmount;
            uint48 timestamp = reward.timestamp;
            if (timestamp >= firstDepositAt_) {
                uint256 activeSupply_ = _activeSuppliesCache[timestamp];
                uint256 activeSharesOf_ = activeSharesOfHintsLen != 0
                    ? _activeSharesOf[msg.sender].upperLookupRecent(timestamp, activeSharesOfHints[j])
                    : _activeSharesOf[msg.sender].upperLookupRecent(timestamp);
                uint256 activeBalanceOf_ =
                    ERC4626Math.previewRedeem(activeSharesOf_, activeSupply_, _activeSharesCache[timestamp]);

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
     * @inheritdoc IVault
     */
    function optInNetwork(address resolver, uint256 maxNetworkLimit_) external {
        if (!IRegistry(NETWORK_REGISTRY).isEntity(msg.sender)) {
            revert NotNetwork();
        }

        if (isNetworkOptedIn(msg.sender, resolver)) {
            revert NetworkAlreadyOptedIn();
        }

        if (maxNetworkLimit_ == 0) {
            revert InvalidMaxNetworkLimit();
        }

        _isNetworkOptedIn[msg.sender][resolver] = true;

        _networkLimit[msg.sender][resolver].amount = 0;
        nextNetworkLimit[msg.sender][resolver].timestamp = 0;

        maxNetworkLimit[msg.sender][resolver] = maxNetworkLimit_;

        emit OptInNetwork(msg.sender, resolver);
    }

    /**
     * @inheritdoc IVault
     */
    function optOutNetwork(address resolver) external {
        if (!isNetworkOptedIn(msg.sender, resolver)) {
            revert NetworkNotOptedIn();
        }

        _updateLimit(_networkLimit[msg.sender][resolver], nextNetworkLimit[msg.sender][resolver]);

        _isNetworkOptedIn[msg.sender][resolver] = false;

        nextNetworkLimit[msg.sender][resolver].amount = 0;
        nextNetworkLimit[msg.sender][resolver].timestamp = currentEpochStart() + 2 * epochDuration;

        maxNetworkLimit[msg.sender][resolver] = 0;

        emit OptOutNetwork(msg.sender, resolver);
    }

    /**
     * @inheritdoc IVault
     */
    function optInOperator() external {
        if (!IRegistry(OPERATOR_REGISTRY).isEntity(msg.sender)) {
            revert NotOperator();
        }

        if (isOperatorOptedIn(msg.sender)) {
            revert OperatorAlreadyOptedIn();
        }

        if (!_isOperatorOptedIn[msg.sender]) {
            _isOperatorOptedIn[msg.sender] = true;
        } else {
            operatorOptOutAt[msg.sender] = 0;
        }

        emit OptInOperator(msg.sender);
    }

    /**
     * @inheritdoc IVault
     */
    function optOutOperator() external {
        if (!isOperatorOptedIn(msg.sender)) {
            revert OperatorNotOptedIn();
        }

        operatorOptOutAt[msg.sender] = currentEpochStart() + 2 * epochDuration;

        emit OptOutOperator(msg.sender);
    }

    /**
     * @inheritdoc IVault
     */
    function setMetadataURL(string calldata metadataURL_) external onlyOwner {
        if (metadataURL.equal(metadataURL_)) {
            revert AlreadySet();
        }

        metadataURL = metadataURL_;

        emit SetMetadataURL(metadataURL_);
    }

    /**
     * @inheritdoc IVault
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

    function claimAdminFee(address recipient, address token) external onlyOwner {
        uint256 claimableAdminFee_ = claimableAdminFee[token];
        if (claimableAdminFee_ == 0) {
            revert InsufficientAdminFee();
        }

        claimableAdminFee[token] = 0;

        IERC20(token).safeTransfer(recipient, claimableAdminFee_);

        emit ClaimAdminFee(token, claimableAdminFee_);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositWhitelist(bool status) external onlyRole(DEPOSIT_WHITELIST_SET_ROLE) {
        if (depositWhitelist == status) {
            revert AlreadySet();
        }

        depositWhitelist = status;

        emit SetDepositWhitelist(status);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositorWhitelistStatus(address account, bool status) external onlyRole(DEPOSITOR_WHITELIST_ROLE) {
        if (status && !depositWhitelist) {
            revert NoDepositWhitelist();
        }

        if (isDepositorWhitelisted[account] == status) {
            revert AlreadySet();
        }

        isDepositorWhitelisted[account] = status;

        emit SetDepositorWhitelistStatus(account, status);
    }

    /**
     * @inheritdoc IVault
     */
    function setNetworkLimit(
        address network,
        address resolver,
        uint256 amount
    ) external onlyRole(NETWORK_LIMIT_SET_ROLE) {
        if (!isNetworkOptedIn(network, resolver)) {
            revert NetworkNotOptedIn();
        }

        if (amount > maxNetworkLimit[network][resolver]) {
            revert ExceedsMaxNetworkLimit();
        }

        _setLimit(_networkLimit[network][resolver], nextNetworkLimit[network][resolver], amount);

        emit SetNetworkLimit(network, resolver, amount);
    }

    /**
     * @inheritdoc IVault
     */
    function setOperatorLimit(
        address operator,
        address network,
        uint256 amount
    ) external onlyRole(OPERATOR_LIMIT_SET_ROLE) {
        Limit storage limit = _operatorLimit[operator][network];
        DelayedLimit storage nextLimit = nextOperatorLimit[operator][network];

        if (!isOperatorOptedIn(operator)) {
            if (amount != 0) {
                revert OperatorNotOptedIn();
            } else {
                limit.amount = 0;
                nextLimit.amount = 0;
                nextLimit.timestamp = 0;
            }
        } else {
            _setLimit(limit, nextLimit, amount);
        }

        emit SetOperatorLimit(operator, network, amount);
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

    function _getLimit(Limit storage limit, DelayedLimit storage nextLimit) private view returns (uint256) {
        if (nextLimit.timestamp == 0 || clock() < nextLimit.timestamp) {
            return limit.amount;
        }
        return nextLimit.amount;
    }

    function _setLimit(Limit storage limit, DelayedLimit storage nextLimit, uint256 amount) private {
        _updateLimit(limit, nextLimit);

        if (amount < limit.amount) {
            nextLimit.amount = amount;
            nextLimit.timestamp = currentEpochStart() + 2 * epochDuration;
        } else {
            limit.amount = amount;
            nextLimit.amount = 0;
            nextLimit.timestamp = 0;
        }
    }

    function _updateLimit(Limit storage limit, DelayedLimit storage nextLimit) private {
        if (nextLimit.timestamp != 0 && nextLimit.timestamp <= clock()) {
            limit.amount = nextLimit.amount;
            nextLimit.timestamp = 0;
            nextLimit.amount = 0;
        }
    }
}
