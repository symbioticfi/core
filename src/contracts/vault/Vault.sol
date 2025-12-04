// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {MigratableEntity} from "../common/MigratableEntity.sol";
import {VaultStorage} from "./VaultStorage.sol";

import {Checkpoints} from "../libraries/Checkpoints.sol";
import {ERC4626Math} from "../libraries/ERC4626Math.sol";

import {IBaseDelegator} from "../../interfaces/delegator/IBaseDelegator.sol";
import {IBaseSlasher} from "../../interfaces/slasher/IBaseSlasher.sol";
import {IRegistry} from "../../interfaces/common/IRegistry.sol";
import {IVault} from "../../interfaces/vault/IVault.sol";

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract Vault is VaultStorage, MigratableEntity, AccessControlUpgradeable, IVault {
    using Checkpoints for Checkpoints.Trace256;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using Math for uint256;
    using SafeERC20 for IERC20;

    constructor(address delegatorFactory, address slasherFactory, address vaultFactory)
        VaultStorage(delegatorFactory, slasherFactory)
        MigratableEntity(vaultFactory)
    {}

    /**
     * @inheritdoc IVault
     */
    function isInitialized() external view returns (bool) {
        return isDelegatorInitialized && isSlasherInitialized;
    }

    /**
     * @inheritdoc IVault
     */
    function totalStake() public view returns (uint256) {
        (uint256 pendingWithdrawals,) = _previewWithdrawalTotals(Time.timestamp());
        // Total slashable stake = active stake + pending (non-claimable) withdrawals
        return activeStake() + pendingWithdrawals;
    }

    /**
     * @inheritdoc IVault
     */
    function activeBalanceOfAt(address account, uint48 timestamp, bytes calldata hints) public view returns (uint256) {
        ActiveBalanceOfHints memory activeBalanceOfHints;
        if (hints.length > 0) {
            activeBalanceOfHints = abi.decode(hints, (ActiveBalanceOfHints));
        }
        return ERC4626Math.previewRedeem(
            activeSharesOfAt(account, timestamp, activeBalanceOfHints.activeSharesOfHint),
            activeStakeAt(timestamp, activeBalanceOfHints.activeStakeHint),
            activeSharesAt(timestamp, activeBalanceOfHints.activeSharesHint)
        );
    }

    /**
     * @inheritdoc IVault
     */
    function activeBalanceOf(address account) public view returns (uint256) {
        return ERC4626Math.previewRedeem(activeSharesOf(account), activeStake(), activeShares());
    }

    /**
     * @notice Get claimable withdrawals for a particular account.
     * @param account account to get the withdrawals for
     * @return claimable withdrawals for the account
     */
    function withdrawalsOf(address account) public view returns (uint256) {
        DoubleEndedQueue.Bytes32Deque storage queue = _withdrawalEntries[account];
        uint256 totalAssets;
        uint48 now_ = Time.timestamp();
        uint256 length = queue.length();

        for (uint256 i; i < length; ++i) {
            uint256 packed = uint256(queue.at(i));
            (uint256 shares, uint48 unlockAt) = _unpackWithdrawal(packed);
            if (unlockAt <= now_) {
                // Calculate assets for this entry based on its bucket's conversion ratio
                uint256 bucketIndex = _bucketIndexFromUnlockAt(unlockAt);
                uint256 assetPerShare = _bucketAssetPerShare(bucketIndex);

                totalAssets += shares.mulDiv(assetPerShare, 1e18, Math.Rounding.Floor);
            }
        }

        return totalAssets;
    }

    /**
     * @inheritdoc IVault
     */
    function slashableBalanceOf(address account) external view returns (uint256) {
        uint256 total = activeBalanceOf(account);
        uint48 now_ = Time.timestamp();

        // Sum all slashable withdrawal shares (unlockAt > now)
        uint256 slashableShares = withdrawalSharesOf(account);

        if (slashableShares > 0) {
            (uint256 pendingWithdrawals_, uint256 pendingWithdrawalShares_) = _previewWithdrawalTotals(now_);
            total += ERC4626Math.previewRedeem(slashableShares, pendingWithdrawals_, pendingWithdrawalShares_);
        }

        return total;
    }

    /**
     * @inheritdoc IVault
     */
    function deposit(address onBehalfOf, uint256 amount)
        public
        virtual
        nonReentrant
        returns (uint256 depositedAmount, uint256 mintedShares)
    {
        if (onBehalfOf == address(0)) {
            revert InvalidOnBehalfOf();
        }

        if (depositWhitelist && !isDepositorWhitelisted[msg.sender]) {
            revert NotWhitelistedDepositor();
        }

        uint256 balanceBefore = IERC20(collateral).balanceOf(address(this));
        IERC20(collateral).safeTransferFrom(msg.sender, address(this), amount);
        depositedAmount = IERC20(collateral).balanceOf(address(this)) - balanceBefore;

        if (depositedAmount == 0) {
            revert InsufficientDeposit();
        }

        if (isDepositLimit && activeStake() + depositedAmount > depositLimit) {
            revert DepositLimitReached();
        }

        uint256 activeStake_ = activeStake();
        uint256 activeShares_ = activeShares();

        mintedShares = ERC4626Math.previewDeposit(depositedAmount, activeShares_, activeStake_);

        _activeStake.push(Time.timestamp(), activeStake_ + depositedAmount);
        _activeShares.push(Time.timestamp(), activeShares_ + mintedShares);
        _activeSharesOf[onBehalfOf].push(Time.timestamp(), activeSharesOf(onBehalfOf) + mintedShares);

        emit Deposit(msg.sender, onBehalfOf, depositedAmount, mintedShares);
    }

    /**
     * @inheritdoc IVault
     */
    function withdraw(address claimer, uint256 amount)
        external
        nonReentrant
        returns (uint256 burnedShares, uint256 mintedShares)
    {
        if (claimer == address(0)) {
            revert InvalidClaimer();
        }

        if (amount == 0) {
            revert InsufficientWithdrawal();
        }

        burnedShares = ERC4626Math.previewWithdraw(amount, activeShares(), activeStake());

        if (burnedShares > activeSharesOf(msg.sender)) {
            revert TooMuchWithdraw();
        }

        mintedShares = _withdraw(claimer, amount, burnedShares);
    }

    /**
     * @inheritdoc IVault
     */
    function redeem(address claimer, uint256 shares)
        external
        nonReentrant
        returns (uint256 withdrawnAssets, uint256 mintedShares)
    {
        if (claimer == address(0)) {
            revert InvalidClaimer();
        }

        if (shares > activeSharesOf(msg.sender)) {
            revert TooMuchRedeem();
        }

        withdrawnAssets = ERC4626Math.previewRedeem(shares, activeStake(), activeShares());

        if (withdrawnAssets == 0) {
            revert InsufficientRedemption();
        }

        mintedShares = _withdraw(claimer, withdrawnAssets, shares);
    }

    /**
     * @notice Claim collateral from the vault for a specific withdrawal index.
     * @param recipient account that receives the collateral
     * @param index index of the withdrawal entry to claim
     * @return amount amount of the collateral claimed
     */
    function claim(address recipient, uint256 index) external nonReentrant returns (uint256 amount) {
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }

        amount = _claimIndex(index);

        IERC20(collateral).safeTransfer(recipient, amount);

        emit Claim(msg.sender, recipient, amount);
    }

    /**
     * @notice Claim collateral from the vault for the first count claimable withdrawal entries.
     * @param recipient account that receives the collateral
     * @param count number of withdrawal entries to claim (from the front of the queue)
     * @return amount total amount of the collateral claimed
     */
    function claimBatch(address recipient, uint256 count) external nonReentrant returns (uint256 amount) {
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }

        amount = _claimBatch(count);

        IERC20(collateral).safeTransfer(recipient, amount);

        emit Claim(msg.sender, recipient, amount);
    }

    /**
     * @inheritdoc IVault
     */
    function onSlash(uint256 amount, uint48 captureTimestamp) external nonReentrant returns (uint256 slashedAmount) {
        if (msg.sender != slasher) {
            revert NotSlasher();
        }

        uint48 now_ = Time.timestamp();
        (uint256 pendingWithdrawals_,) = _processMaturedBuckets(now_);

        // Validate capture timestamp: must be within the slashing guarantee window
        // The guarantee window is: captureTimestamp to captureTimestamp + withdrawalDelay
        // We can only slash if the guarantee is still valid (now <= captureTimestamp + withdrawalDelay)
        if (captureTimestamp > now_ || now_ > captureTimestamp + withdrawalDelay) {
            revert InvalidCaptureEpoch();
        }

        uint256 activeStake_ = activeStake();

        // Calculate total slashable stake: active stake + pending withdrawals
        uint256 slashableStake = activeStake_ + pendingWithdrawals_;
        slashedAmount = Math.min(amount, slashableStake);

        if (slashedAmount > 0) {
            uint256 activeSlashed = slashedAmount.mulDiv(activeStake_, slashableStake);
            uint256 withdrawalsSlashed = slashedAmount - activeSlashed;

            _activeStake.push(now_, activeStake_ - activeSlashed);
            withdrawals = pendingWithdrawals_ - withdrawalsSlashed;

            IERC20(collateral).safeTransfer(burner, slashedAmount);
        }

        emit OnSlash(amount, captureTimestamp, slashedAmount);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositWhitelist(bool status) external nonReentrant onlyRole(DEPOSIT_WHITELIST_SET_ROLE) {
        if (depositWhitelist == status) {
            revert AlreadySet();
        }

        depositWhitelist = status;

        emit SetDepositWhitelist(status);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositorWhitelistStatus(address account, bool status)
        external
        nonReentrant
        onlyRole(DEPOSITOR_WHITELIST_ROLE)
    {
        if (account == address(0)) {
            revert InvalidAccount();
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
    function setIsDepositLimit(bool status) external nonReentrant onlyRole(IS_DEPOSIT_LIMIT_SET_ROLE) {
        if (isDepositLimit == status) {
            revert AlreadySet();
        }

        isDepositLimit = status;

        emit SetIsDepositLimit(status);
    }

    /**
     * @inheritdoc IVault
     */
    function setDepositLimit(uint256 limit) external nonReentrant onlyRole(DEPOSIT_LIMIT_SET_ROLE) {
        if (depositLimit == limit) {
            revert AlreadySet();
        }

        depositLimit = limit;

        emit SetDepositLimit(limit);
    }

    function setDelegator(address delegator_) external nonReentrant {
        if (isDelegatorInitialized) {
            revert DelegatorAlreadyInitialized();
        }

        if (!IRegistry(DELEGATOR_FACTORY).isEntity(delegator_)) {
            revert NotDelegator();
        }

        if (IBaseDelegator(delegator_).vault() != address(this)) {
            revert InvalidDelegator();
        }

        delegator = delegator_;

        isDelegatorInitialized = true;

        emit SetDelegator(delegator_);
    }

    function setSlasher(address slasher_) external nonReentrant {
        if (isSlasherInitialized) {
            revert SlasherAlreadyInitialized();
        }

        if (slasher_ != address(0)) {
            if (!IRegistry(SLASHER_FACTORY).isEntity(slasher_)) {
                revert NotSlasher();
            }

            if (IBaseSlasher(slasher_).vault() != address(this)) {
                revert InvalidSlasher();
            }

            slasher = slasher_;
        }

        isSlasherInitialized = true;

        emit SetSlasher(slasher_);
    }

    /**
     * @notice Get all withdrawal entries for a particular account.
     * @param account account to get the withdrawal entries for
     * @return array of packed withdrawal entries (shares << 48 | unlockAt)
     */
    function withdrawalEntries(address account) external view returns (uint256[] memory) {
        DoubleEndedQueue.Bytes32Deque storage queue = _withdrawalEntries[account];
        uint256 length = queue.length();
        uint256[] memory result = new uint256[](length);

        for (uint256 i; i < length; ++i) {
            result[i] = uint256(queue.at(i));
        }

        return result;
    }

    function _recordWithdrawalShares(uint256 bucketIndex, uint256 mintedShares) internal {
        if (mintedShares == 0) {
            return;
        }

        uint256 length_ = _withdrawalPrefixSum.length;

        if (length_ == 0) {
            if (bucketIndex != 0) {
                revert InvalidTimestamp();
            }
            _withdrawalPrefixSum.push(PrefixSum({cumulativeShares: mintedShares, cumulativeAssets: 0}));
            return;
        }

        if (bucketIndex == length_ - 1) {
            _withdrawalPrefixSum[bucketIndex].cumulativeShares += mintedShares;
            return;
        }

        if (bucketIndex == length_) {
            PrefixSum memory previous = _withdrawalPrefixSum[length_ - 1];
            _withdrawalPrefixSum.push(
                PrefixSum({
                    cumulativeShares: previous.cumulativeShares + mintedShares,
                    cumulativeAssets: previous.cumulativeAssets
                })
            );
            return;
        }

        revert InvalidTimestamp();
    }

    function _bucketSharesBetween(uint256 fromIndex, uint256 toIndex) internal view returns (uint256) {
        if (fromIndex > toIndex) {
            return 0;
        }

        uint256 length_ = _withdrawalPrefixSum.length;
        if (length_ == 0 || fromIndex >= length_) {
            return 0;
        }

        if (toIndex >= length_) {
            revert InvalidTimestamp();
        }

        uint256 upper = _withdrawalPrefixSum[toIndex].cumulativeShares;
        uint256 lower = fromIndex == 0 ? 0 : _withdrawalPrefixSum[fromIndex - 1].cumulativeShares;
        return upper - lower;
    }

    /**
     * @notice Get cumulative assets between two bucket indices.
     * @param fromIndex starting bucket index (inclusive)
     * @param toIndex ending bucket index (inclusive)
     * @return cumulative assets across buckets [fromIndex, toIndex]
     */
    function _bucketAssetsBetween(uint256 fromIndex, uint256 toIndex) internal view returns (uint256) {
        if (fromIndex > toIndex) {
            return 0;
        }

        uint256 length_ = _withdrawalPrefixSum.length;
        if (length_ == 0 || fromIndex >= length_) {
            return 0;
        }

        if (toIndex >= length_) {
            revert InvalidTimestamp();
        }

        uint256 upper = _withdrawalPrefixSum[toIndex].cumulativeAssets;
        uint256 lower = fromIndex == 0 ? 0 : _withdrawalPrefixSum[fromIndex - 1].cumulativeAssets;
        return upper - lower;
    }

    /**
     * @notice Get asset-per-share ratio for a specific bucket.
     * @param bucketIndex bucket index to get the ratio for
     * @return assetPerShare asset amount per share (scaled by 1e18), or 0 if bucket hasn't matured yet
     */
    function _bucketAssetPerShare(uint256 bucketIndex) internal view returns (uint256) {
        uint256 bucketShares = _bucketSharesBetween(bucketIndex, bucketIndex);
        if (bucketShares == 0) {
            return 0;
        }

        uint256 bucketAssets = _bucketAssetsBetween(bucketIndex, bucketIndex);
        if (bucketAssets == 0) {
            return 0;
        }

        return bucketAssets.mulDiv(1e18, bucketShares, Math.Rounding.Floor);
    }

    function _bucketIndex(uint48 unlockAt) internal returns (uint256 index) {
        (bool exists, uint48 lastKey, uint256 lastIndex) = _withdrawalBucketTrace.latestCheckpoint();
        if (!exists) {
            _withdrawalBucketTrace.push(unlockAt, 0);
            return 0;
        }

        if (unlockAt < lastKey) {
            revert InvalidTimestamp();
        }

        if (unlockAt == lastKey) {
            return lastIndex;
        }

        index = lastIndex + 1;
        _withdrawalBucketTrace.push(unlockAt, index);
    }

    function _lastMaturedBucket(uint48 now_) internal view returns (bool hasMatured, uint256 index) {
        (bool exists,,) = _withdrawalBucketTrace.latestCheckpoint();
        if (!exists) {
            return (false, 0);
        }

        Checkpoints.Checkpoint256 memory checkpoint = _withdrawalBucketTrace.at(uint32(_processedWithdrawalBucket));
        if (checkpoint._key > now_) {
            return (false, 0);
        }

        uint256 matureIndex = _withdrawalBucketTrace.upperLookupRecent(now_);
        return (true, matureIndex);
    }

    function _processMaturedBuckets(uint48 now_)
        internal
        returns (uint256 pendingWithdrawals_, uint256 pendingWithdrawalShares_)
    {
        pendingWithdrawals_ = withdrawals;
        pendingWithdrawalShares_ = withdrawalShares;

        (bool hasMatured, uint256 maturedIndex) = _lastMaturedBucket(now_);
        if (!hasMatured || maturedIndex < _processedWithdrawalBucket) {
            return (pendingWithdrawals_, pendingWithdrawalShares_);
        }

        uint256 maturedShares = _bucketSharesBetween(_processedWithdrawalBucket, maturedIndex);
        if (maturedShares == 0) {
            _processedWithdrawalBucket = maturedIndex + 1;
            return (pendingWithdrawals_, pendingWithdrawalShares_);
        }

        uint256 maturedAssets = ERC4626Math.previewRedeem(maturedShares, pendingWithdrawals_, pendingWithdrawalShares_);

        pendingWithdrawals_ -= maturedAssets;
        pendingWithdrawalShares_ -= maturedShares;

        withdrawals = pendingWithdrawals_;
        withdrawalShares = pendingWithdrawalShares_;

        // Store cumulative assets for each bucket in this range
        // This preserves the asset value at which shares in each bucket were converted
        // even if slashing occurs between different buckets maturing
        uint256 cumulativeAssetsBefore =
            _processedWithdrawalBucket == 0 ? 0 : _withdrawalPrefixSum[_processedWithdrawalBucket - 1].cumulativeAssets;

        for (uint256 i = _processedWithdrawalBucket; i <= maturedIndex; ++i) {
            // Calculate assets for this bucket proportionally
            uint256 bucketAssets = maturedAssets.mulDiv(_bucketSharesBetween(i, i), maturedShares, Math.Rounding.Floor);
            cumulativeAssetsBefore += bucketAssets;
            _withdrawalPrefixSum[i].cumulativeAssets = cumulativeAssetsBefore;
        }

        _processedWithdrawalBucket = maturedIndex + 1;
    }

    function _previewWithdrawalTotals(uint48 now_)
        internal
        view
        returns (uint256 pendingWithdrawals_, uint256 pendingWithdrawalShares_)
    {
        pendingWithdrawals_ = withdrawals;
        pendingWithdrawalShares_ = withdrawalShares;

        (bool hasMatured, uint256 maturedIndex) = _lastMaturedBucket(now_);
        if (!hasMatured || maturedIndex < _processedWithdrawalBucket) {
            return (pendingWithdrawals_, pendingWithdrawalShares_);
        }

        uint256 maturedShares = _bucketSharesBetween(_processedWithdrawalBucket, maturedIndex);
        if (maturedShares > 0) {
            uint256 maturedAssets =
                ERC4626Math.previewRedeem(maturedShares, pendingWithdrawals_, pendingWithdrawalShares_);

            pendingWithdrawals_ -= maturedAssets;
            pendingWithdrawalShares_ -= maturedShares;
        }
    }

    function _withdraw(address claimer, uint256 withdrawnAssets, uint256 burnedShares)
        internal
        virtual
        returns (uint256 mintedShares)
    {
        uint48 now_ = Time.timestamp();
        (uint256 pendingWithdrawals_, uint256 pendingWithdrawalShares_) = _processMaturedBuckets(now_);

        _activeSharesOf[msg.sender].push(now_, activeSharesOf(msg.sender) - burnedShares);
        _activeShares.push(now_, activeShares() - burnedShares);
        _activeStake.push(now_, activeStake() - withdrawnAssets);

        // Calculate unlock time: now + withdrawalDelay
        uint48 unlockAt = now_ + withdrawalDelay;

        mintedShares = ERC4626Math.previewDeposit(withdrawnAssets, pendingWithdrawalShares_, pendingWithdrawals_);

        withdrawals = pendingWithdrawals_ + withdrawnAssets;
        withdrawalShares = pendingWithdrawalShares_ + mintedShares;

        uint256 bucketIndex = _bucketIndex(unlockAt);
        _recordWithdrawalShares(bucketIndex, mintedShares);

        uint256 packed = _packWithdrawal(mintedShares, unlockAt);
        _withdrawalEntries[claimer].pushBack(bytes32(packed));

        emit Withdraw(msg.sender, claimer, withdrawnAssets, burnedShares, mintedShares);
    }

    /**
     * @notice Claim a specific withdrawal entry by index.
     * @param index index of the withdrawal entry to claim
     * @return amount amount of the collateral claimed
     */
    function _claimIndex(uint256 index) internal returns (uint256 amount) {
        uint48 now_ = Time.timestamp();
        _processMaturedBuckets(now_);

        DoubleEndedQueue.Bytes32Deque storage queue = _withdrawalEntries[msg.sender];

        if (queue.length() <= index) {
            revert InsufficientClaim();
        }

        // Get the entry at the specified index
        uint256 packed = uint256(queue.at(index));
        (uint256 shares, uint48 unlockAt) = _unpackWithdrawal(packed);

        // Check if the withdrawal is ready to claim
        if (unlockAt > now_) {
            revert WithdrawalNotReady();
        }

        // Calculate assets for this entry based on its bucket's conversion ratio
        uint256 bucketIndex = _bucketIndexFromUnlockAt(unlockAt);
        uint256 assetPerShare = _bucketAssetPerShare(bucketIndex);

        // Use the stored asset-per-share ratio for this bucket
        amount = shares.mulDiv(assetPerShare, 1e18, Math.Rounding.Floor);

        if (amount == 0) {
            revert InsufficientClaim();
        }

        // Remove the element at the specified index from the queue
        // We do this by popping elements before the index, popping the target, then pushing back
        uint256[] memory temp = new uint256[](index);
        for (uint256 i; i < index; ++i) {
            temp[i] = uint256(queue.popFront());
        }

        // Pop the target element (already validated above)
        queue.popFront();

        // Push back all the elements that were before the target
        for (uint256 i; i < index; ++i) {
            queue.pushFront(bytes32(temp[index - 1 - i]));
        }
    }

    /**
     * @notice Claim the first count claimable withdrawal entries.
     * @param count number of withdrawal entries to claim (from the front of the queue)
     * @return amount total amount of the collateral claimed
     */
    function _claimBatch(uint256 count) internal returns (uint256 amount) {
        if (count == 0) {
            revert InsufficientClaim();
        }

        uint48 now_ = Time.timestamp();
        _processMaturedBuckets(now_);

        DoubleEndedQueue.Bytes32Deque storage queue = _withdrawalEntries[msg.sender];

        if (queue.empty()) {
            revert InsufficientClaim();
        }

        uint256 claimableShares;
        uint256 claimedCount = 0;

        // Pop claimable withdrawals from the front of the queue
        // Since withdrawals are added in chronological order, we can pop until we find a non-claimable one
        while (!queue.empty() && claimedCount < count) {
            uint256 packed = uint256(queue.front());
            (uint256 shares, uint48 unlockAt) = _unpackWithdrawal(packed);

            if (unlockAt <= now_) {
                // This withdrawal is ready to claim
                claimableShares += shares;

                // Calculate assets for this entry based on its bucket's conversion ratio
                uint256 bucketIndex = _bucketIndexFromUnlockAt(unlockAt);
                uint256 assetPerShare = _bucketAssetPerShare(bucketIndex);

                // Use the stored asset-per-share ratio for this bucket
                amount += shares.mulDiv(assetPerShare, 1e18, Math.Rounding.Floor);

                queue.popFront();
                claimedCount++;
            } else {
                // Since withdrawals are in chronological order, all remaining are not claimable yet
                break;
            }
        }

        if (claimedCount == 0) {
            revert WithdrawalNotReady();
        }

        if (amount == 0) {
            revert InsufficientClaim();
        }
    }

    /**
     * @notice Get bucket index from unlock timestamp.
     * @param unlockAt unlock timestamp
     * @return bucket index for the given unlock timestamp
     */
    function _bucketIndexFromUnlockAt(uint48 unlockAt) internal view returns (uint256) {
        // Use the timestamp directly as the bucket timestamp (1 second per bucket)
        uint48 bucketTimestamp = unlockAt;

        // Find the bucket index in the trace
        (bool exists, uint48 lastKey, uint256 lastIndex) = _withdrawalBucketTrace.latestCheckpoint();
        if (!exists) {
            return 0;
        }

        if (bucketTimestamp < lastKey) {
            // Bucket is in the past, use upperLookupRecent to find it
            return _withdrawalBucketTrace.upperLookupRecent(bucketTimestamp);
        } else if (bucketTimestamp == lastKey) {
            return lastIndex;
        } else {
            // Bucket is in the future, return the next index (but this shouldn't happen for claimable entries)
            return lastIndex + 1;
        }
    }

    function _initialize(uint64, address, bytes memory data) internal virtual override {
        (InitParams memory params) = abi.decode(data, (InitParams));

        if (params.collateral == address(0)) {
            revert InvalidCollateral();
        }

        if (params.withdrawalDelay == 0) {
            revert InvalidEpochDuration();
        }

        if (params.defaultAdminRoleHolder == address(0)) {
            if (params.depositWhitelistSetRoleHolder == address(0)) {
                if (params.depositWhitelist) {
                    if (params.depositorWhitelistRoleHolder == address(0)) {
                        revert MissingRoles();
                    }
                } else if (params.depositorWhitelistRoleHolder != address(0)) {
                    revert MissingRoles();
                }
            }

            if (params.isDepositLimitSetRoleHolder == address(0)) {
                if (params.isDepositLimit) {
                    if (params.depositLimit == 0 && params.depositLimitSetRoleHolder == address(0)) {
                        revert MissingRoles();
                    }
                } else if (params.depositLimit != 0 || params.depositLimitSetRoleHolder != address(0)) {
                    revert MissingRoles();
                }
            }
        }

        collateral = params.collateral;

        burner = params.burner;

        withdrawalDelay = params.withdrawalDelay;

        depositWhitelist = params.depositWhitelist;

        isDepositLimit = params.isDepositLimit;
        depositLimit = params.depositLimit;

        if (params.defaultAdminRoleHolder != address(0)) {
            _grantRole(DEFAULT_ADMIN_ROLE, params.defaultAdminRoleHolder);
        }
        if (params.depositWhitelistSetRoleHolder != address(0)) {
            _grantRole(DEPOSIT_WHITELIST_SET_ROLE, params.depositWhitelistSetRoleHolder);
        }
        if (params.depositorWhitelistRoleHolder != address(0)) {
            _grantRole(DEPOSITOR_WHITELIST_ROLE, params.depositorWhitelistRoleHolder);
        }
        if (params.isDepositLimitSetRoleHolder != address(0)) {
            _grantRole(IS_DEPOSIT_LIMIT_SET_ROLE, params.isDepositLimitSetRoleHolder);
        }
        if (params.depositLimitSetRoleHolder != address(0)) {
            _grantRole(DEPOSIT_LIMIT_SET_ROLE, params.depositLimitSetRoleHolder);
        }
    }

    function _migrate(
        uint64,
        /* oldVersion */
        uint64,
        /* newVersion */
        bytes calldata /* data */
    )
        internal
        override
    {
        revert();
    }
}
