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

    uint48 private constant BUCKET_DURATION = 1 hours;

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
        (uint256 pendingWithdrawals,,,) = _previewWithdrawalTotals(Time.timestamp());
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
        uint256 claimableShares;
        uint48 now_ = Time.timestamp();
        uint256 length = queue.length();
        (,, uint256 claimableWithdrawals_, uint256 claimableWithdrawalShares_) = _previewWithdrawalTotals(now_);

        for (uint256 i; i < length; ++i) {
            uint256 packed = uint256(queue.at(i));
            (uint256 shares, uint48 unlockAt) = _unpackWithdrawal(packed);
            if (unlockAt <= now_) {
                claimableShares += shares;
            }
        }

        return ERC4626Math.previewRedeem(claimableShares, claimableWithdrawals_, claimableWithdrawalShares_);
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
            (uint256 pendingWithdrawals_, uint256 pendingWithdrawalShares_,,) = _previewWithdrawalTotals(now_);
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
     * @notice Claim all claimable collateral from the vault.
     * @param recipient account that receives the collateral
     * @return amount amount of the collateral claimed
     */
    function claim(address recipient) external nonReentrant returns (uint256 amount) {
        if (recipient == address(0)) {
            revert InvalidRecipient();
        }

        amount = _claim();

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
        }

        if (slashedAmount > 0) {
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

        uint256 length_ = _withdrawalBucketCumulativeShares.length;

        if (length_ == 0) {
            if (bucketIndex != 0) {
                revert InvalidTimestamp();
            }
            _withdrawalBucketCumulativeShares.push(mintedShares);
            return;
        }

        if (bucketIndex == length_ - 1) {
            _withdrawalBucketCumulativeShares[bucketIndex] += mintedShares;
            return;
        }

        if (bucketIndex == length_) {
            uint256 previous = _withdrawalBucketCumulativeShares[length_ - 1];
            _withdrawalBucketCumulativeShares.push(previous + mintedShares);
            return;
        }

        revert InvalidTimestamp();
    }

    function _bucketSharesBetween(uint256 fromIndex, uint256 toIndex) internal view returns (uint256) {
        if (fromIndex > toIndex) {
            return 0;
        }

        uint256 length_ = _withdrawalBucketCumulativeShares.length;
        if (length_ == 0 || fromIndex >= length_) {
            return 0;
        }

        if (toIndex >= length_) {
            revert InvalidTimestamp();
        }

        uint256 upper = _withdrawalBucketCumulativeShares[toIndex];
        uint256 lower = fromIndex == 0 ? 0 : _withdrawalBucketCumulativeShares[fromIndex - 1];
        return upper - lower;
    }

    function _bucketizeUnlock(uint48 unlockAt) internal pure returns (uint48) {
        uint256 unlockAt256 = unlockAt;
        uint256 bucket =
            (unlockAt256 + uint256(BUCKET_DURATION) - 1) / uint256(BUCKET_DURATION) * uint256(BUCKET_DURATION);
        if (bucket > type(uint48).max) {
            revert InvalidTimestamp();
        }
        return uint48(bucket);
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
        claimableWithdrawals = claimableWithdrawals + maturedAssets;
        claimableWithdrawalShares = claimableWithdrawalShares + maturedShares;

        _processedWithdrawalBucket = maturedIndex + 1;
    }

    function _previewWithdrawalTotals(uint48 now_)
        internal
        view
        returns (
            uint256 pendingWithdrawals_,
            uint256 pendingWithdrawalShares_,
            uint256 claimableWithdrawals_,
            uint256 claimableWithdrawalShares_
        )
    {
        pendingWithdrawals_ = withdrawals;
        pendingWithdrawalShares_ = withdrawalShares;
        claimableWithdrawals_ = claimableWithdrawals;
        claimableWithdrawalShares_ = claimableWithdrawalShares;

        (bool hasMatured, uint256 maturedIndex) = _lastMaturedBucket(now_);
        if (!hasMatured || maturedIndex < _processedWithdrawalBucket) {
            return (pendingWithdrawals_, pendingWithdrawalShares_, claimableWithdrawals_, claimableWithdrawalShares_);
        }

        uint256 maturedShares = _bucketSharesBetween(_processedWithdrawalBucket, maturedIndex);
        if (maturedShares > 0) {
            uint256 maturedAssets =
                ERC4626Math.previewRedeem(maturedShares, pendingWithdrawals_, pendingWithdrawalShares_);

            pendingWithdrawals_ -= maturedAssets;
            pendingWithdrawalShares_ -= maturedShares;
            claimableWithdrawals_ += maturedAssets;
            claimableWithdrawalShares_ += maturedShares;
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

        // Calculate unlock time bucket: now + withdrawalDelay, rounded up to the nearest hour bucket
        uint48 unlockAt = _bucketizeUnlock(now_ + withdrawalDelay);

        mintedShares = ERC4626Math.previewDeposit(withdrawnAssets, pendingWithdrawalShares_, pendingWithdrawals_);

        withdrawals = pendingWithdrawals_ + withdrawnAssets;
        withdrawalShares = pendingWithdrawalShares_ + mintedShares;

        uint256 bucketIndex = _bucketIndex(unlockAt);
        _recordWithdrawalShares(bucketIndex, mintedShares);

        uint256 packed = _packWithdrawal(mintedShares, unlockAt);
        _withdrawalEntries[claimer].pushBack(bytes32(packed));

        emit Withdraw(msg.sender, claimer, withdrawnAssets, burnedShares, mintedShares);
    }

    function _claim() internal returns (uint256 amount) {
        uint48 now_ = Time.timestamp();
        _processMaturedBuckets(now_);

        DoubleEndedQueue.Bytes32Deque storage queue = _withdrawalEntries[msg.sender];

        if (queue.empty()) {
            revert InsufficientClaim();
        }

        uint256 claimableShares;

        // Pop claimable withdrawals from the front of the queue
        // Since withdrawals are added in chronological order, we can pop until we find a non-claimable one
        while (!queue.empty()) {
            uint256 packed = uint256(queue.front());
            (uint256 shares, uint48 unlockAt) = _unpackWithdrawal(packed);

            if (unlockAt <= now_) {
                // This withdrawal is ready to claim - pop it from the queue
                claimableShares += shares;
                queue.popFront();
            } else {
                // Since withdrawals are in chronological order, all remaining are not claimable yet
                break;
            }
        }

        if (claimableShares == 0) {
            revert WithdrawalNotReady();
        }

        amount = ERC4626Math.previewRedeem(claimableShares, claimableWithdrawals, claimableWithdrawalShares);

        if (amount == 0) {
            revert InsufficientClaim();
        }

        // Update global pool after claiming
        claimableWithdrawals = claimableWithdrawals - amount;
        claimableWithdrawalShares = claimableWithdrawalShares - claimableShares;
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
