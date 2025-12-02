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
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

contract Vault is VaultStorage, MigratableEntity, AccessControlUpgradeable, IVault {
    using Checkpoints for Checkpoints.Trace256;
    using Math for uint256;
    using SafeCast for uint256;
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
        uint256[] storage entries = withdrawalEntries[account];
        uint256 claimableShares;
        uint48 now_ = Time.timestamp();
        uint256 length = entries.length;
        (, , uint256 claimableWithdrawals_, uint256 claimableWithdrawalShares_) = _previewWithdrawalTotals(now_);

        for (uint256 i; i < length; ++i) {
            (uint256 shares, uint48 unlockAt) = _unpackWithdrawal(entries[i]);
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

    function _updateWithdrawalQueue(uint48 now_)
        internal
        returns (uint256 pendingWithdrawals_, uint256 pendingWithdrawalShares_)
    {
        pendingWithdrawals_ = withdrawals;
        pendingWithdrawalShares_ = withdrawalShares;

        uint256 claimableWithdrawals_ = claimableWithdrawals;
        uint256 claimableWithdrawalShares_ = claimableWithdrawalShares;

        uint256 cursor = _withdrawalQueueCursor;
        uint256 length = _withdrawalQueue.length;

        while (cursor < length) {
            WithdrawalWindow storage window = _withdrawalQueue[cursor];
            if (window.unlockAt > now_) {
                break;
            }

            uint256 windowShares = window.shares;
            uint256 windowAssets =
                ERC4626Math.previewRedeem(windowShares, pendingWithdrawals_, pendingWithdrawalShares_);

            pendingWithdrawals_ -= windowAssets;
            pendingWithdrawalShares_ -= windowShares;
            claimableWithdrawals_ += windowAssets;
            claimableWithdrawalShares_ += windowShares;

            unchecked {
                ++cursor;
            }
        }

        if (cursor != _withdrawalQueueCursor) {
            withdrawals = pendingWithdrawals_;
            withdrawalShares = pendingWithdrawalShares_;
            claimableWithdrawals = claimableWithdrawals_;
            claimableWithdrawalShares = claimableWithdrawalShares_;
            _withdrawalQueueCursor = cursor;

            if (cursor == length && length > 0) {
                delete _withdrawalQueue;
                _withdrawalQueueCursor = 0;
            }
        }
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

        uint256 cursor = _withdrawalQueueCursor;
        uint256 length = _withdrawalQueue.length;

        while (cursor < length) {
            WithdrawalWindow storage window = _withdrawalQueue[cursor];
            if (window.unlockAt > now_) {
                break;
            }

            uint256 windowShares = window.shares;
            uint256 windowAssets =
                ERC4626Math.previewRedeem(windowShares, pendingWithdrawals_, pendingWithdrawalShares_);

            pendingWithdrawals_ -= windowAssets;
            pendingWithdrawalShares_ -= windowShares;
            claimableWithdrawals_ += windowAssets;
            claimableWithdrawalShares_ += windowShares;

            unchecked {
                ++cursor;
            }
        }
    }

    function _pushWithdrawalWindow(uint256 shares, uint48 unlockAt) internal {
        uint256 length = _withdrawalQueue.length;
        if (length > 0) {
            WithdrawalWindow storage last = _withdrawalQueue[length - 1];
            if (last.unlockAt == unlockAt) {
                last.shares += shares;
                return;
            }
        }
        _withdrawalQueue.push(WithdrawalWindow({unlockAt: unlockAt, shares: shares}));
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
        (uint256 pendingWithdrawals_, uint256 pendingWithdrawalShares_) = _updateWithdrawalQueue(now_);

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
            // Note: withdrawalShares are reduced proportionally when withdrawals are reduced
            // The exchange rate (withdrawals / withdrawalShares) should remain constant
            // So we reduce shares proportionally: withdrawalShares = withdrawalShares * (1 - withdrawalsSlashed / withdrawals)
            if (withdrawals > 0) {
                withdrawalShares =
                    pendingWithdrawalShares_.mulDiv(withdrawals, pendingWithdrawals_, Math.Rounding.Floor);
            } else {
                withdrawalShares = 0;
            }
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

    function _withdraw(address claimer, uint256 withdrawnAssets, uint256 burnedShares)
        internal
        virtual
        returns (uint256 mintedShares)
    {
        uint48 now_ = Time.timestamp();
        (uint256 pendingWithdrawals_, uint256 pendingWithdrawalShares_) = _updateWithdrawalQueue(now_);

        _activeSharesOf[msg.sender].push(now_, activeSharesOf(msg.sender) - burnedShares);
        _activeShares.push(now_, activeShares() - burnedShares);
        _activeStake.push(now_, activeStake() - withdrawnAssets);

        // Calculate unlock time: now + withdrawalDelay
        uint48 unlockAt = now_ + withdrawalDelay;

        mintedShares = ERC4626Math.previewDeposit(withdrawnAssets, pendingWithdrawalShares_, pendingWithdrawals_);

        withdrawals = pendingWithdrawals_ + withdrawnAssets;
        withdrawalShares = pendingWithdrawalShares_ + mintedShares;

        uint256 packed = _packWithdrawal(mintedShares, unlockAt);
        withdrawalEntries[claimer].push(packed);
        _pushWithdrawalWindow(mintedShares, unlockAt);

        emit Withdraw(msg.sender, claimer, withdrawnAssets, burnedShares, mintedShares);
    }

    function _claim() internal returns (uint256 amount) {
        uint48 now_ = Time.timestamp();
        _updateWithdrawalQueue(now_);

        uint256[] storage entries = withdrawalEntries[msg.sender];
        uint256 length = entries.length;
        if (length == 0) {
            revert InsufficientClaim();
        }

        uint256 claimableShares;
        uint256 writeIndex;

        // Iterate through all withdrawals and collect claimable ones
        for (uint256 i; i < length; ++i) {
            (uint256 shares, uint48 unlockAt) = _unpackWithdrawal(entries[i]);

            if (unlockAt <= now_) {
                // This withdrawal is ready to claim
                claimableShares += shares;
            } else {
                // This withdrawal is not ready yet, keep it in the array
                if (writeIndex != i) {
                    entries[writeIndex] = entries[i];
                }
                writeIndex++;
            }
        }

        if (claimableShares == 0) {
            revert WithdrawalNotReady();
        }

        // Remove claimed withdrawals by resizing the array
        // Pop elements from the end until we reach writeIndex
        while (entries.length > writeIndex) {
            entries.pop();
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
